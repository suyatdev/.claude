# Observability judge verdict — verification-marker-gate, round 2 (architecting, advisory)

- repo: `tracking-feature-state`
- branch: `docs/post-merge-53`
- head_sha: `029480968e5e149abe8a7e8314a7c732a8774532`
- stage: `architecting` (advisory — no implementation exists; checklist 0/15, `phase: planning`, `branch: none`)
- ts: `2026-08-13T03:56:22Z`
- doc judged: `docs/features/verification-marker-gate.md` (revision 8, 1414 lines; waived past the 800-line
  ceiling by explicit user decision, measured in §Standing decisions)
- prior verdict: `2026-08-13-docs-post-merge-53.md` (round "6" of the spec's own numbering,
  head `287add5`, architecting, risk=medium)

## What was changed

This is still a design document, not code — a plan for a `git commit` gate that refuses to let a
file ship unless its test suite has actually passed against the exact bytes being committed. Since
the verdict this file replaces, two more passes landed:

- **Revision 7** fixed the bug my last round found: the design used to check "did the test suite
  run" *before* checking "is this repo even using this feature," which meant a repo that had never
  opted in could still get blocked by a broken file this feature introduces. That's fixed — the
  opt-in check now sits above almost everything else.
- **Revision 8** is a **deliberate cut, not a bug fix**: the user decided to remove the two
  built-in ways to *watch* the gate working — a log of every block/bypass, and a `--status`
  command — because keeping them was the reason the document had grown to 1,448 lines against an
  800-line house limit. Removing them, plus folding two rare cases into one generic "unsupported"
  bucket, got it down to 1,380. A follow-up commit then formally waived the still-unmet 800-line
  limit for this one file, backed by a real measurement (delete every sentence of prose and the
  file is still 741 lines of tables/scenarios/code — there was no version of this spec under 800).

## Does it do what you wanted?

The core mechanism — block a commit if its test never actually ran against that exact version —
is still fully specified and, if anything, more rigorously nailed down than last round: 52 Gherkin
scenarios, a 24-mutant floor, a closed whitelist for git's option grammar (with measured proof that
an enumerated list can never stay complete), and a latency figure I re-ran myself just now
(23.6–25.1 ms over 15 runs, matching the 23.8 ms median the spec cites, with the exact command
included so anyone can re-check it later instead of trusting a remembered number). That part earns
its "pass."

**The part that matters most this round is what got cut, and the trade is real, not just
theoretical.** The two things removed were this feature's *entire* observability surface — the log
answered "how often is the gate being bypassed," `--status` answered "is the gate even armed right
now." Both are gone from v1. What replaces them is checklist task 14: a one-time check, run once at
install, that feeds a few real payloads into the installed hook and confirms it says no. That is a
**snapshot**, not a **gauge**. It proves the gate was alive the moment someone remembered to run
task 14 — it says nothing about next month, after a `settings.json` edit, a corrupted classifier
file, or a git upgrade that breaks an assumption the whitelist depends on.

Answering the three questions this round was asked to focus on, directly:

1. **Is a one-off arming check an adequate substitute for a queryable arming state?** No, not on
   its own. It answers "was this armed once," never "is this armed now." The spec itself says this
   plainly (`⚠️ Accepted cost... The residual risk is that the gate goes inert later, silently`) —
   I agree with that self-assessment; I'm not finding a hidden problem, I'm confirming the one the
   design already names is real and not fully closed by task 14.
2. **Is shipping with zero usage telemetry acceptable for a momentum guardrail?** This is the
   sharper of the two gaps. The design's own reason for existing is "a warning placed where the
   mistake keeps being made is a disproven control" — i.e., people rationalize past soft
   reminders. `TEST_EXEMPT` is this gate's soft reminder: type a reason string, the commit goes
   through, and in v1 **that reason is checked for shape and then discarded — it is never written
   anywhere.** There is no way, ever, for anyone to ask "how often is this being bypassed and why,"
   which is exactly the question this feature was built to be able to answer about the weaker,
   pre-existing prose warning it replaces. That is a bigger gap than the arming question, because
   task 14 gives the arming question a partial (if weak) answer and nothing gives this one any
   answer at all.
3. **Does the spec's honesty about the gap adequately mitigate it, or should the feature not ship
   without one of the two?** The honesty is real and above-average for this kind of document —
   named accepted cost, two follow-ups queued, task 12 forces `rules/gates.md` and
   `hooks/README.md` to say plainly that v1 ships with no arming query — and that's worth crediting
   as good practice, not hand-waved. But writing down a gap is not the same as closing it, and my
   job is to say which. **My recommendation: restore the decision log before `--status`, not
   after.** Between the two, the log is the one with zero substitute today (the arming question at
   least gets task 14), and it is the one that speaks directly to this control's own reason for
   being built at all. If only one comes back before this ships, it should be that one.

