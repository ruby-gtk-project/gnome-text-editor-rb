# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_preferences_row'

# EditorPreferencesRadio is a preferences row offering a fixed set of values
# for a string settings key.
#
# Ported from upstream's src/editor-preferences-radio.c, which packs a
# GtkCheckButton per choice into an EditorPreferencesRow and activates the one
# matching the key. AdwComboRow shows the same fixed set in the space a
# preferences dialog has, so this port uses it, with the choices' nicks kept
# alongside their labels.
class EditorPreferencesRadio < Adwaita::ComboRow
  include EditorPreferencesRow

  def initialize(title, settings, key, choices)
    super()

    @choices = choices
    self.title = title
    self.use_underline = true
    self.model = Gtk::StringList.new(choices.values)
    bind_setting(settings, key)
    signal_connect('notify::selected') { write_setting(@choices.keys[selected]) }
  end

  def apply_setting(value)
    @choices.keys.index(value)&.then { |index| self.selected = index }
  end
end
