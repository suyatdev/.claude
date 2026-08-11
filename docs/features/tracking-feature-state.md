---
phase: planning
model_tier: high
branch: feat/tracking-feature-state
---

# Feature-state tracking with a browser UI

⚠️ **This card has passed the planning→implementation gate more than once; the convention for that is
recorded here rather than as a fourth `phase` state.** The three-state field cannot express "paused
for revision", so when a mid-implementation spec revision is needed the card returns to
`phase: planning` — the only phase permitting spec edits — keeping its real branch and its ticked
tasks instead of resetting `branch:` to `none`; reopening then takes the literal `gate confirmed`
again. Compliance round 2 cited that `planning`-with-a-branch shape as `gates/phase-branch-mismatch`,
and documenting the convention was the answer, not a fourth state. **Read `phase:` above for where
the card is now** — this paragraph deliberately does not restate it, because one that names the
current phase goes stale at the very next transition, which is how it has broken before. Every other
`planning` card in this repo carries `branch: none` and zero ticked tasks; re-derive that with two
commands — `grep -m1 '^phase:' docs/features/*.md` and `grep -m1 '^branch:' docs/features/*.md` —
never one `-m1` over both patterns, which returns only `phase:` lines because `phase:` sorts first in
every card.

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
- [x] 8 — `task-tracker/server.py` to the wire contract in §Design 3. **Task 14 runs immediately after this one.** Every route, refusal and startup abort smoke-verified against a cmux shim; task 9 is what pins them as tests. ⚠️ **Ticked but owes one edit:** the `confirm_timeout` split in `confirm_surface()` lands in this file, as its own commit before task 9's test — §Tasks 8.
- [ ] 9 — `task-tracker/test_server.py`: criteria 6, 7, 9, 10, 11, **12 and 14**. Not criterion 13.
- [ ] 10 — Wire the UI's command buttons to `POST /command`; copyable text where no terminal exists. **Owns criterion 15** — the page's own failure behaviour, which no server test can reach.
- [ ] 11 — `skills/tracking-feature-state/SKILL.md`. Owns two security controls at launch.
- [ ] 12 — Add the skill to the Skills Catalog in `CLAUDE.md`.
- [ ] 13 — Run every suite, record before/after counts in `## Verification` below.
- [x] 14 — Vendor all six remote assets — nine local files. **Runs right after task 8**; owns criterion 13. Closed on the re-score in `§Verification` — both runs match the revised expectation exactly, on the enumerations already recorded; no new browser run was made.

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
`grep -c skipif task-tracker/*.py` rather than assuming it is still three. Criterion 5 keeps an
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

