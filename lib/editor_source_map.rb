# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'

# EditorSourceMap is the scrollable overview strip beside the editor view — a
# minimap of the whole buffer, tinted to match the current style scheme.
#
# Ported from upstream's src/editor-source-map.c and src/editor-source-map.ui:
# a GtkWidget wrapping a GtkSourceMap and painting a "background" property
# behind it, bound from the view's buffer's style scheme via the "text"
# style's background colour. This port is a Gtk::Box around a GtkSource::Map
# — the gtksourceview5 gem — with the same colour applied through CSS rather
# than a custom GtkSnapshot override, which the Ruby bindings have no call
# for from outside GTK's own C widgets.
class EditorSourceMap < Gtk::Box
  CSS_PRIORITY = Gtk::StyleProvider::PRIORITY_APPLICATION

  def initialize
    super(:vertical, 0)

    add_css_class(css_class)
    Gtk::StyleContext.add_provider_for_display(Gdk::Display.default, css_provider, CSS_PRIORITY)
  end

  def build
    tap { append(map) }
  end

  def view = map.view

  # Upstream's "view" property setter: hands the GtkSourceView to the map and
  # starts tracking its buffer's style scheme for the background tint.
  def view=(view)
    tap do
      map.view = view
      view&.signal_connect('notify::buffer') { track_buffer(view.buffer) }
      track_buffer(view&.buffer)
    end
  end

  private

    def map = @map ||= GtkSource::Map.new.tap { |widget| widget.vexpand = true }

    def css_class = @css_class ||= "editor-source-map-#{object_id.abs}"

    def css_provider = @css_provider ||= Gtk::CssProvider.new

    def track_buffer(buffer)
      tap do
        buffer&.signal_connect('notify::style-scheme') { update_background(buffer.style_scheme) }
        update_background(buffer&.style_scheme)
      end
    end

    # Upstream's style_scheme_to_background: the "text" style's background,
    # or transparent when the scheme has none.
    def update_background(scheme)
      text_background(scheme).then do |color|
        css_provider.load(data: "box.#{css_class}{background-color:#{color || 'transparent'};}")
      end
    end

    def text_background(scheme)
      scheme&.get_style('text')&.then do |style|
        if style.background_set?
          style.background
        end
      end
    end
end
