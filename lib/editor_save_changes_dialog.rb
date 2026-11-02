# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_path'

# EditorSaveChangesDialog asks what to do with the unsaved documents when a
# window is closing.
#
# Ported from upstream's src/editor-save-changes-dialog.c: an AdwAlertDialog
# with Cancel, Discard (or "Discard All") and Save, carrying a preferences
# group of one checked row per unsaved document. Saving writes every checked
# document — to its own file, or to a suggested name under ~/Documents for a
# draft — and discards the rest, which is upstream's behaviour. The dialog
# reports the outcome through the block passed to #choose rather than through
# a GTask.
class EditorSaveChangesDialog < Adwaita::AlertDialog
  HEADING = 'Save Changes?'
  BODY = 'Open documents contain unsaved changes. Changes which are not saved will be permanently lost.'
  UNTITLED = 'Untitled Document'

  def initialize(pages)
    super(HEADING, BODY)

    @pages = pages
    @checks = {}
  end

  def build
    tap do
      add_response('cancel', '_Cancel')
      add_response('discard', @pages.length > 1 ? '_Discard All' : '_Discard')
      add_response('save', '_Save')
      set_response_appearance('discard', Adwaita::ResponseAppearance::DESTRUCTIVE)
      set_response_appearance('save', Adwaita::ResponseAppearance::SUGGESTED)
      self.close_response = 'cancel'
      self.default_response = 'save'
      self.prefer_wide_layout = true
      self.extra_child = group

      @pages.each { |page| group.add(row_for(page)) }
    end
  end

  # Presents the dialog over a window and yields :saved, :discarded or
  # :cancelled once the user has answered.
  def choose(parent, &block)
    tap do
      present(parent)

      signal_connect('response') do |_dialog, response|
        block.call(apply(response))
      end
    end
  end

  def group = @group ||= Adwaita::PreferencesGroup.new

  private

    # Applies the answer: save writes the checked documents and discards the
    # unchecked ones, discard throws every change away, cancel does nothing.
    def apply(response)
      case response
      when 'save' then save_checked
      when 'discard' then discard_all
      else :cancelled
      end
    end

    def save_checked
      @pages.each do |page|
        if @checks.fetch(page).active?
          page.document.save(target_file(page.document))
        else
          page.discard_changes
        end
      end
      :saved
    end

    def discard_all
      @pages.each(&:discard_changes)
      :discarded
    end

    # A document with a file saves to it; a draft gets a suggested name in the
    # user's Documents directory, which is where upstream points it.
    def target_file(document)
      document.file || document.suggest_file(documents_directory)
    end

    def documents_directory
      Gio::File.new_for_path(GLib.get_user_special_dir(GLib::UserDirectory::DIRECTORY_DOCUMENTS) || GLib.home_dir)
    end

    def row_for(page)
      page.document.then do |document|
        Adwaita::ActionRow.new.tap do |row|
          row.use_markup = false
          row.title = row_title(document)
          row.subtitle = row_subtitle(document)
          check_for(page).then do |check|
            row.add_prefix(check)
            row.activatable_widget = check
          end
        end
      end
    end

    def check_for(page)
      @checks[page] ||= Gtk::CheckButton.new.tap do |check|
        check.active = true
        check.valign = :center
      end
    end

    # Translators: %s is replaced with the title of the file.
    def row_title(document)
      document.file ? document.title : format('%s (new)', document.title.empty? ? UNTITLED : document.title)
    end

    def row_subtitle(document)
      (document.file ? document.file.parent : documents_directory).then do |directory|
        if directory.nil?
          '/'
        elsif directory.native?
          EditorPath.collapse(directory.path)
        else
          directory.uri
        end
      end
    end
end
