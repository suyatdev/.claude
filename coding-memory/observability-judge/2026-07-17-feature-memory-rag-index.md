# Observability Judge Verdict — `memsearch` memory RAG index (design)

- **Stage:** architecting (advisory design-stage read — no code, no gating)
- **Repo:** `.claude` · **Branch:** `feature/memory-rag-index`
- **HEAD:** `c2b23fe4126affdd1959a23459cd1b067de69cde`
- **Timestamp:** 2026-07-17T22:06:17Z
- **Spec:** `docs/superpowers/specs/2026-07-17-memory-rag-index-design.md`
- **Risk:** low · **Confidence:** medium

---

## What was changed

A design spec (not code) for `memsearch`: a local, regenerable RAG index over Claude Code
session history. It lets the agent pull a few relevant chunks of past decisions, bugs, and
conventions on demand instead of loading whole transcripts — saving tokens and enabling
cross-repo recall. Store is SQLite (sqlite-vec exact search + FTS5 keyword), models are
local-only Ollama (Qwen embeddings + a 35B digest model released after indexing), consumption
is a Bash-driven CLI plus a silent one-line SessionStart nudge. The DB is a gitignored,
regenerable cache. The branch diff is the spec plus an 11-line `CODING_MEMORY.md` working-index
update.

## Does it do what you wanted?

Yes, on paper. The design maps cleanly onto the stated problem (expensive, unreliable recall)
and every one of the four recall use-cases has a mechanism. The reasoning is genuinely sound,
not lucky: the SQLite-vs-Qdrant call is argued from measured corpus size with explicit revisit
triggers (>500k chunks or p95 >500ms), and the `CODING_MEMORY.md` exclusion is justified on a
durable-vs-ephemeral principle rather than a hunch. Context budget and zero-trust are treated
as first-class (silent nudge, mandatory provenance, digests-as-data-never-instruction,
local-models-only refusal).

## What could go wrong / what I'm unsure about

The whole payoff — retrieval quality — is deferred to implementation and cannot be assessed
from the spec. The golden-query set is the only quantitative quality gate, and it's a small
hand-picked proxy: a green golden-query run can hide poor recall on the questions nobody thought
to add. Worse, LLM digest accuracy is only "spot-checked," not measured — a confidently wrong
digest could surface as "memory." Provenance makes it auditable, but auditability is not
accuracy. Separately, this introduces a whole new uv/Python subsystem plus a third-party
dependency (`sqlite-vec`) into the global config repo, and a SessionStart hook that fires every
session.

## What I'd double-check before merging (implementation gates)

1. Build the golden-query set for real, and size it beyond the obvious happy-path questions;
   treat it as the acceptance bar, not a smoke test.
2. Add a systematic digest-quality measure (not just sampling) — hallucinated summaries are the
   sharpest correctness risk here.
3. Promote the SQLite-vs-Qdrant store decision to an ADR under `docs/decisions/` — it is exactly
   the direction-setting call the conventions say earns one.
4. Get explicit sign-off on the new dependency + uv subsystem entering the global `.claude` repo
   (per the "never add a dependency unilaterally" invariant).
5. Confirm the SessionStart hook stays truly one-line/silent and never auto-injects — verify it
   on a trivial session.

---

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Design squarely addresses the recall/token problem; all four use-cases covered. |
| execution | concern | No code; retrieval quality entirely deferred and unproven, golden set not yet built. |
| trajectory | pass | Decisions argued from measured evidence with explicit revisit triggers — sound, not lucky. |
| regression | pass | Additive; DB gitignored/regenerable. SessionStart hook is the one always-on surface — kept silent by design. |
| context_budget | pass | Exemplary: one-line nudge, no auto-inject, on-demand chunk pull is the whole point. |
| traceability | pass | Thorough doc + mermaid diagram + rationale per decision. |
| success_masking | concern | Narrow golden set + spot-checked (not measured) digests can let a green suite hide mediocre recall / hallucinated summaries. |
| intent_drift | pass | Scope contained; non-goals explicit. New dep + uv subsystem are stated intent, but need explicit approval at impl. |
| checkpoint | pass | Clean feature branch, 2 tidy commits, off main; cache is regenerable. |
| audit_trail | pass | Attributed, dated, status-tracked. Store decision is ADR-worthy — promote to `docs/decisions/` at impl. |

## Concerns

- Retrieval quality is entirely deferred to implementation; the golden-query set does not exist
  yet, so real-world effectiveness is unproven at design stage.
- Golden-query set is a narrow hand-picked proxy — a green suite can mask poor recall on
  out-of-set queries.
- LLM digests can hallucinate; provenance makes them auditable but does not make them accurate,
  and digest quality is only spot-checked rather than systematically measured.
- SQLite-vs-Qdrant store decision is ADR-worthy but lives in a spec, not `docs/decisions/`.
- A new uv/Python subsystem plus `sqlite-vec` enter the global `.claude` config repo — confirm
  dependency approval explicitly at implementation.
- SessionStart hook fires every session — verify the one-line nudge stays silent/cheap and never
  auto-injects.
