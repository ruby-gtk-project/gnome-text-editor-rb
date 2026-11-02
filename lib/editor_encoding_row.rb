# frozen_string_literal: true

require 'adwaita'

# EditorEncodingRow is one encoding in the Change Encoding dialog.
#
# Ported from upstream's src/editor-encoding-row.c and
# src/editor-encoding-row.ui: an AdwActionRow titled with the encoding's name
# that activates the "document.encoding" action with the charset as its
# target.
class EditorEncodingRow < Adwaita::ActionRow
  def initialize(encoding)
    super()

    @encoding = encoding
    self.title = encoding.name
    self.activatable = true
    self.action_name = 'document.encoding'
    self.action_target = GLib::Variant.new(encoding.charset)
  end

  attr_reader :encoding

  # The text the dialog's search field filters on, casefolded as upstream
  # casefolds it.
  def search_key = "#{@encoding.charset} #{@encoding.region}".downcase
end
