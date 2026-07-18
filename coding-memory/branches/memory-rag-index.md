# memsearch branch log

- Task 1: scaffold (uv, py3.12, sqlite-vec==0.1.9 signed off) + config module w/ cloud-model + CODING_MEMORY guards
- Task 2: db layer — schema (chunks/vec0 cosine/FTS5/sources/meta/query_log), transactional replace_source, hashes, stats, p95
- Task 3: ollama client — stdlib HTTP, batched /api/embed, /api/chat with keep_alive=0 (zero idle RAM)
