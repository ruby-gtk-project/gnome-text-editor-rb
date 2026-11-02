# gnome-text-editor — upstream component inventory

Survey of `origin/main` (GNOME Text Editor, C/GTK4/libadwaita/GtkSourceView)
against `lib/` on the `ruby` branch. Produced with the
`component-identification` skill; the house shape is the `ruby-gtk` skill plus
the pilot port at `../gnome-contacts-rb`.

Upstream tree: 300 files, 100 under `src/`, 17 `.ui` templates + 1 standalone
`.ui` (shortcuts), 1 GSettings schema (26 keys), 1 GResource manifest,
59 locales in `po/`.

**State of the port: round 1 is in, the GtkSourceView-dependent tail is not.**
`lib/` holds 45 Ruby files, 7,491 lines, and `test/drive_editor.rb` drives the
app headless. Present: the application and its action table, the shortcuts
dialog, the window with its multi-layout view, breakpoints, both menus, its
action table and its drop target, the page and its actions, the source view
(over `Gtk::TextView`, not `GtkSource::View`), the statusbar, position label,
info bar, search bar and search entry, the open popover with its sidebar row,
model and item, the preferences dialog and its five row classes, the encoding
dialog and row, the save-changes dialog, the properties panel, the theme
selector, the fullscreen box, and every model and helper in section 6 except
the settings-provider stack.

Absent, and mostly for one reason — they need `GtkSource::View`, where this
round builds over plain `Gtk::TextView`: the source map, recoloring, the
bundled style schemes, the language dialog and language row, the
settings-provider stack (`editor-page-settings`, its provider, `-gsettings`,
`defaults/`, `editorconfig/`, `modelines/`), Vim keybindings and the print
operation. Two more are independent of it and simply not written yet:
`editor-focus-chain.c` (`win.focus-neighbor`) and `editor-source-iter.c` (the
word and paragraph movement and deletion shortcuts). Also
absent: `po/` and any gettext call, the four bundled symbolic icons, and the
desktop/metainfo/D-Bus data files.

A note on the mapping: the house style is one upstream source file to one
`lib/<thing>.rb`, but upstream splits almost every component across a `.c`, a
`-private.h` and a `.ui`. Those three are one component and become one Ruby
file. Upstream's `-actions.c` files are also not separate components — they are
the action tables of the class they are named for — but they are large enough
(27 window actions, 7 page actions) that they get their own `*_actions.rb`
mixins, as noted.

---

## 1. Application shell

### `src/editor-application.c`, `src/editor-application-actions.c`, `src/main.c` → `lib/gnome_text_editor/application.rb` + `lib/application_actions.rb`

The application object: command-line handling (`--ignore-session`,
`--new-window`, `--standalone`, `--version`), the app-level action table, the
About dialog and the Clear-History alert.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Application` | 1 | — | `activate`, `open`, `command-line`, `startup` | `Adwaita::Application` is broken in the Ruby bindings — use `Gtk::Application` |
| `Adw.AboutDialog` | 1 | — | `app.about` | `adw_show_about_dialog`: application-name "Text Editor", developer-name "The GNOME Project", translator-credits |
| `Adw.AlertDialog` | 1 | `destructive-action` on `clear-all` | `app.clear-history` | "Clear File History?" / "This action cannot be undone"; responses `cancel`, `clear-all` |

App actions: `app.about`, `app.new-window`, `app.help`, `app.quit`,
`app.remove-recent`, `app.clear-history`, `app.shortcuts`.
Accelerators: `app.quit` = `<ctrl>q`, `app.help` = `F1`.

Status: **present** — lib/gnome_text_editor/application.rb, lib/application_actions.rb.

### `src/shortcuts-dialog.ui` → `lib/shortcuts_dialog.rb`

A standalone `.ui` with no backing `.c` — a component no widget subclass owns.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ShortcutsDialog` | 1 | — | `app.shortcuts`, `<ctrl>question` | top-level named object, not a template |
| `Adw.ShortcutsSection` | 10 | — | — | Windows, Zoom, Documents, Copy and Paste, Undo and Redo, Editing, Selections, Movements, Deletion, General |
| `Adw.ShortcutsItem` | 48 | — | — | one per accelerator; all titles carry `context="shortcut window"` |

Status: **present** — lib/shortcuts_dialog.rb.

---

## 2. The window

### `src/editor-window.c`, `src/editor-window.ui`, `src/editor-window-actions.c`, `src/editor-window-dnd.c` → `lib/editor_window.rb` + `lib/editor_window_actions.rb` + `lib/editor_window_dnd.rb`

