# Observability verdict — `feat/tracking-feature-state` round 10 (architecting, advisory)

- **repo:** `tracking-feature-state` (worktree `/Users/marksuyat/.claude/.claude/worktrees/tracking-feature-state`)
- **branch:** `feat/tracking-feature-state`
- **head_sha:** `3ca4daffd90391b832cd61ed79c371768de87008`
- **base:** `main` (merge-base `fe55b2d5052d85deb87283eab6c6545e17b56e40`)
- **stage:** `architecting` — advisory, does not block
- **judged artifacts:** `docs/features/tracking-feature-state.md` (303 lines) +
  `docs/features/tracking-feature-state.spec.md` (976 lines), read in full from source
- **risk:** medium · **confidence:** high

---

## What was changed

The design document for this feature had grown into a single 1,204-line file that got read into
memory at the start of every session — like keeping the entire owner's manual in your glovebox when
all you ever need at a glance is the one-page checklist. This round tore the manual in two: a short
**checklist half** you read every time (303 lines) and a long **reference half** you only open when a
task sends you there (976 lines). Alongside the split, five specific defects that earlier reviews had
flagged were closed — most importantly, a log line that was supposed to record *which file failed and
why* had nowhere to put either fact, so any test written against it would have quietly agreed with
whatever the code happened to do.

## Does it do what you wanted?

**Yes, and the headline problem is genuinely solved.** Last round I failed this change on context
budget — the document had grown for fourteen commits straight and the authorised fix had sat untaken
for six rounds. It is now taken, and the numbers hold up under my own checking rather than on the
author's word:

- Session-start load: **1,204 → 303 lines (−75%)**.
- I reassembled both halves and compared them line-for-line against the pre-split file. **11 lines
  are "missing" and every one of them is a line this same commit deliberately rewrote** (the old log
  format, the old `403` row, the old `reanalyze` row, the old font-scope wording). Nothing was
  silently dropped in the move.
- **Duplication between the halves is 2 lines**: the shared `# ` title, and one `grep` command that
  legitimately appears in both a task and the security rationale. For a 1,279-line document split
  across a boundary, that is close to the best achievable — `gates.md` warns that two documents
  describing the same work means a reader can't tell which is wrong, and that warning is respected.
- Net growth is **+75 lines**, volunteered honestly in the invocation rather than buried. Against
  −901 at session start, that is noise.

The four defects I named last round were all closed, and I confirmed each from source rather than
from the summary:

| Last round's finding | Status |
|---|---|
| Audit line had no field for `path` or `errno` | **Fixed** — `.spec.md:399`; `errno` is the symbolic name, `path` is the *manifest* path so the serving root can't leak into a pasted log. The reasoning here is better than what I asked for. |
| `nosniff` asserted by nothing | **Fixed** — task-9 bullet, `.md:106-108` |
| Unmapped-extension startup abort asserted by nothing | **Fixed** — `.md:109-113`, proven by a `GET /` that gets no answer rather than by reading code |
| Criterion 13 needs regular *and* fill icons | **Fixed** — `.spec.md:861-865`, plus "record which view was used" |

Two calls the invocation flagged as mine to second-guess: **both are right.** Keeping `§Verification`
in the checklist half is correct — task 13 writes into it during implementation, when the phase gate
forbids editing a spec; in the spec half that task becomes un-performable. And omitting frontmatter
from the spec half is correct and already has a working precedent in this repo
(`docs/features/memory-system-split.spec.md` does the same thing).

**Evidence I ran myself, not took on trust:**

- Pinned suite: `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` → **53 passed in
  4.17s**, matching the card's dated measurement. `node v26.5.0` is present, so the three
  node-guarded tests actually ran rather than skipping.
- Every pinned tool re-read and every one matches: Python `3.9.6`, uv `0.11.28`, node `v26.5.0`,
  cmux `0.64.20 (100) [14e3400b9]`.
- Every `§` reference in the checklist half resolves (`§Design 3`, `§Security`, `§"Injection route"`,
  `§Toolchain` → spec half; `§Verification` → checklist half, stated explicitly at `.md:14-17`).
- Working tree clean; the change touches only docs and memory files.

