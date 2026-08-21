---
phase: implementation
model_tier: low
branch: fix/tracker-frontmatter-comment
---

# Feature-state tracking with a browser UI

⚠️ **This card has passed the planning→implementation gate more than once; the convention for that is
recorded here rather than as a fourth `phase` state.** The three-state field cannot express "paused
for revision", so when a mid-implementation spec revision is needed the card returns to
`phase: planning` — the only phase permitting spec edits — keeping its real branch and its ticked
tasks instead of resetting `branch:` to `none`; reopening then takes the literal `gate confirmed`
again. Compliance round 2 cited that `planning`-with-a-branch shape as `gates/phase-branch-mismatch`,
and documenting the convention was the answer, not a fourth state. **Read `phase:` above for where
the card is now** — restating it here would only go stale at the next transition. Every other
`planning` card in this repo carries `branch: none`; re-derive with `head -5 docs/features/*.md`,
which prints each card's frontmatter under its own filename. Not a `-m1` grep over both keys: that
returns only `phase:` lines, because `phase:` sorts above `branch:` in every card.

**The spec half of this feature lives in `tracking-feature-state.spec.md`** — design, the injection
route, security, and every acceptance criterion. Re-derive the count rather than trusting a number
here — `awk '/^## Acceptance criteria/{f=1;next} f&&/^## /{exit} f&&/^[0-9]+\. /{n++} END{print n}'`
over the spec half, which reads **15** on 2026-08-11. An earlier revision pinned "fourteen" and was
still saying it nine lines above its own reference to criterion 15. The analyzer skips it **by filename** — the
card set is `docs/features/*.md` minus anything ending `.spec.md`
(`grep -n 'SPEC_SUFFIX' task-tracker/analyze.py`). Frontmatter has nothing to do with the selection,
in either direction: a `.spec.md` half is skipped even when it *does* carry a `phase:` key, and a
non-`.spec.md` file that carries none is still counted as a card. Read it when a task sends you
there; it is not session-start reading, which is the whole reason for the split.

**Every `§` reference resolves in the spec half except `§Verification`, which is this file's own
last section** — deliberately, because task 13 writes measurements into it during implementation,
when the phase gate forbids editing a spec. The two files are one document: the terse list below
carries the task numbers, §Tasks in the spec half carries each task's detail under the same
numbers, and `hooks/lib/feature_tasks.py` keeps the two sets equal.

This adds a skill that derives a feature/worktree survey for a given repo, writes it as a versioned
run into a data file, and drives an **already-built** browser UI that renders it — with a control
channel that lets the UI drive the Claude session that launched it. `server.py` is the whole of the
new trust boundary.

⚠️ **The one discipline that governs both files: no count, test total or phase tally is pinned
anywhere as a contract; every code citation carries the command that re-finds it; and the
measurements that genuinely must be recorded — test counts, tool versions — are stamped with their
date and their reproducing command instead of being stated bare.** That third clause is what lets
`## Verification` below report "53 passed on 2026-08-09" without contradicting the first. **Before
trusting any derivation, ask what it cannot see** — a wrongly-scoped one returns cleanly and looks
exactly like a correct result.

That rule's full statement — the defect history, and the three scope failures that cost this feature
the most rounds — is the spec half's preamble, **authoritative if the two ever read differently**.
Not restated here: an earlier revision did, and the copy had already drifted.

## Tasks

**Each task's detail is in §Tasks of `tracking-feature-state.spec.md`** — this list is the terse
half of the pair, and the sync check (`hooks/lib/feature_tasks.py`) matches on the task *number*
only, so everything after the em dash is free to differ between the halves. Do not add detail here;
it belongs in the spec half, and it is what keeps this file readable at session start.

