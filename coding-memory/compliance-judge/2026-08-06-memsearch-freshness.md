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

---

## Round 1 (new loop) — 2026-08-06T23:44:03Z

Fresh loop. The prior loop reached PASS at its round 4; the user then reversed a decision
(`CODING_MEMORY.md` is now to be indexed) and the spec was materially revised, invalidating that
verdict. Round numbering restarts; prior-loop ids are reused where the violation recurs.

- **Verdict: FAIL** (2 violations)
- head_sha: `3b793fa0df4e2d4d1f0ecb598edf6bc86cc6c567`
- spec_blob_sha: `f8268b53126e8dacd48e4eb37b0478e4a10f83d4`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (no `.claude/project-standards.md` exists in this repo)
- Confidence: **high** — every claim R10 makes about the codebase was opened and read at HEAD;
  the two findings are quoted from the live source tree, not inferred.
- Waived: none.

### Layman summary

R10 is thorough, well-argued, and **not buildable as written**. The argument for the reversal is the
strongest part of the spec: the original exclusion existed because `CODING_MEMORY.md`'s durable
content was "already promoted" into indexed files, and R10 proves with dates that the promotion
stopped three weeks ago. That reasoning holds. What does not hold is R10's map of the code it tells
the builder to edit — three of its pointers are wrong, and one of them is wrong in a way that
destroys something that currently works.

**The golden query is at line 4, not line 2.** The spec says `golden_queries.json:2` three times —
in the diagnostic table, in R10.4, and in task 7 — and instructs the builder to replace that line
because its premise is false. Line 2 is a different, perfectly true query (`"why did we choose
sqlite over qdrant…"`, a `must` query). The falsified one is on line 4. A builder following the
instruction literally deletes a passing acceptance query and leaves the broken one in place. This is
not a guess on my part: **this same file's round-4 entry, written yesterday, cites
`golden_queries.json:4` correctly.** The number got worse in the revision.

**The config guard is at lines 57-60, not 56-59.** Line 56 is
`excludes = tuple(raw.get("exclude_paths", ()))` — a load-bearing assignment consumed twelve lines
later as `exclude_paths=excludes`. R10.2 says "delete the `ConfigError` check in
`config.py:56-59`." Deleting exactly that range removes the `excludes` assignment, leaves the
raise's orphaned closing `)` on line 60, and yields a `SyntaxError` plus an undefined name — so
`load_config` fails for **every** caller, which is precisely the "breaks a caller it does not name"
risk. The spec even adds "`load_config` keeps its other validation unchanged," showing the intent is
right; the coordinates are not.

**"The three pinning tests" undercounts the blast radius to less than half.** The real number is
seven assertions across two files. Four of them are counts that nobody has named: `test_index.py`
asserts `report["processed"] == 4` at line 84 and again at line 135, `== 3` at line 149, and `== 2`
at line 160. The test fixture at `test_index.py:58` writes a `CODING_MEMORY.md` into the corpus
precisely so it can be proved *not* indexed; once the exclusion lifts, that file becomes a fifth
indexable source and **every one of those four numbers is off by exactly one.** The spec gives no
new values, so the builder invents them — and an agent watching `processed == 4` fail has an obvious
wrong fix available (put the exclusion back, or edit the fixture) that would silently defeat the
whole requirement.

Separately, `test_index.py:93` is a *single compound* assertion —
`assert not any("CODING_MEMORY" in p or "subagents" in p for p in all_paths)`. R10.3 says to flip it
to assert inclusion while "**the `subagents/` assertions in both stay exactly as they are**." Both
cannot be true of one line. It has to be split into two assertions, and the spec never says so.

The rest of the revision is genuinely good and I want that on the record. Every *other* code
citation verifies exactly: `config.json:16`, `README.md:22`, `status.py:27`,
`index.py:100/125-127/135-137`, `db.py:121/125/156`, `cli.py:66`, `test_config.py:40-43` and `:46-48`,
the design doc's lines 58, 67, 70, 135 and its 154-163 "What Is NOT Indexed" section, and the plan's
line 19. The evidence for the reversal checks out too — `is_excluded` really is a substring match
(`return any(pat in s for pat in cfg.exclude_paths)`), so the three-repo reach R10 names is real, and
`digest_input_char_cap` really does apply only to `_transcript_chunks`, so the "docs are never
truncated" aside is correct. The three measurement traps are all true of the code as it stands.
The historical `core-conduct/unsurfaced-run-errors` violation stays closed: decision 6, R3's degraded
line, the classification table's row 5, and task 4's "assert the emitted line, not the parsed field"
now form a complete read path for `last_run_errors`.

