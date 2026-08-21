# Observability judge verdict — verification-marker-gate, round 4 (architecting, advisory)

- repo: `tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `33d9ff978947d2a10d63b62216dd3449164a5999`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, `branch: none`)
- ts: `2026-08-13T16:29:47Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 11, 1,614 lines, `wc -l` confirmed;
  waived past the 800-line ceiling by explicit user decision, §Standing decisions → O3)
- prior verdict: `2026-08-13-docs-post-merge-53-round3.md` (head `9251218`, architecting, risk=medium)

## What was changed

Revision 11 repairs a defect that survived rounds 1 through 3 undetected: the `TEST_EXEMPT` validation
regex, `^[^\x00-\x1f\x7f]{1,200}$`, is Python syntax. The gate that evaluates it, `hooks/test-marker-guard.sh`,
is bash. I did not take the document's word for this — I reproduced it myself on the pinned interpreter.

```
$ bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)   # matches the doc's pinned version exactly

$ bash -c 're="^[^\x00-\x1f\x7f]{1,200}$"; [[ "routine cleanup" =~ $re ]]; echo $?'
2   # regcomp failure — the regex never even compiles, on every input
```

That confirms the defect exactly as revision 11 describes it: the escape hatch this whole feature depends
on for "don't silently rationalise past a warning" was **inert from revision 1 through revision 10** — it
would have denied every exemption, always, with the same message a genuine typo produces. The fix replaces
it with `^[[:print:]]{1,200}$` pinned to `LC_ALL=C`. I reproduced every specific claim made about the
replacement, not just the one about compiling:

```
$ LC_ALL=C bash -c '... [[ "$input" =~ $re ]] ...'
ACCEPT: plain ascii     REJECT: tab        REJECT: newline    REJECT: ESC
REJECT: DEL             REJECT: ZWSP U+200B   REJECT: ZWJ U+200D   REJECT: RTLO U+202E
REJECT: 201 chars        ACCEPT: 200 chars
```

Plus the locale claim specifically — that the `LC_ALL=C` pin is what makes accented letters rejected
(and that the same class is admitted under a UTF-8 locale, which is the stated, accepted cost):

```
LC_ALL=en_US.UTF-8 -> ACCEPTS "rôutine cleanüp"
LC_ALL=C            -> REJECTS "rôutine cleanüp"
```

Every one of these matched the document's claims exactly, on the first run, on the exact pinned bash.
I also re-ran the three log-reading one-liners from §Decision logging against a synthetic four-line log
and confirmed `cut -f2 | sort | uniq -c` correctly separates `EXEMPT` from `BLOCK`, and the day-bucketed
`awk` correctly buckets by date — both closing round 3's concern that those claims were asserted rather
than demonstrated.

## Does it do what you wanted?

Yes, and the fix is narrower and better-verified than the defect it replaces. Point by point against your
four questions:

