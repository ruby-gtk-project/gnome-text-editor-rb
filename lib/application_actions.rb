# frozen_string_literal: true

require 'adwaita'
require_relative 'shortcuts_dialog'

# ApplicationActions installs the application-wide actions: new window, the
# about dialog, help, quit, and the two that manage the recent-documents
# history.
#
# Ported from upstream's src/editor-application-actions.c. The action names,
# their parameter types and the accelerators the application installs for
# them are upstream's; the about dialog's fields are this port's own, as the
# port is a different piece of software from the app it was ported from.
class ApplicationActions
  HELP_URI = 'help:gnome-text-editor'

  # name => accelerators, as upstream's
  # gtk_application_set_accels_for_action calls set them.
  ACCELERATORS = {
    'app.new-window'           => ['<Control>n'],
    'app.quit'                 => ['<Control>q'],
    'app.shortcuts'            => ['<Control>question'],
    'app.help'                 => ['F1'],
    'win.open'                 => ['<Control>o'],
    'win.close-page-or-window' => ['<Control>w'],
    'win.show-primary-menu'    => ['F10'],
    'win.focus-search'         => ['<Control>k'],
    'win.toggle-fullscreen'    => ['F11'],
    'session.new-draft'        => ['<Control>t'],
    'page.save'                => ['<Control>s'],
    'page.save-as'             => ['<Control><Shift>s'],
    'page.begin-search'        => ['<Control>f'],
    'page.begin-replace'       => ['<Control>h'],
    'page.show-goto-line'      => ['<Control>i'],
    'page.copy-all'            => ['<Control><Shift>c'],
    'page.move-to-new-window'  => ['<Control><Shift>n'],
    'page.zoom-in'             => ['<Control>plus', '<Control>equal', '<Control>KP_Add'],
    'page.zoom-out'            => ['<Control>minus', '<Control>KP_Subtract'],
    'page.zoom-one'            => ['<Control>0'],
  }.freeze

  def initialize(application)
    @application = application
  end

  def build
    tap do
      add('new-window') { @application.session.create_window.present }
      add('about') { show_about }
      add('help') { show_help }
      add('quit') { quit }
      add('shortcuts') { show_shortcuts }
      add('remove-recent', '(ss)') { |parameter| remove_recent(parameter) }
      add('clear-history') { @application.session.clear_history }

      ACCELERATORS.each do |name, accelerators|
        @application.app.set_accels_for_action(name, accelerators)
      end
    end
  end

  def about_dialog
    Adwaita::AboutDialog.new.tap do |dialog|
      dialog.application_name = 'Text Editor'
      dialog.application_icon = 'org.rubygtkproject.GnomeTextEditor'
      dialog.developer_name = 'ruby-gtk-project'
      dialog.version = '0.1.0'
      dialog.website = 'https://github.com/ruby-gtk-project/gnome-text-editor-rb'
      dialog.issue_url = 'https://github.com/ruby-gtk-project/gnome-text-editor-rb/issues'
      dialog.license_type = Gtk::License::GPL_3_0
      dialog.comments = 'A Ruby GTK4 / Libadwaita port of GNOME Text Editor.'
    end
  end

  private

    def add(name, parameter_type = nil, &block)
      @application.app.add_action(
        Gio::SimpleAction.new(name, parameter_type && GLib::VariantType.new(parameter_type)).tap do |action|
          action.signal_connect('activate') { |_action, parameter| block.call(parameter) }
        end,
      )
    end

    def show_about
      about_dialog.present(@application.app.active_window)
    end

    def show_shortcuts
      ShortcutsDialog.new.build.present(@application.app.active_window)
    end

    def show_help
      Gtk::UriLauncher.new(HELP_URI).launch(@application.app.active_window, nil) { |_source, _result| nil }
    rescue StandardError
      nil
    end

    # Quitting saves the session first, which is what makes the next start
    # come back to the same tabs.
    def quit
      @application.session.save(shutting_down: true)
      @application.app.quit
    end

    # The parameter is (uri, draft-id), either of which may be empty — the
    # same pair upstream's app.remove-recent takes from the sidebar row.
    def remove_recent(parameter)
      parameter.get_child_value(0).get_string.then do |uri|
        parameter.get_child_value(1).get_string.then do |draft_id|
          @application.session.forget(
            uri:      uri.empty? ? nil : uri,
            draft_id: draft_id.empty? ? nil : draft_id,
          )
        end
      end
    end
end
