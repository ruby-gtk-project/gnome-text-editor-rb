# Test parity — gnome-text-editor-rb

Run with the `test-parity` skill, 2026-11-07 (refresh 2).

| | |
|---|---|
| Upstream | `main` @ `51a092b` |
| Port | `ruby` @ `3546574` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command | none configured — `rake spec` runs an empty `spec/` (unchanged, see below) |

## Upstream has no test suite (unchanged)

```
$ git ls-tree -r --name-only origin/main | grep -iE "test"
.gitlab-ci/test-msvc.bat
```

One file, a CI batch script, not a test. Test parity is 0/0 and is met
trivially — restated from the prior run because it is still true, not
because it is being used to paper over the rest of this report.

## The prior finding — the runtime gate's suite did not actually complete — is now fixed, and the fix is reproduced here, not assumed

The last run of this skill reported that `test/drive_window.rb` segfaulted
before printing its own tally, and that the "83 checks passed, 0 failed"
runtime-gate claim it was handed could not be reproduced. This round's
runtime gate is different — "104 checks passed, 0 failed, covering 26
components" — and this time it **does** reproduce, run fresh in this
session:

```
$ nix develop --command xvfb-run -a ruby test/drive_editor.rb
...
ALL OK                               (13 check.call sites, all passed)
$ nix develop --command xvfb-run -a ruby test/drive_page_settings.rb
...
ALL OK                               (8 check.call sites, all passed)
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
83 of 83 checks passed
DRIVE OK
```

13 + 8 + 83 = **104**, matching the runtime gate's number exactly, for the
first time across the three rounds this skill has now run. The crash
(`lib/editor_settings.rb#boolean_action` calling `.get_boolean` on a value
that was already a plain Ruby boolean) was fixed in commit `3546574`, and
re-running the exact command that crashed last time, in the same
schema-absent dev shell, now completes clean, twice. This round's gate
claim is verified, not just repeated.

## What the number does not cover: the newly-landed Vim keybinding controller has zero check coverage

`lib/editor_page_vim.rb` landed in commit `1f0d594`, between this report's
prior run and this one. Grepping the three driver scripts for anything
that exercises it:

```
$ grep -rn "vim" test/
test/drive_page_settings.rb:94:  check.call('vim modeline beats the .editorconfig') do
test/drive_page_settings.rb:95:    document.call(File.join(project, 'modeline.rb'), "# vim: set ts=5 sw=5 et tw=66:\nx = 1\n").then do |doc|
```

That one hit tests the **modeline parser** recognising a `# vim: ...`
comment and setting the `keybindings` GSetting to `vim` as a side effect —
it never drives a page with `keybindings` actually set to `vim` through the
real settings path, never fires a key through the installed
`Gtk::EventControllerKey`, never issues a `:wq`/`:q!` ex-command, and never
checks the statusbar's command text (which `component-parity.md` finds is
not wired at all). **Zero of the 104 passing checks exercise
`EditorPageVim`'s own behaviour.** Per this audit's framing: a component no
check exercises is unverified, not done, regardless of how clean the
surrounding suite's numbers are. This is the gap this round's gate number,
taken alone, hides — "104/104, DRIVE OK" is true and also says nothing
about whether Vim mode works.

## `spec/` is still an empty harness, not a suite (unchanged)

```
$ find spec test -type f
spec/README.md
spec/spec_helper.rb
test/drive_editor.rb
test/drive_page_settings.rb
test/drive_window.rb
test/gtk_driver.rb
```

Zero `*_spec.rb` files. `rake spec` would run zero examples. Restated from
the prior run because nothing changed it — the RSpec harness
(`.rspec`, `spec/spec_helper.rb`, the `kettle-test` wiring in the gemspec)
is configured and has never run a single example. An RSpec harness existing
is not RSpec tests existing.

## Breakdown

| Script | `check.call`/`check(` sites | Ran this session | Result |
|---|---:|---|---|
| `test/drive_editor.rb` | 13 | yes | ALL OK, 13/13 |
| `test/drive_page_settings.rb` | 8 | yes | ALL OK, 8/8 |
| `test/drive_window.rb` | 83 | yes | **83/83, DRIVE OK — completes clean this round** |

One new observation from this run's full stdout, not previously reported:
step `[31]` (`test/drive_window.rb`, the save-changes dialog) logs `shot
10-save-changes failed: RuntimeError: widget produced no render node (not
realised yet?)` — a screenshot capture failure inside the harness. It does
not fail the step's own `check(...)` call (the dialog's state assertions
pass regardless) and does not affect the 83/83 tally, but it means the
save-changes dialog's screenshot evidence is missing from
`tmp/shots/` while every other dialog's is present. Noted here rather than
silently dropped, per this skill's own standard — a passing check and a
missing piece of evidence for it are not the same thing.

## Rules check

- Every row above is backed by a command actually run this session, not
  carried over from the prior report or read off the diff.
- The runtime gate's "104 checks passed, 0 failed, covering 26 components"
  claim is verified by reproducing the exact total from the three scripts'
  own `check` call counts, not accepted because it sounds plausible.
- The new Vim-controller coverage gap is reported plainly as "zero checks,"
  not rounded up because the file exists and the surrounding suite is
  green — green elsewhere is not evidence for an untouched component.
