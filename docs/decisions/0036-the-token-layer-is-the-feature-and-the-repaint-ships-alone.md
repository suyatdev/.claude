# 0036 — The token layer is the feature, the repaint ships as its own commit, and two of nocturne's three shadows are overridden

- **Status:** Accepted (2026-08-24)
- **Context:** `treko/Treko.dc.html` — the only source file this branch changes. Five new test
  modules ride with it (`treko/test_theme.py`, `test_sidebar.py`, `test_drawer.py`,
  `test_drawer_sections.py`, `test_guards.py`) plus the `treko/cdp_harness.py` headless-Chrome
  harness. Full design, scenarios, acceptance criteria and measurements:
  `docs/features/treko-theme-and-layout.md`. Inherits **ADR 0023** (the design-system export is
  owned externally) by leaving `treko/nocturne.css` byte-untouched and doing all theming in the
  page's own `<style>` block, and **ADR 0034** (the store lives outside every repo, resolved once at
  startup) — which is what makes the Artifacts section unbuildable rather than merely unbuilt.
- **Note:** ADR number **0036** was confirmed free before writing, and again before this record was
  committed: `git log --all --name-only --pretty=format: -- 'docs/decisions/0036*'` returns nothing
  across every ref in this checkout, and `git rev-parse origin/main` equals `git ls-remote origin
  refs/heads/main` (`07c4e6e`), so the remote-tracking side of that sweep is current rather than
  stale. The sweep is recorded as the command rather than as a ref tally on purpose — a count ages
  the moment anyone fetches, and it aged between this file being written and being committed.
  `0028` is still an unused gap and `0026` is still duplicated on disk
  (`…symbolic-ref…` and `…the-gate-does-no-json-parsing…`) — which is why "highest filename + 1" is
  not a uniqueness check.
- **Measured at:** branch `feat/treko-theme-and-layout`, HEAD `3c44ee2`. Every figure below was
  re-run or re-read at that commit. The card's own prose was used as a map, never as a source.

## Context

Treko's board is one HTML file. Until this change its colours were **typed into the markup** — three
copies of `#12131e` and twenty-four `rgba(255,255,255,·)` hairlines and hovers, spread across inline
`style` attributes and, in three places, string literals inside JavaScript. There was no theme
switch because there was nothing to switch: a light mode meant a find-and-replace over a 639-line
file, repeated every time anyone touched a hairline.

So the visible feature people asked for — a Configuration drawer with a light theme — is not the
work. **The token layer is the work**, and the drawer is the thing that makes it reachable. That
inversion is what this record exists to fix in the reader's head, because the diff does not show it:
the commit that matters renders no differently from its parent, by construction.

Measured against its base commit `a5a66a75204f334fff09462e931981431b39081a`, the branch changes
exactly one source file — `treko/Treko.dc.html`, 155 lines — and adds roughly 3,300 lines of tests
and harness that did not previously exist. That ratio is the point: before this branch **nothing
tested the page's appearance at all**. Of the 221 tests in the task-1 baseline, one file read
`Treko.dc.html`, and only to cut out a fenced JavaScript slice for a node loader.

## Decision

**Eight chrome tokens are declared in the page's own `:root`; the substitution that introduces them
ships as a provable no-op in its own commit; the repaint that follows ships in a second; the light
theme overrides two of nocturne's three shadows and deliberately not the third; and the drawer's
third section is dropped rather than deferred.**

| Layer | Before | After |
|---|---|---|
| Chrome colours | 27 literals inline in markup and JS | 8 tokens in the page's second `:root`, the rule opening `--rail:#12131e` |
| Light theme | none — no `data-theme`, no `prefers-color-scheme` anywhere under `treko/` | `body[data-theme="light"]`, **51** custom properties + `color-scheme:light` |
| Shadows in light mode | nocturne's dark hexes, unchanged | `--shadow-sm` and `--shadow-lg` overridden; `--shadow-md` deliberately not |
| Tokenize and repaint | — | two tasks, two commits (`76c3772`, then `4adfda4`) |
| Drawer sections | — | Appearance and Layout. **No Artifacts section** |
| `treko/nocturne.css` | — | **untouched** (ADR 0023) |

The eight tokens and their twenty-seven call sites, counted by expanding each `var()` literally at
the tokenize commit:

`--rail` 3, `--hair` 8, `--hair-2` 1, `--hair-3` 1, `--hover` 8, `--hover-soft` 4, `--hover-faint`
1, `--hover-ghost` 1 — **27**.

