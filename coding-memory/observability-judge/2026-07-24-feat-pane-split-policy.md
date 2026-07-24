# Observability judge — implementation — feat/pane-split-policy

**ts:** 2026-07-24T20:48:09Z · **repo:** `.claude` · **branch:** `feat/pane-split-policy`
**head_sha:** `b38aa24ccfdf3a266e560ce907944055a1c37f12` · **base:** `main` (merge-base `7854ae3`)
**stage:** implementation (gates the PR) · **risk:** medium · **confidence:** high

Verified myself, not taken on report: all seven suites run (`34/89/45/34/81/10/9 = 302 passed,
0 failed`), `shellcheck -x` on all six shell files + the probe (`rc=0`), full diff of every source
file read, the cmux probe fixture confirmed a real live capture (commit `fe7f30a`), the guard's and
dispatcher's two conf parsers compared line by line.

## What was changed

The rule for *where a helper agent runs* used to be one list plus a judgment call. It is now three
lanes with a per-session budget:

- **Read-only helpers** (`Explore`, `Plan`) always run in-process. Never asked about, never counted.
- **The two judges** always get their own pane, sitting *outside* the budget entirely.
- **Everything else is a "worker"**, and once per session you're asked: `inline` (run them in-process)
  or `panes max=N` (up to N side-by-side panes). Past N, the next worker opens a **tab inside** one of
  the existing worker panes, chosen round-robin.

Think of it as a restaurant with N tables reserved for your party. Under N, a new guest gets their own
table. At N, they pull up a chair at an existing table — nobody is turned away and nobody waits. The
judges are staff: they always get a table and it never comes out of your N.

## Does it do what was intended?

Yes. Every decision locked in the spec is in the code, and the two choices the user made at the design
review — `inline` must not silence the judges, and judge panes must not eat a worker slot — aren't
just honored, they're made *structurally impossible to violate*: both lanes are checked before the
policy is ever read. That's the right way to encode a rule you can't afford to get wrong.

The one deviation is declared, not discovered: under a *simultaneous* fan-out, a worker arriving while
another is still opening can fall to in-process instead of tabbing. The user accepted it on 2026-07-24
and it's written down in both the skill and ADR 0009. Sequential dispatch — the normal case — is fine.

## What could go wrong / what I'm unsure about

**The one finding the branch's own review process didn't surface.** A worker pane's run is marked
finished only when the agent completes normally. `run-pane-agent.sh` has no exit trap for it, and
`wait` deliberately doesn't write it on timeout ("the pane stays open for post-mortem"). So if you
**close a worker pane by hand**, or cmux restarts, or an agent hangs past the timeout, that run stays
"live" for the rest of the session *and keeps its recorded surface ref*. Two consequences:

1. The count is inflated, so workers start tabbing while panes are actually free. Cosmetic.
2. Worse: `select_worker_surface` can hand the next overflow a **surface that no longer exists**.
   `cmux_open_tab` can't find it in the tree, returns non-zero, and the dispatcher treats that as an
   *adapter failure* — writing the session cooldown flag and forcing **everything in-process for the
   rest of the session**, with a stderr line that blames cmux.

