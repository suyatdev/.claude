# Observability Judge — feature/memory-rag-index (implementation)

- **ts:** 2026-07-18T06:42:05Z
- **repo:** .claude
- **branch:** feature/memory-rag-index
- **head_sha:** 6f2d4e3524e941ac2ad9ea4d552c787e914c7757
- **base:** main (merge-base fec5746)
- **stage:** implementation

## What was changed

A new tool called `memsearch` was added to the `.claude` config repo. Think of it as a
searchable filing cabinet for past Claude Code sessions: every old session transcript gets
summarized ("digested") by a local AI model, those summaries plus the durable docs
(coding-memory, docs, ADRs, project READMEs) are cut into small labeled cards, and each card
gets both a meaning-based fingerprint (embedding) and a keyword index. A query checks both and
merges the rankings, so future sessions can ask "what did we decide about X?" and get the
answer with a file-and-line receipt attached.

Everything runs on the local machine only: one SQLite file (gitignored), a localhost Ollama
model for embeddings and digests, and one Python dependency (sqlite-vec, pinned, user-approved).
A tiny session-start hook prints at most one line telling the agent the index exists — it never
pastes memory into the session on its own.

## Does it do what you wanted?

Yes, and I verified it live rather than trusting the report:

- **Unit/integration tests:** 63 passed (I ran `uv run pytest` myself).
- **Hook harness:** 5/5 passed (`bash hooks/memsearch-nudge.test.sh`) — silent when there is
  no index, exactly one line when there is, silent on malformed status.
- **Golden acceptance:** 16 passed against the real index (`uv run pytest -m golden`).
- **Live index:** `memsearch status` reports 2332 chunks / 228 sources / p95 149 ms /
  qwen3-embedding:0.6b 1024-dim — matching every claim in the trajectory summary.
- **Evidence artifacts exist and agree:** ADR 0002 (SQLite over Qdrant) with revisit triggers
  that match `status.py`'s constants; the digest-accuracy audit report (12 sampled, 1
  unsupported = 8.3%, under the 10% bar); dependency sign-off recorded in the Task 1 commit
  body; all six design-stage judge flags demonstrably closed.

The trajectory itself was disciplined: 23 small feature/fix/test commits, plan-inherited defects
fixed test-first with the failing case proven red before the fix, deviations logged per task in
`coding-memory/branches/memory-rag-index.md`, and a final whole-branch review that caught three
real cross-module seam bugs (model-mismatch guard in `search()`, missing-DB guard in
`rename_repo()`, full-rebuild coverage).

## What could go wrong / what I'm unsure about

- **"16/16 golden" overstates the enforced bar.** Only the 11 "must" queries can actually fail;
  the 3 stretch and 2 negative queries are warn-only by construction — they can regress forever
  and the suite stays green. The rationale (RRF has no absolute confidence floor) is sound and
  documented in the test file, but read future green runs as "11 enforced + 5 monitored."
- **`memsearch index` exits 0 even if every source errored.** Errors go to stderr and the
  report, but a scripted/cron run checking only the exit code would call a fully-failed backfill
  a success. This is recorded as accepted debt (fail-slow on Ollama-down), so it's a known
  trade, not a surprise — but it is the one place green can mask red.
- **The privacy gate checks model names, not the endpoint.** Config refuses any model with
  "cloud" in its name, but `ollama_url` is never validated as localhost — an edited config
  would ship private transcript content wherever that URL points. Low risk (the config is
  local and user-owned) but the "local-only" invariant is enforced only halfway.
- **One golden expectation was tuned after seeing live results** (expected path changed to the
  file the truth actually lives in — honestly logged and truth-verified). Fine, but it means
  the bar is calibrated to today's corpus, not independent of it.
- **Digest accuracy is a point-in-time audit.** 1 of 12 digests paraphrased a git command
  inaccurately. There's no recurrence schedule as the corpus grows; hallucinated digests are
  auditable via provenance but not prevented.
- **keep_alive:0 lives only on `chat()`.** The 0.6b embed model relies on Ollama's default
  ~5-minute auto-unload, so "zero idle RAM" is instant for the 21 GB digest model but takes a
  few minutes for the small one. The live 310 s verification is consistent with this; the
  summary's "unconditional keep_alive:0" is slightly stronger than the code.

## What I'd double-check before merging

1. Decide whether `memsearch index` should exit non-zero when `errors > 0` (one-line change)
   before anyone wires it into automation.
2. Confirm you're comfortable that stretch/negative goldens can never fail CI, or add a count
   threshold later.
3. Consider validating `ollama_url` is a loopback address in `load_config` as a cheap
   belt-and-suspenders privacy guard.
4. Skim the one UNSUPPORTED digest (session b282f601) in the audit report to confirm the
   miss is as benign as logged.

## Dimensions

| Dimension       | Verdict | Note |
|-----------------|---------|------|
| intent          | pass    | Exactly the spec'd system; all design-stage flags closed with evidence |
| execution       | pass    | 63 + 5 + 16 tests run live by the judge; live index healthy (p95 149 ms) |
| trajectory      | pass    | Per-task subagent + reviewer, RED-proven fixes, deviations logged, final seam review |
| regression      | pass    | Additive subsystem; shared-file touches limited to settings hook append + .gitignore; nudge always exits 0 |
| context_budget  | pass    | One conditional line at SessionStart; never auto-injects chunks; no new always-on rules |
| traceability    | pass    | ADR 0002, spec, plan, branch log, audit report, commit rationale all present and consistent |
| success_masking | concern | Warn-only golden tiers can't fail; `index` exits 0 with errors; golden bar tuned to live corpus |
| intent_drift    | pass    | Settings/model-pref chores are this repo's session-housekeeping norm, disclosed and separate; dep signed off |
| checkpoint      | pass    | 23 atomic commits, clean revert points; unrelated working-tree files kept out of every commit |
| audit_trail     | pass    | Attributable commits with session links; dep sign-off in commit body; eval report persisted |

## Concerns

- Golden bar enforces only the 11 must-queries; 3 stretch + 2 negative are warn-only and structurally can never fail — "16/16" overstates the enforced bar.
- `memsearch index` exits 0 even when every source errors (accepted fail-slow debt); scripted runs can't detect failure by exit code.
- Privacy gate refuses "cloud" model names but never validates ollama_url is localhost — a config edit could send transcripts off-box.
- One golden expectation was tuned to the live index after a miss (logged, truth-verified) — the bar is calibrated to today's corpus.
- Digest audit is point-in-time (12 samples, 1 unsupported at 8.3%); no recurrence schedule as the corpus grows.
- keep_alive:0 only on chat(); embed model relies on Ollama's default ~5-min unload, so zero-idle is not instant for it.

**risk:** low · **confidence:** high