- [x] 1 — Spike the injection route. **Fully done, do not re-run**; all four probes ran 2026-08-09.
- [x] 2 — Vendor the UI: copy the Nocturne export to `task-tracker/`, preserving `_ds/`.
- [x] 3 — `task-tracker/analyze.py`: features + branches only, importing `hooks/lib/feature_tasks.py`.
- [x] 4 — `task-tracker/test_analyze.py`: criteria 1 and 2 against a fixture repo. Round-11 reopen closed: `repo.card(phase=None)` omits the key, and the converse selector direction is asserted by branch, falsified both ways.
- [x] 5 — Waves, constraints and graph derivation, including the `## Depends on` reader.
- [x] 6 — `task-tracker/store.py` + `task-tracker/test_store.py`. Criteria 3-5.
- [x] 7 — `PORTS.md` entry for the control server, before any bind. Port is **8422**.
- [x] 8 — `task-tracker/server.py` to the wire contract in §Design 3. **Task 14 runs immediately after this one.** Every route, refusal and startup abort smoke-verified against a cmux shim; task 9 is what pins them as tests. ⚠️ **The owed edit landed** (2026-08-11, its own commit ahead of task 9): `confirm_surface()` returns `timeout` separately from `unrunnable`, and `CONFIRM_REFUSAL_REASONS` maps the two states to `confirm_timeout`/`confirm_failed` — `grep -n CONFIRM_REFUSAL_REASONS task-tracker/server.py`. §Tasks 8 in the spec half was corrected at `d142643`, in the `review` phase that forbade it earlier; nothing is outstanding on either half.
- [x] 9 — `task-tracker/test_server.py`: criteria 6, 7, 9, 10, 11, **12 and 14**. Not criterion 13. Four files, split at the repo's 800-line ceiling: `test_server.py` (wire contract), `test_server_lifetime.py` (**owns criterion 14** and every startup abort), plus `conftest.py`/`server_harness.py`. Each control was mutation-tested rather than assumed — six deliberate server defects reverted one at a time, every one caught; re-run by mutating a control and requiring its test to fail. ⚠️ **§Tasks 9's `reason` derivation undercounts, and its stated figures are stale** — `_run_send` passes `CONFIRM_REFUSAL_REASONS[state]`, a *computed* reason that no literal-matching `grep` sees. That is the "third emitting shape" the spec predicted but could not name. Re-derive as the spec's block **plus** `set(server.CONFIRM_REFUSAL_REASONS.values())`, which is what `reasons_emitted_in_source()` in `test_server.py` does; the spec half's own count was corrected at `d142643`, in the `review` phase.
- [x] 10 — Wire the UI's command buttons to `POST /command`; copyable text where no terminal exists. **Owns criterion 15** — the page's own failure behaviour, which no server test can reach. Handler `0fd5bcd`, buttons `8fe330a`, tests `75b3108` (written and run red first — twelve failures on the absent marker pair). Criterion 15 is 15 tests in `test_ui_commands.py`, falsified by seven handler mutations of which seven were caught. ⚠️ **The handler could not go in a new `.js` file**: the servable set is a closed sixteen-row list pinned in *both* `server.py` and §Design 3, so a new row is a spec edit and reopens criterion 13; an inline `<script>` dies on the CSP's missing `'unsafe-inline'`. It lives fenced inside the `text/x-dc` block and the test slices it out to load in `node`. **Both render modes were confirmed by an actual headless render, not by inspection** — served, the header shows three command buttons, zero copy chips and the token once; over `file://`, zero buttons and three copy chips (`/clear`, `/handoff`, `python3 task-tracker/analyze.py .`). No unresolved `{{ }}` binding in either.
- [x] 11 — `skills/tracking-feature-state/SKILL.md`. Owns two security controls at launch. Both are written with their failure mode beside them: detaching leaves the parent-death check inert, redirecting `stderr` discards the audit log, and neither shows up in a code read. **The documented launch line was run, not reasoned about** (2026-08-12): `python3 task-tracker/server.py --repo "$PWD"` under the harness's background mode bound this session's real surface, served `/` at `200`, and wrote its startup and audit lines to captured `stderr`; `ps -o ppid=` walked the chain to `server → zsh → claude`, which is what keeps `getppid()` able to change. **Not verified, and not verifiable here:** trigger-routing accuracy — the skill is not discoverable from this worktree, and `skills/_standards/authoring-skills-and-agents.md` records that no eval harness exists in this repo.
- [x] 12 — Add the skill to the Skills Catalog in `CLAUDE.md`. One row, placed after `managing-session-memory` because both answer "where does this work stand"; the catalog is grouped by activity, not alphabetised. `CLAUDE.md` is the only catalog — every other file mentioning a skill name references it in prose (`grep -rln 'verifying-subagent-commits' --include='*.md' .`), so there is no second list to drift.
- [x] 13 — Run every suite, record before/after counts in `## Verification` below. All three ran 2026-08-12, **zero failures before or after**; the before-counts came from a throwaway detached checkout of `main` at `1b983d9`, since a run in this tree is an *after* count by definition. `node --version` = v26.5.0, and the `task-tracker/` run reports **no skips at all** — so criterion 5 got its JS-engine oracle and criterion 15 is verified, not degraded. ⚠️ **The guard re-derivation overcounted by one, and is now fixed in place**: `grep -c skipif` totals 15, but `test_server.py:556` guards on `os.geteuid() == 0`, not `node` — the node-guarded figure is 14, via `grep -h 'skipif(NODE is None' task-tracker/*.py | wc -l`. This lived in the `.md` half, **not** the spec half, so it was never a spec edit; an earlier revision of this note said otherwise and was wrong.
- [x] 14 — Vendor all six remote assets — nine local files. **Runs right after task 8**; owns criterion 13. Closed on the re-score in `§Verification` — both runs match the revised expectation exactly, on the enumerations already recorded; no new browser run was made.
- [x] 15 — Fix `_parse_frontmatter`'s blindness to a YAML trailing comment, which makes this
      repo's own closed-card convention unreadable to this feature's own analyzer.
      `analyze.py:196` splits each frontmatter line on the first `:` and keeps the remainder
      verbatim, so `branch: none  # merged via PR #39 (cbb9f60); fix/falsifier-base-pin deleted`
      is read as a branch *named* that entire string; the `none` test at `analyze.py:269` then
      misses, and the card raises a false "Where is this branch?" question. Plain `branch: none`
      is unaffected — which is why only *closed* cards misreport. Measured against the live repo
      2026-08-19: **3 of 19** `questions[]` are this defect (`falsifier-base-pin`,
      `memsearch-freshness`, `shell-segments-redirects`), and closing this card at task 16 would
      have made it 4. **Red first** — a case in `task-tracker/test_analyze.py` built from one of
      those three real spellings, run and seen to fail before the fix exists. Strip only a comment
      introduced by whitespace-then-`#`, never a bare `#`, so a branch name legitimately carrying
      one survives.
      **Done.** One regex applied in `_parse_frontmatter` to every frontmatter value, not just
      `branch:` — `FRONTMATTER_COMMENT = re.compile(r"\s+#.*$")`; `analyze.py:269`'s `none` test
      was left alone, and proved not to need changing. Red first (`581d38c`): the
      `falsifier-base-pin` spelling verbatim, run and seen to fail on the live "Where is …?"
      string. Its boundary guard (`feat/issue#42` survives whole) passes today, so it was proved
      falsifiable separately — a temporary strip-on-any-`#` truncated it to `feat/issue`. Suite
      **159 → 161, zero failures on either side**, both runs in this worktree (an archive of
      `8f15c6e` under `/tmp` reports two extra server failures; it is not a git repo, and
      re-analyze needs one — an environment artifact, not a baseline).
      ⚠️ **The analyzer's question count went 19 → 20, not 19 → 16.** All three false questions
      are gone and all three cards now report no branch (`—`), but reading those cards correctly
      exposed four questions the bogus branch had been masking, and none is a regression:
      one is **true** — `feature/memsearch-freshness` is not deleted as its card's comment
      claims, it is the branch checked out at `~/.claude` itself — and three are a **second,
      separate defect**: `_ask_about_readiness` gates only on `not card.branch` and never on
      completeness, so it now asks whether a 14/14 card is "ready to start". It was never wrong
      before only because the repo's three plain-`branch: none` cards are all 0/N; this fix
      produced the first complete-and-branchless cards. **Not fixed here** — a distinct defect
      with its own design question, and out of this task's scope. It bears on task 16: closing
      this card to the merged convention makes `tracking-feature-state` the fourth such card.