Nothing is lost and nothing hangs — it degrades exactly as designed. But the cause is stale local
state, not a broken adapter, and the code already has the right vocabulary for that case (the
no-selectable-target path correctly uses exit 3 *without* a cooldown, "capacity, not an adapter
failure"). This path doesn't use it. It's untested and unnamed in the decisions summary.

**On the observability question you asked me to score.** Exit 3 covering three causes is *not* the
real problem — the consumer of these messages is a language model reading English prose, not a script
branching on `$?`, and nothing anywhere branches on 3-vs-3. Call that a note, not a defect. The actual
gap is that **the decisive routing computation is never recorded**. You can reconstruct pane-vs-tab
after the fact from the `kind`/`lane`/`session`/`surface` markers (a genuinely good durable trail),
but "counted 3 live, max is 3, therefore tabbed into surface:X" exists nowhere. When a session's
fan-out mysteriously all goes inline, diagnosis means re-deriving state by hand — and the highest-
consequence failure points at the wrong component while you do it. That's the traceability concern.

**On the evaluation question.** The test evidence is well above the bar and I want to be specific,
because 302 green assertions are exactly the kind of thing that *could* be theater and here aren't:
the count/lane/kind logic runs against **real run-dir fixtures**, the cmux tab primitive was
**probe-verified against live cmux and the capture committed** before the adapter was trusted, and the
new injection boundary took **eight hostile payloads through the real adapter**. That directly closes
the ADR-0008 fake-binary trap the architecting rounds kept flagging. Two honest residuals: nothing
exercises a live cmux actually filling N panes and overflowing (the primitive is proven, the
composition is fake-binary tested), and the skill `description` change is unverified because no
trigger-accuracy harness exists here. The implementer said so plainly rather than implying coverage —
that's the correct answer, and I'm scoring it as declared, not as a defect.

**Smaller, all self-declared:** `dispatch-pane-agent.sh` is 410 lines against a 400 soft limit (800
hard) with a named next-move; `CLAUDE.md` line 22 still says "(judge, plan implementer)" — the one
line that is *always* in context now under-describes the trigger surface; and under `inline` the
dispatcher will still open a pane if invoked directly, so spec scenario 1's "no worker pane is opened"
is guard-enforced only. Consistent with "momentum guardrail, not a boundary," but it is a literal gap.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | All locked decisions present; both user review-gate choices enforced structurally by lane ordering. One user-accepted, documented deviation. |
| `execution` | pass | 302/0 across 7 suites, run by me. `shellcheck -x` clean. Real fixtures, live probe. |
| `trajectory` | pass | Strongest dimension. Task 7's spec contradiction caught *before* coding; fixed with ONE shared predicate so count and selection cannot disagree — structural, not a patch. `dead_mark` chosen over the racier alternative with the race named. Marker write order reasoned to a commit point. Design, not luck. |
| `regression` | concern | Plan implementers move skill-routed → policy-governed on a shipped hook-enforced system (carried from architecting). Plus the new stale-surface → session-wide cooldown surface that `open_tab` introduces. |
| `context_budget` | pass | `gates.md` +~40 words on an existing bullet; SKILL.md +59 lines is on-demand; new conf is 5 lines. |
| `traceability` | concern | Routing decision unlogged at the moment it's made; the worst failure misattributes to the adapter; exit 3 overloaded (minor, prose distinguishes). |
| `success_masking` | pass | The dimension most at risk here, and it holds: real run-dir fixtures, committed live-cmux probe, adversarial security tests. `wait` is deadline-bounded with a hot-spin guard. Residuals named above, not hidden. |
| `intent_drift` | pass | Everything traces to spec, plan, or a named reviewer finding. No new deps. The `PANE_HOME` guard fix is a real correctness prerequisite, documented as such. |
| `checkpoint` | pass | 35 commits, checkpoint-per-task, clean revert point at `b38aa24`. Uncommitted `coding-memory/compliance-judge/` files are unrelated and pre-existing. |
| `audit_trail` | pass | ADR 0009 delivered — closes the concern all three architecting verdicts repeated. Spec locked, plan, 697-line branch record, prior verdicts chained. |

## Concerns

1. A manually-closed or timed-out worker pane never gets its completion marker, so it counts live all
   session AND keeps a surface ref that no longer resolves — the next overflow reads that as an adapter
   failure, writes the session cooldown, and forces everything in-process while blaming cmux. Untested,
   unnamed in the summary; the correct classification (exit 3, no cooldown — capacity, not adapter
   failure) already exists in the code for the sibling case.
2. The routing decision itself is never logged — pane-vs-tab is reconstructible from run-dir markers
   but the count/max/target reasoning is not, so the failure that most needs explaining is the one you
   can least explain.
3. Exit 3 covers three causes (no terminal, no overflow target, no adapter). Minor — the consumer reads
   prose and nothing branches on the code — but it forecloses programmatic handling later.
4. Skill `description` change is unverified by measurement (no trigger-accuracy harness exists);
   honestly declared by the implementer, not concealed.
5. No live end-to-end run of N panes filling and overflowing on real cmux; the primitive is probe-
   verified, the composition is fake-binary tested.
6. `CLAUDE.md` line 22 still carries pre-three-lane framing — the only always-on line on the branch,
   and it now under-describes the trigger surface.
7. Plan implementers move from skill-routed judgment to policy-governed routing on a shipped system —
   user-confirmed, but a real behavior change for every future session.
8. Under `inline`, the dispatcher will still open a pane if invoked directly; spec scenario 1 is
   guard-enforced only.
9. `dispatch-pane-agent.sh` at 410 lines exceeds the 400 soft limit (declared, with a named next-move).

---

# RE-RUN 2 — CURRENT VERDICT (this is the one that gates the PR)

**ts:** 2026-07-24T21:38:02Z · **repo:** `.claude` · **branch:** `feat/pane-split-policy`
**head_sha:** `2418e5b0e286648fd68119e56db3d45ecdc1b739` · **base:** `main`
**stage:** implementation (gates the PR) · **risk:** medium · **confidence:** high

Supersedes RUN 1 (`b38aa24`) above. Verified myself: all seven suites re-run
(`34/95/45/34/81/10/9 = 308 passed, 0 failed`), `shellcheck -x` clean (rc=0), the full
`b38aa24..HEAD` diff read, the reclassification and `ROUTE` code read in place, **and the
locked spec and shipped skill doc read against the new behavior** — which is where this
round's findings came from.

## What was changed

Two commits, both answering RUN 1.

The real one: when the dispatcher tries to open a **tab** inside an existing worker pane and
that fails, it no longer declares the terminal integration broken and switches the whole
session to in-process. It now says "that particular pane is stale," **retires just that pane
from its bookkeeping**, runs this one spawn in-process, and carries on. Opening a *new pane*
failing still trips the session-wide cooldown, and there's now an explicit test pinning that
the two cases stay different.

It also prints one line saying *why* it routed the way it did —
`ROUTE: lane=worker live=2 max=2 kind=tab target=surface:AA` — to the terminal and to a file
in the run directory, written **before** the risky call so it survives the failure. And the
one always-in-context line in `CLAUDE.md` now describes the three lanes correctly.

Analogy: RUN 1's complaint was that finding one chair missing made the restaurant stop seating
anyone all night. Now it just crosses that table off the list and seats you elsewhere. Correct
instinct. The catch is below.

## Does it do what was intended?

Mostly, and the intent behind it is right. But **the code now contradicts the locked spec**,
and nobody updated the spec.

`docs/superpowers/specs/2026-07-22-pane-split-policy-design.md` says it three times — plan step
4 (lines 137-138), the dispatcher contract (lines 180-181), and a **named Gherkin acceptance
scenario** (lines 242-246):

> **Scenario: An adapter that cannot tab degrades to in-process without blocking**
> … **And it writes the session cooldown flag** and the session continues without blocking

The code no longer writes that flag. The two tests that pinned it were **deleted**. The spec
was not amended, ADR 0009 was not amended, and `skills/dispatching-pane-agents/SKILL.md` lines
55-58 still tell a future agent "Adapter failure → per-session cooldown flag + in-process (exit
4)" and list only two exit-3 causes — the new third one is missing. **The shipped operating doc
is now actively wrong about a path that just changed.**

