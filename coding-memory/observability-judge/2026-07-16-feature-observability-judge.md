# Observability Judge Verdict — 2026-07-16

**Repo:** `.claude` · **Branch:** `feature/observability-judge` · **Stage:** `implementation`
**HEAD:** `381bd79eea3f9f728be28d3bb23c431226286410`
**Base:** `main` (merge-base `bec7eef7c75ef215f64891c8b5b824546d06c9b3`)
**Test command run:** `bash hooks/judge-guard.test.sh` → **15 passed, 0 failed** (exit 0), verified live in this run.

This is the final verdict: all five planned pieces are now committed (agent, hook + tests +
settings wiring, skill, gate stub + catalog line, ADR + verdict-store README). A prior
mid-branch dogfood verdict exists at `2026-07-16-observability-judge.md` (HEAD
`fdbd7b943a1245dda0672b8c6601096e3a059292`, only 2 of 5 pieces done at the time); this entry
supersedes it and scores the complete feature.

## What was changed

This branch builds a "does this change actually do what we meant, safely, and can we tell
later if it didn't" checker for this `.claude` config repo, then wires it in so it can't be
skipped. Five pieces, all committed: (1) the `observability-judge` subagent, which reads a
diff plus a plain-English decisions note, scores it against ten yes/no/concern checks, and
writes the result to a log; (2) `hooks/judge-guard.sh`, which blocks `gh pr create` unless
that log has a fresh entry for the exact commit being shipped, plus a 15-case test harness
that feeds it real stdin JSON (the actual code path, not a shortcut) and is wired into
`settings.json`; (3) the `running-the-observability-judge` skill telling the main agent when
to invoke the judge and how to relay its answer; (4) a one-line gate stub in
`rules/gates.md` and a one-line catalog entry in `CLAUDE.md` making the whole thing
discoverable and un-skippable; (5) an ADR and a verdict-store `README.md`. The command
classifier went through two rounds of review-driven hardening — a substring false positive
(the phrase anywhere in a command, including its own commit message) fixed by anchoring, then
an anchored-regex bypass (a quoted-space `FOO="a b" gh pr create` prefix could sneak past)
fixed by switching to `python3`'s `shlex` for real shell-quote-aware tokenizing. A final
whole-branch review then caught two more Important issues and fixed both: the verdict
markdown filename now sanitizes `/` → `-` in the branch name (so `feature/x` and `fix/x`
can't collide, and a slash can't create a stray subdirectory), and `hooks/README.md` — which
had said only `git-guard.sh` was installed — now correctly names all three hooks
(`git-guard.sh`, `doc-guard.sh`, `judge-guard.sh`) actually wired into this repo's
`settings.json` today.

## Does it do what you wanted?

Yes. Every component in the design doc's file manifest exists and matches its stated
responsibility; I checked each one against `docs/superpowers/specs/2026-07-16-observability-judge-design.md`
directly rather than taking the summary's word for it. The 15 hook tests pass, and I
re-ran them myself in this session — not just reported to me. Commit history
(14 commits since the merge-base) shows a clean, incremental, TDD-shaped trajectory: spec →
plan → ADR → hook-with-tests → two review-caught fixes each with its own regression test →
agent → a self-dogfooding verdict run → skill → gate wiring → a final review pass that fixed
two more things. `settings.json` parses as valid JSON with `judge-guard.sh` correctly
appended after `git-guard.sh` and `doc-guard.sh` in the `Bash` `PreToolUse` chain. I also
independently exercised a path the test suite does *not* cover — an `rtk`-wrapped command
(`rtk gh pr create --fill`) — and confirmed by hand that the classifier's documented
`rtk`-unwrapping actually works (correctly blocked with no verdict store present), since RTK
rewrites commands in this exact environment and an untested code path here would matter.

## What could go wrong / what I'm unsure about

