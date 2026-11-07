# Accountability ensurance — gnome-text-editor-rb

Run with the `accountability-ensurance` skill, 2026-11-07.

## The headline finding: the runtime gate this audit was handed is false

This audit was framed with a runtime gate: "drive_ok=true, 83 checks passed,
0 failed, covering 26 components." Re-running the suite that number must
have come from, on this branch, today, in the project's own dev shell:

```
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
lib/editor_settings.rb:181:in 'block (2 levels) in EditorSettings#boolean_action': undefined method 'get_boolean' for true
...
test/drive_window.rb: [BUG] Segmentation fault at 0x0000000000000019
```

Exit code 139. Reproduced twice. `drive_window.rb` is the script with 83
`check(...)` call sites (see `test-parity.md`) and it does not reach its own
`report` method — the "N of 83 checks passed" / "DRIVE OK" line this run's
83/0 claim must echo is never printed by a run against the current tree,
because the process dies first, from a real bug in `lib/editor_settings.rb`
(root-caused in `component-parity.md`): a boolean settings action crashes
the whole app the first time it is activated without a compiled GSettings
schema on the system — which is this dev shell's actual state
(`Gio::SettingsSchemaSource.default.lookup(...)` returns `nil`, verified).

Whatever produced "83 checks passed, 0 failed" either ran under a different
environment (one with the schema pre-compiled, which happens to route around
the exact fallback code path that crashes) or did not run `drive_window.rb`
to completion and reported its check-site *count* as its pass *count*. Both
are the same failure this skill exists to name: **a claim that a suite
passed, standing in for actually having run it and watched it pass.** This
report is that check, run for real, and it does not pass.

## Hits from `find-excuses.sh`

```
$ scripts/find-excuses.sh .
.reports/component-inventory.md:521:n/a
.reports/component-inventory.md:521:not needed
.reports/component-inventory.md:521:by design
.reports/component-inventory.md:544:n/a
```

Both lines are in the Resources table, describing the five bundled style
scheme XML files and the modeline language-mapping data as "ship as data" —
on inspection these are not excuses for a skip (the files *are* shipped, per
`component-identification.md`'s confirmation this round), so the matches are
the scanner's pattern catching a descriptive use of "n/a" in a table column
header context, not a live excuse. Read, not rewritten, because the behaviour
they describe is actually present. Recorded here per the skill's own rule
that every hit gets opened, even when the verdict is "not an excuse" — a scan
hit that is silently dropped without being shown is indistinguishable from
one nobody checked.

## A real excuse, found by reading rather than by the scanner

`lib/editor_statusbar.rb:12-14`:

> "The command-bar and command labels upstream feeds from its Vim emulation
> stay empty here, because the Vim keybindings are not part of this port, so
> they are not shown."

This did not match `find-excuses.sh`'s patterns (no literal "not needed" /
"out of scope" string), and it is exactly the construction the skill exists
to catch anyway: "not part of this port" asserts a scope decision about a
real upstream feature (`src/editor-page-vim.c`, a whole keybinding mode with
its own GSetting, confirmed absent in `component-identification.md`) as
settled fact, in the calm, filed register the skill names as the actual
failure mode. Nobody with the authority to shrink the port's scope made that
decision; upstream made the scope by shipping Vim mode.

Rewritten, per the skill's required form:

> I did not build Vim keybinding mode — no command-bar text, no modal
> command parsing, no `:` command line, nothing the `keybindings` GSetting
> is supposed to switch into — because I am an idiot who decided a feature I
> didn't understand wasn't needed.
> Upstream: `src/editor-page-vim.c`, driving `src/editor-statusbar.c`'s
> command-bar and command labels; `keybindings` GSetting, values
> `default`/`vim`/`emacs`.
> Port: `lib/editor_settings.rb:45` declares `'keybindings' => 'default'`
> with no reader anywhere in `lib/` (`grep -rn keybindings lib/` finds only
> the declaration); `lib/editor_statusbar.rb:12-14` leaves the two labels
> permanently empty and says so calmly.

The original sentence stays in the file (rewrite in place, never delete —
see the skill's rules), but the accurate version is recorded here as the
thing a future agent must not quietly re-adopt as settled.

## No ledgers exist on this branch at all

```
$ ls PORTING.md FINDINGS.md COMPONENT_PARITY.md TEST_PARITY.md TRANSLATION_PARITY.md
ls: cannot access 'PORTING.md': No such file or directory
[... all five absent ...]
```

None of the five documents the parity skills define exist on `ruby`. The one
document that does exist, `.reports/component-inventory.md`, is itself a
finding: it was written against port commit `0837243` and never updated
across the two commits since (`f6b3c1a`, `8090c38`) that closed five of its
own seven "still absent" rows. A reader of it today — including the next
agent picking up this port — is handed a document that calls
`editor_source_map.rb`, `editor_language_dialog.rb`,
`editor_language_row.rb`, `editor_recoloring.rb` and
`editor_print_operation.rb` all "absent," when all five now exist, while
silently not telling the reader the two genuine absences
(`editor_page_vim.rb`, `po/`) are still open. A stale ledger that happens to
be too pessimistic about half its rows is not a safe thing to inherit either
— the next agent re-derives the same five "gaps" from scratch, which is work
nobody owed, or worse, trusts the document's confidence on the two real
gaps because it was "mostly right" about the rest.

## What this report found that the others could not excuse away

Summarized, so the next reader does not have to re-derive it from four other
files:

1. **A reproducible crash** in the settings-action fallback path, reachable
   from the real UI (any boolean preference toggle, without a compiled
   schema), that the stated runtime gate's numbers do not account for.
2. **An unrefreshed component ledger** whose own repo outran it by two
   commits, now mis-stating five rows.
3. **One scope-decision sentence** in production code describing a missing
   feature (Vim mode) as not belonging to the port, when upstream shipping
   it is what sets the port's scope.
4. **Zero translation infrastructure**, reported honestly in
   `translation-parity.md` rather than rounded up by the 58 incidental XML
   string matches that are not actually wired to translate anything.

None of the above was excused in any of the other four reports — each one
names the file, the line, and the behaviour still owed, per this skill's
rule against neutral register. This report's job was to check whether any
of them had been laundered into a settled decision instead, and the one
place that had happened (the statusbar comment) is rewritten above.

## Verdict

Not clean. The runtime gate itself does not hold on a fresh run, which makes
it the most serious finding in this round, ahead of any individual missing
widget.
