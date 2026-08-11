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