- [ ] 16 — Close the card. Frontmatter to this repo's merged convention — `branch: none  # merged
      via PR #51 (06e7c9d) …; feat/tracking-feature-state deleted 2026-08-19` — naming this
      reopen's PR beside it. Observability judge at `implementation` stage pinning the final HEAD,
      then the PR.

## Verification

**Task 1 — injection route. Closed 2026-08-09; nothing is outstanding.** Route is
`cmux send --surface`. All four probes ran live against `cmux 0.64.20 (100) [14e3400b9]`; each
reproducing command is in §"Injection route" beside the finding it produced.

| Probe | Result | Bearing on the design |
|---|---|---|
| `send` into a live Claude TUI (terminal surface), no newline | Delivered to the composer, exit 0, not submitted | The control channel works. This was the premise five rounds of spec work sat on top of |
| `send` at an unresolvable ref (`surface:9999`) | `not_found`, **exit 1**, delivered nowhere | `send` does **not** inherit `rename-tab`'s silent fall-through — the card's central fear does not apply to this verb |
| `send` at an `agent-session` surface | `invalid_params: Surface is not a terminal`, exit 1 | Clean refusal; the channel exists only for a Claude TUI in a `[terminal]` surface |
| `send` at a ref that resolved to the **wrong live Claude session** | Delivered, exit 0, `OK` on stdout | The actual hazard. A successful send reports delivery, never destination — so the send-time check must confirm *identity*, not existence |

