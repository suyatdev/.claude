# Pane-Split Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the user per-session control over how the substantial worker fan-out is placed — `inline` (in-process) or `panes max=N` (N concurrent worker panes, overflow → a new tab inside an existing worker pane), while read-only helpers always stay in-process and the two judges keep their always-on panes outside the policy.

**Architecture:** Three lanes, decided in the existing PreToolUse guard before the policy is ever consulted: (1) read-only `Explore`/`Plan` → in-process; (2) judges → always paned; (3) everything else → policy-governed. The policy is captured lazily at the first governed worker dispatch (the guard denies with structured ask-guidance; the model calls `AskUserQuestion`, writes the choice via a new `set-policy` subcommand, and retries). Under `panes max=N` the dispatcher counts live worker panes from `state/runs/` (each run tagged with its lane + session so judge runs are excluded), opens a pane while the count is below N, and overflows to a new tab (adapter `open_tab` verb, round-robin pane selection) at or above N. Every failure path degrades to the dumb in-process path — the pane system's existing fail-open contract.

**Tech Stack:** bash 3.2 (macOS system bash), `/usr/bin/jq`, the cmux CLI (`/Applications/cmux.app/Contents/Resources/bin/cmux`), macOS `osascript` (iTerm/Terminal adapters). No new dependencies. Fake-binary `.test.sh` harnesses beside each script.

**Source spec:** `docs/superpowers/specs/2026-07-22-pane-split-policy-design.md` (locked, blob `cdc777a`, approved 2026-07-22).

## Global Constraints

Every task's requirements implicitly include this section. Values copied verbatim from the spec + its `Constraints carried forward` section.

- **Fail-open, degrade-never-block.** Any parse/read failure, missing conf, absent terminal, jq failure, or adapter-failure cooldown flag → allow/return the in-process path. Never block, never wait.
- **Recursion guard.** `CLAUDE_PANE_AGENT` set → the guard exits 0 immediately (a pane session must not re-trigger the pane hooks). Unchanged; do not remove.
- **Session-id keying triple.** Resolve the session key as: stdin `.session_id` (hooks) / `$CLAUDE_CODE_SESSION_ID` (dispatcher) / the literal `nosession` fallback when the env var is empty. New state files (`pane-policy-<key>`, `pane-rr-<key>`) reuse this exact convention; the guard checks all three candidate keys, first match wins, mirroring today's `adapter-failed-<key>` cooldown loop.
- **State hygiene.** `umask 077` on every state write (dispatcher already sets it process-wide). No PII, no secrets, no absolute user paths written into state files. State is default-deny and swept by the existing `cleanup_stale` (older than `STALE_DAYS=7`); add no new housekeeping.
- **No new dependencies.** Pinned tools already on the pane path: bash (OS-pinned, Darwin 25.5.0), `/usr/bin/jq` 1.7.1, cmux CLI (layout-verified `0.64.20`), `/usr/bin/osascript`. **Re-verify these pins at implementation start** (the spec defers them to the sibling orchestration/layout-v2 specs).
- **Injection boundary (frozen, inherited).** The new `open_tab` verb adds one caller-supplied token, `<existing-surface-ref>`, crossing into adapter command lines. It MUST inherit the orchestration spec's frozen boundary: no interpolation of caller tokens into cmux/tmux/AppleScript command lines beyond the validated forms; title sanitized to `[A-Za-z0-9 ._:-]` truncated to 64; and the surface-ref validated to `^[A-Za-z0-9:%_.-]{1,64}$` (admits `surface:99`, `%3`, a UUID, `window-123`; rejects spaces, quotes, shell metacharacters).
- **Bounded N.** The `panes max=N` policy line validates `N` as a bounded positive integer (`1 <= N <= 16`) before any shell arithmetic, at both write time (`set-policy`) and read time (guard + dispatcher). A malformed/out-of-range value is treated as "no policy" → re-ask (safe degrade), never a hard error.

---

## File Map

**Modify:**
- `hooks/pane-dispatch-guard.sh` — three-lane routing + policy read (Task 3)
- `hooks/pane-dispatch-guard.test.sh` — new lane/policy cases (Task 3)
- `panes/redirect-agents.conf` — header comment narrowed to "always-paned judges" (Task 3; the two judge lines are unchanged)
- `panes/dispatch-pane-agent.sh` — `set-policy` subcommand + `read_policy` (Task 2); lane/session/surface markers + live-worker count + judge bypass (Task 6); overflow → `open_tab` (Task 7)
- `panes/dispatch-pane-agent.test.sh` — policy, count, overflow cases (Tasks 2, 6, 7)
- `panes/adapters/common.sh` — `validate_open_tab_args` (Task 4)
- `panes/adapters/tmux.sh`, `iterm.sh`, `terminal.sh` — `open_tab` verb (Task 4)
- `panes/adapters/cmux.sh` — `open_tab` verb, probe-verified primitive (Task 5)
- `panes/adapters.test.sh` — `open_tab` fake-binary/dryrun cases (Tasks 4, 5)
- `skills/dispatching-pane-agents/SKILL.md` — three lanes + policy + overflow (Task 8)
- `rules/gates.md` — correct the stale "plan implementers are skill-routed" line (Task 8)

**Create:**
- `panes/cmux-tab-probe.sh` — live probe of the cmux tab primitive (Task 1)
- `panes/adapters/fixtures/tab-live.json` — captured probe fixture (Task 1)
- `panes/inprocess-agents.conf` — read-only in-process set: `Explore`, `Plan` (Task 3)
- `docs/decisions/0009-pane-split-policy-three-lane-governance.md` — ADR (Task 8)

**Config decision (resolved here, per spec "exact file layout deferred to planning"):** two flat one-type-per-line include-lists, each parsed by the guard's existing `while IFS= read` loop — `redirect-agents.conf` narrowed to the always-paned judge set, and a new `inprocess-agents.conf` for the read-only set. Everything in neither file is a governed worker. This is the spec's first-offered option and the least-change, most-consistent choice.

**State file contract (written here, read by guard + dispatcher):**
- `panes/state/pane-policy-<key>` — one line, exactly `inline` or `panes max=N` (`1 <= N <= 16`).
- `panes/state/runs/<run-id>/lane` — one line, `worker` or `judge` (dispatcher writes at dispatch).
- `panes/state/runs/<run-id>/session` — one line, the session key (dispatcher writes at dispatch).
- `panes/state/runs/<run-id>/surface` — one line, the pane's surface ref (dispatcher writes after `open_pane`).
- `panes/state/runs/<run-id>/agent-exit` — the completion marker, **already written by `run-pane-agent.sh:81`** on result-write; a run is "live" while this file is absent. No change to `run-pane-agent.sh`.
- `panes/state/pane-rr-<key>` — one line, a monotonically increasing round-robin index (dispatcher, Task 7).

---

## Task 1: Live cmux tab-primitive probe (HARD GATE — human/live, run on real cmux)

**Why first:** the cmux `open_tab` primitive ("a tab attached to a pane" vs "a tab in the same workspace") is not derivable from the tree JSON (geometry is not in the tree) and every adapter test drives a fake binary. It must be probe-verified against the live cmux CLI before the cmux adapter code (Task 5) is trusted — exactly the precedent set by `panes/cmux-layout-probe.sh` for layout-v2. **This task is run live by the operator, not a fake-binary subagent.** It gates Task 5.

**Files:**
- Create: `panes/cmux-tab-probe.sh`
- Create (captured output): `panes/adapters/fixtures/tab-live.json`
- Record findings in: `coding-memory/branches/pane-split-policy.md`

**Interfaces:**
- Produces: a recorded decision naming the exact cmux subcommand + flags that open a new agent tab into an existing pane's surface, consumed verbatim by Task 5's `cmux.sh open_tab`.

- [ ] **Step 1: Write the probe script**

