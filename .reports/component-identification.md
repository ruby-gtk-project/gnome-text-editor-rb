# Component identification — gnome-text-editor-rb

Run with the `component-identification` skill, 2026-11-07.

| | |
|---|---|
| Upstream | `origin/main` @ `51a092b` |
| Port | `ruby` @ `8090c38` |

## What already exists and what this run adds

`.reports/component-inventory.md` is a prior run of this exact skill, written
against port commit `0837243`. It is a real, detailed inventory (widget
tables, CSS, signals, menu models, action lists) and it is the right shape —
but it is **three commits stale**. `git diff --stat 0837243..8090c38 --
lib/ exe/ data/` shows the two commits since it was written changed exactly
the files that document called absent:

| File | `component-inventory.md` said | Now |
|---|---|---|
| `lib/editor_source_map.rb` | absent | exists (72 lines) |
| `lib/editor_language_dialog.rb` | absent | exists (149 lines) |
| `lib/editor_language_row.rb` | absent | exists (45 lines) |
| `lib/editor_recoloring.rb` | absent | exists (301 lines) |
| `lib/editor_print_operation.rb` | absent | exists (151 lines) |
| `data/styles/{builder,builder-dark,peninsula,peninsula-dark,printing}.xml` | absent | exist, 5 files |
| `lib/editor_page_vim.rb` | absent | **still absent** |
| `po/` + gettext calls | absent | **still absent** |

So of the inventory's seven-item "still absent" list, five have since landed
and two have not. That inventory was never re-run or even hand-edited to
reflect its own repo's last two commits — a reader of it today is told five
things are missing that are not, and is not told that nothing updated the
two genuine survivors. See `accountability-ensurance.md` for why an
unrefreshed ledger is itself a finding, not a formatting nit.

## Identification of the newly-landed units (this run's actual new work)

### `src/editor-source-map.c`, `.ui` → `lib/editor_source_map.rb`

| Widget | × | CSS | Signals/actions | Notes |
|---|---:|---|---|---|
| `Gtk::Box` (wrapper) | 1 | — | — | memoized root, per house style |
| `GtkSource::Map` | 1 | — | `notify::font-scale` tracked on the parent view | binds `view=`, font via CSS, visible tied to `show-map` |

Matches upstream's one-widget template. No CSS class divergence found.

### `src/editor-language-dialog.c/.ui` → `lib/editor_language_dialog.rb`, and
`src/editor-language-row.c/.ui` → `lib/editor_language_row.rb`

Built as `Adwaita::Dialog` + `Gtk::SearchEntry` + two `Gtk::ListBox`es
(`recent_list_box`, `list_box`) feeding `EditorLanguageRow`, same shape as the
upstream table in `component-inventory.md` §5. Confirmed present at the
counts that document records as **absent** — this run supersedes that one
row-for-row for this file.

### `src/editor-recoloring.c` → `lib/editor_recoloring.rb`

No widget of its own (behaviour-only, as upstream is), tints window chrome
from the active `GtkSource::StyleScheme`, gated on the `recolor-window`
GSetting. 301 lines — the single largest file this round, and the one most in
need of the behavioural check in `component-parity.md` (does it actually fire
on scheme change, not just on startup).

### `src/editor-print-operation.c` → `lib/editor_print_operation.rb`

`Gtk::PrintOperation` subclass wired to `page.print`, using
`styles/printing.xml`. Present; not driven by any of the three `test/drive_*`
scripts (see `test-parity.md`) — so "present in `lib/`" is as far as this
component-identification pass can confirm it, and that is distinct from
"works."

## What this pass still finds absent

- **`lib/editor_page_vim.rb`** — no file, no reference to a Vim keybinding
  mode anywhere in `lib/`. The `keybindings` GSetting key exists in
  `lib/editor_settings.rb` (`'keybindings' => 'default'`) with no consumer:
  `grep -rn keybindings lib/` finds only the default's declaration, never a
  read of it. A GSetting with a declared default and no reader is a
  component identified as a stub, not a component.
- **`po/`** — no directory, confirmed by `git ls-tree` and by the translation
  census (`translation-parity.md`): zero `_()`/`N_()`/`gettext` call sites
  anywhere in `lib/`.
- **Vim statusbar text.** `lib/editor_statusbar.rb`'s own comment says
  upstream "feeds [the command-bar and command labels] from its Vim
  emulation" and the port leaves them "empty... because the Vim keybindings
  are not part of this port." Those two labels (`command_bar_text`,
  `command_text`) are built (the widgets exist, per
  `component-inventory.md` §3) but are permanently dead code with the Vim
  mode gone — a component that renders and never has content, which is a
  narrower kind of gap than a missing widget and easy to miss on a widget
  count alone.

## Scope note

This pass did not re-walk the whole app widget-by-widget — `component-
inventory.md` already did that at acceptable depth for 29 of the app's
component files, and re-deriving it from scratch would not find anything
`component-parity.md`'s per-axis check (below) does not already surface.
What this pass contributes is the staleness finding above, the identification
of the 5 newly-landed units, and the two genuine remaining absences
(`editor_page_vim.rb`, `po/`) that both documents must now carry forward
without being re-marked as closed.
