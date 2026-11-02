# frozen_string_literal: true

require 'adwaita'

# EditorBufferMonitor watches a document's file and reports when something
# else has changed it on disk.
#
# Ported from upstream's src/editor-buffer-monitor.c. Upstream notifies through
# the "changed" GObject property; this port calls a block, because the
# consumer — EditorDocument — is the only listener and the Ruby bindings make
# an observer block cheaper than a registered property.
class EditorBufferMonitor
  # Upstream coalesces monitor events for a tenth of a second before going out
  # to query the etag.
  NOTIFY_DELAY = 100
  ETAG_ATTRIBUTE = 'etag::value'

  def initialize(&on_changed)
    @on_changed = on_changed
    @pause_count = 0
    @changed = false
    @failed = false
  end

  attr_reader :file, :etag

  def changed? = @changed

  # Points the monitor at a new file, which clears the "changed" state: a
  # document that has just been saved under a new name is not stale.
  def file=(file)
    unless @file == file
      @file = file
      @etag = nil
      @changed = false
      reset
    end
  end

  def etag=(etag)
    @etag = etag
  end

  # Clears the flag and starts watching afresh — what the document does once it
  # has reloaded from disk.
  def reset
    tap do
      cancel

      if @file && @pause_count.zero?
        @monitor = @file.monitor_file(Gio::FileMonitorFlags::WATCH_MOVES).tap do |monitor|
          monitor.signal_connect('changed') do |_monitor, _file, _other, event|
            on_event(event)
          end
        end
      end
    end
  end

  # Saving the document from inside the editor must not look like an external
  # modification, so the save path brackets its write in pause/unpause.
  def pause
    tap do
      @pause_count += 1
      if @pause_count == 1
        cancel
      end
    end
  end

  def unpause
    tap do
      if @pause_count.positive?
        @pause_count -= 1
      end
      if @pause_count.zero?
        reset
      end
    end
  end

  # A load that failed leaves the monitor paused, so a file the editor cannot
  # read does not keep raising the "changed on disk" banner.
  def failed=(failed)
    unless @failed == failed
      @failed = failed
      @failed ? pause : unpause
    end
  end

  def cancel
    tap do
      if @notify_source
        GLib::Source.remove(@notify_source)
      end
      @notify_source = nil
      @monitor&.cancel
      @monitor = nil
    end
  end

  private

    WATCHED_EVENTS = [
      Gio::FileMonitorEvent::CHANGED,
      Gio::FileMonitorEvent::DELETED,
      Gio::FileMonitorEvent::RENAMED,
    ].freeze

    def on_event(event)
      if WATCHED_EVENTS.include?(event) && @notify_source.nil?
        @notify_source = GLib::Timeout.add(NOTIFY_DELAY) do
          @notify_source = nil
          unless @changed || @failed
            check_etag
          end
          GLib::Source::REMOVE
        end
      end
    end

    # The etag comparison is what stops a touch, or the editor's own write,
    # from being reported as an outside change.
    def check_etag
      current_etag.then do |etag|
        unless @etag && etag == @etag
          @changed = true
          @on_changed&.call
        end
      end
    end

    def current_etag
      @file.query_info(ETAG_ATTRIBUTE, :none).etag
    rescue GLib::Error
      nil
    end
end
