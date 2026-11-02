# frozen_string_literal: true

require 'adwaita'

# ShortcutsDialog lists the keyboard shortcuts.
#
# Ported from upstream's src/shortcuts-dialog.ui, which is a
# GtkShortcutsWindow of nine sections. GtkShortcutsWindow is deprecated in
# GTK 4, and libadwaita's AdwShortcutsDialog is its replacement, so the same
# sections and the same items are built with that instead. The items upstream
# lists for features this port does not have — the overview map, spell
# checking, incrementing the number at the cursor, toggling the caret, the
# restore-closed-tab command and the GtkSourceView movement commands — are
# left out rather than listed and dead.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    'Windows'        => [
      ['New window', '<Control>n'],
      ['Move document to new window', '<Control><Shift>n'],
      ['Move to next tab', '<Control>Page_Down'],
      ['Move to previous tab', '<Control>Page_Up'],
      ['Reorder after next tab', '<Control><Shift>Page_Down'],
      ['Reorder before previous tab', '<Control><Shift>Page_Up'],
    ],
    'Zoom'           => [
      ['Zoom In', '<Control>plus'],
      ['Zoom Out', '<Control>minus'],
      ['Reset Zoom', '<Control>0'],
    ],
    'Documents'      => [
      ['New document', '<Control>t'],
      ['Browse to open document', '<Control>o'],
      ['Save', '<Control>s'],
      ['Save As', '<Control><Shift>s'],
      ['Find/Replace', '<Control>f'],
      ['Close document', '<Control>w'],
      ['Open document properties', 'F9'],
    ],
    'Copy and Paste' => [
      ['Copy selected text to clipboard', '<Control>c'],
      ['Cut selected text to clipboard', '<Control>x'],
      ['Paste text from clipboard', '<Control>v'],
      ['Copy current line down', '<Control><Alt>d'],
    ],
    'Undo and Redo'  => [
      ['Undo previous command', '<Control>z'],
      ['Redo previous command', '<Control><Shift>z'],
    ],
    'Editing'        => [
      ['Search within the document', '<Control>f'],
      ['Search and replace within the document', '<Control>h'],
      ['Toggle overwrite', 'Insert'],
    ],
    'Selections'     => [
      ['Select all', '<Control>a'],
      ['Select current line', '<Control>l'],
    ],
    'Movements'      => [
      ['Move to beginning of document', '<Control>Home'],
      ['Move to end of document', '<Control>End'],
      ['Go to line', '<Control>i'],
    ],
    'Deletion'       => [
      ['Delete from cursor to word start', '<Control>BackSpace'],
      ['Delete from cursor to word end', '<Control>Delete'],
      ['Delete the current line', '<Control>d'],
    ],
    'General'        => [
      ['Show preferences', '<Control>comma'],
      ['Show keyboard shortcuts', '<Control>question'],
      ['Toggle text wrapping', '<Alt>w'],
    ],
  }.freeze

  def initialize
    super()

    self.title = 'Keyboard Shortcuts'
  end

  def build
    tap do
      SECTIONS.each { |title, items| add(section(title, items)) }
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments — the error a no-argument new raises
    # advertises them as "title: utf8, accelerator: utf8", but keywords fail.
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