The main window: a tab view over documents, an adaptive wide/narrow layout, a
header bar with the open popover and primary menu, and the properties side
panel.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` (template root) | 1 | `org-gnome-TextEditor` | `title_query_tooltip_cb` | Ruby port uses `Adwaita::ApplicationWindow` with a `Gtk::Application` |
| `Adw.Breakpoint` | 2 | — | — | drives `multi_layout` between the `wide` and `narrow` layouts |
| `Gtk.ShortcutController` | 2 | — | `win.alternate-help-overlay`, properties toggle | one on the window, one on `properties_button` |
| `Adw.MultiLayoutView` | 1 | — | — | id `multi_layout` |
| `Adw.Layout` | 2 | — | — | `wide` and `narrow` |
| `Adw.LayoutSlot` | 8 | — | — | header bar, tab bar, content, sidebar across both layouts |
| `Adw.BottomSheet` | 1 | — | — | narrow layout only — hosts the properties panel |
| `Adw.OverlaySplitView` | 1 | — | — | wide layout — properties panel as sidebar |
| `Adw.ToolbarView` | 1 | — | — | narrow layout's sheet |
| `EditorFullscreenBox` | 2 | — | — | one per layout |
| `Gtk.Stack` | 2 | — | — | `stack` (tabs / empty), `open_button_stack` (wide / narrow) |
| `Adw.TabView` | 1 | — | `close-page`, `setup-menu`, `create-window` | id `tab_view` |
| `Adw.TabBar` | 1 | — | — | id `tab_bar` |
| `Adw.StatusPage` | 1 | — | — | id `empty`, title "Open a Document" |
| `Gtk.Button` | 4 | `suggested-action`+`large-button`+`pill` (empty-state); plain (new, restore) | `session.new-draft` ×2, `win.unfullscreen` | "_New Empty File", `new_button`, `restore_button` |
| `Adw.HeaderBar` | 1 | — | — | id `header_bar` |
| `Gtk.CenterBox` | 2 | — | `query-tooltip` | title row and subtitle row |
| `Gtk.Label` | 5 | `title`, `subtitle` | — | `title`, `subtitle`, `is_modified` ("•"), "_Open" |
| `Gtk.Image` | 3 | `subtitle` | — | `indicator`, `pan-down-symbolic`, `folder-symbolic` |
| `Gtk.MenuButton` | 2 | `flat` | `win.show-primary-menu` | `open_menu_button` (hosts `EditorOpenPopover`), `primary_menu` (`open-menu-symbolic`) |
| `Gtk.ToggleButton` | 1 | — | — | `properties_button`, `info-outline-symbolic`, `F9` |
| `EditorPropertiesPanel` | 1 | — | — | composite, own file |
| `EditorStatusbar` | 1 | — | — | composite, own file |
| `EditorOpenPopover` | 1 | — | — | composite, own file |
| `Gtk.Box` | 4 | — | — | layout |

Menu models in this file: `primary_menu_model` (16 items across 6 sections —
undo/redo, _New Window, _Save, Save _As…, _Discard Changes…, _Find/Replace…,
_Print…, Fullscreen, Leave Fullscreen, theme-selector custom slot,
P_references, _Keyboard Shortcuts, A_bout Text Editor) and `tab_menu`
(Move _Left, Move _Right, _Move to New Window, Close _Other Tabs, _Close).
The primary menu's `custom:` slot hosts `EditorThemeSelector`.

Window actions (`src/editor-window-actions.c`): `win.open`,
`win.close-current-page`, `win.close-other-pages`, `win.close-page-or-window`,
`win.undo-close-page`, `win.focus-search`, `win.focus-neighbor`,
`win.show-primary-menu`, `win.show-preferences`, `win.fullscreen`,
`win.unfullscreen`, `win.toggle-fullscreen`, `win.alternate-help-overlay`.
It also owns the `Gtk.FileDialog` for Open
(`gtk_file_dialog_open_multiple_text_files`, with filters and an encoding
chooser) and two `Adw.AlertDialog`s for close-with-unsaved-changes.

`src/editor-window-dnd.c` installs a `Gtk.DropTarget` on the window for
dropped files/URIs — behaviour with no widget of its own.

Status: **present** — lib/editor_window.rb, lib/editor_window_actions.rb, lib/editor_window_dnd.rb.

### `src/editor-fullscreen-box.c` → `lib/editor_fullscreen_box.rb`

A `Gtk.Widget` subclass with `Gtk.Buildable`, `Gtk.BinLayout` and a motion
`Gtk.EventControllerMotion`: reveals the header bar when the pointer nears the
top edge in fullscreen. Status: **present** — lib/editor_fullscreen_box.rb.

### `src/editor-theme-selector.c`, `src/editor-theme-selector.ui` → `lib/editor_theme_selector.rb`

The light/dark/follow control in the primary menu's `custom:` slot.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root, `Gtk.BinLayout`) | 1 | — | — | — |
| `Gtk.Box` | 1 | — | — | id `box` |
| `Gtk.CheckButton` | 3 | `theme-selector` + one of `follow`/`light`/`dark` | `settings.style-variant` | tooltips "Follow System Style", "Light Style", "Dark Style"; a11y labels "Follow system style", "Light style", "Dark style" |

Status: **present** — lib/editor_theme_selector.rb.

---

## 3. The document page

### `src/editor-page.c`, `src/editor-page.ui`, `src/editor-page-actions.c` → `lib/editor_page.rb` + `lib/editor_page_actions.rb`

One open document: the source view, the overview map, the go-to-line bar, the
search bar and the position label.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | — | — | — |
| `EditorInfoBar` | 1 | — | — | id `infobar`, composite |
| `Adw.ToolbarView` | 1 | — | — | id `toolbar_view` |
| `Gtk.Overlay` | 1 | — | `get-child-position` | id `overlay` |
| `Gtk.ScrolledWindow` | 1 | — | — | id `scroller` |
| `EditorSourceView` | 1 | `editor` | `notify::font-scale` | id `view`, composite |
| `EditorSourceMap` | 1 | — | — | id `map`, composite |
| `Gtk.ProgressBar` | 1 | `osd` | — | id `progress_bar`, load/save progress |
| `EditorPositionLabel` | 1 | — | — | id `position_label`, composite |
| `Gtk.Revealer` | 2 | — | — | `goto_line_revealer`, `search_revealer` |
| `Gtk.Box` | 4 | `toolbar` (go-to-line) | — | layout |
| `Gtk.Label` | 1 | `heading` | — | "Go to Line" |
| `Gtk.Entry` | 1 | — | `activate` → `goto_line_entry_activate_cb` | `goto_line_entry` |
| `Gtk.Button` | 1 | `suggested-action` | `page.goto-line` | "Go" |
| `Adw.Clamp` | 1 | — | — | wraps the search bar |
| `EditorSearchBar` | 1 | — | — | id `search_bar`, composite |
| `Gtk.FileDialog` | 1 | — | `page.save-as` | `gtk_file_dialog_save_text_file`, with initial file/folder/name and encoding |
| `Adw.AlertDialog` | 1 | — | — | "Failed to save document" |

Page actions (`editor-page-actions.c` + `editor-window-actions.c` targets):
`page.save`, `page.save-as`, `page.confirm-save`, `page.discard-changes`,
`page.infobar-discard-changes`, `page.change-language`, `page.change-encoding`,
`page.change` (settings sub-actions), `page.print`, `page.copy-all`,
`page.move-left`, `page.move-right`, `page.move-to-new-window`,
`page.begin-search`, `page.begin-replace`, `page.show-goto-line`,
`page.goto-line`, `page.zoom-in`, `page.zoom-out`, `page.zoom-one`.

Status: **present** — lib/editor_page.rb, lib/editor_page_actions.rb.

### `src/editor-source-view.c` → `lib/editor_source_view.rb`

`GtkSource.View` subclass: font scaling, draw-spaces, snippets, spell
checking via libspelling, the `<ctrl>period` emoji chooser, line-height,
bracket matching, and the `editor` CSS class. Status: **present** — lib/editor_source_view.rb.

### `src/editor-source-map.c`, `src/editor-source-map.ui` → `lib/editor_source_map.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | — | — | — |
| `GtkSource.Map` | 1 | — | — | id `map`, binds its font and view |