On the invocation's direct question about the log: **yes, `reason` now tells the three `502` cases
apart** — `confirm_failed`, `confirm_timeout` and `send_failed` are separate values behind one wire
code (`.spec.md:419-424`). That part is sound.

## What could go wrong / what I'm unsure about

**1. The split broke one reference, and it broke it under the one task that needs it.**
`.md:279` says "Run the pinned invocation above." In the pre-split file `§Toolchain` sat at line 1106
directly above `§Verification` at 1149, so "above" resolved. `§Toolchain` is now at `.spec.md:923`
and **there is no invocation anywhere in the checklist half.** Task 13 — the task whose whole job is
to run the suites and record counts — lives in the checklist half and can no longer reach the command
it must run. The header's promise that "every `§` reference resolves in the spec half" does not cover
this, because it is not a `§` reference. This is exactly the cross-file coherence regression the
split risks.

**2. The `reanalyze` timeout added this round is a control nothing asserts — the card's own named
recurring defect, reproduced inside the fix for the previous one.** `TASK_TRACKER_ANALYZE_SECS` and
the 60-second bound appear **exactly once**, in the contract-table row at `.spec.md:374`. No task
bullet, no criterion. Compare `TASK_TRACKER_POLL_SECS`/`TASK_TRACKER_IDLE_SECS`, which appear in both
task 9's bullet *and* criterion 14. A test author closing "each status code in the contract table"
will most naturally make the analyzer *exit non-zero*, collect the `500`, and never touch the timeout
branch — so the branch ships untested and the failure it exists to prevent (a request hanging
forever) stays live behind a green suite. The card names this shape twice in its own text
(`.md:100-103`, `.md:130-132`): "a control shipped by the round that was fixing the previous one and
left unasserted."

**3. The `reason` enumeration is still closed and still doesn't cover three of the ten status rows.**
`.spec.md:419-420` lists values and ends "or `-` on success" — a closed list. It omits `not_found`
(404), `method_not_allowed` (405), and `asset_unreadable` (500). **I raised this in round 9 and it was
not fixed**, even though the finding immediately adjacent to it in the same concern list *was*. Two
consequences:

- Criterion 13 run (a) requires two expected `404`s whose `reason=` value is undefined, and task 9
  requires asserting the audit line for "each status code". A test written against an undefined
  field is written to match whatever the code emits and passes automatically — **the self-fulfilling
  assertion this card exists to prevent**, which is precisely the argument the commit message makes
  for fixing the `path`/`errno` half.
- Operationally: §Security argues "a run of refusals is the only evidence a hostile page ever probed
  the endpoint," but a path-traversal probe (criterion 11's attack) logs as `status=404 reason=?`
  with `path=-`, because `path` is explicitly reserved for manifest paths. An operator cannot tell
  traversal probing from favicon noise. Note the tension before "just log the request path": that
  path is attacker-controlled text going into a log.

**4. `phase: planning` while seven tasks are done and their code is merged to `main`.** The card reads
`phase: planning`, yet tasks 1–7 are `[x]` and `task-tracker/analyze.py` is present in `main`
(commit `37a8e38`). Neither half of the document explains this. `CODING_MEMORY.md:4955` does record
"Phase stayed `planning` throughout", so it is deliberate rather than stale — but a reader six months
out, opening the card cold, sees a planning card with shipped code and no explanation, and `gates.md`
calls a phase/reality mismatch stop-and-report rather than guess. Concretely: `phase-guard.sh` will
deny writing `task-tracker/server.py` (task 8) until the gate opens, which is correct behaviour — but
worth knowing before someone tries.

**5. Smaller, carried:** `.md:184` cites "line 6's `support.js`" as a bare number with no re-find
command, while `.spec.md:306` states the same fact *with* the command — the bare copy is the one in
the half read at session start, against the card's own line-24-32 discipline. And `analyze.py` sits
at **792/800 lines**, unchanged; no remaining task edits it, but there are 8 lines of headroom and
the `git_facts.py` split remains named-but-unscheduled.

## What I'd double-check before merging

1. **Fix the dangling invocation reference** — either repeat the `uv run …` command in `§Verification`
   (it is one line, and task 13 needs it in hand) or change "above" to a named `§Toolchain` pointer.
   I'd repeat the command: task 13 must not open the spec half to do its job.
