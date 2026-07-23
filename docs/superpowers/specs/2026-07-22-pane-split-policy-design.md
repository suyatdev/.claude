# Session Pane-Split Policy — inline / panes(max) / overflow-to-tabs — Design

**Date:** 2026-07-22 · **Status:** Draft, pending compliance + observability judges + user review
**Scope:** `hooks/pane-dispatch-guard.sh` (eligibility + policy read), `panes/dispatch-pane-agent.sh`
(count + overflow), `panes/adapters/*.sh` (new `open_tab` primitive, cmux first), a new per-session
policy state file, and doc touches to `dispatching-pane-agents` + `rules/gates.md`. Follow-on to
pane orchestration (`2026-07-20-pane-orchestration-design.md`, PR #23) and pane layout v2
(`2026-07-21-pane-layout-v2-design.md`, PR #25). The dispatcher/adapter `open_pane` contract, the
result-file contract, and the layout logic are untouched except where named.

## Summary

Give the user per-session control over how substantial subagent spawns are placed. At the **first
pane-eligible dispatch** of a session (not at session start — a SessionStart hook cannot ask an
interactive question), the model asks once: **`inline`** (run everything in-process this session) or
**`panes` with a max concurrent count N**. The answer is recorded in a per-session state file and
honored for the rest of the session. Under `panes`, up to **N panes run concurrently**; a spawn that
would exceed N opens as a **new tab inside one of the existing panes** (round-robin) — never silently
inline, never blocked. Read-only helpers (`Explore`, `Plan`, search agents) are **never** governed:
they always run in-process. The whole feature keeps the pane system's existing **fail-open, degrade-
never-block** philosophy: any parse failure, missing adapter capability, or absent terminal falls back
to today's in-process path.

## Requirements (user's, verbatim intent)

Original ask: *"a hook that before any session starts would ask me if I want to split the
sub-agents/spawns into panes, the max limit I want the panes to split to, or if I want to just do
inline."* Refined through brainstorm Q&A into the decisions below. The literal "hook that asks at
session start" is not buildable — hooks are non-interactive — so the *trigger* is a hook (the existing
PreToolUse guard) and the *asking* is model behavior via `AskUserQuestion`.

## Decisions locked during brainstorm (Q&A complete 4/4, 2026-07-22)

1. **Trigger = lazy, at first pane-eligible dispatch.** No blocking prompt at session start (zero
   friction on sessions that never spawn a worker). The existing `pane-dispatch-guard.sh` becomes the
   trigger point.
2. **Scope = worker fan-out.** Governed: the two judges, plan implementers, `general-purpose`/worker
   agents, and parallel fan-out. **Never** governed (always in-process): read-only `Explore`, `Plan`,
   and search helpers. This flips today's model from an **include-list** (`redirect-agents.conf`) to
   an **exclude-list**.
   - **Accepted trade-off:** plan implementers move from *skill-routed judgment* (today's deliberate
     stance, encoded as a comment in `redirect-agents.conf`) to *hook-governed*. The user confirmed
     this is the intended scope.
3. **Max semantics = max CONCURRENT panes; overflow → tab in an existing pane.** When N panes are
   alive and another eligible spawn fires, it opens as a new tab inside one of the N panes
   (round-robin). It does **not** overflow to inline and does **not** block/wait. As a pane finishes,
   a later eligible spawn can claim a pane again.
4. **cmux is the primary target** (the user's terminal — `terminal-detect.sh` returns `cmux`). tmux is
   buildable (panes up to N, then reuse windows as tabs). iTerm2 (`split`-only adapter) and
   Terminal.app (tab-only, no splits) have no native "tab inside a pane"; they **degrade** to "tab in
   the same window" / already-all-tabs. The feature is not held hostage to non-cmux parity.

## Toolchain — pinned

No new dependencies. Uses the tools already on the pane path: `bash`, `/usr/bin/jq` (payload parse),
the cmux CLI (`/Applications/cmux.app/Contents/Resources/bin/cmux`), and macOS `osascript` for the
iTerm/Terminal adapters. Exact versions are those already pinned by the repo's existing pane specs;
this design adds none.

## Components

### `hooks/pane-dispatch-guard.sh` — eligibility + policy read (moderate change)

Today: reads `redirect-agents.conf` as an **include-list**, denies in-process dispatch for listed
types when a terminal exists, fails open. New behavior, evaluated in order after the existing
recursion guard (`CLAUDE_PANE_AGENT` set → exit 0) and jq/terminal availability checks:

1. **Eligibility (exclude-list).** If `subagent_type` is in the read-only exclusion set, exit 0
   (allow in-process); otherwise the type is *governed*. The exclusion set lives in a config file —
   either `redirect-agents.conf` repurposed as an exclusion list, or a new
   `panes/inprocess-agents.conf` (choice deferred to planning). Current members: `Explore` and
   `Plan` (the registry's only read-only/search agents); extend as new read-only helper types
   appear. The `pane-echo` test fixture is not dispatched for real work and needs no entry.
2. **No policy recorded for this session** → **deny (exit 2)** with structured guidance instructing
   the model to: call `AskUserQuestion` (choices: `panes` + a max N, or `inline`; suggest a default
   N), write the answer to the policy file, then retry the dispatch.
3. **Policy = `inline`** → exit 0 (allow in-process).
4. **Policy = `panes`** → deny (exit 2) with today's redirect-to-`dispatch-pane-agent.sh` guidance.
   The dispatcher owns the pane-vs-tab / max-N decision.

Fail-open is preserved: unreadable policy file, missing conf, jq failure, `term == none`, or an
adapter-failure cooldown flag → allow in-process (exactly today's degrade).

### `panes/state/pane-policy-<key>` — new per-session state file

- **Format:** one line, either `inline` or `panes max=N` (N a positive integer).
- **Key:** the session identifier, resolved the same way the codebase already resolves it — stdin
  `.session_id` for hooks, `$CLAUDE_CODE_SESSION_ID` for the dispatcher, with the literal `nosession`
  fallback when the env var is empty (mirrors the `adapter-failed-<key>` flag convention in
  `pane-dispatch-guard.sh` and `dispatch-pane-agent.sh`). The guard already surfaces a stdin/env
  session-id divergence warning; reuse it.
- **Lifecycle:** written once by the model at first eligible dispatch; read by both the guard and the
  dispatcher thereafter. Swept by the dispatcher's existing `cleanup_stale` (files older than
  `STALE_DAYS`), so no new housekeeping.

### `panes/dispatch-pane-agent.sh` — count + overflow (largest change)

On a `dispatch` of a governed type under `panes max=N`:

1. **Count live panes** for this session from `state/runs/` (a run is "live" between its dispatch and
   its completion marker; reuse the run-folder + `run-pane-agent.sh` completion machinery — the exact
   liveness predicate is a flagged assumption, see below).
2. **If live count < N** → `open_pane` as today.
3. **If live count >= N** → select one existing live pane (round-robin via a small rotating index in
   state) and `open_tab` a new agent session into it.
4. **If `open_tab` is unsupported or fails on this adapter** → degrade to in-process (write the
   session cooldown flag exactly as an `open_pane` failure does today). Never block.

### Adapter contract — extended by one verb

Add `open_tab <existing-surface-ref> <title> <launcher-path>` alongside `open_pane`. It attaches a new
agent session as a tab to (or in the same window/group as) an already-open surface, printing the new
surface ref. Per-adapter:

- **`cmux.sh`** — primary. cmux has tabs, panes, and workspaces; `cmux-layout.sh` already reasons about
  tab counts. The exact placement primitive ("tab attached to a pane" vs "tab in the same workspace")
  is **probe-verified** against the live cmux CLI before it is coded (precedent: `cmux-layout-probe.sh`).
- **`tmux.sh`** — panes up to N in a window, then a new window as the "tab."
- **`iterm.sh`** — new tab in the current window (sibling of the split panes; iTerm tabs are
  window-level).
- **`terminal.sh`** — already opens every agent as a tab; `open_tab` is effectively its existing path.
- Any adapter lacking a usable tab primitive returns non-zero, which the dispatcher treats as the
  degrade-to-inline case above.

### Docs — `skills/dispatching-pane-agents` + `rules/gates.md`

- Document the session policy (`inline` / `panes max=N`), the lazy first-dispatch prompt, the
  exclude-list, and the overflow-to-tab behavior with its degrade path.
- Update the pane-dispatch-redirect gate stub to note the policy layer.

## Ask mechanics (the model's role)

When the guard denies with the "no policy" message, the model:

1. Calls `AskUserQuestion` — `panes` (with a max N; offer common values e.g. 2/3/4 + custom) or
   `inline`.
2. Writes the chosen line to `state/pane-policy-<key>`.
3. Retries the dispatch. The guard now finds a policy and routes accordingly.

This reuses the guard's established deny-with-structured-guidance pattern; no new hook event, no
SessionStart change.

## Error handling — every path degrades into the dumb in-process path

Consistent with the pane system's existing header contract ("Degrades, never blocks"):

- Guard: any parse/read failure, no terminal, cooldown flag → allow in-process.
- Dispatcher: `open_pane` or `open_tab` failure → session cooldown flag + in-process for the rest of
  the session (today's behavior, extended to cover `open_tab`).
- A missing/corrupt policy file is treated as "no policy" (re-ask), not as a hard error.

## Flagged assumptions (verify at implementation; each has a degrade path)

1. **Liveness predicate for "concurrent panes."** Assumed derivable from `state/runs/` (dispatched
   but no completion marker). If unreliable, degrade to a conservative count or to overflow-inline.
2. **cmux tab placement primitive.** Assumed cmux can open a tab attached to / in the same group as an
   existing pane. Probe first; if only workspace-level tabs exist, "tab in the same workspace" is the
   honest mapping.
3. **Overflow pane selection.** Round-robin assumed sufficient; least-loaded (fewest tabs) is the
   fallback if round-robin clusters unevenly.
4. **Session-id stability across compaction.** Assumed the policy key is stable for a session's life;
   if a `/compact` rotates the id, the model simply re-asks (safe degrade).

## Acceptance scenarios

```gherkin
Feature: Per-session pane-split policy for governed subagent dispatches

  Scenario: First governed dispatch with no policy prompts once, then honors inline
    Given a session with no recorded policy file (no state/pane-policy-<key>)
    When a governed worker (a judge, implementer, or worker agent) is dispatched
    Then the guard denies the in-process dispatch with exit 2 and structured ask guidance
    And the model calls AskUserQuestion, writes "inline" to state/pane-policy-<key>, and retries
    And that dispatch and every subsequent governed dispatch run in-process
    And no pane is opened for the rest of the session

  Scenario: Panes fill to the max, then overflow to tabs
    Given a recorded policy of "panes max=3" and no live panes for this session
    When a fan-out of 5 governed workers is dispatched
    Then workers 1-3 each open a new pane while the live count is below 3
    And workers 4-5 each open a new tab in an existing live pane, selected round-robin
    And nothing runs in-process and nothing blocks or waits

  Scenario: Read-only agents are never governed and consume no slot
    Given a recorded policy of "panes max=3"
    When an Explore (read-only) agent is dispatched
    Then the guard allows it in-process because it is on the exclusion set
    And it does not consume a pane slot toward the max

  Scenario: A freed pane is reclaimed rather than tabbed
    Given a policy of "panes max=N" where a pane's agent has completed so the live count is below N
    When a new governed worker is dispatched
    Then it opens a new pane, not a tab, because the live count is below N

  Scenario: An adapter that cannot tab degrades to in-process without blocking
    Given a policy of "panes max=N" with N live panes on an adapter whose open_tab returns non-zero
    When an overflow governed worker is dispatched
    Then the dispatcher degrades that spawn to in-process
    And it writes the session cooldown flag and the session continues without blocking

  Scenario: An inline session opens no pane even for a governed judge
    Given a recorded policy of "inline"
    When a compliance-judge (a governed type) is dispatched
    Then it runs in-process this session and opens no pane
    And inline means no panes at all this session, judges included
```

## Testing

Same discipline as the rest of `panes/` — a `.test.sh` beside each script, fake-binary adapters:

- **Guard:** exclude-list (Explore/Plan allowed in-process); no-policy → exit 2 with ask text;
  `inline` → exit 0; `panes` → exit 2 with redirect text; all existing fail-open cases still open.
- **Dispatcher:** live-count < N → `open_pane`; >= N → `open_tab` with round-robin selection;
  `open_tab` failure → cooldown + in-process; session-id keying (env / stdin / `nosession`).
- **Adapters:** `open_tab` fake-binary tests per adapter; `PANE_DRYRUN` path; arg validation reuse.
- **cmux:** live probe of the tab primitive recorded as a fixture before the adapter code is trusted.

## Constraints carried forward

- Fail-open, degrade-never-block; recursion guard (`CLAUDE_PANE_AGENT`); session-id keying triple
  (env / stdin / `nosession`); `umask 077` on state; no PII/secrets in state files; no new
  dependencies; pinned tool versions.

## Open questions (deferred to planning, not blocking)

- Default max N to suggest in the prompt (candidate: 3, or 4 to match the cmux 2×2 quadrant).
- Exact round-robin vs least-loaded overflow selection (assumption 3).
- Whether `inline` should also suppress the two judges' *existing* always-on pane redirect (this spec
  says yes — `inline` means no panes at all this session; confirm at review).
- Phasing suggestion for the plan (not a scope cut): Phase 1 = policy capture + `inline`/`panes(max)`
  with overflow-to-inline to land the control cheaply; Phase 2 = overflow-to-tabs on cmux (the
  adapter lift). The user's target is tabs; phasing only sequences the delivery.
