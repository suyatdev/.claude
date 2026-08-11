---
phase: implementation
model_tier: low
branch: feat/tracking-feature-state
---

# Feature-state tracking with a browser UI

**The spec half of this feature lives in `tracking-feature-state.spec.md`** — design, the injection
route, security, and all fourteen acceptance criteria. The analyzer skips it **by filename** — the
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

The full statement of that rule — the defect history behind it, and the three scope failures that
cost this feature the most rounds — is the preamble of `tracking-feature-state.spec.md`, which is
**authoritative if the two ever read differently**. It is deliberately not restated here: an earlier
revision did restate it, and the copy had already drifted, dropping the stamped-measurement clause
that the section below depends on.

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
- [x] 8 — `task-tracker/server.py` to the wire contract in §Design 3. **Task 14 runs immediately after this one.** Every route, refusal and startup abort smoke-verified against a cmux shim; task 9 is what pins them as tests.
- [ ] 9 — `task-tracker/test_server.py`: criteria 6, 7, 9, 10, 11, **12 and 14**. Not criterion 13.
- [ ] 10 — Wire the UI's command buttons to `POST /command`; copyable text where no terminal exists. **Owns criterion 15** — the page's own failure behaviour, which no server test can reach.
- [ ] 11 — `skills/tracking-feature-state/SKILL.md`. Owns two security controls at launch.
- [ ] 12 — Add the skill to the Skills Catalog in `CLAUDE.md`.
- [ ] 13 — Run every suite, record before/after counts in `## Verification` below.
- [ ] 14 — Vendor all six remote assets — nine local files. **Runs right after task 8**; owns criterion 13.

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
applies here. Stated because an earlier revision warned about exactly that, having read a different
package's config as this one's.

**Criterion 13 — the two browser runs. Ran 2026-08-11. Result: one row fails, in both runs, and
task 14 is therefore not ticked.** Chrome `151.0.0.0` (`navigator.userAgent`, macOS), extension
`read_network_requests`. Server started from the worktree with the scratchpad `cmux` shim
(`CMUX_BIN`/`CMUX_SURFACE_ID`/`FAKE_SURFACE`), which is why every `surface=` in the log below is the
fake UUID. View driven: the default **Overview** — 45 regular and 1 fill phosphor glyph laid out
(`document.querySelectorAll('[class*="ph-"]…').length`), and `document.fonts` reported `Phosphor` and
`Phosphor-Fill` both `loaded`, which is the two-face condition the criterion demands.

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
| **`/vendor/babel.min.js`** | **never requested** | **never requested** | **FAILS — expected 200** |
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

**Why the babel row fails, and why it is not a vendoring defect.** The file is vendored, is on the
manifest (`grep -n 'babel' task-tracker/server.py`), and serves `200 text/javascript` on demand — the
`curl` sweep below confirms it. The page simply never asks for it: `support.js` loads babel **lazily**
from `ensureBabel()` (`grep -n 'function ensureBabel' task-tracker/support.js`), which is reachable
only from `load(kind === "jsx", …)`, and the page contains **zero** `x-import` occurrences
(`grep -c 'x-import' 'task-tracker/Task Tracker.dc.html' task-tracker/_ds/*/_ds_bundle.js` → `0`, `0`).
No view can produce the request, so no differently-driven run rescues it. The criterion pinned nine
`vendor/` rows in advance precisely so the implementation could not edit the target after the fact;
that discipline held and is what surfaced this. **Resolving it edits the spec, so it is escalated, not
worked around.**

⚠️ **The criterion's own named instrument misreported a status, and three oracles caught it.** For
run (a)'s `/tracker-data.js`, `read_network_requests` reported **`503`**; the server's audit log
(`refused status=404 reason=not_found path=tracker-data.js`), a `curl -s -D -` (`HTTP/1.1 404 Not
Found`), and the page's own `fetch('/tracker-data.js')` (`status: 404`, body
`{"ok": false, "error": "not_found"}`) all report **`404`**. The server is correct and the extension's
status is wrong. Recorded because criterion 13 names `read_network_requests` as the mechanism: its
status column must be corroborated, and a future run that trusts it alone will read a correct server
as a broken one.

⚠️ **`/favicon.ico` is observable only on the first load into a profile-fresh origin.** Chrome caches
the negative result, and the extension cannot begin capturing until `read_network_requests` has been
called once, which needs a page already loaded — so the instrumented load is always at least the
second, by which time the favicon is not re-requested. It was captured on the first, uninstrumented
load by the server's audit log (`refused status=404 reason=not_found path=-`, `04:22:46Z`). Stated
rather than tidied away: as written, the favicon row cannot be observed by the criterion's own
mechanism on the run that the criterion enumerates.

The extension also injects its own scripts into the page — four `chrome-extension://…` rows appeared
in every enumeration (`hook-exec.js`, `detector-exec.js`, `detector.js`, `popups-script.js`). They are
observer artefacts, not page requests, and not `http` requests to any host; they are named here so a
later run does not read them as a manifest widening.

Content-Type was verified separately, over `GET` because `HEAD` is a `405`
(`for p in …; do curl -s -D - -o /dev/null "http://127.0.0.1:8422/$p"; done`, 2026-08-11): every path
above returned the manifest's type — `text/html`, `text/javascript`, `text/css`, `font/woff2`, and
`application/json` for the two refusals. This pass is server-side and issues its own requests, so it
was run **after** both enumerations, never during one.

