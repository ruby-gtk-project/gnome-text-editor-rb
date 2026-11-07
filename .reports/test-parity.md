# Test parity — gnome-text-editor-rb

Run with the `test-parity` skill, 2026-11-07.

| | |
|---|---|
| Upstream | `main` @ `51a092b` |
| Port | `ruby` @ `8090c38` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command | none configured — `rake spec` runs an empty `spec/` (see below) |

## Upstream has no test suite

```
$ git ls-tree -r --name-only origin/main | grep -iE "test"
.gitlab-ci/test-msvc.bat
```

One file, a CI batch script, not a test. Census of the worktree with
`test-census.sh` returns 0 rows; no `tests/` or `test/` directory, no
`meson.build` test target, no `g_test_add_func`, no `unittest`/`pytest`.
Verified, not assumed.

**Test parity is 0/0 and is met trivially. The port therefore inherits no
safety net** — every check that exists in this repo was written for the
port and pins nothing upstream considered worth pinning. This is the
finding, not a formality, and it is the reason the runtime-gate claim this
audit was asked to treat skeptically ("drive_ok=true, 83 checks passed, 0
failed, covering 26 components") is worth taking apart below: there is no
inherited suite backing it, only three hand-written driver scripts.

## What actually runs when asked to

```
$ nix develop --command xvfb-run -a ruby test/drive_editor.rb
...
ALL OK
$ nix develop --command xvfb-run -a ruby test/drive_page_settings.rb
...
ALL OK
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
test/drive_window.rb: [BUG] Segmentation fault at 0x0000000000000019
```
exit code **139**, run twice, both times. `drive_window.rb` does not finish.
It does not print its own `GtkDriver::Session#report` tally
(`"N of M checks passed"` / `DRIVE OK`) at all — the process dies before
that line executes. Full detail and root cause (a `NoMethodError` in
`lib/editor_settings.rb`'s GSettings-fallback boolean action, hit by the
Alt+W wrap-text toggle step) is in `component-parity.md` and
`accountability-ensurance.md`; this ledger's job is just to say plainly that
**the claimed "83 checks passed, 0 failed" number cannot be reproduced by
running the suite that is supposed to produce it.**

Breaking down what each script actually proves when it runs:

| Script | `check(...)` call sites (grep) | Ran this session | Result |
|---|---:|---|---|
| `test/drive_editor.rb` | 12 (`check.call`) | yes | ALL OK, 12/12 |
| `test/drive_page_settings.rb` | 8 (`check.call`) | yes | ALL OK, 8/8 |
| `test/drive_window.rb` | 83 (`check(` via `GtkDriver`) | yes | **crashed before `report` ran — checks completed before the crash: ~9 of 83, by the step markers in stdout** |

12 + 8 + 83 = 103 declared check sites across the three scripts, not 83 — the
83 figure in the runtime gate matches `drive_window.rb` alone, which is the
one script that did not complete. Whatever produced "83 checks passed, 0
failed, drive_ok=true" either ran in an environment where the compiled
GSettings schema was present (masking the bug — see
`component-parity.md`) or did not actually observe this run's crash. Either
way, the number is not reproducible from a clean checkout of this branch
today, and this report says so rather than repeating it.

## Extra

- `test/drive_editor.rb` — 12 checks: window build, file open, title
  tracking, search, replace-all, save, properties panel, new draft, zoom,
  fullscreen, recents, session state.
- `test/drive_page_settings.rb` — 8 checks: language guessing, per-language
  defaults, `.editorconfig` precedence, vim/emacs/kate modelines, per-document
  override, word-boundary iteration.
- `test/drive_window.rb` — up to 83 checks across window lifecycle, tab
  management, shortcuts and settings actions; **currently cannot be run to
  completion** (see above).
- `spec/` — contains only `spec_helper.rb` and `spec/README.md` (harness
  documentation for `kettle-test`). Zero `*_spec.rb` files exist. `rake spec`
  would run zero examples. This is not a test suite with nothing to report;
  it is a test framework with nothing wired into it, and it is worth stating
  plainly rather than letting "an RSpec harness is configured" read as "there
  are RSpec tests."

None of the above is parity work — upstream pins nothing, so there is
nothing to be at parity with — and none of it is free of findings either.

## Rules check

- Every row above is backed by a command actually run this session, not by
  reading the driver scripts and assuming they pass.
- The 0/0 upstream result is stated plainly, with the "no inherited safety
  net" consequence spelled out, per the skill's explicit instruction not to
  let a 0/0 report read as a silent pass.
- The crash is reported as what it is — a check suite that does not
  currently complete — rather than rounded up to "DRIVE OK" because two of
  the three scripts did finish clean.
