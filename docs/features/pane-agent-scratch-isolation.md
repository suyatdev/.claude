---
phase: planning
model_tier: high
branch: TBD
---

# Parallel pane agents share a scratch directory and overwrite each other

Queued 2026-09-04 out of round 10 of `docs/features/secret-filename-case-blindness.md`
(branch `fix/secret-filename-case-blindness`, HEAD `bb15b29`).

## What happened

Two judges — `compliance-judge` and `observability-judge` — were dispatched in parallel into
separate panes against the same repository. The observability judge reported, unprompted,
that another judge working in the same `/tmp` directory had overwritten its script and deleted
its working copies, and that it produced one wrong measurement before it isolated itself; it
added that parallel judges must not share a scratch path, because a contaminated replay yields
a plausible number rather than an error.

Stated in this card's own voice, not quoted. The judge said it twice in different words — once
in its pane report and once in its persisted verdict — and **neither travels with this branch**:
pane reports live in a session scratchpad under `/tmp`, and verdict markdown is gitignored
(`.gitignore:114`; only `verdicts.jsonl` is tracked). A blockquote here would promise a
verbatimness no reader of this branch could check, which is precisely the defect this card is
about.

It recovered on its own. The round-10 verdicts are not in doubt: the finding it eventually
reported was independently reproduced in the dispatching session. What is in doubt is every
*future* parallel dispatch, because the failure is silent — a clobbered mutation or a
half-deleted clone still runs and still prints a number.

## Why it happens

`panes/dispatch-pane-agent.sh` gives each dispatch a unique **run directory** (`new_run_dir`,
mode 700, holding `prompt.md` and `launch.sh`) and a unique **result file**
(`$agent_type-$(date +%s)-$$-$RANDOM.md`, per obs final-review F1). Both were deliberately
made collision-proof.

Nothing equivalent exists for the agent's own **working** scratch. The dispatcher never tells
the agent where to put a scratch clone or a mutation script, and neither
`agents/compliance-judge.md` nor `agents/observability-judge.md` names a path — verified by
grepping both for `tmp`, `scratch` and `mktemp`: no matches. So each agent invents one. Two
agents handed near-identical prompts invent the *same* obvious path, which is precisely the
case the dispatcher's other two uniqueness guarantees were written to prevent.

## Shape of the fix (to be designed, not decided here)

The run directory already exists, is already unique, and is already mode 700. The obvious
candidate is to hand the agent a `work/` subdirectory of it and say so in the launcher's
environment or the prompt preamble. Open questions a spec must settle:

- Does the path reach the agent as an environment variable, a prompt preamble, or both? The
  agent must actually *use* it — an unread variable fixes nothing, and the failure stays
  silent either way.
- `cleanup_stale` currently prunes run directories. A scratch clone of a repository is far
  larger than a prompt and a launcher; the retention rule needs revisiting or the fix trades a
  correctness bug for a disk-space one.
- Whether this belongs to the dispatcher (covers every agent type, including workers, which
  have the same exposure) or to the two judge definitions (narrower, but leaves
  `general-purpose` fan-out uncovered — the exact shape the pane-split policy exists to run).
- Whether anything should *verify* isolation rather than merely provide it, given that the
  observed failure mode is a plausible wrong number rather than an error.

## Not done on the originating branch

`panes/` is implementation code and `fix/secret-filename-case-blindness` is a documentation
and test branch in `phase: review`. Mixing them would violate the root-cause-only rule in
`rules/core-conduct.md`. The immediate exposure was handled in that session by writing an
explicit unique scratch path into each judge's dispatch prompt by hand; that is a per-dispatch
workaround, not a fix, and it protects only prompts an author remembers to write it into.