Status: **absent** — lib/editor_source_map.rb not written.

### `src/editor-position-label.c`, `src/editor-position-label.ui` → `lib/editor_position_label.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | `numeric` | — | — |
| `Gtk.Box` | 1 | — | — | id `box` |
| `Gtk.Label` | 4 | — | — | "Ln", `line`, "Col", `column` |

Status: **present** — lib/editor_position_label.rb.

### `src/editor-statusbar.c`, `src/editor-statusbar.ui` → `lib/editor_statusbar.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | `statusbar` (on `box`, per `style.css`) | — | — |
| `Gtk.Box` | 1 | `statusbar` | — | id `box` |
| `Gtk.Label` | 5 | — | — | `command_bar_text`, `command_text`, `selection_count`, `mode`, `position` |

Status: **present** — lib/editor_statusbar.rb.

### `src/editor-info-bar.c`, `src/editor-info-bar.ui` → `lib/editor_info_bar.rb`

The error and recovery states shown above a document. Three stacked info bars.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root, `Gtk.BinLayout`) | 1 | — | — | — |
| `Gtk.Box` | 4 | — | — | id `box` plus one per info bar |
| `Gtk.InfoBar` | 3 | — | — | `access_infobar`, `discard_infobar`, `encoding_infobar` |
| `Gtk.Label` | 6 | — | — | `access_title` "Could Not Open File", `access_subtitle`, `title`, `subtitle`, "Invalid Characters Detected", encoding explanation |
| `Gtk.Button` | 5 | — | `on_try_again_cb`, `on_try_admin_cb`, `page.change-encoding` | "_Retry", "Open As _Administrator", `discard` "_Discard…", `save` "_Save…", `change_encoding` "Change _Encoding…" |
| `Gtk.SizeGroup` | 1 | — | — | equalises the button widths |