Three of those twenty-seven are **JavaScript string literals** inside computed-value objects, not
markup attributes. A tokenize pass that walks HTML attributes misses them silently, which is why the
proof below operates on the whole file's bytes rather than on a parsed DOM.

## The two-commit split, and the one literal that had to lie for a commit

The tokenize pass and the repaint touch the same lines and have **opposite** properties. Tokenizing
must move zero pixels — it is pure substitution, and a reviewer can check that mechanically. The
repaint moves pixels on purpose, and a reviewer can only check it by looking. Combined into one
commit, the reviewer gets neither: a typo in a hairline alpha and an intended re-tint both read as
"a colour changed."

So they are two commits, tokenize first. That ordering is the design, not a convenience.

**Re-verified independently at this HEAD, not copied from the card.** Expanding the eight `var()`
names in `git show 76c3772:treko/Treko.dc.html` — exact literal keys, longest name first, closing
paren included — and deleting the `:root` line the commit added yields a file **byte-identical** to
`git show a5a66a7:treko/Treko.dc.html`. Per-token replacement counts matched the eight figures above
and summed to exactly 27. The check was falsified before its pass was believed: mutating `--hair` to
`.07` breaks the identity, as it must. (`2b96d60`, the gate-opening docs commit the card's Proof A
names as its base, carries a page byte-identical to `a5a66a7`'s, so the two refs are interchangeable
here.)

**One literal had to be temporarily wrong for that property to hold.** The agent panel's top border
was `rgba(255,255,255,.1)`, while the prototype's equivalent token is `.12`. Declaring `--hair-3` at
`.12` during the tokenize pass would have moved a pixel and broken the no-op. It was declared at our
`.1` and moved to `.12` by the repaint commit — confirmed in `4adfda4`'s own diff, which changes
`--hair-3` from `.1` to `.12` and touches nothing outside the two `:root` rules and the light block
(9 insertions, 4 deletions, one file).

**Proof A is not pinned as a test, and that is a real gap.** The card's task 2 asked for it to be
asserted as an `ARCHIVED RECEIPT` comparing the two frozen SHAs. `grep -rn 'ARCHIVED RECEIPT'
treko/` returns nothing at this HEAD, and `test_guards.py`'s 16 test functions cover criteria 15, 16
and 17 only. The proof has been run — twice by the implementation, once more by this ADR — but it
lives in the record, not in the suite. Anyone rewriting history under those two commits loses the
evidence with no test going red.

**A squash-merge destroys this design.** Two commits are the whole rollback point and the whole
reviewability argument; squashing them yields exactly the one-commit diff the split exists to
prevent.

## The shadow divergence: two overridden, one deliberately not

`nocturne.css` declares 51 custom properties in its `:root`, three of which are shadows, and all
three are **hardcoded dark hexes**:

```css
--shadow-sm: 0 0 0 1px #3f424d;                                  /* nocturne.css:78 */
--shadow-md: 0 0 0 1px #595d6c, 0 6px 18px rgba(0,0,0,0.55);     /* :79 */
--shadow-lg: 0 0 0 1px #9397ab, 0 16px 40px rgba(0,0,0,0.65);    /* :80 */
```

They do not self-adapt the way nocturne's `color-mix(...)` rules do. Left alone under a light
ground, the page renders charcoal rings on white cards and a `rgba(0,0,0,0.65)` bloom under a white
drawer. **The prototype's light block does not override any of the three** — checked in the
prototype file itself, not taken from the card: it contains zero `--shadow-sm:` / `--shadow-md:` /
`--shadow-lg:` declarations, only `var(--shadow-…)` reads. Our light block overrides two of them,
and that divergence is deliberate.

Which two, and why exactly those two, is a reader count and nothing else — measured at this HEAD:

| token | `var(...)` reads in `Treko.dc.html` | overridden in the light block |
|---|---|---|
| `--shadow-sm` | 8 | yes |
| `--shadow-lg` | 1 (the drawer panel) | yes |
| `--shadow-md` | **0** | **no** |

`--shadow-md`'s only consumer anywhere is `.elev-md { box-shadow: var(--shadow-md); }`
(`nocturne.css:218`), and no `class="elev` appears in the page. A declared value nothing reads is
not a state — the same rule in `rules/core-conduct.md` that kept `--panel` out of this port
(0 occurrences in `nocturne.css`, and in `Treko.dc.html` only inside the comment that explains its
absence) and kept the three `--color-section*` fills unoverridden (3 declarations in `nocturne.css`,
0 readers in the page).

