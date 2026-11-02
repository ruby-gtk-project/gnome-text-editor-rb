# frozen_string_literal: true

require 'adwaita'

# EditorPreferencesRow is the base the preferences rows share: the settings
# key a row reads and writes.
#
# Ported from upstream's src/editor-preferences-row.c, which is an
# AdwActionRow carrying nothing but a "schema-key" property its subclasses
# bind to GSettings. Here the key and the settings object live in a module the
# row classes include, because each of them derives from a different Adwaita
# row type.
module EditorPreferencesRow
  def bind_setting(settings, key)
    tap do
      @settings = settings
      @schema_key = key
      apply_setting(settings[key])
      settings.on_changed(key) { |value| apply_setting(value) }
    end
  end

  attr_reader :settings, :schema_key

  def write_setting(value)
    tap do
      if @settings
        @settings[@schema_key] = value
      end
    end
  end
end
