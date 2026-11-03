# frozen_string_literal: true

# Drives the editor without a user: opens a file, exercises the window's
# actions and the page's search, then quits. Run with
#   nix develop --command xvfb-run -a ruby test/drive_editor.rb
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'tmpdir'
require 'editor_focus_chain'
require 'gnome_text_editor'

# The drive wants a session of its own, so it neither reads nor writes the one
# a real install keeps. GLib caches the XDG directories on first use, so this
# has to be set before anything asks for them — run the script with
# XDG_CONFIG_HOME and XDG_DATA_HOME pointing somewhere disposable to isolate
# it further.

Dir.mktmpdir('gnome-text-editor-rb') do |dir|
  path = File.join(dir, 'drive.txt')
  File.write(path, "alpha beta gamma\nalpha delta\n")

  editor = GnomeTextEditor::Application.new
  failures = []

  check = lambda do |label, &block|
    block.call
    puts "ok   #{label}"
  rescue StandardError => e
    failures << "#{label}: #{e.class}: #{e.message}"
    puts "FAIL #{label}: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).map { |line| "       #{line}" }
  end

  editor.build

  editor.app.signal_connect('activate') do
    GLib::Timeout.add(500) do
      window = editor.session.windows.first

      check.call('window built') do
        unless window
          raise 'no window'
        end
      end
      check.call('open file') do
        editor.session.open(window, Gio::File.new_for_path(path))
        unless window.visible_page.document.text.include?('alpha')
          raise 'not opened'
        end
      end
      check.call('title tracks page') do
        unless window.title == 'drive.txt'
          raise "title #{window.title}"
        end
      end
      check.call('begin-search') do
        window.visible_page.begin_search(text: 'alpha')
        unless window.visible_page.search_bar.model.occurrence_count == 2
          raise 'no matches'
        end
      end
      check.call('focus chain walks the search bar') do
        window.visible_page.search_bar.then do |bar|
          bar.replace_mode = true
          bar.search_entry.grab_focus

          unless EditorFocusChain.focus_child(bar, bar.focus_chain, :tab_forward)
            raise 'tab forward focused nothing'
          end
          unless EditorFocusChain.contains_focus?(bar.replace_entry)
            raise 'tab forward skipped the replace entry'
          end
          unless EditorFocusChain.focus_child(bar, bar.focus_chain, :tab_backward)
            raise 'tab backward focused nothing'
          end
          unless EditorFocusChain.contains_focus?(bar.search_entry)
            raise 'tab backward did not come back to the search entry'
          end

          bar.replace_mode = false
          bar.search_entry.grab_focus
          EditorFocusChain.focus_child(bar, bar.focus_chain, :tab_forward)

          if EditorFocusChain.contains_focus?(bar.replace_entry)
            raise 'tab forward focused the hidden replace entry'
          end
        end
      end
      check.call('replace-all') do
        window.visible_page.search_bar.replace_entry.text = 'omega'
        window.visible_page.search_bar.replace_all
        if window.visible_page.document.text.include?('alpha')
          raise 'not replaced'
        end
      end
      check.call('save') do
        window.visible_page.document.save
        unless File.read(path).include?('omega')
          raise 'not written'
        end
      end
      check.call('properties panel') do
        window.properties_button.active = true
        if window.properties_panel.name_row.subtitle.to_s.empty?
          raise 'no name'
        end
      end
      check.call('new draft') do
        window.pages.length.then do |before|
          editor.session.add_draft(window)
          unless window.pages.length == before + 1
            raise "pages #{window.pages.length}"
          end
        end
      end
      check.call('zoom') do
        window.zoom_in_button.signal_emit('clicked')
        unless window.visible_page.zoom_level > 1.0
          raise 'no zoom'
        end
      end
      check.call('fullscreen toggle') do
        window.toggle_fullscreen
        window.toggle_fullscreen
      end
      check.call('recents populated') do
        if editor.session.recents.n_items.zero?
          raise 'empty recents'
        end
      end
      check.call('session state written') do
        editor.session.save
        unless editor.session.state_file.query_exists
          raise 'no state file'
        end
      end

      puts(failures.empty? ? 'ALL OK' : "FAILURES: #{failures.length}")
      editor.app.quit
      GLib::Source::REMOVE
    end
  end

  editor.run([])
end
