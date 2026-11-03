# frozen_string_literal: true

require 'adwaita'

# EditorPageSettingsProvider is one source of per-document settings: the
# GSettings the user chose, the per-language defaults, an .editorconfig beside
# the file, a modeline inside it. A provider answers only for the settings it
# knows about and says nothing about the rest, so the stack above it can ask
# the next one down.
#
# Ported from upstream's src/editor-page-settings-provider.c, which declares
# this as a GInterface whose getters take an out parameter and return TRUE when
# they filled it. Ruby has no out parameters, so a getter here returns the
# value, or nil to mean "this provider has no opinion" — the same two-state
# answer in one return value. Upstream's "changed" signal is #on_changed, and
# a provider raises it with #emit_changed; a plain object rather than a GObject
# interface, because nothing in the port needs these to be GObjects.
class EditorPageSettingsProvider
  # Every setting the stack asks about, in upstream's interface order.
  KEYS = %i[
    custom_font
    style_scheme
    style_variant
    insert_spaces_instead_of_tabs
    right_margin_position
    show_line_numbers
    show_right_margin
    use_system_font
    wrap_text
    tab_width
    indent_width
    show_map
    show_grid
    highlight_current_line
    highlight_matching_brackets
    auto_indent
    implicit_trailing_newline
  ].freeze

  def initialize
    @document = nil
    @changed_listeners = []
  end

  attr_reader :document

  # Upstream's set_document vfunc: a provider that watches the document hooks
  # it here. The base class only remembers it.
  def document=(document)
    @document = document
  end

  def on_changed(&block)
    tap { @changed_listeners << block }
  end

  def emit_changed
    tap { @changed_listeners.each(&:call) }
  end

  # The default answer to every setting is "no opinion".
  KEYS.each do |key|
    define_method(key) { nil }
  end
end
