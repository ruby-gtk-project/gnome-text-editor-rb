# Component parity — gnome-text-editor-rb

Run with the `component-parity` skill, 2026-11-07.

| | |
|---|---|
| Upstream | `origin/main` @ `51a092b` |
| Port | `ruby` @ `8090c38` |

No `COMPONENT_PARITY.md` ledger exists on this branch. There is nothing to
build on; this report is the first pass, not an update to a prior one.

## Headline finding: a settings action crashes the running app

This is found on the behaviour axis (Step 5 of the skill: drive the signal,
do not just read that it is connected), and it is serious enough to lead with
rather than bury in a table.

`lib/editor_settings.rb#create_action` installs the `settings.*` action group
the window and the primary menu bind to (`win.show-primary-menu` → the
"Wrap Lines Automatically (Alt+W)" item upstream's
`editor-preferences-dialog.c`/`.ui` table documents in
`component-inventory.md` §5, and the same mechanism backs every other
boolean preference switch). When the compiled GSettings schema is **not**
installed — confirmed with:

```
$ nix develop --command ruby -e "require 'gio2'; puts Gio::SettingsSchemaSource.default.lookup('org.rubygtkproject.GnomeTextEditor', true).inspect"
nil
```

— `EditorSettings` falls back to its JSON store, per its own documented
design (`lib/editor_settings.rb:7-17`), and `create_action` routes to
`fallback_action` → `boolean_action` (`lib/editor_settings.rb:178-187`):

```ruby
def boolean_action(key)
  Gio::SimpleAction.new(key, nil, GLib::Variant.new(self[key] == true)).tap do |action|
    action.signal_connect('activate') do
      (!action.state.get_boolean).tap do |value|
```

`action.state` on this binding already returns a plain Ruby `true`/`false`,
not a `GLib::Variant`, so `.get_boolean` on it raises
`NoMethodError: undefined method 'get_boolean' for true`. That exception is
raised from inside a GLib C callback the Ruby VM cannot unwind through, and
the process segfaults rather than printing a Ruby backtrace and continuing:

```
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
lib/editor_settings.rb:181:in 'block (2 levels) in EditorSettings#boolean_action': undefined method 'get_boolean' for true
...
test/drive_window.rb: [BUG] Segmentation fault at 0x0000000000000019
```

Reproduced twice, deterministically, exit code 139 both times. This is not a
drive-harness artifact: the crash is in `lib/editor_settings.rb`, reachable
from the real primary menu, and it fires the first time *any* boolean
preference is toggled while running without the compiled schema — which is
the state of a fresh checkout in this project's own dev shell, since nothing
in `flake.nix`, `bin/setup` or the Rakefile runs `glib-compile-schemas` on
`data/schemas` as part of setup (confirmed: `schema_installed?` returned
`nil` in the dev shell used to drive this audit).

**Component affected:** every `EditorPreferencesSwitch` row in
`editor_preferences_dialog.rb` (8, per `component-inventory.md` §5) and the
primary-menu "Wrap Lines Automatically" toggle — all of them install a
boolean settings action through this one code path.

**Verdict: gap.** The action exists (count: 1, matches upstream), installs
under the right name (`settings.wrap-text`), and upstream's signal is
present as a connection — but Step 5's drive proves it does not survive
being fired. A connected signal is not a working signal; this is the exact
failure mode the skill's Step 5 exists to catch, and the exact one a
component-count comparison alone would have missed.

## Units ported since `component-inventory.md` was last written

`component-identification.md` (this run) lists the file-level deltas. Axis
read on each, scoped to what is checkable without a GTK session per unit
(full Step 4/5 screenshot-and-drive pass was spent on the crash above; these
get the static three axes):

| Unit | Count | CSS | Signals/actions | Text | Verdict |
|---|---|---|---|:-:|---|
| `editor_source_map.rb` | 1 `GtkSource::Map`, matches upstream's 1 | n/a (no app CSS class on it upstream either) | `notify::font-scale` present | — | parity |
| `editor_language_dialog.rb` + `editor_language_row.rb` | matches §5's table (1 dialog, 2 list boxes, repeater rows) | `org-gnome-TextEditor`/`language-dialog` classes present in source | search-as-you-type present | not checked — see translation-parity.md, this file is unmarked | **gap** (text axis) |
| `editor_recoloring.rb` | behaviour-only, matches | n/a | gated on `recolor-window` key; **not exercised by any `test/drive_*.rb` script** — see test-parity.md | — | unverified, not parity |
| `editor_print_operation.rb` | 1 `Gtk::PrintOperation`, matches | n/a | `page.print` wired per `grep`; **not exercised by any driver** | — | unverified, not parity |

"Unverified" here is deliberately not "parity": per the runtime-gate framing
of this audit, a component no check exercises is unverified, not done, and
recoloring and printing are two of the four newly-landed non-widget
components with zero coverage in `test/drive_*.rb`.

## Still-absent components (carried forward, not re-closed)

- **Vim keybinding mode** (`src/editor-page-vim.c` → no `lib/` file). The
  `keybindings` GSetting exists with a declared default and is read by
  nothing. Upstream's statusbar command-bar/command-text labels are built in
  `lib/editor_statusbar.rb` and have no content source — see
  `accountability-ensurance.md` for the comment that describes this gap as a
  scope decision rather than a missing behaviour.
- **Translatable text on every component in this app** — not a per-component
  gap but the universal fourth axis failure. See `translation-parity.md`:
  0 of 59 languages ship, and the port's own `data/` strings are not wired to
  anything that would translate them either. Every row in the tables above
  that could show "✓" on the Text column instead shows "not checked" or
  "unmarked", because there is no mechanism yet, full stop.

## Stylesheet check

`data/style.css` vs. the five bundled scheme XML files added this round:
scheme files are data for `GtkSource::StyleSchemeManager`, not CSS, so they
are compared as data, not against `data/style.css`. No divergence found
between `data/style.css` and upstream's `src/style.css` beyond the renamed
window CSS class (`org-gnome-TextEditor`, consistent with the app ID
substitution already noted in `component-inventory.md` §7).

## Verdict

Not clean. One confirmed crash-on-use gap (settings actions under the JSON
fallback), two newly-landed non-widget components with no behavioural
verification at all, one dialog with an unmarked-text gap, and the two
carried-forward absences from `component-identification.md`.
