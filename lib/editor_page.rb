# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_document'
require_relative 'editor_info_bar'
require_relative 'editor_page_actions'
require_relative 'editor_page_settings'
require_relative 'editor_path'
require_relative 'editor_position_label'
require_relative 'editor_search_bar'
require_relative 'editor_source_map'
require_relative 'editor_source_view'
require_relative 'editor_utils'

# EditorPage is one tab: the document, the view it is edited in, the info bar
# above it and the search and goto-line bars below it.
#
# Ported from upstream's src/editor-page.c and src/editor-page.ui. Upstream
# notifies the window of title, subtitle and modified changes through GObject
# properties; this port calls listeners registered with #on_changed, which is
# the same notification with less ceremony. The horizontal box upstream puts
# the view and the overview map in holds both here too, the map built from
# EditorSourceMap and shown only when the "show-map" setting is on.
class EditorPage < Gtk::Box
  def initialize(document, settings)
    super(:vertical, 0)

    @document = document
    @settings = settings
    @changed_listeners = []
    @actions = EditorPageActions.new(self)
  end

  attr_reader :document, :window

  def window=(window)
    @window = window
  end

  # Assembles the page and connects the document to the parts that display it.
  def build
    tap do
      append(info_bar.build)
      append(toolbar_view)

      toolbar_view.tap do |view|
        view.content = overlay

        overlay.tap do |container|
          container.child = view_box
          container.add_overlay(progress_bar)
          container.add_overlay(position_label.build)

          view_box.append(scroller)
          scroller.child = source_view.build
          view_box.append(source_map.build)
        end

        view.add_bottom_bar(bottom_box)

        bottom_box.tap do |box|
          box.append(goto_line_revealer)
          box.append(search_revealer)

          goto_line_revealer.child = goto_line_box

          goto_line_box.tap do |line_box|
            line_box.append(goto_line_label)
            line_box.append(goto_line_entry)
            line_box.append(goto_line_button)
          end

          search_revealer.child = search_clamp
          search_clamp.child = search_bar.build
        end
      end

      @actions.build

      page_settings.on_changed { |changed| apply_settings(changed) }
      page_settings.build
      apply_settings(EditorPageSettings::KEYS)

      # "spellcheck" is upstream's own GSetting, outside the per-document
      # settings stack — the one it applies straight from EditorSettings.
      source_view.spellcheck = @settings.spellcheck?
      @settings.on_changed('spellcheck') { source_view.spellcheck = @settings.spellcheck? }

      connect_document
      search_bar.bind_document(@document)
      search_bar.on_state_changed { @actions.update }
      goto_line_entry.signal_connect('activate') { goto_line }

      # Without this, the header bar's zoom percentage button never follows
      # the zoom buttons, the Ctrl+scroll gesture or the Ctrl+plus/minus
      # shortcuts: EditorSourceView#zoom only calls its own @zoom_listeners,
      # and nothing was connecting one, so the button's label only happened
      # to look right after some unrelated update_state (switching tabs,
      # opening a file) coincidentally repainted it.
      source_view.on_zoom_changed { @changed_listeners.each { |listener| listener.call(self) } }
      info_bar.on_retry { @document.load { update_state } }
      info_bar.on_use_admin { @document.use_admin }
      info_bar.on_discard { discard_changes }
      info_bar.on_save { activate_action('page.save', nil) }

      EditorUtils.revealer_auto_hide(goto_line_revealer)
      EditorUtils.revealer_auto_hide(search_revealer)

      update_state
    end
  end

  def on_changed(&block)
    tap { @changed_listeners << block }
  end

  def title = @document.title

  # The directory the file lives in, collapsed to "~/…" — what the window
  # shows under the title.
  def subtitle
    @document.file&.parent&.then { |directory| EditorPath.collapse(directory.path || directory.uri) }.to_s
  end

  def modified? = @document.modified?

  def view = source_view

  # Raises this page's tab in its window and focuses the text.
  def raise_page
    tap do
      @window&.visible_page = self
      grab_focus
    end
  end

  def grab_focus = source_view.grab_focus

  # Where the cursor and selection are, as the session records them.
  def selection_state
    @document.selection_bounds.then do |bounds|
      (bounds || [cursor_iter, cursor_iter]).then do |(from, to)|
        { 'begin' => [from.line, from.line_offset], 'end' => [to.line, to.line_offset] }
      end
    end
  end

  def selection_state=(state)
    state&.then do |saved|
      @document.select_range(iter_from_state(saved['begin']), iter_from_state(saved['end']))
      scroll_to_insert
    end
  end

  # The one-based position the goto-line bar and the statusbar show.
  def visual_position = @document.cursor_line_column

  def report_load_error(error)
    tap do
      @document.then { update_state }
      error
    end
  end

  # Opens the search bar, seeding it with the selection the way upstream does,
  # and moves to the first match.
  def begin_search(replace: false, text: nil)
    tap do
      goto_line_revealer.reveal_child = false
      search_bar.replace_mode = replace
      search_bar.search_text = text || selected_text || search_bar.search_text
      search_revealer.reveal_child = true
      search_bar.grab_focus
      search_bar.move_first
    end
  end

  def hide_search
    tap do
      search_revealer.reveal_child = false
      search_bar.unbind
      search_bar.bind_document(@document)
    end
  end

  def move_next_search
    tap do
      search_bar.move_next
      scroll_to_insert
    end
  end

  def move_previous_search
    tap do
      search_bar.move_previous
      scroll_to_insert
    end
  end

  def show_goto_line
    tap do
      hide_search
      goto_line_entry.text = visual_position.first.to_s
      goto_line_revealer.reveal_child = true
      goto_line_entry.grab_focus
    end
  end

  # Accepts "12" and "12:34", as upstream's sscanf does.
  def goto_line
    tap do
      goto_line_entry.text.scan(/\d+/).map(&:to_i).then do |(line, column)|
        if line
          jump_to(line - 1, column ? column - 1 : 0, skip_whitespace: column.nil?)
        end
      end

      goto_line_revealer.reveal_child = false
      grab_focus
    end
  end

  def scroll_to_insert
    tap { source_view.scroll_to_insert }
  end

  def discard_changes
    tap do
      @document.discard_changes
      update_state
    end
  end

  # Pushes the document's current state into the info bar, the progress bar and
  # the page's listeners — the window's title and the sidebar row both hang off
  # this.
  def update_state
    tap do
      info_bar.update(@document)
      progress_bar.visible = @document.busy?
      progress_bar.fraction = @document.busy_progress
      source_view.editable = !@document.loading?
      @changed_listeners.each { |listener| listener.call(self) }
    end
  end

  def zoom_in = source_view.zoom(1)
  def zoom_out = source_view.zoom(-1)
  def zoom_one = source_view.zoom(0)
  def zoom_level = source_view.zoom_level

  # Copies the whole document to the clipboard: upstream's page.copy-all.
  # Gdk::Clipboard#set takes the value, and a Ruby String arrives as text.
  def copy_all
    tap { clipboard.set(@document.text) }
  end

  def source_view = @source_view ||= EditorSourceView.new(@document)

  def source_map
    @source_map ||= EditorSourceMap.new.tap do |map|
      map.visible = false
      map.view = source_view
    end
  end

  # The settings this document is edited under: the user's preferences, under
  # whatever its language, its .editorconfig and its modelines have to say.
  def page_settings = @page_settings ||= EditorPageSettings.new(@document, settings: @settings)

  def info_bar = @info_bar ||= EditorInfoBar.new

  def search_bar = @search_bar ||= EditorSearchBar.new

  def position_label
    @position_label ||= EditorPositionLabel.new.tap do |label|
      label.visible = false
      label.halign = :end
      label.valign = :end
    end
  end

  def toolbar_view
    @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
      view.vexpand = true
      view.bottom_bar_style = :raised
    end
  end

  def overlay = @overlay ||= Gtk::Overlay.new.tap { |widget| widget.vexpand = true }

  def view_box = @view_box ||= Gtk::Box.new(:horizontal, 0)

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |window|
      window.hexpand = true
      window.vexpand = true
    end
  end

  def progress_bar
    @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
      bar.add_css_class('osd')
      bar.can_focus = false
      bar.halign = :fill
      bar.hexpand = true
      bar.valign = :start
      bar.vexpand = false
      bar.visible = false
    end
  end

  def bottom_box = @bottom_box ||= Gtk::Box.new(:vertical, 0)

  def goto_line_revealer
    @goto_line_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.reveal_child = false
      revealer.transition_type = :slide_up
    end
  end

  def search_revealer
    @search_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.reveal_child = false
      revealer.transition_type = :slide_up
    end
  end

  def search_clamp = @search_clamp ||= Adwaita::Clamp.new.tap { |clamp| clamp.maximum_size = 500 }

  def goto_line_box
    @goto_line_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.halign = :center
      box.add_css_class('toolbar')
    end
  end

  def goto_line_label
    @goto_line_label ||= Gtk::Label.new('Go to Line').tap do |label|
      label.margin_start = 3
      label.margin_end = 3
      label.add_css_class('heading')
    end
  end

  def goto_line_entry
    @goto_line_entry ||= Gtk::Entry.new.tap do |entry|
      entry.width_chars = 3
      entry.max_width_chars = 7
    end
  end

  def goto_line_button
    @goto_line_button ||= Gtk::Button.new.tap do |button|
      button.label = 'Go'
      button.width_request = 50
      button.action_name = 'page.goto-line'
      button.add_css_class('suggested-action')
    end
  end

  # Every setting upstream binds straight to GtkSourceView and GtkSourceBuffer
  # properties, now that this port's view and buffer are the real things.
  def apply_settings(changed)
    tap do
      changed.each do |key|
        case key
        when :custom_font then apply_font
        when :wrap_text then source_view.wrap_text = page_settings.wrap_text
        when :tab_width then source_view.tab_width = page_settings.tab_width
        when :indent_width then source_view.indent_width = page_settings.indent_width
        when :auto_indent then source_view.auto_indent = page_settings.auto_indent
        when :insert_spaces_instead_of_tabs
          source_view.insert_spaces_instead_of_tabs = page_settings.insert_spaces_instead_of_tabs
        when :show_line_numbers then source_view.show_line_numbers = page_settings.show_line_numbers
        when :show_right_margin then source_view.show_right_margin = page_settings.show_right_margin
        when :right_margin_position then source_view.right_margin_position = page_settings.right_margin_position
        when :show_grid then apply_background_pattern
        when :show_map then source_map.visible = page_settings.show_map
        when :highlight_current_line
          source_view.highlight_current_line = page_settings.highlight_current_line
        when :highlight_matching_brackets
          @document.highlight_matching_brackets = page_settings.highlight_matching_brackets
        when :style_scheme then apply_style_scheme
        end
      end
    end
  end

  private

    # No font of its own leaves the view on the system monospace, which is what
    # upstream's binding does when the custom font is unset.
    def apply_font
      page_settings.custom_font.then do |font|
        if font
          source_view.font_desc = Pango::FontDescription.new(font)
        else
          source_view.font_desc = nil
        end
      end
    end

    def apply_background_pattern
      if page_settings.show_grid
        source_view.background_pattern = :grid
      else
        source_view.background_pattern = :none
      end
    end

    def apply_style_scheme
      page_settings.style_scheme.then do |id|
        @document.style_scheme = id && GtkSource::StyleSchemeManager.default.get_scheme(id)
      end
      update_state
    end

    def clipboard = Gdk::Display.default.clipboard

    def connect_document
      @document.signal_connect('cursor_moved') { flash_position }
      @document.signal_connect('title_changed') { update_state }
      @document.signal_connect('busy_changed') { update_state }
      @document.signal_connect('state_changed') { update_state }
    end

    # The position overlay appears as the cursor moves and fades out again,
    # which is upstream's _editor_widget_hide_with_fade on the same label.
    def flash_position
      visual_position.then do |(line, column)|
        position_label.set_position(line, column)
        position_label.visible = true
        position_label.opacity = 1.0
        EditorUtils.widget_hide_with_fade(position_label)
      end
    end

    def cursor_iter = @document.get_iter_at(offset: @document.cursor_position)

    def iter_from_state(position)
      (position || [0, 0]).then do |(line, offset)|
        @document.get_iter_at(line: line.to_i, line_offset: offset.to_i)
      end
    end

    def selected_text
      @document.selection_bounds&.then do |(from, to)|
        @document.get_text(from, to, true).then { |text| text.include?("\n") ? nil : text }
      end
    end

    # Upstream walks past leading whitespace when only a line was given, so
    # "go to line 12" lands on the first thing on that line.
    def jump_to(line, column, skip_whitespace:)
      @document.get_iter_at(line: line, line_offset: column).then do |iter|
        if skip_whitespace
          iter.forward_char while !iter.end? && !iter.ends_line && iter.char.match?(/[[:space:]]/)
        end

        @document.select_range(iter, iter)
        scroll_to_insert
      end
    end
end
