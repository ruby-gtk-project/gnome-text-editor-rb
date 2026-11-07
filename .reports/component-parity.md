# Component parity — gnome-text-editor-rb

Run with the `component-parity` skill, 2026-11-07 (refresh 2).

| | |
|---|---|
| Upstream | `origin/main` @ `51a092b` |
| Port | `ruby` @ `3546574` |

Builds on the prior pass (written against port commit `8090c38`, kept in
this file's git history). That pass's headline finding — a settings action
crashing the running app — and this pass's new finding — a real but
narrower Vim statusbar gap — are both reported below.

## The settings-action crash is fixed; reproduced the fix, not just read it

The prior pass found `lib/editor_settings.rb#boolean_action` calling
`.get_boolean` on `action.state`, which this binding already returns as a
plain Ruby `true`/`false`, raising `NoMethodError` inside a GLib callback
and segfaulting the process the first time any boolean preference fired
without a compiled GSettings schema. Commit `3546574` changes the line to
`!action.state` (no `.get_boolean`). Verified by running the drive suite
fresh, in the same dev shell, under the same schema-absent conditions as
the pass that found the crash:

```
$ nix develop --command ruby -e "require 'gio2'; puts Gio::SettingsSchemaSource.default.lookup('org.rubygtkproject.GnomeTextEditor', true).inspect"
nil
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
    ok   wrap-text flipped
...
83 of 83 checks passed
DRIVE OK
```

Run twice; both times clean, no crash, exit 0. This closes the prior pass's
headline finding. **Verdict: parity, confirmed by re-running the exact
reproduction, not by reading the diff and assuming it works.**

## New finding: the Vim keybinding mode is a real component, but one of its
two halves is missing

`src/editor-page-vim.c` installs two things when `keybindings` becomes
`"vim"`: the modal key controller (`GtkSourceVimIMContext` on a
`Gtk::EventControllerKey`), and — through `src/editor-statusbar.c`'s
`vim_bindings` `GBindingGroup` — the live `command-bar-text`/`command-text`
labels that show the `:` command line the user is typing.

`lib/editor_page_vim.rb` (commit `1f0d594`) ports the first half faithfully:
same controller, same IM context, same three signal names, same three
ex-command groups (`:q`/`:quit`/`^Wc`, `:q!`/`:quit!`, `:wq`) with matching
behaviour on each. Read line-for-line against upstream; no divergence found
in the command logic itself.

The second half was never built. `lib/editor_statusbar.rb` carries the
comment that predates this commit ("the Vim keybindings are not part of
this port") unedited, and nothing in `lib/editor_page_vim.rb`,
`lib/editor_page.rb` or `lib/editor_statusbar.rb` reads or binds
`command_bar_text`/`command_text`. Confirmed the gem exposes both
properties, so this is not a bindings limitation:

```
$ nix develop --command xvfb-run -a ruby -e "require 'gtksourceview5'; ctx = GtkSource::VimIMContext.new; p ctx.respond_to?(:command_bar_text); p ctx.respond_to?(:command_text)"
true
true
```

**Verdict: gap.** The widget exists (the two `Gtk::Label`s in
`EditorStatusbar`, per `component-inventory.md` §3), the data source exists
(the IM context's own properties), and nothing connects them. A user who
switches into Vim mode and starts typing `:wq` gets the correct underlying
behaviour but no on-screen indication they are in command mode at all —
exactly the kind of signal-axis miss the skill's Step 5 exists to catch,
and exactly the kind a widget-count comparison (which would read "present,
present" on both labels) would not.

No `test/drive_*.rb` script would have surfaced this either way, because
none of them ever sets `keybindings` to `vim` — see `test-parity.md`.

## Units carried forward from the prior pass, re-checked

| Unit | Prior verdict | This pass |
|---|---|---|
| `editor_source_map.rb` | parity | unchanged, re-confirmed present and wired |
| `editor_language_dialog.rb` / `editor_language_row.rb` | gap (text axis, unmarked for translation) | unchanged — still true, see `translation-parity.md`; no translation work landed between passes |
| `editor_recoloring.rb` | unverified (no driver exercised it) | now exercised indirectly — `test/drive_window.rb` runs clean end to end with the default style scheme active, but still no step changes `style-scheme` mid-run to prove recoloring re-fires on a scheme change. Still **unverified on its one distinguishing behaviour**, not parity |
| `editor_print_operation.rb` | unverified (no driver exercised it) | `test/drive_window.rb` step 36 now constructs `EditorPrintOperation` and asserts it does not raise. That is real, narrow coverage (construction only — `.run` is explicitly skipped because Xvfb cannot answer the print dialog). Upgraded from "unverified" to **partial**, not full parity |

## Still-absent components (carried forward, not re-closed)

- **Translatable text on every component in this app** — unchanged, the
  universal fourth-axis failure. See `translation-parity.md`: 0 of 59
  languages ship, 0 gettext call sites in `lib/`.
- **`po/`** — unchanged, confirmed absent again this pass.

## Verdict

Not clean. The crash from the prior pass is fixed and the fix is
reproduced, not assumed — but this pass found a new, real gap in the
component it landed alongside the fix (the Vim statusbar binding), and two
of the four previously-"unverified" components are still only partially
covered by anything that actually runs.
