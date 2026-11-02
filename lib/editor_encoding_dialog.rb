# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_encoding_model'
require_relative 'editor_encoding_row'

# EditorEncodingDialog lets a document be reloaded in a different character
# set.
#
# Ported from upstream's src/editor-encoding-dialog.c and
# src/editor-encoding-dialog.ui: an AdwDialog titled "Change Encoding" with a
# search bar over a list of every encoding, a "No Results Found" status page
# for an empty search, and a "document.encoding" action that sets the
# encoding and reloads the document.
class EditorEncodingDialog < Adwaita::Dialog
  def initialize(document)
    super()

    @document = document
    self.title = 'Change Encoding'
    self.content_width = 450
    self.content_height = 550
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

      insert_action_group('document', document_actions)

      search_entry.signal_connect('search-changed') { filter }

      filter
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def search_bar = @search_bar ||= Gtk::SearchBar.new.tap { |bar| bar.search_mode = true }

  def search_clamp = @search_clamp ||= Adwaita::Clamp.new.tap { |clamp| clamp.maximum_size = 400 }

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.hexpand = true
      entry.placeholder_text = 'Search encodings'
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

  def rows
    @rows ||= EditorEncodingModel.default.items.map { |encoding| EditorEncodingRow.new(encoding) }
  end

  private

    def document_actions
      @document_actions ||= Gio::SimpleActionGroup.new.tap do |group|
        group.add_action(
          Gio::SimpleAction.new('encoding', GLib::VariantType.new('s')).tap do |action|
            action.signal_connect('activate') { |_action, parameter| apply(parameter.get_string) }
          end,
        )
      end
    end

    # Setting the encoding and reloading is what upstream's
    # editor_encoding_dialog_set_encoding does; a document with no file has
    # nothing to re-decode, so only the encoding changes.
    def apply(charset)
      EditorEncodingModel.default.get(charset)&.then do |encoding|
        @document.encoding = encoding
        if @document.file
          @document.load(encoding: encoding)
        end
        close
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
