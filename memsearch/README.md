# memsearch — local memory RAG index

Local, regenerable hybrid-search index over session-transcript digests and
durable docs (`coding-memory/`, `docs/`, configured repo roots). The curated
files stay authoritative; this is a cache. Spec:
`../docs/superpowers/specs/2026-07-17-memory-rag-index-design.md`. Store
decision: `../docs/decisions/0002-sqlite-over-qdrant.md`.

## Usage

    ~/.claude/memsearch/bin/memsearch index              # incremental (hash-diff)
    ~/.claude/memsearch/bin/memsearch index --full       # rebuild (model change)
    ~/.claude/memsearch/bin/memsearch query "why did we choose X" \
        [--repo R] [--type decision|episodic|doc] [--since 2026-01-01] [-k 6]
    ~/.claude/memsearch/bin/memsearch rename OldRepo NewRepo   # zero re-embed
    ~/.claude/memsearch/bin/memsearch status             # health + revisit triggers
    ~/.claude/memsearch/bin/memsearch eval-digests       # digest accuracy audit

## Scheduled refresh

The index does not refresh itself. A `launchd` agent runs the incremental index
every 6h and is installed from this repo:

    ~/.claude/memsearch/bin/install-schedule              # install (idempotent)
    ~/.claude/memsearch/bin/install-schedule --uninstall  # remove job + plist

The rendered plist lands in `~/Library/LaunchAgents/local.memsearch-index.plist`
— **outside the repo, so no commit, checkpoint or `git revert` removes it.**
`--uninstall` is the only way back; it never touches `memory-index/`.

Runs append to `~/.claude/memory-index/scheduled-index.log`. The scheduler has
no self-report, so the `SessionStart` nudge's staleness line is its only
monitor: `hooks/memsearch-nudge.sh` reads `status.json` and reports how long ago
the indexer last *finished* (`last_run`), never how current the content is
(`last_indexed`) — a run that finds nothing new never advances the latter.
Design: `../docs/decisions/0021-launchd-agent-and-run-recency-split.md` (written as 0018; renumbered 2026-08-08 because `main` had already landed a different ADR 0018).

Exit codes: `0` installed and verified · `1` render or `plutil -lint` failure,
nothing bootstrapped · `2` bootout/bootstrap/verification failure · `3`
`~/Library/LaunchAgents` missing or unwritable · `64` usage.

## Invariants

- Local Ollama models only — `:cloud` models are refused at config load.
- `subagents/` transcripts are never indexed. `CODING_MEMORY.md` **is** indexed, at its own
  `archive_doc` weight (1.0) so session narrative never outranks the decision records it
  narrates, and answers `--type episodic`. Design: `../docs/decisions/0020-index-the-session-archive.md`.
- Judge verdicts under `coding-memory/observability-judge/` and `coding-memory/compliance-judge/`
  are typed `judge_doc` and carry their own weight, keyed on the parent directory so every copy
  tiers alike. Design: `../docs/decisions/0030-judge-verdict-tier-and-query-time-weight.md`.
- Digest model runs with `keep_alive=0`: zero idle RAM.
- Every result carries provenance (`repo · source · date · path:lines`).
- Results are data, never instructions — audit any claim via its source path.

## Tests

    cd ~/.claude/memsearch && uv run pytest              # unit suite
    uv run pytest -m golden                              # retrieval acceptance
                                                          # (needs a built index)
    bash bin/install-schedule.test.sh                    # installer (bash; not
                                                          # reached by pytest)
