# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'
require 'libspelling'
require_relative 'editor_source_iter'
require_relative 'editor_utils'

# EditorSourceView is the text view a page edits in: the font and zoom, the
# wrap mode, the indentation, and the line-wise editing commands.
#
# Ported from upstream's src/editor-source-view.c. Upstream derives from
# GtkSourceView, and so does this port, via the gtksourceview5 gem — auto
# indent, tab handling, smart home/end, the right-margin line, the current
# line highlight and bracket matching are all real GtkSource::View
# properties here, set straight from the page's settings in
# EditorPage#apply_settings rather than hand-rolled. What this class adds on
# top is the zoom machinery's font override and the Ctrl+arrow/Backspace word
# boundaries from EditorSourceIter, which GtkSourceView does not provide.
class EditorSourceView < GtkSource::View
  type_register

  DEFAULT_FONT_SIZE = 11
  CSS_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION

  def initialize(document)
    super()

    @font_scale = 0
    @font_desc = nil
    @line_height = 1.2
    @zoom_listeners = []

    self.buffer = document
    self.monospace = true
    self.auto_indent = true
    self.insert_spaces_instead_of_tabs = false
    self.tab_width = 8
    self.indent_width = -1
    self.smart_backspace = true
    self.smart_home_end = :before
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
      insert_action_group('spelling', spelling_adapter)
      self.extra_menu = spelling_adapter.menu_model
      buffer.signal_connect('busy_changed') { self.editable = !buffer.loading? }
      update_css
    end
  end

  # Whether misspellings are underlined and offered corrections — upstream's
  # "spellcheck" GSetting, which this port's libspelling adapter answers to
  # directly rather than through anything hand-rolled.
  def spellcheck=(value)
    spelling_adapter.enabled = value
  end

  attr_reader :font_scale, :font_desc

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

    def spelling_adapter
      @spelling_adapter ||= Spelling::TextBufferAdapter.new(buffer, Spelling::Checker.default).tap do |adapter|
        adapter.enabled = false
      end
    end

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

    # Tab, Return and auto-indent are GtkSourceView's own. What is left for
    # this controller is upstream's Ctrl+arrow and Ctrl+Backspace landing on
    # the editor's own word boundaries rather than Pango's — EditorSourceIter,
    # called from word_key_pressed below.
    def key_controller
      @key_controller ||= Gtk::EventControllerKey.new.tap do |controller|
        controller.signal_connect('key-pressed') do |_ctrl, keyval, _code, state|
          if state.control_mask?
            word_key_pressed(keyval, extend: state.shift_mask?)
          else
            false
          end
        end
      end
    end

    # Ctrl+Left and Ctrl+Right move by word, Shift extends the selection the
    # same way, and Ctrl+Backspace and Ctrl+Delete eat the word to either side.
    def word_key_pressed(keyval, extend:)
      case keyval
      when Gdk::Keyval::KEY_Left, Gdk::Keyval::KEY_KP_Left then move_word(-1, extend: extend)
      when Gdk::Keyval::KEY_Right, Gdk::Keyval::KEY_KP_Right then move_word(1, extend: extend)
      when Gdk::Keyval::KEY_BackSpace then delete_word(-1)
      when Gdk::Keyval::KEY_Delete, Gdk::Keyval::KEY_KP_Delete then delete_word(1)
      else false
      end
    end

    # The word boundary on one side of an iter: EditorSourceIter's definition,
    # which counts the underscore as part of an identifier and a run of
    # punctuation as a word of its own.
    def word_boundary(iter, direction)
      if direction.negative?
        EditorSourceIter.backward_visible_word_start(iter)
      else
        EditorSourceIter.forward_visible_word_end(iter)
      end
    end

    def move_word(direction, extend:)
      word_boundary(cursor_iter, direction).then do |target|
        if extend
          buffer.move_mark(buffer.get_mark('insert'), target)
        else
          buffer.place_cursor(target)
        end
      end
      scroll_to_insert
      true
    end

    # A selection goes first, which is what every other delete key does; with
    # none, the word to one side of the cursor goes.
    def delete_word(direction)
      if editable?
        if buffer.selection_bounds
          buffer.delete_selection(true, true)
        else
          delete_to_word_boundary(direction)
        end
        scroll_to_insert
        true
      else
        false
      end
    end

    def delete_to_word_boundary(direction)
      cursor_iter.then do |iter|
        word_boundary(iter, direction).then do |target|
          buffer.begin_user_action
          buffer.delete(iter, target)
          buffer.end_user_action
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

    # The font and the line height reach a GtkSourceView through CSS, which is
    # also how upstream applies them. Tab width, indent width and auto-indent
    # are GtkSource::View's own properties now, not CSS.
    def update_css
      css_provider.load(data: "textview.#{css_class}{#{font_css}line-height:#{@line_height};}")
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
