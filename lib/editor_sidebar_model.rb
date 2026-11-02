# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_sidebar_item'

# EditorSidebarModel is the recent-documents list behind the Open popover:
# every open page, every unsaved draft and every file the session has seen,
# newest first, filtered by what the user types into the popover's search.
#
# Ported from upstream's src/editor-sidebar-model.c. Upstream implements
# GListModel directly over a GSequence sorted by age, and emits items-changed
# as pages come and go. A Ruby class cannot implement GListModel, so this port
# keeps the sorted sequence in Ruby and mirrors it into a GioListStore of small
# GObject boxes, which is what the GtkListView in the popover binds to. The
# dedup rules are upstream's: one row per draft id, per open document, and per
# file.
class EditorSidebarModel
  # A GListModel's items must be GObjects, and EditorSidebarItem is a plain
  # Ruby object, so each item travels to the list view inside one of these.
  class Row < GLib::Object
    type_register

    attr_accessor :item
  end

  def initialize(&on_changed)
    @items = []
    @on_changed = on_changed
    @search = nil
    @store = Gio::ListStore.new(Row.gtype)
  end

  attr_reader :items, :store, :search

  def n_items = visible.length

  def get_item(position) = visible[position]

  # The popover's search text, casefolded the way upstream casefolds its
  # keywords. Setting it re-filters and re-sorts the mirrored store.
  def search=(text)
    text.to_s.strip.downcase.then do |needle|
      if needle.empty?
        @search = nil
      else
        @search = needle
      end
      invalidate
    end
  end

  # Adds a row for an open page, reusing the row that already stands for its
  # draft, document or file so a file does not appear twice.
  def add_page(page)
    (find_by_draft_id(page.document.draft_id) ||
     find_by_file(page.document.file) ||
     add(EditorSidebarItem.new(age: Time.now))).tap do |item|
      item.page = page
      item.age = Time.now
      invalidate
    end
  end

  # Detaches the page but keeps the row: a document that has been closed is
  # still a recent document.
  def remove_page(page)
    find_by_page(page)&.tap do |item|
      item.title = page.title
      item.page = nil
      item.age = Time.now
      invalidate
    end
  end

  def add_file(file, age: Time.now)
    (find_by_file(file) || add(EditorSidebarItem.new(file: file))).tap do |item|
      item.age = age
      invalidate
    end
  end

  def add_draft(draft_id, title: nil, file: nil, age: Time.now)
    (find_by_draft_id(draft_id) ||
     add(EditorSidebarItem.new(draft_id: draft_id, file: file))).tap do |item|
      if title
        item.title = title
      end
      item.age = age
      invalidate
    end
  end

  def remove_item(item)
    tap do
      @items.delete(item)
      invalidate
    end
  end

  def remove_draft(draft_id) = find_by_draft_id(draft_id).then { |item| item ? remove_item(item) : self }

  def remove_file(file) = find_by_file(file).then { |item| item ? remove_item(item) : self }

  def remove_document(document)
    find_by_draft_id(document.draft_id).then { |item| item ? remove_item(item) : self }
  end

  def clear
    tap do
      @items.reject! { |item| item.page.nil? }
      invalidate
    end
  end

  def find_by_page(page) = @items.find { |item| item.page.equal?(page) }

  def find_by_file(file)
    file&.then { |needle| @items.find { |item| item.file && item.file.uri == needle.uri } }
  end

  def find_by_draft_id(draft_id)
    draft_id&.then { |needle| @items.find { |item| item.draft_id == needle } }
  end

  # Re-reads the items, re-applies the search and pushes the result into the
  # GioListStore the view is watching.
  def invalidate
    tap do
      visible.tap do |rows|
        @store.remove_all
        rows.each { |item| @store.append(Row.new.tap { |row| row.item = item }) }
      end

      @on_changed&.call(self)
    end
  end

  private

    def add(item) = item.tap { @items << item }

    # Search scores order the matches; with no search, age does.
    def visible
      if @search
        @items.filter_map do |item|
          item.match(@search).then do |(matched, score)|
            if matched
              [score, item]
            end
          end
        end
              .sort_by { |(score, item)| [score, -(item.age || Time.at(0)).to_f] }
              .map(&:last)
      else
        @items.sort { |a, b| EditorSidebarItem.compare(a, b) }
      end
    end
end