The second finding is small and cheap: one surviving sentence in a document the change already opens.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/r8-missing-config-validator` | `skills/writing-specs/SKILL.md` | A spec must be "precise enough that the agent has nothing left to guess at"; "anything you leave implicit, the agent infers — and inference is where the defects come from" | Requirements → R10 (parts 2, 3, 4); Diagnostic findings table rows 1 and 3; Tasks → 7 | R10's coordinates into the codebase are wrong in three places, so the reversal cannot be executed as specified: `golden_queries.json:2` is the still-true sqlite-over-qdrant query (the falsified one is line 4), `config.py:56-59` includes the `excludes` assignment whose deletion breaks every `load_config` caller (the guard is 57-60), and "the three pinning tests" omits four `report["processed"]` count assertions (`test_index.py:84,135,149,160`) that each shift by one while `test_index.py:93` is a single compound assertion that cannot both flip and leave its `subagents/` half untouched. |
| 2 | `writing-specs/readme-drift` | `skills/writing-specs/SKILL.md` | "Drift causes hallucination… keeping them aligned is not tidiness; it is correctness" — update the doc in the change that makes it wrong, not later | Requirements → R10 part 5; Scenarios → "Every document asserting the exclusion is corrected in the same commit"; Tasks → 7 | `docs/superpowers/plans/2026-07-17-memory-rag-index.md:2828` still asserts "`CODING_MEMORY.md` and `subagents/` transcripts are never indexed" and is absent from R10.5's list, even though task 7 already edits line 19 of that same file and the file sits inside the indexed `docs/` corpus — so after the change the index itself would answer "is CODING_MEMORY.md indexed?" with the retired invariant. |

### Prior-loop violation ids — recurrence record

| prior id | disposition this round |
|---|---|
| `writing-specs/r8-missing-config-validator` | **recurs** (id reused). Different manifestation, same territory and same rule: the previous loop's R8 was unbuildable because it ignored the `ConfigError` guard entirely; R10 now enumerates that guard correctly in prose but misplaces its line range, misplaces the golden query, and under-counts the test blast radius. The class of defect — the reversal specified against a codebase it has mis-mapped — is the same, which is why the slug is preserved rather than re-minted. |
| `writing-specs/readme-drift` | **recurs** (id reused). The primary surfaces are genuinely fixed — `README.md:22`, the design doc's five sites, and `plan:19` are all named and all verify — but one prose assertion of the retired invariant survives at `plan:2828` in a file the change already opens. |
| `core-conduct/unsurfaced-run-errors` | **stays closed.** `last_run_errors` is written (R5), classified (Contracts row 5), rendered (R3 degraded line), falsified ((f) in the falsifier), and tested against the emitted line rather than the parsed field (task 4). |

### Notes (non-blocking)

- **Not cited — `last_run_errors` has no stated usability rule**, unlike the two timestamps, which
  get an explicit "parses and is not in the future, else treated as absent" clause covering both.
  I nearly cited this under `core-conduct`'s boundary-validation line and decided against it: the
  classification table is first-match-wins and row 3 (`last_run` absent or unusable) fires before
  row 5 ever evaluates `last_run_errors`, and the two fields are written by the same
  `_write_status` call so they co-vary in practice. The residual exposure is a hand-edited or
  partially-written `status.json`, and R4's "silent on every error path" contains it. One sentence
  would close it, and it is the only new boundary field in the spec without a stated rule.
- **Not cited — no scenario for stale ∧ degraded.** The Contracts section states the precedence
  twice ("first match wins", and "Rows 4 and 5 both warn; stale wins when both hold, because its
  remediation is the same and the older signal is the more urgent one"), so nothing is left to
  inference — but it is the one stated precedence rule with no Gherkin behind it, while the
  `STALE_HOURS` boundary gets its own dedicated scenario.
- **Not cited — `RUN_MAX_HOURS` has no exact-threshold scenario.** `STALE_HOURS` has one ("The
  threshold itself counts as stale", pinning both 8h and 7h59m). The stuck scenario uses 9h against
  a 6h default, so the `≥` boundary is unpinned. Asymmetric with its sibling constant.
- **Not cited — `docs/features/memory-system-split.spec.md:33`** records "memsearch sources from
  `CODING_MEMORY.md` | **0** (excluded by config)". That is a point-in-time diagnostic measurement
  in a table of measurements, not an invariant claim, and the same file's line 544 already lists the
  removal as planned Phase-2 work — so it reads as anticipating this change rather than contradicting
  it. Leaving it is defensible; a one-line "superseded by" would remove all doubt.
- **Not cited — the plan's stale code listings.** `plans/2026-07-17-memory-rag-index.md` also
  reproduces the config (152), the `is_excluded` test (211), the guard itself (282-284), the test
  fixture (1484) and the golden query (2942), all of which become historically-accurate-but-current-
  false. These are snapshots of what was built, not prose invariants, and updating them would be the
  drive-by cleanup core-conduct warns against. Only line 2828 is a prose invariant claim, which is
  why it alone is cited.
- **Task 9's duration measurement is correctly ordered but arrives late.** It records the real
  wall-clock run duration and escalates to the user if it exceeds `RUN_MAX_HOURS` — but it runs
  *after* task 4 ships the stuck line, so a healthy first full run can fire a false stuck warning in
  the window between them. The spec states this in R3 in those words and hands the constant to the
  user, which is the correct disposal under core-conduct. Recorded, not charged.
- **YAGNI remains clean and the reversal does not breach it.** R10 is user-directed, not
  agent-invented, and its scope is explicitly bounded — Non-goals now names re-scoping *what* of the
  file gets indexed, and defers it to R9's measurement rather than guessing. The "three repos,
  deliberately" paragraph converts a substring-matching side effect into a stated decision, which is
  exactly the right treatment.
- **Architecture trade-offs stay human-owned.** `RUN_MAX_HOURS` goes back to the user if measurement
  contradicts it; ADR 0018 covers the `launchd` daemon and the run-vs-content recency split; ADR 0019
  covers the reversal with the options weighed (delete / invert / weaken the guard). R10's insistence
  that the guard be **deleted rather than inverted** — "a guard pinning a retired rule is worse than
  no guard" — is sound and correctly reasoned.
- **Security territory is clean.** `install-schedule` runs fixed `launchctl` argument vectors with no
  user-supplied input; the only substitution is `__HOME__` → `$HOME` at install time, with a scenario
  asserting no absolute path is committed; the plist is mode `0644` (justified — `launchd` refuses a
  group- or world-writable plist) and `LaunchAgents` `0755`; the scheduled job runs plain `index`,
  never the destructive `--full`. The nudge still reads a plain JSON file, never invokes the CLI, and
  exits 0 on every path. Indexing `CODING_MEMORY.md` does feed session narrative to the local embed
  and digest models — but `chunk_doc`, not `_transcript_chunks`, handles docs, both models are local
  Ollama with `:cloud` refused at config load, and the corpus never leaves the machine. No new
  dependency is introduced.
- **Not cited — spec location.** Unchanged from the prior loop: the repo layer (`rules/gates.md`
  one-canonical-file discipline, `managing-session-memory`) mandates `docs/features/<name>.md` for a
  file carrying `phase` frontmatter and a task checklist, and the repo layer wins over
  `writing-specs`' `docs/superpowers/specs/` default.
- **Not cited — `plutil` unpinned.** Same disposition as every prior round: macOS `25.5.0` is pinned
  in the same table, `plutil` ships with it, and `-lint` is unambiguous.
- **Phase discipline intact.** Frontmatter still reads `phase: planning`, `branch: none`, and task 1
  is the model-switch checkpoint that opens implementation. Task renumbering to 7-11 is internally
  consistent: task 8 correctly depends on task 7 ("so the queries are written against the corpus they
  will be scored on"), and task 10 correctly forbids re-excluding the file if R9 fails.

---

## Round 2 (new loop) — 2026-08-07T02:22:37Z

- **Verdict: FAIL** (2 violations)
- head_sha: `d48513d3f9de0d94b0ab29c1da0815262649c1af`
- spec_blob_sha: `68bb8fb23c507b0a24b0790e440a561753cb83d5`
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (still no `.claude/project-standards.md` in this repo — repo layer is `CLAUDE.md` + `rules/`)
- Confidence: **high** — every coordinate in R10 was opened and read; the R10 mechanism claim was
  re-measured against `memory.db` directly.
- Waived: none.

### Layman summary

Both of last round's findings are genuinely fixed, and the revision went further than the finding
required. I checked every number in R10 against the actual files rather than trusting the spec:
`config.py` line 56 really is the `excludes = ...` assignment that must survive and the guard really
is 57–60; the golden query about the exclusion really is line 4 and line 2 really is the still-true
sqlite-over-qdrant query; the four `processed` counts at `test_index.py` 84/135/149/160 really would
each shift by one; line 93 really is a single compound assertion that cannot both flip and stay put;
and the plan really does assert the retired invariant at both line 19 and line 2828, both of which
are now listed. The extra defect the main agent found on its own is real and important — I ran the
database query myself: `~/.claude/CODING_MEMORY.md`, `CLAUDE.md` and `MEMORY.md` all have **zero**
rows while `PORTS.md` has one, which proves the `~/.claude` root is not walked and that deleting the
exclusion alone would have changed nothing. Other spot checks all held: the two project copies are
exactly 159 and 119 lines, the largest currently indexed doc is exactly 130 chunks, `launchctl getenv
PATH` really is empty, there really is no lock or pidfile anywhere in the package, and ADR numbers
0018/0019 are free (0017 is the highest).

What is still open is one small area the revision did not touch: the **new write to `status.json` at
the start of a run**. In plain terms, the indexer is now being asked to open its own status file
before it starts work, keep two fields out of it, and write it back — but the spec never says what to
do when that file is damaged, and never says what the other six fields should say at that moment.
Two concrete consequences. First, `status.json` is written in one non-atomic shot, and this spec
expects runs to get hard-killed (it says so twice), so a truncated file is a realistic state; if the
indexer just parses it, every scheduled run dies at the first line, and the session nudge is
contractually silent about a malformed file — the index would freeze again with nobody saying so,
which is the exact defect this feature exists to end. Second, on a `memsearch index --full` the
database is deleted *before* the connection is opened, so if the start-of-run write recomputes its
numbers from the database (which is what "`_write_status` gains a parameter distinguishing the two
calls" implies), it will record `chunks: 0`, and the nudge's untouched "0 chunks means stay quiet"
rule then removes the memsearch line entirely for the whole rebuild — precisely when the
"index run in progress" line was supposed to appear.

Neither is hard to close: one paragraph in the `index.py` contract saying an unreadable prior
`status.json` is treated as absent and never aborts the run, and saying whether the entry write
carries the six existing keys over from the prior file or recomputes them (with the `--full` case
named), plus a scenario or two.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Handle errors explicitly, never swallow them; validate all input at system boundaries and fail closed on any validation failure | Contracts → `memsearch/memsearch/index.py` — `_write_status` / `run_index` (the entry write); R5 | The entry write must "preserve the prior `last_run` and `last_run_errors`", which forces `run_index` to read back a `status.json` this same spec elsewhere treats as possibly malformed (R2; Scenario "Malformed status.json stays silent") and which is written in one non-atomic `write_text` by a process the spec twice expects to be hard-killed, yet the behaviour on an unreadable or truncated prior file is nowhere stated — so one torn write can abort every scheduled run at entry while the nudge stays silent by contract. |
| 2 | `writing-specs/edge-cases` | `skills/writing-specs/SKILL.md` | State what correct looks like, what wrong looks like, and enumerate the edges — anything left implicit the agent infers, and inference is where the defects come from | Contracts → `memsearch/memsearch/index.py` — `_write_status` / `run_index`; R5; Scenarios | The spec never says whether the entry write recomputes the six existing keys from the just-connected DB or carries them over from the prior file, and under the reading its own wording favours (`_write_status` "gains a parameter distinguishing the two calls", so `dbmod.stats` runs again) an `index --full` — which unlinks the DB at `index.py:73` *before* `connect` at `:74` — stamps `chunks: 0`, whereupon the nudge's unchanged "`chunks` absent or 0 → exit 0 silently" rule deletes the session line for the entire multi-hour rebuild, contradicting both R3's in-progress line and the claim that `chunks` is "unchanged in name, meaning, and format". |

### Round-1 violations — both fixed, verified line by line

- `writing-specs/r8-missing-config-validator` — **fixed, and over-delivered.** Verified in the tree:
  `config.py:56` is `excludes = tuple(raw.get("exclude_paths", ()))` and `57-60` is the `if not
  any(...)` / `raise ConfigError(...)` guard — R10.2 and task 7 now state both, including "line 56
  must survive". `golden_queries.json:4` is the `"why is CODING_MEMORY.md excluded..."` query and
  `:2` is `"why did we choose sqlite over qdrant..."` — R10.5 now names line 4 and explicitly warns
  off line 2. `test_index.py` `processed` assertions exist at 84 (`== 4`), 135 (`== 4`), 149 (`== 3`)
  and 160 (`== 2`), each of which rises by one once the fixture's curated `CODING_MEMORY.md` becomes
  indexable (the fixture writes it at `:58` into `coding-memory/`, which `make_cfg` lists as the sole
  `curated_docs` entry); `:105` (`== 0`) and `:117` (`== 1`) correctly stay put and are not listed.
  `test_index.py:93` is indeed the single compound `assert not any("CODING_MEMORY" in p or "subagents"
  in p ...)`, and R10.4 now requires it split. The revision's own extra finding is confirmed
  independently: `sqlite3` over `memory.db` returns 0 sources rows for `~/.claude/CLAUDE.md`,
  `~/.claude/MEMORY.md` and any `CODING_MEMORY.md`, and 1 for `PORTS.md` — the `~/.claude` root is
  not walked, so R10's `curated_docs` addition is genuinely load-bearing, and the "Lifting the
  exclusion alone does not reach the archive" scenario is the right guard for it. Also checked: the
  test helper `write_cfg` derives from the real `config.json`, so R10.1's `"archive_doc": 1.0` weight
  automatically reaches every fixture and `index.py:88`'s `cfg.weights[st]` cannot `KeyError`.
- `writing-specs/readme-drift` — **fixed.** `docs/superpowers/plans/2026-07-17-memory-rag-index.md`
  asserts the invariant at `:19` ("Enforced by config validation, not convention") and `:2828`
  ("`CODING_MEMORY.md` and `subagents/` transcripts are never indexed", inside the plan's embedded
  README block); R10.6 now names **both**, with the reason. Design-doc coordinates re-verified: `:58`
  (ASCII architecture diagram), `:67` and `:70` (the excluded Mermaid node and its `NOT indexed`
  edge), `:135`, and the `154-163` "What Is NOT Indexed" block — all five present and all listed.
  `memsearch/README.md:22` verified and covered by R8.

### Notes (non-blocking)

- **R10.4's fixture instruction is resolvable but not self-evident.** "The fixture at
  `test_index.py:58` ... must additionally cover a file at the `~/.claude` root position" reads as an
  edit to the shared `setup_corpus`/`make_cfg` pair used by all four counted tests; if the root file
  were also added to that shared `curated_docs`, the four `processed` counts would rise by **two**,
  not the "+1 each" R10.4 and task 7 both state. It is resolvable inside the document — the "+1 each"
  arithmetic and the paired scenarios (one *with* the `curated_docs` entry, one *without*) together
  force a separate cfg variant for the root-position test — so this is recorded as residual
  imprecision rather than cited. A half-sentence ("in its own cfg variant; the shared fixture's
  counts move by one") would remove the last guess.
- **R9's five measurement queries have no stated home.** Task 8 commits them "as their own commit"
  and falsifier (d) depends on them being a diffable committed artifact, but no path or format is
  given, and the R9 bar (≥2 hits, each ≥0.30, top hit) is not expressible in the existing
  `golden_queries.json` schema. Low defect risk (any committed file satisfies it), so not cited.
- **R3's "whatever its age" reads unconditionally**, while the classification table makes stale
  (row 4) beat degraded (row 5). The table plus its explanatory note is authoritative and explicit,
  so an implementer has a definite answer; the R3 prose is just looser than the contract.
- **Plan-file residue is historical, not live.** Beyond lines 19 and 2828, the plan still mentions
  `CODING_MEMORY` at 41, 152, 205, 211, 282-284, 318, 1484, 1519 and 2890 — but those are code and
  test listings and a completed verification step inside a finished implementation plan, i.e. a
  record of what was built, not an assertion of a current rule. Line 2890 (a sample query "why is
  `CODING_MEMORY.md` excluded from the index") is the closest call and would be worth a look during
  task 7, but rewriting a historical plan's code blocks is not what the drift rule asks for.
- **Every remaining factual claim I could check held.** No lock/pidfile anywhere in
  `memsearch/memsearch/` (decision 5 stands); `digest_input_char_cap` is used only in `digest.py:51`
  and `eval.py:57`, both transcript paths, so R10's "docs are never truncated by it" is right;
  largest indexed doc is exactly 130 chunks; project copies are exactly 159 and 119 lines;
  `launchctl getenv PATH` returns empty; `bin/memsearch` is the one-line `exec uv run --project`
  wrapper, so the plist's `PATH` key really is load-bearing; `status.json` carries exactly the six
  keys the spec lists, with `+00:00` offsets; `session-log.md` ends 2026-07-16 and `decisions.md`
  2026-07-19, confirming promotion stopped; `docs/decisions/` tops out at 0017, so 0018/0019 are
  free; the plan is 3,079 lines as stated; the nudge is registered under `SessionStart` at
  `settings.json:71`. `docs/features/` now returns 11 sources rows, independently confirming
  diagnostic row 2's "no-op — nothing to add".
- **Measurement drift, expected and harmless.** `CODING_MEMORY.md` now reads 3,291 lines / 289,075
  characters against the spec's 3,232 / 285,187 "measured 2026-08-06". That is one day of appends to
  an append-only archive, and the spec dates its measurement; the "single largest source, ~2.5× the
  largest indexed doc" conclusion is unaffected.
- **Security territory still clean.** No new dependency; `install-schedule` runs fixed `launchctl`
  argument vectors with only `__HOME__` → `$HOME` substituted; the plist is mode `0644` (justified)
  and `LaunchAgents` `0755`; the scheduled job runs plain `index`, never `--full`; the nudge still
  reads a plain JSON file, never the CLI, and exits 0 on every path. Indexing `CODING_MEMORY.md`
  creates no new exposure — the file is already committed, `chunk_doc` (not the digest model) handles
  docs, and both models are local Ollama with `:cloud` refused at config load.
- **Not cited — `/opt/homebrew/bin` in the plist `PATH`.** It is an absolute, Apple-Silicon-specific
  path in a committed template, but `launchd` execs without a shell, the spec pins macOS 25.5.0 and
  `uv` 0.11.28 (Homebrew) in the same table, and the path is not user-identifying. The supply-chain
  invariant's target — a hard-coded `$HOME` — is correctly placeholdered and has its own scenario.
- **Not cited — log hygiene.** `scheduled-index.log` has no stated mode or rotation and appends
  forever; same disposition as prior rounds.
- **Not cited — spec location.** Unchanged: `rules/gates.md`'s one-canonical-file discipline mandates
  `docs/features/<name>.md` for a file carrying `phase` frontmatter and a checklist, and the repo
  layer wins over `writing-specs`' `docs/superpowers/specs/` default.
- **YAGNI and scope discipline remain exemplary.** Scope still ends at parent item 5 with item 6
  excluded for a stated reason, eight non-goals are named, and the `RUN_MAX_HOURS` reference point is
  correctly escalated to the user (task 9) rather than quietly widened — the "architecture trade-offs
  stay human-owned" invariant handled exactly right.
- **Phase discipline intact.** Frontmatter still `phase: planning`, `branch: none`; task 1 is the
  model-switch checkpoint that opens implementation.

## Round 3 (new loop) — 2026-08-07T02:52:54Z

- **Verdict: FAIL** (3 violations)
- head_sha: `24e6e29e0a37ccfcf484f85518787c9fecf02b67`
- spec_blob_sha: `391c4cba3bda6f6203e6187eece8b620431e74b3` (re-hashed; matches the caller's value)
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (still no `.claude/project-standards.md` in this repo — repo layer is `CLAUDE.md` + `rules/`)
- Confidence: **high** — every finding was verified against the tree, and the headline one was
  proved by *applying* R10 to a throwaway copy of the package in `/tmp` and running the suite.
- Waived: none.

### Layman summary

Both of last round's findings are properly closed, and the six edits are good ones — the atomic
`os.replace` addition in particular fixes the cause of the very torn file the new rule has to absorb,
which is the right instinct. I re-checked every coordinate again and they all hold: `config.py:56` is
the assignment that must survive and `57-60` is the guard, `golden_queries.json` line 4 really is the
falsified-premise query and line 2 the still-true one, `index.py:73` really unlinks before `:74`
connects, `db.py:112-120` really is the only delete path, and `pyproject.toml:23` really does hide the
golden tests — I confirmed it by running the suite and watching **16 deselected**, exactly matching
task 10's "sixteen golden tests".

Three things are still wrong, and the first two are in the same small area the revision just touched.

**One.** R10 tells the implementer, in bold, that four test assertions will each shift by one and
names them so the implementer doesn't hit "four unexplained failures". I copied `memsearch` to `/tmp`,
made exactly the change R10 describes (dropped the exclusion, added the weight, deleted the guard,
classified by filename), and ran the suite. It produced **seven** failures, not six — the extra one is
`test_index.py:106`, `assert report2["skipped"] == 4`, which becomes 5 for precisely the same reason
the four `processed` counts do. That line is unnamed, and last round's writeup specifically checked
its neighbours 105 and 117 and cleared them, so the miss has now survived two reviews. The class of
finding — "when review rounds keep finding new instances of one class, stop patching and enumerate" —
is exactly the one that warrants a mechanical check rather than another reading.

**Two.** Edit 3 fixed R10.4 to say the root-position test must live in its own config variant, *not*
by extending the shared fixture — with the correct reason, that a second file in the shared fixture
shifts the counts by two rather than one. But task 7, the list an implementer actually works from,
still says "extend the fixture at `test_index.py:58` to cover the `~/.claude`-root position", in the
same sentence as the +1 counts. Two instructions, opposite directions; the one in the task list is
the one that gets followed, and following it breaks the counts the same task states.

**Three.** The contract pins the timestamp expression as `datetime.now(timezone.utc).isoformat()` and
shows `2026-08-06T20:01:40+00:00` as its output, claiming it matches the existing `last_indexed`.
Run on this machine's `python3` it emits `2026-08-07T02:56:16.979370+00:00` — microseconds. The
existing format has none, because `db.py:103` uses `isoformat(timespec="seconds")`, and the live
`status.json` reads `2026-08-06T23:56:46+00:00`. Parsing still works, so nothing breaks at runtime,
but R5's "matching the existing `last_indexed` format" is false as written and a test built from the
documented example would assert a shape the pinned expression never emits. One word (`timespec=
"seconds"`) settles it.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/edge-cases-r10-test-counts` | `skills/writing-specs/SKILL.md` | Good, bad, and edge-case scenarios: state what correct looks like, what wrong looks like, and enumerate the edges — anything left implicit the agent infers, and inference is where the defects come from | R10.4 (the `report["processed"]` count bullet); Tasks → task 7 | The enumeration asserts its own completeness ("six changes, not three"; "Named because a literal implementer will otherwise see four unexplained failures") but omits `test_index.py:106`'s `assert report2["skipped"] == 4`, which rises to 5 for the identical reason the four `processed` counts do — applying R10 to a scratch copy of the package yields five failures in `test_index.py` and seven suite-wide, so the implementer meets one unexplained failure in the file the spec promised to have fully mapped. |
| 2 | `writing-specs/contradictory-requirement` | `skills/writing-specs/SKILL.md` | Requirements must be precise enough that the agent has nothing left to guess at; ambiguity the structure exposes is a decision not yet made | R10.4 (fixture bullet) vs Tasks → task 7 | R10.4 now requires the root-position case "in its own `cfg` variant, **not by extending the shared fixture**" and gives the reason (extending it shifts each `processed` count by two, not one), while task 7 still instructs "extend the fixture at `test_index.py:58` to cover the `~/.claude`-root position" in the same sentence as the +1 counts — so the task list, which is what an implementer executes, prescribes exactly the action R10.4 was revised to forbid and would break the counts it states. |
| 3 | `writing-specs/timestamp-format-contract` | `skills/writing-specs/SKILL.md` | Database schemas and API contracts give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes other components then fail to match | Contracts → `memsearch/memsearch/index.py` (Timestamps bullet); R5 | The pinned expression `datetime.now(timezone.utc).isoformat()` emits microseconds (verified: `2026-08-07T02:56:16.979370+00:00`), so it produces neither the second-precision example the same bullet gives nor R5's promised match with the existing `last_indexed` — which comes from `db.py:103`'s `isoformat(timespec="seconds")` and reads `2026-08-06T23:56:46+00:00` in the live `status.json` — leaving the format of the two fields the whole staleness math parses stated three mutually inconsistent ways. |

