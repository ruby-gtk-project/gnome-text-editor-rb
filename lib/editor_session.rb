# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'adwaita'
require_relative 'editor_document'
require_relative 'editor_sidebar_model'

# EditorSession owns the windows, the open pages, the drafts and the list of
# recent documents, and writes all of it to disk so a restart comes back to
# the same desk.
#
# Ported from upstream's src/editor-session.c. Upstream serialises its state
# into a GVariant at $XDG_CONFIG_HOME/<app id>/session.gvariant; GVariant
# builders have no comfortable Ruby binding, so this port writes the same keys
# — version, drafts, windows, each window's pages, their uris, draft ids,
# selections and which was active — as JSON, under the same directory. The
# auto-save timer, the "seen" and "forgotten" bookkeeping and the dedup rules
# are upstream's.
class EditorSession
  APP_ID = 'org.rubygtkproject.GnomeTextEditor'
  STATE_VERSION = 1
  STATE_BASENAME = 'session.json'
  DEFAULT_AUTO_SAVE_DELAY = 3

  def initialize(settings: nil, &on_windows_changed)
    @settings = settings
    @windows = []
    @pages = []
    @drafts = {}
    @seen = {}
    @forgot = {}
    @auto_save = true
    @auto_save_delay = settings&.auto_save_delay || DEFAULT_AUTO_SAVE_DELAY
    @did_restore = false
    @dirty = false
    @on_windows_changed = on_windows_changed
    @recents = EditorSidebarModel.new
  end

  attr_reader :windows, :pages, :recents, :auto_save_delay

  def auto_save? = @auto_save
  def did_restore? = @did_restore

  def auto_save=(value)
    @auto_save = value
    reset_auto_save
  end

  def auto_save_delay=(delay)
    @auto_save_delay = delay
    reset_auto_save
  end

  # The block the application hands over to make a window; the session calls it
  # rather than requiring EditorWindow, which keeps the dependency pointing one
  # way, as upstream's session does through its application.
  def window_factory=(factory)
    @window_factory = factory
  end

  def create_window
    create_window_no_draft.tap { |window| add_draft(window) }
  end

  def create_window_no_draft
    @window_factory.call.tap { |window| add_window(window) }
  end

  def add_window(window)
    tap do
      unless @windows.include?(window)
        @windows << window
      end
      @on_windows_changed&.call(self)
      mark_dirty
    end
  end

  def remove_window(window)
    tap do
      @windows.delete(window)
      @on_windows_changed&.call(self)
      mark_dirty
    end
  end

  # Opens a file: if it is already open, its page is raised instead, which is
  # what keeps a file from appearing in two tabs.
  def open(window, file, encoding: nil)
    find_page_by_file(file).then do |existing|
      if existing
        existing.raise_page
      else
        open_new(window, file, encoding)
      end
    end
  end

  # Restores a parked draft into a page. The draft keeps its id, so saving it
  # later still clears the right file.
  def open_draft(window, draft_id)
    find_page_by_draft_id(draft_id).then do |existing|
      if existing
        existing.raise_page
      else
        open_new_draft(window, draft_id)
      end
    end
  end

  def add_draft(window) = add_document(window, EditorDocument.new_draft)

  def add_document(window, document)
    @page_factory.call(document).tap { |page| add_page(window, page) }
  end

  # The block the application hands over to make a page for a document.
  def page_factory=(factory)
    @page_factory = factory
  end

  def add_page(window, page)
    tap do
      unless @pages.include?(page)
        @pages << page
      end
      window.add_page(page)
      @recents.add_page(page)
      mark_dirty
    end
  end

  def remove_page(page)
    tap do
      @pages.delete(page)
      @recents.remove_page(page)
      page.document.shutdown
      mark_dirty
    end
  end

  def remove_document(document)
    find_page_by_document(document)&.then { |page| remove_page(page) }
    @recents.remove_document(document)
    self
  end

  def move_page_to_window(page, window)
    tap do
      page.window&.remove_page(page)
      window.add_page(page)
      mark_dirty
    end
  end

  def find_page_by_file(file)
    file&.then { |needle| @pages.find { |page| page.document.file&.uri == needle.uri } }
  end

  def find_page_by_draft_id(draft_id)
    @pages.find { |page| page.document.draft_id == draft_id }
  end

  def find_page_by_document(document)
    @pages.find { |page| page.document.equal?(document) }
  end

  # Opens a list of files at once — the application's command line and the
  # window's drag-and-drop both land here.
  def open_files(files, window: nil)
    (window || @windows.first || create_window_no_draft).then do |target|
      files.each { |file| open(target, file) }
      target
    end
  end

  # Opens a stream as a new draft, which is how upstream handles being handed
  # standard input.
  def open_stream(window, stream)
    EditorDocument.new_draft.then do |document|
      document.text = read_stream(stream)
      document.modified = true
      add_document(window, document)
    end
  end

  # Records that a document has been opened, so it shows up in the recents
  # list and is no longer "forgotten".
  def document_seen(document)
    tap do
      document.file&.then do |file|
        @forgot.delete(file.uri)
        @seen[file.uri] = Time.now
        @recents.add_file(file)
      end
      mark_dirty
    end
  end

  # Drops a recent entry for good: upstream's app.remove-recent.
  def forget(uri:, draft_id: nil)
    tap do
      if uri
        @forgot[uri] = true
      end
      if uri
        @seen.delete(uri)
      end
      if draft_id
        @drafts.delete(draft_id)
      end

      if draft_id
        @recents.remove_draft(draft_id)
        discard_draft_file(draft_id)
      elsif uri
        @recents.remove_file(Gio::File.new_for_uri(uri))
      end

      mark_dirty
      save
    end
  end

  def clear_history
    tap do
      @seen.clear
      @drafts.each_key { |draft_id| discard_draft_file(draft_id) }
      @drafts.clear
      @recents.clear
      mark_dirty
      save
    end
  end

  def can_clear_history? = !@seen.empty? || !@drafts.empty?

  def add_draft_record(draft_id, title, uri)
    tap do
      @drafts[draft_id] = { 'draft-id' => draft_id, 'title' => title, 'uri' => uri }
      mark_dirty
    end
  end

  def remove_draft_record(draft_id)
    tap do
      @drafts.delete(draft_id)
      @recents.remove_draft(draft_id)
      mark_dirty
    end
  end

  def drafts = @drafts.values

  # Reads the state file and rebuilds the windows, their pages and the recents
  # list. Returns the window that was active, or nil when there was nothing to
  # restore.
  def restore
    @did_restore = true

    read_state.then do |state|
      if state
        restore_drafts(state)
        restore_recents(state)
        restore_windows(state)
      end
    end
  end

  # Writes the state file and parks every modified page's draft.
  def save(shutting_down: false)
    tap do
      @pages.each do |page|
        unless page.document.did_shutdown?
          page.document.save_draft
        end
      end
      record_drafts
      write_state(shutting_down: shutting_down)
      @dirty = false
    end
  end

  # Starts, or restarts, the auto-save timer. Each tick parks the drafts of
  # every modified page, which is what makes an unsaved document survive a
  # crash.
  def reset_auto_save
    tap do
      if @auto_save_source
        GLib::Source.remove(@auto_save_source)
      end
      @auto_save_source = nil

      if @auto_save
        @auto_save_source = GLib::Timeout.add_seconds([@auto_save_delay, 1].max) do
          if @dirty
            save
          end
          GLib::Source::CONTINUE
        end
      end
    end
  end

  def mark_dirty
    tap { @dirty = true }
  end

  def state_file
    Gio::File.new_for_path(File.join(GLib.user_config_dir, APP_ID, STATE_BASENAME))
  end

  private

    # The page for a file nothing has open yet: a document that loads itself
    # and reports a failure to the page, and a recents entry for the file.
    def open_new(window, file, encoding)
      EditorDocument.new_for_file(file).then do |document|
        if encoding
          document.encoding = encoding
        end

        add_document(window, document).tap do |page|
          document.load do |error|
            if error
              page.report_load_error(error)
            end
          end
          document_seen(document)
        end
      end
    end

    # The page for a parked draft: the recorded file, if it had one, loaded
    # first so the draft's text replaces it as the modified copy.
    def open_new_draft(window, draft_id)
      @drafts[draft_id].then do |draft|
        EditorDocument.new(file: draft_file_uri(draft), draft_id: draft_id).then do |document|
          if document.file
            document.load
          end

          document.load_draft
          add_document(window, document)
        end
      end
    end

    def read_stream(stream)
      ''.dup.tap do |text|
        loop do
          stream.read(4096).then do |chunk|
            if chunk.nil? || chunk.empty?
              break
            end

            text << chunk
          end
        end
      end
    end

    def draft_file_uri(draft)
      draft && draft['uri'] ? Gio::File.new_for_uri(draft['uri']) : nil
    end

    def discard_draft_file(draft_id)
      File.join(
        GLib.user_data_dir,
        EditorDocument::APP_ID,
        'drafts',
        draft_id,
      ).then do |path|
        FileUtils.rm_f(path)
      end
    end

    def record_drafts
      @pages.each do |page|
        page.document.then do |document|
          if document.modified? || document.file.nil?
            add_draft_record(document.draft_id, document.title, document.uri)
          else
            @drafts.delete(document.draft_id)
          end
        end
      end
    end

    def read_state
      state_file.then do |file|
        unless file.query_exists
          next nil
        end

        JSON.parse(File.read(file.path)).then do |state|
          state['version'] == STATE_VERSION ? state : nil
        end
      end
    rescue StandardError
      nil
    end

    def write_state(shutting_down:)
      state_file.tap do |file|
        FileUtils.mkdir_p(File.dirname(file.path))
        File.write(file.path, JSON.pretty_generate(state_hash(shutting_down: shutting_down)))
      end
    rescue StandardError
      nil
    end

    def state_hash(shutting_down:)
      {
        'version'  => STATE_VERSION,
        'shutdown' => shutting_down,
        'drafts'   => @drafts.values,
        'recents'  => @seen.map { |uri, age| { 'uri' => uri, 'age' => age.to_i } },
        'windows'  => @windows.map { |window| window_hash(window) },
      }
    end

    def window_hash(window)
      {
        'is-active'      => window.active?,
        'default-width'  => window.default_width,
        'default-height' => window.default_height,
        'pages'          => window.pages.map { |page| page_hash(window, page) },
      }
    end

    def page_hash(window, page)
      page.document.then do |document|
        {
          'draft-id'  => document.draft_id,
          'uri'       => document.uri,
          'selection' => page.selection_state,
          'is-active' => window.visible_page.equal?(page),
        }
      end
    end

    def restore_drafts(state)
      state.fetch('drafts', []).each do |draft|
        @drafts[draft['draft-id']] = draft
        @recents.add_draft(
          draft['draft-id'],
          title: draft['title'],
          file:  draft['uri'] && Gio::File.new_for_uri(draft['uri']),
        )
      end
    end

    def restore_recents(state)
      state.fetch('recents', []).each do |recent|
        @seen[recent['uri']] = Time.at(recent['age'].to_i)
        @recents.add_file(Gio::File.new_for_uri(recent['uri']), age: Time.at(recent['age'].to_i))
      end
    end

    def restore_windows(state)
      state.fetch('windows', []).filter_map { |window_state| restore_window(window_state) }
           .then { |windows| windows.find(&:active?) || windows.first }
    end

    def restore_window(window_state)
      create_window_no_draft.tap do |window|
        window.set_default_size(
          window_state.fetch('default-width', 800),
          window_state.fetch('default-height', 600),
        )

        window_state.fetch('pages', [])
                    .filter_map { |page_state| restore_page(window, page_state) }
                    .then do |restored|
          (restored.find { |(_, active)| active } || restored.first)
            &.then { |(page, _)| window.visible_page = page }
        end
      end
    end

    # Returns the restored page and whether the state marked it active, so the
    # window can raise the tab the session was last looking at.
    def restore_page(window, page_state)
      page_state['uri'].then do |uri|
        if uri
          open(window, Gio::File.new_for_uri(uri))
        else
          open_draft(window, page_state['draft-id'])
        end
      end&.then do |page|
        page.selection_state = page_state['selection']
        [page, page_state['is-active'] == true]
      end
    end
end
