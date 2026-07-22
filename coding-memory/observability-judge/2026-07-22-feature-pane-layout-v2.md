# Observability Judge Verdict — pane-layout-v2 (implementation, gating)

- **Repo:** `.claude` · **Branch:** `feature/pane-layout-v2`
- **HEAD:** `e12dc069498879b501b2f1e786d0f95612792160` (pushed; `origin` matches)
- **Base:** `main` (merge-base `98faa38e4c21bc354ca98c79dfc7560c96e71573`)
- **Stage:** implementation (gates the PR)
- **Diff:** 21 files, +4317 / −67. Source: `panes/adapters/cmux-layout.sh` (new, 226 lines),
  `panes/adapters/cmux.sh` (rewritten, 265 lines), `panes/dispatch-pane-agent.sh`,
  `panes/run-pane-agent.sh`, `panes/handoff-wrapper.sh`,
  `skills/dispatching-pane-agents/SKILL.md` (+6 lines). Rest is tests, fixtures, spec, plan,
  and the 938-line engineering log.
- **Spec:** `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md` @ blob `aeb0074`
  (frozen, deliberately unedited) · **Log:** `coding-memory/branches/pane-layout-v2.md`
- **Risk:** low · **Confidence:** high

## Test evidence — run by me, not taken on report

All six suites executed against this working tree: `cmux-exec` 54/0, `cmux-layout` 34/0,
`adapters` 24/0, `dispatch-pane-agent` 39/0, `run-pane-agent` 10/0, `terminal-detect` 9/0 —
**170 passed, 0 failed**. `shellcheck -x` on the four named scripts exits 0, silent.

Because this branch's own log records repeated vacuous-pass and no-op-mutation traps, I did
not take its falsification records on trust. I re-ran three of them independently, in
`mktemp -d` copies of `panes/` (repo never touched):

| Mutation | My result | Log's claim |
|---|---|---|
| `max_by(.index)` → `first` in `layout_rightmost_surface` | layout **31/3** | F2: 31/3 |
| `layout_run_finished` → unconditional `return 0` | layout **24/10** | Task-4 F2 shape |
| aux-create anchor dropped (reproduces the original far-left bug) | exec **53/1** | F3: 53/1 |

Counts match exactly. The suites genuinely discriminate; the green is load-bearing, not
decorative. I also traced the marker path end-to-end by hand rather than inferring it:
`dispatch-pane-agent.sh:133` copies the prompt into `$run_dir/prompt.md` and `:141` passes
that path, so `run-pane-agent.sh`'s `*/runs/*`-guarded `dirname` lands the `agent-exit`
marker in exactly the directory `layout_run_finished` reads. No mismatch.

## Dimension table

| Dimension | Verdict | Basis |
|---|---|---|
| intent | **pass** | All five verbatim requirements met. The four deviations are evidence-forced, not convenient — and deviation 4 is *inside* the spec's own contingency: assumption 4 already reads "else fallback split right of a right-column slot (imperfect geometry, functional)", which is precisely what shipped. |
| execution | **pass** | 170/0 run by me; shellcheck clean; three independent falsifications reproduce the log's counts exactly. Live-verified: workspace scoping, tree shape, impl slots 1–4, reuse re-using the same surface, title stamping, handoff rename, aux position in both orderings. |
| trajectory | **pass** | Reasoning, not luck. 28 numbered corrections, probe-first ordering, predict-then-observe at P8, vacuous passes counted and named in every RED run, falsifications reverted and sha256-verified. Correction 27 falsifies the branch's *own* earlier conclusion rather than defending it. A self-inflicted `git checkout --` data loss is recorded, not buried. |
| regression | **pass** | Four adjacent suites unchanged and green. Adapter contract `open_pane <title> <launcher>` frozen; tmux/iterm/terminal untouched and ignore the new env var. Legacy floor kept byte-identical and pinned by an anchored `grep -qxF "new-split down"`. |
| context_budget | **pass** | +6 lines to one on-demand skill. No `CLAUDE.md` or `rules/` change. The 938-line log and 1225-line plan live in on-demand paths, not always-on context. |
| traceability | **pass** | Unusually strong. Every non-obvious line carries its *why* at the call site, keyed to a probe (P4 destructiveness, P5 workspace context, P6 silent mis-target, P8 height). The aux-height limitation is stated in `layout_rightmost_surface`'s header. |
| success_masking | **concern** | Four items, below. None corrupts data; all are bounded and recorded; but three of them fail *invisibly* with tests green. |
| intent_drift | **pass** | Tightly scoped. No new dependencies (jq and cmux were already required). No drive-by refactors — the one refactor beyond brief (`LAYOUT_JQ_WS_SCOPE`) is byte-output-identical and pinned by falsification F6. |
| checkpoint | **pass** | Clean per-task `feat` + `docs` commit pairs; each task independently revertible; `Doc-Exempt` trailers used honestly on memory-only commits; HEAD pushed and matching `origin`. |
| audit_trail | **concern** | A frozen spec assumption failing live and being accepted as a permanent product limitation is ADR-worthy under this repo's own gate. No ADR exists (`docs/decisions/` stops at 0007), and `CODING_MEMORY.md`'s durable index stops at Task 7 — Tasks 8/9 and probe P8, the two most consequential findings, live only in the branch-scoped log. |

