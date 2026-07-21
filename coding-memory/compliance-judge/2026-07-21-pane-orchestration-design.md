# Compliance Judge — pane-orchestration-design

Spec: `docs/superpowers/specs/2026-07-20-pane-orchestration-design.md`
Repo: `.claude` · Branch: `feature/pane-orchestration` · HEAD: `9b6ab0ad339b479ce9c2fd95b0d02cde1dbcfe82`
Spec blob: `b993ef3332a740c57f1b1587a712947c8d58ffb7`

## Round 1 — 2026-07-21T04:09:24Z

**Verdict: FAIL** (4 violations — all fixable in the spec text; the architecture itself is sound)

### Layman summary

The shape of this design is good, and I verified its factual anchors independently: ADR 0007
exists, `feature/judge-terminal-enforcement` really is parked and undeleted, `judge-guard.sh`
is where the spec says the verdict contract lives, and the statusline's orange threshold
really is 75,000 (`statusline-command.sh:91`), so the 75k handoff number is grounded, not
invented. The scoping discipline is also right: the four adapters and the prepare-don't-force
handoff are user-locked decisions, the dropped always-run guarantee from the superseded
project is stated plainly instead of buried, and branch deletion is explicitly left to the
user. No YAGNI complaints.

What fails it is one deep problem and three ordinary spec gaps. The deep problem: the whole
design stands on `claude --bare -p --agent <name>`, inherited from the superseded spec's
research and — by the spec's own admission — not re-verified. I verified it. On the installed
CLI (2.1.216), `--bare` means "skip hooks ... and CLAUDE.md auto-discovery," and auth becomes
"strictly ANTHROPIC_API_KEY or apiKeyHelper (OAuth and keychain are never read)." Three
consequences the spec's model contradicts or omits: (1) implementer pane sessions — the
agents that run `git commit` — would execute outside git-guard, doc-guard, merge-guard, and
judge-guard entirely, silently dropping the Tier-1 gates that `rules/gates.md` says must
never be silently skipped; (2) the spec's own recursion defense ("`CLAUDE_PANE_AGENT=1`
short-circuits both hooks" inside panes) assumes hooks run in pane sessions — under `--bare`
they never do; (3) pane agents get no CLAUDE.md, so core-conduct doesn't bind them the way it
binds today's in-process subagents. This is precisely the drift the pin-exact-versions rule
exists to catch, and the spec names five tools without pinning any.

