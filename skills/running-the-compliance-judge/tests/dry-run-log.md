# Loop Dry-Run Log — 2026-07-18

End-to-end rehearsal of the `running-the-compliance-judge` loop, agent @ 2f7161a, Sonnet 5
wrapper dispatches (per `tests/README.md`), stores under `tests/out/dryrun-*-store/` (gitignored).
The orchestrator played the reviser role exactly as the skill prescribes; round > 1 dispatches
passed the prior round's violations for exact-id reuse.

## Convergence rehearsal (`dryrun-spec.md`, copy of seeded-unpinned-version.md)

| Round | Verdict | Violation ids | Loop decision |
|---|---|---|---|
| 1 | fail | `writing-specs/pinned-versions`, `writing-specs/unambiguous-requirements` (stdin path) | revise (fix both) |
| 2 | fail | `writing-specs/edge-case-coverage` (NEW — promoted from a round-1 note once the stdin fix exposed it) | revise (new id, not persistent) |
| 3 | pass | — | proceed to user review |

- Round 2 did NOT re-cite either round-1 id after the fixes — resolved violations don't linger.
- Round 2's new violation was correctly treated as non-persistent (new id) → revise, not escalate.
- Round 3 resolved the carried id without re-citing it. **Convergence: OK** — and note it used
  all 3 rounds: one more finding would have escalated at the cap, which is the designed behavior,
  not a failure.
- Observed pattern worth knowing: the judge may promote a round-N non-blocking note into a
  round-N+1 violation when an adjacent fix makes the ambiguity concrete. Legitimate under the
  loop (new id → revise); it is why the cap exists.

## Escalation rehearsal (`dryrun-esc.md`, copy of seeded-embedded-secret.md)

| Round | Verdict | Violation ids | Loop decision |
|---|---|---|---|
| 1 | fail | `core-conduct/hardcoded-secret`, `core-conduct/yagni` | revise (deliberate NON-fix: Telemetry sentence reworded, key kept) |
| 2 | fail | `core-conduct/hardcoded-secret`, `core-conduct/yagni` — **same ids, reused exactly** | **ESCALATE** (same id in two consecutive rounds) |

- Id reuse across dispatches verified — the round-2 judge re-cited both prior ids verbatim when
  handed the round-1 violations, exactly as the id-stability amendment requires.
- The escalation condition (same id, two consecutive rounds) fired correctly; per the rehearsal
  contract the user was NOT actually prompted — the trigger firing is what was under test.
  **Escalation trigger: OK**
- Store append behavior verified in both rehearsals: rounds 2/3 appended sections to the same
  first-round-dated file (glob-first), and `verdicts.jsonl` accumulated one valid line per round.

## Addendum — round>1 glob verified at HEAD (agent @ cf4efc7, 2026-07-18)

Observability-judge concern closure: the date-anchored glob fix (87b2d37) landed after the
rehearsals above, leaving round>1 append behavior unverified at the shipped bytes. Re-ran the
escalation store with a round-3 dispatch at HEAD: the glob `????-??-??-dryrun-esc.md` matched
the existing first-round-dated file and appended its section there (no new file), and both prior
ids were re-cited verbatim (the escalation condition would fire again, spec unchanged between
rounds — the judge itself noted the identical spec_blob_sha). Round>1 append + id reuse now
directly evidenced at HEAD.