Dynamic states set from `editor-info-bar.c` (not visible in the `.ui`):
"File Has Changed on Disk" / "The file has been changed by another program."
with "_Discard Changes and Reload" and "Save _As…"; "Document Restored" /
"Unsaved document has been restored."; "Draft Changes Restored" / "Unsaved
changes to the document have been restored."

Status: **present** — lib/editor_info_bar.rb.

### `src/editor-search-bar.c`, `src/editor-search-bar.ui` → `lib/editor_search_bar.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | `searchbar` | — | — |
| `Adw.BreakpointBin` | 1 | — | — | collapses the replace row when narrow |
| `Gtk.Grid` | 1 | `toolbar` | — | id `grid` |
| `EditorSearchEntry` | 1 | — | — | id `search_entry`, composite |
| `Gtk.EventControllerKey` | 1 | — | `key-pressed` → `on_search_key_pressed_cb` | on the search entry |
| `Gtk.Entry` | 1 | — | — | `replace_entry`, placeholder "Replace" |
| `Gtk.Button` | 5 | `flat` ×3; `flat`+`small-button`+`circular` (close); plain ×2 | `search.move-previous`, `search.move-next`, `search.hide`, `search.replace-one`, `search.replace-all` | "Previous Match"/`go-up-symbolic`, "Next Match"/`go-down-symbolic`, close/`window-close-symbolic`, "_Replace", "Replace _All" |
| `Gtk.ToggleButton` | 1 | `flat` | — | `replace_mode_button`, "Search & Replace", `edit-find-replace-symbolic` |
| `Gtk.MenuButton` | 1 | `flat` | — | `options_button`, "Search Options", `emblem-system-symbolic` |
| `Gtk.Box` | 1 | — | — | links prev/next |

Menu model `options_menu`: Re_gular Expressions (`search-options.regex`),
_Case Sensitive (`search-options.case-sensitive`), Match Whole _Word Only
(`search-options.match-whole-word`).

Status: **present** — lib/editor_search_bar.rb.

### `src/editor-search-entry.c`, `src/editor-search-entry.ui` → `lib/editor_search_entry.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | — | — | — |
| `Gtk.Image` | 2 | — | — | `edit-find-symbolic`; `clear` = `edit-clear-symbolic`, "Clear Entry" |
| `Gtk.Text` | 1 | — | `notify`, `changed`, `activate` | id `text`, placeholder "Search" |
| `Gtk.Label` | 1 | — | — | id `info` — the "N of M" occurrence count |
| `Gtk.GestureClick` | 1 | — | `pressed` → `on_text_clear_button_pressed_cb` | on the clear image |

Status: **present** — lib/editor_search_entry.rb.

---

## 4. The open popover and sidebar

### `src/editor-open-popover.c`, `src/editor-open-popover.ui` → `lib/editor_open_popover.rb`

