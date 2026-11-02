# frozen_string_literal: true

require 'adwaita'

# EditorSearchModel finds every occurrence of the search text in a document,
# highlights them, and walks between them.
#
# Ported from upstream's src/editor-search-model.c together with the search
# context it drives. Upstream's model is a GListModel of GtkSourceSearchContext
# matches, fed by GtkSourceSearchSettings — regular expressions, case
# sensitivity and whole-word matching all come out of GtkSourceView. There is
# no GtkSourceView here, so the match list is computed with Ruby's own regular
# expressions over the buffer's text and the highlighting is done with two
# GtkTextTags, one for every match and one for the current one. The semantics
# that matter are kept: the occurrence count, the one-based position of the
# current match, and wrapping at both ends.
class EditorSearchModel
  MATCH_TAG = 'editor-search-match'
  CURRENT_TAG = 'editor-search-current'

  def initialize(document, &on_changed)
    @document = document
    @on_changed = on_changed
    @search_text = ''
    @regex_enabled = false
    @case_sensitive = false
    @match_whole_word = false
    @matches = []
    @position = 0
    install_tags
  end

  attr_reader :document, :search_text, :matches

  def regex_enabled? = @regex_enabled
  def case_sensitive? = @case_sensitive
  def match_whole_word? = @match_whole_word

  def search_text=(text)
    @search_text = text.to_s
    reload
  end

  def regex_enabled=(value)
    @regex_enabled = value
    reload
  end

  def case_sensitive=(value)
    @case_sensitive = value
    reload
  end

  def match_whole_word=(value)
    @match_whole_word = value
    reload
  end

  def occurrence_count = @matches.length

  # One-based, or 0 when the cursor is not sitting on a match — which is what
  # upstream's "%u of %u" label shows.
  def occurrence_position = @position

  def can_move? = @matches.any?

  # Recomputes the matches and repaints the highlight. Called whenever the text
  # or an option changes, and after every edit the replace actions make.
  def reload
    tap do
      if @search_text.empty?
        @matches = []
      else
        @matches = find_matches
      end
      @position = position_at_cursor
      highlight
      @on_changed&.call(self)
    end
  end

  # Moves to the match after the cursor, wrapping to the first. Returns the
  # match it landed on, or nil when there is nothing to move to.
  def move_next
    @matches.find { |(from, _to)| from > cursor_offset }.then do |match|
      select(match || @matches.first)
    end
  end

  # Moves to the match before the selection, wrapping to the last.
  def move_previous
    @matches.reverse.find { |(from, _to)| from < selection_start_offset }.then do |match|
      select(match || @matches.last)
    end
  end

  def move_first = select(@matches.first)

  # True when the selection is exactly a match, which is what enables the
  # Replace button.
  def can_replace?
    current_match.then { |match| !match.nil? }
  end

  def can_replace_all? = @matches.any?

  # Replaces the match the selection is sitting on. The replacement honours
  # backreferences when the search is a regular expression, as upstream's
  # GtkSourceSearchContext does.
  def replace(replacement)
    current_match&.then do |(from, to)|
      @document.begin_user_action
      @document.delete(iter_at(from), iter_at(to))
      @document.insert(iter_at(from), expand_replacement(replacement, from, to))
      @document.end_user_action
      reload
    end
  end

  # Replaces every match in one undoable step.
  def replace_all(replacement)
    if @matches.any?
      @document.begin_user_action
      @matches.reverse.each do |(from, to)|
        expand_replacement(replacement, from, to).then do |text|
          @document.delete(iter_at(from), iter_at(to))
          @document.insert(iter_at(from), text)
        end
      end
      @document.end_user_action
      reload
    end
  end

  # Drops the highlight, which the page does when the search bar hides.
  def clear
    tap do
      @matches = []
      @position = 0
      remove_tags
      @on_changed&.call(self)
    end
  end

  private

    # Match highlighting and current-match highlighting are tags on the
    # buffer, created once per document.
    def install_tags
      @match_tag = @document.tag_table.lookup(MATCH_TAG) ||
                   @document.create_tag(MATCH_TAG, background: '#f8e45c', foreground: '#000000')
      @current_tag = @document.tag_table.lookup(CURRENT_TAG) ||
                     @document.create_tag(CURRENT_TAG, background: '#ff7800', foreground: '#000000')
    end

    def text = @document.text

    # nil when the pattern itself is invalid, which is how a half-typed
    # regular expression leaves the previous highlight alone rather than
    # raising.
    def pattern
      Regexp.new(
        @regex_enabled ? @search_text : word_bounded(Regexp.escape(@search_text)),
        @case_sensitive ? 0 : Regexp::IGNORECASE,
      )
    rescue RegexpError
      nil
    end

    def word_bounded(escaped) = @match_whole_word ? "\\b#{escaped}\\b" : escaped

    # Offsets, not iterators: iterators do not survive the edits the replace
    # actions make, and the buffer's text is indexed in characters just as
    # GtkTextIter offsets are.
    def find_matches
      pattern.then do |regexp|
        if regexp.nil?
          next @matches
        end

        [].tap do |found|
          offset = 0

          while (match = regexp.match(text, offset))
            if match.end(0) == match.begin(0) && match.begin(0) >= text.length
              break
            end

            found << [match.begin(0), match.end(0)]
            if match.end(0) > match.begin(0)
              offset = match.end(0)
            else
              offset = match.begin(0) + 1
            end
          end
        end
      end
    end

    def highlight
      tap do
        remove_tags
        @matches.each { |(from, to)| @document.apply_tag(@match_tag, iter_at(from), iter_at(to)) }
        current_match&.then { |(from, to)| @document.apply_tag(@current_tag, iter_at(from), iter_at(to)) }
      end
    end

    def remove_tags
      @document.bounds.then do |(from, to)|
        @document.remove_tag(@match_tag, from, to)
        @document.remove_tag(@current_tag, from, to)
      end
    end

    def select(match)
      match&.tap do |(from, to)|
        @document.select_range(iter_at(from), iter_at(to))
        @position = @matches.index(match) + 1
        highlight
        @on_changed&.call(self)
      end
    end

    def current_match
      selection_offsets.then do |(from, to)|
        from == to ? nil : @matches.find { |match| match == [from, to] }
      end
    end

    def position_at_cursor
      current_match.then { |match| match ? @matches.index(match) + 1 : 0 }
    end

    def selection_offsets
      (@document.selection_bounds || [cursor_iter, cursor_iter]).then do |(from, to)|
        [from.offset, to.offset].sort
      end
    end

    def selection_start_offset = selection_offsets.first

    def cursor_offset = cursor_iter.offset

    def cursor_iter = @document.get_iter_at(offset: @document.cursor_position)

    def iter_at(offset) = @document.get_iter_at(offset: offset)

    # "\1" and "\\1" in a replacement refer to the groups of a regular
    # expression search; a literal search replaces literally.
    def expand_replacement(replacement, from, to)
      if @regex_enabled
        pattern.then do |regexp|
          regexp&.match(@document.get_text(iter_at(from), iter_at(to), true))
                 &.then { |match| replacement.gsub(/\\(\d)/) { match[Regexp.last_match(1).to_i].to_s } } || replacement
        end
      else
        replacement
      end
    end
end