2. **Give the `reanalyze` timeout an assertion** in task 9 — short `TASK_TRACKER_ANALYZE_SECS`, a
   hanging analyzer, require `500 reanalyze_failed` and the previous `tracker-data.js` intact.
   Otherwise this round has added the eleventh instance of the card's signature defect.
3. **Close the `reason` enum** over all ten contract rows, or state in the text that it covers only
   the collapsed codes and say explicitly what `reason` carries for a `404`/`405`. Then decide
   deliberately whether an unlisted requested path is recorded at all — and if so, sanitised.
4. **Sweep the split for any other relative reference** ("above", "below", "the table above") that
   crossed the file boundary. I found one; a `grep -nE 'above|below'` across both halves against the
   pre-split ordering is a five-minute check that would confirm there is only one.
5. **Say in the card why `phase: planning` coexists with seven shipped tasks**, in one sentence, so
   the next reader doesn't have to reconstruct it from `CODING_MEMORY.md`.

---

## Dimension table

| Rubric | Dimension | Verdict | Basis |
|---|---|---|---|
| Evaluation | `intent` | **pass** | Split executed and all five named fixes landed; each verified from source, not from the summary |
| Evaluation | `execution` | **concern** | Pinned suite green (53 passed) and all four tool pins match, but the round's own new control ships unasserted and one cross-file reference no longer resolves |
| Evaluation | `trajectory` | **pass** | Split done as a verified line-range move with a reproducible check; +75 net growth volunteered rather than buried; fixes trace to prior findings |
| Evaluation | `regression` | **concern** | `.md:279` "the pinned invocation above" broke — `§Toolchain` moved to the spec half; task 13 lives in the checklist half and needs that command |
| Evaluation | `context_budget` | **pass** | Round-9 **fail** resolved: session-start load 1204 → 303 (−75%); cross-half duplication measured at 2 lines |
| Observability | `traceability` | **concern** | Refs resolve and derivations carry commands, but `.md:184` keeps a bare line number without a falsifier, and the planning/shipped-code state is explained only outside the card |
| Observability | `success_masking` | **concern** | `reanalyze` 60s timeout asserted nowhere (unbounded-wait shape); `reason` enum gap makes task 9's 404/405/`asset_unreadable` audit assertions self-fulfilling |
| Observability | `intent_drift` | **pass** | Diff touches only docs and memory; no scope creep, no drive-by edits, no dependency changes |
| Observability | `checkpoint` | **pass** | Clean tree, single coherent commit, cleanly revertible; nine prior verdicts on record |
| Observability | `audit_trail` | **pass** | Per-round verdicts + `verdicts.jsonl` + ADRs 0022/0023/0024 named; commit message accurate to the diff |

No dimension is `fail`. Round 9's `context_budget` **fail** is cleared.

## Concerns

1. Split broke `.md:279` "the pinned invocation above" — `§Toolchain` now at `.spec.md:923`; task 13 lives in the checklist half with no invocation reachable
2. `reanalyze` 60s timeout / `TASK_TRACKER_ANALYZE_SECS` appears once (`.spec.md:374`), in no task and no criterion — the card's own "control shipped by the fixing round, left unasserted" shape, 11th instance
3. `reason` enum still closed and still omits `not_found`, `method_not_allowed`, `asset_unreadable` — raised in round 9, unfixed while the adjacent `path`/`errno` half was fixed
4. Task 9's audit assertions for 404/405 have no defined `reason` to assert against, so the test is written to match the code and cannot fail
5. Traversal probes (criterion 11's attack) log `path=-` with undefined `reason`, contradicting §Security's "a run of refusals is the only evidence a hostile page probed the endpoint"
6. `phase: planning` with tasks 1-7 `[x]` and `analyze.py` merged in `main` (`37a8e38`); explained only in `CODING_MEMORY.md:4955`, not in either half
7. `.md:184` cites bare "line 6's `support.js`" with no re-find command while `.spec.md:306` carries the command — the bare copy sits in the session-start half
8. `analyze.py` at 792/800 lines, unchanged from round 9; `git_facts.py` split named but unscheduled
9. Criterion 13 remains agent-driven, not runnable under `uv run pytest` and not unattended — stated cost, carried
