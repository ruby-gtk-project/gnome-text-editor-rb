# frozen_string_literal: true

require 'adwaita'

# EditorAnimation tweens numeric widget properties against a frame clock.
#
# Ported from upstream's src/editor-animation.c. Upstream carries a general
# animation object with a dozen easing modes, a GParamSpec-driven value table
# and its own GSource; the only thing the editor animates is a widget's opacity
# when fading the position label out, so this port keeps the easing functions
# and the frame-clock driver and drops the GValue plumbing — the properties are
# set through plain accessors instead.
class EditorAnimation
  # The easing functions upstream exposes as EditorAnimationMode, by the names
  # it gives them.
  EASING = {
    linear:           ->(progress) { progress },
    ease_in_quad:     ->(progress) { progress * progress },
    ease_out_quad:    ->(progress) { -1.0 * progress * (progress - 2.0) },
    ease_in_out_quad: lambda { |progress|
      (progress * 2).then do |p|
        if p < 1.0
          0.5 * p * p
        else
          -0.5 * ((p - 1.0) * (p - 3.0) - 1.0)
        end
      end
    },
    ease_in_cubic:    ->(progress) { progress * progress * progress },
    ease_out_cubic:   ->(progress) { ((progress - 1.0)**3) + 1.0 },
  }.freeze

  DEFAULT_MODE = :ease_out_cubic

  def initialize(widget, duration:, mode: DEFAULT_MODE, &on_done)
    @widget = widget
    @duration = duration.to_f
    @ease = EASING.fetch(mode)
    @on_done = on_done
    @targets = {}
    @stopped = false
  end

  # Records a property to animate: the accessor name, and the value to reach.
  # The starting value is read when #start runs, so a target can be declared
  # before the widget is realized.
  def to(property, value)
    tap { @targets[property] = value.to_f }
  end

  def start
    tap do
      @begin_time = frame_time
      @from = @targets.keys.to_h { |property| [property, @widget.public_send(property).to_f] }
      @tick_id = @widget.add_tick_callback { tick }
    end
  end

  def stop
    tap do
      unless @stopped
        @stopped = true
        if @tick_id
          @widget.remove_tick_callback(@tick_id)
        end
        @tick_id = nil
      end
    end
  end

  def stopped? = @stopped

  private

    # Returns GLib::Source::CONTINUE while the tween runs, so the tick callback
    # stays installed until the final frame has been applied.
    def tick
      if @duration.zero?
        progress = 1.0
      else
        progress = ((frame_time - @begin_time) / @duration)
      end

      if progress >= 1.0
        apply(1.0)
        finish
        GLib::Source::REMOVE
      else
        apply(@ease.call(progress))
        GLib::Source::CONTINUE
      end
    end

    def apply(offset)
      @targets.each do |property, target|
        @from.fetch(property).then do |from|
          @widget.public_send(:"#{property}=", from + ((target - from) * offset))
        end
      end
    end

    def finish
      @stopped = true
      @tick_id = nil
      @on_done&.call
    end

    # Milliseconds. The frame clock is the authority while the widget is on
    # screen; a widget with no clock yet still animates off the monotonic
    # clock rather than freezing. GLib's own monotonic clock has no Ruby
    # binding, and Process::CLOCK_MONOTONIC is the same clock.
    def frame_time
      (@widget.frame_clock&.frame_time || (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1_000_000)) / 1000.0
    end
end