The fourth row was not a designed probe; it happened, to a parallel session, because the operator's
own surface was inferred from `cmux tree`'s `[focused]`/`[selected]` markers while `cmux identify`
returned `surface_ref: null`. Nothing was submitted (no newline) and the composer was restored. It is
recorded here rather than tidied away because it is the only direct evidence this repo has of the
failure the whole §Security section exists to prevent, and it says something no reasoning had: the
mis-delivery is indistinguishable from success at the call site.

**Tasks 2–6 suites.** The canonical invocation, repeated here rather than referenced because task 13
runs from this file and the pin lives in the other half (`§Toolchain` in `tracking-feature-state.spec.md`,
which is authoritative if the two ever disagree):

```
uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q
```

It reported **53 passed** on 2026-08-09; that number is a measurement with a date, not a contract —
re-run it rather than trusting it. There is no system `pytest` here, so `uv run` is the only
invocation that works.

⚠️ **Three of those tests are conditionally skipped on a host without `node`.**
`task-tracker/test_store.py` guards three tests with `@pytest.mark.skipif(NODE is None, ...)`
(`grep -n skipif task-tracker/test_store.py`), one of them criterion 5's JS-loadability check. This
is why `node` is pinned in §Toolchain.

Precisely what is lost, since overstating it is its own defect: each node-guarded test has an
**unguarded Python sibling** asserting byte-identity and a real envelope parse
(`grep -n 'def test_' task-tracker/test_store.py`), so on a node-less host criterion 5 is *partially*
verified, not unverified. What goes missing is the independent JavaScript-engine oracle — exactly the
U+2028/U+2029 class of bug that `store.dumps`'s own docstring names as the reason it escapes them.
Task 13 must record `node --version` beside the counts, and report a skip of these three as
**"criterion 5 verified without a JS-engine oracle"** rather than either a clean pass or a failure.

