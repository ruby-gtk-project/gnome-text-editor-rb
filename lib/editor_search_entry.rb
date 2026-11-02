# frozen_string_literal: true

require 'adwaita'

# EditorSearchEntry is the search bar's text field with the match counter and
# the clear button inside it.
#
# Ported from upstream's src/editor-search-entry.c and
# src/editor-search-entry.ui. Upstream is a GtkWidget implementing GtkEditable
# by delegating to an internal GtkText; the Ruby bindings cannot implement a
# GObject interface, so this port is a GtkBox around the same GtkText and
# forwards the handful of editable calls the search bar makes.
class EditorSearchEntry < Gtk::Box
  CSS_CLASS = 'entry'
  PLACEHOLDER = 'Search'

  def initialize
    super(:horizontal, 6)

    add_css_class(CSS_CLASS)
    @occurrence_count = 0
    @occurrence_position = -1
    @activate_listeners = []
    @changed_listeners = []
  end

  def build
    tap do
      append(find_icon)
      append(text)
      append(info)
      append(clear)

      text.tap do |entry|
        entry.signal_connect('changed') do
          clear.visible = !entry.text.empty?
          @changed_listeners.each { |listener| listener.call(entry.text) }
        end
        entry.signal_connect('activate') { @activate_listeners.each(&:call) }
      end

      clear.add_controller(clear_gesture)
    end
  end

  def on_activate(&block)
    tap { @activate_listeners << block }
  end

  def on_changed(&block)
    tap { @changed_listeners << block }
  end

  # GtkEditable's two calls the search bar relies on.
  def search_text = text.text

  def search_text=(value)
    text.text = value.to_s
  end

  def grab_focus = text.grab_focus

  attr_reader :occurrence_count, :occurrence_position

  def occurrence_count=(count)
    @occurrence_count = count
    update_position
  end

  def occurrence_position=(position)
    @occurrence_position = position
    update_position
  end

  def text
    @text ||= Gtk::Text.new.tap do |entry|
      entry.hexpand = true
      entry.placeholder_text = PLACEHOLDER
    end
  end

  def find_icon = @find_icon ||= Gtk::Image.new(icon_name: 'edit-find-symbolic')

  # Dimmed and tabular, so "3 of 12" does not jump as the numbers change.
  def info
    @info ||= Gtk::Label.new.tap do |label|
      label.xalign = 1
      label.attributes = Pango::AttrList.new.tap do |attributes|
        attributes.insert(Pango::AttrForegroundAlpha.new(33_000))
        attributes.insert(Pango::AttrFontFeatures.new('tnum'))
      end
    end
  end

  def clear
    @clear ||= Gtk::Image.new(icon_name: 'edit-clear-symbolic').tap do |image|
      image.visible = false
      image.tooltip_text = 'Clear Entry'
    end
  end

  private

    def clear_gesture
      @clear_gesture ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.signal_connect('pressed') { self.search_text = '' }
      end
    end

    # Translators: the first number is the current position, the second the
    # number of search results.
    def update_position
      if @occurrence_count.zero?
        info.label = ''
      else
        info.label = "#{[0, @occurrence_position].max} of #{@occurrence_count}"
      end
    end
end
