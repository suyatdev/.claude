# Compliance judge — `docs/features/memsearch-freshness.md`

Spec: `/Users/marksuyat/.claude/docs/features/memsearch-freshness.md`
Repo: `.claude` · base branch `main`

---

## Round 1 — 2026-08-06T20:33:25Z

- **Verdict: FAIL** (7 violations)
- head_sha: `9475034edc496f9c9ab8cf95f630e16deb878204`
- spec_blob_sha: `4e217ec323dd37701b2bc32b1c5a60e0cfefb6a7`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (no `.claude/project-standards.md` in this repo — repo layer is `CLAUDE.md` + `rules/`)
- Confidence: **high** — every finding was checked against the live machine, not inferred.
- Waived: none.

### Layman summary

The diagnosis in this spec is excellent and I could not break it. I re-ran the measurements:
`status.json` really does read `last_indexed: 2026-07-18T06:18:01+00:00` while `memory.db` was
touched today, so the "file mtime doesn't track indexing" trap is real and correctly called out —
a refresh trigger keyed on mtime genuinely would never fire. The `+00:00` format really does parse
under the pinned Python 3.9.6 where a `Z` would not. bash 3.2.57, no `timeout` on PATH, `plutil` at
`/usr/bin/plutil` — all confirmed. The core insight, that the reporting half is what makes the
scheduling half honest, is the right architecture, and the scope discipline (stopping at parent
item 5, excluding item 6 because it rests on a result not yet obtained) is exemplary. Nothing here
is speculative; there is no YAGNI problem.

The nudge half — R1 through R3 — is close to build-ready. Seven Gherkin scenarios, an exact
one-line output for each of the three states, explicit handling for a missing, unparseable, or
future-dated timestamp, and a "fail toward doubt" rule that never claims freshness it can't prove.
That is the part of the spec doing real work.

**The launchd half is where this fails, and it fails in the same shape as the bug it is fixing.**

The most important finding is concrete and mechanical. `memsearch/bin/install-schedule` will
install a job that runs `memsearch index`, but `memsearch/bin/memsearch` is a one-line wrapper
whose entire body is `exec uv run --project "$HOME/.claude/memsearch" ...`. On this machine `uv`
lives at `/opt/homebrew/bin/uv`. `launchctl getenv PATH` returns empty, so the job inherits
launchd's default `/usr/bin:/bin:/usr/sbin:/sbin` — and `uv` is not in any of those four
directories. I checked. The spec's plist contract lists `StartInterval`, `RunAtLoad`,
`StandardOutPath`/`StandardErrorPath`, the `__HOME__` placeholder and a `plutil -lint` gate, but it
never names `ProgramArguments`, `Label`, or an `EnvironmentVariables` PATH. So an implementer
follows the contract exactly, the install reports success, and the job dies at exec with status 127
every six hours forever. The stale line would eventually surface it — which is the design working —
but shipping a scheduler that has never once run is not the intent, and one line of contract
prevents it.

The second finding is the install script's error handling. The spec is admirably explicit that a
`plutil -lint` failure means refuse-and-fail-closed, and that `bootout` should ignore "not found"
for idempotency. But `launchctl bootstrap` — the single call that determines whether the scheduler
exists at all — has no stated failure behaviour, and neither does a missing `~/Library/LaunchAgents`
directory, an unwritable render target, or the script's own exit code. `bootstrap` fails routinely
and noisily in practice (domain errors, an already-loaded label, a plist mode launchd rejects). As
written, a failed install is indistinguishable from a successful one.

The rest are smaller but each would force an implementer to guess: no scenarios at all for R4–R7
(every scenario covers the nudge, none covers the half with system-level side effects); `uv` missing
from the pinned toolchain table despite being the runtime the scheduled job actually executes;
R7's acceptance bar counting "hits from the named feature's own documents" without saying what
makes a document belong to a feature; and a log file specified only as "a log under
`~/.claude/memory-index/`" — a directory that already holds an unexplained zero-byte `reindex.log`.