Recent-documents search, the `<ctrl>k` "find document by name" surface.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Popover` (template root) | 1 | `open-popover` | — | — |
| `Gtk.Box` | 3 | — | — | `box`, header row, `empty` state |
| `Gtk.SearchEntry` | 1 | — | `changed`, `activate`, `stop-search` | placeholder "Search documents" |
| `Gtk.Button` | 1 | — | `win.open` | "Open New Document", `document-open-symbolic` |
| `Gtk.Separator` | 1 | — | — | — |
| `Gtk.Stack` | 1 | — | — | id `stack` — `empty` / `recent` |
| `Gtk.Image` | 1 | `dim-label` | — | `document-open-recent-symbolic` |
| `Gtk.Label` | 1 | `dim-label` | — | "No Recent Documents" |
| `Gtk.ScrolledWindow` | 1 | — | — | id `recent` |
| `Gtk.ListView` | 1 | — | `activate` → `on_list_view_activate_cb` | id `list_view` |
| `Gtk.ShortcutController` | 1 | — | — | two `Gtk.Shortcut`s on the list view |
| `Gtk.NoSelection` | 1 | — | — | id `selection` (model, not a widget) |
| `Gtk.BuilderListItemFactory` | 1 | — | — | its `Gtk.ListItem` template instantiates `EditorSidebarRow` — a repeater, one per recent document |

Status: **present** — lib/editor_open_popover.rb.

### `src/editor-sidebar-row.c`, `src/editor-sidebar-row.ui` → `lib/editor_sidebar_row.rb`

One recent/open document row. A repeater instance from the popover's factory.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root, `Gtk.BinLayout`) | 1 | — | `query-tooltip` → `query_tooltip_cb` | — |
| `Gtk.Grid` | 1 | — | — | id `grid` |
| `Gtk.Stack` | 1 | — | — | id `stack` — blank vs modified dot |
| `Gtk.Label` | 2 | — | — | `empty`, `is_modified` ("•") |
| `Gtk.Inscription` | 3 | `caption`+`dim-label` on subtitle and age | — | `title`, `subtitle`, `age` |
| `Gtk.Button` | 1 | `circular`, `flat` | `clicked` → `on_remove_clicked_cb` | `remove`, "Remove", `window-close-symbolic` |
| `Gtk.Label` (standalone) | 1 | — | — | id `tooltip`, the tooltip body |

Status: **present** — lib/editor_sidebar_row.rb.

### `src/editor-sidebar-model.c`, `src/editor-sidebar-item.c` → `lib/editor_sidebar_model.rb`, `lib/editor_sidebar_item.rb`

The `GListModel` behind the popover list view and its item type (title,
subtitle, age, is-modified, draft flag, recent-manager entry). Not widgets;
needed for the row to have anything to show. Status: **present** — lib/editor_sidebar_model.rb, lib/editor_sidebar_item.rb.

---

## 5. Dialogs

### `src/editor-preferences-dialog.c`, `src/editor-preferences-dialog.ui` → `lib/editor_preferences_dialog.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.PreferencesDialog` (template root) | 1 | `org-gnome-TextEditor`, `preferences` | `win.show-preferences`, `<ctrl>comma` | — |
| `Adw.PreferencesPage` | 1 | — | — | — |
| `Adw.PreferencesGroup` | 8 | — | — | Appearance, (font), (display toggles), (spelling), Line Wrap, Indentation, Behavior, `clear_history_group` |
| `GtkSource.View` | 1 | `preview`, `card` | — | id `source_view`, the live scheme preview |
| `GtkSource.Buffer` | 1 | — | — | id `buffer` (model) |
| `Gtk.FlowBox` | 1 | — | `child-activated` → `style_scheme_activated_cb` | `scheme_group` — a repeater, one swatch per installed style scheme |
| `Adw.ExpanderRow` | 1 | — | — | "Custom _Font" |
| `Gtk.Switch` | 1 | — | — | `use_custom_font` |
| `EditorPreferencesFont` | 1 | — | — | `custom_font` |
| `EditorPreferencesSwitch` | 8 | — | — | Show Grid Pattern, Display _Line Numbers, _Highlight Current Line, Display _Overview Map, Check _Spelling, Show _Right Margin, _Wrap Lines Automatically (Alt+W), A_uto Indentation, _Discover Document Settings (+ subtitle) |
| `EditorPreferencesSpin` | 1 | — | — | `right_margin` "_Margin Position" |
| `Adw.ComboRow` | 1 | — | — | `character_row` "_Character" (tabs/spaces), fed by `EditorIndentModel` |
| `Adw.SpinRow` | 2 | — | `value-changed` → `on_indent_value_changed_cb` | `tab_width` "Spaces Per _Tab", `indent_width` "Spaces Per _Indent" |
| `Gtk.Adjustment` | 2 | — | — | models |
| `Adw.SwitchRow` | 1 | — | — | `restore_session` "_Restore Session" + subtitle |
| `Adw.ButtonRow` | 1 | `destructive-action` | `app.clear-history` | "_Clear History" |

Status: **present** — lib/editor_preferences_dialog.rb.

### `src/editor-preferences-row.c` → `lib/editor_preferences_row.rb`

An `Adw.ActionRow` base carrying the GSettings key/schema properties the four
concrete rows below share. Status: **present** — lib/editor_preferences_row.rb.

### `src/editor-preferences-switch.c` → `lib/editor_preferences_switch.rb`

`EditorPreferencesRow` + `Gtk.Switch` bound to a GSettings boolean. Status: **present** — lib/editor_preferences_switch.rb.

### `src/editor-preferences-spin.c` → `lib/editor_preferences_spin.rb`

`EditorPreferencesRow` + `Gtk.SpinButton` bound to a GSettings number. Status: **present** — lib/editor_preferences_spin.rb.

### `src/editor-preferences-radio.c` → `lib/editor_preferences_radio.rb`

`EditorPreferencesRow` + `Gtk.CheckButton` group bound to a GSettings enum.
Status: **present** — lib/editor_preferences_radio.rb.

### `src/editor-preferences-font.c` → `lib/editor_preferences_font.rb`

An `Adw.ActionRow` that opens a `Gtk.FontDialog`
(`gtk_font_dialog_choose_font`) and writes the chosen font to GSettings.
Status: **present** — lib/editor_preferences_font.rb.

### `src/editor-language-dialog.c`, `src/editor-language-dialog.ui` → `lib/editor_language_dialog.rb`

Document-type picker, reached from `page.change-language`.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` (template root) | 1 | `org-gnome-TextEditor`, `language-dialog` | — | title "Document Type" |
| `Adw.ToolbarView` | 1 | — | — | — |
| `Adw.HeaderBar` | 1 | — | — | — |
| `Gtk.SearchBar` | 1 | — | — | — |
| `Adw.Clamp` | 1 | — | — | — |
| `Gtk.SearchEntry` | 1 | — | — | placeholder "Search" |
| `Gtk.Stack` | 1 | — | — | `document-languages-page` / `no-search-results-page` |
| `Adw.PreferencesPage` | 1 | — | — | — |
| `Adw.PreferencesGroup` | 2 | — | — | `recent_group`, `group` |
| `Gtk.ListBox` | 2 | `content` | — | `recent_list_box`, `list_box` — repeaters over languages, rows are `EditorLanguageRow` |
| `Adw.StatusPage` | 1 | — | — | `edit-find-symbolic`, "No Results Found" — the empty state |

