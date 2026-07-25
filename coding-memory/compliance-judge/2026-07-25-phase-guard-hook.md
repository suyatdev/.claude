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