## What could go wrong / what I'm unsure about

- **Bypass usage is currently unmeasurable and untraceable.** A developer can set `TEST_EXEMPT` on
  every commit, forever, and nothing durable will ever record it — not a log, not the commit
  message, nothing. That's the practical form of the success-masking risk this rubric exists to
  catch: the gate can look 100% healthy (every commit either passes cleanly or carries a validated
  exemption) while quietly doing nothing for weeks.
- **"Armed" can only be checked by hand, and only if someone remembers to.** Without `--status`,
  confirming the gate still works after any change to `settings.json`, the classifier file, or a
  git upgrade requires manually re-running task 14's probe — there's no cheap, ongoing signal.
- **This is still 100% unimplemented** (checklist 0/15, `phase: planning`) — every strength above
  is a strength of the *plan*, not of anything running yet. The 52 scenarios and 24-mutant floor
  are commitments, not results.
- One item from my prior round is now fully resolved and worth naming as a genuine fix, not
  carried-forward risk: the three disagreeing `python3 -I` startup figures (56.3 ms → 20–30 ms →
  ~40 ms) are gone, replaced by one number with a runnable derivation command in the spec. I ran it
  myself (median 24.4 ms) and it landed inside the cited range.

## What I'd double-check before merging

- Before implementation starts, get an explicit answer on whether the decision log comes back into
  v1 scope, given the success_masking/audit_trail gap above — this is a call for the user, not
  something to silently accept because the document names it.
- When task 14 is implemented, confirm it's easy enough to re-run on demand (not just at install)
  so it can double as the "did this go inert" check the design admits it can't otherwise answer.
- Re-verify the 800-line waiver's premise doesn't quietly erode as implementation adds real code
  files around this doc — the waiver is scoped to *this file*, not a blanket exemption for the
  feature.
- Task 1's ADR is still unwritten; confirm it captures the revision-8 scope cut and named
  follow-ups verbatim rather than a summary, since that's the durable record once this document is
  eventually pruned or the checklist marked done.

## Dimension scorecard

| dimension | verdict | why |
|---|---|---|
| intent | pass | Core mechanism (blob-hash receipt gating a commit) is intact, well-specified, and unchanged in substance across both revisions this round covers. |
| execution | pass | No code exists yet (expected at this stage); the verification plan itself is unusually rigorous — 52 Gherkin scenarios, 24-mutant floor, a reproducible latency derivation I re-ran and confirmed. |
| trajectory | pass | Round 1's findings were closed by measurement and reordering (opt-in check, latency re-derivation), not luck; the scope cut is deliberate, user-directed, and backed by a real line-count measurement rather than asserted. |
| regression | pass | No existing files are modified in-scope beyond registration/doc entries (tasks 12-13); pre-existing sibling-guard fail-opens are named but explicitly deferred as separate work, not silently left. |
| context_budget | pass | Read on demand under `docs/features/`, not always-on context; the 800-line waiver is scoped to this one file and its own justification is measured, not asserted. |
| traceability | pass | Exceptionally well-documented: every non-obvious choice carries a measurement, a ⚠️ callout, or a cited line number; an ADR is required at task 1. |
| success_masking | concern | `TEST_EXEMPT` bypass usage is completely unmeasurable in v1 — no log, no durable record anywhere — for a control whose stated purpose is specifically to be resistant to being rationalized past. |
| intent_drift | pass | The scope cut is an authorized, user-directed reduction with a measured justification, not creep; no unauthorized dependencies. |
| checkpoint | pass | Design already specifies revert-pair ordering for the riskiest task pairs (5↔8, 7↔13) before any code exists — good foresight for the implementation stage. |
| audit_trail | concern | Same root cause as success_masking: with the decision log removed and the ADR still unwritten, there is currently no durable record of gate activity or exemption use once this document itself is eventually pruned. |

## Concerns

- The decision log's removal leaves `TEST_EXEMPT` bypass usage permanently unmeasurable in v1 — the
  control's own stated justification (a warning gets rationalized past; a computational receipt
  cannot) does not extend to its own escape valve.
- Task 14's one-off arming check is a snapshot, not a gauge — it cannot detect the gate going inert
  later (config edit, corrupted classifier, git upgrade) without someone remembering to re-run it
  by hand.
- If only one of the two deferred follow-ups (decision log, `--status`) is restored before this
  ships, restore the decision log first — it has no substitute today, while the arming question at
  least gets a partial one from task 14.
- The spec's honesty about both gaps (named accepted cost, queued follow-ups, task 12 forcing the
  gap into `rules/gates.md`/`hooks/README.md`) is real and above-average, but documents the risk
  rather than closing it.
- Everything above scores the plan; zero implementation exists yet (checklist 0/15), so nothing
  here is a verified-working claim.

risk=medium confidence=high