**1. Would the design's own instrumentation have surfaced this failure?** Only weakly, and only after the
fact. Once code exists, the decision log would record a `BLOCK` line with `MSG_BAD_EXEMPT` for every
single exemption attempt — but field 3 of that line is the constant name, never the raw rejected string,
so nothing in the log tells a reader "this looks like a typo" apart from "this looks like the validator is
broken." The only way to tell them apart is to notice, by hand, that the block rate for that one door is
100% and no `EXEMPT` line has ever been written — a pattern nobody is prompted to look for, since `--status`
(the log's one designed reader) remains deferred to a follow-up.

More concretely: I checked task 14, the checklist's **only** pre-PR proof that the gate is armed. It pipes
a plain commit, a bundled `-am` commit, and a wrapped `rtk` commit, and checks each blocks; then repeats
from a non-adopting repo and expects allow. **It never exercises `TEST_EXEMPT` at all.** Had this defect
survived past the TDD step (tasks 2/6, whose scenarios *would* have caught it — "an explicit exemption is
honoured and logged to a file" cannot pass against the broken regex) into an installed hook, task 14 would
report a clean "armed" pass while the escape hatch stayed permanently dead. That's a real, specific gap,
not disclosed anywhere in the document, and it's the same shape of blind spot as the defect just found:
a checklist item that looks like proof of a property it doesn't actually check.

**2. Is the exempt log honest about its diagnostic value, and is the rate signal real?** Yes on both. The
document is explicit — "it is instrumentation, not evidence," machine-local, `0600`, deletable by whoever
wrote it — and I could not find anywhere it overclaims past that. The rate signal (bypass count, bypass
rate by day, which doors fire) is genuinely derivable from the recorded fields; I proved it against a
synthetic log rather than trusting the prose. The one gap is the one named above: field 3's constant-only
granularity for `BLOCK` lines can show *that* something is wrong but not directly *what*.

**3. Is skipping `scan-invisible-unicode.sh` the right call?** Yes. That hook exists, passes its tests, and
is not registered in `settings.json` — I confirmed both (file present; no hit in `settings.json`). Routing
a live door through a dormant, unwired control would mean this feature's correctness depends on someone
else finishing separate, open work — and it turns out to be unnecessary: `[[:print:]]` under `LC_ALL=C`
already rejects every one of ZWSP, ZWJ, and RTLO, which I confirmed directly rather than taking the
document's word for it. The broader "four dormant hooks, no bypass variable" governance gap named in
`rules/gates.md` is real but is repo-level, pre-existing, and correctly out of this feature's scope.

**4. Any other place a property is asserted but never runtime-checked, same shape as the regex bug?** I
scanned the document for every other bash-evaluated pattern and cross-checked two of its other cited
artifacts against the actual repo: `WRAPPERS` at `hooks/lib/shell_segments.py:64` matches verbatim, and
the dormant-hook claim about `scan-invisible-unicode.sh` is accurate. I found no second instance of
Python syntax reaching a bash evaluator. The one gap that *is* the same shape is the task 14 finding
above — a designated verification step that doesn't cover the surface it's implicitly trusted to cover.

## What could go wrong / what I'm unsure about

- **Task 14 doesn't test the exempt path.** This is the main actionable finding this round. It's not a
  defect in what's built yet (nothing is), but a gap in the one checklist item positioned as "the only
  proof v1 has that the gate is armed" — and that proof currently can't tell a live exemption hatch from
  a dead one.
- **The log can show something is wrong but not what.** A `BLOCK`/`MSG_BAD_EXEMPT` line never carries the
  rejected reason string, so distinguishing "broken validator" from "user typo" needs someone to notice an
  unusual rate by hand — plausible, but not structural, and there's no reader (`--status`) prompting anyone
  to look.
- Everything above is still a property of the plan. Checklist is 0/15; nothing has run.
- The file keeps growing under an already-granted waiver (1,576 → 1,614 lines this revision, +38). Not a
  new issue and not something to relitigate per the document's own standing decision — worth eyeballing at
  the next revision, nothing more.

## What I'd double-check before merging

- Extend task 14 (or add a task 14b) to pipe one payload carrying a **valid** `TEST_EXEMPT` and confirm
  exit 0 plus one `EXEMPT` log line — the arming check currently proves every block door fires but never
  proves the one allow-with-a-receipt door does.
- When `--status` is eventually built (follow-up 1), consider whether it should surface the `MSG_BAD_EXEMPT`
  rate specifically, given it's the one door whose 100%-vs-normal rate is the only way to tell "broken"
  from "typo" apart today.
- Nothing else from this round blocks — the regex fix itself is verified correct on the pinned toolchain,
  the log-reading commands work as documented, and the dormant-hook decision is sound.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | Fixed exactly the defect identified — Python-syntax regex evaluated by a bash gate — nothing more, nothing less. |
| execution | pass | Independently reproduced on the pinned bash 3.2.57: old regex exits 2 (regcomp failure) on every input; new regex accepts/rejects exactly as claimed, including the byte-vs-character and locale-sensitivity claims. |
| trajectory | pass | Root-caused, not patched: identifies that the earlier disclosure (round 3) tested the regex in the wrong language engine (Python, not bash), which is why ten revisions missed a regex that never compiled. |
| regression | pass | No code exists to regress; the prose change is bounded, with an explicit "what does not change" paragraph. |
| context_budget | pass | `docs/features/`, read on demand; grew +38 lines under an already-granted, already-justified waiver — a trend to watch, not a new violation, and the document explicitly forecloses relitigating the waiver. |
| traceability | pass | Exact bash version, exact commands, framed as measured rather than recalled — and I reproduced every one independently rather than trusting the prose. |
| success_masking | concern | Task 14, the sole pre-PR "the gate is armed" check, never exercises `TEST_EXEMPT` — the exact path that was silently broken for ten revisions could go dark again post-implementation and this checklist item would still report a clean pass. |
| intent_drift | pass | Change is scoped to the exemption-regex passage and its direct cross-references; declining to depend on the dormant Unicode scanner is itself a scope-discipline decision, not scope creep. |
| checkpoint | pass | Isolated, revertible commit (`33d9ff9`) on a clean chain of individually-revertible prior revisions. |
| audit_trail | pass | Dated, attributed, cites the exact measurement and the exact prior (wrong-engine) finding it corrects; the log's own evidentiary limits are self-disclosed. |

## Concerns

- Task 14 (the design's only pre-PR arming proof) does not exercise `TEST_EXEMPT` at all — a defect in
  that path, including a recurrence of this exact one, could pass task 14 clean.
- The decision log's `BLOCK` line records the `MSG_*` constant but never the rejected raw exempt string,
  so "validator broken" vs. "user typo" is distinguishable only by noticing an unusual rate by hand, with
  no reader (`--status` is deferred) prompting anyone to look.
- File size continues to grow under the existing waiver (+38 lines this revision) — not a new violation,
  worth a glance next revision.
- Still 0/15 implemented; every finding here is a property of the plan, verified against the pinned
  toolchain, not of running code.

risk=low confidence=high
