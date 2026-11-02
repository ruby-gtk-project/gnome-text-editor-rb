# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_sidebar_row'

# EditorOpenPopover is the "Open" button's popover: a search field over the
# recent documents, and a button to browse for a file instead.
#
# Ported from upstream's src/editor-open-popover.c and
# src/editor-open-popover.ui. Upstream builds the rows with a
# GtkBuilderListItemFactory whose template binds EditorSidebarRow to the list
# item; this port uses a GtkSignalListItemFactory, which is how the Ruby
# bindings make rows. The stack that swaps the list for the "No Recent
# Documents" page, the search entry's stop-search handling and activating a
# row to open it are upstream's.
class EditorOpenPopover < Gtk::Popover
  CSS_CLASS = 'open-popover'

  def initialize(model)
    super()

    @model = model
    add_css_class(CSS_CLASS)
    @activate_listeners = []
    @remove_listeners = []
  end

  def build
    tap do
      self.child = box

      box.tap do |container|
        container.append(search_box)
        container.append(Gtk::Separator.new(:horizontal))
        container.append(stack)

        search_box.tap do |row|
          row.append(search_entry)
          row.append(open_button)
        end

        stack.tap do |pages|
          pages.add_named(empty_page, 'empty')
          pages.add_named(recent_scroller, 'recent')
          recent_scroller.child = list_view
        end
      end

      search_entry.tap do |entry|
        entry.signal_connect('changed') do
          @model.search = entry.text
          update_stack
        end
        entry.signal_connect('activate') { activate_first }
        entry.signal_connect('stop-search') { popdown }
      end

      list_view.signal_connect('activate') { |_view, position| activate_position(position) }

      update_stack
    end
  end

  def on_activate(&block)
    tap { @activate_listeners << block }
  end

  def on_remove(&block)
    tap { @remove_listeners << block }
  end

  # Re-reads the model, which the window calls when the session's recents
  # change while the popover is open.
  def refresh
    tap do
      @model.invalidate
      update_stack
    end
  end

  def box = @box ||= Gtk::Box.new(:vertical, 0)

  def search_box
    @search_box ||= Gtk::Box.new(:horizontal, 6).tap do |row|
      row.margin_top = 6
      row.margin_bottom = 6
      row.margin_start = 6
      row.margin_end = 6
    end
  end

  def search_entry
    @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
      entry.placeholder_text = 'Search documents'
      entry.hexpand = true
    end
  end

  def open_button
    @open_button ||= Gtk::Button.new.tap do |button|
      button.tooltip_text = 'Open New Document'
      button.icon_name = 'document-open-symbolic'
      button.action_name = 'win.open'
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |pages|
      pages.vhomogeneous = false
      pages.hhomogeneous = false
    end
  end

  def empty_page
    @empty_page ||= Gtk::Box.new(:vertical, 24).tap do |page|
      page.margin_start = 6
      page.margin_end = 6
      page.margin_top = 36
      page.margin_bottom = 36
      page.append(empty_image)
      page.append(empty_label)
    end
  end

  def empty_image
    @empty_image ||= Gtk::Image.new(icon_name: 'document-open-recent-symbolic').tap do |image|
      image.pixel_size = 96
      image.add_css_class('dim-label')
    end
  end

  def empty_label
    @empty_label ||= Gtk::Label.new('No Recent Documents').tap do |label|
      label.add_css_class('dim-label')
      label.add_css_class('title-2')
    end
  end

  def recent_scroller
    @recent_scroller ||= Gtk::ScrolledWindow.new.tap do |scroller|
      scroller.hexpand = true
      scroller.hscrollbar_policy = :never
      scroller.max_content_height = 600
      scroller.max_content_width = 250
      scroller.min_content_width = 250
      scroller.propagate_natural_height = true
      scroller.vexpand = true
    end
  end

  def list_view
    @list_view ||= Gtk::ListView.new(Gtk::NoSelection.new(@model.store), factory).tap do |view|
      view.single_click_activate = true
    end
  end

  # One EditorSidebarRow per list item, rebound as the view recycles rows.
  def factory
    @factory ||= Gtk::SignalListItemFactory.new.tap do |signal_factory|
      signal_factory.signal_connect('setup') do |_factory, list_item|
        list_item.child = EditorSidebarRow.new.build.tap do |row|
          row.on_remove { |item| @remove_listeners.each { |listener| listener.call(item) } }
        end
      end

      signal_factory.signal_connect('bind') do |_factory, list_item|
        list_item.child.item = list_item.item.item
      end
    end
  end

  private

    def update_stack
      if @model.n_items.zero?
        stack.visible_child_name = 'empty'
      else
        stack.visible_child_name = 'recent'
      end
    end

    def activate_first = activate_position(0)

    def activate_position(position)
      @model.get_item(position)&.then do |item|
        popdown
        @activate_listeners.each { |listener| listener.call(item) }
      end
    end
end
