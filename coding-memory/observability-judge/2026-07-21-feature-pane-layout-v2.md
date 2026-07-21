# Observability Judge Verdict — pane-layout-v2 (architecting, round 1, advisory)

- **Repo:** `.claude` · **Branch:** `feature/pane-layout-v2`
- **HEAD:** `bb4050b90a65e24bdabe919c03c20e2a3100a362`
- **Stage:** architecting (advisory — does not gate)
- **Artifact:** `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md`
  (one docs-only commit off `main`, 342 lines)
- **Test command:** none given (no implementation exists). In its place I verified the
  spec's claims against the checkout: the current `panes/adapters/cmux.sh` is exactly the
  naive `new-split down` + `send` + `rename-tab` path the spec calls the legacy floor;
  `run-pane-agent.sh` matches the marker-insertion claim (atomic result write exists,
  `fail_early` runs before it, so "no marker on early failure" holds structurally); and I
  re-ran `validate-diagrams.sh` on the spec — its Mermaid block passes.
- **Risk:** low · **Confidence:** high

## What was changed

A design (no code yet) that teaches the cmux pane dispatcher to arrange agent panes like
a deliberate desk layout instead of a growing pile: your main session stays far-left,
implementer agents fill a 2x2 grid in the middle (built one cell at a time as needed),
and everything else — judges, handoff, extras — goes in a single far-right column, with
extra agents becoming tabs once the 6-pane cap is reached. Instead of keeping a map of
which pane is which (which dies when the app restarts), the adapter re-reads the live
pane tree on every dispatch and recognizes its own panes by a strict title convention,
like name tags. Finished agents leave an on-disk "done" marker so their pane can be
recycled; a crashed agent leaves no marker, so its pane is preserved for post-mortem.
Anything the layout logic can't figure out falls back to today's dumb split — the smart
path can never make pane dispatch *less* available than it is now.

## Does it do what you wanted?

Yes, at the design level. The user's five verbatim requirements each map to a mechanism,
and the five brainstorm decisions match the decisions summary one-for-one. The reasoning
is evidence-driven, not lucky: the persisted-slot-map alternative was killed by an actual
live probe (cmux refs die with the app process), title-based recognition was chosen
because the probed `--json tree` is flat (positional derivation genuinely can't work),
and the title-restamp alternative was rejected with specific stated costs. The one scope
extension beyond the literal Q&A (recycling finished aux surfaces) is explicitly flagged
for user sign-off rather than smuggled in — the right way to extend. Error handling is
the spec's strongest section: every failure row lands in "degrade to legacy, no
cooldown," preserving PR #23's contract that cooldown means "terminal unusable," never
"layout confused." Toolchain is pinned; the four unverified platform assumptions are
quarantined in their own section, each with a degrade path, none load-bearing for the
fallback.

## What could go wrong / what I'm unsure about

Nothing fails; one dimension is a concern:

1. **"Run dir missing ⇒ finished" is the one silent-success rule** (success_masking:
   concern). If `state/runs/<id>/` disappears for any reason other than the 7-day
   cleanup — a manual tidy-up, an aggressive script — a still-occupied pane looks
   finished and `respawn-pane` will destroy a live agent's pane and scrollback. Bounded
   (the agent's result write was doomed anyway once its run dir vanished) but it's the
   only place the design infers success from absence.
2. **The two hottest paths ride the two least-verified primitives.** Reuse (priority 1)
   depends on `respawn-pane --command` quoting semantics (an open question), and aux
   column creation depends on unverified `new-pane --direction right` (Assumption 4). A
   mis-quoted respawn could "succeed" at the cmux level while leaving a dead pane — only
   the result-file wait timeout would catch it, slowly. The live-probe checklist covers
   both, but it must actually run before the code is trusted.
3. **The legacy floor must stay byte-faithful.** The whole safety argument rests on
   "degraded = exactly today's behavior," while the file containing that behavior gets
   rewritten around it. If the refactor subtly changes the legacy call sequence, every
   degraded session inherits the change invisibly.
4. **`PANE_DRYRUN` is redefined** (derive-then-print). Existing green assertions keep
   passing, but they now exercise different code depending on whether cmux is present —
   the same test means two different things on two machines.
5. Housekeeping: the working tree carries an unrelated modified file
   (`chrome/chrome-native-host`) that is not part of this branch's commit — keep it out
   of future feature commits.

## What I'd double-check before merging

- Run the live-probe checklist first thing at implementation and log results to the
  branch: `respawn-pane --command` quoting, `new-pane --direction right` geometry,
  workspace scoping (Assumption 1).
- Get the explicit user sign-off on the flagged aux-reuse extension before it's coded.
- In Layer-2 tests, assert the degraded path's argv sequence verbatim against today's
  `cmux.sh` behavior (`new-split down` → `send` → `rename-tab`), not just "a split
  happened" — that pins the legacy floor.
- Honor the falsification-by-mutation mandate especially on the "Tier 1 never writes a
  cooldown flag" test — it protects the availability invariant everything else leans on.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | 5/5 verbatim requirements mapped; brainstorm decisions locked and mirrored |
| execution | pass | Design-stage: diagram validated (re-run), legacy-path and marker claims verified against current code, toolchain pinned; unverified primitives quarantined with degrade paths |
| trajectory | pass | Alternatives killed by live probes and platform facts, not vibes; rejections carry stated costs |
| regression | pass | `open_pane` contract frozen, other adapters untouched, cooldown scope narrows only; legacy floor is the guarded invariant |
| context_budget | pass | Skill doc touch is on-demand; no always-on rule/prompt growth |
| traceability | pass | Verbatim requirements, decision table, error table, flagged-assumption section, PR #23 lineage |
| success_masking | concern | "Missing run dir = finished" infers success from absence; respawn mis-quote could leave a dead pane caught only by timeout |
| intent_drift | pass | cmux-only scope held; sole extension (aux reuse) explicitly flagged for sign-off |
| checkpoint | pass | One clean docs-only commit; trivial revert. Unrelated `chrome/chrome-native-host` working-tree mod noted, not committed |
| audit_trail | pass | Dated/statused spec, prior-spec and PR lineage, model-gate note recorded |

## Concerns

- "Run dir missing ⇒ finished" can mark a still-occupied pane reusable if `state/runs/` is cleaned out-of-band; respawn would destroy a live pane
- Reuse path depends on unresolved `respawn-pane --command` quoting; aux column on unverified `new-pane --direction right` — live-probe checklist is load-bearing
- Legacy degradation floor must stay byte-identical to today's cmux.sh; Layer-2 tests should assert the exact legacy argv sequence
- `PANE_DRYRUN` redefinition means existing green assertions exercise different code on cmux vs cmux-less machines
- Aux-surface reuse extension flagged in-spec but user sign-off not yet granted
- Unrelated uncommitted working-tree change (`chrome/chrome-native-host`) rides the branch checkout