Status: **absent** — lib/editor_language_dialog.rb not written.

### `src/editor-language-row.c`, `src/editor-language-row.ui` → `lib/editor_language_row.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` (template root) | 1 | — | — | title is the language name |
| `Gtk.Image` | 1 | — | — | id `image`, `object-select-symbolic`, shown when selected |

Status: **absent** — lib/editor_language_row.rb not written.

### `src/editor-encoding-dialog.c`, `src/editor-encoding-dialog.ui` → `lib/editor_encoding_dialog.rb`

Character-encoding picker, reached from `page.change-encoding` and the
encoding info bar.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.Dialog` (template root) | 1 | — | — | title "Change Encoding" |
| `Adw.ToolbarView` | 1 | — | — | — |
| `Adw.HeaderBar` | 1 | — | — | — |
| `Gtk.SearchBar` | 1 | — | — | — |
| `Adw.Clamp` | 1 | — | — | — |
| `Gtk.SearchEntry` | 1 | — | — | `search_entry`, placeholder "Search encodings" |
| `Gtk.Stack` | 1 | — | — | `encodings` / `empty` |
| `Adw.PreferencesPage` | 1 | — | — | — |
| `Adw.PreferencesGroup` | 1 | — | — | id `group` |
| `Gtk.ListBox` | 1 | `content` | — | id `list_box` — repeater over `EditorEncodingModel`, rows are `EditorEncodingRow` |
| `Adw.StatusPage` | 1 | — | — | `edit-find-symbolic`, "No Results Found" |

Status: **present** — lib/editor_encoding_dialog.rb.

### `src/editor-encoding-row.c`, `src/editor-encoding-row.ui` → `lib/editor_encoding_row.rb`

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` (template root) | 1 | — | — | title/subtitle are the encoding's name and charset |
| `Gtk.Image` | 1 | — | — | id `image`, `object-select-symbolic` |

Status: **present** — lib/editor_encoding_row.rb.

### `src/editor-save-changes-dialog.c` → `lib/editor_save_changes_dialog.rb`

The quit/close confirmation.

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Adw.AlertDialog` | 1 | `destructive-action` on discard, `suggested-action` on save | `page.confirm-save` | "Save Changes?" / "Open documents contain unsaved changes…"; responses `cancel` "_Cancel", `discard` "_Discard"/"_Discard All" (plural), `save` "_Save"; `prefer-wide-layout` |
| `Adw.PreferencesGroup` | 1 | — | — | the dialog's `extra-child` |
| `Gtk.CheckButton` | n | — | `toggled` | **repeater** — one per unsaved page; label is the document title, "Untitled Document" or "%s (new)" for drafts |

Status: **present** — lib/editor_save_changes_dialog.rb.

### `src/editor-properties-panel.c`, `src/editor-properties-panel.ui`, `src/editor-properties.c` → `lib/editor_properties_panel.rb`, `lib/editor_properties.rb`

The `F9` side panel (sidebar when wide, bottom sheet when narrow).

| Widget | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Widget` (template root) | 1 | — | — | — |
| `Adw.PreferencesPage` | 1 | — | — | — |
| `Adw.PreferencesGroup` | 3 | — | — | file info, indentation, "Statistics" |
| `Adw.ActionRow` | 7 | `property`; `location`+`property` on Location | `open-folder`, `page.change-language` | File Name, Location ("Open in File Manager"), _Document Type ("Change Document Type"), Lines, Words, Characters No Spaces, All Characters |
| `Gtk.Image` | 2 | — | — | `open_image` `document-open-symbolic`, `go-next-symbolic` |
| `Adw.ComboRow` | 3 | — | — | `encoding_row` "_Encoding", "_Line Feed", "_Character" |
| `Adw.SwitchRow` | 1 | — | — | `auto_indent_row` "A_uto Indentation" |
| `Adw.SpinRow` | 2 | — | — | `tab_width` "Spaces Per _Tab", `spaces_per_indent_row` "Spaces Per _Indent" |
| `EditorProperties` | 1 | — | `notify::can-open` → `editor_properties_panel_notify_can_open_cb` | model object |
| `EditorEncodingModel`, `EditorNewlineModel`, `EditorIndentModel` | 3 | — | — | models feeding the combo rows |

