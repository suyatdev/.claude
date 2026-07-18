# memsearch branch log

- Task 1: scaffold (uv, py3.12, sqlite-vec==0.1.9 signed off) + config module w/ cloud-model + CODING_MEMORY guards
- Task 2: db layer — schema (chunks/vec0 cosine/FTS5/sources/meta/query_log), transactional replace_source, hashes, stats, p95
- Task 3: ollama client — stdlib HTTP, batched /api/embed, /api/chat with keep_alive=0 (zero idle RAM)
- Task 3 fix: _post now catches json.JSONDecodeError -> OllamaError (non-JSON/HTML error bodies no longer escape as raw JSONDecodeError)
- Task 4: extractor — JSONL -> clean turns; drops tool payloads/thinking/sidechains/meta, keeps tool names
- Task 4 fix: user list-content now keeps real text blocks (was silently dropped), non-dict JSON lines (null/number) no longer crash extraction
- Task 5: chunkers — header-aware markdown split (merge tiny/split oversized) + per-H2 digest chunks w/ recall_type mapping
- Task 6: digest module — 4-section template, truncate-middle cap, injectable chat
- Task 7: indexer — docs then newest-first transcripts, hash-diff skip, per-source atomic, errors recorded not fatal, status.json
- Task 7 fix: replaced vacuous subagents-exclusion check (glob non-recursive, deep fixture path unreachable) with a glob-reachable test that genuinely exercises is_excluded, RED-proven by temporarily removing the filter
- Task 8: hybrid search — vec KNN + FTS5 BM25, RRF fusion, weight boost, repo/type/since filters, provenance formatting, latency log
- Task 8 fix: brief's test_latency_logged_and_fts_syntax_safe asserted query_log count >= 2 after a single search() call — corrected to >= 1 (log_query fires once per search, matching db.py's p95-over-N-queries design; a second call was never made)
- Task 9: rename (metadata-only, zero re-embed proven by vector-identity test) + status (counts, mismatch, revisit triggers)
- Task 9 fix: escaped SQL LIKE wildcards (%, _) in rename_repo's path-segment match — an underscore in a repo name (e.g. my_repo) previously wildcard-matched unrelated paths, inflating paths_rewritten/sources_rewritten counts (no data corruption; REPLACE is literal), RED-proven with a decoy-path test
- Task 10: eval-digests — seeded deterministic digest-vs-transcript audit, persisted markdown report (judge flag b)
- Task 11: CLI (index/query/rename/status/eval-digests) + bin/memsearch uv wrapper
