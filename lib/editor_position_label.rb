# frozen_string_literal: true

require 'adwaita'

# EditorPositionLabel is the "Ln 12 Col 4" overlay that appears over the text
# while the cursor is moving.
#
# Ported from upstream's src/editor-position-label.c and
# src/editor-position-label.ui. Upstream is a GtkWidget with a bin layout and a
# template; this port is a GtkBox with the same four labels, and carries the
# style as a CSS class because the Ruby bindings cannot set a widget class's
# CSS name.
class EditorPositionLabel < Gtk::Box
  CSS_CLASS = 'positionlabel'
  LINE_WIDTH_CHARS = 3

  def initialize
    super(:horizontal, 0)

    add_css_class(CSS_CLASS)
    add_css_class('numeric')
  end

  def build
    tap do
      append(line_prefix)
      append(line)
      append(column_prefix)
      append(column)
    end
  end

  def set_position(line, column)
    tap do
      self.line.label = "#{line}, "
      self.column.label = column.to_s
    end
  end

  # Translators: Ln is short for "Line Number", Col for "Column" — the same
  # abbreviations upstream's template uses.
  def line_prefix
    @line_prefix ||= Gtk::Label.new('Ln').tap { |label| label.margin_end = 3 }
  end

  def column_prefix
    @column_prefix ||= Gtk::Label.new('Col').tap { |label| label.margin_end = 3 }
  end

  def line = @line ||= numeric_label

  def column = @column ||= numeric_label

  private

    # Tabular figures and a fixed width, so the overlay does not jitter as the
    # numbers change.
    def numeric_label
      Gtk::Label.new.tap do |label|
        label.width_chars = LINE_WIDTH_CHARS
        label.attributes = Pango::AttrList.new.tap do |attributes|
          attributes.insert(Pango::AttrFontFeatures.new("'tnum'"))
        end
      end
    end
end
