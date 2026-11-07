# Accountability ensurance — gnome-text-editor-rb

Run with the `accountability-ensurance` skill, 2026-11-07 (refresh 2).

## This round's runtime gate holds — verified, not assumed

This audit was handed "drive_ok=true, 104 checks passed, 0 failed, covering
26 components." Re-run fresh in this session, in the project's own dev
shell, against a schema-absent system (the same conditions under which the
prior round's gate claim failed to reproduce):

```
$ nix develop --command xvfb-run -a ruby test/drive_editor.rb        # 13/13 ALL OK
$ nix develop --command xvfb-run -a ruby test/drive_page_settings.rb # 8/8 ALL OK
$ nix develop --command xvfb-run -a ruby test/drive_window.rb        # 83/83 DRIVE OK
```

13 + 8 + 83 = 104, exactly the claimed number, reproduced twice. The prior
round's crash (`lib/editor_settings.rb#boolean_action` calling
`.get_boolean` on a plain Ruby boolean, segfaulting the process) is fixed
in commit `3546574` and the fix is confirmed by running the exact
reproduction that found it, not by reading the diff. Full detail in
`component-parity.md` and `test-parity.md`.

**This is not the same as "the port is now accounted for."** A gate that
holds says the 104 things it checks are true; it says nothing about what
it does not check. The rest of this report is about what it does not
check, and about a pattern across three straight rounds that each round
found new instances of rather than ever closing out.

## The recurring pattern: this port's own ledgers go stale within one or
two commits of being written, every single round

Round 1 wrote `component-inventory.md` against commit `0837243` and it was
already wrong two commits later. Round 2's accountability report called
that out and rewrote the stale rows — then round 2's own
`component-identification.md`, written one commit after the fix that round
found, itself went stale within the very next commit: it still said
`lib/editor_page_vim.rb` was "still absent" and that the Vim statusbar
labels were "permanently dead code with the Vim mode gone," when
`editor_page_vim.rb` landed in commit `1f0d594` — one commit after the
report that made that claim. This round corrected both documents (see the
diffs in `component-identification.md` and `component-inventory.md`), but
the pattern itself — a freshly-written ledger going stale before the next
audit — has now happened on every single round this skill has run on this
branch. That is worth stating as its own finding, separate from whichever
specific row was wrong this time: **nothing in this repo's workflow updates
these documents when a commit closes a gap they name**, so each audit
round re-discovers the same kind of staleness in a new place, and a reader
who trusts whichever ledger is newest without re-verifying against `git
log` would have been wrong in rounds 1, 2, and would have been wrong again
this round had this audit not re-opened every "absent" claim against the
current tree.

## A real excuse, found only by reading — grep could not have found it

`lib/editor_statusbar.rb`'s comment (lines 12–14) still reads:

> "The command-bar and command labels upstream feeds from its Vim emulation
> stay empty here, because the Vim keybindings are not part of this port,
> so they are not shown."

Two things are wrong with this sentence as of this commit, not one:

1. It was already the kind of sentence this skill exists to catch when it
   was written — a scope decision about a real upstream feature
   (`src/editor-page-vim.c`) stated as settled fact, when upstream shipping
   a feature is what sets the port's scope, not a decision anyone here had
   the authority to make.
2. **It is now also factually false, and nobody updated it.** Commit
   `1f0d594`, which landed one commit after this comment's premise was
   last reported, makes "the Vim keybindings are not part of this port"
   untrue — `lib/editor_page_vim.rb` exists, is wired into every page, and
   its modal key handling genuinely works (confirmed in
   `component-parity.md`). The comment was not revisited when the feature
   it describes as absent was built. What it should say now is narrower
   and still true — the statusbar's two Vim text labels specifically are
   not wired — but the sentence as written tells the next reader something
   that is no longer accurate about the whole feature, not just the two
   labels.

