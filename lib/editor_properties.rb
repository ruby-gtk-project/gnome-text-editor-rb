# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_encoding_model'
require_relative 'editor_indent_model'
require_relative 'editor_newline_model'
require_relative 'editor_path'

# EditorProperties is the model behind the document-properties panel: it reads
# the current page's file, encoding, line endings and indentation, and writes
# changes back to the page.
#
# Ported from upstream's src/editor-properties.c. Upstream exposes every field
# as a GObject property so the panel's template can bind to it, and hands the
# spin rows GtkAdjustments it owns; this port keeps the adjustments, because
# AdwSpinRow needs them, and replaces the property notifications with a single
# listener the panel registers.
class EditorProperties
  TAB_WIDTH_RANGE = (1..32)
  INDENT_WIDTH_RANGE = (-1..32)

  def initialize(&on_changed)
    @on_changed = on_changed
  end

  attr_reader :page

  # Points the model at a page, or at nothing when the window has no tabs.
  def page=(page)
    @page = page
    @document = page&.document
    watch_statistics
    sync_adjustments
    notify
  end

  def document = @document

  # The file's basename, or the draft's title.
  def name = @document ? @document.title : ''

  # The directory the file lives in, collapsed to "~/…"; blank for a draft,
  # which is what disables the Location row.
  def directory
    @document&.file&.parent&.then do |parent|
      parent.native? ? EditorPath.collapse(parent.path) : parent.uri
    end.to_s
  end

  # Whether the Location row can open a file manager, which needs a real file.
  def can_open? = !@document&.file.nil?

  # The syntax language's name. There is no GtkSourceView in this port, so
  # there is nothing to highlight with and nothing to name; the row shows the
  # document's plain-text nature.
  def language_name = 'Plain Text'

  def encoding = @document&.encoding

  def encoding_index = encoding&.index || 0

  def encoding_index=(index)
    EditorEncodingModel.default.get_item(index)&.then do |selected|
      @document&.encoding = selected
      notify
    end
  end

  def newline = @document&.newline

  def newline_index = newline&.index || 0

  def newline_index=(index)
    EditorNewlineModel.default.get_item(index)&.then do |selected|
      @document&.newline = selected
      notify
    end
  end

  def auto_indent? = @page ? @page.view.auto_indent? : false

  def auto_indent=(value)
    @page&.view&.auto_indent = value
    notify
  end

  def indent_style_index
    EditorIndentModel.index_for(@page ? @page.view.insert_spaces_instead_of_tabs? : false)
  end

  def indent_style_index=(index)
    EditorIndentModel.default.get_item(index)&.then do |indent|
      @page&.view&.insert_spaces_instead_of_tabs = indent.insert_spaces_instead_of_tabs?
      notify
    end
  end

  # The adjustments the two spin rows share. They live here, as upstream's do,
  # so switching pages re-seeds them rather than rebuilding the rows.
  def tab_width
    @tab_width ||= Gtk::Adjustment.new(
      8,
      TAB_WIDTH_RANGE.first,
      TAB_WIDTH_RANGE.last,
      1,
      1,
      0,
    ).tap do |adjustment|
      adjustment.signal_connect('value-changed') do
        @page&.view&.tab_width = adjustment.value.to_i
      end
    end
  end

  def indent_width
    @indent_width ||= Gtk::Adjustment.new(
      -1,
      INDENT_WIDTH_RANGE.first,
      INDENT_WIDTH_RANGE.last,
      1,
      1,
      0,
    )
                                     .tap do |adjustment|
      adjustment.signal_connect('value-changed') do
        @page&.view&.indent_width = adjustment.value.to_i
      end
    end
  end

  def statistics = @document&.statistics

  def on_changed(&block)
    tap { @on_changed = block }
  end

  def notify
    tap { @on_changed&.call(self) }
  end

  private

    # Each document's statistics are watched once, so a recount refreshes the
    # panel without the panel asking for a recount.
    def watch_statistics
      @watched ||= {}

      @document&.then do |document|
        unless @watched[document.object_id]
          @watched[document.object_id] = true
          document.on_statistics_changed { notify }
        end
      end
    end

    def sync_adjustments
      @page&.view&.then do |view|
        tab_width.value = view.tab_width
        indent_width.value = view.indent_width
      end
    end
end
