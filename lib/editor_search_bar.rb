# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_focus_chain'
require_relative 'editor_search_entry'
require_relative 'editor_search_model'
require_relative 'editor_utils'

# EditorSearchBar is the find-and-replace toolbar at the bottom of a page.
#
# Ported from upstream's src/editor-search-bar.c and
# src/editor-search-bar.ui. Upstream drives a GtkSourceSearchContext and
# exposes can-move, can-replace and can-replace-all as properties the page
# binds its actions to; this port drives EditorSearchModel and calls the page
# back, which is the same wiring without GObject properties. The search
# options are the same three — regular expressions, case sensitivity and whole
# word — in the same menu, as stateful actions in a "search-options" group.
class EditorSearchBar < Gtk::Grid
  CSS_CLASS = 'searchbar'

  def initialize
    super

    add_css_class(CSS_CLASS)
    add_css_class('toolbar')
    @state_listeners = []
  end

  def build
    tap do
      attach(
        search_entry.build,
        0,
        0,
        1,
        1,
      )
      attach(
        replace_entry,
        0,
        1,
        1,
        1,
      )
      attach(
        navigation_box,
        1,
        0,
        1,
        1,
      )
      attach(
        replace_mode_button,
        2,
        0,
        1,
        1,
      )
      attach(
        options_button,
        3,
        0,
        1,
        1,
      )
      attach(
        close_button,
        4,
        0,
        1,
        1,
      )
      attach(
        replace_button,
        1,
        1,
        1,
        1,
      )
      attach(
        replace_all_button,
        2,
        1,
        3,
        1,
      )

      insert_action_group('search-options', option_actions)
      add_controller(focus_controller)

      search_entry.on_changed { |text| @model&.search_text = text }
      search_entry.on_activate { move_next }

      replace_mode_button.signal_connect('toggled') { apply_replace_mode }
    end
  end

  attr_reader :model

  # The order Tab walks the bar in, which is upstream's own queue: the two
  # entries, the match buttons, the mode and option buttons, the close button
  # and then the two replace buttons.
  def focus_chain
    [
      search_entry,
      replace_entry,
      move_previous_button,
      move_next_button,
      replace_mode_button,
      options_button,
      close_button,
      replace_button,
      replace_all_button,
    ]
  end

  # Points the bar at a document. Upstream re-targets its search context the
  # same way when the page's document changes.
  def bind_document(document)
    tap do
      @model = EditorSearchModel.new(document) { |model| publish(model) }
      @model.search_text = search_entry.search_text
    end
  end

  def unbind
    tap do
      @model&.clear
      @model = nil
    end
  end

  def on_state_changed(&block)
    tap { @state_listeners << block }
  end

  def can_move? = @model ? @model.can_move? : false
  def can_replace? = @model ? @model.can_replace? : false
  def can_replace_all? = @model ? @model.can_replace_all? : false

  def move_next = @model&.move_next

  def move_previous = @model&.move_previous

  # Used when the bar first opens: show the match after the cursor rather than
  # leaving the user looking at an unhighlighted document.
  def move_first = @model&.move_next

  def replace = @model&.replace(replace_entry.text)

  def replace_all = @model&.replace_all(replace_entry.text)

  def search_text = search_entry.search_text

  def search_text=(text)
    search_entry.search_text = text
  end

  # Opens the bar in replace mode, which is what page.begin-replace does.
  def replace_mode=(enabled)
    replace_mode_button.active = enabled
  end

  def replace_mode? = replace_mode_button.active?

  def grab_focus = search_entry.grab_focus

  def search_entry = @search_entry ||= EditorSearchEntry.new

  def replace_entry
    @replace_entry ||= Gtk::Entry.new.tap do |entry|
      entry.primary_icon_name = 'edit-find-replace-symbolic'
      entry.max_width_chars = 20
      entry.hexpand = true
      entry.visible = false
      entry.placeholder_text = 'Replace'
    end
  end

  def navigation_box
    @navigation_box ||= Gtk::Box.new(:horizontal, 3).tap do |box|
      box.homogeneous = true
      box.hexpand = false
      box.append(move_previous_button)
      box.append(move_next_button)
    end
  end

  def move_previous_button = @move_previous_button ||= flat_button('go-up-symbolic', 'Previous Match')

  def move_next_button = @move_next_button ||= flat_button('go-down-symbolic', 'Next Match')

  def replace_mode_button
    @replace_mode_button ||= Gtk::ToggleButton.new.tap do |button|
      button.icon_name = 'edit-find-replace-symbolic'
      button.tooltip_text = 'Search & Replace'
      button.focus_on_click = false
      button.add_css_class('flat')
    end
  end

  def options_button
    @options_button ||= Gtk::MenuButton.new.tap do |button|
      button.direction = :up
      button.icon_name = 'emblem-system-symbolic'
      button.tooltip_text = 'Search Options'
      button.menu_model = options_menu
      button.add_css_class('flat')
    end
  end

  def close_button
    @close_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'window-close-symbolic'
      button.tooltip_text = 'Close Search'
      button.action_name = 'search.hide'
      button.focus_on_click = false
      button.margin_end = 3
      button.halign = :center
      button.valign = :center
      button.add_css_class('flat')
      button.add_css_class('circular')
    end
  end

  def replace_button
    @replace_button ||= Gtk::Button.new.tap do |button|
      button.label = '_Replace'
      button.use_underline = true
      button.action_name = 'search.replace-one'
      button.focus_on_click = false
      button.can_shrink = true
      button.visible = false
    end
  end

  def replace_all_button
    @replace_all_button ||= Gtk::Button.new.tap do |button|
      button.label = 'Replace _All'
      button.use_underline = true
      button.action_name = 'search.replace-all'
      button.focus_on_click = false
      button.can_shrink = true
      button.visible = false
    end
  end

  def options_menu
    @options_menu ||= Gio::Menu.new.tap do |menu|
      menu.append('Re_gular Expressions', 'search-options.regex')
      menu.append('_Case Sensitive', 'search-options.case-sensitive')
      menu.append('Match Whole _Word Only', 'search-options.match-whole-word')
    end
  end

  private

    # Tab and Shift+Tab walk #focus_chain rather than the packing order.
    # Upstream does this from the widget's focus vfunc, which the Ruby
    # bindings cannot override, so the controller runs in the capture phase
    # and only claims the two keys.
    def focus_controller
      @focus_controller ||= Gtk::EventControllerKey.new.tap do |controller|
        controller.propagation_phase = :capture
        controller.signal_connect('key-pressed') do |_ctrl, keyval, _code, _state|
          case keyval
          when Gdk::Keyval::KEY_Tab then EditorFocusChain.focus_child(self, focus_chain, :tab_forward)
          when Gdk::Keyval::KEY_ISO_Left_Tab then EditorFocusChain.focus_child(self, focus_chain, :tab_backward)
          else false
          end
        end
      end
    end

    def flat_button(icon_name, tooltip)
      Gtk::Button.new.tap do |button|
        button.icon_name = icon_name
        button.tooltip_text = tooltip
        button.hexpand = true
        button.focus_on_click = false
        button.add_css_class('flat')
      end
    end

    # The three search options, as the toggles upstream's menu expects.
    def option_actions
      @option_actions ||= Gio::SimpleActionGroup.new.tap do |group|
        {
          'regex'            => :regex_enabled=,
          'case-sensitive'   => :case_sensitive=,
          'match-whole-word' => :match_whole_word=,
        }.each do |name, setter|
          group.add_action(
            Gio::SimpleAction.new(name, nil, GLib::Variant.new(false)).tap do |action|
              action.signal_connect('activate') do
                (!action.state.get_boolean).tap do |value|
                  action.set_state(GLib::Variant.new(value))
                  @model&.public_send(setter, value)
                end
              end
            end,
          )
        end
      end
    end

    # The replace row only exists in replace mode, which is how upstream's
    # template hides it.
    def apply_replace_mode
      replace_mode?.then do |enabled|
        replace_entry.visible = enabled
        replace_button.visible = enabled
        replace_all_button.visible = enabled
        if enabled
          replace_entry.grab_focus
        end
      end
    end

    def publish(model)
      search_entry.occurrence_count = model.occurrence_count
      search_entry.occurrence_position = model.occurrence_position
      move_previous_button.sensitive = model.can_move?
      move_next_button.sensitive = model.can_move?
      @state_listeners.each { |listener| listener.call(self) }
    end
end
