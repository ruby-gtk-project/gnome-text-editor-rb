# frozen_string_literal: true

require 'adwaita'

# EditorJoinedMenu presents several menu models as one.
#
# Ported from upstream's src/editor-joined-menu.c, which implements GMenuModel
# directly and translates positions between the joined menu and the menus it
# was built from, re-emitting items-changed as they change. A Ruby class
# cannot implement GMenuModel, so this port joins the menus into a GMenu of
# sections — one section per joined menu — and rebuilds it when a member
# changes, which is the same menu from the user's side.
class EditorJoinedMenu
  def initialize
    @menus = []
    @menu = Gio::Menu.new
  end

  # The model to hand to a GtkMenuButton or GtkTextView's extra menu.
  attr_reader :menu

  def n_menus = @menus.length

  def append_menu(model)
    tap do
      @menus << model
      watch(model)
      rebuild
    end
  end

  def prepend_menu(model)
    tap do
      @menus.unshift(model)
      watch(model)
      rebuild
    end
  end

  def remove_menu(model)
    tap do
      @menus.delete(model)
      rebuild
    end
  end

  def get_menu(index) = @menus[index]

  private

    # A joined menu follows its members: upstream connects to each one's
    # items-changed, and so does this.
    def watch(model)
      model.signal_connect('items-changed') { rebuild }
    end

    def rebuild
      @menu.remove_all
      @menus.each { |model| @menu.append_section(nil, model) }
    end
end