## Concerns

1. **`layout_rightmost_surface` ships a heuristic with no detector.** Correction 27 falsified
   the "index is left-to-right" reading (a real quadrant ordered impl.1, impl.**3**, impl.**2**,
   impl.4). Max-index landed in the rightmost column in every observed case and the flat tree
   offers nothing better, so shipping it is defensible — but nothing logs when the anchor is
   unusual. A cmux traversal-order change would silently mis-place the aux column with all
   170 tests still green.
2. **Aux column is half-height when created after the quadrant is populated** (P8,
   user-confirmed). Accepting this is defensible: three independent grounds establish it is
   unfixable from the current CLI, the trade (right-column-sometimes-half-height vs.
   full-height-but-2nd-from-left) is stated explicitly, the common real path — handoff and
   judges opening before any quadrant exists — is unaffected, and it is the fallback the spec
   already authorised. But it is documented in only two places, one of them a branch-scoped
   log, while the durable spec still shows a full-height far-right column.
3. **Verify-after-rename's *repair* path has never executed live.** Its own rename rides P6's
   silent focused-tab fallback, so a repair fired against a victim ref that has since become
   unresolvable would rename the user's focused tab. Bounded to one unverified call, only
   reachable after a mis-target already occurred, and zero mis-targets fired across two live
   sessions — but it is an untested write path that can touch a user pane.
4. **"Missing run dir = finished" is now paired with reuse-by-`send`.** Under the spec's
   original `respawn-pane` a wrongly-"finished" surface would have been visibly destroyed;
   under `send` it gets `bash <launcher>` *typed into whatever process lives there*. Trigger
   is narrow (run dir deleted while the agent still runs; cleanup is 7-day), and this
   interaction is not called out anywhere as a combined risk.
5. **Silent degrade-to-legacy is thin on signal.** One stderr breadcrumb per dispatch, exit 0,
   no persistent record. Stderr does reach the user (`open_pane_or_cooldown` captures only
   stdout), but a systemic cause — a cmux upgrade changing the tree shape, exactly the P2
   failure — would disable the whole feature for a session while every test stays green and
   the only symptom is stacked panes plus an easily-missed line.
6. **Two write paths have no automated coverage.** `%q`'s backslash form as received by the
   target shell, and the handoff-wrapper rename (no wrapper suite exists; the wrapper also
   hardcodes the cmux app path with no `PANE_CMUX_BIN` override, unlike every other caller).
   Both were live-verified once.
7. **Unrelated uncommitted edits still ride this checkout** (`chrome/chrome-native-host`,
   `settings.json`) — the same item the architecting round flagged. Not in the diff, so the
   change itself is clean, but they would follow a branch switch.

## What was changed

The pane dispatcher used to drop every agent into a growing stack of splits. This teaches
it to arrange them like a deliberate desk: your session stays far-left, implementer agents
fill a 2x2 grid in the middle one cell at a time, and everything else — judges, the handoff
pane, extras — goes in a column on the far right, with overflow becoming tabs. There is no
saved layout file. On every dispatch the adapter re-reads the live pane tree and recognises
its own panes by a strict title convention, the way you'd find your coat by the name tag
rather than by remembering which hook you used. Finished agents leave a "done" marker file
so their pane can be recycled; a crashed agent leaves none, so its pane is preserved for you
to read. If any of the clever logic gets confused, it silently falls back to the old dumb
split — the smart path can never make pane dispatch less available than it is today.

## Does it do what you wanted?

Yes, with one honest exception you already know about. All five of your stated requirements
landed and were confirmed with your own eyes in a live workspace: the 2x2 quadrant builds in
the right order, reuse recycles a finished pane instead of growing the grid, and the aux
column sits on the far right.

