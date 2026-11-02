# frozen_string_literal: true

require 'adwaita'

# EditorWindowDnd lets files be dropped on a window to open them.
#
# Ported from upstream's src/editor-window-dnd.c, which installs a
# GtkDropTarget for GDK_TYPE_FILE_LIST on the window and hands whatever is
# dropped to the session. The Ruby bindings cannot read a GdkFileList, so the
# target accepts text/uri-list instead — which is the same drag payload every
# file manager offers — and resolves the URIs to files itself.
class EditorWindowDnd
  def initialize(window)
    @window = window
  end

  def build
    tap { @window.add_controller(drop_target) }
  end

  def drop_target
    @drop_target ||= Gtk::DropTarget.new(GLib::Type::STRING, :copy).tap do |target|
      target.set_gtypes([GLib::Type::STRING])
      target.signal_connect('drop') { |_target, value, _x, _y| open_dropped(value) }
    end
  end

  private

    # A uri-list is newline separated and may carry comment lines, which are
    # skipped.
    def open_dropped(value)
      parse_uris(value.to_s).then do |files|
        if files.empty?
          next false
        end

        @window.session.open_files(files, window: @window)
        true
      end
    end

    def parse_uris(text)
      text.split(/\r?\n/)
          .map(&:strip)
          .reject { |line| line.empty? || line.start_with?('#') }
          .map { |uri| uri.include?('://') ? Gio::File.new_for_uri(uri) : Gio::File.new_for_path(uri) }
    end
end
