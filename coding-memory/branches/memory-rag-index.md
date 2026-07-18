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
