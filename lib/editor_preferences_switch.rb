# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_preferences_row'

# EditorPreferencesSwitch is a preferences row with a switch bound to a
# boolean settings key.
#
# Ported from upstream's src/editor-preferences-switch.c, which packs a
# GtkSwitch into an EditorPreferencesRow and binds it to its schema key.
# AdwSwitchRow is that row, so this port uses it.
class EditorPreferencesSwitch < Adwaita::SwitchRow
  include EditorPreferencesRow

  def initialize(title, settings, key)
    super()

    self.title = title
    self.use_underline = true
    bind_setting(settings, key)
    signal_connect('notify::active') { write_setting(active?) }
  end

  def apply_setting(value)
    self.active = value == true
  end
end