Mirror `cmux-layout-probe.sh`: build a scratch workspace, open a base pane, then exercise the candidate tab primitives and report which yields a tab in the target pane. `new-surface --pane <pane-ref>` is the leading candidate (it is already used by `cmux.sh`'s `tab` verb in `execute_plan`), but the probe must confirm it attaches to the *named* pane rather than the focused one, and capture the resulting ref shape.

```bash
#!/usr/bin/env bash
# cmux-tab-probe.sh — live probe backing the pane-split-policy open_tab primitive
# (spec: docs/superpowers/specs/2026-07-22-pane-split-policy-design.md). Run it
# from a cmux pane after any cmux upgrade, BEFORE trusting cmux.sh open_tab.
# EVIDENCE-GATHERING, not a contract: when cmux changes, update the expectations
# here and re-record the findings in coding-memory/branches/pane-split-policy.md.
set -u
CMUX_BIN="${PANE_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
JQ_BIN="${PANE_JQ_BIN:-/usr/bin/jq}"
FIXTURE="${1:-$HOME/.claude/panes/adapters/fixtures/tab-live.json}"
export CMUX_QUIET=1

say()  { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }

[ -x "$CMUX_BIN" ] || { echo "no cmux at $CMUX_BIN"; exit 1; }
[ -x "$JQ_BIN" ]   || { echo "no jq at $JQ_BIN"; exit 1; }
note "cmux: $("$CMUX_BIN" version 2>&1 | head -1)"

NORM_JQ='[.. | objects | select(has("ref") and has("pane_ref") and has("title"))]
         | .[] | [.pane_ref, .ref, .title] | @tsv'
norm() { "$JQ_BIN" -r "$NORM_JQ" 2>/dev/null; }

say "T1: scratch workspace"
ws_out="$("$CMUX_BIN" new-workspace --name "tab-probe-scratch" 2>&1)"
ws_ref="$(printf '%s' "$ws_out" | awk '$1=="OK"{print $2}')"
case "$ws_ref" in workspace:*) note "scratch: $ws_ref" ;; *) echo "no workspace ref: $ws_out"; exit 1 ;; esac
cleanup() { "$CMUX_BIN" close-workspace --workspace "$ws_ref" >/dev/null 2>&1; }
trap cleanup EXIT

say "T2: base pane + its surface/pane refs"
base_surface="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' 'NR==1{print $2}')"
base_pane="$("$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | awk -F'\t' 'NR==1{print $1}')"
note "base surface=$base_surface  base pane=$base_pane"

say "T3: candidate — new-surface --pane <pane-ref> (attach a tab to a NAMED pane)"
ns_out="$("$CMUX_BIN" --json new-surface --pane "$base_pane" --workspace "$ws_ref" 2>&1)"
printf '   %s\n' "$ns_out"
new_ref="$(printf '%s' "$ns_out" | "$JQ_BIN" -er '.surface_ref' 2>/dev/null)" || new_ref=""
note "new surface ref=[$new_ref] (expect surface:*)"
note "tree AFTER — confirm the new surface shares base pane $base_pane (same pane_ref column):"
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null | norm | sed 's/^/   /'
note "FINDING: if the new surface's pane_ref == $base_pane, 'new-surface --pane <pane>' IS"
note "         the open_tab primitive — a tab inside the target pane. Record it."

say "T4: does the tab accept a launcher via send? (open_tab must run the agent)"
if [ -n "$new_ref" ]; then
  "$CMUX_BIN" send --workspace "$ws_ref" --surface "$new_ref" -- "echo TAB_SEND_OK\n" >/dev/null 2>&1
  note "sent an echo to $new_ref — visually confirm TAB_SEND_OK printed in the new tab."
fi

say "T5: capture fixture"
mkdir -p "$(dirname "$FIXTURE")"
"$CMUX_BIN" --json tree --workspace "$ws_ref" 2>/dev/null > "$FIXTURE"
printf '   fixture written: %s (%s bytes)\n' "$FIXTURE" "$(wc -c < "$FIXTURE" | tr -d ' ')"
note "REVIEW before committing — no real titles/paths:"
"$JQ_BIN" -r '[.. | objects | .title? // empty] | unique | .[]' "$FIXTURE" | sed 's/^/   title: /'

say "cleanup"
printf '   Press Enter to close %s ' "$ws_ref"; IFS= read -r _
cleanup
note "closed."
```

- [ ] **Step 2: Make it executable**

Run: `chmod 755 panes/cmux-tab-probe.sh`

- [ ] **Step 3: Run the probe live on real cmux (operator action)**

Run (from a real cmux pane): `bash panes/cmux-tab-probe.sh`
Expected: T3 prints a `surface:*` ref whose `pane_ref` equals the base pane, and T4's `TAB_SEND_OK` appears visually in the new tab. If cmux only exposes workspace-level tabs (no per-pane attach), record that instead — Task 5 then maps `open_tab` to "a tab in the same workspace" (the honest degrade named in the spec).

- [ ] **Step 4: Record findings + review the fixture**

Append a `## Task 1 — cmux tab probe` section to `coding-memory/branches/pane-split-policy.md` stating the exact subcommand + flags the adapter must use, the ref shape, and whether it is pane-attached or workspace-level. Confirm `tab-live.json` contains no real titles or paths.

- [ ] **Step 5: Commit**

```bash
git add panes/cmux-tab-probe.sh panes/adapters/fixtures/tab-live.json coding-memory/branches/pane-split-policy.md
git commit -m "feat(panes): live cmux tab-primitive probe + fixture (pane-split Task 1)"
```

---

## Task 2: Policy state file — `set-policy` writer + `read_policy` reader

**Files:**
- Modify: `panes/dispatch-pane-agent.sh` (add `set-policy` subcommand + `read_policy` helper + `MAX_PANES` constant)
- Test: `panes/dispatch-pane-agent.test.sh`

**Interfaces:**
- Produces: `dispatch-pane-agent.sh set-policy inline` and `dispatch-pane-agent.sh set-policy panes --max N` — writes `state/pane-policy-<key>` (key = `${CLAUDE_CODE_SESSION_ID:-nosession}`), validating N ∈ [1,16]; exit 0 on success, exit 64 on a bad/out-of-range N.
- Produces: `read_policy <policy-file-path>` — prints `inline`, or `panes max=N` (only when the file holds a valid line), or nothing (missing/malformed → caller treats as "no policy"). Used by the guard (Task 3) and the dispatcher (Task 6/7).

- [ ] **Step 1: Write the failing test**

Add to `panes/dispatch-pane-agent.test.sh` (before the final summary print):

```bash
# --- set-policy writes and validates the per-session policy file
export PANE_STATE_DIR="$TMP/state"   # already set at top; restated for locality
SP_SID="policy-sess-$$"
CLAUDE_CODE_SESSION_ID="$SP_SID" bash "$DISPATCH" set-policy inline >/dev/null 2>&1
[ "$(cat "$PANE_STATE_DIR/pane-policy-$SP_SID" 2>/dev/null)" = "inline" ] && ok "set-policy inline written" || bad "set-policy inline written"
CLAUDE_CODE_SESSION_ID="$SP_SID" bash "$DISPATCH" set-policy panes --max 3 >/dev/null 2>&1
[ "$(cat "$PANE_STATE_DIR/pane-policy-$SP_SID" 2>/dev/null)" = "panes max=3" ] && ok "set-policy panes max=3 written" || bad "set-policy panes max=3 written"
bash "$DISPATCH" set-policy panes --max 0 >/dev/null 2>&1
[ $? -eq 64 ] && ok "set-policy max=0 rejected" || bad "set-policy max=0 rejected"
bash "$DISPATCH" set-policy panes --max 99 >/dev/null 2>&1
[ $? -eq 64 ] && ok "set-policy max=99 (>16) rejected" || bad "set-policy max=99 rejected"
bash "$DISPATCH" set-policy panes --max abc >/dev/null 2>&1
[ $? -eq 64 ] && ok "set-policy non-numeric max rejected" || bad "set-policy non-numeric max rejected"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: FAIL — `set-policy` is not a recognized command yet (dispatcher's `case` falls to the usage `die`, exit 64 for every line, so the "written" assertions fail).

- [ ] **Step 3: Implement `MAX_PANES`, `read_policy`, and the `set-policy` case**

In `panes/dispatch-pane-agent.sh`, add the constant near the other constants (after `POLL_SECS=2`):

```bash
MAX_PANES=16                 # upper bound on 'panes max=N' (spec: bounded positive int)
POLICY_RE='^panes max=([0-9]+)$'
```

Add `read_policy` near the other helpers (after `sanitize_title`):

```bash
# read_policy <file> -> prints "inline" or "panes max=N" for a VALID line, else
# nothing (missing/corrupt/out-of-range => caller treats as "no policy"). Never
# errors: a malformed policy is a safe re-ask, not a failure (spec error table).
read_policy() {
  local f="$1" line n
  [ -f "$f" ] && [ -r "$f" ] || return 0
  line="$(head -n 1 "$f" 2>/dev/null)"
  if [ "$line" = "inline" ]; then printf 'inline\n'; return 0; fi
  if [[ "$line" =~ $POLICY_RE ]]; then
    n="${BASH_REMATCH[1]}"
    if [ "$n" -ge 1 ] && [ "$n" -le "$MAX_PANES" ] 2>/dev/null; then printf 'panes max=%s\n' "$n"; fi
  fi
  return 0
}
```

Add the `set-policy` case to the top-level `case "$cmd"` (alongside `dispatch|wait|handoff`):

```bash
  set-policy)
    mode="${1:-}"; [ -n "$mode" ] && shift || die "usage: set-policy {inline|panes --max N}"
    max=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --max) [ $# -ge 2 ] || die "--max needs a value"; max="$2"; shift 2 ;;
        *) die "unknown option: $1" ;;
      esac
    done
    key="${CLAUDE_CODE_SESSION_ID:-nosession}"
    mkdir -p "$STATE_DIR"
    case "$mode" in
      inline) printf 'inline\n' > "$STATE_DIR/pane-policy-$key" || die "cannot write policy file" ;;
      panes)
        [[ "$max" =~ ^[0-9]+$ ]] || die "--max must be a whole number 1..$MAX_PANES"
        { [ "$max" -ge 1 ] && [ "$max" -le "$MAX_PANES" ]; } || die "--max out of range (1..$MAX_PANES)"
        printf 'panes max=%s\n' "$max" > "$STATE_DIR/pane-policy-$key" || die "cannot write policy file" ;;
      *) die "set-policy mode must be inline or panes" ;;
    esac
    printf 'POLICY: %s\n' "$(cat "$STATE_DIR/pane-policy-$key")"
    ;;
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: PASS — all five `set-policy` assertions plus every pre-existing case.

