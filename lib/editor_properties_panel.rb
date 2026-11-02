# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_encoding_model'
require_relative 'editor_file_manager'
require_relative 'editor_indent_model'
require_relative 'editor_newline_model'
require_relative 'editor_properties'

# EditorPropertiesPanel is the document-properties sidebar: the file's name and
# location, its encoding and line endings, the indentation settings and the
# document's statistics.
#
# Ported from upstream's src/editor-properties-panel.c and
# src/editor-properties-panel.ui. The rows, their order, their titles and
# their mnemonics are the template's; the bindings the template writes as
# <lookup> expressions are the #refresh method here, because the Ruby bindings
# offer no GtkExpression. The combo rows take their names from
# GtkStringLists built by the three models, since AdwComboRow needs a
# GListModel and the model objects are plain Ruby.
class EditorPropertiesPanel < Adwaita::PreferencesPage
  def initialize
    super

    @properties = EditorProperties.new { refresh }
  end

  def build
    tap do
      add(file_group)
      add(editing_group)
      add(statistics_group)

      file_group.tap do |group|
        group.add(name_row)
        group.add(location_row)
        group.add(document_type_row)
        group.add(encoding_row)
        group.add(newline_row)
      end

      editing_group.tap do |group|
        group.add(auto_indent_row)
        group.add(indent_character_row)
        group.add(tab_width_row)
        group.add(indent_width_row)
      end

      statistics_group.tap do |group|
        group.add(lines_row)
        group.add(words_row)
        group.add(characters_row)
        group.add(all_characters_row)
      end

      insert_action_group('properties', panel_actions)

      encoding_row.signal_connect('notify::selected') do
        @properties.encoding_index = encoding_row.selected
      end
      newline_row.signal_connect('notify::selected') do
        @properties.newline_index = newline_row.selected
      end
      indent_character_row.signal_connect('notify::selected') do
        @properties.indent_style_index = indent_character_row.selected
      end
      auto_indent_row.signal_connect('notify::active') do
        @properties.auto_indent = auto_indent_row.active?
      end

      refresh
    end
  end

  attr_reader :properties

  def page=(page)
    @properties.page = page
  end

  # Pushes every value from the model into the rows. One method, because the
  # panel has one source of truth and rebuilding a row would lose its focus.
  def refresh
    tap do
      name_row.subtitle = @properties.name
      name_row.tooltip_text = @properties.name
      location_row.subtitle = @properties.directory
      location_row.tooltip_text = @properties.directory
      location_row.sensitive = @properties.can_open?
      document_type_row.subtitle = @properties.language_name
      encoding_row.selected = @properties.encoding_index
      newline_row.selected = @properties.newline_index
      auto_indent_row.active = @properties.auto_indent?
      indent_character_row.selected = @properties.indent_style_index
      refresh_statistics
    end
  end

  def file_group = @file_group ||= Adwaita::PreferencesGroup.new

  def editing_group = @editing_group ||= Adwaita::PreferencesGroup.new

  def statistics_group
    @statistics_group ||= Adwaita::PreferencesGroup.new.tap { |group| group.title = 'Statistics' }
  end

  def name_row
    @name_row ||= property_row('File Name').tap do |row|
      row.subtitle_selectable = true
    end
  end

  def location_row
    @location_row ||= property_row('Location').tap do |row|
      row.tooltip_text = 'Open in File Manager'
      row.activatable = true
      row.action_name = 'properties.open-folder'
      row.subtitle_lines = 1
      row.add_css_class('location')
      row.add_suffix(
        Gtk::Image.new(icon_name: 'document-open-symbolic').tap do |image|
                image.valign = :center
                image.margin_start = 6
              end,
      )
    end
  end

  # Upstream makes this row activatable and opens the language dialog from it.
  # There is no GtkSourceView in this port, so there is no language to choose;
  # the row reports the document's type and nothing more.
  def document_type_row
    @document_type_row ||= property_row('_Document Type').tap do |row|
      row.use_underline = true
    end
  end

  def encoding_row
    @encoding_row ||= combo_row('_Encoding', EditorEncodingModel.default.string_list).tap do |row|
      row.enable_search = true
      row.search_match_mode = :substring
    end
  end

  def newline_row = @newline_row ||= combo_row('_Line Feed', EditorNewlineModel.default.string_list)

  def indent_character_row = @indent_character_row ||= combo_row('_Character', EditorIndentModel.default.string_list)

  def auto_indent_row
    @auto_indent_row ||= Adwaita::SwitchRow.new.tap do |row|
      row.title = 'A_uto Indentation'
      row.use_underline = true
    end
  end

  def tab_width_row = @tab_width_row ||= spin_row('Spaces Per _Tab', @properties.tab_width)

  def indent_width_row = @indent_width_row ||= spin_row('Spaces Per _Indent', @properties.indent_width)

  def lines_row = @lines_row ||= property_row('Lines')
  def words_row = @words_row ||= property_row('Words')
  def characters_row = @characters_row ||= property_row('Characters, No Spaces')
  def all_characters_row = @all_characters_row ||= property_row('All Characters')

  private

    def panel_actions
      @panel_actions ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(
          Gio::SimpleAction.new('open-folder').tap do |action|
                    action.signal_connect('activate') { open_folder }
                  end,
        )
      end
    end

    def open_folder
      @properties.document&.file&.then { |file| EditorFileManager.show(file) }
    end

    # The statistics object is created the first time the panel asks for it,
    # which is upstream's editor_document_load_statistics.
    def refresh_statistics
      @properties.statistics.then do |statistics|
        if statistics
          lines_row.subtitle = statistics.n_lines.to_s
        else
          lines_row.subtitle = ''
        end
        if statistics
          words_row.subtitle = statistics.n_words.to_s
        else
          words_row.subtitle = ''
        end
        if statistics
          characters_row.subtitle = statistics.n_printable.to_s
        else
          characters_row.subtitle = ''
        end
        if statistics
          all_characters_row.subtitle = statistics.n_chars.to_s
        else
          all_characters_row.subtitle = ''
        end
      end
    end

    def property_row(title)
      Adwaita::ActionRow.new.tap do |row|
        row.title = title
        row.use_markup = false
        row.add_css_class('property')
      end
    end

    def combo_row(title, model)
      Adwaita::ComboRow.new.tap do |row|
        row.title = title
        row.use_underline = true
        row.use_markup = false
        row.model = model
      end
    end

    def spin_row(title, adjustment)
      Adwaita::SpinRow.new(adjustment, 1, 0).tap do |row|
        row.title = title
        row.use_underline = true
        row.numeric = true
      end
    end
end