One thing I want to record as *passing*, because the request asked: **the falsifier is genuinely
falsifiable.** Clauses (a), (b) and (e) are mechanically hook-testable, (d) is checkable from git
history precisely because the queries commit first, and (c) is observational but has a defined
threshold. It is not a fake falsifier and it should survive the revision unchanged.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | API contracts give the agent real interface boundaries instead of letting it improvise shapes | Contracts → `memsearch/launchd/local.memsearch-index.plist.template` | The plist contract omits `Label`, `ProgramArguments` and any `EnvironmentVariables` PATH, so the command line must be invented — and the obvious rendering fails at exec because `memsearch` execs `uv` from `/opt/homebrew/bin`, absent from launchd's default PATH. |
| 2 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Handle errors explicitly, never swallow them; fail closed on any validation failure | Contracts → `memsearch/bin/install-schedule` | Only `plutil -lint` failure has stated behaviour, while `launchctl bootstrap` failure — the boundary deciding whether the scheduler exists at all — plus a missing `~/Library/LaunchAgents`, an unwritable target and the script's own exit codes are unspecified, so a failed install can report success. |
| 3 | `writing-specs/edge-cases` | `skills/writing-specs/SKILL.md` | State what correct looks like, what wrong looks like, and enumerate the edges | Scenarios | All seven scenarios exercise the nudge (R1–R3); R4–R7 — install idempotency, the fail-closed lint refusal, a bootstrap failure, the golden-query change, the retrieval bar — have no scenario at all, and that is the half with system-level side effects. |
| 4 | `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md` | Pin the exact version of every library and tool | Toolchain — pinned | `uv`, the runtime the scheduled job actually executes (`memsearch/bin/memsearch` is a one-line `exec uv run --project` wrapper), is absent from the table entirely, and `sqlite3` is listed as `system` with no version. |
| 5 | `gates/adr-required` | `rules/gates.md` | ADRs under `docs/decisions/` remain required for structural and direction-pivoting decisions | Design decisions (3) / Tasks | Adopting a persistent `launchd` daemon as the scheduling mechanism is structural, and the spec overturns two parent-spec items on new evidence, yet none of the nine tasks writes an ADR — in a repo whose 17 existing ADRs sit at finer granularity than this (0002 sqlite-over-qdrant, 0014 empty-index). |
| 6 | `writing-specs/ambiguous-acceptance-bar` | `skills/writing-specs/SKILL.md` | Requirements the agent can satisfy and you can check; no requirement readable two ways | Requirements → R7 | "≥2 hits from the named feature's own documents" and "top hit from that feature" give no membership rule for what counts as a feature's own document (path prefix? ADRs? hooks?), so task 8's pass/fail becomes a judgment call rather than a measurement. |
| 7 | `writing-specs/ambiguous-log-path` | `skills/writing-specs/SKILL.md` | No placeholders or requirements readable two ways | Contracts → plist template (`StandardOutPath`/`StandardErrorPath`) | The log is specified only as "a log under `~/.claude/memory-index/`" with no filename, and that directory already contains an unexplained zero-byte `reindex.log`, so an implementer cannot tell whether to reuse it or create a new one. |

### Notes (non-blocking)

- **Falsifier passes.** (a), (b), (e) are mechanically hook-testable; (d) is git-checkable and is
  the reason committing the queries first is load-bearing; (c) is observational with a defined
  threshold. Genuinely falsifiable — keep it as written.
- **Boundary validation on `last_indexed` is well specified** — absent, unparseable, and negative
  age all route to unknown-age and never to fresh, and the exact output wording never echoes the
  raw field, so there is no injection path into the emitted line. Right posture.
- Diagnostic claims verified live: `status.json` reads `last_indexed 2026-07-18T06:18:01+00:00`
  with 228 sources / 2332 chunks; `memory.db` mtime is today against a Jul 18 index, confirming the
  mtime trap; the SQL `_`-wildcard warning is correct; `datetime.fromisoformat` under 3.9.6 parses
  `+00:00` but not `Z`, as stated.
- Toolchain claims verified: bash 3.2.57(1)-release arm64-apple-darwin25, python3 3.9.6, no
  `timeout` binary on PATH, `plutil` present at `/usr/bin/plutil`.
- **Not cited — file modes.** No mode is stated for the rendered plist (launchd refuses a
  group/world-writable plist, so this is functional, not just hygiene) or for the new log, and the
  log appends forever with no rotation stated.
- **Not cited — zero-trust.** Task 7 has an implementing agent install a persistent background
  daemon into the user's login session with no stated confirmation step; core-conduct wants
  destructive/autonomous actions summarised in plain English first. Held as a note because the
  human spec-review gate arguably supplies that consent.
- **Not cited — spec location.** `writing-specs` defers to `docs/superpowers/specs/`, but the repo
  layer (`rules/gates.md` one-canonical-file discipline) mandates `docs/features/<name>.md` for
  feature-scale work, and project rules win on conflict. Same reasoning as the `memory-system-split`
  rounds.
- **YAGNI is clean.** Scope explicitly ends at parent item 5; item 6 is excluded with a stated
  reason; the four non-goals are named. No speculative surface.
- Incidental: `memory.db` is now ~42 MB against `status.json`'s recorded `db_bytes` of ~17.5 MB —
  `query_log` growth since July. Out of scope here, but the scheduler will make `db_bytes`
  meaningful again, and unbounded `query_log` growth may deserve its own item later.

---

## Round 2 — 2026-08-06T21:32:00Z

- **Verdict: FAIL** (2 violations — **all 7 round-1 violations are fixed**; both findings are new)
- head_sha: `124b504d5b3d31128d2690d75bb746258be39557`
- spec_blob_sha: `ca5b5e0260b008c1f3d75163871e4fb0519c202b`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
- Confidence: **high** — both new findings were verified against the live source, not inferred.
- Waived: none.

