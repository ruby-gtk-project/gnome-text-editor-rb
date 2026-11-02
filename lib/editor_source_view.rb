# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_utils'

# EditorSourceView is the text view a page edits in: the font and zoom, the
# wrap mode, the indentation, and the line-wise editing commands.
#
# Ported from upstream's src/editor-source-view.c. Upstream derives from
# GtkSourceView, so it inherits auto-indent, tab handling, smart home/end and
# the zoom machinery's font override; this port derives from GtkTextView and
# implements the ones the editor's settings expose — auto indent, indent
# width, tab width, spaces instead of tabs — on top of it. Syntax
# highlighting, snippets, the right-margin line and the spelling menu come
# from GtkSourceView and have no counterpart here.
class EditorSourceView < Gtk::TextView
  type_register

  DEFAULT_FONT_SIZE = 11
  CSS_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION

  def initialize(document)
    super()

    @font_scale = 0
    @font_desc = nil
    @line_height = 1.2
    @auto_indent = true
    @insert_spaces_instead_of_tabs = false
    @tab_width = 8
    @indent_width = -1
    @zoom_listeners = []

    self.buffer = document
    add_css_class(css_class)
    Gtk::StyleContext.add_provider_for_display(Gdk::Display.default, css_provider, CSS_PRIORITY)
  end

  # Assembles the controllers and actions. The view's own styling lives in the
  # memoized accessors, so this only wires behaviour.
  def build
    tap do
      add_controller(scroll_controller)
      add_controller(key_controller)
      add_controller(shortcut_controller)
      insert_action_group('buffer', buffer_actions)
      buffer.signal_connect('busy_changed') { self.editable = !buffer.loading? }
      update_css
    end
  end

  attr_reader :font_scale, :font_desc, :tab_width, :indent_width

  def auto_indent? = @auto_indent
  def insert_spaces_instead_of_tabs? = @insert_spaces_instead_of_tabs

  # Zoom is counted in points added to the configured font size, which is how
  # upstream's font_scale works: zoom(0) resets it.
  def zoom(amount)
    tap do
      if amount.zero?
        @font_scale = 0
      else
        @font_scale = @font_scale + amount
      end
      update_css
      @zoom_listeners.each { |listener| listener.call(zoom_level) }
    end
  end

  def on_zoom_changed(&block)
    tap { @zoom_listeners << block }
  end

  # The ratio the window's menu shows next to the zoom buttons.
  def zoom_level
    base_font_size.then { |size| [1, size + @font_scale].max.to_f / size }
  end

  def font_desc=(font_desc)
    @font_desc = font_desc
    @font_scale = 0
    update_css
  end

  def line_height=(line_height)
    @line_height = line_height
    update_css
  end

  def auto_indent=(value)
    @auto_indent = value
  end

  def insert_spaces_instead_of_tabs=(value)
    @insert_spaces_instead_of_tabs = value
  end

  def tab_width=(width)
    @tab_width = width
    update_tab_stops
  end

  def indent_width=(width)
    @indent_width = width
  end

  # How many columns one indent step is: the indent width when set, otherwise
  # the tab width, which is what -1 means in the GSettings schema.
  def effective_indent_width = @indent_width.to_i.positive? ? @indent_width : @tab_width

  def wrap_text=(wrap_text)
    self.wrap_mode = EditorUtils.wrap_mode(wrap_text)
  end

  # Selects the whole line, or extends an existing line-wise selection, which
  # is what Ctrl+L does.
  def select_line
    line_bounds.then do |(from, to)|
      buffer.select_range(from, to)
    end
    self
  end

  def delete_line
    line_bounds.then do |(from, to)|
      buffer.begin_user_action
      buffer.delete(from, to)
      buffer.end_user_action
    end
    self
  end

  # Copies the current line below itself and leaves the cursor on the copy,
  # which is upstream's buffer.duplicate-line.
  def duplicate_line
    line_bounds.then do |(from, to)|
      buffer.get_text(from, to, true).then do |text|
        buffer.begin_user_action
        buffer.insert(to, text.end_with?("\n") ? text : "#{text}\n")
        buffer.end_user_action
      end
    end
    self
  end

  # Scrolls the cursor into view the way the page does after a search or a
  # goto-line.
  def scroll_to_insert
    tap { scroll_to_mark(
      buffer.get_mark('insert'),
      0.25,
      true,
      1.0,
      0.5,
    ) }
  end

  private

    def css_provider = @css_provider ||= Gtk::CssProvider.new

    # Each view gets its own class so its font and zoom are its own, even
    # though the provider is installed for the whole display — the Ruby
    # bindings' per-widget style context is deprecated.
    def css_class = @css_class ||= "editor-source-view-#{object_id.abs}"

    # Ctrl+scroll zooms; everything else falls through to the scrolled window.
    def scroll_controller
      @scroll_controller ||= Gtk::EventControllerScroll.new(:vertical).tap do |controller|
        controller.signal_connect('scroll') do |ctrl, _dx, dy|
          if ctrl.current_event_state.control_mask?
            zoom(dy.negative? ? 1 : -1)
            true
          else
            false
          end
        end
      end
    end

    # Tab inserts spaces when the document asks for spaces, and Return copies
    # the previous line's indentation when auto-indent is on. GtkSourceView
    # does both for upstream.
    def key_controller
      @key_controller ||= Gtk::EventControllerKey.new.tap do |controller|
        controller.signal_connect('key-pressed') do |_ctrl, keyval, _code, _state|
          case keyval
          when Gdk::Keyval::KEY_Tab then insert_indent
          when Gdk::Keyval::KEY_Return, Gdk::Keyval::KEY_KP_Enter then insert_newline_with_indent
          else false
          end
        end
      end
    end

    # The accelerators upstream installs with
    # gtk_widget_class_add_binding_action. The zoom actions they name live in
    # the page's action group, one widget up: the view must not install a
    # "page" group of its own, because GTK stops walking up once it finds a
    # widget carrying the prefix, and the page's group is the complete one.
    def shortcut_controller
      @shortcut_controller ||= Gtk::ShortcutController.new.tap do |controller|
        {
          '<Control>plus'        => 'page.zoom-in',
          '<Control>KP_Add'      => 'page.zoom-in',
          '<Control>equal'       => 'page.zoom-in',
          '<Control>minus'       => 'page.zoom-out',
          '<Control>KP_Subtract' => 'page.zoom-out',
          '<Control>0'           => 'page.zoom-one',
          '<Control>l'           => 'buffer.select-line',
          '<Control>d'           => 'buffer.delete-line',
          '<Control><Alt>d'      => 'buffer.duplicate-line',
        }.each { |accelerator, action| controller.add_shortcut(EditorUtils.shortcut(accelerator, action)) }
      end
    end

    def buffer_actions
      @buffer_actions ||= Gio::SimpleActionGroup.new.tap do |group|
        {
          'select-line'    => -> { select_line },
          'delete-line'    => -> { delete_line },
          'duplicate-line' => -> { duplicate_line },
        }.each do |name, command|
          group.add_action(
            Gio::SimpleAction.new(name).tap do |action|
                        action.signal_connect('activate') { command.call }
                      end,
          )
        end
      end
    end

    # The font and the line height reach a GtkTextView through CSS, which is
    # also how upstream applies them.
    def update_css
      css_provider.load(data: "textview.#{css_class}{#{font_css}line-height:#{@line_height};}")
      update_tab_stops
    end

    def font_css
      @font_desc.then do |desc|
        if desc
          scaled_font_description(desc).then { |scaled| EditorUtils.font_description_to_css(scaled) }
        else
          "font-family:monospace;font-size:#{[1, DEFAULT_FONT_SIZE + @font_scale].max}pt;"
        end
      end
    end

    # Zooming adds points to the configured size rather than multiplying it,
    # and never goes below 1pt.
    def scaled_font_description(desc)
      desc.dup.tap do |scaled|
        scaled.size = [1, base_font_size + @font_scale].max * Pango::SCALE
      end
    end

    def base_font_size
      size = @font_desc&.size.to_i / Pango::SCALE
      size.positive? ? size : DEFAULT_FONT_SIZE
    end

    # A tab stop every tab_width characters wide, measured in the view's own
    # font by laying out that many spaces.
    def update_tab_stops
      create_pango_layout(' ' * @tab_width).size.first.then do |width|
        if width.positive?
          self.tabs = Pango::TabArray.new(1, false).tap { |tabs| tabs.set_tab(0, :left, width) }
        end
      end
    end

    def insert_indent
      if @insert_spaces_instead_of_tabs
        buffer.insert_at_cursor(' ' * effective_indent_width)
        true
      else
        false
      end
    end

    def insert_newline_with_indent
      if @auto_indent
        buffer.insert_at_cursor("\n#{current_indentation}")
        scroll_to_insert
        true
      else
        false
      end
    end

    def current_indentation
      buffer.get_iter_at(offset: buffer.cursor_position).then do |iter|
        buffer.get_iter_at(line: iter.line).then do |start|
          buffer.get_text(start, iter, true)[/\A[ \t]*/]
        end
      end
    end

    # The bounds of the current line, or of every line an existing selection
    # touches. A selection that already spans whole lines is left alone, which
    # is how repeated Ctrl+L behaves upstream.
    def line_bounds
      (buffer.selection_bounds || [cursor_iter, cursor_iter]).then do |(from, to)|
        if from.starts_line && to.starts_line && from.line != to.line
          [from, to]
        else
          [buffer.get_iter_at(line: from.line),
           buffer.get_iter_at(line: [to.line + 1, buffer.line_count - 1].min).then do |iter|
             to.line + 1 > buffer.line_count - 1 ? buffer.end_iter : iter
           end
]
        end
      end
    end

    def cursor_iter = buffer.get_iter_at(offset: buffer.cursor_position)
end
