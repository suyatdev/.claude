# Compliance judge — `docs/features/phase-guard-hook.md`

Spec: `docs/features/phase-guard-hook.md` (repo `phase-guard-hook` worktree, branch
`worktree-phase-guard-hook`)

---

## Round 1 — 2026-07-25 — **FAIL** (5 violations)

**HEAD:** `ed353a12605ef8cfd9e02a292687a99282fd21a7` · **spec blob:** `d972b9b3335855343e2196ea1a3c0d435f8e436c`

### Layman summary

This is a strong spec — genuinely above the bar for this store. Its central move (stop asking
"which feature is active?", ask "does this branch carry permission?") does hold up, and every
factual claim I could check against the actual files turned out to be true: the two cited hook
line numbers are exactly right, `settings.json` really does have exactly three `PreToolUse`
matcher blocks, the three pinned tool versions match this machine, the subtle `git cat-file
--batch` parser claim is empirically correct, and the task list never edits tests and
implementation in the same step.

What blocks it is a gap between what the spec promises and what it builds. The hook guards the
`Edit`, `Write`, and `NotebookEdit` tools — but not the `Bash` tool. An agent that writes source
with `sed -i`, `cat > file`, or `python -c` is not stopped at all, and no hook in the existing
`Bash` chain catches it either. Meanwhile the spec says there is deliberately "no bypass" and even
requires the block message to tell the user so. That combination will mislead a reader into
trusting a fence with an open gate beside it. The gap may well be acceptable — but it has to be
written down in Non-goals, not discovered later.

The other four are smaller but concrete: the spec carefully specifies fail-open behavior for steps
1–7 and then goes silent exactly where the two `git` subprocesses run (steps 8–9), so an
infrastructure failure there falls through to *deny*, which is the opposite of the rule the spec
set itself. During a rebase, `git rev-parse --abbrev-ref HEAD` returns the literal string `HEAD`,
so every source write gets blocked — and the spec's own closing note records a concurrent session
that was mid-rebase, so this is not hypothetical. "Fails frontmatter parsing" is never defined, so
one of the eight allow-scenarios cannot be turned into a test without the implementer inventing
the rule. And `awk`/`sed` sit in the pinned-versions table with no version at all, in a table whose
whole point is that the toolchain is pinned.

### Violations