The brief framed this as replacing "Task 7's stated intent." It is not task-level. It is a
spec-level locked decision with an acceptance scenario, and the only record of the reversal is
session memory and a comment in a test file. That understates it, and I'm scoring it as it is.

## What could go wrong / what I'm unsure about

**1. The convergence argument is incomplete — and the gap is the exact case the spec named.**
I was asked to check it, so: the comment argues that even against a genuinely broken adapter
the session still converges on the cooldown, because retiring drains one pane per failure until
the count drops under N, at which point `open_pane` fails and writes the flag. That holds **only
if `open_pane` fails too.** It assumes brokenness is the same for both verbs.

Now take the case the spec explicitly wrote down — "If `open_tab` is **unsupported** or fails on
this adapter," and "any adapter lacking a usable tab primitive returns non-zero." An adapter that
can split panes but cannot tab:

- live = N → overflow → `open_tab` fails → it retires a **perfectly healthy, still-running** pane
  from the count → live = N-1 → this spawn goes in-process. No cooldown.
- next worker: live = N-1 < N → **opens a brand-new pane.** The retired one is still on screen.
  Physical panes = N+1, counted = N.
- repeat: **+1 real pane every two overflowing dispatches, forever, silently, and the cooldown
  never arrives.**

The user asked for `max=N` panes. This path quietly exceeds it without bound. The old cooldown
was over-aggressive for stale state — my RUN 1 finding, still valid — but it *was* the thing
bounding this. The fix collapsed two different causes into one and kept the good answer for only
one of them. Mitigating, and why this is medium and not high: all four shipped adapters
(`cmux`, `tmux`, `iterm`, `terminal`) do implement `open_tab`, and cmux's is probe-verified
against the live CLI. So today it needs a *partial* or transient failure to fire. It is
untested, undeclared, and reachable.

