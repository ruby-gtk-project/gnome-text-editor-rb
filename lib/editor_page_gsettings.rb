# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_page_settings_provider'

# EditorPageGsettings is the bottom of the settings stack: the values the user
# chose in Preferences, which apply to every document that nothing more
# specific has an opinion about.
#
# Ported from upstream's src/editor-page-gsettings.c. Upstream reads a
# GSettings directly and re-reads on its "change-event"; this port reads
# EditorSettings, which is the same keys over either GSettings or the JSON
# fallback, and listens to its per-key notifications instead. Upstream's
# get_custom_font answers "the font is nothing" when use-system-font is set,
# which in this port's protocol is the same nil that means "no opinion": there
# is no provider below this one, so either way the page is left with no font of
# its own and falls back to the system monospace.
class EditorPageGsettings < EditorPageSettingsProvider
  # The keys whose change should make the stack re-read this provider.
  WATCHED = %w[
    auto-indent
    custom-font
    highlight-current-line
    highlight-matching-brackets
    indent-style
    indent-width
    right-margin-position
    show-grid
    show-line-numbers
    show-map
    show-right-margin
    style-scheme
    style-variant
    tab-width
    use-system-font
    wrap-text
  ].freeze

  def initialize(settings)
    super()

    @settings = settings
    WATCHED.each { |key| @settings.on_changed(key) { emit_changed } }
  end

  def custom_font
    if @settings.use_system_font?
      nil
    else
      @settings.custom_font
    end
  end

  def style_scheme = @settings.style_scheme
  def style_variant = @settings.style_variant
  def insert_spaces_instead_of_tabs = @settings.indent_style == 'space'
  def right_margin_position = @settings.right_margin_position
  def show_line_numbers = @settings.show_line_numbers?
  def show_right_margin = @settings.show_right_margin?
  def use_system_font = @settings.use_system_font?
  def wrap_text = @settings.wrap_text?
  def tab_width = @settings.tab_width
  def indent_width = @settings.indent_width
  def show_map = @settings.show_map?
  def show_grid = @settings.show_grid?
  def highlight_current_line = @settings.highlight_current_line?
  def highlight_matching_brackets = @settings.highlight_matching_brackets?
  def auto_indent = @settings.auto_indent?
end
