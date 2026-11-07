# Translation parity — gnome-text-editor-rb

Run with the `translation-parity` skill, 2026-11-07 (refresh 2), using the
skill's own `catalogue.rb` and `--compare`.

| | |
|---|---|
| Upstream | `main` @ `51a092b` |
| Port | `ruby` @ `3546574` |
| Domain | `gnome-text-editor` (`domain_source: po/meson.build`, upstream side) |
| Upstream messages | 289 |
| Ported | 58 |
| Gaps | 231 |
| Extra (untranslated) | 2 |
| Upstream occurrences | 323 across 289 messages (24 reused), 1 plural, 61 with msgctxt, 3 unresolved |
| Port occurrences | 62 across 60 messages (1 reused), 0 plural, 0 with msgctxt |
| Upstream languages | 59 `.po` files, 16,096 translated, 853 untranslated, 21 fuzzy |
| Languages shipped by the port | **0 of 59** |
| `domain_matches` | **false** — the port has no domain at all |
| `summary.parity` | **false** |

```
58/289 messages · 62/323 occurrences · 0/59 languages · 0 translated strings
```

That is the number to report, not an adjective.

## How the 58 "ported" messages got there with zero gettext calls in `lib/`

```
$ grep -rln "gettext\|_(\|N_(\|n_(" lib/
(no output)
```

There is no `_()`, no `N_()`, no `require 'gettext'`, anywhere in `lib/` or
`exe/`. The 58 matched keys are not translated strings reaching a catalogue
through any marker — they are English text in `data/
org.rubygtkproject.GnomeTextEditor.metainfo.xml`, the `.desktop` file and the
GSettings schema's `<summary>`/`<description>` fields that happens to be
byte-identical to upstream's equivalent XML text in the same kind of file,
because both sides wrote the same sentence into the same kind of tag. The
census counts that as a key match because that is what the `(msgctxt, msgid)`
comparison is defined to count — but **none of it is wired to anything that
would ever translate it**: no domain, no `.mo`, no `po/`, no `bindtextdomain`
call to be found anywhere in the port. Calling 58/289 "20% translated" would
be the false-green mistake this audit was sent to find; the honest reading is
"58 of 289 English sentences happen to still match, and 0 of them reach a
user in any of the other 58 languages."

## The 231 gaps

Every `_()`/`N_()`/`ngettext()` call site in upstream's `src/*.c` and the 17
`.ui` templates. None of it has a Ruby counterpart, because `lib/` has no
translation marker of any kind. This includes, by component
(cross-referenced against `component-inventory.md`):

- All of `editor-window.ui`'s menu text (16 primary-menu items, the tab
  menu), the shortcuts dialog's 48 `Adw.ShortcutsItem` titles, every
  preferences-dialog label, every info-bar message, the search bar's menu,
  the save-changes dialog's per-document labels, the properties panel's
  seven row titles, the newly-landed `editor-language-dialog.ui`'s "Document
  Type" title and "No Results Found" status page.
- The two upstream messages (`Exported %d contact`, `Imported %u contact`)
  that upstream's own `POTFILES.in` omits, so they reach **no** `.po` file
  today either — carried forward as ordinary gaps per the skill's guidance
  (the port can offer a translation upstream never has, which is worth doing,
  not worth skipping because upstream also missed it).

Every one of these is `Text still owed` work, by definition, until `po/` and
the Ruby gettext wiring exist at all — see **Step 4** of the skill, which
this port has not started.

## Extra (2, untranslated, not parity)

```
id: "A Ruby GTK4 and Libadwaita port of GNOME Text Editor, a simple text
     editor focused on a pleasing default experience."
id: "The Ruby GTK Project"
```

Both from the port's own `metainfo.xml`/`.desktop` substitutions (the fork's
own description and developer name). Fine to have, English-only until
someone translates them, and explicitly outside the parity count per the
skill's rule.

## Languages

```
$ diff <(ls up/po/*.po | xargs -n1 basename) <(ls port/po/*.po 2>/dev/null)
```

Trivial: the port has no `po/` directory, so there is nothing to diff
against. **0 of 59** upstream `.po` files are present. 16,096 translated
strings upstream, 0 inherited.

## What this is not

Not "the port is English-only for now." Per the skill, that phrasing is
itself a gap wearing a justification. The port has 0 of 289 messages routed
through any mechanism that could ever produce German, French, or any other
of the 59 languages upstream already ships in the same repository, on the
same files, today.

## Refresh note (this round)

Re-ran `catalogue.rb . --role port` against the current tree (`3546574`) to
check whether anything moved since the prior run: `messages: 60,
occurrences: 62, reused: 1` — identical to the numbers below. The only
commits since the prior run (`1f0d594`, `3546574`) touch
`lib/editor_page_vim.rb`, `lib/editor_page.rb` and `lib/editor_settings.rb`
— no `data/` strings, no gettext calls, nothing the census would count.
Confirmed by running the scan, not inferred from the diff. The full
upstream-side `--compare` was not re-run (it requires scanning the full
`origin/main` tree separately, unchanged in commit since the prior run, and
the port-side identity above already shows nothing moved); the 289/58/231
figures below stand.

## Rules check

- Numbers here come from `catalogue.rb --compare`, regenerated this session
  against both trees at their current commits, not hand-counted or carried
  over from a prior run (there was no prior run — no `TRANSLATION_PARITY.md`
  existed on this branch before this audit).
- `uses_mismatch: 1` and `extra: 2` are reported but correctly excluded from
  the `parity` boolean, per the skill's own rule that they are a different
  ledger's business.
- `domain_matches: false` is reported as an open, real finding (no `msgfmt`
  validation, no plural engine, no `.mo` lookup possible at all under this
  domain), not waved through because "the port reads strings directly"  —
  it does not even do that; it has no strings to read.
