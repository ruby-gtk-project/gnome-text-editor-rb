# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_path'
require_relative 'editor_utils'

# EditorSidebarItem is one row's worth of data in the recent-documents list:
# a file, an open page, or a draft that is neither.
#
# Ported from upstream's src/editor-sidebar-item.c. Upstream notifies the row
# through GObject properties and queries the file's modification time in an
# async batch; this port exposes plain accessors and takes the age from the
# query the model already performs, because the model is what knows when a row
# is new.
class EditorSidebarItem
  DRAFT_SUBTITLE = 'Draft'
  UNTITLED = 'New Document'
  PORTAL_PREFIX = '/run/user'
  PORTAL_SEGMENT = 'doc'

  def initialize(file: nil, page: nil, draft_id: nil, title: nil, age: nil)
    @file = file
    @draft_id = draft_id
    @title = title
    @age = age
    @is_modified_set = false
    @is_modified = false
    self.page = page
  end

  attr_reader :file, :page, :draft_id, :age

  def draft_id=(draft_id)
    @draft_id = draft_id
  end

  def age=(age)
    @age = age
  end

  def title=(title)
    @title = title
  end

  # Adopting a page makes the row live: the title and the modified dot now
  # follow the open document rather than the recorded values.
  def page=(page)
    @page = page

    @page&.then do |live|
      @draft_id = live.document.draft_id
      @is_modified_set = true
      @is_modified = live.modified?
    end
  end

  # Upstream's rule: a row with neither a page nor a file is a draft, and a
  # draft is always "modified" because its text exists nowhere else.
  def is_modified?
    if @is_modified_set && @is_modified
      true
    else
      if @page.nil? && @file.nil?
        true
      else
        @page ? @page.modified? : false
      end
    end
  end

  # The row's dot is hidden when the item is an empty, unmodified draft.
  def empty? = @file.nil? && @page.nil? && !is_modified?

  def title
    if @title
      @title
    else
      if @page
        @page.title
      else
        if @file.nil?
          UNTITLED
        else
          File.basename(@file.parse_name)
        end
      end
    end
  end

  # The directory the file lives in, collapsed to "~/…"; portal-exported files
  # show their host path, and a draft just says "Draft".
  def subtitle
    if @file.nil?
      DRAFT_SUBTITLE
    else
      @file.parent.then do |directory|
        if directory.nil?
          ''
        elsif from_document_portal?(directory)
          EditorPath.portal_host_path(directory)
        elsif directory.native?
          EditorPath.collapse(directory.path)
        else
          directory.uri
        end
      end
    end
  end

  # "Just now", "Yesterday", a weekday — the relative age shown at the row's
  # right edge.
  def age_label = @age ? EditorUtils.date_time_format(@age) : ''

  def uri = @file&.uri

  # Raises the page if the document is already open, and otherwise asks the
  # session to open the file or the draft.
  def open(session, window)
    if @page
      @page.raise_page
    elsif @file
      session.open(window, @file)
    elsif @draft_id
      session.open_draft(window, @draft_id)
    end
  end

  # Upstream scores a prefix match 0, a substring match 1 and a fuzzy match
  # 2 or more, so exact-ish matches float to the top of the search. The fuzzy
  # pass is GtkSourceView's; this port scores it by how far apart the matched
  # characters ended up, which orders results the same way.
  def match(search)
    if search.nil? || search.empty?
      [true, 0]
    else
      keywords.filter_map { |keyword| score(keyword, search) }.min.then do |best|
        best ? [true, best] : [false, nil]
      end
    end
  end

  # More recent first, which is what the recents list sorts by.
  def self.compare(a, b) = (b.age || Time.at(0)) <=> (a.age || Time.at(0))

  private

    def keywords = [title.downcase, subtitle.downcase]

    def score(keyword, search)
      if keyword.start_with?(search)
        0
      elsif keyword.include?(search)
        1
      else
        fuzzy_score(keyword, search)
      end
    end

    # Walks the needle through the haystack in order, counting the characters
    # skipped; nil when a character cannot be found at all.
    def fuzzy_score(keyword, search)
      offset = 0
      penalty = 0

      search.each_char do |char|
        keyword.index(char, offset).then do |found|
          if found
            penalty += found - offset
            offset = found + 1
          else
            penalty = nil
          end
        end

        if penalty.nil?
          break
        end
      end

      if penalty
        penalty + 2
      end
    end

    # Files handed over by the document portal live under
    # /run/user/$UID/doc/, where the basename tells you nothing useful.
    def from_document_portal?(directory)
      directory.path.to_s.then do |path|
        path.start_with?(PORTAL_PREFIX) && path.split(File::SEPARATOR).include?(PORTAL_SEGMENT)
      end
    end
end