- [ ] **Step 5: Commit**

```bash
git add panes/dispatch-pane-agent.sh panes/dispatch-pane-agent.test.sh
git commit -m "feat(panes): pane-policy state file — set-policy writer + read_policy (bounded N)"
```

---

## Task 3: Guard — three-lane routing + policy read

**Files:**
- Modify: `hooks/pane-dispatch-guard.sh`
- Create: `panes/inprocess-agents.conf`
- Modify: `panes/redirect-agents.conf` (header comment only; judge lines unchanged)
- Test: `hooks/pane-dispatch-guard.test.sh`

**Interfaces:**
- Consumes: `read_policy`'s file format (Task 2) — reads `state/pane-policy-<key>` directly (the guard is a self-contained hook and sources nothing; it re-implements the same tiny read against the identical format).
- Produces: exit 0 = allow in-process; exit 2 = deny. Two distinct exit-2 stderr messages: **ask-guidance** (no policy → contains `AskUserQuestion` + the `set-policy` command) and **redirect-guidance** (judge, or `panes` → contains `dispatch-pane-agent.sh` + `dispatching-pane-agents`).

**Routing order** (after the recursion guard + payload/jq/subagent_type extraction, all unchanged):
1. read-only set (`inprocess-agents.conf`) → exit 0 (in-process; independent of terminal).
2. terminal available? no → exit 0 (fail-open floor).
3. cooldown flag for any candidate key? → exit 0 (fail-open floor).
4. judge set (`redirect-agents.conf`) → exit 2 **redirect** (always paned; policy not consulted).
5. read policy under each candidate key (first match wins):
   - none/malformed → exit 2 **ask**.
   - `inline` → exit 0 (in-process).
   - `panes max=N` → exit 2 **redirect** (dispatcher owns pane-vs-tab).

- [ ] **Step 1: Write the failing tests**

Rewrite the case list in `hooks/pane-dispatch-guard.test.sh`. Keep the harness (`payload`, `run_case`) and the existing fail-open cases; add the read-only conf and policy setup. Replace lines 9–56 region setup + cases with:

```bash
export PANE_REDIRECT_CONF="$TMP/redirect.conf"
export PANE_INPROCESS_CONF="$TMP/inprocess.conf"
export PANE_STATE_DIR="$TMP/state"
export PANE_TERMINAL_DETECT="$TMP/detect.sh"
mkdir -p "$PANE_STATE_DIR"
printf '# comment\n\ncompliance-judge\nobservability-judge\n' > "$PANE_REDIRECT_CONF"
printf '# read-only in-process set\nExplore\nPlan\n' > "$PANE_INPROCESS_CONF"
printf '#!/usr/bin/env bash\necho cmux\n' > "$TMP/detect.sh"; chmod 700 "$TMP/detect.sh"
unset CLAUDE_PANE_AGENT CLAUDE_CODE_SESSION_ID
```

Then the case block (`payload $type $sid`; `run_case desc want-exit payload env...`):

```bash
# read-only lane — always in-process, even with a panes policy set
printf 'panes max=3\n' > "$PANE_STATE_DIR/pane-policy-s1"
run_case "Explore -> allow in-process"        0 "$(payload Explore s1)" X=1
run_case "Plan -> allow in-process"           0 "$(payload Plan s1)" X=1
# judge lane — always paned, regardless of policy
run_case "judge under panes -> deny"          2 "$(payload compliance-judge s1)" X=1
printf 'inline\n' > "$PANE_STATE_DIR/pane-policy-s1"
run_case "judge under inline -> deny"         2 "$(payload observability-judge s1)" X=1
rm -f "$PANE_STATE_DIR/pane-policy-s1"
run_case "judge with no policy -> deny"       2 "$(payload compliance-judge s1)" X=1
# governed worker lane
run_case "worker no policy -> deny (ask)"     2 "$(payload general-purpose s1)" X=1
printf 'inline\n' > "$PANE_STATE_DIR/pane-policy-s1"
run_case "worker under inline -> allow"       0 "$(payload general-purpose s1)" X=1
printf 'panes max=2\n' > "$PANE_STATE_DIR/pane-policy-s1"
run_case "worker under panes -> deny (redirect)" 2 "$(payload general-purpose s1)" X=1
printf 'garbage line\n' > "$PANE_STATE_DIR/pane-policy-s1"
run_case "worker malformed policy -> deny (ask)" 2 "$(payload general-purpose s1)" X=1
rm -f "$PANE_STATE_DIR/pane-policy-s1"
# fail-open floor still holds
run_case "inside pane -> allow"               0 "$(payload general-purpose s1)" CLAUDE_PANE_AGENT=1
run_case "malformed stdin -> allow"           0 'not json' X=1
run_case "empty stdin -> allow"               0 '' X=1
```

Add message-content assertions (after the existing divergence + deny-pointer checks):

```bash
# no-policy worker -> ASK guidance names AskUserQuestion + set-policy
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'AskUserQuestion' && printf '%s' "$out" | grep -q 'set-policy'; then
  printf 'ok   — no-policy worker gets ask guidance\n'; pass=$((pass+1))
else printf 'FAIL — ask guidance incomplete (got: %s)\n' "$out"; fail=$((fail+1)); fi
# worker under panes -> REDIRECT guidance names the dispatcher + skill
printf 'panes max=2\n' > "$PANE_STATE_DIR/pane-policy-s1"
out=$(printf '%s' "$(payload general-purpose s1)" | bash "$HOOK" 2>&1 >/dev/null)
if printf '%s' "$out" | grep -q 'dispatch-pane-agent.sh' && printf '%s' "$out" | grep -q 'dispatching-pane-agents'; then
  printf 'ok   — panes worker gets redirect guidance\n'; pass=$((pass+1))
else printf 'FAIL — redirect guidance incomplete (got: %s)\n' "$out"; fail=$((fail+1)); fi
rm -f "$PANE_STATE_DIR/pane-policy-s1"
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash hooks/pane-dispatch-guard.test.sh`
Expected: FAIL — the guard treats `general-purpose` as unlisted → allow (exit 0), so the worker/ask/redirect cases fail; `Explore`/`Plan` are not yet a recognized in-process set.

- [ ] **Step 3: Create the read-only conf + narrow the redirect conf comment**

Create `panes/inprocess-agents.conf`:

```
# inprocess-agents.conf — one subagent_type per line ('#' comments).
# Read-only / search helpers that ALWAYS run in-process and are never governed by
# the session pane-split policy. Checked before the policy in pane-dispatch-guard.sh.
Explore
Plan
```

Replace the header comment of `panes/redirect-agents.conf` (leave the two judge lines):

```
# redirect-agents.conf — one subagent_type per line ('#' comments).
# The ALWAYS-PANED lane: these types are denied in-process dispatch by
# hooks/pane-dispatch-guard.sh whenever a terminal is available, regardless of the
# session pane-split policy (inline/panes) — the judges keep their always-on panes
# and are NOT counted against the worker max N. Governed workers (plan implementers,
# general-purpose/worker agents, fan-out) are NOT listed here; they fall through to
# the policy. Read-only helpers live in inprocess-agents.conf.
compliance-judge
observability-judge
```

- [ ] **Step 4: Rewrite the guard routing**

Edit `hooks/pane-dispatch-guard.sh`. Add the new conf var beside `CONF` (line 13):

```bash
INPROCESS_CONF="${PANE_INPROCESS_CONF:-$HOME/.claude/panes/inprocess-agents.conf}"
```

Add a shared list-match helper after the env-var block (before the recursion guard), so both confs use one parser:

