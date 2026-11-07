# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'

# EditorPageVim wires GtkSourceView's modal vim emulation onto a page's view
# whenever the "keybindings" setting says "vim", and tears it down again when
# it says anything else.
#
# Ported from upstream's src/editor-page-vim.c. Upstream listens for
# "changed::keybindings" on the application's GSettings and installs or
# removes a GtkEventControllerKey carrying a GtkSourceVimIMContext on the
# view; this port does the same through EditorSettings#on_changed, with the
# controller and the IM context held by this class rather than EditorPage's
# own ivars. The three ex-commands (":q", ":q!", ":wq") and the "write" and
# "edit" IM context signals are upstream's.
class EditorPageVim
  QUIT_COMMANDS = [':q', ':quit', '^Wc'].freeze
  FORCE_QUIT_COMMANDS = [':q!', ':quit!'].freeze
  WRITE_QUIT_COMMANDS = [':wq'].freeze

  def initialize(page, settings)
    @page = page
    @settings = settings
    @controller = nil
  end

  def build
    tap do
      @settings.on_changed('keybindings') { apply_keybindings }
      apply_keybindings
    end
  end

  private

    def apply_keybindings
      if @settings.keybindings == 'vim'
        install_controller
      else
        remove_controller
      end
    end

    def install_controller
      unless @controller
        im_context.client_widget = view
        @controller = Gtk::EventControllerKey.new.tap do |controller|
          controller.propagation_phase = :capture
          controller.set_im_context(im_context)
        end
        view.add_controller(@controller)
      end
    end

    def remove_controller
      @controller&.then do |controller|
        view.remove_controller(controller)
        view.overwrite = false
      end
      @controller = nil
    end

    def im_context
      @im_context ||= GtkSource::VimIMContext.new.tap do |context|
        context.signal_connect('write') { |_ctx, path| on_write(path) }
        context.signal_connect('edit') { |_ctx, path| on_edit(path) }
        context.signal_connect('execute-command') { |_ctx, command| on_execute_command(command) }
      end
    end

    def on_write(path)
      if path && !path.empty?
        @page.document.save(Gio::File.new_for_path(resolve_path(path)))
      else
        @page.document.save
      end
    end

    def on_edit(path)
      if path && !path.empty?
        session&.open(@page.window, Gio::File.new_for_path(resolve_path(path)))
      else
        @page.discard_changes
      end
    end

    def on_execute_command(command)
      if QUIT_COMMANDS.include?(command)
        session&.remove_page(@page)
        true
      elsif FORCE_QUIT_COMMANDS.include?(command)
        @page.discard_changes
        session&.remove_page(@page)
        true
      elsif WRITE_QUIT_COMMANDS.include?(command)
        @page.document.save do |error|
          session&.remove_page(@page) if error.nil?
        end
        true
      else
        false
      end
    end

    def resolve_path(path)
      if File.absolute_path?(path)
        path
      else
        @page.document.file&.parent&.then { |parent| File.join(parent.path, path) } || File.expand_path(path)
      end
    end

    def session = @page.window&.session

    def view = @page.view
end
