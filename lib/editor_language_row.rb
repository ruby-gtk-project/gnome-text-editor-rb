# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'

# EditorLanguageRow is one language in the Document Type dialog: a
# GtkSourceLanguage, or nil for Plain Text.
#
# Ported from upstream's src/editor-language-row.c and
# src/editor-language-row.ui: an AdwActionRow titled with the language's name,
# holding a checkmark image the dialog shows only on the selected row, and
# matched against the search filter by its id and its name, both casefolded.
class EditorLanguageRow < Adwaita::ActionRow
  def initialize(language = nil)
    super()

    @language = language
    if language
      self.title = language.name
    else
      self.title = 'Plain Text'
    end
    self.activatable = true
    add_suffix(checkmark)
  end

  attr_reader :language

  def selected=(value)
    checkmark.visible = value
  end

  # The id and name the Document Type dialog's search entry filters on,
  # casefolded as upstream's g_utf8_strdown casefolds them.
  def search_key = "#{@language ? @language.id : 'plaintext'} #{self.title}".downcase

  private

    def checkmark
      @checkmark ||= Gtk::Image.new(icon_name: 'object-select-symbolic').tap do |image|
        image.valign = :center
        image.visible = false
      end
    end
end