```bash
# in_conf <conf-file> <type> -> 0 if the type is a non-comment line in the file.
in_conf() {
  local conf="$1" want="$2" line
  [ -f "$conf" ] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    line=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -n "$line" ] && [ "$line" = "$want" ] && return 0
  done < "$conf"
  return 1
}
```

Replace the routing body (current lines 29–73, from `# Condition 1` through the final `exit 2`) with the three-lane order. The recursion guard (line 19), payload/jq (21–24), and `subagent_type` extraction (26–27) stay above this verbatim:

```bash
# Lane 1: read-only helpers ALWAYS run in-process (independent of terminal/policy).
if in_conf "$INPROCESS_CONF" "$subagent_type"; then exit 0; fi

# Fail-open floor: no terminal, or a prior adapter failure this session -> allow.
term=$("$DETECT" 2>/dev/null) || exit 0
[ "$term" != "none" ] || exit 0

sid=$(printf '%s' "$payload" | "$JQ_BIN" -er '.session_id // empty' 2>/dev/null) || sid=""
env_sid="${CLAUDE_CODE_SESSION_ID:-}"
if [ -n "$sid" ] && [ -n "$env_sid" ] && [ "$sid" != "$env_sid" ]; then
  printf 'pane-dispatch-guard: session-id mismatch (stdin %s vs env %s) — cooldown flags may not line up.\n' "$sid" "$env_sid" >&2
fi
for key in "$sid" "$env_sid" nosession; do
  if [ -n "$key" ] && [ -f "$STATE_DIR/adapter-failed-$key" ]; then
    printf 'pane-dispatch-guard: a pane adapter failed earlier this session — allowing in-process dispatch.\n' >&2
    exit 0
  fi
done

# Lane 2: judges are ALWAYS paned, regardless of policy.
if in_conf "$CONF" "$subagent_type"; then
  {
    printf 'pane-dispatch-guard: "%s" is a judge — it always runs in its own terminal pane (%s), never in-process.\n' "$subagent_type" "$term"
    printf 'Redirect it to a pane:\n'
    # shellcheck disable=SC2016
    printf '  1. Write the agent prompt to a file in the scratchpad.\n'
    # shellcheck disable=SC2016
    printf '  2. "$HOME"/.claude/panes/dispatch-pane-agent.sh dispatch %s --prompt-file <f> [--cwd <repo>]\n' "$subagent_type"
    # shellcheck disable=SC2016
    printf '  3. "$HOME"/.claude/panes/dispatch-pane-agent.sh wait --result-file <RESULT_FILE printed by dispatch>\n'
    printf 'Procedure and fallback rules: load the dispatching-pane-agents skill.\n'
  } >&2
  exit 2
fi

# Lane 3: governed worker — consult the per-session policy (first matching key).
policy=""
for key in "$env_sid" "$sid" nosession; do
  [ -n "$key" ] || continue
  pf="$STATE_DIR/pane-policy-$key"
  [ -f "$pf" ] || continue
  line="$(head -n 1 "$pf" 2>/dev/null)"
  if [ "$line" = "inline" ]; then policy="inline"; break; fi
  if printf '%s' "$line" | grep -Eq '^panes max=([1-9]|1[0-6])$'; then policy="panes"; break; fi
done

case "$policy" in
  inline) exit 0 ;;   # worker fan-out runs in-process this session
  panes)
    {
      printf 'pane-dispatch-guard: session policy is "panes" — "%s" runs in a pane/tab, not in-process (%s).\n' "$subagent_type" "$term"
      # shellcheck disable=SC2016
      printf '  1. Write the agent prompt to a file in the scratchpad.\n'
      # shellcheck disable=SC2016
      printf '  2. "$HOME"/.claude/panes/dispatch-pane-agent.sh dispatch %s --prompt-file <f> [--cwd <repo>]\n' "$subagent_type"
      # shellcheck disable=SC2016
      printf '  3. "$HOME"/.claude/panes/dispatch-pane-agent.sh wait --result-file <RESULT_FILE printed by dispatch>\n'
      printf 'The dispatcher owns pane-vs-tab and the max-N overflow. Load the dispatching-pane-agents skill.\n'
    } >&2
    exit 2 ;;
  *)  # no policy recorded (or malformed) -> ask once, then retry
    {
      printf 'pane-dispatch-guard: no pane-split policy set for this session — ask the user once.\n'
      printf '  1. Call AskUserQuestion: "inline" (workers in-process) or "panes" with a max N (suggest 3).\n'
      # shellcheck disable=SC2016
      printf '  2. Record it: "$HOME"/.claude/panes/dispatch-pane-agent.sh set-policy inline\n'
      # shellcheck disable=SC2016
      printf '     or:        "$HOME"/.claude/panes/dispatch-pane-agent.sh set-policy panes --max <N>\n'
      printf '  3. Retry this same dispatch; the guard now routes by the recorded policy.\n'
      printf 'Rationale and the three lanes: load the dispatching-pane-agents skill.\n'
    } >&2
    exit 2 ;;
esac
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `bash hooks/pane-dispatch-guard.test.sh`
Expected: PASS — all lane cases, both message-content assertions, and every retained fail-open case.

- [ ] **Step 6: Commit**

```bash
git add hooks/pane-dispatch-guard.sh hooks/pane-dispatch-guard.test.sh panes/inprocess-agents.conf panes/redirect-agents.conf
git commit -m "feat(panes): guard three-lane routing (read-only/judge/policy) + policy read"
```

---

## Task 4: Adapter `open_tab` — validation + tmux/iterm/terminal

**Files:**
- Modify: `panes/adapters/common.sh` (add `validate_open_tab_args`)
- Modify: `panes/adapters/tmux.sh`, `panes/adapters/iterm.sh`, `panes/adapters/terminal.sh`
- Test: `panes/adapters.test.sh`

**Interfaces:**
- Produces: `<adapter>.sh open_tab <existing-surface-ref> <title> <launcher-path>` → prints the new surface ref; exit 65 on arg-validation failure; exit 1 on a runtime tab-open failure; exit 64 on unknown verb. Consumed by the dispatcher (Task 7).
- Consumes: `validate_open_tab_args` validates the surface-ref (`^[A-Za-z0-9:%_.-]{1,64}$`) plus the same title/launcher checks as `validate_open_pane_args`.

- [ ] **Step 1: Write the failing tests**

Add to `panes/adapters.test.sh` (mirror its existing `open_pane` dryrun cases). The launcher must satisfy `validate_open_*_args` (path shape `.../state/runs/<id>/launch.sh` under `PANE_STATE_DIR`):

```bash
# --- open_tab: arg validation + per-adapter dryrun
export PANE_STATE_DIR="${PANE_STATE_DIR:-$TMP/state}"
RUNID="1700000000-1-1"
LAUNCH="$PANE_STATE_DIR/runs/$RUNID/launch.sh"
mkdir -p "$(dirname "$LAUNCH")"; printf '#!/usr/bin/env bash\n:\n' > "$LAUNCH"; chmod 700 "$LAUNCH"

