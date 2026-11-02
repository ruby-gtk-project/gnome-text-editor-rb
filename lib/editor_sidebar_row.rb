# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_sidebar_item'

# EditorSidebarRow is one row of the Open popover's recent-documents list.
#
# Ported from upstream's src/editor-sidebar-row.c and
# src/editor-sidebar-row.ui: a grid with the modified dot, the title, the
# directory under it, the relative age at the right and a close button that
# forgets the entry. Upstream binds the labels to the item's properties; this
# port fills them in #item=, because the item is a plain Ruby object.
class EditorSidebarRow < Gtk::Grid
  def initialize
    super

    self.column_spacing = 6
    self.margin_top = 6
    self.margin_bottom = 6
    self.margin_start = 6
    self.margin_end = 6
    @remove_listeners = []
  end

  def build
    tap do
      attach(
        is_modified,
        0,
        0,
        1,
        2,
      )
      attach(
        title,
        1,
        0,
        2,
        1,
      )
      attach(
        subtitle,
        1,
        1,
        1,
        1,
      )
      attach(
        age,
        2,
        1,
        1,
        1,
      )
      attach(
        remove_button,
        3,
        0,
        1,
        2,
      )

      remove_button.signal_connect('clicked') do
        @remove_listeners.each { |listener| listener.call(@item) }
      end
    end
  end

  attr_reader :item

  # Shows an item. Everything the row displays is derived here, so rebinding a
  # recycled row is one call — which is what GtkListView's factory wants.
  def item=(item)
    @item = item

    item&.then do |row_item|
      title.text = row_item.title
      subtitle.text = row_item.subtitle
      age.text = row_item.age_label
      age.visible = !row_item.age_label.empty?
      is_modified.visible = row_item.is_modified? && !row_item.empty?
      self.tooltip_text = row_item.uri || row_item.title
    end
  end

  def on_remove(&block)
    tap { @remove_listeners << block }
  end

  def is_modified
    @is_modified ||= Gtk::Label.new('•').tap do |label|
      label.halign = :center
      label.valign = :baseline
      label.visible = false
    end
  end

  def title
    @title ||= Gtk::Inscription.new.tap do |inscription|
      inscription.xalign = 0
      inscription.text_overflow = :ellipsize_middle
      inscription.hexpand = true
    end
  end

  def subtitle
    @subtitle ||= Gtk::Inscription.new.tap do |inscription|
      inscription.text_overflow = :ellipsize_end
      inscription.min_chars = 25
      inscription.nat_chars = 25
      inscription.hexpand = true
      inscription.min_lines = 1
      inscription.nat_lines = 1
      inscription.xalign = 0
      inscription.add_css_class('caption')
      inscription.add_css_class('dim-label')
    end
  end

  def age
    @age ||= Gtk::Inscription.new.tap do |inscription|
      inscription.valign = :center
      inscription.halign = :end
      inscription.visible = false
      inscription.add_css_class('caption')
      inscription.add_css_class('dim-label')
    end
  end

  def remove_button
    @remove_button ||= Gtk::Button.new.tap do |button|
      button.valign = :center
      button.halign = :end
      button.icon_name = 'window-close-symbolic'
      button.tooltip_text = 'Remove'
      button.add_css_class('circular')
      button.add_css_class('flat')
    end
  end
end
