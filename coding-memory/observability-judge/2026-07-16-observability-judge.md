# Observability Judge Verdict — 2026-07-16

**Repo:** `.claude` · **Branch:** `feature/observability-judge` · **Stage:** `implementation`
**HEAD:** `fdbd7b943a1245dda0672b8c6601096e3a059292`
**Base:** `main` (merge-base `bec7eef7c75ef215f64891c8b5b824546d06c9b3`)
**Test command run:** `bash hooks/judge-guard.test.sh` → **15 passed, 0 failed** (exit 0), verified live in this run.

This is a dogfood run: the judge scoring the branch that built the judge itself. Note up front —
at this HEAD, only two of the four planned components are committed: the `observability-judge`
agent and the `judge-guard.sh` hook + tests + settings wiring. The `running-the-observability-judge`
skill and the `rules/gates.md` stub / `CLAUDE.md` catalog line are later tasks, not yet committed.
This verdict scores what exists, not the pending work.

## What was changed

This branch adds a "does this change actually do what we meant, safely, and can we tell later
if it didn't" checker for this `.claude` config repo. Two pieces landed so far: (1) an agent
(`agents/observability-judge.md`) that reads a diff plus a plain-English "here's what we decided
and why" note, scores it against ten yes/no/concern checks, and writes the result to a log; (2) a
guard hook (`hooks/judge-guard.sh`) that blocks `gh pr create` unless that log has a fresh entry
for the exact commit being shipped — like a "did you check the fire extinguisher" sign taped to
the exit door. The hook's command-detection went through two rounds of hardening: round 1 fixed a
false-positive that blocked its own commit message; round 2 (found by review, not by a live
failure) closed a bypass where a quoted env-variable prefix could sneak past the check.

## Does it do what you wanted?

Yes, for the slice that's built. The hook's 15 tests pass, and I re-ran them myself just now —
they weren't just reported to me, they're green in this exact session. The tests exercise the
hook the way it will really be called (JSON piped over stdin), not a shortcut version, which is
the right way to test a hook. The agent side is exactly what's being dogfooded right now: this
verdict is being produced by literally running the thing the branch built.

## What could go wrong / what I'm unsure about

- **The gate is already live for every repo on this machine, not just this one.** `judge-guard.sh`
  is wired into the *global* `~/.claude/settings.json`, and that file is read from disk as-is —
  git branch doesn't matter to the running harness. So right now, before the companion skill and
  gate-stub land, any `gh pr create` anywhere on this machine is blocked unless someone either
  passes `JUDGE_EXEMPT=<reason>` or knows to invoke the `observability-judge` agent by name. The
  hook's own block message tells the user to "see running-the-observability-judge" — a skill file
  that does not exist on disk yet. That's a dangling pointer for a few commits until Task 4 lands.
  It's not a functional break (the escape hatch works, and the agent is directly invocable), but
  it's a real, immediate source of friction if an unrelated PR needs to go out in the interim.
- **The first version of the hook had a bug that blocked its own commit.** That's a good sign the
  system is being dogfooded for real, but it also means the initial test suite didn't think to
  cover "the guard phrase shows up inside a commit message" until it happened live. The fix was
  clean and the regression test was added afterward, but the fact it wasn't anticipated up front
  (this repo has hit "phrase matched anywhere in the command" bugs before, per the hooks README)
  is worth noting rather than smoothing over.
- **Minor:** `hooks/README.md` documents the other hooks (`git-guard.sh`, `checkpoint-before-modify.sh`,
  etc.) but not `judge-guard.sh` — though to be fair, `doc-guard.sh` isn't documented there either,
  so this is an existing gap this branch didn't introduce, just didn't close.
- I can't score the skill, the gate stub, or the `CLAUDE.md` catalog line because they don't exist
  yet on this branch — that's expected per the stated scope, not a defect, but it means the "is this
  discoverable/un-skippable" half of the design is still unverified.

## What I'd double-check before merging

1. Before opening the PR, confirm Tasks 4 and 5 (skill + gate stub + catalog line) are actually
   committed, and that the hook's block message and the skill's existence line up — i.e. by the
   time this ships, "see running-the-observability-judge" should resolve to a real file.
2. Consider whether the window between "hook is live" (this commit) and "skill/gate exist" (later
   commits) is acceptable to have shipped to `main` in that order, or whether it's worth squashing
   so the gate and its explanation land together.
3. Spot-check the `shlex`-based classifier against one more shape not in the current 15 tests:
   multiple chained env-assignments mixed with `export FOO=x; gh pr create ...` — the semicolon
   form isn't a single leading-assignment prefix and isn't currently exercised.
4. Confirm `hooks/README.md` gets a `judge-guard.sh` entry at some point (even if not blocking this
   PR, given `doc-guard.sh` has the same gap).

## Dimension scores

| Dimension | Rubric | Score |
|---|---|---|
| Intent | Evaluation | pass |
| Execution | Evaluation | pass |
| Trajectory | Evaluation | concern |
| Regression | Evaluation | concern |
| Context budget | Evaluation | pass |
| Traceability | Observability | pass |
| Success masking | Observability | pass |
| Intent drift | Observability | pass |
| Checkpoint | Observability | pass |
| Audit trail | Observability | pass |

## Concerns (short form)

- Hook already live-blocks `gh pr create` globally, mid-branch, before the skill/gate that explain it exist.
- Hook's own block message references a not-yet-existent skill file at this HEAD.
- Round-1 hook bug (self-blocking substring match) was caught reactively, not anticipated by the initial test design, despite a documented prior lesson in this repo.
- `hooks/README.md` doesn't list `judge-guard.sh` (pre-existing gap, shared with `doc-guard.sh`).

**risk=low confidence=medium**