The cheap fix, if you want one: count consecutive `open_tab` failures per session and write the
cooldown at the 2nd or 3rd. Stale state self-heals on the first (the whole point of `8c2b07f`),
a tab-incapable adapter still converges, and the spec scenario becomes true again.

**2. Retiring writes a false marker on a healthy run.** `dead_mark` stamps `DISPATCH-FAILED`
into the *target's* run dir — a run that dispatched fine and whose agent is still working.
`run-pane-agent.sh` overwrites `agent-exit` with the real status on completion, so it
self-corrects; but until then the durable trail misreports a healthy run's fate, and the retire
event itself is written nowhere durable (inferable from the failing dispatch's `route` plus its
own marker, not stated).

**3. The new breadcrumb is undocumented.** `<run-dir>/route` appears in no skill, no ADR, no
spec — only in session memory. The `ROUTE:` stderr line explains itself when you see it; the
durable copy is discoverable only by reading 450 lines of dispatcher. A post-mortem artifact
nobody is told the location of is a partially delivered fix. One line in SKILL.md closes it.

**Is deferring the root cause defensible? Yes.** Nothing writes `agent-exit` when a pane dies
abnormally, so a hand-closed pane still inflates the count — but the retire now makes that
**self-healing**: the first overflow that hits it costs one spawn going in-process, then the
count is right. That is a bounded, non-destructive residual, and an exit trap in
`run-pane-agent.sh` is a real change to the pane runner with its own test surface that does not
belong at the tail of a 37-commit branch. I'd ship the deferral. What I would *not* ship
unremarked is that the over-count direction is now bounded while the **under-count direction
(finding 1) is not**, and that one was introduced here.

**NIT 1 graded cosmetic — I agree.** The round-robin index still advances on a failed
`open_tab`, so a pane can get skipped, and it can now repeat. But rotation still visits every
pane over time — no starvation, just imperfect fairness — and round-robin is a spec-level
heuristic with least-loaded named as the fallback. Cosmetic is the right grade.

