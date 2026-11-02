# frozen_string_literal: true

require 'adwaita'

# EditorFullscreenBox holds the header bar, the tab bar and the content, and
# slides the bars out of the way in fullscreen until the pointer reaches the
# top edge.
#
# Ported from upstream's src/editor-fullscreen-box.c. Upstream is a GtkWidget
# with its own layout and overlay handling wrapped around an AdwToolbarView;
# this port is a bin around the same AdwToolbarView and toggles its
# reveal-top-bars and reveal-bottom-bars, which is the mechanism upstream's
# reveal and conceal paths end in. The three timings and the five-pixel hot
# edge are upstream's constants.
class EditorFullscreenBox < Adwaita::Bin
  FULLSCREEN_HIDE_DELAY = 300
  FORCED_REVEAL_DELAY = 1500
  SHOW_HEADERBAR_DISTANCE_PX = 5

  def initialize
    super

    @fullscreen = false
    @last_y = 0
  end

  def build
    tap do
      self.child = toolbar_view
      add_controller(motion_controller)
    end
  end

  def add_top(widget)
    tap { toolbar_view.add_top_bar(widget) }
  end

  def add_bottom(widget)
    tap { toolbar_view.add_bottom_bar(widget) }
  end

  def content=(widget)
    toolbar_view.content = widget
  end

  def fullscreen? = @fullscreen

  # Entering fullscreen conceals the bars; leaving it puts them back.
  def fullscreen=(fullscreen)
    @fullscreen = fullscreen
    @fullscreen ? conceal : reveal_permanently
  end

  def revealed? = toolbar_view.reveal_top_bars?

  # Shows the bars for a moment even though the pointer is nowhere near the
  # top — what upstream's forced reveal does when a shortcut needs the user to
  # see the header.
  def reveal
    tap do
      cancel_timeouts
      set_revealed(true)
      @forced_reveal_id = GLib::Timeout.add(FORCED_REVEAL_DELAY) do
        @forced_reveal_id = nil
        queue_conceal
        GLib::Source::REMOVE
      end
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  private

    def motion_controller
      @motion_controller ||= Gtk::EventControllerMotion.new.tap do |controller|
        controller.signal_connect('motion') { |_controller, _x, y| on_motion(y) }
        controller.signal_connect('leave') { queue_conceal }
      end
    end

    # While the bars are hidden the hot edge is five pixels tall; once they are
    # showing, the whole bar area keeps them up, so the pointer can travel to a
    # button without them sliding away underneath it.
    def titlebar_area_height
      revealed? ? toolbar_view.top_bar_height : SHOW_HEADERBAR_DISTANCE_PX
    end

    def on_motion(y)
      @last_y = y

      if @fullscreen
        if y <= titlebar_area_height
          cancel_timeouts
          set_revealed(true)
        else
          queue_conceal
        end
      end
    end

    def queue_conceal
      tap do
        if @fullscreen && @forced_reveal_id.nil? && @hide_id.nil?
          @hide_id = GLib::Timeout.add(FULLSCREEN_HIDE_DELAY) do
            @hide_id = nil
            if @last_y > titlebar_area_height
              conceal
            end
            GLib::Source::REMOVE
          end
        end
      end
    end

    def conceal
      cancel_timeouts
      set_revealed(false)
    end

    def reveal_permanently
      cancel_timeouts
      set_revealed(true)
    end

    def set_revealed(revealed)
      toolbar_view.reveal_top_bars = revealed
      toolbar_view.reveal_bottom_bars = revealed
    end

    def cancel_timeouts
      if @hide_id
        GLib::Source.remove(@hide_id)
      end
      if @forced_reveal_id
        GLib::Source.remove(@forced_reveal_id)
      end
      @hide_id = nil
      @forced_reveal_id = nil
    end
end
