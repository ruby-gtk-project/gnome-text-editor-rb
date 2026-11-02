# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_preferences_row'

# EditorPreferencesFont is the row that picks the editor's font.
#
# Ported from upstream's src/editor-preferences-font.c, which draws a preview
# of the font inside the row and opens a GtkFontChooser when activated.
# GtkFontDialogButton is GTK 4's font chooser and shows the font's own name in
# its own face, so this port puts one in an AdwActionRow.
class EditorPreferencesFont < Adwaita::ActionRow
  include EditorPreferencesRow

  def initialize(title, settings, key)
    super()

    self.title = title
    self.use_underline = true
    bind_setting(settings, key)
    add_suffix(button)
    self.activatable_widget = button
    button.signal_connect('notify::font-desc') { write_setting(button.font_desc.to_s) }
  end

  def button
    @button ||= Gtk::FontDialogButton.new(Gtk::FontDialog.new).tap do |widget|
      widget.valign = :center
      widget.level = :font
    end
  end

  def apply_setting(value)
    Pango::FontDescription.new(value.to_s).then do |font_desc|
      unless button.font_desc.to_s == font_desc.to_s
        button.font_desc = font_desc
      end
    end
  end
end
