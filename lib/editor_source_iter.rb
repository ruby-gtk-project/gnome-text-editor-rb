# frozen_string_literal: true

require 'adwaita'

# EditorSourceIter is the editor's own definition of a word: the boundaries
# the word-wise movement, deletion and double-click selection use, which are
# wider than Pango's (the underscore counts as a word character) and narrower
# than Vim's (a run of punctuation is a word of its own).
#
# Ported from upstream's src/editor-source-iter.c, which upstream in turn took
# from GtkSourceView. Upstream's functions take a GtkTextIter in and move it in
# place; the Ruby bindings hand out a mutable Gtk::TextIter too, but a method
# that quietly moved its argument would be a trap, so every function here
# copies what it is given and returns the new position. Upstream's
# gboolean-returning movers additionally say whether they moved, which the
# counted variants need; that pair is #advance_word_end and
# #retreat_word_start, and the plain movers wrap them.
module EditorSourceIter
  module_function

  # Go to the end of the next or current "full word" — a group of non-blank
  # characters. Upstream's _editor_source_iter_forward_full_word_end, the 'E'
  # Vim command.
  def forward_full_word_end(iter)
    pos = iter.copy
    non_blank_found = false

    while space?(pos)
      unless pos.forward_char
        break
      end
    end

    while !pos.end? && !space?(pos)
      non_blank_found = true

      unless pos.forward_char
        break
      end
    end

    if non_blank_found
      pos
    else
      iter.copy
    end
  end

  # The symmetric move: the start of the previous or current full word.
  def backward_full_word_start(iter)
    pos = iter.copy
    non_blank_found = false

    until pos.start?
      prev = pos.copy

      unless prev.backward_char
        break
      end

      unless space?(prev)
        break
      end

      pos = prev
    end

    until pos.start?
      prev = pos.copy

      unless prev.backward_char
        break
      end

      if space?(prev)
        break
      end

      non_blank_found = true
      pos = prev
    end

    if non_blank_found
      pos
    else
      iter.copy
    end
  end

  def starts_full_word?(iter)
    if iter.end?
      false
    else
      iter.copy.then do |prev|
        if prev.backward_visible_cursor_position
          space?(prev) && !space?(iter)
        else
          !space?(iter)
        end
      end
    end
  end

  def ends_full_word?(iter)
    iter.copy.then do |prev|
      if prev.backward_visible_cursor_position
        !space?(prev) && (iter.end? || space?(iter))
      else
        false
      end
    end
  end

  # Pango's natural-language word, plus the underscore, which programming
  # languages use inside identifiers.
  def forward_extra_natural_word_end(iter)
    next_word_end = iter.copy
    limit = nil

    if next_word_end.forward_visible_word_end
      limit = next_word_end
    end

    pos = forward_underscore_end(iter, limit) || next_word_end

    loop do
      if underscore?(pos)
        unless pos.forward_visible_cursor_position
          break
        end
      elsif pos.starts_word
        unless pos.forward_visible_word_end
          break
        end
      else
        break
      end
    end

    pos
  end

  # The symmetric move.
  def backward_extra_natural_word_start(iter)
    prev_word_start = iter.copy
    limit = nil

    if prev_word_start.backward_visible_word_start
      limit = prev_word_start
    end

    pos = backward_underscore_start(iter, limit) || prev_word_start

    until pos.start?
      prev = pos.copy

      unless prev.backward_visible_cursor_position
        break
      end

      if underscore?(prev)
        pos = prev
      elsif pos.ends_word
        unless pos.backward_visible_word_start
          break
        end
      else
        break
      end
    end

    pos
  end

  def starts_extra_natural_word?(iter, visible: true)
    iter.copy.then do |prev|
      if backward_cursor_position(prev, visible)
        if iter.starts_word
          !underscore?(prev)
        else
          underscore?(iter) && !underscore?(prev) && !iter.ends_word
        end
      else
        iter.starts_word || underscore?(iter)
      end
    end
  end

  def ends_extra_natural_word?(iter, visible: true)
    iter.copy.then do |prev|
      if backward_cursor_position(prev, visible)
        if iter.end?
          iter.ends_word || underscore?(prev)
        elsif iter.ends_word
          !underscore?(iter)
        else
          underscore?(prev) && !underscore?(iter) && !iter.starts_word
        end
      else
        false
      end
    end
  end

  # The end of the next word, by the editor's definition: upstream's
  # _editor_source_iter_forward_visible_word_end, the 'e' Vim command. Returns
  # the new position and whether it moved anywhere short of the end of the
  # buffer, which is what the counted version needs.
  def advance_word_end(iter)
    farthest = forward_full_word_end(iter)
    next_word_end = forward_extra_natural_word_end(iter)
    result = nil

    if farthest.compare(next_word_end).negative? || same?(iter, next_word_end)
      result = farthest
    else
      word_start = backward_extra_natural_word_start(next_word_end)

      if word_start.compare(iter) <= 0
        result = next_word_end
      elsif starts_full_word?(word_start)
        result = next_word_end
      else
        result = word_start
      end
    end

    [result, !same?(result, iter) && !result.end?]
  end

  # The symmetric move.
  def retreat_word_start(iter)
    farthest = backward_full_word_start(iter)
    prev_word_start = backward_extra_natural_word_start(iter)
    result = nil

    if prev_word_start.compare(farthest).negative? || same?(iter, prev_word_start)
      result = farthest
    else
      word_end = forward_extra_natural_word_end(prev_word_start)

      if iter.compare(word_end) <= 0
        result = prev_word_start
      elsif ends_full_word?(word_end)
        result = prev_word_start
      else
        result = word_end
      end
    end

    [result, !same?(result, iter) && !result.end?]
  end

  def forward_visible_word_end(iter) = advance_word_end(iter).first

  def backward_visible_word_start(iter) = retreat_word_start(iter).first

  # A negative count moves the other way, as upstream's counted movers do.
  def forward_visible_word_ends(iter, count)
    if count.negative?
      backward_visible_word_starts(iter, -count)
    else
      pos = iter.copy
      moving = true

      count.times do
        if moving
          stepped = advance_word_end(pos)
          pos = stepped.first
          moving = stepped.last
        end
      end

      pos
    end
  end

  def backward_visible_word_starts(iter, count)
    if count.negative?
      forward_visible_word_ends(iter, -count)
    else
      pos = iter.copy
      moving = true

      count.times do
        if moving
          stepped = retreat_word_start(pos)
          pos = stepped.first
          moving = stepped.last
        end
      end

      pos
    end
  end

  def starts_word?(iter)
    if starts_full_word?(iter) || starts_extra_natural_word?(iter)
      true
    else
      # "abcd|()", at the start of the word "()".
      !ends_full_word?(iter) && ends_extra_natural_word?(iter)
    end
  end

  def ends_word?(iter)
    if ends_full_word?(iter) || ends_extra_natural_word?(iter)
      true
    else
      # "abcd()|efgh", at the end of the word "()".
      !starts_full_word?(iter) && starts_extra_natural_word?(iter)
    end
  end

  # Upstream short-circuits this on the character under the iter to stay fast
  # on minified text; it reads that character twice rather than reading the
  # previous one, so the short circuit comes to "a word character under the
  # iter is inside a word", and this port keeps that behaviour.
  def inside_word?(iter)
    if word_char?(iter)
      true
    elsif starts_word?(iter)
      true
    else
      retreat_word_start(iter).then do |(prev_word_start, moved)|
        if moved
          forward_visible_word_end(prev_word_start).then do |word_end|
            prev_word_start.compare(iter) <= 0 && iter.compare(word_end).negative?
          end
        else
          false
        end
      end
    end
  end

  # The bounds a double-click selects: GTK's own algorithm over the editor's
  # word boundaries. Returns the pair [start, end].
  def extend_selection_word(location)
    start_iter = location.copy
    end_iter = location.copy

    if inside_word?(start_iter)
      unless starts_word?(start_iter)
        start_iter = backward_visible_word_start(start_iter)
      end

      unless ends_word?(end_iter)
        end_iter = forward_visible_word_end(end_iter)
      end
    else
      start_iter = selection_start_outside_word(start_iter)
      end_iter = selection_end_outside_word(end_iter)
    end

    [start_iter, end_iter]
  end

  # The boundary on the iter's line between the indentation and the text.
  def leading_spaces_end_boundary(iter)
    iter.copy.tap do |leading_end|
      leading_end.line_offset = 0

      until leading_end.ends_line
        unless space?(leading_end)
          break
        end

        leading_end.forward_char
      end
    end
  end

  # The boundary on the iter's line between the text and its trailing spaces.
  def trailing_spaces_start_boundary(iter)
    trailing_start = iter.copy

    unless trailing_start.ends_line
      trailing_start.forward_to_line_end
    end

    until trailing_start.starts_line
      prev = trailing_start.copy
      prev.backward_char

      unless space?(prev)
        break
      end

      trailing_start = prev
    end

    trailing_start
  end

  # The start of a double-click selection that landed between words: the end
  # of the previous word when it is on the same line, the start of the line
  # otherwise.
  def selection_start_outside_word(start_iter)
    retreat_word_start(start_iter).then do |(candidate, moved)|
      if moved
        forward_visible_word_end(candidate)
      else
        candidate
      end
    end.then do |candidate|
      if candidate.line == start_iter.line
        candidate
      else
        start_iter.copy.tap { |at_line_start| at_line_start.line_offset = 0 }
      end
    end
  end

  # The end of such a selection: the start of the next word when it is on the
  # same line, the end of the line otherwise.
  def selection_end_outside_word(end_iter)
    advance_word_end(end_iter).then do |(candidate, moved)|
      unless moved
        candidate = end_iter.copy.tap(&:forward_to_end)
      end

      if ends_word?(candidate)
        candidate = backward_visible_word_start(candidate)
      end

      candidate
    end.then do |candidate|
      if candidate.line == end_iter.line
        candidate
      else
        end_iter.copy.tap(&:forward_to_line_end)
      end
    end
  end

  # The character under an iter, as a one-character string; the empty string
  # at the end of the buffer, where GTK reports no character at all.
  def char_at(iter) = iter.char.to_s

  def space?(iter) = char_at(iter).match?(/\A\s\z/)

  def underscore?(iter) = char_at(iter) == '_'

  def word_char?(iter) = char_at(iter).match?(/\A[[:alnum:]_]\z/)

  def same?(one, other) = one.compare(other).zero?

  def backward_cursor_position(iter, visible)
    if visible
      iter.backward_visible_cursor_position
    else
      iter.backward_cursor_position
    end
  end

  # Scans forward for an underscore, stopping at the limit, and answers with
  # the position just after it — upstream searches for "_" with
  # gtk_text_iter_forward_search bounded the same way.
  def forward_underscore_end(iter, limit)
    pos = iter.copy
    found = nil

    while !pos.end? && (limit.nil? || pos.compare(limit).negative?)
      if underscore?(pos)
        pos.forward_char
        found = pos
        break
      end

      unless pos.forward_char
        break
      end
    end

    found
  end

  # The symmetric search: the position of the previous underscore.
  def backward_underscore_start(iter, limit)
    pos = iter.copy
    found = nil

    until pos.start?
      if limit && pos.compare(limit) <= 0
        break
      end

      unless pos.backward_char
        break
      end

      if underscore?(pos)
        found = pos
        break
      end
    end

    found
  end
end
