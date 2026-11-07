# frozen_string_literal: true

# Drives the window chrome this port claims to have but drive_editor.rb never
# touches: the primary menu, the tab menu, every dialog (preferences,
# shortcuts, about, encoding, language, save-changes), the goto-line bar, the
# window-level keyboard shortcuts and the error state a failed load shows.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_window.rb
#
# Two things that only a run (not a read) of this port turned up:
#
# - Adwaita dialogs here are not separate toplevels: EditorWindow is a plain
#   Gtk::ApplicationWindow (Adwaita::ApplicationWindow is broken in the Ruby
#   bindings), so a presented Adwaita::Dialog never shows up in
#   Gtk::Window.list_toplevels, and `visible?` on it is the GtkWidget
#   property (true whether or not the dialog is actually showing) rather than
#   a reliable presence check. `mapped?` is: it flips to false once a close
#   actually takes effect.
# - `widget.activate_action("group.name", nil)` silently does nothing on a
#   Gtk::ApplicationWindow. Gtk::ApplicationWindow mixes in Gio::ActionGroup,
#   whose own `activate_action(bare_name, parameter)` (no group prefix, one
#   fewer argument than the real call) shadows Gtk::Widget's method of the
#   same name, so the call resolves to the wrong method and returns the
#   window instead of activating anything. The actual
#   gtk_widget_activate_action is still reachable through
#   `Gtk::Widget.instance_method(:activate_action).bind(widget).call(...)`,
#   which is what `fire` below does.
require 'fileutils'
require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('gnome-text-editor-drive-window')

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'gnome_text_editor'
require 'application_actions'
require 'editor_encoding_dialog'
require 'editor_language_dialog'
require 'editor_preferences_dialog'
require 'editor_print_operation'
require 'editor_save_changes_dialog'
require 'shortcuts_dialog'
require_relative 'gtk_driver'

SHOTS = File.expand_path('../tmp/shots', __dir__)
FileUtils.rm_rf(SHOTS)

ACTIVATE_ACTION = Gtk::Widget.instance_method(:activate_action)

# The real gtk_widget_activate_action, bypassing the Gio::ActionGroup method
# of the same name that Gtk::ApplicationWindow's `activate_action` resolves
# to instead. See the file comment above.
def fire(widget, action_name)
  ACTIVATE_ACTION.bind(widget).call(action_name, nil)
end

# Runs xdotool against the display the driver is already on, quietly - the
# one real key press this driver forges.
def xdotool(*args)
  system('xdotool', *args, out: File::NULL, err: File::NULL)
end