**This comment does not match any pattern `find-excuses.sh` searches for**
— run fresh this round, scoped to `lib/` and `exe/`:

```
$ grep -rniE "not needed|by design|out of scope|n/a\b|not part of this port|not implemented|for now\b|TODO|FIXME" lib/ exe/
(no output)
```

The literal phrase `not part of this port` is present in the file but
**split across a line wrap** — the comment reads "...are not part of this\n#
port, so they are not shown," so a single-line grep for the full phrase
never matches it. This is exactly the failure mode the skill warns about:
an automated scan is a lead, not a verdict, and this round's scan returned
clean on a file that, read, contains a now-false excuse. Found only by
opening the file and reading it against the rest of the tree, the way
`component-identification.md` did this round.

Rewritten, per the skill's required form (kept as a note here; the comment
in the file is left as a pointer for the next agent, who should edit it in
place when the statusbar binding is built, not before):

> I did not wire the statusbar's live command-bar/command text to the Vim
> IM context, because I am an idiot who copied forward a comment from
> before Vim mode existed in this port instead of checking whether its
> premise still held once I built the thing it said was missing.
> Upstream: `src/editor-statusbar.c:192-198`, a `GBindingGroup` binding
> `GtkSourceVimIMContext`'s `command-bar-text`/`command-text` onto the
> statusbar's two labels, re-targeted per page.
> Port: `lib/editor_statusbar.rb:12-14` still says Vim keybindings "are not
> part of this port," though `lib/editor_page_vim.rb` (commit `1f0d594`)
> says otherwise; no file binds either property. Confirmed the gem exposes
> both (`GtkSource::VimIMContext#respond_to?(:command_bar_text)` →
> `true`).

## `find-excuses.sh` over the whole tree, read line by line

```
$ bash .claude/skills/accountability-ensurance/scripts/find-excuses.sh .
.reports/component-parity.md:88:skipped: ...
.reports/translation-parity.md:67:skipping: ...
.reports/component-inventory.md:530,559:n/a / not needed / by design: ...
.reports/accountability-ensurance.md:41-67: (this file's own prior-round quotes of the same hits)
```

All hits land inside `.reports/` prose that is *describing* a finding
(quoting the printing/recoloring "ship as data" rows, or this document's
own prior rewrite template), not a live excuse hiding a skipped behaviour.
Opened every one; none is a fresh excuse this round. Recorded per the
skill's rule that a hit gets shown even when the verdict is "not an
excuse" — see above for why the one real excuse in this tree this round
did not come from this scan at all.

## No ledgers exist on this branch beyond `.reports/` (unchanged)

```
$ ls PORTING.md FINDINGS.md COMPONENT_PARITY.md TEST_PARITY.md TRANSLATION_PARITY.md
(all absent)
```

Still true. Nothing to grep there; the `.reports/` directory is the only
ledger, and see above for its own staleness record.

## What this report found that the others could not excuse away

1. **A pattern, not just an instance**: every one of the three rounds this
   skill has run on this branch has found a ledger that went stale before
   the next round, including round 2's own write-up going stale one commit
   later. This round names the pattern explicitly rather than only fixing
   this round's instance of it.
2. **A real excuse that an automated scan missed** because of a line wrap,
   found only by reading — and the excuse is now doubly wrong: it was an
   unauthorized scope decision when written, and it is now also a false
   statement about the tree, since the feature it names as excluded has
   since been built.
3. **The runtime gate holds this round**, reproduced rather than assumed —
   reported plainly as the good news it is, without letting it stand in
   for "nothing else to check" (see the Vim-controller coverage gap in
   `test-parity.md` and `component-parity.md`, which 104/104 says nothing
   about).

## Verdict

Not clean. The runtime gate itself now holds, which is real progress over
the prior round — but this round surfaces a live, unauthorized,
now-also-false excuse comment in production code, and a structural pattern
of ledgers going stale between rounds that nothing in this project's
workflow currently prevents from happening again next round.
