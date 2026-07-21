# Observability Judge Verdict — pane orchestration (architecting, advisory)

- **Repo:** `.claude` · **Branch:** `feature/pane-orchestration`
- **HEAD:** `9b6ab0ad339b479ce9c2fd95b0d02cde1dbcfe82`
- **Stage:** architecting (advisory — does not gate)
- **Artifact:** `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md` +
  `docs/decisions/0007-pane-orchestration-supersedes-judge-terminal-enforcement.md`
  (one docs-only commit off `main`)
- **Test command:** none yet (nothing implemented). In its place I ran the spec's own
  declared checks and probed its platform assumptions: both Mermaid blocks pass
  `validate-diagrams.sh`; `claude` 2.1.216 confirms `--bare`, `--agent <name>`, `-p`, and
  `--output-format` all exist; `judge-guard.sh` verdict contract confirmed untouched;
  `CODING_MEMORY.md` item 0b supersession marker confirmed; retired branch confirmed intact
  with its judged spec aboard.
- **Risk:** medium · **Confidence:** high

## What was changed

A design (no code yet) for running the "big" helper agents — the two judges and plan
implementers — in their own visible terminal panes as real separate Claude sessions,
instead of invisibly inside the main session. Results come back through a file the main
session watches, extending the existing judge-verdict file pattern. A second hook watches
context usage and at 75k tokens opens a "press Enter to take over" pane rather than
switching automatically. Four terminal adapters (cmux, tmux, iTerm2, Terminal.app), and
everything degrades to today's in-process behavior when a pane can't open. ADR 0007
records that this absorbs and retires the parked judge-terminal-enforcement project.

## Does it do what you wanted?

Yes, at the design level. All four verbatim user requirements map to a named component,
the locked brainstorm decisions match the decisions summary one-for-one, the supersession
was an explicit user choice with its cost (no improved always-run guarantee for the
judges) stated plainly rather than hidden, and the new-instruction gate was walked with
the classification recorded in the spec. The reasoning is sound throughout — hook-only
interception was rejected on a verified platform fact (hook timeouts fail open), and
auto-switch at 75k was rejected to avoid two sessions racing on one repo.

## What could go wrong / what I'm unsure about

Two design gaps the spec does **not** list among its open questions:

1. **The adapter-failure fallback is unreachable as specified.** The error table promises
   "adapter failure → guard allows in-process dispatch," but the guard's deny condition
   keys only on `terminal-detect.sh` output, which doesn't change when an adapter fails
   (e.g. iTerm2 without the Automation grant). After a failed dispatch, the in-process
   retry gets denied again — a potential deny-loop with no specified escape mechanism.
2. **`--bare` skips hooks — including the Tier-1 guards.** The pinned pane invocation
   (`claude --bare -p --agent …`) was inherited from the judge-only superseded spec, where
   it was harmless. Generalized to plan *implementers*, it means pane sessions that make
   commits run without git-guard, doc-guard, or judge-guard. The recursion story doesn't
   need `--bare` (the `CLAUDE_PANE_AGENT` short-circuit covers it), so this flag choice
   deserves a deliberate revisit for implementers.

Smaller items: the spec's error table says the `CLAUDE_PANE_AGENT` early-exit was
"already locally patched per ADR 0006" — grep finds zero occurrences of that variable
anywhere; the parenthetical refers to the hooks having precedent for local patching, but
an implementer could misread it as done and skip the patch. ADR 0007 and the spec say the
superseded spec was "judged through round 4," but the retired branch holds spec verdicts
through round 6 — the discarded judged work is understated in the record that justifies
discarding it. The Testing section cites `scripts/validate-diagrams.sh`; the real path is
`skills/diagramming-technical-docs/scripts/validate-diagrams.sh`. And the watcher spec
doesn't say the fired-flag check happens *before* transcript parsing — on a
PostToolUse `*` matcher, that ordering is what keeps every tool call cheap.

## What I'd double-check before merging (this doc) / before implementing

- Add the two gaps above to the spec's open questions or fix them in the text: give the
  guard a channel to learn of dispatch failure (e.g. a per-session fallback state file the
  dispatcher writes), and decide `--bare` vs. hooks-on per agent class.
- The spec's own listed spikes stand: PreToolUse matcher name (`Agent` vs `Task`), cmux
  `new-split` workspace targeting from a non-TTY hook process, and whether `--agent <name>`
  still loads `~/.claude/agents/*.md` under `--bare` (both judge agents live there, not in
  a plugin — if `--bare` skips user agent definitions too, the pinned invocation breaks).
- Correct the round-4/round-6 count in ADR 0007 and the validator path in Testing.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| intent | pass | All 4 verbatim requirements traced to components; decisions match summary |
| execution | concern | Nothing runnable yet (expected); adapter-failure fallback internally inconsistent; spikes unverified though all pinned CLI flags confirmed on 2.1.216 |
| trajectory | pass | Alternatives weighed with verified platform facts; supersession explicitly user-decided |
| regression | concern | `--bare` disables Tier-1 guard hooks inside pane implementer sessions; PostToolUse `*` watcher cost hinges on unspecified flag-check ordering |
| context_budget | pass | Skill on demand, hooks are scripts, one-line stubs; triage gate walked |
| traceability | pass | Diagrams validate; two doc nits (validator path, ambiguous "already patched" parenthetical) |
| success_masking | pass | Waits bounded (900s); fallback emits a notice; dropped always-run guarantee stated plainly, not hidden |
| intent_drift | pass | Docs-only commit; absorption user-sanctioned; scope boundaries explicit |
| checkpoint | pass | Single clean commit on feature branch; old-branch deletion deferred to user |
| audit_trail | concern | ADR 0007 understates discarded work: spec judged through round 6, not 4 |

## Concerns

1. Adapter-failure fallback unreachable: guard deny keys only on terminal-detect, so after
   a failed dispatch (iTerm grant missing) the in-process retry is re-denied — the error
   table row has no mechanism behind it.
2. `claude --bare` skips hooks: pane implementers would commit without
   git-guard/doc-guard/judge-guard; flag set inherited from the judge-only superseded spec.
3. Verify `--agent <name>` loads `~/.claude/agents/` definitions under `--bare` (judges are
   user-level agents, and `--bare` skips settings/plugins).
4. ADR 0007 and spec say "judged through round 4"; retired branch holds spec verdicts
   through round 6.
5. "Already locally patched per ADR 0006" is misreadable as the `CLAUDE_PANE_AGENT` exit
   existing today — grep finds zero occurrences.
6. Watcher should check the fired-flag before parsing the transcript; ordering unspecified
   on an every-call matcher. Testing section's validator path is wrong
   (`skills/diagramming-technical-docs/scripts/validate-diagrams.sh`).