for a in tmux iterm terminal; do
  # good args -> dryrun exits 0 and echoes the launcher
  out=$(PANE_DRYRUN=1 bash "$ADAPTERS/$a.sh" open_tab surface:42 "worker.1" "$LAUNCH" 2>&1); rc=$?
  { [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "$LAUNCH"; } && ok "$a open_tab dryrun ok" || bad "$a open_tab dryrun ok" "rc=$rc: $out"
  # bad surface ref -> exit 65, no dryrun output
  PANE_DRYRUN=1 bash "$ADAPTERS/$a.sh" open_tab 'surface 42; rm' "worker.1" "$LAUNCH" >/dev/null 2>&1
  [ $? -eq 65 ] && ok "$a open_tab rejects bad surface ref" || bad "$a open_tab rejects bad surface ref"
  # bad title -> exit 65
  PANE_DRYRUN=1 bash "$ADAPTERS/$a.sh" open_tab surface:42 'bad"title' "$LAUNCH" >/dev/null 2>&1
  [ $? -eq 65 ] && ok "$a open_tab rejects bad title" || bad "$a open_tab rejects bad title"
  # unknown verb -> exit 64
  bash "$ADAPTERS/$a.sh" bogus surface:42 "worker.1" "$LAUNCH" >/dev/null 2>&1
  [ $? -eq 64 ] && ok "$a rejects unknown verb" || bad "$a rejects unknown verb"
done
```

(Use whatever variable `adapters.test.sh` already binds for the adapters dir; the snippet assumes `$ADAPTERS` and `$TMP` per that file's setup — adapt to the local names.)

- [ ] **Step 2: Run to confirm failure**

Run: `bash panes/adapters.test.sh`
Expected: FAIL — the adapters only accept `open_pane`; `open_tab` hits the usage guard (exit 64) for every case.

- [ ] **Step 3: Add `validate_open_tab_args` to `common.sh`**

Append to `panes/adapters/common.sh`:

```bash
# validate_open_tab_args <surface-ref> <title> <launcher-path> -> 0 ok, 1 reject.
# The surface-ref is a NEW caller-supplied token crossing into adapter command
# lines; pin it to a strict allowlist covering every adapter's ref shape
# (surface:99, %3, a UUID, window-123) with no spaces/quotes/shell metacharacters.
# Title + launcher reuse the open_pane boundary exactly.
validate_open_tab_args() {
  local ref="$1" title="$2" launcher="$3"
  local ref_re='^[A-Za-z0-9:%_.-]{1,64}$'
  if ! [[ "$ref" =~ $ref_re ]]; then
    printf 'adapter: surface-ref outside allowlist [A-Za-z0-9:%%_.-] (max 64)\n' >&2; return 1
  fi
  validate_open_pane_args "$title" "$launcher"
}
```

- [ ] **Step 4: Add `open_tab` to `tmux.sh`**

A new window is tmux's "tab" once panes fill (spec). Replace the single-verb guard with a `case`. In `panes/adapters/tmux.sh`, change lines 10–23 to:

```bash
verb="${1:-}"
case "$verb" in
  open_pane)
    title="${2:-}"; launcher="${3:-}"
    validate_open_pane_args "$title" "$launcher" || exit 65
    if [ "${PANE_DRYRUN:-}" = "1" ]; then
      printf 'DRYRUN: %s split-window -d -P -F #{pane_id} "bash %s"\n' "$TMUX_BIN" "$launcher"
      printf 'DRYRUN: %s select-pane -t <ref> -T "%s"\n' "$TMUX_BIN" "$title"; exit 0
    fi
    ref=$("$TMUX_BIN" split-window -d -P -F '#{pane_id}' "bash $launcher") \
      || { printf 'tmux: split-window failed\n' >&2; exit 1; }
    "$TMUX_BIN" select-pane -t "$ref" -T "$title" 2>/dev/null || true
    printf '%s\n' "$ref" ;;
  open_tab)
    ref_in="${2:-}"; title="${3:-}"; launcher="${4:-}"
    validate_open_tab_args "$ref_in" "$title" "$launcher" || exit 65
    # tmux "tab" = a new window (the surface ref is not needed to place it; it is
    # validated for contract uniformity and audit only).
    if [ "${PANE_DRYRUN:-}" = "1" ]; then
      printf 'DRYRUN: %s new-window -d -P -F #{pane_id} "bash %s"\n' "$TMUX_BIN" "$launcher"
      printf 'DRYRUN: %s select-pane -t <ref> -T "%s"\n' "$TMUX_BIN" "$title"; exit 0
    fi
    ref=$("$TMUX_BIN" new-window -d -P -F '#{pane_id}' "bash $launcher") \
      || { printf 'tmux: new-window failed\n' >&2; exit 1; }
    "$TMUX_BIN" select-pane -t "$ref" -T "$title" 2>/dev/null || true
    printf '%s\n' "$ref" ;;
  *) printf 'usage: tmux.sh {open_pane|open_tab} ...\n' >&2; exit 64 ;;
esac
```

- [ ] **Step 5: Add `open_tab` to `iterm.sh`**

iTerm tabs are window-level (a sibling of the split panes). In `panes/adapters/iterm.sh`, replace the single-verb guard + script build (lines 15–38) with a `case`; the `open_tab` arm creates a tab in the current window:

```bash
verb="${1:-}"
case "$verb" in
  open_pane)
    title="${2:-}"; launcher="${3:-}"
    validate_open_pane_args "$title" "$launcher" || exit 65
    osa_script=$(cat <<EOF
tell application "iTerm2"
  tell current session of current window
    set newSession to (split horizontally with default profile command "bash $launcher")
  end tell
  tell newSession to set name to "$title"
  return id of newSession
end tell
EOF
) ;;
  open_tab)
    ref_in="${2:-}"; title="${3:-}"; launcher="${4:-}"
    validate_open_tab_args "$ref_in" "$title" "$launcher" || exit 65
    osa_script=$(cat <<EOF
tell application "iTerm2"
  tell current window
    set newTab to (create tab with default profile command "bash $launcher")
  end tell
  tell current session of newTab to set name to "$title"
  return id of current session of newTab
end tell
EOF
) ;;
  *) printf 'usage: iterm.sh {open_pane|open_tab} ...\n' >&2; exit 64 ;;
esac

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  printf 'DRYRUN: %s -e <<EOF\n%s\nEOF\n' "$OSASCRIPT_BIN" "$osa_script"
  exit 0
fi
if ! ref=$("$OSASCRIPT_BIN" -e "$osa_script" 2>&1); then
  printf 'iterm: osascript failed (Automation grant missing?): %s\n' "$ref" >&2; exit 1
fi
printf '%s\n' "$ref"
```

- [ ] **Step 6: Add `open_tab` to `terminal.sh`**

Terminal.app already opens every agent as a tab, so `open_tab` is its `open_pane` path (spec). In `panes/adapters/terminal.sh`, replace the single-verb guard (line 12) with a `case` that accepts either verb, taking `title`/`launcher` from the right positions:

```bash
verb="${1:-}"
case "$verb" in
  open_pane) title="${2:-}"; launcher="${3:-}" ;;
  open_tab)  ref_in="${2:-}"; title="${3:-}"; launcher="${4:-}"
             validate_open_tab_args "$ref_in" "$title" "$launcher" || exit 65 ;;
  *) printf 'usage: terminal.sh {open_pane|open_tab} ...\n' >&2; exit 64 ;;
esac
[ "$verb" = open_pane ] && { validate_open_pane_args "$title" "$launcher" || exit 65; }
```

(The rest of the file — the `osa_script` heredoc, the dryrun branch, and the run — is unchanged; both verbs share the "new tab" behavior.)

- [ ] **Step 7: Run the tests to confirm they pass**

Run: `bash panes/adapters.test.sh`
Expected: PASS — the new `open_tab` dryrun + validation cases for tmux/iterm/terminal, plus every pre-existing `open_pane` case.

- [ ] **Step 8: Commit**

```bash
git add panes/adapters/common.sh panes/adapters/tmux.sh panes/adapters/iterm.sh panes/adapters/terminal.sh panes/adapters.test.sh
git commit -m "feat(panes): open_tab adapter verb + surface-ref validation (tmux/iterm/terminal)"
```

---

## Task 5: cmux adapter `open_tab` (probe-verified)

**Files:**
- Modify: `panes/adapters/cmux.sh`
- Test: `panes/adapters.test.sh`

**Prerequisite:** Task 1's recorded finding. The steps below assume the probe confirmed `new-surface --pane <pane-ref>` attaches a tab to the named pane (the leading candidate). **If the probe found otherwise** (e.g. only workspace-level tabs), implement the recorded primitive instead and adjust the dryrun assertion accordingly — the arg-validation and control-flow structure is unchanged.

**Interfaces:**
- Consumes: the dispatcher passes the target worker pane's recorded **surface** ref (Task 6 writes `state/runs/<id>/surface`). cmux `new-surface` takes `--pane`, so `open_tab` resolves the surface ref to its pane via a tree read (the surface's `pane_ref`), then attaches. On any resolution failure → exit non-zero (dispatcher degrades to in-process).
- Produces: `cmux.sh open_tab <surface-ref> <title> <launcher>` → prints the new surface ref; exit 65 on arg-validation, exit 1 on a runtime failure.

- [ ] **Step 1: Write the failing test**

Add to `panes/adapters.test.sh`. cmux's dryrun already derives against a fake `PANE_CMUX_BIN`; for `open_tab`, assert dryrun prints the `new-surface` intent and that a bad ref is rejected. A minimal fake cmux that answers `--json tree` with the committed `tree-live.json` and echoes a ref for `new-surface`:

```bash
# --- cmux open_tab
FAKE_CMUX="$TMP/fake-cmux.sh"
cat > "$FAKE_CMUX" <<'FCE'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"--json tree"*) cat "$HOME/.claude/panes/adapters/fixtures/tab-live.json" 2>/dev/null || echo '{}' ;;
  *"new-surface"*) echo '{"surface_ref":"surface:777"}' ;;
  *"send"*|*"rename-tab"*) : ;;
  *"version"*) echo "cmux 0.64.20 (100) [test]" ;;
  *) : ;;
esac
FCE
chmod 700 "$FAKE_CMUX"

