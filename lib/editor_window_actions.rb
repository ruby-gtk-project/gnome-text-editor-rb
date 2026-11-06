# frozen_string_literal: true

require 'adwaita'
require 'gtksourceview5'
require_relative 'editor_encoding_dialog'
require_relative 'editor_language_dialog'
require_relative 'editor_preferences_dialog'
require_relative 'editor_print_operation'
require_relative 'editor_save_changes_dialog'

# EditorWindowActions installs every action the window answers: the session's
# new-draft, the window's own open/close/fullscreen commands, and the "page."
# actions that act on whichever tab is visible.
#
# Ported from upstream's src/editor-window-actions.c. Upstream installs these
# as class actions and builds its "settings" group from
# g_settings_create_action for nine keys; this port uses GSimpleActionGroups
# and EditorSettings#create_action, which is the same action for either store.
class EditorWindowActions
  # The keys upstream exposes as the window's "settings" action group.
  SETTING_KEYS = %w[
    auto-indent
    discover-settings
    indent-style
    show-line-numbers
    show-right-margin
    spellcheck
    style-variant
    tab-width
    wrap-text
  ].freeze

  def initialize(window)
    @window = window
  end

  def build
    tap do
      @window.insert_action_group('session', session_actions)
      @window.insert_action_group('win', window_actions)
      @window.insert_action_group('page', page_actions)
      @window.insert_action_group('settings', settings_actions)
      update(nil)
    end
  end

  # Enables only what the visible page can actually do, which is upstream's
  # _editor_window_actions_update.
  def update(page)
    tap do
      has_page = !page.nil?
      can_save = has_page && (page.modified? || page.document.file.nil?)

      %w[close-current-page close-other-pages close-page-or-window focus-neighbor].each do |name|
        window_actions.lookup_action(name).enabled = has_page
      end

      %w[save-as discard-changes begin-search begin-replace change-encoding change-language copy-all
         move-left move-right move-to-new-window zoom-in zoom-out zoom-one
         show-goto-line goto-line print
].each do |name|
        page_actions.lookup_action(name).enabled = has_page
      end

      page_actions.lookup_action('save').enabled = can_save
      page_actions.lookup_action('confirm-save').enabled = can_save
      page_actions.lookup_action('infobar-discard-changes').enabled = has_page
    end
  end

  # Asks about the unsaved document a closing tab holds, then yields whether
  # the close may go ahead.
  def confirm_close(page, &block)
    EditorSaveChangesDialog.new([page]).build.choose(@window) do |outcome|
      block.call(outcome != :cancelled)
    end
  end

  # The same question for every unsaved tab, which is what closing the window
  # asks.
  def confirm_close_window(&block)
    @window.pages.select(&:modified?).then do |unsaved|
      if unsaved.empty?
        block.call(true)
      else
        EditorSaveChangesDialog.new(unsaved).build.choose(@window) do |outcome|
          block.call(outcome != :cancelled)
        end
      end
    end
  end

  def session_actions
    @session_actions ||= Gio::SimpleActionGroup.new.tap do |group|
      add(group, 'new-draft') { @window.session.add_draft(@window) }
    end
  end

  def window_actions
    @window_actions ||= Gio::SimpleActionGroup.new.tap do |group|
      add(group, 'close-current-page') { close_current_page }
      add(group, 'close-page-or-window') { close_page_or_window }
      add(group, 'close-other-pages') { @window.close_other_pages }
      add(group, 'open') { open_file }
      add(group, 'show-primary-menu') { @window.primary_menu_button.popup }
      add(group, 'focus-search') { @window.open_menu_button.popup }
      add(group, 'focus-neighbor', 'i') { |parameter| @window.focus_neighbor(parameter.get_int32) }
      add(group, 'toggle-fullscreen') { @window.toggle_fullscreen }
      add(group, 'fullscreen') { @window.fullscreen }
      add(group, 'unfullscreen') { @window.unfullscreen }
      add(group, 'show-preferences') { show_preferences }
    end
  end

  def page_actions
    @page_actions ||= Gio::SimpleActionGroup.new.tap do |group|
      add(group, 'save') { save }
      add(group, 'confirm-save') { save }
      add(group, 'save-as') { save_as }
      add(group, 'discard-changes', 'b') { discard_changes }
      add(group, 'infobar-discard-changes') { discard_changes }
      add(group, 'change', 'i') { |parameter| change_page(parameter.get_int32) }
      add(group, 'copy-all') { with_page(&:copy_all) }
      add(group, 'move-left') { move_page(-1) }
      add(group, 'move-right') { move_page(1) }
      add(group, 'move-to-new-window') { move_to_new_window }
      add(group, 'begin-search') { with_page { |page| page.begin_search(replace: false) } }
      add(group, 'begin-replace') { with_page { |page| page.begin_search(replace: true) } }
      add(group, 'change-encoding') { change_encoding }
      add(group, 'change-language') { change_language }
      add(group, 'print') { print_page }
      add(group, 'zoom-in') { with_page(&:zoom_in) }
      add(group, 'zoom-out') { with_page(&:zoom_out) }
      add(group, 'zoom-one') { with_page(&:zoom_one) }
      add(group, 'show-goto-line') { with_page(&:show_goto_line) }
      add(group, 'goto-line') { with_page(&:goto_line) }
    end
  end

  def settings_actions
    @settings_actions ||= Gio::SimpleActionGroup.new.tap do |group|
      SETTING_KEYS.each { |key| group.add_action(@window.settings.create_action(key)) }
    end
  end

  private

    def add(group, name, parameter_type = nil, &block)
      group.add_action(
        Gio::SimpleAction.new(name, parameter_type && GLib::VariantType.new(parameter_type)).tap do |action|
          action.signal_connect('activate') { |_action, parameter| block.call(parameter) }
        end,
      )
    end

    def with_page(&block) = @window.visible_page&.then(&block)

    def close_current_page
      with_page { |page| @window.remove_page(page) }
    end

    # Upstream's win.close-page-or-window closes the last tab's window rather
    # than leaving an empty one.
    def close_page_or_window
      @window.pages.length > 1 ? close_current_page : @window.close
    end

    def open_file
      Gtk::FileDialog.new.tap do |dialog|
        dialog.title = 'Open File'
        dialog.open_multiple(@window) do |_source, result|
          begin
            dialog.open_multiple_finish(result)&.then do |files|
              @window.session.open_files(files.to_a, window: @window)
            end
          rescue StandardError
            nil
          end
        end
      end
    end

    def save
      with_page do |page|
        page.document.file ? page.document.save { page.update_state } : save_as
      end
    end

    # Save As starts in the directory the last save used, which upstream keeps
    # in the "last-save-directory" key.
    def save_as
      with_page do |page|
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = 'Save As'
          dialog.initial_name = page.document.suggest_filename
          last_save_directory&.then { |directory| dialog.initial_folder = directory }

          dialog.save(@window) do |_source, result|
            begin
              dialog.save_finish(result)&.then do |file|
                page.document.save(file) { page.update_state }
                remember_save_directory(file)
                @window.session.document_seen(page.document)
                @window.update_state
              end
            rescue StandardError
              nil
            end
          end
        end
      end
    end

    def last_save_directory
      @window.settings.last_save_directory.then do |path|
        unless path.to_s.empty?
          Gio::File.new_for_path(path)
        end
      end
    end

    def remember_save_directory(file)
      file.parent&.then do |directory|
        @window.settings.last_save_directory = directory.path.to_s
      end
    end

    def discard_changes
      with_page do |page|
        page.discard_changes
        @window.update_state
      end
    end

    def change_page(index)
      @window.pages[index]&.then { |page| @window.visible_page = page }
    end

    def move_page(direction)
      with_page do |page|
        direction.negative? ? @window.move_page_left(page) : @window.move_page_right(page)
      end
    end

    def move_to_new_window
      with_page do |page|
        @window.session.create_window_no_draft.tap do |window|
          @window.detach_page(page)
          @window.session.move_page_to_window(page, window)
          window.present
        end
      end
    end

    def change_encoding
      with_page do |page|
        EditorEncodingDialog.new(page.document).build.present(@window)
      end
    end

    def change_language
      with_page do |page|
        current = page.document.language_id&.then { |id| GtkSource::LanguageManager.default.get_language(id) }
        EditorLanguageDialog.new(current) { |language| page.document.language_id = language&.id }
                            .build.present(@window)
      end
    end

    def print_page
      with_page { |page| EditorPrintOperation.new(page.document, page.view, @window.settings).run(@window) }
    end

    def show_preferences
      EditorPreferencesDialog.new(@window.settings).build.present(@window)
    end
end
