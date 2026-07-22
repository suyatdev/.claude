# Brainstorm: pane-layout v2 (structured workspace layout)

**Status: INTAKE ONLY — clarifying questions not yet asked.** Captured at the 2026-07-21
~82k-token freshness checkpoint so a fresh session can resume the brainstorm without re-deriving
anything. Follow-on to pane orchestration (PR #23, `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md`).

## User requirements (verbatim intent, 2026-07-21)

All panes live in ONE workspace; split direction depends on what triggered the dispatch:

1. Sub-agent implementation tasks → 5-pane layout: far-left = main session, each subagent in a
   quadrant (2x2) to the right of it.
2. Any additional pane opens to the right of the quadrant, as a new session.
3. Full layout: far-left pane = main session · middle pane = 2x2 quadrant of subagents/spawns ·
   far-right pane = additional.
4. Sessions past the 6th always open as a new tab ON the 6th (far-right) pane.
5. Hard cap: 6 panes per workspace.

```
+--------+-----------+-----------+
|        | SA1 | SA2 |           |
|  main  |-----+-----| additional|
|        | SA3 | SA4 | (tabs >6) |
+--------+-----------+-----------+
```

## Current-system facts (verified this session)

- `panes/adapters/cmux.sh` is layout-blind: every dispatch is `new-split down` targeting the
  calling workspace via `$CMUX_WORKSPACE_ID`/`$CMUX_SURFACE_ID`. No slot/position awareness.
- `panes/dispatch-pane-agent.sh` (209 lines) keeps per-run state only (`state/runs/<id>/`);
  no per-workspace layout state exists. Adapter contract is `open_pane <title> <launcher>` —
  no role/slot parameter.
- Panes stay open after the agent exits (`exec /bin/zsh -i` in the launcher) — slot
  reclamation is therefore a real design question, not hypothetical.

## cmux CLI recon (confirmed via --help, 2026-07-21)

The layout is fully expressible:

- `new-split <left|right|up|down> [--workspace] [--surface] [--panel]` — directional splits
  targeting a specific surface → can build main | quadrant | right column.
- `new-surface [--type terminal] [--pane <ref>]` — adds a surface (tab) to an EXISTING pane →
  the ">6 opens a tab in pane 6" mechanism.
- `list-panes`, `list-pane-surfaces`, `tree` — inspect live layout (reconcile state vs. panes
  the user closed manually).
- Also available if needed: `move-surface --pane`, `swap-pane`, `split-off`, `focus-pane`,
  `resize-pane`, and `new-workspace --layout <json>` (upfront JSON layout — only for NEW
  workspaces, so likely irrelevant: the main session already lives in an existing workspace).

## Decisions (clarifying Q&A — COMPLETE 5/5, 2026-07-21)

1. **Role classification — DECIDED: implementers only → quadrant.** The 2x2 quadrant is
   reserved for plan-task implementers/reviewers. The two judges (compliance/observability),
   the context-handoff pane, and user-requested extra sessions ALL route to the far-right
   "additional" pane (tabbing there when full). User explicitly chose this over the
   recommended "all agents → quadrant" option.
2. **Slot reclamation — DECIDED: reuse finished slots.** A quadrant slot whose agent has
   exited (result file written) is fair game — the next implementer dispatch replaces that
   surface. Scrollback is lost; `state/runs/<id>/` result files + transcripts remain the
   durable record. Quadrant never overflows from finished work.
3. **Construction timing — DECIDED: progressive splits.** 1st implementer = one middle pane;
   2nd splits it into a stack; 3rd/4th complete the 2x2. Deterministic split sequence, no
   empty panes; single-implementer runs stay a clean two-pane layout.

4. **Adapter scope — DECIDED: cmux-only.** Only `cmux.sh` learns slot/role placement;
   tmux/iterm/kitty keep today's dumb `new-split down` and ignore any new contract hint.
   (User took the recommended default.)
5. **Quadrant overflow — DECIDED: tabs on a quadrant pane.** A 5th+ concurrent implementer
   opens as a new surface (tab) on an existing quadrant pane via `new-surface --pane`.
   Implementers never leave the quadrant; far-right stays judges/handoff/extras. Accepted
   visibility cost: a tabbed implementer is hidden until its tab is clicked.

## cmux recon round 2 (verified 2026-07-21 checkpoint session)

- `cmux --json tree --all` exposes per-surface `title`, `tty`, refs, `index_in_pane`, plus
  workspace titles — VERIFIED live (the handoff pane's title was visible in the output).
- **Pane list is FLAT — no geometry.** No x/y, no split-tree structure in the JSON. Which
  pane is "the quadrant" or "far-right" CANNOT be inferred from position; role/slot identity
  must be carried by surface titles (a naming convention) and/or stored pane refs.
- `rename-tab [--surface <ref>] <title>` sets a surface title programmatically — so
  create-then-rename works without relying on in-shell OSC escapes.
- `new-split <left|right|up|down> [--workspace] [--surface] [--focus]` — help shows NO
  output of the created pane/surface refs. UNVERIFIED whether it prints them; live-probe
  next session before designing around ref capture. Fallback: diff `tree --json` before/after.
- `new-surface` confirms the tab mechanism: `--pane <ref>`, `--working-directory`, `--focus`.
  (Also offers `--type agent-session --provider claude` — noted, likely out of scope.)

## cmux recon round 3 — live probe (2026-07-21, fresh session; scratch workspace, cleaned up)

- **`--json new-split` RETURNS REFS** — verified live: `{"pane_ref": "pane:30",
  "surface_ref": "surface:51", "type": "terminal", "window_ref": "window:1",
  "workspace_ref": "workspace:7"}`. Plain form prints `OK surface:50 workspace:7`.
  Ref capture is direct; the tree-diff fallback is unnecessary.
- `--focus false` respected on `new-split` and `new-workspace` (no focus steal).
- Full command sweep — slot-REUSE primitives exist: `close-surface --surface <ref>`,
  **`respawn-pane [--surface <ref>] [--command <cmd>]`** (relaunch a command in an existing
  surface, in place — likely THE reuse mechanism), `send`/`send-key` (typing into the idle
  zsh — fragile, avoid). Also available: `new-pane --direction`, `move-surface`,
  `tab-action`, `set-status`/`set-progress`/`notify` (out of scope, noted).
- Refs are app-session-scoped shorts (`pane:30`; UUIDs via `--id-format both`). Either form
  dies with the cmux app process → **any persisted ref map must revalidate against live
  `tree` anyway** — directly undermines a persistent-slot-map approach.

## Approaches proposed (2026-07-21 — **USER PICKED A**)

**A. Smart cmux adapter, live-derived layout (RECOMMENDED).** Dispatcher exports an optional
role hint env var (e.g. `PANE_AGENT_ROLE=implementer|aux`); only `cmux.sh` reads it. Per
dispatch the adapter derives layout from `cmux --json tree` + a title convention (set via
`rename-tab --surface` at creation, e.g. `[impl:run-id] task`), then: reuse a finished slot
(`respawn-pane`/`close-surface`+`new-surface`), split progressively (1 → stack → 2x2), or
tab overflow (`new-surface --pane`). No persistent state; tree is ground truth; self-heals
on manual pane closes. Env-var hint = zero changes to other adapters and no `common.sh`
arg-validation churn. Cost: cmux.sh grows significantly; title convention is load-bearing;
needs jq (or python) for tree parsing.

**B. Persistent slot map in `state/workspaces/<ws>/slots.json`.** Explicit slot→ref map
written from `--json new-split` output. Killed by the round-3 finding: refs die on app
restart, so every read must revalidate against live tree — B degenerates into A plus a
cache with staleness bugs, plus the new-state/stale-cleanup burden, plus desync when the
user closes panes manually.

**C. Layout policy in dispatcher + new adapter primitives** (`open_pane_at <slot>`,
`open_tab_in <pane>`, `query_layout`). Adapter-agnostic policy, testable without cmux — but
widest blast radius (dispatcher + 4 adapters + both suites) and builds generality Q4
explicitly declined (cmux-only). YAGNI.

Recommendation rationale: A is the only option with zero new persistent state, honors Q4's
cmux-only scope, and the probe confirmed every primitive it needs.

**DECIDED 2026-07-21: Approach A.** Pre-pick clarification asked and answered: A's layout
state survives session handoffs by construction — the tree/titles live in the cmux app
process and run results in `state/runs/`; no layout state exists in any Claude session's
context, so any session re-derives identically. Only a cmux APP quit reissues refs; A never
holds refs beyond one dispatch. **Design assumption to carry into the spec:** whether
surface titles survive `restore-session` after an app restart is UNVERIFIED — if lost, the
adapter sees unmanaged panes and starts fresh splits (degraded: possible extra panes; never
broken). Flag in spec, don't probe.

## Next step (fresh session) — DESIGN SECTIONS DONE, WRITE THE DOC

**STATUS 2026-07-21 (design-doc session): steps (1)+(2) DONE — spec written and
self-reviewed at `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md`, committed on
branch `feature/pane-layout-v2`. Steps (3) judges, (4) user review, (5) writing-plans
remain.**

**ALL FIVE design sections APPROVED 2026-07-21 (same-day resume session; drafts below are
the approved content, including the section-3 slot-number amendment to section 2's grammar
and the aux-reuse extension).** Remaining flow: (1) write the design doc from the approved
sections → `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md` (include the four
flagged assumptions + the beyond-Q&A aux-reuse extension explicitly; Mermaid diagram of the
dispatch decision flow per diagramming-technical-docs); (2) spec self-review (inline);
(3) compliance + observability judges in parallel per running-the-compliance-judge (pane-
dispatched); (4) user review gate; (5) superpowers:writing-plans. **Model: user directed
Opus 4.8 for writing-plans + implementation** (formal pre-implementation gate still gets
asked at code start); spec writing + judge rounds stay on the session's current model
unless the user says otherwise.

## Design section drafts (presented one at a time per superpowers:brainstorming)

### Section 1 — Architecture & component boundaries (drafted 2026-07-21 resume session; PRESENTED, awaiting approval)

- **Dispatcher (`dispatch-pane-agent.sh`):** gains ONE optional flag — `dispatch ... --role
  <implementer|aux>` (allowlist-validated; default `aux`; the `handoff` subcommand is always
  `aux`). Its only new job is exporting `PANE_AGENT_ROLE=<role>` into the adapter call's
  environment. No layout knowledge lives here. ~6 lines.
- **Adapter argv contract FROZEN:** `open_pane <title> <launcher>` unchanged → `common.sh`
  validation untouched; tmux/iterm/kitty adapters untouched (they never read the env var).
  Q4's cmux-only scope made structural.
- **`cmux.sh` = executor:** reads `PANE_AGENT_ROLE` (absent/unknown → `aux`), fetches
  `cmux --json tree`, asks the decision helper for a plan, executes it
  (`respawn-pane` / `new-split` / `new-surface --pane` + `rename-tab`), prints the surface
  ref, sends the launcher. Legacy `new-split down` disappears as a role path but SURVIVES as
  the degradation floor: any layout-derivation failure (jq missing, tree call fails,
  unparseable JSON) → plain `new-split down` + rename, i.e. today's exact behavior. Hard
  failure (→ cooldown) only where it hard-fails today: new-split/send themselves failing.
- **New `panes/adapters/cmux-layout.sh`:** sourced PURE decision helper — functions take
  (tree JSON, role) and return an action plan (`reuse <surface_ref>` | `split <dir>
  <target_ref>` | `tab <pane_ref>`) + the title to stamp. Zero cmux invocations inside, so
  it unit-tests against canned JSON fixtures with no cmux app (feeds section 5), and keeps
  cmux.sh within file-size norms.
- **Runner/launcher:** possibly a small completion-marking hook so finished slots are
  detectable at the NEXT dispatch (exact mechanism — title restamp vs on-disk marker — is
  section 2's decision).
- **State added: none.** Live tree is ground truth; `state/runs/` unchanged.
- Data flow: caller/skill → `dispatch --role implementer` → env → `cmux.sh` →
  `--json tree` → `cmux-layout.sh` plan → execute + rename → ref → send launcher.

### Section 2 — Title convention + slot derivation (APPROVED 2026-07-21; slot-number amendment added by section 3)

**Section 1 was APPROVED as drafted (user, 2026-07-21).**

- **Title grammar** (inside the FROZEN allowlist `[A-Za-z0-9 ._:-]` ≤64 — the earlier
  `[impl:run-id]` bracket sketch is amended; allowlist is a reviewed security boundary):
  `impl:<run-id> <label>` (quadrant) | `aux:<run-id> <label>` (far-right). run-id =
  `[0-9]+-[0-9]+-[0-9]+` (existing epoch-pid-random). Recognition is ANCHORED:
  `^(impl|aux):[0-9]+-[0-9]+-[0-9]+ `. **Adapter composes the title** — extracts run-id
  from the already-validated launcher path (`.../runs/<run-id>/launch.sh`), prefixes
  role+run-id to the dispatcher's label, truncates at 64 from the RIGHT (prefix never
  truncated). Dispatcher label drops the redundant `pane: ` prefix (1-word change).
- **Finished-slot marking — DECIDED (recommend): on-disk marker, not title restamp.**
  Runner writes `state/runs/<run-id>/agent-exit` (containing DONE/FAILED) immediately
  AFTER a successful result-file write; run_dir derived from `dirname prompt_file` with a
  shape guard (no contract change). fail_early paths write NO marker → slot never
  auto-reused → error pane preserved for post-mortem. In-pane `rename-tab` restamp
  REJECTED: unverified `$CMUX_SURFACE_ID` format for `--surface`, needs role plumbing into
  the launcher, and adds a second title form — all for cosmetics `notify` already covers.
- **Derivation rules** (per dispatch, from `--json tree`): managed surface ⇔ anchored
  grammar match. impl slot = pane with ≥1 impl surface; slot FINISHED ⇔ every impl
  surface's run-id has agent-exit marker OR its run dir is gone (7-day cleanup ⇒ finished);
  else RUNNING. aux pane = pane with ≥1 aux surface and NO impl surface (impl wins mixed
  panes). Unmanaged panes (incl. the user's main session) are INVISIBLE — never reused,
  never tabbed, never split-targets. **Main pane needs NO tree identification**: "split
  right of main" uses cmux's env-implicit targeting (bare `new-split right`, as today);
  all other splits target managed surface refs read live from the tree.
- **Flagged assumptions / edges:** (1) workspace scoping — managed titles in OTHER
  workspaces must not attract splits; mechanism = bare `tree` env-scoping OR matching
  `$CMUX_WORKSPACE_ID` to tree refs, verify at implementation, degrade to plain
  `new-split down` if neither works. (2) Post-handoff, main runs in an `aux:`-titled
  surface → handoff-wrapper best-effort renames its tab on adoption to strip the managed
  prefix (assumes `rename-tab --surface "$CMUX_SURFACE_ID"` works in-pane; fallback = aux
  tabs land on main's pane — annoying, functional). (3) restore-session title loss →
  everything unmanaged → fresh splits (already flagged).

### Section 3 — Dispatch decision algorithm (APPROVED 2026-07-21, incl. slot-number amendment + aux-reuse extension)

- **Grammar amendment (to approved §2): slot number in the impl title —
  `impl.<slot>:<run-id> <label>`, slot ∈ 1-4.** Rationale: the tree is FLAT and reuse
  rewrites run-ids, so creation-epoch order cannot recover which pane is top/bottom; the
  slot number in the title IS the positional memory (lives in the cmux app like all other
  layout state; zero new files). Tabbed overflow surfaces carry their pane's slot. `.` is
  in the frozen allowlist.
- **Implementer path, in order:** (1) REUSE: any finished impl surface (per §2 marker
  rules) → `respawn-pane --surface <ref> --command "bash <launcher>"` + rename; pick
  OLDEST finished (run-id epoch). Never grows the quadrant. (2) CREATE (no reusable,
  Q < 4 slots present): fill the LOWEST missing slot — slot1 = env-implicit
  `new-split right` (splits main's cell); slot2 = `new-split down --surface <slot1>`;
  slot3 = `new-split right --surface <slot1>`; slot4 = `new-split right --surface
  <slot2>`. Either interleaving still converges to 2x2; lowest-missing-first also
  self-heals user-closed slots (slot deps are well-founded: 2,3 need 1; 4 needs 2; slot1
  missing → env-implicit split from main again). New surface gets the launcher via `send`
  (proven path) + rename. (3) TAB OVERFLOW (Q == 4, none finished): `new-surface --pane`
  on the slot with the FEWEST surfaces (tie → lowest slot) + send + rename.
- **Aux path:** aux pane exists → reuse a finished aux surface (respawn, oldest first)
  else new tab (`new-surface --pane` + send). No aux pane → create it: probe
  `new-pane --direction right` (full-height right column — ASSUMPTION #4, unverified);
  fallback `new-split right --surface <slot3|slot4|newest right-column surface>`
  (imperfect geometry, functional); no quadrant at all → env-implicit `new-split right`.
  **Aux-surface reuse is an extension beyond the literal Q&A** (Q2 covered the quadrant)
  — recommended for symmetry + bounded tab growth; flagged for user sign-off.
- **6-pane cap is EMERGENT, not counted:** managed layout never creates beyond
  slot1-4 + aux (+ main) = 6. User-made unmanaged panes can push the visual total past 6;
  they are invisible to the algorithm and unmolested. `close-surface` ends up UNUSED
  (respawn covers reuse); pane proportions/`resize-pane` = out of scope (user-draggable;
  future nicety).

### Section 4 — Error handling / degradation (APPROVED 2026-07-21)

**Principle: layout smarts may only ever fail INTO the dumb-but-working path; only the
dumb path's failure escalates to cooldown.** PR #23's cooldown contract keeps its meaning
("terminal unusable"), never "layout confused".

- **Tier 1 — degrade to legacy `new-split down` + send + rename (one stderr breadcrumb
  `cmux-layout: degraded (<reason>)`, NEVER cooldown):** jq missing; `--json tree` fails
  or unparseable; workspace scoping unestablishable (assumption #1); derivation nonsense.
  Malformed titles → those surfaces are simply unmanaged. Duplicate slot N → NEWEST run-id
  wins, losers unmanaged (never touched). Derivation runs BEFORE any mutating call, so a
  Tier-1 failure performs exactly one mutation path — no half-built layouts.
- **TOCTOU race (target surface vanished between tree read and respawn/new-surface/
  new-split):** retry ONCE with a fresh derivation, then legacy. Bounded, deterministic.
- **Tier 2 — unchanged from today (adapter exits nonzero → dispatcher cooldown flag →
  in-process for the session):** the legacy split itself fails, or `send` fails
  post-creation (pane exists but empty — same partial state v1 ships today; no rollback,
  no close-surface cleanup: destroying panes on error contradicts the post-mortem
  philosophy).
- **Role input:** dispatcher validates `--role` against the allowlist and dies loudly on
  garbage (caller bug = fail fast, usage exit). At the adapter, absent/unknown env →
  treated as `aux` + stderr note. The RAW env value never enters any command line or
  title — only the adapter's own mapped constant (`impl`/`aux`) does.
- **Marker + wrapper niceties are best-effort:** agent-exit write failure → stderr note,
  slot just never looks finished (never reused; extra splits at worst) — the PANE_RESULT
  contract is untouched. Handoff-wrapper rename failure → `|| true` (documented: aux tabs
  may land on main's pane). Run-id extraction somehow failing → unprefixed title
  (unmanaged surface) + stderr note, dispatch proceeds.
- **Accepted risk (explicit):** no timeout wrappers on cmux calls — consistent with every
  existing adapter call; degradation policy targets errors, not hangs (macOS lacks stock
  `timeout(1)`; adding machinery = YAGNI until a hang is ever observed).

### Section 5 — Testing (APPROVED 2026-07-21 — ALL FIVE SECTIONS NOW APPROVED)

(Ground truth: suites are `panes/adapters.test.sh` (table-driven dry-run + validation, no
real panes), `dispatch-pane-agent.test.sh`, `run-pane-agent.test.sh`; the 4 adapters are
cmux/tmux/iterm/terminal — earlier "kitty" mentions were wrong.)

- **Layer 1 — NEW `panes/adapters/cmux-layout.test.sh` (pure decision tests):** source the
  helper, feed canned tree-JSON fixtures + a fake `PANE_STATE_DIR` (runs dirs ±
  `agent-exit`) → assert the emitted plan. Case matrix: empty→create slot1;
  lowest-missing-slot fill; reuse-oldest-finished; full+busy→tab fewest-surfaces (tie →
  lowest slot); aux exists/absent/reuse; duplicate slot → newest wins; malformed titles →
  unmanaged; missing run dir = finished; absent role → aux. Real jq, no cmux, fast.
- **Layer 2 — fake cmux binary:** make `CMUX_BIN` overridable as
  `${PANE_CMUX_BIN:-/Applications/...}` (precedent: PANE_CLAUDE_BIN / PANE_STATE_DIR;
  env-only, test-only — controlling env = controlling process, no boundary weakening).
  Fake = bash script that logs argv and replays scripted per-subcommand responses from a
  fixture dir. Asserts CALL SEQUENCES (respawn for reuse, correct `--surface` targets,
  rename carries prefix) and the §4 matrix: garbage tree → legacy call + stderr breadcrumb
  + NO cooldown flag; respawn fails once → re-derive → legacy; legacy split fails → exit
  nonzero (cooldown-flag assertion lives in dispatch-pane-agent.test.sh).
- **Layer 3 — existing suites extended, PANE_DRYRUN redefined as derive-then-print:**
  derivation is read-only, so dryrun derives (via PANE_CMUX_BIN if set) and prints the
  plan; with no cmux available it prints the legacy plan → existing `"new-split down"`
  assertions keep passing on cmux-less machines. tmux/iterm/terminal loop cases unchanged.
  dispatch-pane-agent.test.sh += `--role` validation (valid/invalid/absent);
  run-pane-agent.test.sh += marker cases (written after result write, DONE/FAILED content,
  fail_early → NO marker, shape guard → no marker outside runs/).
- **Falsification discipline (token-bar lesson, mandatory):** every degradation/guard test
  is validated by mutating the code it guards and watching it go red before trusting
  green — e.g. helper exits nonzero on missing jq → the "Tier-1 never cooldowns" test must
  catch the flag write.
- **Live probe checklist (implementation start, NOT CI):** scripted scratch-workspace
  probe resolving assumptions #1/#2/#4 (workspace scoping, in-pane rename, `new-pane
  --direction`); #3 (restore-session titles) stays observational. Results → branch log.
  2x2 visual correctness: one manual live check, not automated.

## Constraints to carry into the design

- Degrade-never-block invariant from PR #23 stands (adapter failure → cooldown → in-process).
- Adapter contract change touches `dispatch-pane-agent.sh`, all 4 adapters' arg validation
  (`common.sh`), and both test suites.
- Per-workspace layout state (slot map) is new state — needs the same stale-cleanup treatment
  as `state/runs/`.
- Model-switch gate: user implicitly stayed on Fable 5 for the brainstorm (2026-07-21); the
  pre-implementation gate must still be asked separately when this reaches code.

## User review gate — CLEARED 2026-07-21

Spec reviewed at blob aeb0074 (commit bb4050b) with round-1 judge verdicts fresh. Explicit
user sign-off recorded on both flagged items, with ZERO spec edits (verdicts remain valid):

1. **Aux-reuse extension APPROVED** — finished aux surfaces are respawned oldest-first
   before tabbing (the extension beyond Q2's literal quadrant-only scope). Accepted trade:
   reused surface's scrollback is lost; `state/runs/<id>/` stays the durable record.
2. **All 4 flagged assumptions SIGNED OFF** as implementation-time verifications: live
   probe at implementation start resolves #1/#2/#4, #3 stays observational; degrade paths
   as specced.

The spec's status line intentionally still says "pending judges + user review" — editing
the file would change its blob SHA and invalidate both judge verdicts over a cosmetic fix.
THIS entry is the authoritative approval record.

Next: `superpowers:writing-plans` on Opus 4.8 (user's standing direction), on
`feature/pane-layout-v2`; the formal pre-implementation model gate is still asked when
code starts. Carry the judges' notes into implementation: pin `respawn-pane --command`
quoting during the live probe before REUSE is coded; obs success_masking concern
(out-of-band `state/runs/` cleanup could recycle a busy pane); fallback tests assert the
exact legacy command sequence.