# bad surface ref -> exit 65 before any cmux call
PANE_DRYRUN=1 PANE_CMUX_BIN="$FAKE_CMUX" bash "$ADAPTERS/cmux.sh" open_tab 'bad ref' "worker.1" "$LAUNCH" >/dev/null 2>&1
[ $? -eq 65 ] && ok "cmux open_tab rejects bad surface ref" || bad "cmux open_tab rejects bad surface ref"
# good args, dryrun -> exits 0 and names new-surface
out=$(PANE_DRYRUN=1 PANE_CMUX_BIN="$FAKE_CMUX" bash "$ADAPTERS/cmux.sh" open_tab surface:42 "worker.1" "$LAUNCH" 2>&1); rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'new-surface'; } && ok "cmux open_tab dryrun names new-surface" || bad "cmux open_tab dryrun names new-surface" "rc=$rc: $out"
# unknown verb still rejected
bash "$ADAPTERS/cmux.sh" bogus surface:42 "worker.1" "$LAUNCH" >/dev/null 2>&1
[ $? -eq 64 ] && ok "cmux rejects unknown verb" || bad "cmux rejects unknown verb"
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash panes/adapters.test.sh`
Expected: FAIL — `cmux.sh` accepts only `open_pane` (line 24 hard-guards it), so `open_tab` and `bogus` both hit that guard.

- [ ] **Step 3: Refactor the cmux verb guard + add `open_tab`**

In `panes/adapters/cmux.sh`, replace the single-verb guard (line 24) and the arg binding (line 25–26) with a verb dispatch that keeps `open_pane`'s entire existing body intact and adds an `open_tab` path. The cleanest minimal change: keep the whole existing script as the `open_pane` implementation, and add an early `open_tab` branch that returns before the `open_pane` machinery:

```bash
verb="${1:-}"
case "$verb" in
  open_pane) title="${2:-}"; launcher="${3:-}"
             validate_open_pane_args "$title" "$launcher" || exit 65 ;;
  open_tab)  ref_in="${2:-}"; title="${3:-}"; launcher="${4:-}"
             validate_open_tab_args "$ref_in" "$title" "$launcher" || exit 65
             cmux_open_tab "$ref_in" "$title" "$launcher"; exit $? ;;
  *) printf 'usage: cmux.sh {open_pane|open_tab} <...>\n' >&2; exit 64 ;;
esac
```

Define `cmux_open_tab` above that guard (after `fetch_tree`/`decide_plan` are defined, so it can reuse `fetch_tree`, `WS_ARGS`, `split_capture`, `finish_surface`, `json_ref`). It resolves the caller's surface ref to its pane, then attaches a tab there:

```bash
# cmux_open_tab <surface-ref> <title> <launcher> — attach a new agent tab to the
# pane that currently holds <surface-ref>. Probe (Task 1) confirmed
# 'new-surface --pane <pane>' opens a tab inside the named pane. Any resolution
# or creation failure exits non-zero so the dispatcher degrades to in-process.
cmux_open_tab() {
  local ref="$1" tab_title="$2" tab_launcher="$3" tree pane new_ref
  # Recompute the injection-safe launcher quote for THIS launcher (the top-level
  # launcher_q was built for open_pane's $launcher).
  launcher="$tab_launcher"; launcher_q="$(printf '%q' "$launcher")"
  if [ "${PANE_DRYRUN:-}" = "1" ]; then
    printf 'DRYRUN: %s new-surface --pane <pane-of %s>\n' "$CMUX_BIN" "$ref"
    printf 'DRYRUN: %s send --surface <ref> -- "bash %s\\n"\n' "$CMUX_BIN" "$launcher"
    return 0
  fi
  tree="$(fetch_tree)" || { printf 'cmux open_tab: no tree; cannot resolve %s\n' "$ref" >&2; return 1; }
  # pane_ref of the surface whose ref == $ref (normalized TSV: pane_ref, ref, title)
  pane="$(printf '%s' "$tree" | layout_normalize_tree | awk -F'\t' -v r="$ref" '$2==r{print $1; exit}')"
  [ -n "$pane" ] || { printf 'cmux open_tab: surface %s not in tree; degrade\n' "$ref" >&2; return 1; }
  new_ref="$(split_capture new-surface --pane "$pane")" || { printf 'cmux open_tab: new-surface failed on pane %s\n' "$pane" >&2; return 1; }
  finish_surface "$new_ref" "$tab_title"   # sends the launcher, stamps + verifies the title, prints the ref
}
```

Note: `finish_surface` uses the file-global `launcher_q`; the function reassigns `launcher`/`launcher_q` above so `send_launcher` runs the tab's launcher, not the (unset) open_pane one. `TREE_RAW` stays empty in this path, so `stamp_title`'s verify-after-rename short-circuits at its `[ -n "$TREE_RAW" ] || return 0` guard — acceptable (a tab title is cosmetic; the send already happened).

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash panes/adapters.test.sh`
Expected: PASS — cmux `open_tab` validation + dryrun cases, plus every existing cmux `open_pane`/layout case.

- [ ] **Step 5: Commit**

```bash
git add panes/adapters/cmux.sh panes/adapters.test.sh
git commit -m "feat(panes): cmux open_tab verb — attach agent tab to a worker pane (probe-verified)"
```

---

## Task 6: Dispatcher — lane/session/surface markers, live-worker count, judge bypass

**Files:**
- Modify: `panes/dispatch-pane-agent.sh`
- Test: `panes/dispatch-pane-agent.test.sh`

**Interfaces:**
- Consumes: `read_policy` (Task 2); the judge set from `redirect-agents.conf`.
- Produces: at dispatch, writes `state/runs/<id>/lane` (`worker`|`judge`), `state/runs/<id>/session` (key), and `state/runs/<id>/surface` (ref, after `open_pane`). Provides `count_live_workers <key>` (dirs with `lane=worker`, `session=key`, no `agent-exit`). Judge dispatch → `open_pane`, never counted. Worker under `panes max=N`: count < N → `open_pane`; **count >= N → interim degrade to in-process (exit 3, no cooldown) — replaced by `open_tab` in Task 7.**

- [ ] **Step 1: Write the failing tests**

Add to `panes/dispatch-pane-agent.test.sh`. Build **real run-dir fixtures** (the least-proven piece per the spec's flagged assumption 1) and assert the count + routing:

```bash
# --- lane/session markers + live worker count (real run-dir fixtures)
export PANE_REDIRECT_CONF="$TMP/redirect.conf"   # dispatcher classifies lane via this
printf 'compliance-judge\nobservability-judge\n' > "$PANE_REDIRECT_CONF"
CSID="count-sess-$$"
mk_run() { # $1 lane, $2 session, $3 exited(yes/no) -> makes a fake run dir
  local d; d="$PANE_STATE_DIR/runs/$(date +%s)-$$-$RANDOM"; mkdir -p "$d"
  printf '%s\n' "$1" > "$d/lane"; printf '%s\n' "$2" > "$d/session"; printf 'surface:%s\n' "$RANDOM" > "$d/surface"
  [ "$3" = yes ] && printf 'DONE\n' > "$d/agent-exit"; printf '%s\n' "$d"
}
mk_run worker "$CSID" no  >/dev/null   # live worker 1
mk_run worker "$CSID" no  >/dev/null   # live worker 2
mk_run worker "$CSID" yes >/dev/null   # completed -> not counted
mk_run judge  "$CSID" no  >/dev/null   # judge -> not counted
mk_run worker other-sess no >/dev/null # other session -> not counted
n=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" count-workers 2>/dev/null)
[ "$n" = "2" ] && ok "count_live_workers excludes exited/judge/other-session" || bad "count_live_workers" "got $n want 2"

# judge dispatch -> open_pane, lane=judge, never blocked by policy count
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\necho surface:J1\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" set-policy panes --max 1 >/dev/null 2>&1
out=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" dispatch compliance-judge --prompt-file "$PROMPT" --result-file "$TMP/j.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "judge dispatch under panes max=1 still opens a pane" || bad "judge dispatch under panes" "rc=$rc: $out"
jd=$(find "$PANE_STATE_DIR/runs" -name lane -newer "$PROMPT" -exec grep -l judge {} \; | head -n1)
[ -n "$jd" ] && ok "judge run tagged lane=judge" || bad "judge run tagged lane=judge"

# worker under panes max=1 with 2 live workers already -> interim in-process (exit 3), no cooldown
out=$(CLAUDE_CODE_SESSION_ID="$CSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/w.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 3 ] && ok "worker over max -> interim in-process exit 3" || bad "worker over max exit 3" "rc=$rc: $out"
[ ! -f "$PANE_STATE_DIR/adapter-failed-$CSID" ] && ok "over-max does not write cooldown" || bad "over-max writes no cooldown"
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: FAIL — `count-workers` is not a command; the dispatcher does not yet tag lanes or gate workers on the count.

- [ ] **Step 3: Add lane classification, the count helper, and a `count-workers` debug subcommand**

In `panes/dispatch-pane-agent.sh`, add the judge-set conf var beside the other paths (after `DETECT=...`):

```bash
REDIRECT_CONF="${PANE_REDIRECT_CONF:-$PANES_DIR/redirect-agents.conf}"
```

Add near `read_policy`:

```bash
# is_judge <agent-type> -> 0 if listed in the always-paned judge conf.
is_judge() {
  local want="$1" line
  [ -f "$REDIRECT_CONF" ] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"; line=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -n "$line" ] && [ "$line" = "$want" ] && return 0
  done < "$REDIRECT_CONF"
  return 1
}

# count_live_workers <session-key> -> integer. Live = a run dir tagged
# lane=worker for this session with no agent-exit marker yet. Judge runs
# (lane=judge) and other sessions are excluded — the "judge not counted" and
# "per-session" guarantees ride entirely on these two file checks.
count_live_workers() {
  local key="$1" d n=0
  [ -d "$RUNS_DIR" ] || { printf '0\n'; return 0; }
  for d in "$RUNS_DIR"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}agent-exit" ] && continue
    [ "$(cat "${d}lane" 2>/dev/null)" = worker ] || continue
    [ "$(cat "${d}session" 2>/dev/null)" = "$key" ] || continue
    n=$((n+1))
  done
  printf '%s\n' "$n"
}
```

Add a tiny `count-workers` subcommand (debug/testable surface) to the top-level `case`:

```bash
  count-workers) count_live_workers "${CLAUDE_CODE_SESSION_ID:-nosession}" ;;