### Round-2 violations — both fixed, verified against the tree

- `core-conduct/explicit-error-handling` — **fixed.** The Contracts section now states the entry
  write's read of the prior file is "fallible by design and never aborts the run": `OSError` and
  `JSONDecodeError` are caught, a bad file is treated as an empty object, the condition is reported
  as one line on stderr (landing in `scheduled-index.log`, R6) and never raised. It goes further than
  the finding asked by making **both** writes atomic (temp file + `os.replace` in `db_path.parent`),
  which closes the hole that produces the torn file rather than only absorbing it — `index.py:67` is
  indeed a single non-atomic `write_text` today, so the diagnosis is correct. The downstream
  consequence is stated rather than smoothed over ("with `chunks` absent the nudge stays silent for
  that run"), and Scenarios "An unreadable status.json does not abort the run" and "A status.json
  write survives a kill mid-write" cover both paths. Not re-cited.
- `writing-specs/edge-cases` — **fixed.** The spec now says explicitly that the entry write "carries
  those six keys over from the prior file; it does not recompute them", with the correct mechanism:
  verified in the tree that `_write_status` derives all six from `dbmod.stats(conn)`
  (`index.py:57-67`) and that `--full` unlinks at `index.py:73` *before* the connect at `:74`, so a
  recompute would have stamped `chunks: 0`. Scenario "A full rebuild's entry write does not zero the
  chunk count" pins it. **Note for persistence detection:** this round's violation 1 is also an
  enumeration finding, but it is a *different* territory (R10's test-change list, not the entry
  write) and is therefore filed under a new id — it must not be read as `writing-specs/edge-cases`
  recurring.

### Notes — what was checked and held

- **Every file:line citation re-verified, and all of them are exact.** `config.py:56` /`57-60`;
  `index.py:44-51`, `57-67`, `:67`, `:73`, `:74`, `:100`, `:125-127`, `:135-137`; `db.py:16`,
  `112-120`, `121,125`, `:156`; `status.py:27`; `cli.py:66`; `pyproject.toml:23`;
  `golden_queries.json` lines 2 and 4; `test_config.py:42,48`; `test_index.py:58,84,93,135,149,160`;
  `memsearch/README.md:22`; the design doc at 58, 67, 70, 135 and 154-163; the plan at both 19 and
  2828 with 3,079 lines total; `memory-system-split.spec.md:540`. `docs/decisions/` tops out at 0017,
  so 0018/0019 are free.
- **Task 10's premise confirmed by execution.** A bare `uv run pytest` reports "16 deselected",
  matching the spec's "sixteen golden tests" exactly — the `-m golden` instruction is load-bearing
  and correctly stated.
- **The scenario counts in tasks 4 and 5 are right.** Fourteen nudge-facing scenarios and eight
  install/uninstall scenarios, counted in the Scenarios block.
- **R10.3's mechanism is sound, not just plausible.** `index.py:88` looks the weight up as
  `cfg.weights[st]` where `st` comes straight from `_iter_docs`, so classifying by filename really
  does apply `archive_doc: 1.0` — no second edit needed. Confirmed by the scratch-copy run, in which
  the classification took effect without touching `chunk_doc`.
- **Toolchain table re-verified live, every row.** `bash` 3.2.57 with no `timeout` binary on PATH,
  `python3` 3.9.6 which parses `+00:00` and rejects `Z` (both confirmed by execution), `uv` 0.11.28
  at `/opt/homebrew/bin`, `sqlite3` 3.51.0, macOS 25.5.0, `bin/memsearch` a one-line
  `exec uv run --project`. `launchctl getenv PATH` returns empty, so the plist `PATH` key is as
  load-bearing as claimed.
- **Measurement drift, expected and harmless.** `CODING_MEMORY.md` now reads 3,364 lines / 294,558
  characters against the spec's dated 3,232 / 285,187, and `sources` at `2026-07-18` is now 187 rows
  against the stated 196 (the rebuild keeps migrating rows to today, 724 of them). Both are moving
  targets the spec labels as such, and neither disturbs a conclusion.
- **One understatement, not a violation.** R10 says the file "carries sessions **24 through 30**";
  it actually carries session-numbered entries from session 20 (line 2601) onward, so the
  three-week retrieval hole is larger than claimed, not smaller.
- **Security territory clean.** No new dependency; the template commits `__HOME__` only and has a
  scenario asserting it; `install-schedule` runs fixed `launchctl` argument vectors; plist `0644`,
  `LaunchAgents` `0755`; the nudge still reads a plain JSON file, never the CLI, and exits 0 on every
  path. The new atomic write lands in `db_path.parent`, not a shared tmp — no symlink-swap surface.
- **Not cited, unchanged dispositions from prior rounds.** `/opt/homebrew/bin` in the plist `PATH`;
  `scheduled-index.log` having no stated mode or rotation; the spec living at `docs/features/` rather
  than `docs/superpowers/specs/` (gates.md's one-canonical-file discipline governs a file carrying
  `phase` frontmatter and a checklist, and the repo layer wins).
- **YAGNI, scope, and phase discipline still exemplary.** Scope ends at parent item 5; eight
  non-goals named; `RUN_MAX_HOURS` correctly escalated to the user (task 9, now timing the cold
  `--full` run — the right worst case, since `RUN_MAX_HOURS` must survive the longest run the
  scheduler can start); R10's exit cost (no prune path, verified: `db.py` deletes only at 117 and 120
  inside `replace_source`) now stated up front. Frontmatter remains `phase: planning`, `branch: none`.

