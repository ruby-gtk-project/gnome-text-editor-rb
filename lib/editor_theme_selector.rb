# frozen_string_literal: true

require 'adwaita'

# EditorThemeSelector is the three-circle light/dark/follow picker at the top
# of the main menu.
#
# Ported from upstream's src/editor-theme-selector.c and
# src/editor-theme-selector.ui. The three check buttons share a group and each
# carries the "settings.style-variant" action with its own string target, so
# the GSettings key is what actually selects the variant — exactly as
# upstream's template does. The styling is in data/style.css.
class EditorThemeSelector < Gtk::Box
  CSS_CLASS = 'themeselector'

  # The nicks the GSettings "style-variant" key allows, with the tooltip
  # upstream gives each. Upstream also sets an accessible label per button;
  # the Ruby bindings cannot marshal an array of GtkAccessibleProperty, so the
  # tooltip is what names the button, which is what GTK falls back to anyway.
  VARIANTS = [
    ['follow', 'Follow System Style'],
    ['light', 'Light Style'],
    ['dark', 'Dark Style'],
  ].freeze

  def initialize
    super(:horizontal, 12)

    add_css_class(CSS_CLASS)
    self.hexpand = true
  end

  def build
    tap do
      buttons.each_value { |button| append(button) }

      buttons['light'].tap do |first|
        buttons['follow'].group = first
        buttons['dark'].group = first
      end
    end
  end

  # The check buttons, keyed by the variant nick, so the menu can hand one to
  # the group and the rest follow.
  def buttons
    @buttons ||= VARIANTS.to_h do |(nick, tooltip)|
      [nick, variant_button(nick, tooltip)]
    end
  end

  private

    def variant_button(nick, tooltip)
      Gtk::CheckButton.new.tap do |button|
        button.add_css_class('theme-selector')
        button.add_css_class(nick)
        button.hexpand = true
        button.halign = :center
        button.focus_on_click = false
        button.tooltip_text = tooltip
        button.action_name = 'settings.style-variant'
        button.action_target = GLib::Variant.new(nick)
      end
    end
end
