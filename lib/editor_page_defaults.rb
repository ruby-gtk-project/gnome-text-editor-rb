# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_page_settings_provider'

# EditorPageDefaults is the built-in per-language house style: PEP 8's 79
# columns and four spaces for Python, the GNU 80/8/2 for C, two spaces for
# Ruby, and so on.
#
# Ported from upstream's src/defaults/editor-page-defaults.c, table and
# citations included. Upstream reads the language from the document's
# GtkSourceLanguage and re-reads on notify::language; this port reads
# EditorDocument#language_id — the identifier the document guesses from its
# file name, since there is no GtkSourceLanguageManager here — and re-reads on
# the document's "language_changed" signal.
class EditorPageDefaults < EditorPageSettingsProvider
  # language id => [right margin position, tab width, indent width, spaces].
  # A right margin of 0 and an indent width below 1 mean "nothing to say",
  # which is how upstream's getters read the same table.
  DEFAULTS = {
    # https://www.python.org/dev/peps/pep-0008/
    'python'   => [79, 4, -1, true],
    'python3'  => [79, 4, -1, true],

    # GNOME/GNU style
    'c'        => [80, 8, 2, true],
    'chdr'     => [80, 8, 2, true],

    # https://llvm.org/docs/CodingStandards.html
    'cpp'      => [80, 8, 2, true],
    'cpphdr'   => [80, 8, 2, true],

    # GNOME JS Style
    'js'       => [80, 4, -1, true],

    # http://www.mono-project.com/community/contributing/coding-guidelines
    'c-sharp'  => [80, 8, -1, false],

    # https://google.github.io/styleguide/javaguide.html
    'java'     => [100, 2, -1, true],

    # https://github.com/rubocop-hq/ruby-style-guide
    'ruby'     => [80, 2, -1, true],

    # https://github.com/rust-lang/rustfmt
    'rust'     => [100, 4, -1, true],

    # Others
    'css'      => [80, 2, -1, true],
    'html'     => [80, 2, -1, true],
    'makefile' => [80, 8, -1, false],
    'meson'    => [80, 2, -1, true],
    'markdown' => [0, 4, -1, true],
    'vala'     => [100, 4, -1, false],
    'xml'      => [80, 2, -1, true],
  }.freeze

  def document=(document)
    unless document.equal?(@document)
      super
      document&.signal_connect('language_changed') { emit_changed }
      emit_changed
    end
  end

  def right_margin_position
    defaults.then do |entry|
      if entry && entry[0].positive?
        entry[0]
      end
    end
  end

  def tab_width = defaults&.at(1)

  def indent_width
    defaults.then do |entry|
      if entry && entry[2].positive?
        entry[2]
      end
    end
  end

  def insert_spaces_instead_of_tabs = defaults&.at(3)

  # Upstream's defaults provider is also where the implicit trailing newline
  # comes from, for every language.
  def implicit_trailing_newline = true

  private

    def defaults = DEFAULTS[@document&.language_id]
end
