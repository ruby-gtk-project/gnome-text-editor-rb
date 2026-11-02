# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_preferences_row'

# EditorPreferencesSpin is a preferences row with a spin button bound to a
# numeric settings key.
#
# Ported from upstream's src/editor-preferences-spin.c, which packs a
# GtkSpinButton into an EditorPreferencesRow and takes its range from the
# schema. AdwSpinRow is that row; the range is passed in, because the Ruby
# bindings expose no way to read a key's range back out of the schema.
class EditorPreferencesSpin < Adwaita::SpinRow
  include EditorPreferencesRow

  def initialize(title, settings, key, range, step: 1, digits: 0)
    super(
      Gtk::Adjustment.new(
        settings[key],
        range.first,
        range.last,
        step,
        step,
        0,
      ), step, digits)

    self.title = title
    self.use_underline = true
    self.numeric = true
    bind_setting(settings, key)
    signal_connect('notify::value') { write_setting(digits.zero? ? value.to_i : value) }
  end

  def apply_setting(setting)
    self.value = setting.to_f
  end
end