Status: **present** — lib/editor_properties_panel.rb, lib/editor_properties.rb.

---

## 6. Models and non-widget support

These carry no widgets but every component above is empty without them. Each
is one upstream `.c`/`.h` pair to one `lib/*.rb`.

| Upstream | → `lib/` | What it is | Present |
|---|---|---|---|
| `src/editor-session.c` | `lib/editor_session.rb` | windows, pages, drafts, session save/restore, `session.new-draft` | yes |
| `src/editor-document.c` | `lib/editor_document.rb` | `GtkSource.Buffer` subclass: load, save, encoding, line endings, modified/busy state, draft handling | yes |
| `src/editor-document-statistics.c` | `lib/editor_document_statistics.rb` | lines/words/chars counts for the properties panel | yes |
| `src/editor-buffer-monitor.c` | `lib/editor_buffer_monitor.rb` | watches the file on disk, drives the "changed on disk" info bar | yes |
| `src/editor-properties.c` | `lib/editor_properties.rb` | the properties panel's model object | yes |
| `src/editor-encoding-model.c` | `lib/editor_encoding_model.rb` | `GListModel` of charsets | yes |
| `src/editor-newline-model.c` | `lib/editor_newline_model.rb` | `GListModel` of LF/CRLF/CR | yes |
| `src/editor-indent-model.c` | `lib/editor_indent_model.rb` | `GListModel` of tabs/spaces | yes |
| `src/editor-search-model.c` | `lib/editor_search_model.rb` | search occurrences, the "N of M" count | yes |
| `src/editor-page-settings.c`, `-provider.c` | `lib/editor_page_settings.rb`, `lib/editor_page_settings_provider.rb` | the per-document settings stack | no |
| `src/editor-page-gsettings.c` | `lib/editor_page_gsettings.rb` | GSettings as a settings provider | no |
| `src/defaults/editor-page-defaults.c` | `lib/editor_page_defaults.rb` | built-in per-language defaults provider | no |
| `src/editorconfig/editor-page-editorconfig.c`, `editorconfig-glib.c` | `lib/editor_page_editorconfig.rb` | `.editorconfig` settings provider | no |
| `src/modelines/editor-modeline-settings-provider.c`, `modeline-parser.c` | `lib/editor_modeline_settings_provider.rb` | vim/emacs modeline provider; `modelines/language-mappings` is data | no |
| `src/editor-page-vim.c` | `lib/editor_page_vim.rb` | vim keybinding mode (`keybindings` GSetting), drives the statusbar command text | no |
| `src/editor-print-operation.c` | `lib/editor_print_operation.rb` | `Gtk.PrintOperation` subclass behind `page.print`, uses `styles/printing.xml` | no |
| `src/editor-recoloring.c` | `lib/editor_recoloring.rb` | tints the window chrome from the style scheme (`recolor-window` GSetting) | no |
| `src/editor-joined-menu.c` | `lib/editor_joined_menu.rb` | concatenates `GMenuModel`s for the primary menu | yes |
| `src/editor-file-manager.c` | `lib/editor_file_manager.rb` | "Open in File Manager" / show-in-folder | yes |
| `src/editor-path.c` | `lib/editor_path.rb` | home-relative path shortening for titles and rows | yes |
| `src/editor-focus-chain.c` | `lib/editor_focus_chain.rb` | focus movement helper for `win.focus-neighbor` | no |
| `src/editor-source-iter.c` | `lib/editor_source_iter.rb` | word/paragraph iteration for the movement and deletion shortcuts | no |
| `src/editor-animation.c` | `lib/editor_animation.rb` | the smooth-scroll animation helper | yes |
| `src/editor-frame-source.c` | folded into `lib/editor_animation.rb` | frame-clock `GSource` used by the animation; the Ruby port ticks off the widget's frame clock inside `EditorAnimation`, so there is no separate file | yes |
| `src/editor-utils.c` | `lib/editor_utils.rb` | shared helpers (date formatting, "Untitled Document", etc.) | yes |
| `src/line-reader-private.h` | folded into `lib/editor_document.rb` | line splitting during load | yes |
| *(no single upstream file — GSettings is read inline throughout `src/`)* | `lib/editor_settings.rb` | port-only: one wrapper over the 26 schema keys, `Gio::Settings` when the compiled schema is installed and a JSON file otherwise (GLib aborts rather than raises on a missing schema) | yes |