## Round 4 (new loop) — 2026-08-07T03:40:45Z

- **Verdict: FAIL** (4 violations — all **new**; all three round-3 violations verified **closed**
  against the live tree, none re-cited)
- head_sha: `24e6e29e0a37ccfcf484f85518787c9fecf02b67`
- spec_blob_sha: `7266fea3231dc030095ae43957e63cfded9fd489` (re-hashed; matches the invocation)
- Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, `rules/gates.md`, `CLAUDE.md`
  (no `.claude/project-standards.md` exists in this repo)
- Confidence: **high** — every finding was read out of the live source or reproduced by running the
  command the spec names, not inferred from the spec's own account of itself.
- Waived: none.

### Layman summary

**The three things you directed be fixed are genuinely fixed, and I checked each by hand rather
than by reading the revision notes.** The missing `skipped` count is now derived from a stated rule
instead of a list, and I applied that rule to all nine count assertions in `test_index.py`: the five
the spec says move do move, the four it says stay do stay, and "seven failures suite-wide" is exactly
right (five test functions in `test_index.py`, two in `test_config.py`). The fixture contradiction is
gone — task 7 and R10.4 now both say the same thing. The timestamp is right, and I proved it by
running Python 3.9.6 on this machine: a bare `isoformat()` really does emit microseconds, the pinned
`timespec="seconds"` form matches `db.py:103`, and it matches the live `status.json`
(`2026-08-06T23:56:46+00:00`) character for character.

**The three design gaps you folded in are well built.** The decay rule closes a real hole — a dead
scheduler now reads as *stale* with working remediation instead of "stuck" forever — and it is
carried through the table, the falsifier and a scenario. The error-count robustness rule is right,
and the archive-retrieval fix is the sharpest catch in the revision: I confirmed at `chunk.py:111`
that archive chunks really would have landed in the generic `doc` bucket and been invisible to
`--type episodic`, and that `RECALL_TYPES` already contains `episodic` with no `CHECK` on the
column, so "no migration needed" is true.

**What blocks: two of them can make the builder do the wrong thing; two are wrong numbers.**

The first blocker is a **swapped label** in the same paragraph that has now been wrong three rounds
running. The spec names `test_index.py:117` as "limit-scoped" and puts it in the *do-not-move* list.
Line 117 is not the limit test — it is `test_changed_file_reindexes_only_itself`. The limit-scoped
assertion is at `:149`, which the very same paragraph lists as one that **must** move. So the spec
says both "the limit-scoped assertion moves" and "the limit-scoped assertion doesn't move", in a
paragraph whose stated purpose is to stop an implementer touching the wrong line. The same list also
names the stale comments at `:84` and `:160` but misses the equally stale ones at `:135` and `:148`.

The second blocker is a **contradiction the new rule introduced and nobody swept for**. Adding the
"unreadable error count" state means an absent `last_run_errors` must render a ⚠ line, never a fresh
one — correct, and the spec argues it well. But three existing scenarios still say the line is
*fresh* from a starting state that never mentions `last_run_errors` at all: the run-that-changed-
nothing scenario, the "7 hours 59 minutes" branch, and the future-`run_started` scenario. Task 4
tells the builder to write one test per scenario, so they will write a test that the classification
table says must fail. One word per scenario fixes it.

The two remaining findings are wrong numbers that cannot misdirect the build but should not go to
you uncorrected. R3 still says "**Three** states beyond fresh/stale/unknown" and then lists four.
And R10.6 says the plan sweep "returns **eleven** hits" — I ran the exact command the spec
prescribes on the unmodified file and got **14** (10 if you match `CODING_MEMORY.md` with the
extension). The four lines it names as asserting the retired rule are all correct; only the total
is wrong.