The exception is **height**. When the aux column is created *after* the quadrant is already
full, it comes out half-height in the bottom-right instead of a full-height column. This is
argued unfixable from the current cmux CLI on three separate grounds, and I checked the
argument rather than accepting it: the pane list really is flat (no nesting or geometry to
read), splits really do inherit their anchor's container, and the one true sidebar mechanism
is disabled by cmux itself. Accepting it is the right call — the alternative was a
full-height column permanently in the *wrong position*, and the common case (handoff and
judges opening before any quadrant exists) still gives you the full-height column the design
asked for. So: position always right, height sometimes wrong, versus position always wrong.
That trade is correctly made.

The four deviations from the frozen spec were all forced by live evidence, not by
convenience. The best of them: the spec said to reuse a pane with `respawn-pane`, and the
probe discovered that command *destroys* the surface it was meant to recycle — it killed a
real pane during the probe. Switching to `send` preserves the intent exactly and was later
confirmed live when a second dispatch reused the same surface and the surface survived.

## What could go wrong / what I'm unsure about

- **The far-right anchor is an educated guess, and it can't tell you when it's wrong.** The
  code picks the pane with the highest `index` and assumes that's the rightmost. The branch
  proved to itself that this reasoning is not strictly true (in a real quadrant a left-column
  pane sorted *after* a right-column one), kept the code because nothing better exists in
  the tree, and honestly downgraded the comment to "heuristic". Shipping it is fine. The
  thing to sit with is that if a future cmux changes how it walks its panes, your aux column
  quietly appears in the wrong place and **every one of the 170 tests still passes**.
- **The self-repair path for a mis-named tab has never actually run.** cmux has a nasty
  behaviour (probe P6): renaming a tab that no longer exists doesn't error — it renames
  whatever tab you're *looking at*, and exits 0. The code defends against this properly by
  re-reading the tree and checking the name landed where intended. But the *repair* it does
  after detecting a mis-name uses the same risky command, and that repair has only ever run
  against a fake. It's one call, it's only reachable after something already went wrong, and
  no mis-name occurred in two live sessions — but it's the one path that could put a wrong
  name on a pane you're using.
- **"The folder is gone, so the agent must be finished."** If a run's state folder
  disappears while its agent is still working, the code will treat that pane as free and
  type `bash <launcher>` into it. Under the spec's original design that would have visibly
  destroyed the pane; now it types into whatever is living there. Narrow trigger, accepted
  and recorded — but the combination of "assume finished" and "type into it" is newer than
  the note that accepts it.
- **When the clever path gives up, it says so once and quietly.** One line on stderr per
  dispatch, then the old behaviour. That's the right *safety* choice, but it means a
  systemic breakage — say a cmux upgrade changing the JSON shape, which is exactly what the
  first probe caught — would turn the whole feature off for a session and the only clue
  would be your panes stacking up again.
- **Documentation durability.** The most user-visible limitation of this feature is written
  in the branch log and one code comment. The spec is frozen on purpose (sensible — its blob
  keys the earlier verdicts), so it still describes a full-height column, and the durable
  memory index stops at Task 7. Six months from now the branch log is the only thing that
  explains why your aux column is sometimes short.

## What I'd double-check before merging

1. **Write the ADR.** A frozen spec assumption failing live and being accepted as a permanent
   limitation is exactly what `docs/decisions/` is for, and this repo's own gates say so.
   One short ADR covering the aux-height trade and the `respawn-pane` → `send` deviation
   makes both survive the branch log.
2. **Bring `CODING_MEMORY.md` up to Task 9.** It currently stops at Task 7, so the durable
   index is missing the live smoke check, the aux fix, and probe P8 — the three things a
   future session would most need.
3. **Watch the aux column's position after the next cmux upgrade.** That heuristic is the
   one piece of this with no self-check. The re-runnable probe script is committed
   (`panes/cmux-layout-probe.sh`) — the spec already says a cmux upgrade re-runs the probe
   checklist, and this is the item that most needs it.
4. **Decide whether a degrade deserves more than one stderr line.** A counter or a state
   file would turn "the layout silently stopped working" into something you can notice.
   Not a merge blocker; worth a follow-up ticket.
5. **Commit or stash `chrome/chrome-native-host` and `settings.json`.** They are unrelated to
   this branch, they have been riding the checkout since the architecting round, and they
   will follow you to whatever branch you switch to next.