| # | id | rule source | rule | where (spec) | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/coverage-gap` | `skills/writing-specs/SKILL.md:28` | Good, bad, and edge-case scenarios — state explicitly what wrong looks like; anything left implicit the agent infers | "Non-goals" (L378–384); Q4 (L96–101); "Deny message must contain" item 4 (L267–268); Registration (L165–167) | The matcher is `Edit\|Write\|NotebookEdit`, so any source write through the `Bash` tool (`sed -i`, `cat >`, `python -c`, `patch`) is unguarded — verified: none of the four existing `Bash`-matcher hooks (`git-guard`, `doc-guard`, `judge-guard`, `merge-guard`) inspects file writes — yet Non-goals lists only three holes and the mandated deny message asserts no bypass exists. |
| 2 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md:13` | Handle errors explicitly, never swallow them | Order of operations steps 8–9 (L186–191); "Fail-closed only at step 10" (L194–198) vs. Q3 (L87–95) | Steps 1–7 each name a ⊘ fail-open exit, but steps 8 and 9 state no failure behavior; if `git for-each-ref`, `git cat-file --batch`, or `git rev-parse --abbrev-ref HEAD` fails or returns empty, the only specified continuation is step 10 **deny** — contradicting Q3's own principle that infrastructure failure fails open. |
| 3 | `writing-specs/edge-cases` | `skills/writing-specs/SKILL.md:28` | Enumerate the edges | Step 9 (L190–191); design table (L52–59); Group B scenarios (L317–351) | `git rev-parse --abbrev-ref HEAD` returns the literal `HEAD` when detached (verified on git 2.50.1), so during any rebase, bisect, or detached checkout the branch is unclaimed and **every** source write is denied with a message advising `branch: HEAD`; the spec's own Notes (L417–421) record a concurrent session mid-rebase, so this state occurs in practice and is enumerated nowhere. |
| 4 | `writing-specs/ambiguity` | `skills/writing-specs/SKILL.md:20`, `:28` | A requirement you cannot phrase as Given/When/Then is one you have not decided; nothing left implicit | Step 7 (L184–185); Group A example 7 (L295); toolchain row (L240); Task 1 (L391) | "A file that fails to parse is skipped" and Scenario A7 "every `docs/features/*.md` fails frontmatter parsing" are untestable as written — the spec never defines what constitutes a parse failure (missing `---` fence? missing `phase:`? missing `branch:`?) nor what an unrecognized `phase:` value does, so a typo'd `phase: plannning` silently disables a CRITICAL gate and Task 1's test cannot be written without inventing the contract. |
| 5 | `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md:32`; `rules/core-conduct.md:21` | Pin the exact version of every library and tool | "Pinned toolchain" table, `frontmatter` row (L240); Group A example 4 (L292); step 4 (L176–180) | The frontmatter row's Version cell contains the tool names, not versions — `awk` is BWK awk 20200816 and `sed` is BSD sed on this machine, and the BSD/GNU split (`sed -i` argument form, `awk` extensions) is exactly the dialect trap the table pins `bash` 3.2.57 to avoid; separately, Scenario A4 names a fallback `python` interpreter that appears in no other section and carries no version, leaving it undecided whether the fallback (sibling convention `command -v python3 \|\| command -v python`) exists at all. |

### Verified true (adversarial checks that passed)

- `hooks/doc-guard.sh:149` is exactly `CODING_MEMORY.md|coding-memory/*|docs/*) has_doc=1; continue ;;` — the classification the spec claims to reuse.
- `hooks/git-guard.sh:22` is exactly the inline-regex trap comment the spec cites.
- `settings.json` `PreToolUse` matchers are exactly `Bash`, `Task|Agent`, `*` — the spec's "this is a fourth" claim holds. (`PostToolUse` already carries an `Edit|Write|NotebookEdit` block, so the matcher string is proven.)
- Pinned versions match this machine: bash 3.2.57(1) arm64-apple-darwin25, Python 3.9.6, git 2.50.1 (Apple Git-155).
- **Group C parser contract is empirically correct.** Probe on git 2.50.1: a present blob emits `<sha> blob <size>\n<content>` with **no** echo of the request; a missing object emits the request line verbatim + ` missing`. The spec's "consume in input order" conclusion is sound.
- Task ordering is clean: tasks 1/3/5/6 are tests, 2/4 implementation, 7–9 registration/docs, 10 dogfood — no task edits tests and implementation together (`rules/core-conduct.md:17`).
- ADR 0010's objection is quoted accurately (`docs/decisions/0010-*.md:42–43`).
- `hooks/git-guard.sh:89–90` does block `git commit` on main/master, so the narrowing's "the write cannot land on `main`" layering argument is sound.
- No absolute paths and no secrets in the spec.
- Architecture trade-offs (Q1 build-vs-defer, Q2 framing, Q6 bypass) are routed to the user rather than silently decided — `rules/core-conduct.md:21` satisfied.

### Not cited (deliberate)

- **Spec location** (`docs/features/` vs. `docs/superpowers/specs/`) — excluded by dispatch; the spec discloses the contradiction and resolves to the newer project-level ADR 0010.
- **No Mermaid diagram** despite a 10-step decision flow — `writing-specs:26` asks for visual aids, but ADR 0004 ("Make the Diagramming Standard Reachable, Not Enforced") is the project layer and states neither judge rubric scores for diagrams. Project rules win. Recorded as a note.
- **`## Verification` → `<Appended during review.>`** — not a TBD; it matches the canonical template at `skills/managing-session-memory/assets/feature-file-template.md:24`.
- **Copying `doc-guard.sh:149` rather than sharing it** — no hook in this repo sources a shared library; self-contained scripts are the house style (`rules/core-conduct.md:9`, match the surrounding structure).
- **Building despite ADR 0010's "when observed being skipped" deferral** — disclosed in Q1 and deferred to the user at the gate; per dispatch, the disclosure is judged, not the decision.

### Notes (non-blocking)

- `git cat-file --batch` appends a trailing `LF` after blob content (verified via `od -c`). Since each blob here is a whole multi-line markdown file, the parser must skip exactly `<size>` bytes **plus** one newline; the Group C table says only "then the content".
- The Group C safety argument ("ref names cannot contain `:` or whitespace") covers only the ref half of `<branch>:<path>`. A feature filename containing `:` or whitespace would break the first-colon split. Author-controlled, so low risk, but the claim reads as complete.
- Group C asserts a *subprocess count* as a behavioral test. Justified by the every-write hot path, but it couples the test suite to an implementation detail; consider asserting it as a performance note rather than a hard scenario.
- Task 7's "verified 2026-07-25" claim about `settings.json` is accurate as of this HEAD.
- Spec is 428 lines — within the file-size convention and readable end to end, which is the point of the review gate (`writing-specs:49`).

### Waivers

None. No user-waived violation ids were supplied for this round.

---

## Round 2 — 2026-07-25 — **FAIL** (4 violations, all new)

**HEAD:** `1befe03e2eb3b6b7b7782f3a10dddccb1bf61092` · **spec blob:** `fa68e7fa74cb168607bf69dce565d95e6dc081cb`
**Branch:** `worktree-phase-guard-hook` · **Spec:** 733 lines (was 429) · **Confidence:** high

### Layman summary

All five round-1 violations are genuinely fixed — I checked each one against the file rather than
taking the revision list's word for it. The Bash-tool hole is now a disclosed non-goal with an
honest deny message, steps 8–9 name their fail-open exits, detached HEAD is decided and tested,
the frontmatter contract is written out in three checkable clauses, and every pinned version in the
toolchain table matches what this machine actually reports (I ran them: bash 3.2.57, python3 3.9.6,
`python` genuinely absent, git 2.50.1, awk 20200816, BSD sed). Every cited line reference is exact:
`judge-guard.sh:28`, `doc-guard.sh:49`, `doc-guard.sh:149`, `git-guard.sh:22`, and
`pane-dispatch-guard.sh:43-50`. The four judgement calls are each argued in the spec, not merely
asserted.

The spec grew by 300 lines, and the growth introduced four new problems — which is the ordinary
cost of a large revision, not a sign the revision was wrong.

The most serious is bookkeeping that broke during the renumber: **task 8 now writes tests and
writes implementation in the same step**, which is the one testing rule core-conduct states as an
absolute, and which the task list's own preamble claims it obeys. The other three are places where
a round-2 addition stopped short of being buildable: the Gherkin `Background` still defines a
"guarded write" without `settings.json` even though three other sections now exempt it; the
once-per-session flag has no file path, no test override, and — in the *one* branch it exists to
serve, where python is missing — no way to read the session id it is keyed on; and the Group C
shim, which was pinned specifically so the test would measure something, logs only argv and so
cannot observe the stdin the fourth assertion is about.

Each fix is small. None requires reopening a design decision.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `core-conduct/test-impl-same-step` | `rules/core-conduct.md:17` | "Never edit tests and implementation in the same step — the test is the unbiased baseline." | Tasks — task 8 (L627–630) | Task 8 reads "Extend the test with Group A2 … **Then implement** the once-per-session flag", pairing test authorship with implementation inside one task, contradicting the list's own preamble at L606–607 ("Tests precede implementation in every pair"). |
| 2 | `writing-specs/contradictory-guarded-write-definition` | `skills/writing-specs/SKILL.md:20,28` | Ambiguity must surface in the Given/When/Then form; nothing central may be left implicit. | Scenarios — `Background` (L362–365); Q4 (L106–109) | The Background defines the term every later scenario invokes — "a guarded write is one whose path is NOT `CODING_MEMORY.md`, `coding-memory/*`, `docs/*`, or `.claude/*`" — and omits `settings.json`, which step 6 (L201–204), the unguarded-path scenario (L472–478) and Rollback (L277–280) all exempt; Q4 still reports the older list as "Carried as specified". |
| 3 | `writing-specs/underspecified-session-flag` | `skills/writing-specs/SKILL.md:25,28` | Contracts and data structures must be given, not improvised; edge cases enumerated. | "Two exits that must not be silent" (L265–268); Tasks — task 8 | The once-per-session flag is keyed "off the payload's `session_id` with `$CLAUDE_CODE_SESSION_ID` as fallback", but exit #1 fires precisely when no interpreter exists to parse the payload, so the primary key is unreadable by construction; no flag path, no test-time override, and no behaviour when both keys are empty (the siblings define `$STATE_DIR` and a literal `nosession` — `context-handoff-watch.sh:14,27-28,42-43`, `pane-dispatch-guard.sh:55`), leaving A2 example 1's "a second invocation adds none" unwritable. |
| 4 | `writing-specs/unverifiable-group-c-assertion` | `skills/writing-specs/SKILL.md:28` | State what correct looks like precisely enough that it can be checked. | Group C — "Mechanism, pinned" (L541–543) and the scenario's fourth Then (L556) | The pinned shim "appends its own **argv** to a counter file, then `exec`s the real `git`", which cannot observe stdin, yet the scenario asserts "the cat-file process is fed N*M lines of the form `<branch>:<path>`" — the one assertion the mechanism was pinned to make checkable is the one it cannot produce. |

### Round-1 violations — all resolved

| Round-1 id | Status | Evidence checked |
|---|---|---|
| `writing-specs/coverage-gap` | **resolved** | Fourth Non-goal (L584–594) + "Why the Bash hole does not sink the design" (L596–602); deny-message clause 4 now says "no bypass **environment variable** exists" (L356–357); Q6 qualified (L131–136). |
| `core-conduct/explicit-error-handling` | **resolved** | Step 8 "Either git call failing (nonzero exit) → ⊘" (L214); step 9 "Nonzero exit or empty output → ⊘" (L216); A1 examples 7–9; plus the no-local-branches scenario (L398–404) pinning empty ≠ failure. |
| `writing-specs/edge-cases` | **resolved** | Design-table row (L60), the detached-HEAD paragraph deciding allow-silently with reasons (L62–69), step 9 ⊘, A1 example 10. |
| `writing-specs/ambiguity` | **resolved** | "Frontmatter contract" (L233–251) — three clauses, optional `branch:`, forward-compatible unknown keys, skip-never-guess — plus eight Group A3 scenarios. |
| `writing-specs/pinned-versions` | **resolved** | Toolchain table now carries versions, not names, and each was independently re-run on this machine: bash `3.2.57(1)-release (arm64-apple-darwin25)`, python3 `3.9.6`, `python` absent, awk `20200816`, sed BSD (rejects `--version`). Dialect constraints stated for awk and sed. |

### Adversarial checks requested by the dispatch

1. **Audible exits vs. the Contracts output rule** — no contradiction. L346–348 carves out exactly
   two exceptions and holds stdout empty on every path. The A1/A2 assertion split matches.
2. **`pane-dispatch-guard.sh:43-50`** — accurate for what the spec claims of it (stdin `session_id`,
   `$CLAUDE_CODE_SESSION_ID`, and surfacing a divergence between them). It does not establish
   flag *writing* — it only reads a flag the dispatcher wrote. The write-a-flag-once precedent is
   `context-handoff-watch.sh:14,27-28,42-43`. Folded into violation 3 rather than cited separately.
3. **`judge-guard.sh:28` / `doc-guard.sh:49`** — both exact: `py=$(command -v python3 || command -v python) || py=""`.
   `doc-guard.sh:149` and `git-guard.sh:22` also exact.
4. **Task renumbering** — pairs 1/2, 3/4, 5/6 are correctly test-then-implement. Task 8 breaks the
   rule outright (violation 1). Tasks 7 and 9 write tests for behaviour implemented back in task 6;
   that is test-after, not same-step, so it clears the invariant but forfeits the red-first signal.
5. **Counting-`git` shim** — the `exec` of a pre-captured absolute `git` cannot recurse; the hook
   resolving `git` by bare name means a `PATH`-prepended shim does intercept it. Sound for argv
   counting. It cannot serve the stdin assertion (violation 4), and the shim must be installed
   *after* fixture setup or the harness's own `git` calls pollute the counter.
6. **The four judgement calls** — each justified, not merely stated: detached HEAD (transient
   mechanical state, Q3 blast radius, per-write warning would be noise); unrecognized `phase:`
   (skip-never-guess, fails open per Q3, audible when it is total); `settings.json` exempt (a guard
   that can block edits to its own off switch is a footgun, tied to Rollback path 2); shim over
   wall-clock (a timing threshold is flaky and gets deleted the first time CI reddens).

### Notes (non-blocking)

- `git` is the only tool whose behaviour the design depends on structurally — `for-each-ref`,
  `cat-file --batch` output shape, `rev-parse --abbrev-ref` returning literal `HEAD` — and it has
  no row in the "Pinned toolchain" table, though `2.50.1` is pinned twice in prose (L63, L566).
  Adding the row costs one line and removes the asymmetry.
- **Still open from round 1:** the Group C parser table says a blob is `<sha> blob <size>` "then the
  content"; `cat-file --batch` also emits a trailing `LF` after the content (verified round 1 via
  `od -c`). A parser that skips exactly `<size>` bytes desynchronises on the second record.
- `docs/features/` that exists but holds zero `.md` files makes "every file was skipped" (step 7)
  vacuously true, so the A2 audible line would fire once per session in such a repo forever. The
  same step-3 `stat` also passes if `docs/features` is a regular file.
- Rollback path 3 asserts "a non-executable hook is skipped by the harness". Hooks are registered as
  direct paths (`$HOME/.claude/hooks/<name>.sh`), so `chmod -x` yields exit 126, and L342–344 of this
  same spec calls any nonzero-non-2 exit a defect. Unverified claim in a last-resort recovery path.
- `settings.json` is exempted by root-relative *name*, in every repo this global hook fires in, where
  it is as likely to be application config as this hook's off switch.
- A malformed feature file is skipped silently whenever at least one well-formed file survives
  (A3 asserts `bad.md` is *not* named). The `phase: plannning` typo therefore still degrades quietly
  in a multi-file repo; naming skipped files in the deny message would close the gap for one line.
- The `python` fallback is retained "for parity with the siblings, not because it is exercised here"
  and costs py2/py3-compatible syntax on the primary path. Defensible as house consistency
  (`rules/core-conduct.md:9`, match the surrounding style); worth revisiting rather than citing.
- No `writing-secure-code` violation. The `<branch>:<path>` lines fed to `cat-file --batch` are
  repo-controlled and passed on stdin, not through a shell; payload paths are pattern-matched, not
  evaluated; the deny message carries no secrets. Ref-name safety is argued explicitly (L575).
- Spec is 733 lines. Still readable end to end, but it is now over half judge-round scaffolding
  (L651–717); consider moving the round logs out once the gate opens, so the durable artifact stays
  the design.

### Waivers

None. No user-waived violation ids were supplied for this round.
