# Observability verdict — `feat/tracking-feature-state` (architecting, advisory) — round 2

- **Repo:** `tracking-feature-state` (worktree of `~/.claude`)
- **Branch:** `feat/tracking-feature-state`
- **HEAD:** `01f0c45ba7e998448183b175a438156203b33dd0`
- **Base:** `main` (merge-base `fe55b2d5052d85deb87283eab6c6545e17b56e40`)
- **Stage:** `architecting` — advisory, does not gate a PR
- **Prior read judged:** `128e79c` (2026-08-11T15:42:05Z) — this round covers the two commits since:
  `686057d` (fix three cited spec-text defects, re-confirm the spec-half size waiver) and `01f0c45`
  (record the `confirm_timeout` gap and the code-not-spec decision to close it).

## What was changed

Two documentation-only commits (verified: `git diff 128e79c..HEAD --stat` touches only
`docs/features/tracking-feature-state.spec.md`, `CODING_MEMORY.md`, and this judge's own memory
files — no line in `task-tracker/*.py` moved). The first commit fixed three wording defects my
predecessor's round flagged: a `405` row that, read literally, made the feature's own state-changing
route (`POST /command`) a `405`; a claim that a `cmux send` exit code is "logged server-side" when
the structured audit line has no field for it; and the word "bijection" describing a status→reason
mapping that the design deliberately does not have (several statuses collapse multiple reasons). The
second commit records a new finding, made while re-deriving the numbers behind that third fix: the
spec names an audit value `confirm_timeout` in four places, but the code path that would emit it
(`confirm_surface()`) collapses a timeout and a plain failure into one indistinguishable state. The
user's decision — recorded correctly — is that `server.py` gets a small edit to split that state,
landing as its own commit **before** task 9's test, never in the same step.

## Does it do what you wanted?

Yes, and it went a step further than "wanted." All three defects I'd have flagged are fixed, and I
independently re-checked each fix against `task-tracker/server.py` rather than taking the commit
message's word:

- **405 row** — confirmed correct: `GET /command` and `POST /` are the only method/path pairs that
  actually hit `self._method_not_allowed()`; `POST /command` and `OPTIONS /command` are handled by
  their own routes, matching the corrected prose exactly.
- **Exit-code claim** — confirmed correct: `server.py:273` writes the exit code with a bare
  `sys.stderr.write`, not through `audit()`; the structured line at `server.py:134` indeed carries no
  exit-code field.
- **"Bijection" → "total coverage in both directions"** — I re-ran the *exact* grep the spec now
  embeds (`grep -oE '_fail\([0-9]+, "[a-z_]+", "[a-z_]+"' task-tracker/server.py | sed …`) and got 14
  distinct `(status, reason)` pairs, five of them `403` (`bad_token`, `host_mismatch`,
  `origin_mismatch`, `path_escape`, `unknown_id`) and one `502` (`confirm_failed`). That confirms the
  commit's corrected `403 → five` count. Reading the surrounding code by hand (not the grep) turned up
  a second `502` reason, `send_failed`, emitted at `server.py:582` via a bare `audit()` call that
  bypasses `_fail()` entirely — so the code does emit two `502` reasons, matching the commit's
  `502 → two` claim, but **the grep the spec now tells a reader to re-run does not find the second
  one** (see concern below).
- **`confirm_timeout` gap** — confirmed real, independently: `confirm_surface()`
  (`server.py:236-253`) returns the single string `"unrunnable"` for both `TimeoutExpired` and a
  non-zero/`OSError` exit, and the caller (`server.py:574-576`) maps that one state to
  `reason="confirm_failed"` unconditionally. `confirm_timeout` cannot be produced by the code as it
  stands today. Task 9, as currently written, requires driving a request that produces it — which is
  currently impossible. Recording this as a **code** change (not a spec relaxation) and deferring it to
  its own pre-test commit is the right call under this repo's own testing discipline (never edit tests
  and the thing under test in the same step), and it is exactly the class of defect — "the document
  names a value the code cannot emit" — that this card's entire audit-log section exists to prevent.

Both the task-number sync check (`hooks/lib/feature_tasks.py … tracking-feature-state`, exit 0) and
the acceptance-criteria count (`awk … | wc -l` over `## Acceptance criteria` → 15) still hold.

## What could go wrong / what I'm unsure about

- **The newly-written derivation itself has the exact blind spot this card spends a whole preamble
  warning about.** The reproducing command added at spec.md's `reason` bullet
  (`grep -oE '_fail\(…)'…`) only sees reasons emitted through the `_fail()` helper. `server.py:582`
  emits `reason="send_failed"` through a bare `audit()` call instead, so running that command today
  returns `502 confirm_failed` only — a false single-reason answer for a status the surrounding prose
  correctly lists as two-valued (`send_failed`, `confirm_failed`/`confirm_timeout`). Nobody is
  currently misled by it, because the enum text two sections later already names `send_failed`
  explicitly — but a reader who trusts the command over the prose, exactly as this card repeatedly
  instructs, gets the wrong answer. This is a real, if minor, documentation defect, and it is ironic
  given what this round's commits were fixing.
