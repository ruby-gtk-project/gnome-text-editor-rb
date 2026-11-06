# frozen_string_literal: true

require 'fileutils'
require 'adwaita'
require 'gtksourceview5'

# EditorPrintOperation prints a document through GtkSourceView's print
# compositor: a title and page number in the header and footer, syntax
# highlighting swapped to the "printing" style scheme so colour choices read
# on paper, and the view's own tab width and line numbers carried over.
#
# Ported from upstream's src/editor-print-operation.c. Upstream subclasses
# GtkPrintOperation and overrides its "begin_print", "paginate", "draw_page"
# and "end_print" virtual methods; the Ruby bindings have no virtual-method
# override for GtkPrintOperationClass, so this port is a plain class wrapping
# a Gtk::PrintOperation and connecting to the same four signals instead, which
# carry the same GtkPrintContext.
class EditorPrintOperation
  APP_ID = 'org.rubygtkproject.GnomeTextEditor'

  def initialize(document, view, settings)
    @document = document
    @view = view
    @settings = settings

    operation.signal_connect('begin-print') { |_op, context| begin_print(context) }
    operation.signal_connect('paginate') { |_op, context| paginate(context) }
    operation.signal_connect('draw-page') { |_op, context, page_nr| @compositor.draw_page(context, page_nr) }
    operation.signal_connect('end-print') { @compositor = nil }
    operation.signal_connect('done') do |_op, result|
      if result == :apply
        save_settings
      end
    end
  end

  def run(window) = tap { operation.run(:print_dialog, window) }

  private

    def operation
      @operation ||= Gtk::PrintOperation.new.tap do |op|
        op.default_page_setup = page_setup
        op.print_settings = print_settings
        op.embed_page_setup = true
      end
    end

    # Upstream reaches for the Adwaita printing scheme unless the document is
    # already printing in its own; this port's buffer is the real
    # GtkSource::Buffer, so the swap is the buffer's own style-scheme and
    # language, not a text copy into an alternate one.
    def begin_print(context)
      syntax_hl = @document.highlight_syntax?
      scheme = print_scheme(syntax_hl)

      @compositor = GtkSource::PrintCompositor.new(@view).tap do |compositor|
        compositor.tab_width = @view.tab_width
        compositor.highlight_syntax = syntax_hl
        if @view.show_line_numbers?
          compositor.print_line_numbers = 1
        else
          compositor.print_line_numbers = 0
        end
        compositor.print_header = true
        compositor.print_footer = true
        compositor.wrap_mode = :word_char

        unless @settings.use_system_font?
          compositor.set_body_font_name(@settings.custom_font)
          compositor.set_line_numbers_font_name(@settings.custom_font)
          compositor.set_header_font_name(@settings.custom_font)
          compositor.set_footer_font_name(@settings.custom_font)
        end

        compositor.set_header_format(
          true,
          header_left,
          nil,
          nil,
        )
        # Translators: %N is the current page number, %Q is the total number
        # of pages (ex. Page 2 of 10)
        compositor.set_footer_format(
          true,
          nil,
          nil,
          'Page %N of %Q',
        )
      end

      @original_scheme = @document.style_scheme
      if scheme
        @document.style_scheme = scheme
      end
    end

    def print_scheme(syntax_hl)
      current = @document.style_scheme
      if syntax_hl && current && current.id != 'printing'
        GtkSource::StyleSchemeManager.default.get_scheme('printing')
      end
    end

    def header_left
      if @document.file.nil?
        "Draft: #{@document.title}"
      elsif @document.file.native?
        "File: #{@document.title}"
      else
        @document.uri
      end
    end

    def paginate(context)
      @compositor.paginate(context).tap do |finished|
        if finished
          operation.n_pages = @compositor.n_pages
          @document.style_scheme = @original_scheme
        end
      end
    end

    def page_setup
      Gtk::PageSetup.new.tap do |setup|
        setup.load_file(page_setup_path)
      rescue StandardError
        nil
      end
    end

    def print_settings
      Gtk::PrintSettings.new.tap do |settings|
        settings.load_file(print_settings_path)
      rescue StandardError
        nil
      end
    end

    def save_settings
      FileUtils.mkdir_p(File.dirname(print_settings_path))
      operation.print_settings.to_file(print_settings_path)
      operation.default_page_setup.to_file(page_setup_path)
    rescue StandardError
      nil
    end

    def print_settings_path = File.join(GLib.user_data_dir, APP_ID, 'print-settings')

    def page_setup_path = File.join(GLib.user_data_dir, APP_ID, 'page-setup')
end
