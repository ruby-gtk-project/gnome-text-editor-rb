# frozen_string_literal: true

require 'adwaita'

# EditorFileManager asks the desktop's file manager to show a file.
#
# Ported from upstream's src/editor-file-manager.c, which is itself borrowed
# from the GIMP. Only the Unix branch is ported — the Windows and macOS
# branches call into shell32 and AppKit, which the Ruby bindings cannot reach.
# Upstream's Unix branch calls org.freedesktop.FileManager1.ShowItems over
# D-Bus so the file is selected inside its directory; the Ruby bindings expose
# no synchronous D-Bus proxy constructor, so this port hands the directory to
# the desktop's handler instead, which opens the same window without the file
# pre-selected.
module EditorFileManager
  class << self
    # Returns true when the request went out, or false and the error message,
    # which is what the properties panel reports.
    def show(file)
      file.parent.then do |directory|
        Gio::AppInfo.launch_default_for_uri((directory || file).uri, nil)
        [true, nil]
      end
    rescue StandardError => e
      [false, e.message]
    end
  end
end
