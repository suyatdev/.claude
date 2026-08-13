# 0026 — The marker gate does no JSON parsing; one Python call returns plain text

- **Status:** Accepted (2026-08-13)
- **Context:** `docs/features/verification-marker-gate.md` (revision 13, `phase: planning`, 0/15).
  Forced by compliance-judge round 6, which failed the spec on two violations:
  `writing-specs/unpinned-json-parse-classifier-output` and
  `writing-specs/unpinned-json-parse-marker-read`.
- **Decision owner:** user (2026-08-13). Architecture trade-offs and new dependencies are
  human-owned per `rules/core-conduct.md` § Existing and New Work and § Parallel-Agent Invariants;
  the assistant posed the options and did not choose.
- **Supersedes:** the wire contract at §3 nodes `CO`/`M` as written through revision 13.

## Context

The gate (`hooks/test-marker-guard.sh`) is bash. As specified through revision 13 it was required to:

1. parse the classifier's JSON stdout at node `CO` — including a `paths` array and an `exempt` string
   the spec states the classifier **does not sanitise** (`:403`); and
2. read each on-disk marker file at node `M` and validate its `version`/`blob`/`path` fields, after
   independently re-deriving the writer's percent-encoded filename.

Three facts make that unbuildable as written:

- **bash 3.2.57 has no JSON parser**, and none is pinned. `jq` does not appear in §Pinned versions.
- **The latency budget provisions exactly two `python3` starts** for the entire flow (`:836-838`) —
  the cwd read and the classification. Neither covers these validations, and no third is provisioned.
- The spec **cites a precedent it does not follow**. `hooks/git-guard.sh:59-72`, named at `:361` as
  the model for the cwd read, has `python3` parse the JSON and hand bash back a single **plain
  string**; bash never re-parses JSON. Nodes `CO` and `M` abandoned that pattern.

The result was a requirement stating *what* must be validated at an adversarial-input boundary while
leaving *how* to the implementer — the fifth instance of this spec's recurring defect class (a
behaviour required without pinning the construct that produces it; see revisions 11, 12, 13 and the
round-6 observability finding on the log file's mode).

## Decision

**No JSON crosses into bash.** Classification and marker reading merge into a single `python3` entry
point that performs all JSON handling internally and returns **plain tab-separated lines** on stdout,
which bash consumes with `read`. The gate becomes a thin bash wrapper around one Python decision call.

Rejected alternatives, and why:

| option | rejected because |
|---|---|
| Pin `jq` and parse in bash | A genuine new external dependency on every machine the hook runs on. `core-conduct` forbids adding one unilaterally, and `jq` version skew becomes a new pinning surface. |
| Add a third `python3` call, re-budget latency | Three process starts on every `git commit`. The two-start budget was a deliberate constraint, not an accident. |
| Drop JSON everywhere for flat key=value | Viable and genuinely close. Not chosen: it rewrites the marker schema and still leaves two components to keep in sync, where this decision collapses them to one. |

## Consequences

- **Process starts should go down, not up.** Merging classification and marker reading into one call
  means the budget is renegotiated in the favourable direction. ⚠️ This is an *expectation*, not a
  measurement — the merged entry point does not exist yet. The latency budget table must be
  re-measured against the real implementation, not updated from this prediction.
- **The opt-in ordering rule must be re-verified against the merged entry point.** The spec requires
  the classifier to run before repo-state checks so an un-opted-in repo is never touched; folding
  marker reading into the same process puts both behind one call, and that ordering is now internal
  to Python rather than enforced by call sequence in bash. This is the highest-risk consequence of
  this decision and is explicitly open work for revision 14.
- The `MSG_NO_PYTHON` door grows in importance: with one Python call carrying the whole decision, its
  failure mode is the whole gate's failure mode.
- Validation of the unsanitised `exempt` value moves inside Python, where a real schema check is
  available — which is what `writing-secure-code` asks for at a boundary handling adversarial input.

## Status of the spec

Revision 14 applies this, alongside three other round-6 findings (log-file mode enforcement,
percent-encoding order, `awk`/`cut` absent from §Pinned versions). The round-6 verdicts — compliance
FAIL, observability risk=medium — are recorded under `coding-memory/`. Round 7 is owed after
revision 14 lands; the card stays at `phase: planning` throughout.
