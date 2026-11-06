# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'
require_relative 'editor_language_row'

# EditorLanguageDialog lets a document's syntax highlighting be set by hand —
# the Document Type dialog.
#
# Ported from upstream's src/editor-language-dialog.c and
# src/editor-language-dialog.ui: an AdwDialog with a search entry over a list
# of every known GtkSourceLanguage plus "Plain Text", a "No Results Found"
# status page for an empty search, and a "language" property the row
# activation keeps in step with the checkmark. Upstream also lists the
# session's recently-used languages in a group of their own; this port's
# session keeps no such list, so that group is left out and every language
# lives in the one list.
class EditorLanguageDialog < Adwaita::Dialog
  def initialize(language, &on_selected)
    super()

    @on_selected = on_selected
    @selected = nil
    self.title = 'Document Type'
    self.content_width = 350
    self.content_height = 550

    select_language(language)
  end

  def build
    tap do
      self.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.add_top_bar(search_bar)
        view.content = stack
      end

      search_bar.child = search_clamp
      search_clamp.child = search_entry

      stack.tap do |pages|
        pages.add_named(preferences_page, 'list')
        pages.add_named(empty_page, 'empty')
      end

      preferences_page.add(group)
      group.add(list_box)

      rows.each { |row| list_box.append(row) }

      list_box.signal_connect('row-activated') { |_box, row| activate_row(row) }
      search_entry.signal_connect('search-changed') { filter }

      filter
      search_entry.grab_focus
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def search_bar = @search_bar ||= Gtk::SearchBar.new.tap { |bar| bar.search_mode = true }

  def search_clamp = @search_clamp ||= Adwaita::Clamp.new.tap { |clamp| clamp.maximum_size = 400 }

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.hexpand = true
      entry.placeholder_text = 'Search languages'
    end
  end

  def stack = @stack ||= Gtk::Stack.new

  def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

  def empty_page
    @empty_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = 'No Results Found'
      page.icon_name = 'edit-find-symbolic'
    end
  end

  def group = @group ||= Adwaita::PreferencesGroup.new

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |box|
      box.selection_mode = :none
      box.add_css_class('boxed-list')
    end
  end

  # One row per visible GtkSourceLanguage, "Plain Text" first — upstream's
  # own ordering, since gtk_list_box_append is called for nil before the
  # language ids are walked.
  def rows
    @rows ||= [EditorLanguageRow.new] + visible_languages.map { |language| EditorLanguageRow.new(language) }
  end

  private

    def visible_languages
      GtkSource::LanguageManager.default.language_ids.filter_map do |id|
        GtkSource::LanguageManager.default.get_language(id).then do |language|
          unless language.hidden?
            language
          end
        end
      end
    end

    def activate_row(row)
      tap do
        select_row(row)
        @on_selected&.call(row.language)
        close
      end
    end

    # Marks the row matching the document's current language, which is what
    # upstream's editor_language_dialog_set_language does before the dialog is
    # shown.
    def select_language(language)
      tap { select_row(rows.find { |row| row.language&.id == language&.id }) }
    end

    def select_row(row)
      tap do
        @selected&.selected = false
        @selected = row
        @selected&.selected = true
      end
    end

    def filter
      search_entry.text.strip.downcase.then do |needle|
        rows.each { |row| row.visible = needle.empty? || row.search_key.include?(needle) }
        if rows.any?(&:visible?)
          stack.visible_child_name = 'list'
        else
          stack.visible_child_name = 'empty'
        end
      end
    end
end
