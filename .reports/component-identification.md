# Component identification — gnome-text-editor-rb

Run with the `component-identification` skill, 2026-11-07 (refresh 2).

| | |
|---|---|
| Upstream | `origin/main` @ `51a092b` |
| Port | `ruby` @ `3546574` |

## What already exists and what this run corrects

The prior two runs of this document (against port commits `0837243` and then
`8090c38`) both went stale within a commit or two of being written — the
second refresh itself still says `lib/editor_page_vim.rb` is "still absent"
and lists the Vim statusbar labels as "permanently dead code with the Vim
mode gone." Neither claim survives `git diff --stat 8090c38..3546574 --
lib/`:

| File | Said as of `8090c38` | Now (`3546574`) |
|---|---|---|
| `lib/editor_page_vim.rb` | absent | **exists** (117 lines, commit `1f0d594`) |
| `lib/editor_settings.rb` boolean action | not flagged here (crash was `component-parity.md`'s finding) | fixed (commit `3546574`) |
| `po/` + gettext calls | absent | **still absent** |

So of the two genuine absences this document was carrying, one has closed.
This is the second time in a row this document has gone stale across the
very commits it was meant to track — see `accountability-ensurance.md` for
why that pattern, not just this one instance, is the finding worth keeping
open.

## Identification of the newly-landed unit

### `src/editor-page-vim.c` → `lib/editor_page_vim.rb`

| Type | × | Signals/behaviour | Notes |
|---|---:|---|---|
| `Gtk::EventControllerKey` | 1 | `propagation_phase = :capture`, carries the IM context | installed/removed on `changed::keybindings`, matches upstream's `self->vim` lifecycle |
| `GtkSource::VimIMContext` | 1 | `write`, `edit`, `execute-command` signals wired | matches upstream's `on_vim_write_cb`/`on_vim_edit_cb`/`on_vim_execute_command_cb` |
| ex-commands | 3 groups | `:q`/`:quit`/`^Wc`, `:q!`/`:quit!`, `:wq` | matches upstream's `QUIT`/`FORCE_QUIT`/`WRITE_QUIT` literal sets exactly |

Built, wired into `lib/editor_page.rb` (`@vim = EditorPageVim.new(self,
settings)`, `@vim.build` called from `EditorPage#build`), and the
`keybindings` GSetting now has a real reader (`@settings.keybindings ==
'vim'`), closing the "declared default with no consumer" gap the prior
refresh flagged.

## What this still finds absent or newly incomplete

- **`po/`** — no directory, confirmed by `git ls-tree` and the translation
  census (`translation-parity.md`): zero `_()`/`N_()`/`gettext` call sites
  anywhere in `lib/`. Unchanged from every prior run.

- **Vim statusbar text is still not wired, and the comment describing why is
  now actively false, not just an excuse.** `lib/editor_statusbar.rb:12-14`
  still reads: "The command-bar and command labels upstream feeds from its
  Vim emulation stay empty here, because the Vim keybindings are not part of
  this port, so they are not shown." Vim keybindings **are** now part of
  this port (`lib/editor_page_vim.rb`, wired into every page). The premise
  the comment gives for the two labels staying empty no longer holds, and
  nobody touched the comment or the labels when `editor_page_vim.rb` landed.
  Confirmed the gem exposes what upstream binds: `GtkSource::VimIMContext`
  responds to both `command_bar_text` and `command_text` (checked live via
  `nix develop --command xvfb-run -a ruby -e "require
  'gtksourceview5'; p GtkSource::VimIMContext.new.respond_to?(:command_bar_text)"`
  → `true`, same for `command_text`). Upstream binds these through a
  `GBindingGroup` (`src/editor-statusbar.c:192-198`) re-targeted per page;
  the port has no equivalent, so a user who switches into Vim mode and types
  `:` sees GtkSourceView's own modal key handling work but gets **no status
  bar feedback at all** — the one piece of UI upstream dedicates to telling
  the user they are mid-command is silently missing. This is a real,
  user-visible component gap, not a documentation nit, and no `test/drive_*`
  script would catch it because none of them ever sets `keybindings` to
  `vim` (see `test-parity.md`).

## Scope note

Unchanged from the prior refresh: this pass does not re-walk the whole app
widget-by-widget. `component-inventory.md` carries the full per-file tables;
this document's job is to track what has moved since the inventory was
written and flag what it has not caught up on. The one item this pass adds
beyond "is the file present" is the Vim statusbar binding gap above, found
by reading `lib/editor_statusbar.rb`'s own comment against the state of the
rest of the tree rather than trusting that the comment's premise still held.