- **The gate is global, not per-repo.** `judge-guard.sh` reads/writes under
  `$HOME/.claude/coding-memory/observability-judge/`, and is wired into the *global*
  `~/.claude/settings.json`. From this commit forward, **every** `gh pr create` in **every**
  repo on this machine is blocked unless that repo's branch+HEAD has a fresh implementation
  verdict or the caller passes `JUDGE_EXEMPT=<reason>`. This is the explicit, accepted design
  (the ADR and spec say so), but it's a real behavioral change with immediate blast radius
  beyond this repo — including any non-interactive/CI script that calls `gh pr create` and
  has no way to run the subagent or pass an env var. Worth confirming that's genuinely
  intended for every project, not just this one, before it ships.
- **One code path is exercised by hand-testing, not by the automated suite.** The classifier
  strips a leading `rtk` wrapper (mirroring `git-guard.sh`'s precedent, since RTK's own hook
  rewrites commands ahead of this one), but none of the 15 committed test cases cover
  `rtk gh pr create ...`. I verified it works, but the suite itself doesn't guard against a
  future edit silently breaking that branch — worth adding one case.
- **A stale artifact from before the filename fix still sits in the store.** The prior
  dogfood verdict's markdown file is named `2026-07-16-observability-judge.md`, not
  `2026-07-16-feature-observability-judge.md` — i.e. it dropped the `feature/` prefix
  entirely rather than sanitizing the slash, which looks like exactly the naming bug the
  final review fixed in the *code*, just never retrofitted onto the *already-committed file*.
  It doesn't collide with anything today and doesn't affect the hook (which only reads
  `verdicts.jsonl`), but the store now holds one file that doesn't match its own documented
  `<YYYY-MM-DD>-<branch_slug>.md` schema in `README.md` — a small, harmless inconsistency in
  an otherwise careful audit trail.
- **The chained-command gap is real, documented, and accepted, not hidden.** `foo &&
  gh pr create ...` still isn't caught (same tradeoff `git-guard.sh` already makes), and the
  test suite explicitly asserts this passes rather than pretending it's covered — that's the
  right way to document a known gap, but it is still a way past the gate for someone who goes
  looking for one.

## What I'd double-check before merging

1. Confirm the global, cross-repo blast radius of `judge-guard.sh` is genuinely wanted for
   every project on this machine, including any script or CI job elsewhere that calls
   `gh pr create` non-interactively and can't run the judge or set `JUDGE_EXEMPT`.
2. Add one test case for the `rtk`-wrapped form (`rtk gh pr create ...`) so the classifier's
   documented behavior stops relying on manual spot-checks.
3. Either rename the stale `2026-07-16-observability-judge.md` to match the corrected
   `<date>-<branch_slug>.md` schema, or add a short note explaining it predates the filename
   fix — small, but it's the one loose thread in an otherwise tight audit trail.
4. Spot-check one more shape outside the current 15 tests: multiple chained env-assignments
   before a semicolon-separated `gh pr create` (`export FOO=x; gh pr create ...`) — not a
   leading-prefix form, so not currently exercised, and worth knowing whether it's caught or
   falls into the same documented `&&` gap.

## Dimension scores

| Dimension | Rubric | Score |
|---|---|---|
| Intent | Evaluation | pass |
| Execution | Evaluation | pass |
| Trajectory | Evaluation | pass |
| Regression | Evaluation | concern |
| Context budget | Evaluation | pass |
| Traceability | Observability | pass |
| Success masking | Observability | pass |
| Intent drift | Observability | pass |
| Checkpoint | Observability | pass |
| Audit trail | Observability | concern |

## Concerns (short form)

- `judge-guard.sh` is a global gate: every `gh pr create` in every repo on this machine is now blocked without a fresh verdict or `JUDGE_EXEMPT` — intended, but confirm the cross-repo/CI impact is acceptable.
- The `rtk`-wrapper-stripping code path is untested by the automated suite (verified by hand in this run, not by a committed test case).
- The pre-fix dogfood verdict file (`2026-07-16-observability-judge.md`) still uses the old, buggy naming scheme and wasn't renamed to match the corrected `<date>-<branch_slug>.md` schema.
- The chained-command gap (`foo && gh pr create`) is real and documented, not a hidden bypass, but remains a way past the gate.

**risk=low confidence=high**
