# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'adwaita'
require 'gtksourceview5'
require_relative 'editor_buffer_monitor'
require_relative 'editor_document_statistics'
require_relative 'editor_encoding_model'
require_relative 'editor_newline_model'

# EditorDocument is the text buffer behind a page: the file it came from, the
# draft that backs it when it has no file yet, its encoding and line endings,
# and the loading and saving around all of that.
#
# Ported from upstream's src/editor-document.c, with the line-splitting helper
# from src/line-reader-private.h folded in — Ruby's String#each_line is the
# same thing. Upstream derives from GtkSourceBuffer and drives loading and
# saving through GtkSourceFileLoader and GtkSourceFileSaver; this port derives
# from GtkSource::Buffer too — the gtksourceview5 gem — so syntax highlighting
# and the style scheme come from the buffer itself. The load and save paths
# stay the plain Gio calls, with encoding detection and newline conversion
# done by EditorEncodingModel and EditorNewlineModel, because upstream's own
# loader and saver exist mainly to run off the main thread, which this port
# does not need.
class EditorDocument < GtkSource::Buffer
  type_register

  # Upstream's cursor-moved comes from GtkSourceBuffer, and so does this
  # port's now that the class derives from the real thing — no define_signal
  # for it, just a connection in #connect_buffer_signals. The rest are its own.
  define_signal(
    'cursor_jumped',
    GLib::Signal::RUN_LAST,
    nil,
    nil,
  )
  define_signal(
    'title_changed',
    GLib::Signal::RUN_LAST,
    nil,
    nil,
  )
  define_signal(
    'busy_changed',
    GLib::Signal::RUN_LAST,
    nil,
    nil,
  )
  define_signal(
    'state_changed',
    GLib::Signal::RUN_LAST,
    nil,
    nil,
  )
  define_signal(
    'saved',
    GLib::Signal::RUN_LAST,
    nil,
    nil,
  )
  define_signal(
    'language_changed',
    GLib::Signal::RUN_LAST,
    nil,
    nil,
  )

  APP_ID = 'org.rubygtkproject.GnomeTextEditor'

  # Upstream's TITLE_MAX_LEN and TITLE_LAST_WORD_POS: a draft's title is the
  # first hundred characters of its text, cut at a word boundary if one turns
  # up in the first twenty.
  TITLE_MAX_LEN = 100
  TITLE_LAST_WORD_POS = 20
  READ_ONLY_SUFFIX = '[Read-Only]'
  UNTITLED = 'New Document'

  READ_CHUNK_SIZE = 64 * 1024
  METADATA_CURSOR = 'metadata::gte-cursor'
  ETAG_ATTRIBUTE = 'etag::value'
  WRITE_ATTRIBUTE = 'access::can-write'

  def self.new_draft = new

  def self.new_for_file(file) = new(file: file)

  def initialize(file: nil, draft_id: nil)
    super()

    @file = file
    @draft_id = draft_id || SecureRandom.uuid
    @encoding = EditorEncodingModel.default.utf8
    @newline = EditorNewlineModel.default.get("\n")
    @busy_count = 0
    @busy_progress = 0.0
    @loading = false
    @readonly = false
    @externally_modified = false
    @was_restored = false
    @did_shutdown = false
    @had_error = false
    @fallback_used = false
    @error_message = nil
    @language_id = nil
    @language_id_overridden = false
    @guess_content_type = nil
    @monitor = EditorBufferMonitor.new { mark_externally_modified }
    @monitor.file = @file

    connect_buffer_signals
    sync_language
  end

  attr_reader :file, :draft_id, :encoding, :newline, :busy_progress, :error_message

  def loading? = @loading
  def busy? = @busy_count.positive?
  def readonly? = @readonly
  def externally_modified? = @externally_modified
  def was_restored? = @was_restored
  def did_shutdown? = @did_shutdown
  def had_error? = @had_error
  def fallback_used? = @fallback_used

  def draft_id=(draft_id)
    @draft_id = draft_id || SecureRandom.uuid
  end

  def was_restored=(value)
    @was_restored = value
  end

  def encoding=(encoding)
    unless @encoding == encoding
      @encoding = encoding
      signal_emit('state_changed')
    end
  end

  def newline=(newline)
    unless @newline == newline
      @newline = newline
      signal_emit('state_changed')
    end
  end

  def uri = @file&.uri

  # The file the draft's text is parked in while the document has no file of
  # its own: $XDG_DATA_HOME/<app id>/drafts/<draft id>.
  def draft_file
    Gio::File.new_for_path(
      File.join(
        GLib.user_data_dir,
        APP_ID,
        'drafts',
        @draft_id,
      ),
    )
  end

  # Upstream's editor_document_dup_title: the basename if there is a file,
  # otherwise the leading words of the text, with "[Read-Only]" appended when
  # the file cannot be written.
  def title
    (@file ? File.basename(@file.parse_name) : title_from_text).then do |base|
      @readonly ? "#{base} #{READ_ONLY_SUFFIX}" : base
    end
  end

  # The language this document is written in, as a GtkSourceView language id:
  # what a modeline said it is, or GtkSourceLanguageManager's guess from the
  # file's name and content.
  def language_id
    if @language_id_overridden
      @language_id
    else
      guessed_language_id
    end
  end

  # What a modeline asks for, or the Language dialog's choice — upstream sets
  # the buffer's language here too, which is what drives syntax highlighting;
  # nil means no language, and plain text, at all.
  def language_id=(language_id)
    (language_id != self.language_id).then do |changed|
      @language_id = language_id
      @language_id_overridden = true
      self.language = language_id && GtkSource::LanguageManager.default.get_language(language_id)

      if changed
        signal_emit('language_changed')
      end
    end
  end

  # The name to offer in a Save As dialog: the title, with a ".txt" suffix
  # added when it has none. Upstream asks the GtkSourceLanguage for a
  # suggested suffix first, which this port has no source of.
  def suggest_filename
    (title_from_text.empty? ? UNTITLED : title_from_text).then do |name|
      File.extname(name).empty? ? "#{name}.txt" : name
    end
  end

  def suggest_file(directory) = directory.get_child(suggest_filename)

  # Statistics are created on demand, because only the properties panel wants
  # them, and recounted as the buffer changes. Their listeners are kept apart
  # from the "state_changed" signal: that signal is what makes the page and the
  # window refresh, and the properties panel is what asks for the statistics,
  # so routing the recount through it would have the panel rebuild itself.
  def statistics
    (@statistics ||= EditorDocumentStatistics.new(self) do |computed|
      statistics_listeners.each { |listener| listener.call(computed) }
    end).tap do |statistics|
      unless statistics.loaded?
        statistics.reload
      end
    end
  end

  def on_statistics_changed(&block)
    tap { statistics_listeners << block }
  end

  def statistics_loaded? = !@statistics.nil?

  # Reads the file into the buffer. Encoding detection runs over the bytes
  # first, so a Latin-1 file opens as its own text rather than as U+FFFD;
  # passing an encoding skips detection, which is what the Change Encoding
  # dialog needs.
  # Yields the GLib::Error on failure, nil on success.
  def load(encoding: nil)
    mark_busy
    @loading = true

    begin
      @file.then do |file|
        read_bytes(file).then do |bytes|
          apply_loaded_text(bytes, encoding)
          query_readonly(file)
          @guess_content_type = query_content_type(file)
          sync_language
          @monitor.etag = query_etag(file)
          @monitor.failed = false
          @monitor.reset
          clear_error
        end
      end
      restore_cursor
      if block_given?
        yield nil
      end
    rescue StandardError => e
      record_error(e)
      @monitor.failed = true
      if block_given?
        yield e
      end
    ensure
      @loading = false
      unmark_busy
      signal_emit('title_changed')
      signal_emit('state_changed')
    end

    self
  end

  # Writes the buffer to a file and, on success, drops the draft that was
  # standing in for it. The monitor is paused around the write so the editor's
  # own save does not come back as an external modification.
  def save(file = @file)
    mark_busy
    @monitor.pause

    begin
      write_text(file, encoded_text)
      (file != @file).then do |moved|
        @file = file

        if moved
          @guess_content_type = nil
          sync_language
          signal_emit('language_changed')
        end
      end
      @monitor.file = file
      @monitor.etag = query_etag(file)
      @externally_modified = false
      self.modified = false
      query_readonly(file)
      save_cursor
      discard_draft
      clear_error
      signal_emit('saved')
      if block_given?
        yield nil
      end
    rescue StandardError => e
      record_error(e)
      if block_given?
        yield e
      end
    ensure
      @monitor.unpause
      unmark_busy
      signal_emit('title_changed')
      signal_emit('state_changed')
    end

    self
  end

  # Parks the current text in the drafts directory so an unsaved document
  # survives a restart. A document with a file and no changes has nothing to
  # park, which is upstream's behaviour too.
  def save_draft
    if modified? || @file.nil?
      draft_file.tap do |target|
        FileUtils.mkdir_p(File.dirname(target.path))
        write_text(target, text)
      end
    end
    self
  end

  # Loads the parked text back, marking the buffer modified: the restored text
  # differs from what is on disk, which is what the info bar announces.
  def load_draft
    draft_file.then do |source|
      if source.query_exists
        begin_irreversible_action
        self.text = read_bytes(source).force_encoding(Encoding::UTF_8)
        end_irreversible_action
        self.modified = true
        @was_restored = true
        signal_emit('title_changed')
      end
    end
    self
  end

  def discard_draft
    draft_file.then do |target|
      if target.query_exists
        target.delete
      end
    end
    self
  rescue StandardError
    self
  end

  # Throws away the buffer's changes and reads the file again — the info bar's
  # "Discard Changes" and the window's reload path.
  def discard_changes
    discard_draft
    @was_restored = false

    if @file
      load
    else
      begin_irreversible_action
      self.text = ''
      end_irreversible_action
      self.modified = false
      self
    end
  end

  # True when the file is a local one the editor could not read, so opening it
  # again over admin:// has a chance of working. Upstream exposes this as its
  # "suggest-admin" property and the info bar shows the administrator button
  # for it.
  def suggest_admin?
    @had_error && @file&.native? && @file.uri.start_with?('file:///')
  end

  # Reopens the same path over the admin:// backend, which prompts for
  # authentication and then loads with elevated rights.
  def use_admin
    tap do
      if suggest_admin?
        @file = Gio::File.new_for_uri("admin://#{@file.path}")
        @monitor.file = @file
        load
      end
    end
  end

  # Marks the document finished with, so the session stops saving drafts for
  # it once its page has been closed.
  def shutdown
    tap do
      @did_shutdown = true
      @monitor.cancel
      @statistics&.cancel_queued
    end
  end

  def mark_busy
    tap do
      @busy_count += 1
      if @busy_count == 1
        signal_emit('busy_changed')
      end
    end
  end

  def unmark_busy
    tap do
      if @busy_count.positive?
        @busy_count -= 1
      end

      if @busy_count.zero?
        @busy_progress = 0.0
        signal_emit('busy_changed')
      end
    end
  end

  # Cursor position, one-based, as the statusbar and the position label show it.
  def cursor_line_column
    get_iter_at(offset: cursor_position_offset).then { |iter| [iter.line + 1, iter.line_offset + 1] }
  end

  # The number of lines, or characters within a line, the selection spans.
  # Upstream's statusbar computes this from the selection bounds.
  def selection_count
    selection_bounds.then do |bounds|
      if bounds
        bounds.then do |(from, to)|
          from.line == to.line ? (to.line_offset - from.line_offset).abs : (to.line - from.line).abs
        end
      else
        0
      end
    end
  end

  # Remembers where the cursor is so a reload can put it back, which is what
  # upstream's _editor_document_save_insert_mark is for.
  def save_insert_mark
    tap { @saved_insert = get_iter_at(offset: cursor_position_offset).then { |iter| [iter.line, iter.line_offset] } }
  end

  def restore_insert_mark
    tap do
      @saved_insert&.then do |(line, offset)|
        place_cursor(get_iter_at(line: line, line_offset: offset))
      end
    end
  end

  def cursor_position_offset = get_property('cursor-position')

  # Default handlers for the signals this class defines. GLib looks these up
  # by name when the signal is emitted, so each defined signal needs one.
  # "cursor-moved" is not here: it is GtkSourceBuffer's own signal now, not
  # one define_signal added.
  def signal_do_cursor_jumped = nil
  def signal_do_title_changed = nil
  def signal_do_busy_changed = nil
  def signal_do_state_changed = nil
  def signal_do_saved = nil
  def signal_do_language_changed = nil

  private

    # GtkSourceLanguageManager's guess from the file's name and, once loaded,
    # its content — the same two-argument guess upstream makes.
    def guessed_language_id
      @file&.then do |file|
        GtkSource::LanguageManager.default.guess_language(
          File.basename(file.parse_name),
          @guess_content_type,
        )&.id
      end
    end

    # Keeps the buffer's actual GtkSource::Language, which drives syntax
    # highlighting, in step with #language_id whenever the guess could have
    # moved: a fresh load, or a save under a new name.
    def sync_language
      language_id.then { |id| self.language = id && GtkSource::LanguageManager.default.get_language(id) }
    end

    def statistics_listeners = @statistics_listeners ||= []

    def connect_buffer_signals
      signal_connect('cursor-moved') do
        unless @editing
          signal_emit('cursor_jumped')
        end
      end

      signal_connect('changed') do
        @editing = true
        if @file.nil?
          signal_emit('title_changed')
        end
        @statistics&.queue_reload
        @editing = false
      end

      signal_connect('modified-changed') { signal_emit('state_changed') }
    end

    # Upstream walks the buffer a character at a time, collapsing runs of
    # punctuation and whitespace into single spaces and stopping at a blank
    # line. This is the same walk over the first TITLE_MAX_LEN characters.
    def title_from_text
      ''.dup.then do |title|
        count = 0

        text.each_char do |char|
          if count >= TITLE_MAX_LEN
            break
          end
          if char == "\n" && !title.empty?
            break
          end

          if char.match?(/[[:space:]]/) || char.match?(/[[:punct:]]/)
            if count > TITLE_LAST_WORD_POS
              break
            end

            unless title.empty? || title.end_with?(' ')
              count += 1
              title << ' '
            end
          else
            count += 1
            title << char
          end
        end

        title.strip
      end
    end

    def apply_loaded_text(bytes, forced = nil)
      (forced || EditorEncodingModel.default.detect(bytes)).then do |detected|
        @encoding = detected
        detected.decode(bytes).then do |(decoded, fallback_used)|
          @fallback_used = fallback_used
          @newline = EditorNewlineModel.detect(decoded)
          begin_irreversible_action
          self.text = decoded.gsub(/\r\n|\r/, "\n")
          end_irreversible_action
          self.modified = false
        end
      end
    end

    # The buffer always holds "\n"; the file gets whatever convention the
    # document is set to, in whatever charset it is set to.
    def encoded_text = @encoding.encode(@newline.apply(text))

    # Read through a Gio input stream rather than Gio::File#load_contents:
    # load_contents aborts the process when it fails — a missing or unreadable
    # file kills the editor instead of raising — while the stream raises a
    # Gio::IOError the load path can report.
    #
    # The unpack is not decoration. A string handed over by a Gio stream
    # arrives with its character range already cached as ASCII-only, whatever
    # bytes it holds, and Ruby trusts that cache: String#valid_encoding? says
    # true and String#encode skips the conversion, so a Latin-1 file would be
    # declared UTF-8 and pushed into the buffer as invalid bytes. Rebuilding
    # the string through unpack recomputes the range.
    def read_bytes(file)
      file.read.then do |stream|
        ''.b.tap do |bytes|
          while (chunk = stream.read(READ_CHUNK_SIZE)) && !chunk.empty?
            bytes << chunk.b
          end

          stream.close
        end
      end.unpack1('a*')
    end

    def write_text(file, content)
      file.replace_contents(
        content,
        nil,
        false,
        :none,
      )
    end

    def query_etag(file)
      file.query_info(ETAG_ATTRIBUTE, :none).etag
    rescue StandardError
      nil
    end

    def query_content_type(file)
      file.query_info('standard::content-type', :none).content_type
    rescue StandardError
      nil
    end

    def query_readonly(file)
      file.query_info(WRITE_ATTRIBUTE, :none)
          .get_attribute_boolean(WRITE_ATTRIBUTE)
          .then { |can_write| @readonly = !can_write }
    rescue StandardError
      @readonly = false
    end

    # The cursor is kept in the file's Gio metadata, the same attribute
    # upstream uses, so reopening a file lands where it was left. A filesystem
    # with no metadata store refuses the write; the position is a convenience,
    # so the refusal is swallowed rather than reported as a save failure.
    def save_cursor
      cursor_line_column.then do |(line, column)|
        Gio::FileInfo.new.tap do |info|
          info.set_attribute_string(METADATA_CURSOR, "#{line}:#{column}")
          @file.set_attributes_from_info(info, :none)
        end
      end
    rescue StandardError
      nil
    end

    def restore_cursor
      @file.query_info(METADATA_CURSOR, :none)
           .get_attribute_string(METADATA_CURSOR)
           &.split(':')
           &.then { |(line, column)| place_cursor(get_iter_at(line: line.to_i - 1, line_offset: column.to_i - 1)) }
    rescue StandardError
      nil
    end

    def mark_externally_modified
      @externally_modified = true
      signal_emit('state_changed')
    end

    def record_error(error)
      @had_error = true
      @error_message = error.message
    end

    def clear_error
      @had_error = false
      @error_message = nil
    end
end