Worth saying plainly: this is now the third consecutive round where a *counted enumeration* in this
spec fails to reproduce, while every *line-number citation* I checked was right. The pattern points
at the counts, not at the analysis. Rather than patch these two numbers, the cheap fix is one
mechanical sweep — recount the states, recount the sweep hits, and grep the Scenarios block for
every "fresh" and pin `last_run_errors` in each.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/edge-cases-r10-test-counts` | `skills/writing-specs/SKILL.md` | Good, bad and edge cases stated explicitly and enumerated — anything left implicit the agent infers, and inference is where the defects come from | R10 → part 4 (The tests) / Task 7 | Round 3's omitted `skipped` assertion is closed, but the same enumeration now mislabels `test_index.py:117` as "limit-scoped" when it is `test_changed_file_reindexes_only_itself`'s `processed == 1` — the limit-scoped assertion is `:149`, which the same paragraph lists as one that *must* move — so the do-move and do-not-move lists assert opposite things about "the limit-scoped assertion", and the list of stale inline comments names `:84` and `:160` while omitting the equally stale ones at `:135` and `:148`. |
| 2 | `writing-specs/fresh-scenarios-error-count` | `skills/writing-specs/SKILL.md` | Force State → Action → Outcome; a requirement you cannot phrase unambiguously as Given/When/Then is one you have not decided — and no requirement may be readable two ways | Scenarios ("A successful run that changes nothing…", "The threshold itself counts as stale", "A future run_started is not a run in progress") vs. R3 / Contracts classification row 5 | The new *unreadable error count* rule makes an absent `last_run_errors` render a ⚠ line and explicitly "not the fresh line", yet three scenarios assert `Then the line is fresh` from a Given that never pins `last_run_errors`, so the Scenarios block and the classification table demand opposite outcomes for the same input — and task 4 requires a hook test per scenario, forcing the implementer to guess which one wins. |
| 3 | `writing-specs/r3-state-count` | `skills/writing-specs/SKILL.md` | Maintain the spec with production rigor; requirements the agent can satisfy and you can check (with `rules/core-conduct.md` — verify your own outputs before calling something done) | Requirements → R3 (lead sentence) | R3 announces "Three states beyond fresh/stale/unknown, each with its own line" and then enumerates four such states — in progress, stuck, degraded, and the newly added unreadable error count — so the requirement's own count contradicts the list beneath it, in a spec that elsewhere (task 4) warns that "a number written here … drifts". |
| 4 | `writing-specs/plan-sweep-hit-count` | `rules/core-conduct.md` | Verify your own outputs before calling something done; debug from evidence, not symptoms | R10 → part 6 (The documents that assert the opposite) | R10.6 states as a dated measurement that "the sweep on 2026-08-06 returns eleven hits", but running the exact command it prescribes — `grep -n CODING_MEMORY docs/superpowers/plans/2026-07-17-memory-rag-index.md` — returns **14** on a file unmodified since 2026-07-17 (10 if matched as `CODING_MEMORY.md`), so the figure the paragraph's own "hand lists have been wrong twice" argument rests on is itself wrong, leaving the implementer three untriaged hits beyond the seven the spec accounts for. |

### Round-3 violations — all three fixed, verified against the tree

| round-3 id | status | evidence checked this round |
|---|---|---|
| `writing-specs/edge-cases-r10-test-counts` | **fixed as cited** (new defects in the same paragraph — see violation 1) | The generative rule is stated and I applied it independently to every count assertion in `test_index.py`. The five named as moving are correct: `:84` (4→5), `:106` `skipped` (4→5, the round-3 omission, now present), `:135` (4→5), `:149` (3→4), `:160` (2→3). The four named as static are correct: `:105` (`processed == 0` on a no-change run), `:117` (only the changed file reprocesses), `:136` (`skipped == 0` under `--full`), `:161` (error count). "Seven failures suite-wide" is exact — those five assertions live in five distinct test functions, plus `test_config.py`'s two. I also confirmed the mechanism: `make_cfg` (`test_index.py:65-74`) overrides `curated_docs` but inherits `exclude_paths` and `weights` from the real `config.json`, so lifting the exclusion really does make the fixture's `curated/CODING_MEMORY.md` a fifth source and `archive_doc: 1.0` really must land in the real config. |
| `writing-specs/contradictory-requirement` | **fixed** | Task 7 now reads "cover the `~/.claude`-root position in **its own `cfg` variant, leaving the shared fixture at `test_index.py:58` untouched**", matching R10.4 word for word. The prescription that contradicted R10.4 is gone; the two-sided assertion (a `sources` row when `curated_docs` names it, none when it does not) survives in both places and in two scenarios. |
| `writing-specs/timestamp-format-contract` | **fixed, proven by execution** | Ran on this machine's `python3` 3.9.6: bare `isoformat()` → `2026-08-07T03:45:43.454967+00:00` (microseconds, as the spec now warns); `fromisoformat('2026-08-06T20:01:40+00:00')` parses; `…Z` raises. `db.py:103` is `datetime.now(timezone.utc).isoformat(timespec="seconds")`, and the live `memory-index/status.json` carries `"last_indexed": "2026-08-06T23:56:46+00:00"` — so the pinned form, R5's "second precision" wording, and the existing field now agree exactly. |

### Notes (non-blocking)

- **The archive-retrieval catch is correct at the source level, not merely plausible.**
  `chunk.py:111` is verbatim `recall = "decision" if "decisions" in str(path) else "doc"`;
  `chunk_doc`'s signature already takes `source_type`; `chunk.py:141` is the digest path's
  `else "episodic"`; `RECALL_TYPES` at `db.py:17` is `("decision", "episodic", "doc")`; and the
  schema line (`db.py:72`) declares `recall_type TEXT NOT NULL` with **no** `CHECK`. Every clause of
  R10.3's one-line-fix claim holds, including "no migration is needed".
- **The decay rule is carried all the way through.** R3's decay bullet, the table's rows 1–2 bound
  by `RUN_ABANDON_HOURS`, the "unusable" note under the table, falsifier clauses (c) and (g), and a
  dedicated scenario all agree. Traced the 30-hour case by hand: `run_started` unusable → rows 1–2
  skip → `last_run` usable and 30h old → row 4 stale with working remediation. Correct.
- **The data-flow diagram was not swept.** Its outcome node still reads
  `fresh · stale · in-progress · unknown` — missing stuck, degraded, and unreadable-count. Same root
  as violations 2 and 3 (a new state added to the bullets, table, R5 and falsifier but not to the
  summary surfaces). Fold it into the one sweep rather than treating it separately.
- **`:135` and `:149` also carry stale inline comments.** `:135`'s reads
  `# 2 docs + 2 transcripts, all reprocessed` and line 148 reads `# 2 docs + 1 transcript (the
  newest)`. Both become wrong for exactly the reason `:84`'s and `:160`'s do. Cited inside
  violation 1; repeated here so the fix list is complete.
- **Line 3067 of the plan is not a "historical listing".** It reads "Update `CODING_MEMORY.md`
  (active session + next steps)…" — a workflow instruction unrelated to indexing. It is correctly
  left alone, but R10.6's blanket characterisation of "the rest" as historical code and test
  listings does not describe it.
- **Every line-number citation I checked is right**, including several the spec added this round:
  `config.py:56` (`excludes = …`, must survive) and `:57-60` (the guard); `db.py:16`, `:17`, `:72`,
  `:103`, `:112-120`, `:121,125`, `:156`; `index.py:43-54` (`_iter_docs`, both `source_type`
  hardcodes inside the cited 44-51), `:57-67`, `:67`, `:73`, `:74`, `:100`, `:125-127`, `:135-137`;
  `chunk.py:111`, `:141`; `cli.py:39` (`choices=["decision","episodic","doc"]`), `:66`;
  `status.py:27`; `pyproject.toml:23`; `golden_queries.json` lines 2 (sqlite-over-qdrant, still
  correct) and 4 (the falsified-premise query); `test_config.py:42,48`;
  `test_index.py:58,84,93,105,106,117,135,136,149,160,161`; `memsearch/README.md:22`; the design doc
  at 58, 67, **70** (`Z -.->|NOT indexed| S` — asserts the rule without containing the string, a
  good catch) and 135, plus 154-163; the plan at 19, 2828, 2890, 2942 and 3,079 lines total;
  `memory-system-split.spec.md:540`. 16 golden queries confirmed. `docs/decisions/` tops out at
  0017, so 0018 and 0019 are free.
- **Toolchain table re-verified live, every row**: `bash` 3.2.57, `python3` 3.9.6, `uv` 0.11.28 at
  `/opt/homebrew/bin`, `sqlite3` 3.51.0, darwin 25.5.0. `launchctl getenv PATH` returns empty, so
  the plist `PATH` key is load-bearing as claimed; `bin/memsearch` is the one-line
  `exec uv run --project` wrapper; `memory-index/reindex.log` exists (Aug 6 19:56), distinct from
  the new `scheduled-index.log`. `config.json` matches the spec exactly: `curated_docs` is
  `["~/.claude/coding-memory", "~/.claude/docs", "~/.claude/PORTS.md"]` (no `~/.claude` root) and
  `weights` is `curated_doc 1.5 / repo_doc 1.2 / transcript_digest 1.0`.
- **Expected measurement drift, not a finding.** `CODING_MEMORY.md` now reads 3,364 lines /
  294,558 bytes against the spec's dated 3,232 / 285,187 — an append-only file that grew during the
  session. No conclusion depends on the exact figure.
- **The nudge's existing contract (R4) is stated accurately.** `hooks/memsearch-nudge.sh` reads
  `${MEMSEARCH_STATUS:-…}`, makes a single `python3` call, exits 0 silently when the file is absent
  or `chunks` is 0 or non-numeric, prints one line, and is registered at `settings.json:71`. Every
  "Unchanged" claim in the Contracts section checks out.
- **Part B (core-conduct + security) clean, again.** No new dependency; the plist template commits
  `__HOME__` only, with a scenario asserting no absolute path; `install-schedule` fails closed with
  distinct exit codes per step and `plutil -lint` before bootstrap; rendered plist `0644`,
  `LaunchAgents` `0755`; the only shell execution is fixed `launchctl` argument vectors with no
  external input; the atomic status write renders into `db_path.parent`, not a shared tmp. Error
  handling is stated at every boundary the design introduces, including the unpleasant ones (killed
  run, truncated `status.json`, bootstrap that reports success while loading nothing). YAGNI holds:
  every added constant and the new weight tier carries a named failure mode, scope still ends at
  parent item 5, and `RUN_MAX_HOURS` is explicitly handed back to the user rather than widened.
- **Unchanged dispositions from prior rounds** (not cited): the spec living at `docs/features/`
  rather than `docs/superpowers/specs/` — gates.md's one-canonical-file discipline governs a file
  carrying `phase` frontmatter and a checklist, and the repo layer wins; `/opt/homebrew/bin` in the
  plist `PATH`; `scheduled-index.log` having no stated mode or rotation. Frontmatter remains
  `phase: planning`, `branch: none`.

---

## Round 5 — 2026-08-07T04:27:00Z — **FAIL** (1 violation)

`main` @ `9ad77809` · spec blob `748b108ba85fe519997136a918be9ee660a0367b` · confidence **high**

### In layman's terms

The spec was restructured this round rather than patched again. It now has **one** table of the
eight freshness states, and every other part of the document points at that table instead of
copying it. That fixed the root cause of rounds 3 and 4: a state got added in one place and the
half-dozen places that repeated it went stale. All four of round 4's findings are genuinely
closed — I re-ran every command they rested on rather than trusting the spec's word for it.

One thing still does not survive re-measurement, and it is the same species as before: a number
recalled instead of re-run. The spec argues that adding `CODING_MEMORY.md` to the index could
drown out other results, and sizes that risk as "**2.3× the largest doc currently indexed**",
naming a compliance-judge design doc as that largest doc. It isn't the largest. Three documents
already in the index are bigger — a vibe-scape plan at 185,097 characters, another at 154,330,
and `docs/features/phase-guard-hook.md` at 132,469 — against the true largest the archive is
**1.6×**, not 2.3×. The named doc is only the largest by *chunk count*, while the spec's own
arithmetic is character-based. This does not misdirect anyone building the feature (R9 is still
the real instrument), but it sits inside the one paragraph whose whole claim is "measured, not
argued", and it makes the risk read ~40% scarier than the corpus actually supports.

### Violations

| id | rule source | where | why |
|---|---|---|---|
| `core-conduct/noise-risk-largest-doc` | `rules/core-conduct.md` | R10 → *The noise risk is real and is measured, not argued* | `coding-memory/compliance-judge/2026-07-26-03b-deploy-design.md` (129,880 chars) is **not** the largest indexed doc — `vibe-scape/docs/plans/2026-07-13-live-presence-plan.md` (185,097), `…/2026-07-13-ar-portal-client-plan.md` (154,330) and `~/.claude/docs/features/phase-guard-hook.md` (132,469, same `curated_doc` bucket) are all larger and all carry `sources` rows, so the stated **2.3×** is really **1.6×** and the superlative names the wrong file. |

### Round 4's four findings — all verified closed, none re-cited

- `writing-specs/edge-cases-r10-test-counts` — **closed.** The R10.4 table now labels `:117` as
  the *changed-file* test (`test_changed_file_reindexes_only_itself`, `processed == 1`) and
  `:149` as the *limit-scoped* one (`processed == 3` → 4), matching `test_index.py` exactly, and
  explicitly flags the earlier mislabel. All four stale inline comments are now named —
  `:84`, `:135`, `:148`, `:160` — and each quoted comment text is verbatim correct. The five
  movers (`:84,:106,:135,:149,:160`) and four non-movers (`:105,:117,:136,:161`) are each right
  under the +1 rule; "seven failing functions from eight failing assertions" is exact
  (`:84`/`:93` share `test_full_run_indexes_all_sources_newest_first`).
- `writing-specs/fresh-scenarios-error-count` — **closed.** Every scenario asserting a fresh line
  now pins `last_run_errors is 0`: *Fresh index reports its age*, *The threshold itself counts as
  stale*, *A successful run that changes nothing*, *A clean recent run is fresh*, *A future
  run_started is not a run in progress*. I walked all 44 scenarios against the state table's
  first-match-wins ordering; every one resolves to exactly the state it claims.
- `writing-specs/r3-state-count` — **closed.** R3 says "Eight states", the table has rows 1–8, the
  emitted-line list has 8 entries in the same order, and the diagram's `OUT` node names all eight.
- `writing-specs/plan-sweep-hit-count` — **closed and correct.**
  `grep -n CODING_MEMORY docs/superpowers/plans/2026-07-17-memory-rag-index.md` returns exactly
  **14**, at lines 19, 41, 152, 205, 211, 282, 284, 318, 1484, 1519, 2828, 2890, 2942, 3067 — the
  spec's four-to-correct (19, 2828, 2890, 2942) and ten-to-leave (41, 152, 205, 211, 282, 284,
  318, 1484, 1519, 3067) partition matches hit for hit. Plan is 3,079 lines.

### Everything else re-measured this round

Live, not recalled: `sources` = **911** rows, **187** at `2026-07-18` and **724** at `2026-08-06`
— exactly as R9's premise-refresh states. `session-log.md` last date `2026-07-16`,
`decisions.md` `2026-07-19`, both still frozen. Project copies 159 / 119 lines. Deploy-design doc
129,880 chars / 130 chunks (both figures right; only the superlative around them is wrong).
`~/.claude/CLAUDE.md`, `MEMORY.md` and `CODING_MEMORY.md` all 0 `sources` rows; `PORTS.md`
indexed. `golden_queries.json` holds 16 entries — 11 `must`, 3 `stretch`, 2 `negative` — line 4 is
the CODING_MEMORY exclusion query, line 2 the still-correct sqlite-over-qdrant one, and entry 11
at file line 12 is the mid-july/`episodic`/`since`/`.jsonl` case task 10 predicts as a casualty.
`test_golden_queries.py:37-41` asserts presence only, `:47-52` and `:57-60` warn — R9's claim that
its bar is invisible to that harness is correct. Toolchain verified row by row: bash 3.2.57,
python3 3.9.6 (bare `isoformat()` emits microseconds; `timespec='seconds'` matches `db.py:103` and
the live `status.json`; `Z` is rejected), uv 0.11.28 at `/opt/homebrew/bin`, venv python 3.12.13,
sqlite3 3.51.0, darwin 25.5.0, `launchctl getenv PATH` empty. Every source citation checked out:
`config.py:56`/`57-60`, `db.py:16,17,72,103,112-120,121,125,156`, `index.py:43-54,57-67,67,73,74,
100,125-127,135-137`, `chunk.py:109-111,140-141`, `cli.py:39,66`, `status.py:27`,
`pyproject.toml:23`, `README.md:22`, design doc 58/67/70/135/154-163,
`memory-system-split.spec.md:540`. `docs/decisions/` tops out at 0017, so 0018/0019 are free. No
lock or pidfile exists in `memsearch/` (decision 5's premise holds); `digest_input_char_cap` is
used only in `digest.py`/`eval.py`, never in `chunk_doc`.

### Waivers

None. No violation has ever been waived on this spec.

## Round 6 — 2026-08-07T05:33:10Z — **FAIL** (1 violation)

Blob `948f332606dba0a5f909bd662dd4e4d8a1a7e839` · commit `dd3004988e038b9b5b6ee4d2304c0b6db9f7619d` · branch `main` · 1113 lines.

### In layman's terms

Round 5's one finding is genuinely fixed — I re-measured every number in that paragraph from
scratch and they are all exact. The noise multiplier is now `1.62×` against the file that really is
the biggest indexed document, and the old wrong figure survives only inside the note explaining why
it was wrong. The R9 score-floor discovery is real too: I re-derived the scorer's ceiling from
source and it is `0.04918`, so the old `≥0.30` bar could never have been met by anything. Staging
the replacement floor for a human to set from measured data reads as a decision, not a blank — task
8b produces the numbers, a person picks the bar, and task 10 refuses to invent one. I am not citing
that.

What is still wrong is small but it is the spec's own house rule. R3 says its eight-state table is
the final word and every other part of the document is derived from it. Two parts have not been
re-derived. R1–R2 promise, in pinned exact wording, that a missing "when did the last run finish"
timestamp always prints `age unknown` — but the table prints `index run in progress` instead when a
run has just started, which is exactly what the spec's own "first run after upgrade" scenario
demands. And the table's own list of places to update when it changes still points at a section
that round 5 deleted, and still omits falsifier clause (h), which the falsifier itself says comes
from state 3. Both are one-sentence fixes. They matter because this is the precise defect —
a surface restating the states going stale — that rounds 1–4 kept failing on and that round 5's
rewrite was built to end.

### Violations

| id | rule source | where | why |
|---|---|---|---|
| `writing-specs/derived-surfaces-out-of-sync` | `skills/writing-specs/SKILL.md` | R2, and R3 → "The state table — the single source of truth" (the derived-surface list) | R3 declares its table authoritative over "every other surface in this spec", but two surfaces have not been re-derived from it. (1) R2 pins the exact wording `memsearch: 2332 chunks, age unknown — query with: …` for a "missing, unparseable, or future-dated `last_run`" — states 1, 2 and 3 contradict that, since a missing `last_run` with a usable recent `run_started` emits the in-progress line, which the spec's own scenario "The first run after upgrade has no last_run yet" asserts explicitly ("And it is not the unknown-age line"). (2) R3's own enumeration of surfaces to re-derive names "the classification table under Contracts", which round 5 deliberately deleted (Contracts now says the states are "deliberately *not* restated here"), and names "falsifier clauses (f) and (g)" while the falsifier itself says "(f), (g) and (h) are **derived from R3's state table** — … (h) from state 3". |

Both halves are pre-existing (the round-5 blob `748b108` carries the same list at its line 119 and
the same falsifier text at its line 879) and were not cited in round 5. They are newly cited here,
not persistent — `writing-specs/derived-surfaces-out-of-sync` is a fresh id.

### Round 5's violation — verified closed, re-measured from zero

`core-conduct/noise-risk-largest-doc` is **closed**. Every figure re-derived this round rather than
read back:

| claim in the spec | measured | verdict |
|---|---|---|
| `CODING_MEMORY.md` 300,160 characters | `wc -m` = 300,160 | exact |
| largest indexed doc = `vibe-scape/docs/plans/2026-07-13-live-presence-plan.md`, 184,620 chars | ranked all 367 non-transcript `sources` rows by on-disk character count; it is #1 at 184,620 | exact |
| that file has 121 chunks | `count(chunks)` = 121 | exact |
| three indexed docs larger than the previously-named file | 184,620 · 153,701 · 131,516 all exceed `2026-07-26-03b-deploy-design.md` at 128,317 | exact |
| the old file is largest by **chunk count**, not size | 130 chunks, the corpus maximum | exact |
| multiplier `1.62×` | 300,160 / 184,620 = 1.62572 | truncated, not rounded (1.63 rounds); conservative direction |

`grep` over the spec finds `2.3` and `03b-deploy-design` only inside the correction note that
explains them. No other surface still carries the old number.

### R9's ceiling — re-derived from source, not accepted

`search.py:19` is `RRF_K = 60`. `:64` accumulates `1.0 / (RRF_K + rank + 1)` over exactly two id
lists (`vec_ids`, `fts_ids`), so the fusion maximum is `2 × 1/61 = 0.0327869`. The weight multiply
is `r["score"] = round(base_score * r.pop("weight"), 6)` and `config.json` weights top out at
`curated_doc: 1.5`. Ceiling `= 0.0491803` → **0.04918**, exactly as the spec and task 8b state, and
the old `≥0.30` bar was **6.1×** that ceiling. The ceiling survives R10 unchanged, because
`archive_doc` enters at 1.0 and does not raise `max(weight)`. The two live scores (0.046514,
0.040114) were not re-run — that needs Ollama and a model load — but both sit under the ceiling and
are consistent with it. One citation slip: the weight multiply is `search.py:80`, not `:78`; the
`:61-64` fusion range and `:19` are right.

### The staged floor, the three corrections, and the new Non-goal — all judged, none cited

- **Staged R9 floor.** Not a TBD. Clauses 1 and 2 bind unconditionally; clause 3 is explicitly
  non-binding until recorded; task 8b runs the queries, records raw unrounded scores plus the
  ceiling, and stops for a named human decision; task 10 reports `not yet binding` rather than
  passing, failing, or inventing a number, and says "stop and ask". Every state of the world has a
  defined behaviour, so the spec is unambiguous and checkable. Unusual, not deficient.
- **R3 state-3 prose.** Now says the stamp "stops being *believed*, though it remains **usable** in
  the table's sense", with the prior wording quoted and disowned. Agrees with the definition above
  it. Round 5's note 3 is closed.
- **Decay scenario.** `last_run` 40h / `run_started` 30h is satisfiable (30h ago is later than 40h
  ago) and, walked through first-match-wins: rows 1–2 fail on age ≥ `RUN_ABANDON_HOURS`, row 3
  fails on `last_run` present, row 4 fails on `last_run` usable, row 5 fires at 40h ≥ 8h — "stale,
  not stuck", carrying the index command, exactly as the scenario claims.
- **Non-goals heading claim.** Re-counted: `^## ` session headings number **20** — 17 date-first
  (`## 2026-08-06 — session N: …`) and 3 session-first (`## Session 29 — …`) — and **zero** carry
  the `Session N — <date>` shape. Matches the corrected text figure for figure.