```

- [ ] **Step 4: Write the lane/session markers and gate the worker path**

Extend `open_pane_or_cooldown` to record the surface ref (optional 4th-positional run dir), keeping its direct-call `die` semantics:

```bash
open_pane_or_cooldown() { # $1 title, $2 launcher, $3 run_dir(optional) — prints TERMINAL/PANE_REF
  local term ref sid
  term="$("$DETECT" 2>/dev/null)" || term=none
  if [ "$term" = "none" ] || [ ! -x "$ADAPTERS_DIR/$term.sh" ]; then
    die "no supported terminal ('$term') — dispatch in-process via the Agent tool instead" 3
  fi
  if ! ref="$("$ADAPTERS_DIR/$term.sh" open_pane "$1" "$2")"; then
    sid="${CLAUDE_CODE_SESSION_ID:-nosession}"
    : > "$STATE_DIR/adapter-failed-$sid"
    die "adapter '$term' failed; cooldown flag written — in-process dispatch is allowed for the rest of this session" 4
  fi
  [ -n "${3:-}" ] && printf '%s\n' "$ref" > "$3/surface" 2>/dev/null
  printf 'TERMINAL: %s\nPANE_REF: %s\n' "$term" "$ref"
}
```

In the `dispatch)` arm, after the launcher is written and `chmod 700`'d (after line 145) and `export PANE_AGENT_ROLE="$role"`, replace the single `open_pane_or_cooldown` call (line 150) with lane tagging + policy gating:

```bash
    key="${CLAUDE_CODE_SESSION_ID:-nosession}"
    if is_judge "$agent_type"; then lane=judge; else lane=worker; fi
    printf '%s\n' "$lane" > "$run_dir/lane"
    printf '%s\n' "$key"  > "$run_dir/session"

    export PANE_AGENT_ROLE="$role"
    title="$(sanitize_title "$agent_type")"
    if [ "$lane" = worker ]; then
      policy="$(read_policy "$STATE_DIR/pane-policy-$key")"
      case "$policy" in
        panes\ max=*)
          n="${policy#panes max=}"
          live="$(count_live_workers "$key")"
          if [ "$live" -ge "$n" ]; then
            # INTERIM (replaced by open_tab in Task 7): at/over the worker max,
            # degrade THIS spawn to in-process without a cooldown (capacity, not
            # an adapter failure). exit 3 = "run in-process", same as no-terminal.
            die "worker max $n reached ($live live) — dispatch this spawn in-process; overflow-to-tab lands in Task 7" 3
          fi ;;
        *) : ;;   # inline/none reaching the dispatcher: single pane, no gating
      esac
    fi
    open_pane_or_cooldown "$title" "$launcher" "$run_dir"
    printf 'RESULT_FILE: %s\n' "$result_file"
```

(Delete the now-superseded lines 149–151; `role`/`title` are folded into the block above.)

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: PASS — count fixture, judge-bypass, lane tagging, over-max interim exit 3 with no cooldown, and every pre-existing case.

- [ ] **Step 6: Commit**

```bash
git add panes/dispatch-pane-agent.sh panes/dispatch-pane-agent.test.sh
git commit -m "feat(panes): dispatcher lane/session tagging + live-worker count + judge bypass"
```

---

## Task 7: Dispatcher — overflow to `open_tab` (round-robin)

**Files:**
- Modify: `panes/dispatch-pane-agent.sh`
- Test: `panes/dispatch-pane-agent.test.sh`

**Interfaces:**
- Consumes: `count_live_workers`, the per-run `surface` markers (Task 6), the adapter `open_tab` verb (Tasks 4–5).
- Produces: at/over the worker max, selects a live worker pane round-robin (rotating index `state/pane-rr-<key>`) and `open_tab`s into it; on `open_tab` failure → cooldown flag + in-process (exit 4). Replaces Task 6's interim exit-3 branch.

- [ ] **Step 1: Write the failing tests**

Replace the Task-6 "worker over max -> interim exit 3" assertion with overflow assertions, and add an `open_tab`-failure case. The fake adapter must answer both `open_pane` and `open_tab`:

```bash
# fake adapter: open_pane -> surface:P<n>; open_tab -> record its args, surface:T1
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:P$RANDOM ;;\n  open_tab) printf "%%s\\n" "$@" > "%s/tab-args"; echo surface:T1 ;;\n  *) exit 64 ;;\nesac\n' "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
OSID="overflow-sess-$$"
CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" set-policy panes --max 2 >/dev/null 2>&1
# two live workers with known surface refs
d1="$PANE_STATE_DIR/runs/$(date +%s)-$$-1"; mkdir -p "$d1"; printf 'worker\n'>"$d1/lane"; printf '%s\n' "$OSID">"$d1/session"; printf 'surface:AA\n'>"$d1/surface"
d2="$PANE_STATE_DIR/runs/$(date +%s)-$$-2"; mkdir -p "$d2"; printf 'worker\n'>"$d2/lane"; printf '%s\n' "$OSID">"$d2/session"; printf 'surface:BB\n'>"$d2/surface"
# next worker overflows to a tab, round-robin picks one of the live surfaces
out=$(CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/o1.md" --cwd "$TMP" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "overflow worker exits 0 (tab)" || bad "overflow worker exits 0" "rc=$rc: $out"
tabref=$(sed -n '2p' "$TMP/tab-args")   # open_tab <surface> <title> <launcher>: argv[2] = surface
case "$tabref" in surface:AA|surface:BB) ok "overflow open_tab targets a live worker surface" ;; *) bad "overflow open_tab targets a live worker surface" "$tabref" ;; esac
printf '%s' "$out" | grep -q '^PANE_REF: surface:T1' && ok "overflow prints the new tab ref" || bad "overflow prints tab ref" "$out"

# open_tab failure -> cooldown + in-process (exit 4)
printf '#!/usr/bin/env bash\ncase "$1" in\n  open_pane) echo surface:P1 ;;\n  open_tab) exit 1 ;;\n  *) exit 64 ;;\nesac\n' > "$PANE_ADAPTERS_DIR/cmux.sh"; chmod 700 "$PANE_ADAPTERS_DIR/cmux.sh"
CLAUDE_CODE_SESSION_ID="$OSID" bash "$DISPATCH" dispatch general-purpose --prompt-file "$PROMPT" --result-file "$TMP/o2.md" --cwd "$TMP" >/dev/null 2>&1
[ $? -eq 4 ] && ok "open_tab failure -> exit 4" || bad "open_tab failure -> exit 4"
[ -f "$PANE_STATE_DIR/adapter-failed-$OSID" ] && ok "open_tab failure writes cooldown" || bad "open_tab failure writes cooldown"
```

- [ ] **Step 2: Run to confirm failure**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: FAIL — the over-max branch still exits 3 (interim), so the overflow-to-tab assertions fail.

- [ ] **Step 3: Add round-robin selection + `open_tab_or_cooldown`**

In `panes/dispatch-pane-agent.sh`, add beside `count_live_workers`:

```bash
# select_worker_surface <key> -> a live worker pane's surface ref, round-robin.
# Non-zero if none has a recorded surface. The rotating index persists in state.
select_worker_surface() {
  local key="$1" d ref i=0 rr="$STATE_DIR/pane-rr-$key"
  local refs=()
  for d in "$RUNS_DIR"/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}agent-exit" ] && continue
    [ "$(cat "${d}lane" 2>/dev/null)" = worker ] || continue
    [ "$(cat "${d}session" 2>/dev/null)" = "$key" ] || continue
    ref="$(cat "${d}surface" 2>/dev/null)"
    [ -n "$ref" ] && refs+=("$ref")
  done
  [ "${#refs[@]}" -gt 0 ] || return 1
  [ -f "$rr" ] && i="$(cat "$rr" 2>/dev/null)"
  [[ "$i" =~ ^[0-9]+$ ]] || i=0
  printf '%s\n' "$(( i + 1 ))" > "$rr" 2>/dev/null
  printf '%s\n' "${refs[$(( i % ${#refs[@]} ))]}"
}