### Layman summary

The revision did what it claimed, and I checked each claim rather than taking it. All seven
round-1 violations are genuinely closed: the plist contract is now a key-by-key table with `Label`,
`ProgramArguments`, the load-bearing `PATH` that includes `/opt/homebrew/bin` (I re-confirmed `uv`
is at `/opt/homebrew/bin/uv` and that `memsearch/bin/memsearch` is a one-line `exec uv run`
wrapper), `PYTHONUNBUFFERED`, `ProcessType`, mode `0644`, and a named log `scheduled-index.log`
distinguished from the leftover `reindex.log`. `install-schedule` now has four exit codes, a
post-bootstrap `launchctl print` verification, directory creation, and an explicit fail-closed
rule. Scenarios went from 7 to 19 and the install half, the package change and the golden query all
have their own. The toolchain table now pins `uv 0.11.28`, venv `python 3.12.13` and
`sqlite3 3.51.0` — I ran all three and every number matches exactly. Task 2 writes ADR 0018, and
0018 is in fact the next free number (existing ADRs stop at 0017). R9's membership rule is now
mechanical. Internal consistency is unusually good: the task list's "ten nudge scenarios" and "six
install scenarios" both count correctly.

The `last_run` fix is the right fix and I verified the defect it addresses:
`_index_one` really does `return` early when a file's hash is unchanged
(`memsearch/memsearch/index.py:125-127`), and `last_indexed` really is `max(indexed_at)`
(`db.py`), so a successful run that changes nothing never advances it. Building staleness on
`last_run` instead is correct.

**Two new things block, and the first is the more serious of the two.**

The design writes a `last_run_errors` field that nothing ever reads. I traced what actually happens
when a run fails the way this spec says it fails: `_index_one` catches *every* exception into
`report["errors"]` and keeps going, and `run_index` then writes `status.json` unconditionally at the
end. So a scheduled run with Ollama down does not crash — it completes, stamps a brand-new
`last_run`, records the errors, and the nudge prints the **fresh** line. Decision 4 says the
scheduler "runs blind" and that the staleness warning "is exactly the compensating control"; the
data-flow diagram draws a dotted edge labelled "run fails: Ollama down" as the failure signal. That
control does not cover its own named failure mode: a run that fails on every file *clears* the
warning rather than raising it. This is the same shape as the bug the spec exists to fix — a
reassuring line vouching for an index nobody checked. The fix is small (one classification branch,
or one sentence saying a non-zero `last_run_errors` never renders as plain fresh), but it has to be
decided in the spec, not guessed at by the implementer.

The second is documentation drift, and it is mechanical. `memsearch/README.md` states as an
invariant: "`CODING_MEMORY.md` and `subagents/` transcripts are never indexed." R8 deletes
`CODING_MEMORY.md` from `exclude_paths` (I confirmed it is there today, `memsearch/config.json:16`),
which makes that line false the moment task 6 lands. Tasks 6 and 7 update `config.json` and
`golden_queries.json` but nothing updates the README — and the README's Usage block will also be
the only place a human would look for the new `bin/install-schedule` entry point. `writing-specs`
is explicit that README updates happen in the change that makes them wrong, not later.

On the two items I was asked to re-judge from scratch: the missing confirmation step before
installing a persistent daemon stays a note — the action is additive and idempotent, the spec is
itself the plain-English summary, and the human review gate supplies consent — though I would still
like one line naming the uninstall (`launchctl bootout` + `rm`), because nothing outside the repo is
covered by a git checkpoint. The `docs/features/` vs `docs/superpowers/specs/` path also stays a
note: this file carries `phase` frontmatter and a task checklist, which `rules/gates.md` mandates
live at `docs/features/<name>.md`, and the repo layer wins on conflict.