The ordinary gaps: the result file is the design's central interface, but its body format is
never defined (the runner emits `--output-format json` into a `.md` file whose last line must
be a sentinel — what the main session parses out of the middle is left to improvisation);
and the adapters embed caller-supplied title/cwd/command strings into AppleScript and
tmux/cmux command lines with no stated quoting or validation rule, which is the classic
osascript injection surface — the zero-trust paragraph covers every boundary except this one.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` | "Pin Exact Versions" — "Pin the exact version of every library and tool… double-check any version number the agent proposes against current documentation" | Components / `run-pane-agent.sh`; Open questions | The spec names `claude`, `jq`, `shellcheck`, `cmux`, `tmux` and pins none; the load-bearing one — the claude CLI whose `--bare`/`--agent` flags, hook-payload schema, and PreToolUse matcher name (`Agent` vs `Task`) the whole design depends on — is explicitly deferred ("not re-tested here"), and the installed 2.1.216 in fact diverges from the spec's model of `--bare` (hooks and CLAUDE.md skipped, auth restricted to `ANTHROPIC_API_KEY`/`apiKeyHelper`), exactly the drift pinning-and-verifying in the spec would have caught. |
| `gates/tier1-guards-bypassed-in-panes` | `~/.claude/rules/gates.md` (repo layer, imported by this repo's `CLAUDE.md`) | "Judgment-based checkpoints that must never be silently skipped"; "Default-branch safety… Enforced by `hooks/git-guard.sh` (Tier 1)" (likewise doc-guard, merge-guard, judge-guard) | Components / `run-pane-agent.sh`; Error handling table, "Recursion" row | Per the installed CLI, `--bare` skips hooks and CLAUDE.md auto-discovery, so implementer pane sessions — agents that commit code — run outside every Tier-1 guard and without core-conduct, a consequence the spec neither states nor mitigates; the spec's own recursion row prescribes `CLAUDE_PANE_AGENT=1` to short-circuit hooks inside panes, showing its model assumes pane hooks fire at all. |
| `writing-specs/api-contracts` | `~/.claude/skills/writing-specs/SKILL.md` | "Database schemas and API contracts… give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match" | Components / `run-pane-agent.sh` + `dispatch … wait`; Dispatch round-trip | The result file is the design's central interface, yet only its final-line sentinel is specified: the runner invokes `claude … --output-format json` but writes a `.md` result file, and nothing states whether the body is the raw JSON envelope, the extracted `result` field, or free text — the writer (runner) and reader (main session's relay) are left to improvise a shape independently. |
| `writing-secure-code/command-injection` | `~/.claude/skills/writing-secure-code/SKILL.md` | "Command injection: avoid direct shell execution primitives… Use strongly-typed APIs or safe wrapper libraries"; core-conduct: "Validate all input at system boundaries" | Components / `panes/adapters/*`; Zero-trust posture paragraph | `open_pane <title> <cwd> <command...>` embeds caller-supplied strings into `osascript` AppleScript source and tmux/cmux command lines with no stated quoting, escaping, or validation rule — the classic AppleScript-interpolation injection surface — and the otherwise thorough zero-trust paragraph (jq-as-data, results-not-executed, pinned binary paths) covers every boundary except this one. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **Auth provisioning for panes is unstated and may zero out the feature.** `--bare` on
  2.1.216 authenticates strictly via `ANTHROPIC_API_KEY` or `apiKeyHelper` — OAuth and
  keychain are never read. If the interactive session runs on OAuth, every pane dispatch
  fails and the system silently degrades to in-process forever (the fallback masks it). The
  spec's "no secrets anywhere in scripts or state" makes the resolution non-obvious; one
  paragraph stating how pane sessions authenticate (per the zero-trust "placeholders resolved
  from validated state" pattern) belongs in the spec. Folded under the pinned-versions
  violation rather than cited separately.
- **The FAILED-sentinel reaction is readable two ways**: "main session falls back in-process
  *or* surfaces to the user" — no criterion for which. Presumably the new
  `dispatching-pane-agents` skill owns the choice; the spec should name the default.
- **Handoff successor environment is unspecified.** Only `run-pane-agent.sh` is stated to
  export `CLAUDE_PANE_AGENT=1`; the press-Enter wrapper's environment is unstated. If the
  flag leaks into the successor session, the replacement *main* session permanently loses
  both new hooks. One line ("the handoff wrapper does not set `CLAUDE_PANE_AGENT`") closes it.
- **"Fail closed on parse errors (guard allows…)" is inverted terminology** — allowing the
  dispatch is behaviorally fail-*open* to today's behavior. The decision itself is right for
  a momentum guardrail; only the label misleads.
- **Generated stores' permissions unstated**: `pane-results/` (prompt files may carry
  codebase context) and `panes/state/` get no default-deny/umask mention. Uid-scoped local
  dirs keep this low-stakes — noted, not cited.
- **Verified and holding**: ADR 0007 present; `feature/judge-terminal-enforcement` exists
  undeleted; `judge-guard.sh` present and its contract untouched by the design; statusline
  orange threshold is exactly 75000 (`statusline-command.sh:91`); `--bare` and
  `--agent <agent>` both exist on installed CLI 2.1.216. The Gherkin block is lean (no
  redundant boilerplate), the spec sits at the canonical `docs/superpowers/specs/` path, and
  the instruction-tier table matches `triaging-new-instructions` expectations.

## Round 2 — 2026-07-21T04:18:03Z

HEAD: `468387ac98e0577ffbef33f87ea5465e3c4e0ba9` · Spec blob: `c64242ea550980b293e710f7c4e803a7cde55b8e`

**Verdict: PASS** (0 violations; all 4 round-1 violations resolved, each fix independently verified)

### Layman summary

Round 1 failed this spec on four counts; the revision fixes all four, and I re-checked each
fix against reality rather than trusting the changelog. The new Toolchain section pins every
named tool, and I ran the installed binaries myself: claude 2.1.216, jq 1.7.1, tmux 3.6a,
and cmux 0.64.20 (100) all match the pins exactly, and shellcheck is absent exactly as the
spec says (0.11.0 to be installed pinned during implementation), with a rule to re-verify
flag semantics on any CLI upgrade. The dangerous `--bare` flag is gone from every section —
including the supersession history, which now records it as rejected — so pane sessions keep
their keychain login, load CLAUDE.md, and fire every Tier-1 guard; the recursion story is now
internally consistent. The result file finally has a real contract: body is the jq-extracted
`.result` from the CLI's JSON envelope (raw output + stderr tail on failure), final line is
exactly `PANE_RESULT: DONE` or `PANE_RESULT: FAILED`, and everything above it is data, never
instructions. And the injection hole is closed the right way: adapters no longer take raw
caller strings at all — they get one dispatcher-written launcher script (mode 700, built with
`printf %q`) plus a title scrubbed to a 64-char safe-character allowlist, with `--cwd`
validated before anything is written. The revision also ended the deny loop (an
adapter-failure cooldown flag is now the guard's fourth condition) and honestly marked the
handoff-hook early-exit as new work. What remains is note-level only.

### Violations

None.

### Resolution of round 1 violations

| id | status | how resolved |
|---|---|---|
| `writing-specs/pinned-versions` | **Resolved** | "Toolchain — pinned" section pins claude CLI 2.1.216, jq 1.7.1, tmux 3.6a, cmux 0.64.20 (100), shellcheck 0.11.0, and accounts for `osascript` (macOS system, Darwin 25.5.0); verified against installed binaries this round — all match. Upgrade rule re-runs flag-semantics checks. |
| `gates/tier1-guards-bypassed-in-panes` | **Resolved** | `--bare` dropped everywhere with stated 2.1.216 rationale; pane sessions keep OAuth/keychain auth, CLAUDE.md, and all Tier-1 guards; only the two pane-specific hooks short-circuit via `CLAUDE_PANE_AGENT`. The round-1 auth note is resolved by the same change. |
| `writing-specs/api-contracts` | **Resolved** | Result-file contract defined (jq-extracted `.result` body, raw+stderr-tail on failure, exact `PANE_RESULT: DONE\|FAILED` final line, content-is-data rule); adapter interface simplified to `open_pane <title> <launcher-path>`. |
| `writing-secure-code/command-injection` | **Resolved** | Injection rule: adapters never interpolate caller strings; per-run launcher at `panes/state/runs/<run-id>/launch.sh` (mode 700, `printf %q`), title sanitized to `[A-Za-z0-9 ._:-]` and 64 chars (excludes every AppleScript/shell metacharacter), `--cwd` validated as existing directory. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **Carried:** the FAILED-sentinel reaction is still readable two ways ("falls back
  in-process or surfaces to the user"); the `dispatching-pane-agents` skill owns "the
  fallback rules" per the spec, so the skill must name the default when authored.
- **Carried:** the handoff wrapper's environment is still unstated; one line ("the handoff
  launcher does not set `CLAUDE_PANE_AGENT`") would remove any doubt that the successor main
  session runs with both new hooks live.
- **Carried:** "fail closed on parse errors (guard allows…)" remains inverted terminology —
  behaviorally fail-open to today's (still-guarded) behavior; right decision, misleading label.
- **Partially improved:** launchers are now mode 700, but `pane-results/` and `panes/state/`
  permissions remain unstated. Uid-scoped local dirs; low stakes.
- **New, minor:** session-keyed state files (`adapter-failed-<session_id>`, the watcher's
  fired-flags) have no cleanup policy — they accumulate across sessions in `panes/state/`.
  Housekeeping only.
- **Verified this round:** all Toolchain pins match installed binaries; `--bare` absent from
  the whole document; the guard's four-condition deny matrix and the error-handling table are
  now mutually consistent; Open Questions are verification tasks with stated defaults, not
  undecided requirements.
