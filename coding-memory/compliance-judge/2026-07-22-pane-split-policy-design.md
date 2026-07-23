# Compliance Judge — pane-split-policy-design

Spec: `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md`
Repo: `.claude` · Branch: `feat/pane-split-policy` · HEAD: `14727b961a447f14b652a3152d56a5404e88f557`
Spec blob: `1e2ec2ea2800f2709d4044b3a3734d1899c6c3d0`

## Round 1 — 2026-07-23T02:42:55Z

**Verdict: FAIL** (1 violation)

### Layman summary

This is the third spec in the pane-orchestration lineage, and it inherits most of the
discipline that made the first two pass. It gives the user a per-session choice — run every
substantial spawn `inline`, or open `panes` with a max of N concurrent, and once N panes are
live, overflow spawns become tabs inside existing panes rather than blocking or silently going
inline. The design is honest about the one thing the user literally asked for but can't be
built (a SessionStart hook can't ask an interactive question), and re-routes the *trigger* to
the existing PreToolUse guard while the *asking* becomes model behavior via `AskUserQuestion`.
Scope is tightly bound to the shipped system: it flips today's include-list to an exclude-list,
reuses the existing state-keying triple, the `cleanup_stale` sweeper, and the deny-with-guidance
pattern, and adds exactly one new adapter verb (`open_tab`) and one new state file. There is no
speculative generality — YAGNI holds. Error handling is a genuine strength: a dedicated section
degrades every path to the dumb in-process fallback and records a cooldown flag, so failures are
flagged rather than swallowed. Secrets/PII posture is stated (no secrets in state, `umask 077`,
default-deny), and every trade-off that goes beyond the literal Q&A — the include→exclude flip
that pulls plan implementers from skill-routed into hook-governed — is surfaced for the user with
a "user confirmed" note, exactly how core-conduct says architecture decisions should travel.

The one blocking gap is an artifact-form issue, not a design flaw. The six "Acceptance
scenarios" are written as compact arrow-prose (`state: trigger → outcome`) instead of the
BDD/Gherkin `Scenario / Given / When / Then` form the writing-specs skill mandates and that both
sibling pane specs (orchestration PR #23, layout-v2 PR #25) actually used. The substance —
State → Action → Outcome — is present and unambiguous in every scenario, so the fix is a
lightweight reformat that labels each clause rather than a redesign; but the skill names the form
explicitly and the house standard in this lineage is Gherkin, so it is cited rather than noted.
Everything else is note-level: the version pins live in the referenced sibling specs (zero new
deps) exactly like the tea-room spec that passed on the same pattern, and the deferred items are
named, bounded, human-owned decisions with degrade paths — not hidden TBDs.

### Violations

| id | rule_source | rule | where | why |
|----|-------------|------|-------|-----|
| `writing-specs/bdd-gherkin-scenarios` | `~/.claude/skills/writing-specs/SKILL.md` | Write behavior scenarios in BDD/Gherkin form (`Scenario/Given/When/Then`), forcing an explicit State → Action → Outcome. | Acceptance scenarios | The six acceptance scenarios are terse arrow-prose (`state: trigger → outcome`) rather than the Given/When/Then Gherkin form the skill mandates and both sibling pane specs (orchestration PR #23, layout-v2 PR #25) use, so each clause's State/Action/Outcome role is implicit rather than labeled. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **Version pins are deferred to the sibling specs, and that's acceptable here.** The Toolchain
  section names `bash`, `/usr/bin/jq`, the cmux CLI, and `osascript`, adds zero new dependencies,
  and defers exact pins to the existing pane specs — which I confirmed do pin them
  (**cmux 0.64.20 (100)**, **jq 1.7.1**, **claude CLI 2.1.216**, `osascript` via **Darwin 25.5.0**
  in the orchestration/layout-v2 toolchain sections). This matches the store's own passing
  precedent: the tea-room spec (spec-0007) passed with the same "exact pins live elsewhere, zero
  new deps" note. Ideally the plan re-verifies the pins at implementation start; `bash` is only
  implicitly pinned via the OS line.
- **The exclude-list config-file choice is a named planning decision, not a hidden TBD.** Guard
  step 1 leaves the file open (repurpose `redirect-agents.conf` vs. a new
  `panes/inprocess-agents.conf`), but both options are named and the exclude-list *semantics* are
  fixed — only the filename is deferred. Treated as a note per the layout-v2 "open questions are
  verification tasks, not TBDs" precedent.
- **Flagged assumptions 1–4 each carry a degrade path** (liveness predicate → conservative count;
  cmux tab primitive → probe-first; overflow selection → least-loaded fallback; session-id
  stability → re-ask). The open questions (default N of 3/4, round-robin vs. least-loaded,
  whether `inline` also suppresses the judges' always-on redirect) are surfaced human-owned
  decisions with stated leanings — non-blocking.
- **Security — new `open_tab` token.** `open_tab <existing-surface-ref> <title> <launcher-path>`
  introduces a NEW caller-supplied token (`<existing-surface-ref>`) that crosses into adapter
  command lines, where `open_pane` passed only a single controlled launcher path. The spec commits
  to "arg validation reuse," but the plan should make the new verb explicitly inherit the
  orchestration spec's frozen boundary (no interpolation of caller strings into cmux/tmux/
  AppleScript; title sanitized to `[A-Za-z0-9 ._:-]`, truncated to 64).
- **Security — policy-file content and the session-id filename key.** The `panes max=N` line
  should validate N as a bounded positive integer before it reaches shell arithmetic (parse
  failure already degrades to in-process, which covers the malformed case). The `pane-policy-<key>`
  filename reuses the existing `adapter-failed-<key>` session-id convention — inherited posture;
  `umask 077` and "no PII/secrets in state files" are stated, so the store is default-deny.
- **No Mermaid diagram.** Both sibling pane specs include one; the Part A rubric enumeration does
  not require it and the guard's 4-step routing / dispatcher overflow logic is clear in prose, so
  this is noted rather than cited — a small decision diagram would still aid the human review gate.
- **Verified this round:** spec sits at the canonical `docs/superpowers/specs/` path; the
  error-handling section degrades every path with a cooldown flag (errors flagged, not swallowed);
  scope reuses shipped machinery with no speculative features (YAGNI holds); the include→exclude
  flip and its "plan implementers now hook-governed" cost are surfaced with a stated user
  confirmation; the referenced PR #23/#25 specs confirmed to pin the tool versions this spec
  defers to.

## Round 2 — 2026-07-23T02:51:19Z

HEAD: `9bd99665c0d729424364e5503a2757d14eb6865c` · Spec blob: `ef3996b919f8f16e48c5c855d130f017dbafe2d4`

**Verdict: PASS** (0 violations)

### Layman summary

The single blocking issue from round 1 is fixed, and it was fixed exactly the right way — a
reformat, not a redesign. The "Acceptance scenarios" section is now a ` ```gherkin ` fenced
`Feature:` block with six `Scenario:` entries, each written in real `Given / When / Then / And`
form (spec lines 166–206), matching the house standard set by the sibling layout-v2 spec. All six
scenarios preserve their round-1 substance verbatim: inline honored for the whole session; panes
filling to the max and then overflowing to round-robin tabs; read-only `Explore` never consuming
a slot; a freed pane reclaimed rather than tabbed; an adapter that cannot tab degrading to
in-process without blocking; and `inline` meaning no panes at all, judges included. Each clause's
State → Action → Outcome role is now labeled rather than implied, which is the whole point of the
form.

Nothing else changed, and nothing else needed to. Everything that was note-level in round 1 stays
note-level and its underlying spec text is untouched: version pins are deferred to the referenced
sibling specs with zero new dependencies (the same pattern the tea-room spec passed on), the
exclude-list config-file filename is a named bounded planning decision, the four flagged
assumptions each carry a degrade path, and the security posture around the new `open_tab` token
and the `panes max=N` policy line is stated with a clear direction for the plan to inherit the
orchestration spec's frozen boundary. Scope is still tightly bound to the shipped pane system with
no speculative generality (YAGNI holds), error handling still degrades every path to the dumb
in-process fallback with a cooldown flag, and the one architecture trade-off that exceeds the
literal Q&A (include→exclude flip) is still surfaced with a user-confirmed note. With the sole
violation resolved and no new territory disturbed, this spec is clear to advance to the user
review gate.

### Violations

None.

### Resolved since round 1

| id | resolution |
|----|-----------|
| `writing-specs/bdd-gherkin-scenarios` | Acceptance scenarios rewritten from arrow-prose into a `gherkin`-fenced `Feature:` block with six `Scenario:` entries in `Given / When / Then / And` form (spec lines 166–206); content preserved verbatim, no design change. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking) — carried forward, spec text unchanged

- **Version pins deferred to the sibling pane specs; acceptable, zero new deps.** Toolchain names
  `bash`, `/usr/bin/jq`, the cmux CLI, and `osascript` and adds no dependencies; exact pins live in
  the referenced orchestration/layout-v2 specs (**cmux 0.64.20 (100)**, **jq 1.7.1**,
  **claude CLI 2.1.216**, `osascript` via **Darwin 25.5.0**) — same passing pattern as the tea-room
  spec. Plan should re-verify pins at implementation start; `bash` is only implicitly OS-pinned.
- **Security — new `open_tab` caller-supplied token.**
  `open_tab <existing-surface-ref> <title> <launcher-path>` adds a caller-supplied
  `<existing-surface-ref>` token crossing into adapter command lines. Spec commits to "arg
  validation reuse" and carries the constraints forward; the plan must make the new verb explicitly
  inherit the orchestration spec's frozen boundary (no interpolation of caller strings into
  cmux/tmux/AppleScript; title sanitized to `[A-Za-z0-9 ._:-]`, truncated to 64).
- **Security — policy-file content + session-id key.** The `panes max=N` line should validate N as
  a bounded positive integer before shell arithmetic (parse failure already degrades to
  in-process); state store is default-deny (`umask 077`, no PII/secrets stated).
- **Exclude-list config-file choice is a named, bounded planning decision**, not a hidden TBD —
  semantics fixed, only the filename deferred (repurpose `redirect-agents.conf` vs new
  `panes/inprocess-agents.conf`).
- **No Mermaid diagram** — not required by the Part A rubric enumeration and the routing/overflow
  logic is clear in prose, but a small decision diagram would still aid the human review gate.

## Round 1 (re-entry after post-review material revision) — 2026-07-23T03:09:32Z

HEAD: `2815bbadcf9e62168daa4b140e17a39c9d04f4d7` · Spec blob: `cdc777a9a7e8c6982fe0e5ba00c813e10c2b780c`

**Verdict: PASS** (0 violations)

> Re-entry: the round-2 PASS above was invalidated when the user materially revised the spec at
> the review gate. The revision replaces the earlier two-way include→exclude flip with an explicit
> **three-lane model**: (1) read-only `Explore`/`Plan`/search helpers always run in-process;
> (2) the two judges (`compliance-judge`, `observability-judge`) keep an **always-on** pane
> redirect — never asked about, never inline, and **not counted** against the worker max N, so
> `inline` no longer silences them; (3) plan implementers, `general-purpose`/worker agents, and
> parallel fan-out obey the session policy (`inline` or `panes max=N` with overflow-to-tab). Judged
> fresh against the live rule set.

### Layman summary

The post-review revision is a scope *clarification*, not a new feature, and it lands cleanly. The
old design silenced everything under `inline`; the user decided at the review gate that the two
judges are load-bearing quality gates and must keep their panes no matter what — so the spec now
carves the fan-out into three lanes and, crucially, keeps the judge lane *outside* the counted
worker budget. The mechanics follow through end to end: the guard evaluates the two carve-outs
(read-only → in-process, judges → always-paned) *before* it ever consults the policy file, so
neither lane can trigger the ask or be silenced by `inline`; the dispatcher explicitly bypasses
the count-and-overflow logic for judge dispatches so a judge pane can sit on top of N live worker
panes; and the one new thing this requires — a way to tell a judge run apart from a worker run so
judge panes don't eat the worker count — is named as a flagged assumption with a concrete degrade
path (fall back to a conservative count or overflow-inline if the lane tag proves unreliable). The
Gherkin block grew two dedicated scenarios that pin exactly this: a judge still gets a pane under
an `inline` policy, and a live judge pane does not consume a worker slot at the max.

Everything that made round 2 pass is intact and untouched by the edit. The round-1 arrow-prose
defect stays fixed — acceptance scenarios are a `gherkin`-fenced `Feature:` block with seven
`Given / When / Then / And` scenarios covering the happy path, overflow-to-tabs, read-only
non-governance, both judge carve-outs, freed-pane reclaim, and adapter-can't-tab degrade. Scope is
still bound to the shipped pane system with no speculative generality (YAGNI holds); error handling
still degrades every path to the dumb in-process fallback with a cooldown flag; the state store is
default-deny (`umask 077`, no PII/secrets); version pins are still deferred to the sibling specs
with zero new dependencies (confirmed pinned there); and the architecture trade-off that exceeds
the literal Q&A — plan implementers moving from skill-routed into hook-governed, and the judges
staying paned under `inline` — is surfaced as a human-owned decision with an explicit
"user chose this at review (2026-07-22)" annotation, exactly as core-conduct requires. The revision
introduces no new blocking issue; the remaining items are the same bounded, note-level planning
refinements. Clear to advance to the user review gate.

### Violations

None.

### Still resolved (from the original round 1)

| id | status |
|----|--------|
| `writing-specs/bdd-gherkin-scenarios` | Remains resolved. Acceptance scenarios are a `gherkin`-fenced `Feature:` block with seven `Given / When / Then / And` scenarios (spec lines 201–247), now including the two judge-lane scenarios the revision added. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **Three-lane model is internally coherent and correctly ordered.** The guard checks the two
  carve-outs (read-only in-process; always-paned judges) in steps 1–2 **before** the policy checks
  in steps 3–5, and the dispatcher explicitly bypasses count/overflow for judges — so judges can
  never trigger the ask, never run inline, and never consume a worker slot. Verified against the
  new Gherkin scenarios "A judge always gets a pane, even under an inline policy" and "A judge pane
  is not counted against the worker max."
- **The one genuinely new dependency of the revision is honestly flagged.** Excluding judge panes
  from the worker count requires tagging each run's lane (worker vs judge); the spec marks this as
  Flagged assumption 1 ("assumed cheap since the dispatcher already knows the `subagent_type` at
  dispatch time") with a stated degrade path (conservative count / overflow-inline). Surfacing the
  risk with a fallback is the right spec-layer move, not a TBD.
- **Round-robin overflow keeps "a small rotating index in state"** whose file/format is an
  implementation detail deferred to planning; the *behavior* (round-robin, with least-loaded as the
  Flagged-assumption-3 fallback) is fixed, so this is not a behavioral ambiguity.
- **Version pins deferred to the sibling pane specs; acceptable, zero new deps.** Toolchain names
  `bash`, `/usr/bin/jq`, the cmux CLI, and `osascript`, adds no dependencies; exact pins confirmed
  in the referenced orchestration/layout-v2 specs (**cmux 0.64.20 (100)**, **jq 1.7.1**,
  **claude CLI 2.1.216**, `osascript` via **Darwin 25.5.0**). Plan should re-verify pins at
  implementation start; `bash` is only implicitly OS-pinned.
- **Security — new `open_tab` caller-supplied token.**
  `open_tab <existing-surface-ref> <title> <launcher-path>` adds a caller-supplied
  `<existing-surface-ref>` token crossing into adapter command lines. Spec commits to
  "arg validation reuse" and carries the constraints forward; the plan must make the new verb
  explicitly inherit the orchestration spec's frozen boundary (no interpolation of caller strings
  into cmux/tmux/AppleScript; title sanitized to `[A-Za-z0-9 ._:-]`, truncated to 64).
- **Security — policy-file content + session-id key.** The `panes max=N` line should validate N as
  a bounded positive integer before shell arithmetic (a malformed/corrupt file already degrades to
  "no policy → re-ask"); state store is default-deny (`umask 077`, no PII/secrets stated); the
  `pane-policy-<key>` filename reuses the existing `adapter-failed-<key>` session-id convention.
- **Config-file layout for the read-only/judge sets** (repurpose `redirect-agents.conf` narrowed to
  the judges + a new read-only exclusion list, vs. a single two-section file) is a named, bounded
  planning decision — the carve-out semantics are fixed, only the filename/layout is deferred.
- **No Mermaid diagram** — not required by the Part A enumeration and the guard's ordered routing +
  dispatcher overflow logic reads clearly in prose, but a small three-lane decision diagram would
  aid the human review gate given the added lane.
- **Verified this round:** spec at the canonical `docs/superpowers/specs/` path; dedicated
  error-handling section degrades every path with a cooldown flag (errors flagged, not swallowed);
  scope reuses shipped machinery with no speculative features (YAGNI holds); the include→exclude
  flip and the judges-stay-paned decision are surfaced with an explicit user confirmation; sibling
  PR #23/#25 specs confirmed to pin the tool versions this spec defers to.