⚠️ **Criterion 15's tests are node-guarded too, and they degrade worse.** Task 10 adds
`task-tracker/test_ui_commands.py` under the same guard — re-derive the count with
`grep -h 'skipif(NODE is None' task-tracker/*.py | wc -l` rather than assuming it is still three.
**Filter on `NODE`, not on `skipif`:** a bare `grep -c skipif` returns **15** and overcounts, because
`test_server.py:556` guards on `os.geteuid() == 0` — root, not `node`. The node-guarded figure is
**14** (3 in `test_store.py`, 11 in `test_ui_commands.py`), and it counts decorators, not tests.
Criterion 5 keeps an
unguarded Python sibling, so a node-less host still verifies it partially; criterion 15 has none,
because the behaviour is browser JS end to end. On such a host task 13 reports criterion 15
**not verified** — not passed, and not skipped-therefore-fine.

⚠️ **Task 13 must record before-counts per suite, captured before touching anything**, so a
pre-existing failure is not read as a regression introduced by this feature.

`task-tracker/` carries **no pytest configuration of any kind** — the repo's only `pyproject.toml`
governs `memsearch/` alone (`find . -name pyproject.toml`), so no `addopts` and no mark deselection
applies. An earlier revision warned otherwise, having read a different package's config as this one's.

**Criterion 13 — the two browser runs. Ran 2026-08-11; scored one row a failure against the table as
it then stood, and passes on the re-score below.** Chrome `151.0.0.0` (`navigator.userAgent`, macOS),
extension `read_network_requests`. Server started from the worktree with the scratchpad `cmux` shim
(`CMUX_BIN`/`CMUX_SURFACE_ID`/`FAKE_SURFACE`), which is why every `surface=` below is the fake UUID.
View driven: the default **Overview** — 45 regular and 1 fill phosphor glyph
(`document.querySelectorAll('[class*="ph-"]…').length`), with `document.fonts` reporting `Phosphor`
and `Phosphor-Fill` both `loaded`, the two-face condition the criterion demands.

| Path | (a) store moved aside | (b) store restored | Criterion |
|---|---|---|---|
| `/` | 200 | 200 | matches |
| `/vendor-resources.js` | 200 | 200 | matches |
| `/support.js` | 200 | 200 | matches |
| `/_ds/nocturne-73641b21…/styles.css` | 200 | 200 | matches |
| `/_ds/nocturne-73641b21…/_ds_bundle.js` | 200 | 200 | matches |
| `/tracker-data.js` | 404 | 200 | matches |
| `/tracker-data-fallback.js` | 200 | 200 | matches |
| `/tracker-data.sample.js` | 200 | **absent** | matches |
| `/favicon.ico` | 404 (first load only — see below) | absent | see below |
| `/vendor/react.production.min.js` | 200 | 200 | matches |
| `/vendor/react-dom.production.min.js` | 200 | 200 | matches |
| **`/vendor/babel.min.js`** | **never requested** | **never requested** | **failed the original table (expected 200); matches the revised one, which drops the row — see RESOLUTION** |
| `/vendor/phosphor/regular/style.css` | 200 | 200 | matches |
| `/vendor/phosphor/regular/Phosphor.woff2` | 200 | 200 | matches |
| `/vendor/phosphor/fill/style.css` | 200 | 200 | matches |
| `/vendor/phosphor/fill/Phosphor-Fill.woff2` | 200 | 200 | matches |
| `/vendor/inter/inter.css` | 200 | 200 | matches |
| `/vendor/inter/inter-latin.woff2` | 200 | 200 | matches |

`window.TRACKER_DATA_SOURCE === 'sample'` held in run (a). It is `undefined` in run (b) — the shim
returns before setting it — and the footer timestamps differ between the runs (`02:41` sample vs
`06:21` generated), which is the evidence the two runs rendered different data. No request went to any
host other than `127.0.0.1`, and **no `/vendor/babel.min.js.map` was requested**, so the source-map
hazard did not materialise.