- **New Non-goal, the zero-walk run.** Honest and sufficient. Verified the mechanism: `chunks` in
  `status.json` comes from `dbmod.stats(conn)` over the whole `chunks` table, so it does survive a
  run that walked nothing, and R4's "`chunks` absent or 0" escape hatch genuinely cannot catch it.
  The bullet names the gap, the mechanism, why it is the same species as the Background failure,
  the cost of closing it (a new field, a ninth state, its scenarios and tests), and the pointer to
  use if it recurs. Naming a bounded limitation is what core-conduct asks for; closing it here
  would be the scope creep.

### Everything else re-measured this round

Live index: 911 `sources` rows, 367 docs + 544 transcripts. `status.json` carries exactly the six
keys the Contracts section promises to preserve, with `last_indexed` `2026-08-06T23:56:46+00:00`.
`coding-memory/session-log.md` frozen at 2026-07-16, `decisions.md` at 2026-07-19 — both as stated.
The plan sweep re-run returns **14** hits at 19, 41, 152, 205, 211, 282, 284, 318, 1484, 1519,
2828, 2890, 2942, 3067; the four-to-correct / ten-to-leave partition matches hit for hit, and the
plan is 3,079 lines. `test_index.py` line by line: `:58` fixture writes `CODING_MEMORY.md` into the
curated dir; `:84 processed == 4  # 2 docs + 2 transcripts`; `:93` compound; `:105 == 0`;
`:106 skipped == 4`; `:117 processed == 1`; `:135 == 4  # … all reprocessed`; `:136 skipped == 0`;
`:148` comment; `:149 == 3`; `:160 == 2  # the two docs still landed`; `:161 len(errors) == 2` —
the movers/non-movers table and all four quoted comments are correct. `test_config.py:40-43` is the
mandatory-exclusion test and `:48` the inclusion assertion. `config.py:56` is the `excludes = …`
line that must survive, `:57-60` the guard. `db.py:16/17/103/112/120/121,125/156`,
`index.py:44-51/57/67/73/74/100/125-127/135-137`, `chunk.py:111/140-141`, `cli.py:39/66`,
`status.py:27`, `pyproject.toml:23` (`addopts = "-m 'not golden'"`), `README.md:22`, design doc
58/67/70/135/154-163, `memory-system-split.spec.md:540` — all exact. `golden_queries.json` holds 16
entries (11 `must`, 3 `stretch`, 2 `negative`); entry 11 at file line 12 is the mid-july /
`episodic` / `since: 2026-07-01` / `.jsonl` case; `test_golden_queries.py:37-41` asserts presence
only, `:47-52` and `:57-60` warn. ADRs top out at 0017 so 0018/0019 are free. Project copies 159
and 119 lines. Toolchain row by row: bash 3.2.57, python3 3.9.6, uv 0.11.28 (Homebrew), venv python
3.12.13, sqlite3 3.51.0, darwin 25.5.0; `launchctl getenv PATH` empty, so the plist `PATH` key is
load-bearing; `bin/memsearch` is the one-line `exec uv run --project` wrapper.

**Part B clean.** No new dependency. The only shell execution is fixed `launchctl` argument vectors
plus a `plutil -lint` gate that must pass before anything is bootstrapped; no external input
reaches a command line; `install-schedule` fails closed on 1/2/3 and never prints success on a
non-zero path; rendered plist 0644, LaunchAgents 0755; the committed template carries `__HOME__`
only, with a scenario asserting it. `status.json` writes are atomic via `os.replace` into
`db_path.parent`, and the entry write's fallible read is caught (`OSError`, `JSONDecodeError`),
reported once on stderr, never raised. On `writing-secure-code` §5: R10 adds the archive to the
embedded corpus, but `ollama_url` is `http://localhost:11434` and `_refuse_cloud` rejects cloud
models, so nothing new leaves the machine.

