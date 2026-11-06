# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'
require_relative '../application_actions'
require_relative '../editor_document'
require_relative '../editor_page'
require_relative '../editor_session'
require_relative '../editor_settings'
require_relative '../editor_window'

module GnomeTextEditor
  # Application starts the editor: it builds the session, restores the
  # previous one, applies the style variant and the font, and keeps the
  # stylesheet loaded.
  #
  # Ported from upstream's src/editor-application.c, src/main.c and
  # src/editor-application-actions.c. Upstream derives from AdwApplication,
  # which the Ruby bindings cannot subclass, so this is a plain object around
  # a GtkApplication, with libadwaita initialised by hand and the style
  # manager driven from the same "style-variant" key. The command line handling
  # is upstream's: files named on the command line are opened in a window, and
  # with none the previous session is restored.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = 'org.rubygtkproject.GnomeTextEditor'
    CSS_RESOURCE = 'style.css'

    def build
      app.tap do
        Adwaita.init

        app.signal_connect('startup') do
          load_stylesheet
          load_icons
          load_style_schemes
          apply_style_variant
          settings.on_changed('style-variant') { apply_style_variant }
          settings.on_changed('line-height') { apply_line_height }
          settings.on_changed('auto-save-delay') { session.auto_save_delay = settings.auto_save_delay }

          actions.build
          session.reset_auto_save
        end

        app.signal_connect('activate') { activate }

        app.signal_connect('open') do |_app, files, _hint|
          session.open_files(files.to_a).then { |window| present(window) }
        end

        app.signal_connect('shutdown') { session.save(shutting_down: true) }
      end
    end

    def run(argv = ARGV) = app.run(argv)

    # Gtk::Application, not Adwaita::Application: the Adwaita subclass is
    # broken in the Ruby bindings, so libadwaita is initialised by hand in
    # #build and every other Adwaita widget works as normal.
    def app
      @app ||= Gtk::Application.new(APP_ID, [:handles_open]).tap do |application|
        application.register_session = true
      end
    end

    def settings = @settings ||= EditorSettings.new

    # The session needs factories for its windows and pages, because it owns
    # their lifetime but not their classes.
    def session
      @session ||= EditorSession.new(settings: settings).tap do |editor_session|
        editor_session.window_factory = -> { new_window(editor_session) }
        editor_session.page_factory = ->(document) { EditorPage.new(document, settings) }
      end
    end

    def actions = @actions ||= ApplicationActions.new(self)

    def css_provider = @css_provider ||= Gtk::CssProvider.new

    def style_manager = @style_manager ||= Adwaita::StyleManager.default

    private

    # Restoring the session is what upstream does when it is activated with no
    # files: the windows and tabs come back, and a fresh start gets one window
    # with one empty draft.
      def activate
        if @activated
          present(app.active_window || session.windows.first)
        else
          @activated = true
          restore_or_create.then { |window| present(window) }
        end
      end

      def restore_or_create
        (settings.restore_session? ? session.restore : nil) || session.create_window
      end

      def present(window)
        window&.tap do |target|
          target.present
          apply_line_height
        end
      end

      def new_window(editor_session)
        EditorWindow.new(app, editor_session, settings).build.tap do |window|
          window.signal_connect('notify::is-active') { editor_session.mark_dirty }
        end
      end

      # The stylesheet ships beside lib/ as data/style.css, which is where the
      # flake installs it.
      def load_stylesheet
        css_path.then do |path|
          if File.exist?(path)
            css_provider.load(path: path)
            Gtk::StyleContext.add_provider_for_display(
              Gdk::Display.default, css_provider, Gtk::StyleProvider::PRIORITY_APPLICATION,
            )
          end
        end
      end

      # The four action symbolics the window and the info bar name ship beside
      # lib/ as data/icons, laid out as an icon theme. Upstream reaches them
      # through its GResource bundle, which the icon theme reads from
      # /org/gnome/TextEditor/icons; this port adds the directory to the
      # display's icon theme instead, and the packaged build also installs it
      # into share/icons.
      def load_icons
        icons_path.then do |path|
          if Dir.exist?(path)
            Gtk::IconTheme.get_for_display(Gdk::Display.default).add_search_path(path)
          end
        end
      end

      # The five style schemes upstream bundles as src/styles/*.xml ship beside
      # lib/ as data/styles, which is where the flake installs them too.
      # GtkSourceStyleSchemeManager reads every "*.xml" in a search path
      # directory, so adding the directory is the whole registration.
      def load_style_schemes
        styles_path.then do |path|
          if Dir.exist?(path)
            manager = GtkSource::StyleSchemeManager.default
            manager.append_search_path(path)
            manager.force_rescan
          end
        end
      end

      def icons_path = File.join(
        __dir__,
        '..',
        '..',
        'data',
        'icons',
      )

      def styles_path = File.join(
        __dir__,
        '..',
        '..',
        'data',
        'styles',
      )

      def css_path = File.join(
        __dir__,
        '..',
        '..',
        'data',
        CSS_RESOURCE,
      )

      # The line height is the one view setting upstream drives straight from
      # its GSettings rather than through the per-page settings stack; the font,
      # the wrap mode and the indentation come from each page's
      # EditorPageSettings, so that an .editorconfig or a modeline can overrule
      # the preferences for one document without the application pushing the
      # preferences back over them.
      def apply_line_height
        each_view { |view| view.line_height = settings.line_height }
      end

      # "follow", "light" or "dark", the three values the schema allows.
      def apply_style_variant
        case settings.style_variant
        when 'light'
          style_manager.color_scheme = Adwaita::ColorScheme::FORCE_LIGHT
        when 'dark'
          style_manager.color_scheme = Adwaita::ColorScheme::FORCE_DARK
        else
          style_manager.color_scheme = Adwaita::ColorScheme::DEFAULT
        end
      end

      def each_view(&block)
        session.pages.each { |page| block.call(page.view) }
      end
  end
end