**Why the babel row was scored a failure, and why it is not a vendoring defect.** The file is
vendored, on the manifest (`grep -n 'babel' task-tracker/server.py`), and serves `200 text/javascript`
on demand. The page simply never asks for it: `ensureBabel()`
(`grep -n 'function ensureBabel' task-tracker/support.js`) is reachable only from
`load(kind === "jsx", …)`, and the page has **zero** `x-import` occurrences
(`grep -c 'x-import' 'task-tracker/Task Tracker.dc.html' task-tracker/_ds/*/_ds_bundle.js` → `0`, `0`),
so no view can produce the request and no differently-driven run rescues it. **The full reasoning is
criterion 13's own note in the spec half, which is authoritative and is not restated here** — this
card has already been bitten once by a duplicated paragraph that drifted.

⚠️ **Two instrument caveats — the measurements stay here, the reasoning moved onto the criterion.**
(1) For run (a)'s `/tracker-data.js`, `read_network_requests` reported **`503`** while three oracles
reported **`404`**: the server's audit log (`refused status=404 reason=not_found path=tracker-data.js`),
a `curl -s -D -` (`HTTP/1.1 404 Not Found`), and the page's own `fetch('/tracker-data.js')`
(`status: 404`, body `{"ok": false, "error": "not_found"}`). The server is correct and the extension's
status column is wrong, so that column must be corroborated — a run trusting it alone reads a correct
server as a broken one. (2) `/favicon.ico` is observable only on a first, uninstrumented load: capture
cannot start until `read_network_requests` has been called once, which needs a page already loaded,
and Chrome caches the negative by then. It was captured by the server's audit log
(`refused status=404 reason=not_found path=-`, `04:22:46Z`), which is how the criterion now scores it.

The extension also injects four `chrome-extension://…` scripts (`hook-exec.js`, `detector-exec.js`,
`detector.js`, `popups-script.js`) into every enumeration. Observer artefacts, not page requests and
not `http` to any host; named so a later run does not read them as a manifest widening.

**RESOLUTION 2026-08-11 — the spec was revised, and the run above now matches it exactly.** The
failure record is left standing rather than rewritten: it is the evidence, and it is what justified
the revision. Both escalated gaps were closed in the spec half (`path_escape` added to the `reason`
enum and the `403` row; `babel.min.js` removed from criterion 13's expected set, with task 9 picking
up **both** the manifest row and the `vendor-resources.js` mapping), plus the `/favicon.ico` row
scoped to the audit log and the two instrument caveats recorded on the criterion itself.

Re-scored against the revised tables, **using the enumerations already recorded above — no new run**:

| Run | Observed distinct `http` paths | Revised expectation | Match |
|---|---|---|---|
| (a) | 16 (`tracker-data.js` appears twice; `chrome-extension://` rows excluded) | 17 rows − `/favicon.ico` (audit-log-scored) = 16 | **exact** |
| (b) | 15 | (a)'s 16 − `/tracker-data.sample.js` = 15 | **exact** |

So criterion 13 passes on the evidence already on file, and **task 14 is ticked above** on that
re-score.

Content-Type was verified separately, over `GET` because `HEAD` is a `405`
(`for p in …; do curl -s -D - -o /dev/null "http://127.0.0.1:8422/$p"; done`, 2026-08-11): every path
above returned the manifest's type — `text/html`, `text/javascript`, `text/css`, `font/woff2`, and
`application/json` for the two refusals. This pass is server-side and issues its own requests, so it
was run **after** both enumerations, never during one.

**Task 13 — every suite, before and after. Ran 2026-08-12. Zero failures on either side.**

The before-counts could not come from this worktree: the feature's code is already committed here, so
a run in this tree is an *after* count by definition. They were taken from a throwaway detached
checkout of `main` at `1b983d9` (`git worktree add --detach <scratchpad>/baseline-main main`), which
is the only way the claim "not a pre-existing failure" is measured rather than reasoned about.

