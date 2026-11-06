# frozen_string_literal: true

require 'adwaita'
require_relative 'editor_fullscreen_box'
require_relative 'editor_open_popover'
require_relative 'editor_properties_panel'
require_relative 'editor_recoloring'
require_relative 'editor_statusbar'
require_relative 'editor_theme_selector'
require_relative 'editor_utils'
require_relative 'editor_window_actions'
require_relative 'editor_window_dnd'

# EditorWindow is the main window: the tab view, the header bar that titles
# whichever tab is showing, the properties sidebar and the statusbar.
#
# Ported from upstream's src/editor-window.c and src/editor-window.ui.
# Upstream derives from AdwApplicationWindow, which the Ruby bindings cannot
# subclass, so this port derives from GtkApplicationWindow and puts an
# AdwBreakpointBin inside it to carry the two breakpoints the template
# declares — the window itself is what owns them upstream. Everything else is
# the template: the AdwMultiLayoutView with its wide and narrow layouts, the
# four slots, the AdwOverlaySplitView for the properties panel, the
# AdwBottomSheet the narrow layout shows it in, and the two menus.
class EditorWindow < Gtk::ApplicationWindow
  CSS_CLASS = 'org-gnome-TextEditor'
  NARROW_BREAKPOINT = 'max-width: 650sp'
  COMPACT_BREAKPOINT = 'max-width: 400sp'

  def initialize(application, session, settings)
    super(application)

    @session = session
    @settings = settings
    @pages = []
    @actions = EditorWindowActions.new(self)
    @dnd = EditorWindowDnd.new(self)

    add_css_class(CSS_CLASS)
    self.title = 'Text Editor'
    self.width_request = 360
    set_default_size(800, 600)
  end

  attr_reader :session, :settings, :pages

  # Assembles the window. Only structure and behaviour here; every widget's
  # own configuration is in its accessor.
  def build
    tap do
      self.child = breakpoint_bin

      breakpoint_bin.tap do |bin|
        bin.child = multi_layout
        bin.add_breakpoint(narrow_breakpoint)
        bin.add_breakpoint(compact_breakpoint)
      end

      multi_layout.tap do |layouts|
        layouts.add_layout(wide_layout)
        layouts.add_layout(narrow_layout)
        layouts.set_child('header_bar', header_bar)
        layouts.set_child('tab_bar', tab_bar)
        layouts.set_child('content', stack)
        layouts.set_child('properties', properties_panel.build)
        layouts.layout_name = 'wide'
      end

      fullscreen_box.build.tap do |box|
        box.add_top(Adwaita::LayoutSlot.new('header_bar'))
        box.add_top(Adwaita::LayoutSlot.new('tab_bar'))
        box.content = split_view
      end

      split_view.tap do |view|
        view.content = Adwaita::LayoutSlot.new('content')
        view.sidebar = Adwaita::LayoutSlot.new('properties')
      end

      narrow_box.build.tap do |box|
        box.add_top(Adwaita::LayoutSlot.new('header_bar'))
        box.add_top(Adwaita::LayoutSlot.new('tab_bar'))
        box.content = Adwaita::LayoutSlot.new('content')
      end

      bottom_sheet.tap do |sheet|
        sheet.content = narrow_box
        sheet.sheet = narrow_properties_toolbar
        narrow_properties_toolbar.content = Adwaita::LayoutSlot.new('properties')
      end

      stack.tap do |pages|
        pages.add_named(tabs_box, 'tabs')
        pages.add_named(empty_page, 'empty')

        tabs_box.tap do |box|
          box.append(tab_view)
          box.append(statusbar.build)
        end
      end

      header_bar.tap do |bar|
        bar.title_widget = title_box
        bar.pack_start(open_menu_button)
        bar.pack_start(new_button)
        bar.pack_end(restore_button)
        bar.pack_end(primary_menu_button)
        bar.pack_end(properties_button)
      end

      title_box.tap do |box|
        box.append(title_center)
        box.append(subtitle_center)

        title_center.tap do |center|
          center.set_start_widget(is_modified)
          center.set_center_widget(title_label)
        end

        subtitle_center.tap do |center|
          center.set_start_widget(indicator)
          center.set_center_widget(subtitle_label)
        end
      end

      add_controller(window_shortcuts)
      @actions.build
      @dnd.build

      connect_tab_view
      connect_properties
      connect_open_popover
      connect_close_request

      @settings.on_changed('recolor-window') { apply_recoloring }

      update_state
    end
  end

  # Adds a page as a new tab and selects it.
  def add_page(page)
    tap do
      page.window = self
      unless @pages.include?(page)
        @pages << page
      end
      tab_view.append(page.build).tap do |tab|
        bind_tab(tab, page)
        tab_view.selected_page = tab
      end
      page.on_changed { update_state }
      update_state
    end
  end

  def remove_page(page)
    tap do
      tab_for(page)&.then { |tab| tab_view.close_page(tab) }
    end
  end

  # Takes the page out of the tab view without asking to save, which is what
  # moving a tab to another window needs.
  def detach_page(page)
    tap do
      tab_for(page)&.then do |tab|
        @tabs.delete(page)
        @pages.delete(page)
        tab_view.close_page(tab)
        update_state
      end
    end
  end

  def visible_page
    tab_view.selected_page&.then { |tab| page_for(tab) }
  end

  def visible_page=(page)
    tab_for(page)&.then { |tab| tab_view.selected_page = tab }
  end

  # The "is-active" property, read through get_property: the Ruby bindings
  # generate no predicate for it on GtkWindow.
  def active? = get_property('is-active')

  def default_width = default_size.first

  def default_height = default_size.last

  # Walks to the next or previous tab: upstream's win.focus-neighbor.
  def focus_neighbor(direction)
    tap do
      direction.negative? ? tab_view.select_previous_page : tab_view.select_next_page
    end
  end

  # Reorders the visible tab within the tab view: page.move-left and
  # page.move-right.
  def move_page_left(page)
    tap { tab_for(page)&.then { |tab| tab_view.reorder_backward(tab) } }
  end

  def move_page_right(page)
    tap { tab_for(page)&.then { |tab| tab_view.reorder_forward(tab) } }
  end

  def close_other_pages
    tap do
      tab_view.selected_page&.then { |tab| tab_view.close_other_pages(tab) }
    end
  end

  # Pushes the visible page's state into the header bar, the statusbar and the
  # actions — the one place the window's chrome is refreshed from.
  def update_state
    tap do
      visible_page.then do |page|
        if page
          zoom_level_button.label = "#{(page.zoom_level * 100).round}%"
        else
          zoom_level_button.label = '100%'
        end
        if page
          title_label.label = page.title
        else
          title_label.label = 'Text Editor'
        end
        if page
          subtitle_label.label = page.subtitle
        else
          subtitle_label.label = ''
        end
        if page
          is_modified.visible = page.modified?
        else
          is_modified.visible = false
        end
        if page
          indicator.visible = page.document.externally_modified?
        else
          indicator.visible = false
        end
        indicator.icon_name = 'document-modified-symbolic'
        statusbar.visible = !page.nil?
        if @pages.empty?
          stack.visible_child_name = 'empty'
        else
          stack.visible_child_name = 'tabs'
        end
        properties_panel.page = page
        unless @bound_page.equal?(page)
          statusbar.bind_page(page)
        end
        @bound_page = page
        if page
          self.title = page.title
        else
          self.title = 'Text Editor'
        end
      end

      @actions.update(visible_page)
      apply_recoloring
    end
  end

  def toggle_fullscreen
    tap { fullscreened? ? unfullscreen : fullscreen }
  end

  def statusbar = @statusbar ||= EditorStatusbar.new

  def properties_panel = @properties_panel ||= EditorPropertiesPanel.new

  def open_popover
    @open_popover ||= EditorOpenPopover.new(@session.recents).build
  end

  def breakpoint_bin = @breakpoint_bin ||= Adwaita::BreakpointBin.new.tap do |bin|
    bin.width_request = 360
    bin.height_request = 200
  end

  def multi_layout = @multi_layout ||= Adwaita::MultiLayoutView.new

  def wide_layout
    @wide_layout ||= Adwaita::Layout.new(fullscreen_box).tap { |layout| layout.name = 'wide' }
  end

  def narrow_layout
    @narrow_layout ||= Adwaita::Layout.new(bottom_sheet).tap { |layout| layout.name = 'narrow' }
  end

  def fullscreen_box = @fullscreen_box ||= EditorFullscreenBox.new

  def narrow_box = @narrow_box ||= EditorFullscreenBox.new

  def bottom_sheet = @bottom_sheet ||= Adwaita::BottomSheet.new

  def narrow_properties_toolbar = @narrow_properties_toolbar ||= Adwaita::ToolbarView.new

  def split_view
    @split_view ||= Adwaita::OverlaySplitView.new.tap do |view|
      view.sidebar_position = :end
      view.show_sidebar = false
      view.min_sidebar_width = 350
    end
  end

  def stack = @stack ||= Gtk::Stack.new.tap { |widget| widget.hexpand = true }

  def tabs_box = @tabs_box ||= Gtk::Box.new(:vertical, 0)

  def tab_view
    @tab_view ||= Adwaita::TabView.new.tap do |view|
      view.hexpand = true
      view.vexpand = true
      view.menu_model = tab_menu
    end
  end

  def tab_bar = @tab_bar ||= Adwaita::TabBar.new.tap { |bar| bar.view = tab_view }

  def empty_page
    @empty_page ||= Adwaita::StatusPage.new.tap do |page|
      page.title = 'Open a Document'
      page.description = 'Create a new document (Ctrl+N), or open an existing one (Ctrl+O)'
      page.child = empty_button
    end
  end

  def empty_button
    @empty_button ||= Gtk::Button.new.tap do |button|
      button.label = '_New Empty File'
      button.use_underline = true
      button.action_name = 'session.new-draft'
      button.halign = :center
      button.add_css_class('suggested-action')
      button.add_css_class('pill')
    end
  end

  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def title_box
    @title_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.hexpand = true
      box.valign = :center
      box.margin_start = 12
      box.margin_end = 12
    end
  end

  def title_center = @title_center ||= Gtk::CenterBox.new.tap { |box| box.hexpand = true }

  def subtitle_center = @subtitle_center ||= Gtk::CenterBox.new

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.ellipsize = :middle
      label.add_css_class('title')
    end
  end

  def subtitle_label
    @subtitle_label ||= Gtk::Label.new.tap do |label|
      label.ellipsize = :middle
      label.add_css_class('subtitle')
    end
  end

  def is_modified
    @is_modified ||= Gtk::Label.new('•').tap do |label|
      label.halign = :end
      label.hexpand = true
      label.visible = false
    end
  end

  def indicator
    @indicator ||= Gtk::Image.new.tap do |image|
      image.hexpand = true
      image.halign = :end
      image.visible = false
      image.margin_end = 6
      image.pixel_size = 12
      image.add_css_class('subtitle')
    end
  end

  def open_menu_button
    @open_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.tooltip_text = 'Recently Used Documents'
      button.add_css_class('flat')
      button.popover = open_popover
      button.child = open_button_stack
    end
  end

  # Wide shows "Open ▾"; the 400sp breakpoint swaps it for a folder icon.
  def open_button_stack
    @open_button_stack ||= Gtk::Stack.new.tap do |stack|
      stack.add_named(open_button_wide, 'wide')
      stack.add_named(Gtk::Image.new(icon_name: 'folder-symbolic'), 'narrow')
      stack.visible_child_name = 'wide'
      stack.hhomogeneous = false
    end
  end

  def open_button_wide
    @open_button_wide ||= Gtk::Box.new(:horizontal, 3).tap do |box|
      box.append(Gtk::Label.new('_Open').tap { |label| label.use_underline = true })
      box.append(Gtk::Image.new(icon_name: 'pan-down-symbolic'))
    end
  end

  def new_button
    @new_button ||= Gtk::Button.new.tap do |button|
      button.action_name = 'session.new-draft'
      button.icon_name = 'tab-new-symbolic'
      button.tooltip_text = 'New Tab'
    end
  end

  def restore_button
    @restore_button ||= Gtk::Button.new.tap do |button|
      button.tooltip_text = 'Leave Fullscreen'
      button.icon_name = 'view-restore-symbolic'
      button.action_name = 'win.unfullscreen'
      button.visible = false
    end
  end

  def primary_menu_button
    @primary_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.tooltip_text = 'Main Menu'
      button.icon_name = 'open-menu-symbolic'
      button.popover = primary_menu_popover
    end
  end

  def properties_button
    @properties_button ||= Gtk::ToggleButton.new.tap do |button|
      button.tooltip_text = 'Document Properties'
      button.icon_name = 'info-outline-symbolic'
      button.add_controller(properties_shortcut)
    end
  end

  # The theme selector and the zoom buttons are the two custom items upstream's
  # menu model declares.
  def primary_menu_popover
    @primary_menu_popover ||= Gtk::PopoverMenu.new(primary_menu).tap do |popover|
      popover.add_child(theme_selector.build, 'theme')
      popover.add_child(zoom_box, 'zoom')
    end
  end

  def theme_selector = @theme_selector ||= EditorThemeSelector.new

  def zoom_box
    @zoom_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.add_css_class('linked')
      box.homogeneous = true
      box.append(zoom_out_button)
      box.append(zoom_level_button)
      box.append(zoom_in_button)
    end
  end

  def zoom_out_button
    @zoom_out_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'zoom-out-symbolic'
      button.tooltip_text = 'Zoom Out'
      button.action_name = 'page.zoom-out'
      button.add_css_class('flat')
    end
  end

  def zoom_in_button
    @zoom_in_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = 'zoom-in-symbolic'
      button.tooltip_text = 'Zoom In'
      button.action_name = 'page.zoom-in'
      button.add_css_class('flat')
    end
  end

  def zoom_level_button
    @zoom_level_button ||= Gtk::Button.new.tap do |button|
      button.label = '100%'
      button.tooltip_text = 'Reset Zoom'
      button.action_name = 'page.zoom-one'
      button.add_css_class('flat')
    end
  end

  def primary_menu
    @primary_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, Gio::Menu.new.tap { |section| section.append_item(custom_item('theme')) })
      menu.append_section(nil, Gio::Menu.new.tap { |section| section.append_item(custom_item('zoom')) })
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_New Window', 'app.new-window')
              end,
      )
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_Save', 'page.save')
                section.append('Save _As…', 'page.save-as')
                section.append_item(
                  Gio::MenuItem.new('_Discard Changes…', nil).tap do |item|
                            item.set_detailed_action('page.discard-changes(false)')
                          end,
                )
              end,
      )
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_Find/Replace…', 'page.begin-search')
              end,
      )
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('Fullscreen', 'win.fullscreen')
                section.append('Leave Fullscreen', 'win.unfullscreen')
              end,
      )
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('P_references', 'win.show-preferences')
                section.append('_Keyboard Shortcuts', 'app.shortcuts')
                section.append('A_bout Text Editor', 'app.about')
              end,
      )
    end
  end

  def tab_menu
    @tab_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('Move _Left', 'page.move-left')
                section.append('Move _Right', 'page.move-right')
              end,
      )
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('_Move to New Window', 'page.move-to-new-window')
              end,
      )
      menu.append_section(
        nil,
        Gio::Menu.new.tap do |section|
                section.append('Close _Other Tabs', 'win.close-other-pages')
                section.append('_Close', 'win.close-current-page')
              end,
      )
    end
  end

  private

    def recoloring_css_provider = @recoloring_css_provider ||= Gtk::CssProvider.new

    # Upstream's chrome-recolouring: reapplies, on every update_state, a
    # CssProvider carrying EditorRecoloring's @define-color rules for the
    # visible page's style scheme — or clears it when there is no page, the
    # scheme is Adwaita, or the "recolor-window" setting is off.
    def apply_recoloring
      if @settings.recolor_window?
        css = visible_page&.document&.style_scheme&.then { |scheme| EditorRecoloring.generate_css(scheme) }
      else
        css = nil
      end
      recoloring_css_provider.load(data: css || '')
      Gtk::StyleContext.add_provider_for_display(
        Gdk::Display.default, recoloring_css_provider, Gtk::StyleProvider::PRIORITY_APPLICATION,
      )
    end

    def custom_item(name)
      Gio::MenuItem.new(nil, nil).tap { |item| item.set_attribute_value('custom', GLib::Variant.new(name)) }
    end

    def narrow_breakpoint
      @narrow_breakpoint ||= Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse(NARROW_BREAKPOINT))
                                               .tap do |breakpoint|
        breakpoint.add_setter(multi_layout, 'layout-name', 'narrow')
      end
    end

    def compact_breakpoint
      @compact_breakpoint ||= Adwaita::Breakpoint.new(Adwaita::BreakpointCondition.parse(COMPACT_BREAKPOINT))
                                                 .tap do |breakpoint|
        breakpoint.add_setter(multi_layout, 'layout-name', 'narrow')
        breakpoint.add_setter(open_button_stack, 'visible-child-name', 'narrow')
      end
    end

    # F11 and Alt+W, the two shortcuts upstream's template installs on the
    # window itself.
    def window_shortcuts
      @window_shortcuts ||= Gtk::ShortcutController.new.tap do |controller|
        controller.add_shortcut(EditorUtils.shortcut('F11', 'win.toggle-fullscreen'))
        controller.add_shortcut(EditorUtils.shortcut('<Alt>w', 'settings.wrap-text'))
      end
    end

    # F9 toggles the properties panel, scoped to the button as upstream's
    # managed shortcut controller is.
    def properties_shortcut
      @properties_shortcut ||= Gtk::ShortcutController.new.tap do |controller|
        controller.scope = :managed
        controller.add_shortcut(
          Gtk::Shortcut.new(EditorUtils.shortcut_trigger('F9'), Gtk::ActivateAction.get),
        )
      end
    end

    def tabs = @tabs ||= {}

    def bind_tab(tab, page)
      tabs[page] = tab
      tab.title = page.title
      tab.tooltip = page.document.uri.to_s
      page.on_changed do
        tab.title = page.title
        tab.tooltip = page.document.uri.to_s
      end
    end

    def tab_for(page) = tabs[page]

    def page_for(tab) = tabs.key(tab)

    def connect_tab_view
      tab_view.signal_connect('notify::selected-page') { update_state }

      # Upstream's on_tab_view_close_page_cb: confirm unsaved changes, then
      # let the close through.
      tab_view.signal_connect('close-page') do |_view, tab|
        page_for(tab).then do |page|
          if page.nil? || !page.modified?
            finish_close(tab, page, true)
          else
            @actions.confirm_close(page) { |allow| finish_close(tab, page, allow) }
          end
        end
        true
      end

      tab_view.signal_connect('create-window') { @session.create_window_no_draft.tap(&:present).tab_view }
    end

    def finish_close(tab, page, allow)
      if allow
        page&.then do |closing|
          tabs.delete(closing)
          @pages.delete(closing)
          @session.remove_page(closing)
        end
      end

      tab_view.close_page_finish(tab, allow)
      update_state
    end

    def connect_properties
      properties_button.signal_connect('toggled') do
        split_view.show_sidebar = properties_button.active?
        bottom_sheet.open = properties_button.active?
      end

      split_view.signal_connect('notify::show-sidebar') do
        properties_button.active = split_view.show_sidebar?
      end
    end

    # Closing the window asks about every unsaved tab first, which is what
    # upstream's close handler does before letting the window go.
    def connect_close_request
      signal_connect('close-request') do
        if @closing
          false
        else
          @actions.confirm_close_window do |allow|
            if allow
              @closing = true
              @session.remove_window(self)
              close
            end
          end
          true
        end
      end
    end

    def connect_open_popover
      open_popover.on_activate { |item| item.open(@session, self) }
      open_popover.on_remove { |item| @session.forget(uri: item.uri, draft_id: item.draft_id) }

      signal_connect('notify::fullscreened') do
        restore_button.visible = fullscreened?
        header_bar.show_start_title_buttons = !fullscreened?
        header_bar.show_end_title_buttons = !fullscreened?
        fullscreen_box.fullscreen = fullscreened?
        narrow_box.fullscreen = fullscreened?
      end
    end
end
