# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_preferences_font'
require_relative 'editor_preferences_radio'
require_relative 'editor_preferences_spin'
require_relative 'editor_preferences_switch'

# EditorPreferencesDialog is the application's preferences window.
#
# Ported from upstream's src/editor-preferences-dialog.c and
# src/editor-preferences-dialog.ui. The page, its group titles and the rows'
# labels and mnemonics are the template's. The rows upstream shows for
# GtkSourceView features — the style-scheme gallery, the overview map, line
# numbers, the right-margin line, the background grid, current-line
# highlighting, spell checking and snippets — are not here, because this port
# edits in a GtkTextView and those settings would do nothing; the keys stay in
# the schema. The "Clear History" group is the one upstream puts at the
# bottom, wired to the same app.clear-history action.
class EditorPreferencesDialog < Adwaita::PreferencesDialog
  INDENT_CHOICES = { 'space' => 'Space', 'tab' => 'Tab' }.freeze
  TAB_WIDTH_RANGE = (1..32)
  INDENT_WIDTH_RANGE = (-1..32)
  LINE_HEIGHT_RANGE = (0.5..10.0)
  AUTO_SAVE_RANGE = (1..300)

  def initialize(settings)
    super()

    @settings = settings
    self.title = 'Preferences'
  end

  def build
    tap do
      add(page)

      page.tap do |prefs|
        prefs.add(appearance_group)
        prefs.add(font_group)
        prefs.add(indentation_group)
        prefs.add(wrap_group)
        prefs.add(behavior_group)
      end

      appearance_group.add(style_variant_row)

      font_group.tap do |group|
        group.add(use_system_font_row)
        group.add(custom_font_row)
        group.add(line_height_row)
      end

      indentation_group.tap do |group|
        group.add(auto_indent_row)
        group.add(indent_character_row)
        group.add(tab_width_row)
        group.add(indent_width_row)
      end

      wrap_group.add(wrap_text_row)

      behavior_group.tap do |group|
        group.add(restore_session_row)
        group.add(auto_save_delay_row)
      end

      use_system_font_row.signal_connect('notify::active') { update_font_sensitivity }
      update_font_sensitivity
    end
  end

  def page
    @page ||= Adwaita::PreferencesPage.new.tap do |prefs|
      prefs.title = 'Preferences'
      prefs.icon_name = 'preferences-system-symbolic'
    end
  end

  def appearance_group
    @appearance_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Appearance' }
  end

  def font_group = @font_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Font' }

  def indentation_group
    @indentation_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Indentation' }
  end

  def wrap_group = @wrap_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Line Wrap' }

  def behavior_group
    @behavior_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Behavior' }
  end

  def style_variant_row
    @style_variant_row ||= EditorPreferencesRadio.new(

      '_Style Variant',

      @settings,

      'style-variant',
      { 'follow' => 'Follow System Style', 'light' => 'Light Style', 'dark' => 'Dark Style' },

    )
  end

  def use_system_font_row
    @use_system_font_row ||= EditorPreferencesSwitch.new('Use _System Monospace Font', @settings, 'use-system-font')
  end

  def custom_font_row = @custom_font_row ||= EditorPreferencesFont.new('Custom _Font', @settings, 'custom-font')

  def line_height_row
    @line_height_row ||= EditorPreferencesSpin.new(

      'Line _Height',

      @settings,

      'line-height',
      LINE_HEIGHT_RANGE,

      step:   0.1,
      digits: 2,
    )
  end

  def auto_indent_row = @auto_indent_row ||= EditorPreferencesSwitch.new('A_uto Indentation', @settings, 'auto-indent')

  def indent_character_row
    @indent_character_row ||= EditorPreferencesRadio.new(
      '_Character',
      @settings,
      'indent-style',
      INDENT_CHOICES,
    )
  end

  def tab_width_row
    @tab_width_row ||= EditorPreferencesSpin.new(
      'Spaces Per _Tab',
      @settings,
      'tab-width',
      TAB_WIDTH_RANGE,
    )
  end

  def indent_width_row
    @indent_width_row ||= EditorPreferencesSpin.new(

      'Spaces Per _Indent',

      @settings,

      'indent-width',
      INDENT_WIDTH_RANGE,
    )
  end

  def wrap_text_row
    @wrap_text_row ||= EditorPreferencesSwitch.new('_Wrap Lines Automatically (Alt+W)', @settings, 'wrap-text')
  end

  def restore_session_row
    @restore_session_row ||= EditorPreferencesSwitch.new('_Restore Session', @settings, 'restore-session')
  end

  def auto_save_delay_row
    @auto_save_delay_row ||= EditorPreferencesSpin.new(

      'Auto Save _Delay (Seconds)',

      @settings,
      'auto-save-delay',

      AUTO_SAVE_RANGE,
    )
  end

  private

    # The custom font and its line height only matter when the system font is
    # not in use, which is how upstream's template gates them.
    def update_font_sensitivity
      (!use_system_font_row.active?).then do |custom|
        custom_font_row.sensitive = custom
        line_height_row.sensitive = custom
      end
    end
end