| Suite | Invocation | Before (`main` @ `1b983d9`) | After (branch @ `578438e`) |
|---|---|---|---|
| `task-tracker/` | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` | **53 passed**, 3.86s | **159 passed**, 108.29s |
| `memsearch/` | `cd memsearch && uv run pytest -q` | **74 passed, 23 deselected**, 0.55s | **74 passed, 23 deselected**, 0.55s |
| `hooks/` | each `hooks/*.test.sh` and `hooks/lib/*.test.py` run directly, exit code checked | **11 of 11 files exit 0** | **11 of 11 files exit 0** |

`node --version` = **v26.5.0** on the host for both sides.

**The two count columns are not meant to match, and only one comparison is load-bearing.**
`task-tracker/`'s before-count is smaller because `main` carries only part of this feature —
`analyze.py`, `store.py` and their two test files, but no `server.py`, `test_server.py`,
`test_server_lifetime.py` or `test_ui_commands.py` (`git ls-tree --name-only main task-tracker/`).
The baseline's job is the **failure** column, not the total: `main` is green, so none of the 159 can be
excused as pre-existing and no failure had to be argued about. The other two suites are untouched by
this branch and their identical figures are the evidence of that.

**Criterion 5 has its JS-engine oracle, and criterion 15 is verified — because nothing skipped.** The
`task-tracker/` run reports `159 passed` with no `skipped` term at all, so every node-guarded test
executed. §Verification's degraded wordings above ("criterion 5 verified without a JS-engine oracle";
criterion 15 **not verified**) are the node-less-host branch and did **not** apply to this run.

⚠️ **The guard count re-derivation needed one filter the original command did not carry, and it has
been fixed in place above.** `grep -c skipif task-tracker/*.py` totals **15**, but one of them —
`test_server.py:556`, `skipif(os.geteuid() == 0, …)` — guards on **root**, not on `node`. The
node-guarded figure is **14** (`grep -h 'skipif(NODE is None' task-tracker/*.py | wc -l`): 3 in
`test_store.py`, 11 in `test_ui_commands.py`. The number is decorators, not tests — that distinction
does not matter here only because the skip count was zero.

**This correction was *not* a spec edit, and an earlier revision of this section wrongly said it was.**
The `grep -c skipif` instruction lives only in this `.md` half; the spec half contains no such command
(`grep -n 'skipif' <spec>` returns two unrelated lines, one of which correctly scopes "three
`test_store.py` tests"). So it was always editable under the phase gate and cost no compliance
re-judge — unlike the two genuine spec corrections, which landed at `d142643`.

**`memsearch`'s golden and measurement tests did not run on either side, by configuration.**
`memsearch/pyproject.toml` sets `addopts = "-m 'not golden and not measurement'"`, which is where the
**23 deselected** comes from. Those are the real-index tests, so this pass says nothing about them in
either direction — deselected is neither passed nor failed, and the symmetry across before/after is
what makes the comparison sound, not their absence.

**Review-phase closeout, 2026-08-19.** Two items landed before this card reopened; both are
permitted at `phase: review`.

- Three notes in this half claimed the two spec corrections of `d142643` were still queued. They
  were not: `d142643` landed both, but touched only the `.spec.md` half (one file, +18/−6), so the
  pointers beside them went stale. Corrected in place at tasks 8 and 9 and in the guard-count
  paragraph above. This is the same defect `d142643`'s own message names — "leaving a known thing
  described as unknown" — reproduced three times by the commit that fixed two instances of it.
- `origin/feat/tracking-feature-state` was deleted. Verified at the moment of action, not earlier:
  `529456d`, **0 commits ahead** of `origin/main` and an ancestor of it
  (`git merge-base --is-ancestor` → true), so nothing on it was unmerged. Restore if ever needed:
  `git push origin 529456dc2e4be61f3a1cd4e77a25ce3749a21998:refs/heads/feat/tracking-feature-state`.

**Reopened to `planning` 2026-08-19**, for task 15: the analyzer cannot read this repo's own
closed-card convention. Per the frontmatter convention at the head of this card, the reopen keeps a
real branch rather than resetting to `none`, and takes the literal `gate confirmed` again before
task 15 begins. Task 16's closing frontmatter is deliberately *not* written yet — writing it now
would seed a fourth instance of the defect task 15 exists to fix.
