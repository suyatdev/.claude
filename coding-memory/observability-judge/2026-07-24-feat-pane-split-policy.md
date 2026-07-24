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