Non-UI / build-only, no port target: `src/editor-types.h`,
`src/editor-types-private.h`, `src/build-ident.h.in`, `src/meson.build`,
`src/win32.rc.in`, `build-aux/`, `subprojects/`, `data/macos/`.

---

## 7. Resources

| Upstream | → port | What | Present |
|---|---|---|---|
| `src/style.css` | `data/style.css` loaded by a `Gtk::CssProvider` in `lib/gnome_text_editor/application.rb` | classes `window.org-gnome-TextEditor`, `dialog.preferences`, `.language-dialog`, `box.statusbar`, `row.location.property`, `page`, `popover`, plus `.theme-selector`, `.large-button`, `.editor`, `.property`, `.open-popover`, `.searchbar` | yes |
| `src/styles/{builder,builder-dark,peninsula,peninsula-dark,printing}.xml` | ship as data, register with `GtkSource::StyleSchemeManager` | 5 bundled style schemes | no |
| `data/org.gnome.TextEditor.gschema.xml` | `data/schemas/org.rubygtkproject.GnomeTextEditor.gschema.xml`, compiled and read through `lib/editor_settings.rb` | 26 keys: auto-save-delay, style-variant, indent-style, auto-indent, tab-width, indent-width, show-line-numbers, show-right-margin, right-margin-position, show-map, show-grid, highlight-current-line, wrap-text, use-system-font, custom-font, style-scheme, discover-settings, spellcheck, restore-session, recolor-window, keybindings, last-save-directory, draw-spaces (flags), enable-snippets, line-height, highlight-matching-brackets | yes (all 26 keys, renamed to the fork's app id) |
| `src/org.gnome.TextEditor.gresource.xml` | not needed — the Ruby port has no `.ui` files by design | the 17 templates it lists are the components above | n/a |
| `data/icons/hicolor/scalable/actions/*.svg` | ship as data, add to the icon theme search path | `document-admin-symbolic`, `document-modified-symbolic`, `external-link-symbolic`, `info-outline-symbolic` — referenced by the info bar and the properties button | no |
| `data/org.gnome.TextEditor.desktop.in.in`, `.metainfo.xml.in.in`, `.service.in` | `data/` equivalents | desktop entry, AppStream metadata, D-Bus activation | no |
| `po/` (59 locales, `POTFILES.in` lists 42 files) | `po/` + `lib/` gettext calls | translation catalogue; every `translatable="yes"` string above | no |
| `src/modelines/language-mappings` | ship as data | modeline-name → language-id table | no |

---

## Totals

- 17 `.ui` templates + 1 standalone `.ui` → 18 declarative component units.
- 29 port-target component files with widgets (sections 1–5): **26 present, 3 absent**
  (`editor_source_map.rb`, `editor_language_dialog.rb`, `editor_language_row.rb`).
- 27 model/support files (section 6): **16 present, 10 absent**, 1 folded in
  (`editor-frame-source.c` → `editor_animation.rb`), plus the port-only
  `editor_settings.rb`.
- 7 resource groups (section 7): **2 present** (`data/style.css`, the GSettings
  schema), 4 absent, 1 n/a.
- Actions to install: 7 app, 13 win, 20 page, 5 search, 3 search-options,
  1 settings, 1 session.
- 48 keyboard shortcuts in 10 sections.

The remaining gap is one theme: everything left depends on GtkSourceView
(syntax highlighting, the style schemes, the map, the per-language settings
stack) or on the translation catalogue.

## Suggested port order

Steps 1–10 are done except the three widget files named above; what is left is
step 11 plus the GtkSourceView swap that unblocks it.

1. `editor_document.rb` + `editor_utils.rb` + `editor_path.rb` — a buffer that loads and saves.
2. `editor_source_view.rb`, `editor_page.rb` — one document on screen.
3. `editor_window.rb` + `editor_window_actions.rb` + `editor_session.rb` — tabs, the empty state, new/open/save.
4. `editor_statusbar.rb`, `editor_position_label.rb`, `editor_source_map.rb`.
5. `editor_search_entry.rb`, `editor_search_bar.rb`, `editor_search_model.rb`.
6. `editor_open_popover.rb`, `editor_sidebar_row.rb`, `editor_sidebar_model.rb`, `editor_sidebar_item.rb`.
7. `editor_info_bar.rb`, `editor_save_changes_dialog.rb`, `editor_buffer_monitor.rb`.
8. The preferences family, then `editor_properties_panel.rb` + `editor_properties.rb` + `editor_document_statistics.rb`.
9. `editor_language_dialog.rb`/`_row`, `editor_encoding_dialog.rb`/`_row` and their models.
10. `shortcuts_dialog.rb`, `editor_theme_selector.rb`, `editor_fullscreen_box.rb`, `editor_recoloring.rb`, `editor_joined_menu.rb`.
11. The settings-provider stack, vim mode, print operation, `po/`.
