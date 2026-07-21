# Observability Judge Verdict — pane orchestration (architecting, advisory, round 2)

- **Repo:** `.claude` · **Branch:** `feature/pane-orchestration`
- **HEAD:** `468387ac98e0577ffbef33f87ea5465e3c4e0ba9` (one revision commit since round 1's
  `9b6ab0a`)
- **Stage:** architecting (advisory — does not gate)
- **Artifact:** `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md` +
  `docs/decisions/0007-pane-orchestration-supersedes-judge-terminal-enforcement.md`
- **Test command:** none yet (nothing implemented). In its place I re-ran the spec's own
  declared doc check and independently verified the revision's load-bearing platform claim:
  both Mermaid blocks pass `validate-diagrams.sh`; `claude --help` on the installed 2.1.216
  confirms `--bare` "skip[s] hooks … keychain reads, and CLAUDE.md auto-discovery" and
  "Anthropic auth is strictly ANTHROPIC_API_KEY or apiKeyHelper … OAuth and keychain are
  never read" — exactly the semantics the spec cites for rejecting it; all four Tier-1
  guard hooks the spec names exist under `hooks/`; no `panes/` implementation snuck in;
  `CLAUDE_CODE_SESSION_ID` confirmed present in the Bash environment (relevant to the new
  cooldown-flag plumbing, see below).
- **Risk:** low · **Confidence:** high

## What was changed

A revision of the pane-orchestration design (still docs only, no code) responding to
round 1 and the compliance judge's round 1 FAIL. Five substantive edits: (1) the `--bare`
flag is dropped from the pane invocation, so pane sessions keep their safety hooks, global
instructions, and normal login — with the CLI's own help text quoted as the reason;
(2) a "cooldown flag" gives the redirect guard a fourth condition, so after one failed
pane-open the session falls back to today's in-process behavior instead of looping on
denials; (3) the whole toolchain is pinned by version with a re-verify-on-upgrade rule;
(4) the result file both sides build against is now a written contract (jq-extracted body,
exact `PANE_RESULT: DONE|FAILED` final line, content-is-data); (5) adapters never receive
raw caller strings — the dispatcher writes a mode-700 launcher script and hands over only
its path plus an allowlist-sanitized title. The three accuracy nits (round count, patched
ambiguity, validator path) were also fixed.

## Does it do what you wanted?

Yes. Both round 1 design gaps are genuinely closed, not papered over. The deny-loop now
has a concrete escape mechanism with its own error-table row, and the `--bare` reversal is
grounded in a platform fact I verified verbatim against the installed CLI — the revision
even caught a consequence round 1 missed (`--bare` would have broken OAuth auth entirely
on this machine, so every pane would have failed at launch). The reversal is recorded
consistently in the spec, the ADR, and the absorption story, and the follow-up question it
creates ("does `--agent` load user-level agents *without* `--bare`?") is retained as an
explicit smoke check rather than silently dropped. The injection rule and result-file
contract go beyond what round 1 asked for, in the right direction, without scope creep.

## What could go wrong / what I'm unsure about

Nothing at round 1's severity. Residuals, largest first:

1. **Watcher ordering — the one round 1 item the revision did not address.** The
   `context-handoff-watch.sh` section still describes "read the transcript, then check
   fill ≥ 75k and the fired-flag." On a PostToolUse `*` matcher that runs on every tool
   call in every repo, the fired-flag check must come *before* transcript parsing or the
   hook pays the parse cost forever after firing once. One sentence fixes it.
2. **Cooldown-flag plumbing is unspecified.** The dispatcher (a model-invoked script, not
   a hook) writes `panes/state/adapter-failed-<session_id>` — but the spec never says
   where the dispatcher gets the session id. `CLAUDE_CODE_SESSION_ID` exists in the Bash
   environment on 2.1.216 and presumably equals the `session_id` hooks receive on stdin,
   but that equivalence is an assumption; it belongs in Open Questions next to the other
   smoke checks. Stale-flag cleanup under `panes/state/` is also unspecified (harmless
   accumulation, but housekeeping should be decided, not discovered).
3. **ADR 0007's round-count fix missed one spot.** Context now correctly says "verdicts
   through round 6," but Options still says option 1 "Preserves four rounds of judged
   work" — a one-word leftover of the exact inaccuracy round 1 flagged.
4. **Accepted trade, worth naming:** one transient adapter hiccup (e.g. a single cmux
   failure) disables pane dispatch for the *entire rest of the session*. Deliberate,
   visible via the one-line notice, and it degrades to today's behavior — but a flaky
   adapter will make panes quietly rare in practice.
5. Minor: `<run-id>` generation for `panes/state/runs/` is unspecified (uniqueness under
   concurrent dispatches matters; the launcher also embeds the prompt, so the run dir
   should share the launcher's 700 posture).

## What I'd double-check before merging (this doc) / before implementing

- Add the fired-flag-first ordering sentence to the watcher section (item 1).
- Name the session-id source for the dispatcher (`CLAUDE_CODE_SESSION_ID`) and add the
  env-var-equals-hook-stdin equivalence to the Open Questions smoke checks.
- Fix "four rounds" → "six" in ADR 0007's Options section.
- The spec's own retained spikes stand and are correctly parked: `--agent` loading
  `~/.claude/agents/*.md` without `--bare`, cmux non-TTY workspace targeting, the
  `Agent`-vs-`Task` matcher name.

## Dimensions

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Revision maps 1:1 to round 1 + compliance findings; nothing asked-for dropped, no extras beyond the two contracts both reviews implied |
| execution | concern | Still nothing runnable (expected at this stage); declared doc check passes; `--bare` semantics independently verified; three spikes remain open by design |
| trajectory | pass | Reversal driven by a verified platform fact, not review-pleasing; caught the OAuth-breakage consequence round 1 missed; open question retained honestly |
| regression | concern | Round 1's `--bare`/Tier-1 gap resolved; the remaining item is the still-unspecified fired-flag-first ordering on the every-call watcher |
| context_budget | pass | Unchanged posture: skill on demand, one-line stubs; dropping `--bare` adds per-pane (not always-on) context, intended |
| traceability | pass | Each reversal documented with the verified fact inline, in both spec and ADR; diagrams validate |
| success_masking | pass | Cooldown degrade is visible (one-line notice) and stated plainly as a whole-session trade; waits still bounded; sentinel contract unambiguous |
| intent_drift | pass | Single docs-only commit; every hunk traces to a named review finding |
| checkpoint | pass | One clean revision commit atop round 1's HEAD on the feature branch |
| audit_trail | pass | ADR corrected where it justifies the discard (Context); one stale "four rounds" phrase remains in Options — nit, listed |

## Concerns

1. Watcher fired-flag-before-transcript-parse ordering still unspecified on the
   PostToolUse `*` matcher — the only round 1 item the revision left unaddressed.
2. Cooldown-flag session-id plumbing unspecified: dispatcher is not a hook;
   `CLAUDE_CODE_SESSION_ID` env var exists on 2.1.216 but its equivalence to hook-stdin
   `session_id` is unverified — add to Open Questions. Stale-flag cleanup also undecided.
3. ADR 0007 Options still says "four rounds of judged work"; the round-6 correction
   missed this spot.
4. Accepted trade to keep visible: one transient adapter failure disables pane dispatch
   for the entire rest of the session.
5. `<run-id>` uniqueness/generation unspecified for `panes/state/runs/`; run dir should
   inherit the launcher's 700 posture (prompt lives inside it).
