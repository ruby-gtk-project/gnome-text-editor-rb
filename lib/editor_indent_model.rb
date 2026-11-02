# frozen_string_literal: true

require 'adwaita'

# EditorIndent is "Space" or "Tab"; EditorIndentModel is the two-item list the
# properties panel and preferences dialog choose between.
#
# Ported from upstream's src/editor-indent-model.c.
class EditorIndent
  attr_reader :name, :index

  def initialize(name, insert_spaces_instead_of_tabs, index)
    @name = name
    @insert_spaces_instead_of_tabs = insert_spaces_instead_of_tabs
    @index = index
  end

  def insert_spaces_instead_of_tabs? = @insert_spaces_instead_of_tabs

  # The GSettings "indent-style" nick for this item.
  def style = @insert_spaces_instead_of_tabs ? 'space' : 'tab'
end

class EditorIndentModel
  ITEMS = [['Space', true], ['Tab', false]].freeze

  def self.default = @default ||= new

  def initialize
    @items = ITEMS.each_with_index.map { |(name, spaces), index| EditorIndent.new(name, spaces, index) }
  end

  attr_reader :items

  def n_items = @items.length

  def get_item(position) = @items[position]

  # Upstream's editor_indent_get_index_for: spaces first, tabs second.
  def self.index_for(insert_spaces) = insert_spaces ? 0 : 1

  def self.for_style(style) = default.items[index_for(style == 'space')]

  def string_list = Gtk::StringList.new(@items.map(&:name))
end