open_tab_or_cooldown() { # $1 surface, $2 title, $3 launcher, $4 run_dir — prints TERMINAL/PANE_REF
  local term ref sid
  term="$("$DETECT" 2>/dev/null)" || term=none
  if [ "$term" = "none" ] || [ ! -x "$ADAPTERS_DIR/$term.sh" ]; then
    die "no supported terminal ('$term') — dispatch in-process via the Agent tool instead" 3
  fi
  if ! ref="$("$ADAPTERS_DIR/$term.sh" open_tab "$1" "$2" "$3")"; then
    sid="${CLAUDE_CODE_SESSION_ID:-nosession}"
    : > "$STATE_DIR/adapter-failed-$sid"
    die "adapter '$term' open_tab failed; cooldown flag written — in-process dispatch is allowed for the rest of this session" 4
  fi
  [ -n "${4:-}" ] && printf '%s\n' "$ref" > "$4/surface" 2>/dev/null
  printf 'TERMINAL: %s\nPANE_REF: %s\n' "$term" "$ref"
}
```

- [ ] **Step 4: Replace the interim over-max branch with overflow**

In the `dispatch)` arm's worker block (Task 6), replace the interim `die "worker max ... in Task 7" 3` with the overflow path, and route the final open call:

```bash
    export PANE_AGENT_ROLE="$role"
    title="$(sanitize_title "$agent_type")"
    overflow=0
    if [ "$lane" = worker ]; then
      policy="$(read_policy "$STATE_DIR/pane-policy-$key")"
      case "$policy" in
        panes\ max=*)
          n="${policy#panes max=}"
          live="$(count_live_workers "$key")"
          [ "$live" -ge "$n" ] && overflow=1 ;;
        *) : ;;
      esac
    fi
    if [ "$overflow" = 1 ]; then
      target="$(select_worker_surface "$key")" || die "no live worker surface to overflow into — dispatch in-process" 3
      open_tab_or_cooldown "$target" "$title" "$launcher" "$run_dir"
    else
      open_pane_or_cooldown "$title" "$launcher" "$run_dir"
    fi
    printf 'RESULT_FILE: %s\n' "$result_file"
```

- [ ] **Step 5: Run the tests to confirm they pass**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: PASS — overflow targets a live worker surface, prints the tab ref, `open_tab` failure writes the cooldown and exits 4, and every earlier case still passes.

- [ ] **Step 6: Run the full pane suite**

Run each and confirm `0 failed`:
```bash
bash hooks/pane-dispatch-guard.test.sh
bash panes/dispatch-pane-agent.test.sh
bash panes/adapters.test.sh
bash panes/adapters/cmux-layout.test.sh
bash panes/adapters/cmux-exec.test.sh
bash panes/run-pane-agent.test.sh
bash panes/terminal-detect.test.sh
```
Expected: every suite prints `N passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add panes/dispatch-pane-agent.sh panes/dispatch-pane-agent.test.sh
git commit -m "feat(panes): worker overflow to open_tab with round-robin pane selection"
```

---

## Task 8: Docs — skill, gate stub, ADR

**Files:**
- Modify: `skills/dispatching-pane-agents/SKILL.md`
- Modify: `rules/gates.md`
- Create: `docs/decisions/0009-pane-split-policy-three-lane-governance.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Document the policy in the skill**

Add a `## Session pane-split policy` section to `skills/dispatching-pane-agents/SKILL.md` covering: the three lanes (read-only in-process / always-paned judges / policy-governed workers); the lazy first-worker-dispatch prompt (`AskUserQuestion` → `set-policy inline` or `set-policy panes --max N` → retry); `inline` vs `panes max=N` semantics; overflow-to-tab (round-robin) and its degrade-to-in-process path; and that judges are never asked about, never inline, and never counted against N. Note `N` is bounded 1..16.

- [ ] **Step 2: Correct the stale gate stub**

In `rules/gates.md`, the **Pane-dispatch redirect** bullet currently reads (verbatim): "plan implementers are skill-routed". That is now false — plan implementers are policy-governed workers. **Correct it in place** (do not append):

> **Pane-dispatch redirect:** substantial agents run in terminal panes, not in-process — the two judges are hook-enforced (`hooks/pane-dispatch-guard.sh` always paned, outside the session policy) and read-only helpers (`Explore`/`Plan`) always run in-process; every other worker (plan implementers, `general-purpose`, fan-out) is governed by the per-session pane-split policy (`inline` / `panes max=N`, captured lazily at the first worker dispatch). Procedure: `dispatching-pane-agents`.

- [ ] **Step 3: Write the ADR**

Confirm the next number: `ls docs/decisions/` (expect `0009` to be next after `0008`). Create `docs/decisions/0009-pane-split-policy-three-lane-governance.md` recording: the decision (three-lane governance — read-only in-process, judges always-paned, workers policy-governed; the include→exclude reshaping of `redirect-agents.conf`); the options weighed (single include→exclude flip vs. the three-lane split; the user's review-gate choice that `inline` must not silence the judges and that judge panes are uncounted); why the three-lane model won; and the consequences (plan implementers move from skill-routed judgment to policy-governed; the new `open_tab` boundary; `pane-policy-<key>` state). Embed a small rendered Mermaid decision diagram of the three lanes (see `diagramming-technical-docs`).

- [ ] **Step 4: Commit**

```bash
git add skills/dispatching-pane-agents/SKILL.md rules/gates.md docs/decisions/0009-pane-split-policy-three-lane-governance.md
git commit -m "docs(panes): three-lane pane-split policy — skill, gate stub, ADR 0009"
```

---

## Self-review notes (author, against the spec)

- **Spec coverage:** Trigger/eligibility (guard, Task 3) ✓; three lanes (Tasks 3, 6) ✓; `inline`/`panes max=N` capture (Tasks 2–3) ✓; count + overflow-to-tab (Tasks 6–7) ✓; `open_tab` adapter verb, cmux-first probe (Tasks 1, 4, 5) ✓; `pane-policy-<key>` state (Task 2) ✓; every-path-degrades error handling (fail-open floor in the guard, exit-3 capacity/no-terminal, exit-4 cooldown throughout) ✓; docs + gate-stub + ADR (Task 8) ✓. All seven Gherkin acceptance scenarios map to named tests: scenario 1 (Task 3 inline + guard), 2 (Task 7 overflow), 3 (Task 3 read-only), 4 (Task 3 judge under inline), 5 (Task 6 judge-not-counted), 6 (Task 6 count<N reclaim), 7 (Task 7 open_tab failure).
- **Flagged assumptions:** #1 liveness + lane tag → Task 6 proven on real run-dir fixtures; #2 cmux tab primitive → Task 1 live probe gating Task 5; #3 round-robin → Task 7 (least-loaded is a noted fallback); #4 session-id stability → safe re-ask degrade, no code (guard re-asks when no policy under the current key).
- **Security carry-forwards (compliance judge):** `open_tab` surface-ref allowlist + title/launcher reuse (Task 4 `validate_open_tab_args`); bounded-N validated at write (Task 2) and read (Tasks 2–3, dispatcher); state default-deny via `umask 077`; no interpolation of caller tokens into adapter command lines (dryrun assertions confirm the constructed command shape).
- **Type consistency:** `read_policy` emits `panes max=N`; the dispatcher parses it with `${policy#panes max=}` and the guard with `^panes max=([1-9]|1[0-6])$` — same format, both bounded to 16. `open_tab <surface> <title> <launcher>` argument order is identical across `validate_open_tab_args`, all four adapters, and `open_tab_or_cooldown`. Lane values are exactly `worker`/`judge` at every producer (dispatcher write) and consumer (count/select).
- **Execution note:** Task 1 is a live operator gate (real cmux), not a fake-binary subagent task; Task 5 depends on its recorded finding. Re-verify tool version pins at implementation start (Global Constraints).