R9's downgraded blindness guarantee is, as asked, judged only for honesty: it is honest. It states
what was lost, why it cannot be recovered, exactly what remains ("written without first running any
query against the rebuilt index"), and it invites the reader to discount the result. The falsifier
carries the same downgrade in clause (d). That is the right way to record a weakened guarantee.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `core-conduct/unsurfaced-run-errors` | `rules/core-conduct.md` | Handle errors explicitly, never swallow them; fail closed on any validation failure | Design decisions 4 & 6 / R5 / Contracts → `hooks/memsearch-nudge.sh` classification | `last_run_errors` is written to `status.json` but no requirement, scenario or classification branch ever reads it, so a run in which every source failed (Ollama down — the failure mode decision 4 names) still stamps `last_run` and prints the *fresh* line, silently clearing the very warning decision 4 designates as its compensating control. |
| 2 | `writing-specs/readme-drift` | `skills/writing-specs/SKILL.md` | Drift causes hallucination — the obligation runs down to `README.md`, updated in the change that makes it wrong, not later | Requirements → R8 / Tasks 6–7 | R8 removes `CODING_MEMORY.md` from `exclude_paths` (`memsearch/config.json:16`), which falsifies `memsearch/README.md`'s stated invariant "`CODING_MEMORY.md` and `subagents/` transcripts are never indexed", and no task updates that README — which is also the only place documenting `memsearch/bin/`, where the new `install-schedule` entry point lands. |

### Round-1 violations — all fixed

| round-1 id | status | evidence checked this round |
|---|---|---|
| `writing-specs/api-contracts` | **fixed** | Plist table now names `Label`, `ProgramArguments`, `EnvironmentVariables → PATH` (with `/opt/homebrew/bin`, re-verified as `uv`'s real location), `PYTHONUNBUFFERED`, `ProcessType`, mode `0644`. |
| `core-conduct/explicit-error-handling` | **fixed** | `install-schedule` now states exit codes 0/1/2/3, directory creation at `0755`, a post-bootstrap `launchctl print` verification, and an explicit fail-closed/no-success-message rule. |
| `writing-specs/edge-cases` | **fixed** | 19 scenarios (counted): 10 nudge, 6 install incl. idempotency, lint refusal, bootstrap failure and unwritable directory, plus package, golden-query and retrieval scenarios. |
| `writing-specs/pinned-versions` | **fixed** | `uv 0.11.28`, venv `python 3.12.13`, `sqlite3 3.51.0` — all three run on this machine and match exactly; macOS `25.5.0` confirmed via `uname -r`. |
| `gates/adr-required` | **fixed** | New task 2 writes `docs/decisions/0018-*.md`; `docs/decisions/` currently ends at `0017`, so the number is free and correct. |
| `writing-specs/ambiguous-acceptance-bar` | **fixed** | R9 now defines membership mechanically: source path exactly `docs/features/F.md` or `docs/features/F.spec.md`, nothing else. |
| `writing-specs/ambiguous-log-path` | **fixed** | Log named `scheduled-index.log`, explicitly distinguished from `reindex.log` with the reason recorded. |

### Notes (non-blocking)

- **Considered and *not* cited — the first-run classification gap.** When `run_started` exists and
  `last_run` does not (the state during the very first run after this lands, since `run_index`
  stamps `run_started` while "preserving the prior `last_run`" that does not yet exist), the
  contract's ordered rule 1 (`run_started > last_run`) has an undefined predicate and is evaluated
  before rule 4 (`last_run` absent → unknown). R2 resolves it toward unknown-age; a natural
  implementation of rule 1 would resolve it toward in-progress. Held as a note because the window is
  one-time and a few minutes long, and both readings are safe — neither claims freshness and neither
  emits a remediation command that could invite a second indexer. One clause in rule 1 ("and
  `last_run` is present") would close it.
- **Not cited, unchanged from round 1 — no uninstall path.** The spec says how to install and
  re-install the agent but never how to remove it. Worth one line (`launchctl bootout` + `rm`),
  since a launchd agent lives outside the repo and no git checkpoint covers it.
- **Not cited — log mode and rotation.** The plist mode is now specified; `scheduled-index.log`'s
  mode is not, and it appends forever with no rotation. Local, single-user, low stakes.
- **Not cited — spec location.** Same reasoning as round 1: `writing-specs` defers to
  `docs/superpowers/specs/`, but `rules/gates.md` one-canonical-file discipline mandates
  `docs/features/<name>.md` for a file carrying `phase` frontmatter and a task checklist, and the
  repo layer wins.
- **Not cited — daemon-install consent.** Task 9 installs a persistent gui-domain agent. Additive,
  idempotent, spec-reviewed by a human, and decision 4 is an explicitly recorded user decision.
- **R9 honesty check passes.** The downgraded blindness guarantee is stated plainly, its cause is
  recorded, what remains is named precisely, and falsifier clause (d) carries the same downgrade.
- **YAGNI still clean.** The `last_run` widening into the package is evidence-driven and
  user-approved; non-goals name the lock/pidfile gap, the exit-code contract, parent item 6 and
  re-measurement cadence. No speculative surface. (`last_run_errors` is the one field with no
  consumer — cited above as an error-handling gap, not as YAGNI, because the right fix is to *use*
  it, not to drop it.)
- **Security territory is clean.** `install-schedule` executes only fixed `launchctl` argument
  vectors; the template's only substitution is `__HOME__` → `$HOME`; the committed template holds no
  absolute user path (a scenario asserts it); the nudge still reads a plain JSON file, never invokes
  the CLI, renders computed ages rather than echoing raw fields, and exits 0 on every path.
- Source claims re-verified this round: `_index_one` early-returns on an unchanged hash and catches
  every exception into `report["errors"]`; `run_index` calls `_write_status` unconditionally after
  the loops; `stats()` computes `last_indexed` as `max(indexed_at)`; `cli.py` returns 0
  unconditionally for `index`. All as the spec describes.

## Round 3 — 2026-08-06T22:03:26Z

- **Verdict: FAIL** (2 violations — one **new and blocking**, one **persistent from round 2**,
  now half-fixed; round-2 violation 1 is genuinely closed)
- head_sha: `34718d8f86ba7bcd88ca8a88135ac9f3143a07d9`
- spec_blob_sha: `eef3aea004dc865e692205b17562f2f56cc89e26`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (no `.claude/project-standards.md` exists in this repo)
- Confidence: **high** — both findings were read out of the live source with exact line numbers,
  not inferred from the spec's own claims.
- Waived: none.

### Layman summary

The error-reporting hole from round 2 is properly closed — I walked it end to end rather than
taking the spec's word: the field is written at run end, read by classification rule 5, rendered as
its own warning line, asserted by a scenario that checks the *emitted line* rather than the parsed
field, guarded by falsifier clause (f), and surfaced in `memsearch status` too. That one is done.

The new finding is the serious one, and it is the same species of trap the spec itself collects in
its "measurement traps" section. **R8 says to delete `CODING_MEMORY.md` from `exclude_paths` — but
the code refuses to start if you do.** `memsearch/memsearch/config.py:56-60` raises `ConfigError`
whenever `exclude_paths` does not contain `CODING_MEMORY.md`, and `cli.py` turns that into exit 1.
So the moment task 6 lands as written, *every* memsearch command — `index`, `query`, `status` — and
the new 6-hourly launchd job all die at config load. Three live tests pin that behaviour
(`test_config.py:40`, `test_config.py:48`, `test_index.py:93`). The spec never mentions `config.py`,
`ConfigError`, validation, or `test_config.py` anywhere — I grepped; zero hits. The diagnostic table
checked that the exclusion *works* (0 chunks, no `sources` row) but not that it is *enforced*, so a
premise that looked verified is the one that breaks. An implementing agent hitting this would have
to invent the resolution — delete the guard, invert it, or weaken it — and that is a decision the
spec should own, especially since the guard was deliberately built as validation rather than
convention.

The second finding is the documentation-drift one from round 2, now half-fixed. The `memsearch/README.md`
half is genuinely closed. But I enumerated every remaining document rather than checking only the
one I named last round, and the highest-authority one is still open: the memsearch design spec at
`docs/superpowers/specs/2026-07-17-memory-rag-index-design.md` asserts the exclusion in five places,
including an entire section headed "What Is NOT Indexed" with the rationale R8 reverses. That file is
itself indexed by memsearch (`~/.claude/docs` is a `curated_docs` root), and `golden_queries.json:4`
routes the query "why is CODING_MEMORY.md excluded" straight to it — so after this lands, the index
answers that question with a rationale that is no longer true. That is precisely the
confident-answer-from-stale-memory failure this whole feature exists to eliminate.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/r8-missing-config-validator` | `skills/writing-specs/SKILL.md` | Requirements the agent can satisfy and you can check; contracts give the real interface boundaries instead of letting the agent improvise — anything left implicit, the agent infers, and inference is where the defects come from | Requirements → R8 / Tasks 6–7 / Contracts | R8 directs removing `CODING_MEMORY.md` from `exclude_paths`, but `memsearch/memsearch/config.py:56-60` raises `ConfigError("exclude_paths must contain CODING_MEMORY.md")` at every `load_config`, so the change as specified makes every `memsearch` command and the new 6-hourly launchd job exit 1; the spec never mentions `config.py`, the validator, or the three tests that pin it (`test_config.py:40`, `test_config.py:48`, `test_index.py:93`), leaving the agent to invent how to reverse a deliberately enforced invariant. |
| 2 | `writing-specs/readme-drift` | `skills/writing-specs/SKILL.md` | Drift causes hallucination — the obligation runs down to `README.md`, updated in the change that makes it wrong, not later | Requirements → R8 / Tasks 6–7 | The `memsearch/README.md` half is now fixed, but R8 equally falsifies `docs/superpowers/specs/2026-07-17-memory-rag-index-design.md` (lines 58, 67, 70, 135 and the "What Is NOT Indexed" section at 154-163, whose "durable vs. ephemeral" rationale R8 reverses) and `docs/superpowers/plans/2026-07-17-memory-rag-index.md:19`, and no task updates either — while `~/.claude/docs` is a `curated_docs` root, so the index will serve that false rationale as the answer to `golden_queries.json:4`. |

### Round-2 violations — one fixed, one persistent

| round-2 id | status | evidence checked this round |
|---|---|---|
| `core-conduct/unsurfaced-run-errors` | **fixed** | Walked end to end: contracts stamp `last_run_errors = len(report["errors"])` at completion and *preserve* the prior value on the entry write (closing the clobber hole); classification rule 5 reads it; R3's degraded line renders `⚠ last run had N errors`; the scenario asserts the emitted line is "not the fresh line"; falsifier (f) covers it; task 4 mandates asserting the line, not the field; `memsearch status` shows it. I also confirmed the honest edge: with Ollama down and no file changed, `_index_one` early-returns as *skipped* before embedding, so zero errors and a fresh line is truthful — and the spec's own "run that changes nothing" scenario covers it. |
| `writing-specs/readme-drift` | **persistent (half-fixed)** | R8 now carries a dedicated README paragraph, task 6 requires the correction "in the same commit" plus documenting `bin/install-schedule`, and a scenario asserts the README no longer claims the exclusion. The design-spec and plan halves are untouched — see violation 2. |

### Notes (non-blocking)

- **Every spec citation I checked is accurate.** `memsearch/README.md:22`, `memsearch/config.json:16`,
  `status.py:27`, `index.py:100` (`_write_status` after the loops), `_index_one`'s catch-and-continue,
  `index.py:125-127`'s unchanged-hash early return, and `cli.py`'s unconditional `return 0` for
  `index` are all exactly as described. The parent spec's Phase 2 list and its acceptance bar
  (k=6, ≥2 hits, ≥0.30, top hit) match R9 verbatim, and parent item 1 does record the exclusion
  rationale as falsified — so R8's *intent* is human-approved and traceable; only its mechanics are
  incomplete.
- **Round-2 note now closed — uninstall.** R7 makes removal first-class with `--uninstall`, a
  no-op-success path, an explicit "never touches `memory-index/`" guarantee, and two scenarios.
- **Task 7 is under-specified.** "Update the golden query for the changed exclusion" does not say
  what it becomes; today's entry asks "why is CODING_MEMORY.md excluded" and expects
  `memory-rag-index-design`. Delete, invert, or re-point are three materially different test suites —
  and the re-point target is the document in violation 2. Held as a note because the direction is
  clear once violation 2 is fixed.
- **Internal consistency is good.** I counted 26 scenarios: 14 nudge, 8 install/uninstall, 4 package
  and measurement — matching task 4's "fourteen nudge scenarios" and task 5's "eight" exactly. The
  six classification rules are mutually consistent with R1–R3 and with every boundary scenario
  (exactly-8h stale, `run_started == last_run`, future timestamps on both fields, first-run-after-upgrade).
- **Round-2's first-run note is now closed.** Rule 1 explicitly reads "`last_run` absent or
  `run_started > last_run`", and a scenario pins the first-run-after-upgrade case to in-progress.
- **Degraded has no floor.** `last_run_errors > 0` warns forever if one source fails persistently —
  the alert-fatigue mode decision 1 argues against for staleness, without the same reasoning applied
  here. Design observation only; fail-loud is a defensible choice for an honesty feature.
- **Rule 3 precedes rule 5.** A run with errors whose `last_run` is unusable reports "age unknown"
  without naming the error count. Not cited: it never claims freshness, so nothing is swallowed.
- **`last_run_errors` has no stated absent/non-numeric handling**, unlike the timestamps, which get an
  explicit usability rule. Low impact — the field is always written alongside `last_run`, and the
  hook's existing `except: print(0)` shape keeps it silent — but one clause would match the rigour
  of the rest.
- **Not cited — version pins.** `plutil` and the Ollama server version are named but unpinned; macOS
  `25.5.0` covers the former and both embedding/digest models are pinned exactly. Neither can lead the
  agent to build the wrong thing.
- **Not cited — spec location.** Unchanged from rounds 1-2: the repo layer (`rules/gates.md`
  one-canonical-file discipline) mandates `docs/features/<name>.md` for a file carrying `phase`
  frontmatter and a task checklist, and the repo layer wins over `writing-specs`' default.
- **Not cited — log file mode.** The plist mode `0644` is specified and justified (launchd refuses
  group/world-writable); `scheduled-index.log`'s mode is not, and it appends without rotation.
  Machine-local, single-user, and the log carries paths and exception text, not content.
- **YAGNI still clean.** The refresh trigger is a user-registered need ("the design deferred this as
  YAGNI and that deferral caused the 18-day drift" — parent item 4); stuck detection is justified by
  the absent lock; `--uninstall` by the agent living outside the repo. Non-goals name the lock gap,
  retry, exit-code contract, parent item 6 and re-measurement cadence. Scope explicitly stops at
  parent item 5. No speculative surface.
- **Security territory is clean.** `install-schedule` runs fixed `launchctl` argument vectors with no
  user-supplied input; the only template substitution is `__HOME__` → `$HOME`, with a scenario
  asserting no absolute path is committed; the scheduled job runs plain `index`, never the
  destructive `--full` that unlinks the db; the nudge still reads a plain JSON file, never invokes
  the CLI, and exits 0 on every path. R8 newly feeds `CODING_MEMORY.md` to a model, but that model is
  local Ollama with no egress and the index already holds `coding-memory/`, `docs/` and transcripts —
  no new class of data leaves the machine.

## Round 4 — 2026-08-06T22:20:34Z

- **Verdict: PASS** (0 violations — both round-3 violations structurally resolved, not reworded)
- head_sha: `51c5dee8734cffd26ee8d9ab4a4cff88c32eb6b6`
- spec_blob_sha: `50ad053a5a11402833614f54d410edcd390d18f8`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (no `.claude/project-standards.md` exists in this repo)
- Confidence: **high** — I re-verified every reachable factual claim in the spec against the live
  machine and source tree rather than accepting the revision account, including all eight pinned
  versions and every code line number cited.
- Waived: none.

### Layman summary

Both blocking findings are gone, and gone the right way. Round 3's problem was one requirement (R8)
that told the builder to delete `CODING_MEMORY.md` from the index's exclusion list — a change the
code physically refuses to accept, because `config.py` raises an error at startup if that entry is
missing. The fix was not to paper over it: the requirement was **dropped**, the exclusion kept, and
the whole thing moved to Non-goals with the reasoning written out — including the honest counterpoint
that the original justification may have expired, recorded for whoever picks it up rather than
quietly assumed either way. That also dissolves the second finding, because there is no longer any
change that falsifies the older design documents. I confirmed the exclusion's three test pins and the
golden query are all still consistent with the spec as it now reads: `test_config.py:42` and `:48`,
`test_index.py:93`, and `golden_queries.json:4`, which asks "why is CODING_MEMORY.md excluded" and
still gets a true answer.

The second thing worth saying plainly: the spec **caught itself lying and said so in writing.** An
earlier draft cited "1h26m over 601 sources" as a measured run duration. It was not a duration — it
was a stopwatch glance at a run that had not finished (the same run was still going at 2h17m over 683
sources). The spec now states the duration is unmeasured, warns that it may exceed the 6-hour stuck
threshold and would then fire a false alarm on a perfectly healthy first run, and hands the constant
to the user once task 8 measures it for real. That is the correct disposal of an unknown under
core-conduct: a stated default, a named trigger, and a human owner — not a guessed number.

I checked the rest for regressions and found none. All eight pinned versions verify exactly on this
machine (`bash` 3.2.57, `python3` 3.9.6, `uv` 0.11.28, `sqlite3` 3.51.0, darwin 25.5.0, and both
Ollama models present); `launchctl getenv PATH` really is empty, which is what makes the plist's
`PATH` key load-bearing rather than boilerplate; every cited line number is right
(`status.py:27`, `db.py:156`, `index.py:100/125-127/135-137`, `cli.py:66`, `README.md:22`,
`plans/2026-07-17-memory-rag-index.md:19`). Scenario counts match the tasks that claim them —
fourteen nudge, eight install/uninstall. Error handling is stated at every boundary the design
introduces, including the ugly ones: a killed run, a mid-write `status.json`, a bootstrap that
reports success while loading nothing. Nothing is speculative, no secret or absolute path is
committed, and the only shell execution runs fixed argument vectors with no user input.

The remaining items below are polish, not blockers. None can lead the agent to build the wrong thing.

### Violations

None.

### Round-3 violations — both fixed

| round-3 id | status | evidence checked this round |
|---|---|---|
| `writing-specs/r8-missing-config-validator` | **fixed** | The requirement was removed, not patched. R8 now carries only the README obligation for `bin/install-schedule`. Parent items 1 and 3 sit in Non-goals citing `config.py:56-59` by name, the three pinning tests, and the plan's "enforced by config validation, not convention" line — all four of which I verified verbatim. Task 6 states affirmatively that `memsearch/config.json` and `README.md:22` are *not* touched. The diagnostic table's rows 1 and 3 now read "Real, but out of scope here" and "Falls with item 1". Nothing in the spec can now trip the validator. |
| `writing-specs/readme-drift` | **fixed** | With the exclusion kept, `docs/superpowers/specs/2026-07-17-memory-rag-index-design.md` and `docs/superpowers/plans/2026-07-17-memory-rag-index.md:19` stay true and need no edit — the drift had no source left. The README half stays closed: R8 requires `memsearch/README.md` to document `install-schedule` **in the same commit that adds it**, task 6 enforces it, and a scenario asserts it. A second scenario now pins the *survival* of the README:22 invariant. I confirmed `golden_queries.json:4` still resolves correctly under the kept exclusion. |

### Notes (non-blocking)

- **Every factual claim I could reach verifies.** Versions: `bash` 3.2.57(1) arm64-apple-darwin25,
  `python3` 3.9.6, `uv` 0.11.28 (Homebrew, `/opt/homebrew/bin`), `sqlite3` 3.51.0, `uname -r` 25.5.0,
  `qwen3-embedding:0.6b` and `qwen3.6:35b-mlx` both present in `ollama list`. Line numbers:
  `config.py:56-59` (the guard), `test_config.py:42,48`, `test_index.py:93`, `status.py:27`,
  `db.py:156`, `index.py:100,125-127,135-137`, `cli.py:66` (`return 0`), `README.md:22`,
  `plans/…:19`, `memory-system-split.spec.md` Phase 2 list. `launchctl getenv PATH` is empty (exit 0,
  no output), `~/.claude/memory-index/reindex.log` exists as described, ADR 0017 exists and 0018 does
  not. After round 3's fabricated measurement I treated verification as the default, not the exception.
- **The data-flow diagram enumerates four of six nudge states.** `OUT` reads
  "fresh · stale · in-progress · unknown" and the edge label says "last_run vs 8h threshold", omitting
  *stuck* and *degraded* and the `RUN_MAX_HOURS` arm. Not cited: R3 and the classification table both
  enumerate all six explicitly with "first match wins", so the authoritative contract is unambiguous
  and the diagram cannot mislead the build. Worth a one-word fix to the node label if the spec is
  touched again for any other reason.
- **Task 3 points at the wrong test file for the `status.py` half.** It names `test_index.py` and
  `test_cli.py`, but `status_report`'s coverage lives in `test_rename_status.py:96`
  (`test_status_report_contents`); `test_cli.py` has only `test_status_without_index`. Not cited: the
  requirement is satisfiable either way, and I confirmed the existing assertions (`chunks: 1`,
  `curated_doc: 1`, model/dim, no `REVISIT`) do **not** pin the `last_indexed` label, so relabelling
  it breaks nothing.
- **The "exclusion survives" scenario has no owning task.** Its three assertions are already pinned by
  the existing suite (`test_config.py:42,48`, `test_index.py:93`, `golden_queries.json:4`), so it
  holds by doing nothing — which is exactly what task 6 says to do. Recorded so a future reader does
  not mistake it for an untested claim.
- **`RUN_MAX_HOURS` is a stated default over an unmeasured quantity.** Deliberate and correctly
  handled — default 6, measurement in task 8, escalation to the user if it lands higher — but it does
  mean the stuck line may fire once on a healthy first run before task 8 closes. The spec says so in
  those words. Not a violation; core-conduct puts that call with the human.
- **`last_run_errors` still has no stated malformed-value rule**, unlike the timestamps, which get an
  explicit usability clause. Carried forward from round 3 at the same low impact: R4's "silent on
  every error path" and the hook's existing catch-all keep it from ever producing a wrong line.
- **Not cited — `plutil` unpinned.** Named in Contracts and task 5 but absent from the toolchain
  table; macOS `25.5.0` is pinned in the same table and `plutil` ships with it, and `-lint` is
  unambiguous. Same disposition as rounds 1-3.
- **Not cited — spec location.** Unchanged from rounds 1-3: the repo layer (`rules/gates.md`
  one-canonical-file discipline, `managing-session-memory`) mandates `docs/features/<name>.md` for a
  file carrying `phase` frontmatter and a task checklist, and the repo layer wins over
  `writing-specs`' `docs/superpowers/specs/` default. The spec's own header also justifies staying
  single-file against ADR 0017 decision 7.
- **Phase discipline is intact.** Frontmatter reads `phase: planning`, `branch: none`, and task 1 is
  the model-switch checkpoint 2 that opens implementation — no branch created, no implementation
  work presumed, consistent with the gate.
- **YAGNI still clean.** Every one of the six nudge states traces to a named failure mode (stuck to
  the absent lock, degraded to the Ollama-down case decision 4 names); `--uninstall` traces to the
  agent living outside the repo where `git revert` cannot reach it. Scope stops at parent item 5, and
  Non-goals now names nine exclusions including the two dropped this round.
- **Error handling covers the unpleasant paths.** A crashed or killed run leaves
  `run_started > last_run` and surfaces as stuck with no recovery attempted (stated); a mid-write
  `status.json` degrades to the silent malformed-JSON path; a `bootstrap` that reports success but
  loads nothing is defined as a failed install with its own verification step and exit code. Four
  distinct install exit codes, each printing the failing step.
- **Security territory is clean, and smaller than last round.** `install-schedule` runs fixed
  `launchctl` argument vectors with no user-supplied input; the only substitution is `__HOME__` →
  `$HOME` at install time, with a scenario asserting no absolute path is committed; the plist is mode
  `0644` and `LaunchAgents` `0755`; the scheduled job runs plain `index`, never the destructive
  `--full` that unlinks the db; the nudge still reads a plain JSON file, never invokes the CLI, and
  exits 0 on every path. Round 3's one new data-exposure surface — feeding `CODING_MEMORY.md` to the
  local model — is gone with R8's old text. No new dependency is introduced.
- **`scheduled-index.log` mode and rotation remain unspecified**, as in round 3. Machine-local,
  single-user, and the log carries paths and exception text rather than content; the spec does
  justify the filename's separation from `reindex.log`.