**What genuinely improved, verified not taken on report:** 308/0 with the +6 assertions doing
real work — the new tests rewind the round-robin index so *only* the dead-mark can change the
answer, read the `route` file back out of the failing dispatch's own run dir, and explicitly pin
that `open_pane` still writes the cooldown so the two classifications cannot silently
re-converge. That is careful test design, not padding. `ROUTE` is placed exactly where claimed
(after the `lane` commit point at line 339, before the adapter call at line 348). RUN 1's
finding 3 is fully closed.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | concern | Code contradicts a locked-spec acceptance scenario (cooldown on `open_tab` failure); spec, ADR and SKILL.md unamended; disclosed as task-level when it is spec-level. Deliberate and user-directed, not concealed — hence concern, not fail. |
| `execution` | pass | 308/0 across 7 suites, re-run by me. `shellcheck -x` rc=0. New tests are well isolated. |
| `trajectory` | concern | Downgraded from RUN 1. The fix is well reasoned and its argument was *written down* — which is what let me check it — but the argument silently assumes verb-independent adapter failure, and nobody re-read the spec while reversing behavior the spec pinned. |
| `regression` | concern | Carried: plan implementers move skill-routed → policy-governed. New: a bounded degrade path replaced by an unbounded one (pane count can exceed `max=N` without limit), untested. |
| `context_budget` | pass | `CLAUDE.md` catalog line now accurate, net ~+15 words on one always-on line. Everything else on-demand. |
| `traceability` | concern | Substantially improved — the decisive computation is now recorded, durably, before the risky call, and tested in the failure case. Residual: the artifact's location is undocumented, and SKILL.md's degrade-path list now actively mis-states behavior. |
| `success_masking` | concern | Downgraded from RUN 1. The suites are honest, but the count went **up** (+6) while a safety property went **away**: two assertions were deleted for contradicting the change, and nothing covers panes exceeding `max`. That is the shape this dimension exists to catch. |
| `intent_drift` | pass | Every line of `8c2b07f` traces to a RUN 1 finding. No scope creep, no new deps, no drive-by edits. |
| `checkpoint` | pass | 37 commits, fix isolated in one revertible commit, clean tree apart from the pre-existing unrelated `compliance-judge/` files. `2418e5b` is a clean revert point. |
| `audit_trail` | concern | Downgraded from RUN 1. Branch memo and CODING_MEMORY are unusually complete and self-critical, `Doc-Exempt` carries a real reason — but a behavior change of this rank is recorded only in session memory, not in the spec, the ADR, or the skill. Session memory is not the operating record. |

## Concerns

1. The code contradicts the locked spec's Gherkin scenario "An adapter that cannot tab degrades
   to in-process without blocking … And it writes the session cooldown flag" (spec lines
   137-138, 180-181, 242-246). Spec, ADR 0009 and SKILL.md were not amended; the two tests
   pinning it were deleted; the reversal is recorded only in session memory and a test comment,
   and was disclosed as task-level when it is spec-level.
2. The convergence argument in the new comment holds only if `open_pane` also fails. Against an
   adapter that can pane but cannot tab — the case the spec names — each overflow retires a
   healthy pane, the count drops under N, and the next worker opens a NEW pane: +1 real pane per
   two overflowing dispatches, unbounded, silent, cooldown never written, `max=N` quietly
   exceeded. Untested and undeclared. Mitigated only by all four shipped adapters implementing
   `open_tab` today.
3. `skills/dispatching-pane-agents/SKILL.md` lines 55-58 now actively mis-state the degrade
   paths: it still says adapter failure → cooldown + exit 4, and omits the new exit-3 stale-target
   path entirely. The shipped operating doc disagrees with the shipped code.
4. `<run-dir>/route` is documented in no skill, ADR or spec — a durable post-mortem artifact whose
   location is discoverable only by reading the dispatcher source.
5. `dead_mark` writes `DISPATCH-FAILED` into a healthy, still-running pane's run dir; corrected
   when that agent completes, but until then the durable trail misreports it, and the retire
   event itself is recorded nowhere durable.
6. ROOT CAUSE STILL OPEN (declared): nothing writes `agent-exit` when a pane dies abnormally.
   Deferral judged defensible — the retire makes it self-healing at a cost of one in-process
   spawn — but the accounting can now drift in BOTH directions, and the new direction is the
   unbounded one.
7. Round-robin index still advances on a failed `open_tab` and the skip can now repeat; agreed
   cosmetic (rotation still visits every pane; least-loaded is the named fallback).
8. Carried from RUN 1, unchanged: no live end-to-end run of N panes filling and overflowing on
   real cmux; skill `description` change unverified by measurement; under `inline` the dispatcher
   still opens a pane if invoked directly (guard-enforced only); plan implementers move to
   policy-governed routing on a shipped system.
9. `panes/dispatch-pane-agent.sh` is 450 lines against the 400-line soft limit (was 410); split
   deliberately deferred. `hooks/doc-guard.sh` classifies `CLAUDE.md` as source, so `8c2b07f`
   needed a `Doc-Exempt` trailer — flagged for a separate decision, not worked around.
