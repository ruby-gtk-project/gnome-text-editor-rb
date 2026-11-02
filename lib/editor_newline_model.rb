# frozen_string_literal: true

require 'adwaita'

# EditorNewline names one line-ending convention; EditorNewlineModel is the
# fixed list of the three the editor offers.
#
# Ported from upstream's src/editor-newline-model.c. Upstream's EditorNewline
# wraps a GtkSourceNewlineType and the model is a singleton GListModel so a
# combo row can bind to it. There is no GtkSourceView in this port, so the
# newline type is the literal line terminator, and the list is exposed both as
# plain Ruby objects and, for AdwComboRow, as a GtkStringList of the names.
class EditorNewline
  attr_reader :terminator, :name, :index

  def initialize(terminator, name, index)
    @terminator = terminator
    @name = name
    @index = index
  end

  # Rewrites text so every line ends with this convention. Used when saving.
  def apply(text) = text.gsub(/\r\n|\r|\n/, @terminator)
end

# The model is a singleton upstream so that every combo row shares one list and
# the indexes line up; `.default` serves the same purpose here.
class EditorNewlineModel
  ITEMS = [
    ["\n", 'Unix/Linux (LF)'],
    ["\r\n", 'Windows (CR+LF)'],
    ["\r", 'Mac OS Classic (CR)'],
  ].freeze

  INVALID_POSITION = Gtk::INVALID_LIST_POSITION

  def self.default = @default ||= new

  def initialize
    @items = ITEMS.each_with_index.map { |(terminator, name), index| EditorNewline.new(terminator, name, index) }
  end

  attr_reader :items

  def n_items = @items.length

  def get_item(position) = @items[position]

  # The item for a terminator, so a document's detected line ending can be
  # shown in the properties panel.
  def get(terminator) = @items.find { |item| item.terminator == terminator }

  def lookup(newline) = newline ? newline.index : INVALID_POSITION

  # The names, in list order, for AdwComboRow.
  def string_list = Gtk::StringList.new(@items.map(&:name))

  # Detects which of the three conventions a blob of text uses. Upstream gets
  # this from GtkSourceFileLoader; here the document asks for it directly.
  def self.detect(text)
    if text.include?("\r\n")
      default.get("\r\n")
    elsif text.include?("\r")
      default.get("\r")
    else
      default.get("\n")
    end
  end
end
