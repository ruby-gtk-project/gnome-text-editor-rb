# frozen_string_literal: true

require 'adwaita'

# EditorPageActions installs the search actions a page answers for itself and
# keeps them enabled only while there is something to act on.
#
# Ported from upstream's src/editor-page-actions.c. Upstream installs both the
# "search." and the "page." actions here as class actions, and the window
# installs a second set of "page." actions of its own; GTK's action muxer
# merges the two. The Ruby bindings have no class-action API, so these live in
# a GSimpleActionGroup inserted on the page, and a GSimpleActionGroup shadows
# rather than merges with the one above it — so only the "search." prefix
# belongs to the page, and every "page." action is the window's, where it acts
# on whichever page is visible. The enabled-state updates are upstream's: all
# four stay insensitive until the search bar reports a match.
class EditorPageActions
  def initialize(page)
    @page = page
  end

  def build
    tap do
      @page.insert_action_group('search', search_actions)
      update
    end
  end

  def update
    tap do
      search_actions.lookup_action('move-next').enabled = @page.search_bar.can_move?
      search_actions.lookup_action('move-previous').enabled = @page.search_bar.can_move?
      search_actions.lookup_action('replace-one').enabled = @page.search_bar.can_replace?
      search_actions.lookup_action('replace-all').enabled = @page.search_bar.can_replace_all?
    end
  end

  def search_actions
    @search_actions ||= Gio::SimpleActionGroup.new.tap do |group|
      add(group, 'hide') { @page.hide_search }
      add(group, 'move-next', 'b') { @page.move_next_search }
      add(group, 'move-previous', 'b') { @page.move_previous_search }
      add(group, 'replace-one') { replace_one }
      add(group, 'replace-all') { replace_all }
    end
  end

  private

    def add(group, name, parameter_type = nil, &block)
      group.add_action(
        Gio::SimpleAction.new(name, parameter_type && GLib::VariantType.new(parameter_type)).tap do |action|
          action.signal_connect('activate') { block.call }
        end,
      )
    end

    # Replacing one match moves on to the next, which is what makes repeated
    # Replace walk through the document.
    def replace_one
      if @page.search_bar.can_replace?
        @page.search_bar.replace
        @page.scroll_to_insert
        @page.search_bar.move_next
      end
    end

    def replace_all
      if @page.search_bar.can_replace_all?
        @page.search_bar.replace_all
        @page.scroll_to_insert
      end
    end
end