**Benign drift, carried as notes not violations.** R10 says "3,433 lines" at two places while the
dated re-measurement says 3,484 (`wc -l` agrees with 3,484); the file grows every session and the
spec calls its figures a floor. "Carries sessions 24 through 31" still understates — the headings
run 17 → 32 — but understating strengthens its own argument, as round 5 also concluded. The spec is
1113 lines and carries inline "corrected in round N" annotations; that is deliberate anti-recall
discipline rather than bloat, though those annotations would read better relocated to
`## Verification` once the spec is approved.

**Unchanged dispositions, not re-cited:** spec at `docs/features/` rather than
`docs/superpowers/specs/`, `/opt/homebrew/bin` in the plist `PATH`, `scheduled-index.log` with no
stated mode or rotation. No repo-layer `.claude/project-standards.md` exists. Frontmatter remains
`phase: planning`, `branch: none`.

### Waivers

None. No violation has ever been waived on this spec.

---

## Round 7 — 2026-08-07 — FAIL (1 violation)

`.claude` @ `main` · head `a7b95e77b4a51f25da5d055366b096fa6c7902e6` · spec blob
`d0428e4d40d36372647e260657e1204a262098a6` · 1163 lines · confidence **high**

### In plain English

Round 6's finding is genuinely closed. R2 no longer pins a line of output; it states the guarantee
("never fresh without proof") and hands the wording to R3's table, naming states 1-4 correctly.
R3's list of surfaces to re-derive now names R2 and clause **(h)** and has dropped the Contracts
table round 5 deleted. I re-derived all eight states by hand against every scenario in the spec:
each one classifies to the state it claims, including the two future-timestamp cases and the decay
case. No disagreement anywhere between the table and the surfaces the list names.

The new failure is one list entry over. **Falsifier clause (a) says the feature has failed if a
session starts with `last_run` older than `STALE_HOURS` and no stale line is emitted — and R3's
table requires exactly that, twice.** First-match-wins puts *in progress* (1) and *stuck* (2)
ahead of *stale* (5), so a run that is currently going suppresses the stale line by design. That
is not a corner case for state 2: "stuck" means `run_started` is 6-24h ago and is *newer* than
`last_run`, so once `run_started` passes 8h, `last_run` is necessarily older than 8h too. Every
stuck run in that range trips clause (a). Clause **(g)** blesses precisely the same line ("an
in-progress or stuck line is still emitted more than `RUN_ABANDON_HOURS` after `run_started`" is
the failure, so emitting it *within* 24h is correct). Both (a) and (g) are listed as **hook
tests** — task 4 would write two tests that cannot both pass against a correct implementation.

The reason it slipped is the same reason round 6's did: clause (a) is a surface derived from the
table's *ordering*, and it is not in R3's derived-surface list. Only (f), (g) and (h) are named
there; (a) and (b) are declared un-derived. (b) genuinely is safe — state 5 fires only at
`≥ STALE_HOURS`, so no stale line can appear under the threshold. (a) is not.

Same rule, same territory as round 6, so the id carries forward — but it is a **different
instance** inside that territory, not the round-6 text left unfixed. The fix is small: scope (a)
to the states that can actually emit stale (something like "…and no stale line is emitted while no
run is in progress or stuck"), and add (a) to R3's list in the same edit.

Round 7's other three changes all check out and are not cited. R9's clause 3 is now
*better*-specified, not worse: the conjunction-of-binding-clauses rule, the
`pass (clause 3 not yet binding)` reporting form, falsifier **(i)** and the second scenario agree
with each other and with task 8b and task 10(b), and (i) closes the real hole — that "not yet
binding" fails nothing, making a skipped measurement the cheapest green board. `3,433` is gone;
`3,484` appears three times and `wc -l` agrees. `search.py:80` is correct
(`r["score"] = round(base_score * r.pop("weight"), 6)`), and the 0.04918 ceiling is exact
arithmetic on `2 × 1/61 × 1.5`.

### Violations

| id | source | where | why |
|---|---|---|---|
| `writing-specs/derived-surfaces-out-of-sync` | `skills/writing-specs/SKILL.md` | Falsifier clause (a), against R3's state table (states 1-2) and falsifier clause (g); and R3's derived-surface list, which does not name (a) | Clause (a) declares the feature failed whenever `last_run` exceeds `STALE_HOURS` with no stale line, but R3's first-match-wins ordering mandates the in-progress and stuck lines instead — and a state-2 run with `run_started` 8-24h old *always* has `last_run` older than 8h — so the clause-(a) and clause-(g) hook tests contradict each other, and (a) is absent from the list of surfaces to re-derive. |

Citations, re-run this round: table at spec `:148-157` ("Eight states. First match wins."), rows 1,
2 and 5; state-2 range from `RUN_MAX_HOURS` 6 / `RUN_ABANDON_HOURS` 24 at `:216`; clause (a) at
`:960-961`; clause (g) at `:968-969`; hook-test designation and the derived-clause list at
`:975-977`; R3's derived-surface list at `:131-134`.

### Derived surfaces that agree with the table but are not on its list — notes, not violations

Every one of these is currently *correct*; naming them is about the index, not about restating the
states. Round 5 removed duplication deliberately and none of this asks for it back.

- **R1 (`:105-107`) pins two output lines verbatim** — the fresh line and the stale line. Diffed
  character for character against table rows 8 and 5: identical today. It is the same shape as the
  round-6 R2 defect and it is not on the derived list.
- **Contracts → `hooks/memsearch-nudge.sh` (`:613-616`)** states ordering consequences: "states 5,
  6 and 7 all warn, stale wins" and "state 3 is checked before state 4". Both correct against
  first-match-wins; both would go stale if a state were inserted.
- **Three Non-goals bullets** name states: zero-walk → "state 8, fresh" (`:993`); lock/pidfile →
  states 1, 2 carry no remediation and decay to state 5 (`:1025-1027`); log rotation → "states 2,
  3, 6 and 7 all point a reader at that file" (`:1034`). All three verified correct against the
  table's remediation column.

### Other notes

- **Task 9's stop condition names only `RUN_MAX_HOURS`** (`:1125-1126`) while R3 says both run
  constants are re-chosen against the measurement and calls `RUN_ABANDON_HOURS` "the stricter
  obligation". In practice safe — any duration that threatens 24h necessarily exceeds 6h, so the
  stop fires — but the task could name both.
- **"Carries sessions 24 through 31"** (`:357-358`) still understates: headings run **17 → 32**
  (24 `##` headings, 20 of them session-shaped). Carried as a note in rounds 5 and 6 for the same
  reason — understating strengthens the argument the sentence is making.
- **Length.** 547 → 1163 lines across seven rounds (+50 this round); 12 lines are "corrected in
  round N" annotation. Still reads as anti-recall discipline rather than padding, but
  `writing-specs`' tokenization constraint is real — these belong under `## Verification` once the
  spec is approved.

### Everything re-measured this round (not recalled)

Live index **911** `sources` rows — **187** at `2026-07-18`, **724** at `2026-08-06`, matching the
Background exactly. `CODING_MEMORY.md` **3,484 lines / 300,160 characters**; largest indexed `.md`
is `vibe-scape/docs/plans/2026-07-13-live-presence-plan.md` at **184,620** characters / **121**
chunks → **1.62×** (300160/184620 = 1.6258); the three larger-than-the-old-claim docs are
**184,620 / 153,701 / 131,516**, and `2026-07-26-03b-deploy-design.md` is largest by *chunk* count
(**130**) at 128,317 characters — the unit-conflation correction is right in both directions. Plan
sweep re-run: **14** hits, partitioned exactly as stated (correct: 19, 2828, 2890, 2942; leave: 41,
152, 205, 211, 282, 284, 318, 1484, 1519, 3067), plan is 3,079 lines. Design doc 58 / 67 / 70
(`Z -.->|NOT indexed| S`) / 135 / 154-163 all exact. Code: `search.py:19` `RRF_K = 60`, `:61-64`
two-retriever RRF, `:80` weight multiply; `config.py:56` `excludes = …`, `:57-60` guard;
`db.py:16/17/103/112-120/121,125/156`; `index.py:44-51/57-67/73/74/100/125-127/135-137`;
`chunk.py:111/140-141`; `cli.py:39/66`; `status.py:27` — every one exact. Tests: `test_index.py`
`:58/84/93/105/106/117/135/136/148/149/160/161` and all four quoted comments verbatim;
`test_config.py:42/48`; `test_golden_queries.py:37-41` presence-only, `:47-52` and `:57-60` warn;
`golden_queries.json` 16 entries (11 `must` / 3 `stretch` / 2 `negative`), line 4 is the falsified
premise and line 2 the still-correct sqlite-over-qdrant query, entry 11 at file line 12 is the
mid-july/`episodic`/`since`/`.jsonl` case; `pyproject.toml:23` `addopts = "-m 'not golden'"`;
`README.md:22`. Toolchain row by row: bash 3.2.57, python3 3.9.6 (rejects `Z`, parses `+00:00`), uv
0.11.28 Homebrew at `/opt/homebrew/bin`, venv python 3.12.13, sqlite3 3.51.0, darwin 25.5.0, no
`timeout` binary, `launchctl getenv PATH` empty. Project copies 159 and 119 lines. `config.json`
confirms `curated_docs` omits the `~/.claude` root, so R10's "necessary but not sufficient" trap is
real.

**Part B clean, unchanged from round 6.** No new dependency (pytest 8.3.4, sqlite-vec 0.1.9,
hatchling 1.27.0 already pinned in `pyproject.toml` + `uv.lock`); shell execution is fixed
`launchctl` argument vectors behind a `plutil -lint` gate; `install-schedule` fails closed 1/2/3
and never prints success on a non-zero path; plist 0644, LaunchAgents 0755, `__HOME__` only with a
scenario asserting it; `status.json` writes atomic via `os.replace`, entry-read fallible-by-design
and caught. No absolute paths, no secrets. YAGNI holds — eight states each carry a stated failure
they exist to catch, and R10 is corrective.

**Not re-cited (settled):** spec at `docs/features/`, `/opt/homebrew/bin` in the plist `PATH`,
`scheduled-index.log` mode/rotation, the unset R9 floor (round 7 made it stricter, not worse), the
zero-files-walked Non-goal. No repo-layer `.claude/project-standards.md` exists.

### Waivers

None. No violation has ever been waived on this spec.

---

## Round 8 — 2026-08-07 · `main` @ `1a15a77` · blob `eff35fbf` · **FAIL** (1 violation)

### In plain English

Round 8 did the right thing about the wrong-shaped problem: instead of patching one more
out-of-sync sentence, it built a sixteen-row index of every place in the spec that names one of the
eight nudge states, and declared the state table the only place a state is defined. That is the
correct fix for a defect that had survived three rounds. The index is genuinely good — I checked
every row against the table and none of them contradicts it, and I re-measured every number the
spec's conclusions rest on (chunk counts, the scorer's ceiling, the archive's size, thirty-odd
file:line citations) and every single one held.