**One honest wrinkle in that reasoning.** `--shadow-lg` was overridden when the light block landed
(`af5321a`), and its single reader — the drawer panel — did not exist until the drawer shell landed
two commits later (`6ded764`). Traced across the branch, `var(--shadow-lg)` count goes
`0, 0, 0, 0, 1, 1` at `2b96d60 → 76c3772 → af5321a → 4adfda4 → 6ded764 → 3c44ee2`. So for two
commits it was a declared value with no reader — the exact thing the rule forbids — justified by a
reader the same card was about to add. It has one now. Recorded rather than smoothed over, because
the reader-count test is only worth anything if it is applied to its own exceptions.

The override values follow the rule `nocturne.css` states for itself directly above the declarations
("soft ink-tinted shadows on a light theme, a hairline edge + ambient darkness on a dark one"),
inverted for the light ground rather than invented.

## Coverage is asserted as a property, not maintained as a list

The light block declares **51 distinct custom properties** (verified by parsing the block, not by
counting the card's prose): 33 overriding `nocturne.css`, the 8 status hues, the 8 chrome tokens
above, and the 2 shadows. That total coincidentally equals `nocturne.css`'s own 51 — a different 51,
not a copy of it.

Nothing maintains a hand-written list of what to override, because the first light-mode bug will
always be a token nobody thought of. Instead: of the **41** distinct `var(--name)`-reachable names
in `Treko.dc.html` at this HEAD, **39 are declared in the light block and 2 are excepted by name** —
`--font-heading` and `--mono`, both non-colour. That set was 40 when the card last measured it at
`16faaa4`; the one added since is `--shadow-lg`, arriving with the drawer. Nothing was lost.

What survives as a raw literal is exactly what should: `#12131e` once (its own `:root`
declaration), and `rgba(255,255,255,` nine times — seven in `:root`, and **two inside a fenced
exempt region** marked `criterion-2-exempt:start` / `:end`. Those two are the drawer's preview
cards, each a miniature of the *other* theme; tokenizing them would make both previews identical and
the control would stop meaning anything.

That marker cost one bug worth keeping, because it generalises. The exempt comment originally
**quoted** the literals it was exempting — and the region begins after the comment ends, so the
comment sat outside its own exemption and was correctly flagged. The fix was to name the literals in
words, not to teach the scanner to skip comments: a scanner blind to comments cannot see a literal
hidden in a commented-out style rule.

## Why the Artifacts section is omitted, not deferred

The prototype's drawer has three sections. This card ships two, and the third is **dropped
outright** — a decision that needs a record precisely because "deferred" is the default reading of
any missing feature.

**In the prototype it is already a stub.** `saveArtPath` writes `taskTracker.artifactsPath` to
`localStorage`, sets a saved flag, and stops. Read directly rather than taken from the card: the
key's *only* readers are `artPath` and `artPathDraft` in the same component's state seed — the field
re-populating itself. No queue form, no analyzer, nothing outside the control consumes it. Meanwhile
the copy beside that field claims the directory is where snapshots are written and that the Ledger
queues runs into it; neither clause is true of any code in either tree.

**On our side it would be worse, not better.** Since ADR 0034 the store directory is resolved
**once, at startup**: `store_location.read_store_dir()` reads `TREKO_STORE_DIR` (the constant is
`store_location.py:24`) and the single call site is `server.py:729`. There is no runtime setter, and
`POST /command` accepts exactly three verbs — `server.py:75-76` builds `ALLOWED_IDS` from
`SEND_COMMANDS` (`clear`, `handoff`) and `LOCAL_COMMANDS` (`reanalyze`), and none of the three
carries a filesystem path. A path typed into the drawer would change a browser key while the server
kept writing exactly where it always did.

That is the failure `rules/core-conduct.md` names by name: a control that accepts input, says
"Saved", and configures nothing is a display that reads as a measurement while being a substitute.
**Show the real thing or show nothing.**

The omission is asserted, not merely intended: `test_drawer_sections.py`'s
`test_d9_no_artifacts_section_was_ported` fails if any of `artifactsPath`, `saveArtPath`,
`artPathDraft`, `artSaved` or `setArtPath` appears in the page. Its own docstring states what it
cannot prove — that nobody adds an unrelated third section.

**What would make it real.** A `/command` verb carrying a path, which means the server creating and
writing a directory at an address the browser supplied — a trust-boundary extension of the same
weight as the one ADR 0034 handled, earning its own design and its own judge round. Short of that,
the honest cheap version is display-only: render the resolved `store_dir` the server already knows,
with no input and no Save. Also out of scope here, because the page has no channel that carries it
today.

## Alternatives considered

| Option | Verdict | Why |
|---|---|---|
| **Tokenize and repaint as two commits (chosen)** | **Accepted** | Each commit has one checkable property. The first is mechanically provable; the second is a single `:root` block a human can read. |
| One combined commit | Rejected | A typo in a hairline alpha and an intended re-tint are indistinguishable in the same diff. The reviewer loses both checks at once. |
| Declare `--hair-3` at the prototype's `.12` during the tokenize pass | Rejected | It moves a pixel, which falsifies the no-op the commit exists to prove. Same literal, two commits, and each commit's property stays true. |
| Take only the neutral half of the prototype's palette | Rejected | A user decision, taken at brainstorming: the whole palette, including the cyan accent and the re-tinted `--ok` / `--info`. Not relitigated here. |
| Override all three nocturne shadows | Rejected | `--shadow-md` has zero readers in this page. Overriding it changes nothing anyone sees and adds a value the reader-count rule would then have to except. |
| Override none, matching the prototype | Rejected | `--shadow-sm` has 8 readers and `--shadow-lg` has one; both would render dark rings and a dark bloom on a white ground. The prototype's omission is a gap, not a position. |
| Port `--panel` and `--color-section*` for completeness | Rejected | Zero readers each. A declared value nothing reads is not a state. |
| Defer the Artifacts section to a later card | Rejected | "Deferred" implies the design exists and the work is queued. Neither is true: the server has no channel that could carry it, so what would ship is a control that configures nothing. |
| Ship Artifacts as display-only now | Rejected (out of scope) | It is the honest version and is recorded as the path forward, but the page has no channel carrying `store_dir` today, so it is new plumbing rather than a section. |
| Follow `prefers-color-scheme` | Rejected (separate ask) | Neither tree has a media query today, and an explicit persisted choice is the point of the two new `localStorage` keys. Following the OS is its own decision. |

## Consequences

- **The repaint reaches every user, including one who never opens the drawer.** Dark stays the
  *default mode*, not the default *colours*: an unset `taskTracker.theme` still renders
  `data-theme="dark"`, but "dark" itself now means the cyan accent, `#1c1e2b` surfaces and the
  re-tinted `--ok` / `--info`. A non-choosing user is guaranteed the mode they had, never the exact
  colours they had.
- **The no-op proof is history, not a guard.** Both of Proof A's SHAs are now fixed, so re-running it
  says nothing about the live page — and it is not in the suite at all (see above). Its value is as a
  record of what `76c3772` did, and that record depends on those two commits surviving to `main`
  unsquashed.
- **`--shadow-md` will bite whoever first writes `class="elev-md"`.** It is left dark-hardcoded on
  purpose. The reasoning is a reader count, so the moment the count stops being zero the decision
  needs re-taking — that is the intended trigger, not an oversight.
- **The page is at 740 lines** (`wc -l treko/Treko.dc.html`), against this card's 800-line ceiling,
  up from 639 at the base commit. The drawer's two sections and the sidebar handler consumed most of
  that headroom. Further UI work in this file moves logic out rather than adding lines.
- **Dark mode fails the same contrast check the light theme now passes.** Measured during
  implementation on the untouched page, so it predates this branch; the re-tint's lifted greys
  improved it as a side effect. It is recorded so a later reader does not mistake it for a regression
  this change caused, and it is explicitly **not** a claim that dark passes.
- **Not verified by this ADR:** the suite's pass counts. The card records 294 passed / 0 failed at
  `3c44ee2`, and `pytest` was **not** re-run while writing this record because a full run was already
  in flight in this worktree. Every colour, count, path and SHA above was re-derived directly from
  the tree or from `git show`; the test *results* are cited from the card and are the one class of
  claim here that this record did not independently re-measure.
- **Two card tasks remain open at this HEAD** and are named rather than assumed done: the real
  browser walkthrough, and the post-change node-ID set diff against the task-1 baseline of 221. A
  changed total is not a regression, but only a set diff can show nothing was lost.