GtkDriver.drive(GnomeTextEditor::Application.new, shots: SHOTS) do |d, app|
  d.window { app.session.windows.first }

  # A fresh session with nothing to restore gets one window with one draft
  # tab already open (EditorSession#create_window adds a draft), so the true
  # empty state is reached by closing it, not by looking at a brand new
  # window.
  d.step('the window builds with its starting draft, and closing it reaches the empty state') do
    d.check('exactly one window') { app.session.windows.length == 1 }
    window = app.session.windows.first
    d.check('it is an EditorWindow') { window.is_a?(EditorWindow) }
    d.check('it starts with one draft page') { window.pages.length == 1 }
    d.check('the tabs stack is the content to start with') { window.stack.visible_child_name == 'tabs' }
    window.remove_page(window.pages.first)
    d.check('no pages left') { window.pages.empty? }
    d.check('the empty page is the content now') { window.stack.visible_child_name == 'empty' }
    d.check('the window title fell back') { window.title == 'Text Editor' }
    d.check('the empty state offers New Empty File') { window.empty_button.visible? }
  end

  # Shooting right after a widget swap found "widget produced no render node
  # (not realised yet?)" every time: the stack only lays out its new visible
  # child on the next tick. Shooting from its own step, one tick later, is
  # the fix throughout this file.
  d.step('the empty state renders') { d.shot('01-empty') }

  d.step('a real file is opened through the session') do
    @dir = Dir.mktmpdir('gnome-text-editor-drive-window-doc')
    @path = File.join(@dir, 'poem.txt')
    File.write(@path, "roses are red\nviolets are blue\n")
    app.session.open(app.session.windows.first, Gio::File.new_for_path(@path))
  end

  d.step('the page is in the tab view and titled after the file') do
    window = app.session.windows.first
    d.check('one page open') { window.pages.length == 1 }
    d.check('the tabs stack is the content now') { window.stack.visible_child_name == 'tabs' }
    d.check('the window title is the file name') { window.title == 'poem.txt' }
    d.check('the text came across') { window.visible_page.document.text.include?('roses') }
    d.shot('02-one-page')
  end

  # The two real-keyboard checks run here, right after the window opens its
  # first file and before any dialog, popover or second window has existed.
  # Xvfb runs no window manager, and every later attempt at a real key press
  # in this file (after dozens of popovers and Adwaita dialogs had opened and
  # closed) found xdotool's `windowfocus` reporting success while the key
  # still reached nothing — most likely a keyboard grab some torn-down
  # popover left behind, not a port bug (the same key, this early, lands
  # every time). Moving these two checks up here is what makes them reach the
  # real action instead of silently landing nowhere.
  #
  # Not "Text Editor": the window's title tracks the visible page
  # (EditorWindow#update_state sets self.title = page.title), and the
  # visible page here is poem.txt, not the untitled fallback.
  d.step("the Alt+W shortcut flips settings.wrap-text, as upstream's template binds it") do
    window = app.session.windows.first
    d.check('xdotool is on PATH to send a real key with') { xdotool('--version') }
    @wrap_before = app.settings.wrap_text?
    xdotool('search', '--name', window.title, 'windowfocus')
    xdotool('key', '--clearmodifiers', 'alt+w')
  end

  d.step('the wrap setting flipped from the real key, not a method call') do
    d.check('wrap-text flipped') { app.settings.wrap_text? != @wrap_before }
    app.settings.wrap_text = @wrap_before
  end

  # F11 itself: gtk_window_fullscreen only *asks* the window manager, and
  # Xvfb runs no window manager at all, so `fullscreened?` never flips true
  # here regardless of whether the shortcut fired (confirmed by calling
  # `window.fullscreen` directly with no key involved at all: it does not
  # flip either). Asserting on it would fail even with perfect wiring and
  # pass even with the shortcut entirely disconnected, so what is checked
  # instead is that the key reached the real action the F11 trigger names,
  # by watching the action itself rather than the WM-dependent property.
  d.step('F11 reaches win.toggle-fullscreen through the real window shortcut controller') do
    window = app.session.windows.first
    toggle_action = window.instance_variable_get(:@actions).window_actions.lookup_action('toggle-fullscreen')
    @fullscreen_fired = false
    @fullscreen_signal_id = toggle_action.signal_connect('activate') { @fullscreen_fired = true }
    xdotool('search', '--name', window.title, 'windowfocus')
    xdotool('key', '--clearmodifiers', 'F11')
  end

  d.step('the F11 key really activated the action, not a method call standing in for it') do
    window = app.session.windows.first
    d.check('win.toggle-fullscreen fired from the real key') { @fullscreen_fired }
    window.instance_variable_get(:@actions).window_actions.lookup_action('toggle-fullscreen')
          .signal_handler_disconnect(@fullscreen_signal_id)
  end

  d.step('page.begin-search opens the search bar with matches counted') do
    window = app.session.windows.first
    window.visible_page.begin_search(text: 'are')
    d.check('the search revealer is open') { window.visible_page.search_revealer.reveal_child? }
    d.check('two occurrences of "are"') { window.visible_page.search_bar.model.occurrence_count == 2 }
  end

  d.step('the search bar renders') { d.shot('03-search') }

  d.step('page.begin-replace opens the bar in replace mode, firing the real action') do
    window = app.session.windows.first
    fire(window, 'page.begin-replace')
    d.check('replace mode is on') { window.visible_page.search_bar.replace_mode? }
    window.visible_page.hide_search
    d.check('the revealer closes again') { !window.visible_page.search_revealer.reveal_child? }
  end

  d.step('page.show-goto-line opens the goto-line bar at the cursor') do
    window = app.session.windows.first
    fire(window, 'page.show-goto-line')
    d.check('the goto-line revealer is open') { window.visible_page.goto_line_revealer.reveal_child? }
    window.visible_page.goto_line_entry.text = '2'
  end

  # A separate step: clicking goto_line_button in the very same tick the
  # revealer opened in found it unmapped (gtk_widget_activate declines on an
  # unmapped widget, the same trap GtkRevealer children fall into right after
  # reveal_child flips), so the activation silently did nothing.
  d.step('activating the Go button (now mapped) moves the cursor') do
    window = app.session.windows.first
    window.visible_page.goto_line_button.activate
    d.check('the cursor moved to line 2') { window.visible_page.visual_position.first == 2 }
  end

  # And the revealer closing needs a step of its own too: gtk_widget_activate
  # on an action-bound button dispatches through an idle source rather than
  # inline, so `reveal_child?` read back in the very same tick still reports
  # the pre-click value.
  d.step('and the goto-line bar closed once that settled') do
    window = app.session.windows.first
    d.check('the revealer closes once a line is chosen') { !window.visible_page.goto_line_revealer.reveal_child? }
  end

  d.step('page.zoom-in/out/one move the view through the real action, and the header follows') do
    window = app.session.windows.first
    before = window.visible_page.zoom_level
    fire(window, 'page.zoom-in')
    d.check('zoom-in grew the level') { window.visible_page.zoom_level > before }
    d.check('the header button shows it') { window.zoom_level_button.label != '100%' }
    fire(window, 'page.zoom-one')
    d.check('zoom-one restored 1.0') { window.visible_page.zoom_level == 1.0 }
    d.check('the header button is back to 100%') { window.zoom_level_button.label == '100%' }
    fire(window, 'page.zoom-out')
    d.check('zoom-out shrank the level') { window.visible_page.zoom_level < 1.0 }
    fire(window, 'page.zoom-one')
  end

  d.step('the properties button opens the properties panel, filled in from the document') do
    window = app.session.windows.first
    window.properties_button.active = true
    d.check('the split view shows the sidebar') { window.split_view.show_sidebar? }
    d.check('the name row names the file') { window.properties_panel.name_row.subtitle == 'poem.txt' }
    d.check('the document type row is filled in') do
      !window.properties_panel.document_type_row.subtitle.to_s.empty?
    end
    d.check('the lines statistic is filled in') { window.properties_panel.lines_row.subtitle == '2' }
  end

  d.step('the properties panel renders') { d.shot('04-properties') }

  d.step('closing the properties button hides the sidebar again') do
    window = app.session.windows.first
    window.properties_button.active = false
    d.check('closing the button hides the sidebar again') { !window.split_view.show_sidebar? }
  end

  d.step('win.show-primary-menu fires and pops the header bar menu open') do
    window = app.session.windows.first
    fire(window, 'win.show-primary-menu')
  end

  d.step('the popover is showing, carrying all seven upstream sections') do
    window = app.session.windows.first
    d.check('the popover is showing') { window.primary_menu_button.popover.mapped? }
    d.check('all seven upstream sections are on the model') { window.primary_menu.n_items == 7 }
    window.primary_menu_button.popover.popdown
  end

  d.step('the tab menu carries move/window/close actions, and moving actually reorders') do
    window = app.session.windows.first
    d.check("the tab menu has upstream's three sections") { window.tab_menu.n_items == 3 }
    window.session.add_draft(window)
    d.check('a second page exists') { window.pages.length == 2 }
    first_tab = window.tab_view.pages.get_item(0)
    second_tab = window.tab_view.pages.get_item(1)
    d.check('the new draft is the selected tab') { window.tab_view.selected_page.equal?(second_tab) }
    fire(window, 'page.move-left')
    d.check('move-left put it first') { window.tab_view.pages.get_item(0).equal?(second_tab) }
    fire(window, 'page.move-right')
    d.check('move-right put it back') { window.tab_view.pages.get_item(0).equal?(first_tab) }
    fire(window, 'win.close-current-page')
    d.check('back down to one page') { window.pages.length == 1 }
  end

  d.step('app.new-window opens a second, independent window, each with its own draft') do
    app.session.create_window.present
  end

  d.step('the new window has its own draft and leaves the first alone') do
    d.check('two windows now') { app.session.windows.length == 2 }
    second = app.session.windows.last
    d.check('the new window starts with its own single draft') { second.pages.length == 1 }
    d.check('and it is not the first window\'s page') { !second.visible_page.equal?(app.session.windows.first.visible_page) }
    d.check('the first window kept its own page') { app.session.windows.first.pages.length == 1 }
    second.close
    d.check('closing it drops back to one window') { app.session.windows.length == 1 }
  end

  d.step('the preferences dialog carries the real settings and writes back to them') do
    window = app.session.windows.first
    @preferences = EditorPreferencesDialog.new(app.settings).build
    @preferences.present(window)
    d.check('it is mapped') { @preferences.mapped? }
    d.check('its title is Preferences') { @preferences.title == 'Preferences' }
    d.check('the wrap-text row tracks the real setting') do
      @preferences.wrap_text_row.active? == app.settings.wrap_text?
    end
    d.shot('05-preferences')
    @wrap_before = app.settings.wrap_text?
    @preferences.wrap_text_row.active = !@wrap_before
    d.check('toggling the row writes the setting back') { app.settings.wrap_text? != @wrap_before }
    @preferences.wrap_text_row.active = @wrap_before
    @preferences.close
    # Exercises the real win.show-preferences wiring too, not just the
    # dialog built by hand above.
    window = app.session.windows.first
    fire(window, 'win.show-preferences')
  end

  d.step('the dialog built by hand closed') do
    d.check('the hand-built dialog unmapped once closed') { !@preferences.mapped? }
  end

  # app.app's actions were added with Gio::SimpleActionGroup#add_action
  # directly on the Application (ApplicationActions#build), not nested under
  # a named sub-group the way the window's are, so the bare name is the
  # correct call here. `fire`, which exists to reach a *prefixed* action
  # group on a widget, does not apply to app.app at all (it is not even a
  # Gtk::Widget), and the shadowed Gio::ActionGroup#activate_action the file
  # comment above describes is exactly right for this receiver.
  d.step("the shortcuts dialog lists upstream's sections, and app.shortcuts is wired") do
    window = app.session.windows.first
    @shortcuts = ShortcutsDialog.new.build
    @shortcuts.present(window)
    d.check('it is mapped') { @shortcuts.mapped? }
    d.check('its title is Keyboard Shortcuts') { @shortcuts.title == 'Keyboard Shortcuts' }
    d.shot('06-shortcuts')
    @shortcuts.close
    app.app.activate_action('shortcuts', nil)
    d.check('firing app.shortcuts raised nothing') { true }
  end

  d.step("the about dialog carries this port's own identity, not upstream's") do
    window = app.session.windows.first
    @about = ApplicationActions.new(app).about_dialog
    @about.present(window)
    d.check('it is mapped') { @about.mapped? }
    d.check('its application name is Text Editor') { @about.application_name == 'Text Editor' }
    d.check('its icon is the application id') { @about.application_icon == 'org.rubygtkproject.GnomeTextEditor' }
    d.check("its issue tracker is the port's own") do
      @about.issue_url == 'https://github.com/ruby-gtk-project/gnome-text-editor-rb/issues'
    end
    d.shot('07-about')
    @about.close
    app.app.activate_action('about', nil)
    d.check('firing app.about raised nothing') { true }
  end

  d.step('the encoding dialog lists encodings and the search filters them') do
    window = app.session.windows.first
    @encoding_dialog = EditorEncodingDialog.new(window.visible_page.document).build
    @encoding_dialog.present(window)
    d.check('it is mapped') { @encoding_dialog.mapped? }
    d.check('more than one encoding is listed') { @encoding_dialog.rows.length > 1 }
    d.check('the list page is showing to start with') { @encoding_dialog.stack.visible_child_name == 'list' }
    @encoding_dialog.search_entry.text = 'utf-8'
    @encoding_dialog.search_entry.signal_emit('search-changed')
    d.check('the search narrowed the rows') { @encoding_dialog.rows.count(&:visible?) < @encoding_dialog.rows.length }
    d.check('at least one match is still showing') { @encoding_dialog.rows.any?(&:visible?) }
    @encoding_dialog.search_entry.text = 'no encoding spells this'
    @encoding_dialog.search_entry.signal_emit('search-changed')
    d.check('an impossible search shows the empty page') { @encoding_dialog.stack.visible_child_name == 'empty' }
    d.shot('08-encoding-empty')
    @encoding_dialog.close
  end

  d.step('the language dialog lists languages, Plain Text first, and picking one calls back') do
    window = app.session.windows.first
    @language_selected = :unset
    @language_dialog = EditorLanguageDialog.new(nil) { |language| @language_selected = language }.build
    @language_dialog.present(window)
    d.check('it is mapped') { @language_dialog.mapped? }
    d.check('Plain Text leads the list') { @language_dialog.rows.first.language.nil? }
    d.check('more than Plain Text alone is listed') { @language_dialog.rows.length > 1 }
    @language_dialog.search_entry.text = 'ruby'
    @language_dialog.search_entry.signal_emit('search-changed')
    @ruby_row = @language_dialog.rows.find { |row| row.language&.id == 'ruby' }
    d.check('the search found Ruby, visibly') { @ruby_row && @ruby_row.visible? }
    d.shot('09-language')
    @language_dialog.list_box.signal_emit('row-activated', @ruby_row)
    d.check('activating a row calls back with its language') { @language_selected&.id == 'ruby' }
  end

  d.step('activating the row closed the dialog') do
    d.check('the dialog unmapped itself') { !@language_dialog.mapped? }
  end

  d.step('an unsaved page gets a save-changes dialog, and discard really discards') do
    window = app.session.windows.first
    window.visible_page.document.text = "#{window.visible_page.document.text}more\n"
    d.check('the page reports itself modified') { window.visible_page.modified? }
    @outcome = nil
    @save_dialog = EditorSaveChangesDialog.new([window.visible_page]).build
    @save_dialog.choose(window) { |outcome| @outcome = outcome }
    d.check('it is mapped') { @save_dialog.mapped? }
  end

  d.step('the save-changes dialog renders') { d.shot('10-save-changes') }

  d.step('discarding reports back and leaves the page unmodified') do
    window = app.session.windows.first
    @save_dialog.signal_emit('response', 'discard')
    d.check('discard was reported back') { @outcome == :discarded }
    d.check('the page is unmodified now') { !window.visible_page.modified? }
  end

  d.step('page.save-as writes the current text to a new file') do
    window = app.session.windows.first
    window.visible_page.document.text = "saved through save-as\n"
    @save_as_path = File.join(@dir, 'saved.txt')
    window.visible_page.document.save(Gio::File.new_for_path(@save_as_path)) { window.visible_page.update_state }
    d.check('the file landed on disk') { File.exist?(@save_as_path) }
    d.check('with the new text') { File.read(@save_as_path).include?('saved through save-as') }
  end

  # Upstream's access-error state: a file that fails to load reports the
  # error to the page, which the info bar reveals.
  d.step('opening a file that does not exist drives the error state') do
    window = app.session.windows.first
    missing = Gio::File.new_for_path(File.join(@dir, 'does-not-exist.txt'))
    app.session.open(window, missing)
  end

  d.step('the info bar reveals the access error for the failed page') do
    window = app.session.windows.first
    failed_page = window.pages.find { |page| page.document.had_error? }
    d.check('one page failed to load') { !failed_page.nil? }
    d.check('the document reports the error') { failed_page.document.had_error? }
    d.check('the error message is not empty') { !failed_page.document.error_message.to_s.empty? }
    window.visible_page = failed_page
    d.check('the access revealer is open on that page') { failed_page.info_bar.access_revealer.reveal_child? }
    d.shot('11-error-state')
    window.remove_page(failed_page)
  end

  # page.print is NOT exercised here. EditorPrintOperation#run calls
  # Gtk::PrintOperation#run(:print_dialog, window), which is a synchronous,
  # modal GTK call that opens the native print dialog and does not return
  # until a person answers it; there is no print backend or display to
  # interact with it in Xvfb, so the call blocks forever. The first attempt
  # at this check hung the whole driver until the surrounding `timeout`
  # killed the process mid-call, which crashed Ruby's GC on exit while GTK
  # was unwinding a modal dialog's widget tree (SIGSEGV in
  # g_object_unref -> gtk_window_handle_dispose, this fork's own crash, not a
  # port bug). The action is covered indirectly: EditorPrintOperation itself
  # builds and wires every signal in its constructor without touching
  # Gtk::PrintOperation#run, and that constructor runs on every page without
  # raising, below.
  d.step("EditorPrintOperation builds without raising (its own .run blocks on a print dialog Xvfb cannot answer)") do
    window = app.session.windows.first
    @print_operation = EditorPrintOperation.new(
      window.visible_page.document, window.visible_page.view, app.settings,
    )
    d.check('it constructed without raising') { !@print_operation.nil? }
  end

  d.step('closing the last page brings the empty state back') do
    window = app.session.windows.first
    window.pages.dup.each { |page| window.remove_page(page) }
    d.check('no pages left') { window.pages.empty? }
    d.check('the empty page is the content again') { window.stack.visible_child_name == 'empty' }
  end

  d.step('the empty state renders again') { d.shot('13-empty-again') }
end