- **Task 8 stays ticked with no note pointing at the fix `confirm_timeout` now requires.** The gap
  lives in `server.py`, which is task 8's own deliverable, and the fix is a small but real code change
  to a component already marked done. The card has an established pattern for exactly this situation —
  task 4 was explicitly "re-opened in round 11" when a gap was found in its own output — but task 8's
  checklist entry in the `.md` half carries no equivalent marker; the only place this is written down
  is a `⚠️` bullet nested inside task 9's spec entry. Someone scanning the terse `.md` list alone would
  not learn that task 8's own file needs a further edit before task 9 can be satisfied.
- **The compliance judge has not been re-run against either of these two commits.** Both are
  spec-editing commits, and `CODING_MEMORY.md`'s own session-66 entry says "compliance re-enters at
  round 1" — the last recorded compliance pass (round 3, `verdicts.jsonl`) is pinned to `128e79c`'s
  blob, which this round has since edited twice. Not a defect in what shipped, just an open obligation
  the commits themselves correctly flag but have not yet discharged.

## What I'd double-check before merging

1. Re-run (or replace) the `502`/`403` reason-coverage grep so it also catches bare `audit()` calls —
   or note explicitly, next to the command, that it only covers `_fail()`-routed reasons and that
   `send_failed` is a known exception. Either is cheap; leaving the command silently wrong is not, given
   task 9 is told to treat it as authoritative.
2. Either tick a re-open marker on task 8 pointing at the `confirm_timeout` fix, or fold that note into
   task 8's own `.md`/`.spec.md` entries, so the gap is visible from the terse checklist and not only
   from inside task 9's detail.
3. Re-run the compliance judge against `01f0c45` before treating this spec as settled — it is due, by
   this repo's own convention, and hasn't run yet.
4. Nothing here blocks continuing — this is an advisory architecting-stage read, and the two commits
   under review are a net improvement with one small documentation defect of their own.

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Fixed exactly the three cited defects, verified against source, and surfaced a real new gap along the way rather than patching around it. |
| execution | concern | No test command was in scope (docs-only change); the one reproducing command this round adds is itself under-scoped (misses a bare-`audit()` reason). |
| trajectory | pass | Re-derived disputed numbers from source instead of trusting the prior verdict's word; found they were wrong; recorded the derivation instead of a new number, per the card's own rule. |
| regression | pass | No source file touched; task-sync check and criterion count both still verify clean. |
| context_budget | concern | Both halves remain over ADR-0017 caps under two live, explicit waivers; `.spec.md` grew 1473→1506 (+2.2%) this round, within the card's own re-raise threshold; `.md` unchanged at 216. |
| traceability | concern | Excellent overall (dated, reproducible derivations throughout) but the new `502`/`403` grep has a verified blind spot — the exact failure mode this card's preamble warns about, now present in its own newest addition. |
| success_masking | pass | The opposite of masking: this round exists specifically to un-mask a spec value (`confirm_timeout`) the code could never have produced, which would otherwise have forced a self-fulfilling task-9 assertion. |
| intent_drift | pass | Both commits stayed tightly scoped to the three cited defects, the waiver re-confirmation, and the incidentally-discovered gap — no drive-by edits elsewhere in either file. |
| checkpoint | pass | Two small, independently revertible, correctly `Doc-Exempt`-tagged commits; easy clean revert point. |
| audit_trail | pass | Commit messages and `CODING_MEMORY.md` both narrate what was wrong, how it was found, and who decided the fix — including an honest admission that the prior verdict's own numbers were wrong. |

## Concerns

- New task-9 reason-coverage derivation (`grep -oE '_fail\(...)'`) misses reasons emitted via a bare `audit()` call bypassing `_fail()` — verified it returns only `502 confirm_failed`, silently omitting `502 send_failed` (server.py:582), though the nearby enum prose already lists both correctly.
- `confirm_timeout` gap (verified real) is correctly deferred to a server.py edit ahead of task 9's test, but task 8's checklist entry stays ticked with no reopening marker, unlike task 4's precedent for a completed task with a newly found gap in its own output.
- Compliance judge has not been re-run since these two spec-edit commits; last pass (round 3) is pinned to the pre-fix blob and is stale by this repo's own convention (recorded in CODING_MEMORY.md itself).
- Both size waivers remain live (spec.md 1506 vs <=800, .md 216 vs <=200); spec.md grew +33 lines (+2.2%) since the round-128e79c re-confirmation — within the card's own "handful of lines" tolerance, worth a fresh look if growth continues.
- server.py at 694/800 lines still carries no documented split-deferral note unlike analyze.py's task-3 entry — asymmetry inherited from the prior read, not introduced this round, observed only.