But the index is not complete. The **Design decisions** section — decisions 1, 2, 5 and 6 — names
states and asserts their order, and no row for it exists in the table. Decision 5 is the sharp
instance: it says flatly that *"the nudge reports an in-progress run rather than a stale one"* and
calls that a safety behaviour, because telling a reader to run the indexer while one is already
running invites a second one. The state table does not actually promise that. Past
`RUN_ABANDON_HOURS` the decay deliberately reclassifies exactly that run as **state 5, stale** —
which *does* carry the index command. The spec knows this and says so in the concurrency Non-goal
("the guarantee is bounded, not absolute"), and that Non-goal *is* in the index. Decision 5, which
a reader hits four hundred lines earlier, states the unbounded version and is not.

So this is the same class the last three rounds fixed one instance at a time, and the same class
round 8's inventory exists to close — one surface the sweep missed. It is a small edit (add a
Design-decisions row; bound decision 5's sentence the way the Non-goal already does), and it is
cited rather than noted because the spec's own rule is explicit: *"Anything added to this spec that
names a state joins this table in the same edit."*

Supporting evidence that the sweep was not run against the round-8 document: the header says it
covered *"all 1,163 lines"*. This file is **1,214** lines. 1,163 is exactly the line count of the
round-7 blob (`a7b95e7`), the revision this table replaced.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/derived-surfaces-out-of-sync` | `skills/writing-specs/SKILL.md` | The spec is the source of truth — maintain it with production rigor; drift between a source of truth and its derived surfaces causes the agent to describe behavior that does not exist | Design decisions (decisions 1, 2, 5 and 6), against R3's sixteen-entry derived-surface inventory and the state table's rows 1 and 5 | Decisions 5 and 6 name states and assert their precedence yet no Design-decisions row exists in the inventory the spec's own rule requires ("anything added to this spec that names a state joins this table in the same edit"), and decision 5 states its concurrency guarantee unconditionally where the table reclassifies the same run as state 5, stale — carrying the index command — past `RUN_ABANDON_HOURS` |

Recurrence: cited in rounds 6 and 7 under the same id, in different territory each time
(round 6: R2's pinned line vs. the table; round 7: falsifier clause (a) vs. clauses (g)/(a)'s
precedence). Round 8 fixed both cited instances and replaced the three-entry list with a sixteen-entry
inventory; the class narrowed sharply but did not close.

### The sweep I ran, section by section

Every section of the spec, checked for a state name, a rendered line, or an ordering claim:

| Section | Names a state / line / ordering? | In the inventory? |
|---|---|---|
| Header, Background, Diagnostic findings | no (the quoted *"2332 chunks…"* is today's line, not a new one) | n/a |
| **Design decisions 1, 2, 5, 6** | **yes — 1/5/7/8 by name, plus decision 5's precedence claim** | **NO — violation** |
| R1, R2 | yes | yes |
| State table, eight rendered lines | authoritative | yes |
| Why each state exists | yes | yes (description overstated — see notes) |
| The three constants | yes (1, 2, 5) | yes (row says 2 and 5) |
| R4 ("at most one line", silent paths) | silent paths sit outside the table by the spec's own words | out of scope, defensible |
| R5 (`last_run_errors` … "unknown, never zero") | restates row 6's *condition* without naming the state | borderline — see notes |
| R6-R10 | no | n/a |
| Data flow (OUT node + the monitor sentence) | yes, all eight in table order | yes |
| Contracts → `index.py` | yes (stuck **and** in-progress) | yes (row names only stuck) |
| Contracts → `status.py`, plist, `install-schedule` | no | n/a |
| Contracts → `memsearch-nudge.sh` | yes (1-8, 5/6/7 warn, stale wins, 3 before 4) | yes |
| Scenarios | yes — all eight states plus both silent paths, verified individually | yes |
| Falsifier (a)-(i) | yes (1, 2, 3, 5, 6, 7, 8) | yes (row omits 8) |
| Non-goals: zero files / concurrency / log growth / retrying | yes | yes, all four, all agreeing |
| Non-goals: dating, re-scoping, promotion, re-measuring, exit code, misc | no | n/a |
| What success means | "reliably fresh index" — generic usage, not the state | out of scope |
| Task 4 | yes (3, 4, 6, 7 + 3-before-4 ordering) | yes (row names 3, 6, 7) |
| Tasks 9, 10, 10c, 11 | constants and falsifier letters only, no states | n/a |

### Everything re-measured this round (not recalled)

**Chunk-count range, mechanically re-counted** — `SELECT s.path, count(c.id) … WHERE s.path LIKE
'%/docs/features/%'` returns exactly eleven files in exactly the spec's order and values:
`phase-guard-hook` **91**, `replay-harness-base-pin` **70**, `verification-marker-gate` **53**,
`memory-system-split.spec` **31**, `git-guard-empty-index` **24**, `memsearch-freshness` **14**,
`shell-segments-redirects` **13**, `git-guard-chained-command` **13**, `falsifier-base-pin` **9**,
`stale-phase-guard-rule-text` **6**, `memory-system-split` **6**. Spread 91/6 = **15.17×** ✓.

**Scorer ceiling, re-derived from source** — `search.py:19` `RRF_K = 60`; `:64`
`rrf[cid] = rrf.get(cid, 0.0) + 1.0 / (RRF_K + rank + 1)` over exactly two id lists (`vec_ids`,
`fts_ids`); `:80` `round(base_score * r.pop("weight"), 6)`; `config.json` weights
`{curated_doc: 1.5, repo_doc: 1.2, transcript_digest: 1.0}`. Ceiling `2 × 1/61 × 1.5 =`
**0.0491803…** → **0.04918** ✓. R9's removal of the score clause leaves two rank clauses that can
genuinely fail, and the chunk-count-span requirement is the right guard against tuning the sample
instead of the number.

**Archive and corpus** — `CODING_MEMORY.md` **300,160 characters / 3,484 lines** ✓;
**24** `## ` headings of which **17** date-first and **3** session-first = **20** session-shaped in
two forms ✓; largest indexed doc `2026-07-13-live-presence-plan.md` **184,620** chars / **121**
chunks → 300160/184620 = **1.6258** → 1.62× ✓; the three docs larger than the old claim are
**184,620 / 153,701 / 131,516** ✓ and `2026-07-26-03b-deploy-design.md` is 128,317 chars but
**130** chunks ✓; only `PORTS.md` is indexed from the `~/.claude` root (no `CLAUDE.md`,
`MEMORY.md`, `CODING_MEMORY.md` row) ✓; `curated_docs` = coding-memory, docs, PORTS.md ✓;
`session-log.md` last date **2026-07-16**, `decisions.md` last decision **2026-07-19** ✓.

**Citations** — `config.py:56` `excludes = tuple(...)` and `:57-60` the `raise ConfigError`;
`db.py:16` `SOURCE_TYPES`, `:17` `RECALL_TYPES` containing `episodic`; `chunk.py:111`
`recall = "decision" if "decisions" in str(path) else "doc"`; `test_index.py` `:58` (fixture writes
into the *curated* dir), `:84`=4, `:93` compound, `:105`=0, `:106`=4, `:117`=1, `:135`=4, `:136`=0,
`:148` comment, `:149`=3, `:160`=2, `:161`=2 — and all four quoted inline comments verbatim;
`test_config.py:40/42/48`; `golden_queries.json` line 4 = the falsified-premise query, line 2 = the
still-correct sqlite-over-qdrant one, file line 12 = golden entry 11 (`mid july`, `must`,
`{rtype: episodic, since: 2026-07-01}`, `.jsonl`); 16 entries = 11 `must` / 3 `stretch` /
2 `negative`; `test_golden_queries.py:37-41` asserts presence only, stretch/negative `warnings.warn`;
`pyproject.toml:23` `addopts = "-m 'not golden'"`; `README.md:22`. Every one exact.

**Part B clean.** No YAGNI overreach against the stated need (eight states each catch a named
failure; R10 is corrective; item 6 excluded). Error paths explicit at every boundary the design
introduces — entry write fallible-by-design and caught, atomic `os.replace`, nudge exit 0 on every
path, `install-schedule` exit 0/1/2/3 each naming the failing step and never printing success on a
non-zero path. `__HOME__` placeholder only, with a scenario asserting no committed absolute path;
plist 0644, LaunchAgents 0755. No injection surface: `launchctl` is called with fixed argument
vectors and `$(id -u)`, no user-supplied input reaches a shell or a SQL string. `CODING_MEMORY.md`
is already git-tracked, so indexing it into a local `memory.db` adds no exposure that did not
already exist. `RUN_MAX_HOURS` is escalated to the user against task 9's measurement rather than
silently chosen — architecture trade-off correctly left human-owned.

**Round-7 violation resolved.** Clause (a) is now scoped to *"no state 1, 2 or 3 line applies"*,
which removes the (a)/(g) contradiction: a state-2 run whose `run_started` is 8-24h old no longer
demands a stale line, and the two hook tests task 4 creates can now both pass.

### Notes (non-blocking)

1. The inventory header says the sweep covered *"all 1,163 lines"*; the file is **1,214**. 1,163 is
   exactly the round-7 blob's line count — the sweep describes the revision this table replaced.
2. Five inventory rows under-describe their surface. **"Per-state rationale bullets | all eight, by
   name and number"** — the section has **five** bullets (1, 2, 3, 6, 7); states 4 and 5 appear only
   inside bullet 3's prose and state 8 is not named at all. **"Threshold rationale | states 2 and
   5"** also names 1 and 2 ("states 1 and 2 exist to prevent"). **"Contracts → `index.py` | the
   stuck-run case"** also names the in-progress line twice. **"Task 4 | states 3, 6, 7"** also names
   state 4 and the 3-before-4 ordering. **"Falsifier | 1, 2, 5, 6, 7, 3"** — clauses (f) and (g)
   also name the fresh line, state 8. None contradicts the table; they are descriptions written
   loosely in a table whose header claims mechanical derivation.
3. R5's parenthetical (*"any other value, or its absence, is unknown, never zero, per R3"*) restates
   row 6's condition in substance without naming the state — borderline against the sweep's own
   stated criteria, and worth a decision either way.
4. *"a cold run approaching `RUN_ABANDON_HOURS` makes state 5 fire … while the first run is still
   alive"* reads two ways. The *"second concurrent indexer"* contrast makes "first" mean "the one
   already running", which agrees with the table; a reader could take it as state 3's *first run*,
   for which `last_run` is absent and the remediation is the log, not the index command.
5. The scenario coverage is genuinely complete — all eight states and both silent paths each have a
   scenario, and the OUT node lists all eight names in table order.

### Waivers

None. No violation has ever been waived on this spec.
