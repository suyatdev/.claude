# Pane Layout v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pane-dispatched agents build a deterministic one-workspace cmux layout — main far-left, progressive 2x2 implementer quadrant, far-right aux column, tab overflow — derived live from `cmux --json tree` plus a title convention, with zero persistent layout state.

**Architecture:** The dispatcher grows one `--role implementer|aux` flag exported as `PANE_AGENT_ROLE`; the cmux adapter fetches the tree, asks a new sourced *pure* helper (`cmux-layout.sh`) for an action plan (`reuse`/`split`/`tab`/`aux-create`), executes it, and stamps a managed title (`impl.<slot>:<run-id> <label>` / `aux:<run-id> <label>`). The runner writes an `agent-exit` marker after a successful result write so finished surfaces are detectable. Layout smarts only ever fail INTO the legacy `new-split down` path (Tier 1, stderr breadcrumb, never cooldown); only the legacy path failing keeps today's Tier-2 cooldown semantics.

**Tech Stack:** bash (macOS /usr/bin/env bash — assume 3.2: indexed arrays OK, NO `declare -A`), jq 1.7.1 at `/usr/bin/jq`, cmux 0.64.20 (100), shellcheck 0.11.0.

**Spec:** `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md` (user-approved 2026-07-21 incl. aux-reuse extension + 4 flagged assumptions). Do NOT edit the spec file — its blob SHA keys the judge verdicts.

## Global Constraints

- Toolchain pinned: cmux 0.64.20 (100), jq 1.7.1, claude CLI 2.1.216, shellcheck 0.11.0, macOS Darwin 25.5.0.
- Title allowlist is FROZEN and security-reviewed: `[A-Za-z0-9 ._:-]`, max 64 chars. The adapter composes managed titles *inside* that allowlist; truncation is always from the right (the prefix is never eaten).
- Adapter contract `open_pane <title> <launcher>` is FROZEN — `common.sh` and the tmux/iterm/terminal adapters are untouched.
- State added: NONE beyond `state/runs/<run-id>/agent-exit`. No new files under `state/`, no slot maps.
- The raw `PANE_AGENT_ROLE` env value never enters a command line or title — only the adapter's own mapped constant does.
- Degrade-never-block: Tier-1 failures (jq missing, tree unparseable, derivation nonsense, scoping unestablishable) → legacy `new-split down` + one stderr breadcrumb `cmux-layout: degraded (<reason>)` + exit 0. Tier-2 (legacy split or send fails) → exit non-zero → dispatcher cooldown, exactly today's semantics. No timeout wrappers (accepted risk).
- Env overrides are test-only precedent (`PANE_CLAUDE_BIN`/`PANE_STATE_DIR`): new ones are `PANE_CMUX_BIN`, `PANE_JQ_BIN`.
- Every degradation/guard test is validated by mutating the code it guards and watching it go RED before trusting green (falsification discipline — mandatory).
- `shellcheck` 0.11.0 must pass on every touched script before its commit.
- Files stay under 400 lines. Match the existing scripts' comment style (comments state the *why*, cite spec/obs findings).
- Commits on branch `feature/pane-layout-v2`. Each commit stages `coding-memory/branches/pane-layout-v2.md` with a one-line progress note (doc-guard requires a doc alongside substantial source changes).
- NOT in scope: `close-surface`, `resize-pane`, other adapters, kitty, README standardization.

## File Structure

- `panes/cmux-layout-probe.sh` — NEW: scripted live probe (re-run on any cmux upgrade).
- `panes/adapters/fixtures/tree-live.json` — NEW: live-captured `--json tree` fixture (scratch workspace only, reviewed before commit).
- `panes/run-pane-agent.sh` — MODIFY: agent-exit marker after result write.
- `panes/dispatch-pane-agent.sh` — MODIFY: `--role` flag, env export, title prefix drop.
- `panes/handoff-wrapper.sh` — MODIFY: best-effort in-pane rename on adoption.
- `panes/adapters/cmux-layout.sh` — NEW: sourced pure decision helper.
- `panes/adapters/cmux.sh` — REWRITE: role mapping, tree fetch, plan execution, two-tier degradation, derive-then-print dryrun.
- `panes/adapters/cmux-layout.test.sh` — NEW: Layer-1 pure decision tests (canned JSON, no cmux).
- `panes/adapters/cmux-exec.test.sh` — NEW: Layer-2 fake-cmux call-sequence + degradation tests.
- `panes/run-pane-agent.test.sh`, `panes/dispatch-pane-agent.test.sh`, `panes/adapters.test.sh` — EXTEND (Layer 3).
- `skills/dispatching-pane-agents/SKILL.md` — MODIFY: document `--role`.
- `coding-memory/branches/pane-layout-v2.md` — NEW: branch log (probe results land here first).

---

### Task 1: Live probe — resolve the flagged assumptions and capture the tree fixture

The spec's four assumptions and two open questions are resolved HERE, before any adapter code exists (both judges required probes logged first). The probe is a committed script so a cmux upgrade can re-run it.

**Files:**
- Create: `panes/cmux-layout-probe.sh`
- Create: `panes/adapters/fixtures/tree-live.json`
- Create: `coding-memory/branches/pane-layout-v2.md`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: probe findings in the branch log that Tasks 5–7 depend on: (P1) bare-`tree` workspace scoping mechanism, (P2) real `--json tree` JSON shape + fixture, (P3) `new-pane --direction right` existence/geometry, (P4) `respawn-pane --command` quoting semantics, (P5) whether `--json new-surface` returns refs, (P6) `rename-tab --surface "$CMUX_SURFACE_ID"` from inside a pane, (P7) `$CMUX_WORKSPACE_ID` format vs tree `workspace_ref` format.

- [ ] **Step 1: Write the probe script**

```bash
#!/usr/bin/env bash
# cmux-layout-probe.sh — live probe backing the pane-layout-v2 assumptions
# (spec: docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md). Run it
# from a cmux pane after any cmux upgrade, BEFORE trusting the layout adapter.
# It builds a scratch workspace, exercises every primitive the adapter relies
# on, prints a P1..P7 findings report, captures the scratch workspace's tree
# JSON as the test fixture, and cleans up after an Enter.
set -u
CMUX_BIN="${PANE_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
JQ_BIN="${PANE_JQ_BIN:-/usr/bin/jq}"
FIXTURE="${1:-$HOME/.claude/panes/adapters/fixtures/tree-live.json}"

say() { printf '\n== %s\n' "$*"; }
[ -x "$CMUX_BIN" ] || { echo "no cmux at $CMUX_BIN"; exit 1; }
[ -x "$JQ_BIN" ] || { echo "no jq at $JQ_BIN"; exit 1; }

say "P7: env formats (record verbatim)"
printf 'CMUX_WORKSPACE_ID=%s\nCMUX_SURFACE_ID=%s\n' \
  "${CMUX_WORKSPACE_ID:-unset}" "${CMUX_SURFACE_ID:-unset}"

say "P2a: create scratch workspace"
ws_out="$("$CMUX_BIN" --json new-workspace 2>&1)"; printf '%s\n' "$ws_out"
ws_ref="$(printf '%s' "$ws_out" | "$JQ_BIN" -er '.workspace_ref' 2>/dev/null)" \
  || { echo "could not parse workspace ref -- record the raw output above and STOP"; exit 1; }

say "P1: is bare --json tree scoped to the CALLING workspace?"
echo "bare tree workspace refs:"
"$CMUX_BIN" --json tree 2>/dev/null | "$JQ_BIN" '[.. | objects | .workspace_ref? // empty] | unique'
echo "--all tree workspace refs:"
"$CMUX_BIN" --json tree --all 2>/dev/null | "$JQ_BIN" '[.. | objects | .workspace_ref? // empty] | unique'
echo "(P1 = scoped iff the bare list excludes $ws_ref while --all includes it)"

say "P3: does new-pane --direction right exist, and is it a full-height column?"
"$CMUX_BIN" --json new-pane --direction right --workspace "$ws_ref" 2>&1 || echo "P3: FAILED (record verbatim)"
echo "(visually confirm in the scratch workspace: full-height right column?)"

say "P2b+P5: split with ref capture, then tab via new-surface"
sp_out="$("$CMUX_BIN" --json new-split down --workspace "$ws_ref" 2>&1)"; printf '%s\n' "$sp_out"
sp_ref="$(printf '%s' "$sp_out" | "$JQ_BIN" -er '.surface_ref' 2>/dev/null)" || sp_ref=""
pane_ref="$(printf '%s' "$sp_out" | "$JQ_BIN" -er '.pane_ref' 2>/dev/null)" || pane_ref=""
if [ -n "$pane_ref" ]; then
  echo "P5 new-surface --json output:"
  "$CMUX_BIN" --json new-surface --pane "$pane_ref" 2>&1
fi

say "P4: respawn-pane --command quoting (does the command run through a shell?)"
if [ -n "$sp_ref" ]; then
  "$CMUX_BIN" respawn-pane --surface "$sp_ref" --command "echo A B && echo QUOTED" 2>&1
  echo "(inspect that surface: 'A B' then 'QUOTED' on separate lines = shell semantics;"
  echo " literal '&&' in output = argv semantics -- record which)"
fi

say "P6: rename-tab --surface with a managed-grammar title"
[ -n "$sp_ref" ] && "$CMUX_BIN" rename-tab --surface "$sp_ref" -- "impl.1:1700000000-1-1 probe" 2>&1
echo "(then run: $CMUX_BIN --json tree --all | $JQ_BIN '..|objects|select(.surface_ref?==\"$sp_ref\").title'"
echo " to confirm the title round-trips through the tree)"

say "P2c: capture the scratch workspace subtree as the committed fixture"
"$CMUX_BIN" --json tree --all 2>/dev/null \
  | "$JQ_BIN" --arg ws "$ws_ref" '[.. | objects | select(.workspace_ref? == $ws)]' > "$FIXTURE"
printf 'fixture written: %s (%s bytes) -- REVIEW before committing (no real titles)\n' \
  "$FIXTURE" "$(wc -c < "$FIXTURE" | tr -d ' ')"

say "cleanup"
printf 'Press Enter to close the scratch workspace %s ' "$ws_ref"; IFS= read -r _
"$CMUX_BIN" close-workspace --workspace "$ws_ref" 2>&1 || echo "close it manually"
```

Save as `panes/cmux-layout-probe.sh`, `chmod 755`. If cmux help shows different flag names for any subcommand (`--workspace` targeting, `close-workspace`), adjust the probe to the real flags and note the correction in the report — the probe is evidence-gathering, not a contract.

- [ ] **Step 2: Run it from a cmux pane**

Run: `mkdir -p ~/.claude/panes/adapters/fixtures && bash ~/.claude/panes/cmux-layout-probe.sh`
Expected: a P1–P7 report and `panes/adapters/fixtures/tree-live.json` (non-empty JSON array).

- [ ] **Step 3: Record findings and gate**

Create `coding-memory/branches/pane-layout-v2.md` with a `## Live probe (cmux 0.64.20)` section recording P1–P7 **verbatim** (exact JSON shapes, exact quoting behavior). Then apply the gates:

- **P1 both-fail gate:** if bare `tree` is NOT workspace-scoped AND `$CMUX_WORKSPACE_ID` cannot be matched to tree `workspace_ref`s (P7 formats irreconcilable) — **STOP and escalate to the user**: the whole feature would be permanently Tier-1 legacy (spec assumption 1).
- **P2 shape gate:** if the tree JSON does not nest surfaces (with `surface_ref` + `title`) under objects carrying `pane_ref` + `surfaces`, rewrite `layout_normalize_tree`'s jq (Task 4 Step 3) against the real shape — the fixture test will enforce it either way.
- **P3/P4/P5 notes:** Task 7's executor already treats `new-pane` failure, respawn quoting, and missing `new-surface` refs as runtime fallbacks; record which path is live so Task 7's fixtures match reality.

- [ ] **Step 4: Commit**

```bash
git add panes/cmux-layout-probe.sh panes/adapters/fixtures/tree-live.json coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): add cmux layout live probe + captured tree fixture"
```

---

### Task 2: run-pane-agent.sh — the agent-exit completion marker

**Files:**
- Modify: `panes/run-pane-agent.sh` (insert after the `write_result "$body" "$status"` line, currently line 68)
- Test: `panes/run-pane-agent.test.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `state/runs/<run-id>/agent-exit` containing exactly `DONE` or `FAILED` (one line), written ONLY after a successful result write. `fail_early` writes NO marker. Tasks 4–5 read it via `layout_run_finished`.

- [ ] **Step 1: Write the failing tests**

Append to `panes/run-pane-agent.test.sh` before the final summary `printf`:

```bash
# 7-9. agent-exit marker (pane-layout v2): written only after a successful
# result write, containing the status; fail_early and non-runs-shaped run dirs
# write no marker.
RUNS="$TMP/state/runs/1700000000-2-2"; mkdir -p "$RUNS"
cp "$PROMPT" "$RUNS/prompt.md"
make_stub 'printf "{\"result\":\"ok\"}\n"'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS/prompt.md" "$TMP/r7.md" "$TMP" >/dev/null 2>&1
if [ "$(cat "$RUNS/agent-exit" 2>/dev/null)" = "DONE" ]; then
  printf 'ok   — marker DONE after clean run\n'; pass=$((pass+1))
else printf 'FAIL — marker DONE after clean run\n'; fail=$((fail+1)); fi

RUNS2="$TMP/state/runs/1700000000-3-3"; mkdir -p "$RUNS2"; cp "$PROMPT" "$RUNS2/prompt.md"
make_stub 'exit 3'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS2/prompt.md" "$TMP/r8.md" "$TMP" >/dev/null 2>&1
if [ "$(cat "$RUNS2/agent-exit" 2>/dev/null)" = "FAILED" ]; then
  printf 'ok   — marker FAILED after failed run\n'; pass=$((pass+1))
else printf 'FAIL — marker FAILED after failed run\n'; fail=$((fail+1)); fi

RUNS3="$TMP/state/runs/1700000000-4-4"; mkdir -p "$RUNS3"
# fail_early path: prompt file missing entirely
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$RUNS3/prompt.md" "$TMP/r9.md" "$TMP" >/dev/null 2>&1
if [ ! -e "$RUNS3/agent-exit" ]; then
  printf 'ok   — fail_early writes no marker\n'; pass=$((pass+1))
else printf 'FAIL — fail_early writes no marker\n'; fail=$((fail+1)); fi

# prompt outside a runs/ dir (shape guard): no marker anywhere near it
make_stub 'printf "{\"result\":\"ok\"}\n"'
PANE_CLAUDE_BIN="$TMP/claude-stub" bash "$RUNNER" pane-echo "$PROMPT" "$TMP/r10.md" "$TMP" >/dev/null 2>&1
if [ ! -e "$TMP/agent-exit" ]; then
  printf 'ok   — shape guard: no marker outside runs dirs\n'; pass=$((pass+1))
else printf 'FAIL — shape guard: no marker outside runs dirs\n'; fail=$((fail+1)); fi
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash panes/run-pane-agent.test.sh`
Expected: `FAIL — marker DONE after clean run` and `FAIL — marker FAILED after failed run`; the fail_early and shape-guard cases pass vacuously (no marker exists yet); summary shows 2 failed.

- [ ] **Step 3: Implement the marker**

In `panes/run-pane-agent.sh`, immediately after `write_result "$body" "$status" || fail_early "cannot write result file: $result_file"`:

```bash
# Layout-v2 completion marker: written ONLY after a successful result write, so
# a fail_early run leaves no marker and its pane is never auto-reused (spec:
# the error pane is preserved for post-mortem). Run dir comes from the prompt
# file's directory with a shape guard — never trust it blindly.
marker_dir="$(cd "$(dirname "$prompt_file")" 2>/dev/null && pwd)" || marker_dir=""
case "$marker_dir" in
  */runs/*) printf '%s\n' "$status" > "$marker_dir/agent-exit" 2>/dev/null \
              || printf 'run-pane-agent: could not write agent-exit marker\n' >&2 ;;
esac
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash panes/run-pane-agent.test.sh`
Expected: all cases ok, `0 failed`.

- [ ] **Step 5: Falsify the guards**

Temporarily move the marker block INTO `write_result` (so fail_early also writes it) → run the suite → the `fail_early writes no marker` case must go RED. Revert. Then temporarily drop the `case ... */runs/*)` guard → the shape-guard case must go RED. Revert. If either stays green, fix the TEST before proceeding.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck panes/run-pane-agent.sh panes/run-pane-agent.test.sh
git add panes/run-pane-agent.sh panes/run-pane-agent.test.sh coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): agent-exit marker after successful result write"
```

---

### Task 3: dispatcher --role flag + role env + title prefix drop + handoff rename

**Files:**
- Modify: `panes/dispatch-pane-agent.sh` (usage comment lines 3–6; dispatch arg loop lines 85–93; title line 143; handoff line 204)
- Modify: `panes/handoff-wrapper.sh` (between the `read` and the `exec`, lines 19–20)
- Test: `panes/dispatch-pane-agent.test.sh`

**Interfaces:**
- Consumes: nothing new.
- Produces: `PANE_AGENT_ROLE` (`implementer`|`aux`) exported into the adapter's environment; adapter title argument is now the bare agent type (no `pane: ` prefix) — Tasks 6–7 read the env var and compose the managed title from this label.

- [ ] **Step 1: Write the failing tests**

In `panes/dispatch-pane-agent.test.sh`: (a) make the ok-adapter stub record the role env — replace the existing stub line 25 with:

```bash
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/adapter-args"\nprintf "%%s\\n" "${PANE_AGENT_ROLE:-unset}" > "%s/adapter-role"\necho surface:99\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
```

(b) change the title expectation (line 50) — the `pane: ` prefix is dropped:

```bash
[ "$title" = "observability-judge" ] && ok "bare agent-type title passed" || bad "bare agent-type title passed" "$title"
```

(c) after the title assertion, add:

```bash
role_seen=$(cat "$TMP/adapter-role" 2>/dev/null)
[ "$role_seen" = "aux" ] && ok "role defaults to aux" || bad "role defaults to aux" "$role_seen"

# --- --role validation and export
out=$(bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/role1.md" --cwd "$TMP" --role implementer 2>&1)
[ $? -eq 0 ] && ok "--role implementer accepted" || bad "--role implementer accepted" "$out"
[ "$(cat "$TMP/adapter-role" 2>/dev/null)" = "implementer" ] && ok "implementer role exported" || bad "implementer role exported"
rm -f "$TMP/adapter-args"
bash "$DISPATCH" dispatch pane-echo --prompt-file "$PROMPT" --result-file "$TMP/role2.md" --cwd "$TMP" --role wizard >/dev/null 2>&1
[ $? -eq 64 ] && ok "garbage --role -> usage exit 64" || bad "garbage --role -> usage exit 64"
[ ! -f "$TMP/adapter-args" ] && ok "garbage --role never reaches adapter" || bad "garbage --role never reaches adapter"
```

(d) in the handoff section, after the `htitle` assertion (which is UNCHANGED — handoff's title never had the `pane: ` prefix), add:

```bash
[ "$(cat "$TMP/adapter-role" 2>/dev/null)" = "aux" ] && ok "handoff role is aux" || bad "handoff role is aux"
```

Note the handoff adapter stub (line 108) must also record the role — extend it the same way as (a):

```bash
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/handoff-args"\nprintf "%%s\\n" "${PANE_AGENT_ROLE:-unset}" > "%s/adapter-role"\necho surface:7\n' "$TMP" "$TMP" > "$PANE_ADAPTERS_DIR/cmux.sh"
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: FAIL on "bare agent-type title passed" (still `pane: observability-judge`), "role defaults to aux", "implementer role exported", "garbage --role -> usage exit 64", "handoff role is aux". F1/F4 and the other legacy cases stay green.

- [ ] **Step 3: Implement in the dispatcher**

In `panes/dispatch-pane-agent.sh`:

1. Usage comment (line 4) and the dispatch `die` usage string (line 84): append `[--role implementer|aux]`.
2. Init (line 85): `prompt_file=""; result_file=""; run_cwd="$PWD"; role="aux"`.
3. Arg loop — add before the `*)` arm:

```bash
        --role)        [ $# -ge 2 ] || die "--role needs a value";        role="$2";        shift 2 ;;
```

4. After the loop, next to the agent-type validation (line 94):

```bash
    # Allowlist, fail fast: a garbage role is a caller bug and must die before
    # any adapter call (spec error table).
    case "$role" in implementer|aux) ;; *) die "--role must be implementer or aux (got: $role)" ;; esac
```

5. Replace the dispatch open call (line 143) — bare agent type as the label, role exported only for this call:

```bash
    export PANE_AGENT_ROLE="$role"
    open_pane_or_cooldown "$(sanitize_title "$agent_type")" "$launcher"
```

6. In the handoff branch, before its open call (line 204):

```bash
    export PANE_AGENT_ROLE=aux
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash panes/dispatch-pane-agent.test.sh`
Expected: all ok, `0 failed`.

- [ ] **Step 5: Handoff-wrapper in-pane rename (Assumption 2)**

In `panes/handoff-wrapper.sh`, insert between `IFS= read -r _` and the `exec` line:

```bash
# Layout-v2 (spec assumption 2): this pane was opened under a managed
# "aux:<run-id>" title. Once adopted as the main session that title must stop
# matching the managed grammar, or future aux dispatches would tab onto main's
# pane. Best-effort by design — documented consequence if it fails.
CMUX_BIN="/Applications/cmux.app/Contents/Resources/bin/cmux"
if [ -n "${CMUX_SURFACE_ID:-}" ] && [ -x "$CMUX_BIN" ]; then
  "$CMUX_BIN" rename-tab --surface "$CMUX_SURFACE_ID" -- "main session" >/dev/null 2>&1 || true
fi
```

If probe finding P6 recorded a different `--surface` argument format for `$CMUX_SURFACE_ID`, use the recorded form. No automated test (no wrapper suite exists; cmux-less machines can't exercise it) — verify once live at the end of Task 8.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck panes/dispatch-pane-agent.sh panes/dispatch-pane-agent.test.sh panes/handoff-wrapper.sh
git add panes/dispatch-pane-agent.sh panes/dispatch-pane-agent.test.sh panes/handoff-wrapper.sh coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): --role flag, PANE_AGENT_ROLE export, handoff adoption rename"
```

---

### Task 4: cmux-layout.sh — tree normalization, managed classification, finished check

**Files:**
- Create: `panes/adapters/cmux-layout.sh`
- Test: `panes/adapters/cmux-layout.test.sh` (part 1)

**Interfaces:**
- Consumes: `panes/adapters/fixtures/tree-live.json` (Task 1); `state/runs/<run-id>/agent-exit` (Task 2).
- Produces (for Task 5, exact signatures):
  - `layout_normalize_tree` — stdin: tree JSON → stdout TSV `pane_ref<TAB>surface_ref<TAB>title`, one line per surface, filtered to `$CMUX_WORKSPACE_ID`'s workspace when that var is set and matchable.
  - `layout_managed` — stdin: normalized TSV → stdout TSV `kind(impl|aux)<TAB>slot(1-4|-)<TAB>run_id<TAB>pane_ref<TAB>surface_ref`, managed surfaces only.
  - `layout_run_finished <run_id>` — exit 0 = finished (marker exists OR run dir gone), 1 = running. Honors `PANE_STATE_DIR`.

- [ ] **Step 1: Write the failing tests (harness + part-1 cases)**

Create `panes/adapters/cmux-layout.test.sh`:

```bash
#!/usr/bin/env bash
# cmux-layout.test.sh — Layer-1 pure decision tests: canned tree JSON + a fake
# state dir, zero cmux. Run: bash panes/adapters/cmux-layout.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
mkdir -p "$PANE_STATE_DIR/runs"
unset CMUX_WORKSPACE_ID
# shellcheck source=/dev/null
. "$HERE/cmux-layout.sh"

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s%s\n' "$1" "${2:+ ($2)}"; fail=$((fail+1)); }
eq()  { [ "$2" = "$3" ] && ok "$1" || bad "$1" "want [$3] got [$2]"; }

mkrun()  { mkdir -p "$PANE_STATE_DIR/runs/$1"; }                 # running
mkdone() { mkrun "$1"; printf 'DONE\n' > "$PANE_STATE_DIR/runs/$1/agent-exit"; }

# tree builders — shape mirrors fixtures/tree-live.json (Task 1)
pane() { # $1 pane_ref, $2.. "surface_ref|title" pairs
  local p="$1"; shift; local s out=""
  for s in "$@"; do
    out="$out{\"surface_ref\":\"${s%%|*}\",\"title\":\"${s#*|}\",\"index_in_pane\":0},"
  done
  printf '{"pane_ref":"%s","surfaces":[%s]}' "$p" "${out%,}"
}
tree() { # $1.. pane json blobs
  local IFS=,; printf '[{"workspace_ref":"workspace:1","title":"ws","panes":[%s]}]' "$*"
}

# --- normalize: real fixture from the live probe parses to non-empty TSV
norm_live="$(layout_normalize_tree < "$HERE/fixtures/tree-live.json")"
[ -n "$norm_live" ] && ok "live fixture normalizes to TSV" || bad "live fixture normalizes to TSV"
printf '%s\n' "$norm_live" | awk -F'\t' 'NF!=3{exit 1}' && ok "TSV is 3 fields" || bad "TSV is 3 fields"

# --- normalize: canned shape, field mapping exact
t="$(tree "$(pane pane:1 'surface:10|zsh')" "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 taskA')")"
norm="$(printf '%s' "$t" | layout_normalize_tree)"
eq "normalize maps pane/surface/title" "$(printf '%s\n' "$norm" | sed -n 2p)" \
   "$(printf 'pane:2\tsurface:20\timpl.1:1700000001-1-1 taskA')"

# --- workspace filter: with CMUX_WORKSPACE_ID set, other workspaces drop out
t2='[{"workspace_ref":"workspace:1","panes":[{"pane_ref":"pane:1","surfaces":[{"surface_ref":"surface:10","title":"mine"}]}]},{"workspace_ref":"workspace:2","panes":[{"pane_ref":"pane:9","surfaces":[{"surface_ref":"surface:90","title":"impl.1:1700000001-1-1 other-ws"}]}]}]'
n2="$(printf '%s' "$t2" | CMUX_WORKSPACE_ID=workspace:1 layout_normalize_tree)"
printf '%s\n' "$n2" | grep -q 'other-ws' && bad "workspace filter excludes foreign panes" "$n2" || ok "workspace filter excludes foreign panes"

# --- managed classification
m="$(printf 'pane:2\tsurface:20\timpl.3:1700000001-2-3 taskA\npane:3\tsurface:30\taux:1700000002-4-5 judge\npane:4\tsurface:40\tzsh\npane:5\tsurface:50\timpl.9:1700000001-1-1 badslot\npane:6\tsurface:60\timpl.2:notarunid x\n' | layout_managed)"
eq "impl line parsed" "$(printf '%s\n' "$m" | sed -n 1p)" "$(printf 'impl\t3\t1700000001-2-3\tpane:2\tsurface:20')"
eq "aux line parsed"  "$(printf '%s\n' "$m" | sed -n 2p)" "$(printf 'aux\t-\t1700000002-4-5\tpane:3\tsurface:30')"
eq "unmanaged/malformed excluded" "$(printf '%s\n' "$m" | wc -l | tr -d ' ')" "2"

# --- finished check
mkdone 1700000001-1-1; mkrun 1700000002-1-1
layout_run_finished 1700000001-1-1 && ok "marker => finished" || bad "marker => finished"
layout_run_finished 1700000002-1-1 && bad "no marker => running" || ok "no marker => running"
layout_run_finished 1699999999-9-9 && ok "missing run dir => finished" || bad "missing run dir => finished"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash panes/adapters/cmux-layout.test.sh`
Expected: immediate failure — `cmux-layout.sh: No such file or directory` (the source line).

- [ ] **Step 3: Implement the helper (part 1)**

Create `panes/adapters/cmux-layout.sh`:

```bash
#!/usr/bin/env bash
# cmux-layout.sh — pure layout decision helper, SOURCED by cmux.sh, never
# executed and never calling cmux: every function reads stdin/arguments and
# prints a result, so the whole file unit-tests against canned JSON fixtures
# (spec: Components). Layout state lives in surface titles because the cmux
# tree is flat — titles are the positional memory.
#
# Normalized form (TSV, one surface per line):  pane_ref \t surface_ref \t title
# Managed grammar (anchored; inside the frozen [A-Za-z0-9 ._:-]<=64 allowlist):
#   impl.<slot>:<run-id> <label>   slot 1-4    |   aux:<run-id> <label>

LAYOUT_JQ="${PANE_JQ_BIN:-/usr/bin/jq}"
LAYOUT_MANAGED_RE='^(impl\.([1-4])|aux):([0-9]+-[0-9]+-[0-9]+) '

# stdin: `cmux --json tree` output -> normalized TSV. Recursive descent keeps
# this resilient to wrapper objects; the live-captured fixture test pins it to
# the real 0.64.20 shape. When CMUX_WORKSPACE_ID identifies a workspace object
# in the tree, everything outside it is dropped (spec assumption 1 defence).
layout_normalize_tree() {
  local ws="${CMUX_WORKSPACE_ID:-}"
  case "$ws" in ""|workspace:*) ;; *) ws="workspace:$ws" ;; esac
  "$LAYOUT_JQ" -r --arg ws "$ws" '
    (if $ws != "" and ([.. | objects | select(.workspace_ref? == $ws)] | length) > 0
     then [.. | objects | select(.workspace_ref? == $ws)] else [.] end)
    | [.[] | .. | objects | select(has("pane_ref") and has("surfaces"))] | .[]
    | .pane_ref as $p | .surfaces[]? | select(has("surface_ref") and has("title"))
    | [$p, .surface_ref, .title] | @tsv' 2>/dev/null
}

# stdin: normalized TSV -> managed surfaces only:
#   kind(impl|aux) \t slot(1-4|-) \t run_id \t pane_ref \t surface_ref
# Near-miss titles simply do not match — unmanaged, invisible (spec).
layout_managed() {
  local pane surface title
  while IFS=$'\t' read -r pane surface title; do
    [[ "$title" =~ $LAYOUT_MANAGED_RE ]] || continue
    if [ -n "${BASH_REMATCH[2]}" ]; then
      printf 'impl\t%s\t%s\t%s\t%s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "$pane" "$surface"
    else
      printf 'aux\t-\t%s\t%s\t%s\n' "${BASH_REMATCH[3]}" "$pane" "$surface"
    fi
  done
}

# $1 run_id -> 0 finished, 1 running. Missing run dir = finished (the 7-day
# cleanup removes old dirs; obs-judge success_masking caveat is accepted and
# recorded in the spec).
layout_run_finished() {
  local root="${PANE_STATE_DIR:-$HOME/.claude/panes/state}" dir="$1"
  dir="$root/runs/$1"
  [ -d "$dir" ] || return 0
  [ -f "$dir/agent-exit" ]
}
```

If probe finding P2 recorded a different nesting (Task 1 Step 3 gate), adjust ONLY the jq program in `layout_normalize_tree` — the fixture test decides when it's right.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash panes/adapters/cmux-layout.test.sh`
Expected: all ok, `0 failed`.

- [ ] **Step 5: Falsify**

Temporarily change `LAYOUT_MANAGED_RE` to drop the trailing space (unanchored label boundary) → the "unmanaged/malformed excluded" case must go RED (the `impl.2:notarunid x` near-miss... that one still fails the run-id; instead the falsification input is a title like `impl.1:1700000001-1-1x` — add it to the `layout_managed` input line in the test FIRST, confirm green with the correct regex, then mutate). Revert. Temporarily make `layout_run_finished` return 0 unconditionally → "no marker => running" must go RED. Revert.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x panes/adapters/cmux-layout.sh panes/adapters/cmux-layout.test.sh
git add panes/adapters/cmux-layout.sh panes/adapters/cmux-layout.test.sh coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): cmux-layout pure helper — normalize, classify, finished check"
```

---

### Task 5: cmux-layout.sh — the decision algorithm and title composition

**Files:**
- Modify: `panes/adapters/cmux-layout.sh` (append)
- Test: `panes/adapters/cmux-layout.test.sh` (part 2, append before the summary)

**Interfaces:**
- Consumes: Task 4's three functions, verbatim signatures.
- Produces (for Tasks 6–7):
  - `layout_compose_title <prefix> <run_id> <label>` — prefix `impl.<slot>`|`aux`; empty run_id → the bare label (unmanaged); always truncated to 64 bytes from the right.
  - `layout_decide <role> <run_id> <label>` — tree JSON on stdin → exactly two lines:
    `PLAN: reuse <surface_ref>` | `PLAN: split <right|down> <env|surface_ref>` | `PLAN: tab <pane_ref>` | `PLAN: aux-create <env|surface_ref>`, then `TITLE: <composed title>`. Non-zero exit = derivation failure (Tier-1 for the caller).

- [ ] **Step 1: Write the failing tests**

Append to `panes/adapters/cmux-layout.test.sh` before the summary block (uses the `tree`/`pane`/`mkrun`/`mkdone` builders from Task 4):

```bash
# --- layout_decide: implementer path
decide() { printf '%s' "$1" | layout_decide "$2" "$3" "$4"; }
NEW=1700000099-9-9

t_empty="$(tree "$(pane pane:1 'surface:10|zsh')")"
eq "empty ws -> create slot 1" "$(decide "$t_empty" implementer $NEW lbl)" \
   "$(printf 'PLAN: split right env\nTITLE: impl.1:%s lbl' $NEW)"

# Task 4's finished-check cases marked this run finished — reset it to running
mkrun 1700000001-1-1; rm -f "$PANE_STATE_DIR/runs/1700000001-1-1/agent-exit"
t_s1="$(tree "$(pane pane:1 'surface:10|zsh')" "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 a')")"
eq "slot1 busy -> create slot 2" "$(decide "$t_s1" implementer $NEW lbl)" \
   "$(printf 'PLAN: split down surface:20\nTITLE: impl.2:%s lbl' $NEW)"

mkrun 1700000002-1-1; mkrun 1700000003-1-1
t_s124="$(tree "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 a')" \
               "$(pane pane:3 'surface:30|impl.2:1700000002-1-1 b')" \
               "$(pane pane:5 'surface:50|impl.4:1700000003-1-1 d')")"
eq "lowest missing slot (3) from slot1" "$(decide "$t_s124" implementer $NEW lbl)" \
   "$(printf 'PLAN: split right surface:20\nTITLE: impl.3:%s lbl' $NEW)"

mkdone 1700000002-1-1
eq "finished slot reused before growth (oldest finished)" "$(decide "$t_s124" implementer $NEW lbl)" \
   "$(printf 'PLAN: reuse surface:30\nTITLE: impl.2:%s lbl' $NEW)"
mkrun 1700000002-1-1; rm -f "$PANE_STATE_DIR/runs/1700000002-1-1/agent-exit"

mkrun 1700000004-1-1
t_full="$(tree "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 a' 'surface:21|zsh')" \
              "$(pane pane:3 'surface:30|impl.2:1700000002-1-1 b')" \
              "$(pane pane:4 'surface:40|impl.3:1700000003-1-1 c' 'surface:41|zsh')" \
              "$(pane pane:5 'surface:50|impl.4:1700000004-1-1 d')")"
eq "full busy quadrant -> tab fewest-surfaces, tie lowest slot" \
   "$(decide "$t_full" implementer $NEW lbl)" \
   "$(printf 'PLAN: tab pane:3\nTITLE: impl.2:%s lbl' $NEW)"

# duplicate slot: newest run-id's pane wins; loser is invisible
mkrun 1700000005-1-1
t_dup="$(tree "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 old')" \
             "$(pane pane:6 'surface:60|impl.1:1700000005-1-1 new')")"
eq "duplicate slot -> newest wins as split target" "$(decide "$t_dup" implementer $NEW lbl)" \
   "$(printf 'PLAN: split down surface:60\nTITLE: impl.2:%s lbl' $NEW)"

# --- layout_decide: aux path
t_noaux="$(tree "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 a')" \
               "$(pane pane:4 'surface:40|impl.3:1700000003-1-1 c')")"
eq "no aux pane -> aux-create, fallback slot3" "$(decide "$t_noaux" aux $NEW judgelbl)" \
   "$(printf 'PLAN: aux-create surface:40\nTITLE: aux:%s judgelbl' $NEW)"
eq "no aux, no quadrant -> aux-create env" "$(decide "$t_empty" aux $NEW judgelbl)" \
   "$(printf 'PLAN: aux-create env\nTITLE: aux:%s judgelbl' $NEW)"

mkrun 1700000006-1-1
t_aux="$(tree "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 a')" \
             "$(pane pane:7 'surface:70|aux:1700000006-1-1 judge')")"
eq "busy aux pane -> tab on it" "$(decide "$t_aux" aux $NEW lbl)" \
   "$(printf 'PLAN: tab pane:7\nTITLE: aux:%s lbl' $NEW)"
mkdone 1700000006-1-1
eq "finished aux surface reused (extension, user-approved)" "$(decide "$t_aux" aux $NEW lbl)" \
   "$(printf 'PLAN: reuse surface:70\nTITLE: aux:%s lbl' $NEW)"

# mixed pane: impl wins -> pane is a slot, its aux surface never aux-targets
t_mixed="$(tree "$(pane pane:2 'surface:20|impl.1:1700000001-1-1 a' 'surface:21|aux:1700000006-1-1 j')")"
eq "mixed pane is impl -> aux creates its own column" "$(decide "$t_mixed" aux $NEW lbl)" \
   "$(printf 'PLAN: aux-create env\nTITLE: aux:%s lbl' $NEW)"

# --- titles
eq "empty run_id -> unmanaged bare label" "$(layout_compose_title impl.1 '' plainlabel)" "plainlabel"
long_label="$(printf 'L%.0s' $(seq 1 80))"
composed="$(layout_compose_title impl.2 $NEW "$long_label")"
eq "title truncated to 64" "${#composed}" "64"
case "$composed" in "impl.2:$NEW "*) ok "prefix never truncated" ;; *) bad "prefix never truncated" "$composed" ;; esac
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash panes/adapters/cmux-layout.test.sh`
Expected: every new case FAILs with `layout_decide: command not found`; Task-4 cases stay green.

- [ ] **Step 3: Implement**

Append to `panes/adapters/cmux-layout.sh`:

```bash
# $1 prefix (impl.<slot>|aux), $2 run_id ("" = unmanaged), $3 label.
# Truncates from the RIGHT at 64 so the managed prefix always survives (spec).
layout_compose_title() {
  if [ -n "$2" ]; then printf '%.64s' "$1:$2 $3"; else printf '%.64s' "$3"; fi
}

# $1 role (implementer|aux), $2 run_id (may be ""), $3 label; tree JSON on
# stdin. Prints one PLAN: line and one TITLE: line (contract in the header).
# Reuse is per-SURFACE (any finished impl surface, oldest run-id epoch first) —
# the Gherkin "only slot 2's run-id has a marker" scenario pins this reading.
layout_decide() {
  local role="$1" new_run="$2" label="$3"
  local norm managed kind slot rid pane surface epoch s
  norm="$(layout_normalize_tree)"
  managed="$(printf '%s\n' "$norm" | layout_managed)"

  # Pass A — winning pane per slot (duplicate slot: newest run-id epoch wins;
  # losers are unmanaged from here on and never touched).
  local slot_pane=("" "" "" "" "") slot_max=("" -1 -1 -1 -1) slot_ref=("" "" "" "" "")
  while IFS=$'\t' read -r kind slot rid pane surface; do
    [ "$kind" = impl ] || continue
    epoch="${rid%%-*}"
    if [ "$epoch" -gt "${slot_max[$slot]}" ] 2>/dev/null; then
      slot_max[$slot]="$epoch"; slot_pane[$slot]="$pane"
    fi
  done <<EOF
$managed
EOF

  # Pass B — per-slot target refs and the oldest finished reusable surface.
  local reuse_ref="" reuse_slot="" reuse_epoch=""
  while IFS=$'\t' read -r kind slot rid pane surface; do
    [ "$kind" = impl ] || continue
    [ "$pane" = "${slot_pane[$slot]}" ] || continue
    [ -n "${slot_ref[$slot]}" ] || slot_ref[$slot]="$surface"
    if layout_run_finished "$rid"; then
      epoch="${rid%%-*}"
      if [ -z "$reuse_ref" ] || [ "$epoch" -lt "$reuse_epoch" ]; then
        reuse_ref="$surface"; reuse_slot="$slot"; reuse_epoch="$epoch"
      fi
    fi
  done <<EOF
$managed
EOF

  if [ "$role" = implementer ]; then
    if [ -n "$reuse_ref" ]; then
      printf 'PLAN: reuse %s\n' "$reuse_ref"
      printf 'TITLE: %s\n' "$(layout_compose_title "impl.$reuse_slot" "$new_run" "$label")"
      return 0
    fi
    local missing=""
    for s in 1 2 3 4; do [ -n "${slot_pane[$s]}" ] || { missing="$s"; break; }; done
    if [ -n "$missing" ]; then
      # Split table (spec): deps are well-founded — 2,3 need 1; 4 needs 2; a
      # missing slot 1 is env-implicit from main again, so lowest-missing-first
      # self-heals user-closed slots.
      case "$missing" in
        1) printf 'PLAN: split right env\n' ;;
        2) printf 'PLAN: split down %s\n'  "${slot_ref[1]}" ;;
        3) printf 'PLAN: split right %s\n' "${slot_ref[1]}" ;;
        4) printf 'PLAN: split right %s\n' "${slot_ref[2]}" ;;
      esac
      printf 'TITLE: %s\n' "$(layout_compose_title "impl.$missing" "$new_run" "$label")"
      return 0
    fi
    local best_slot="" best_count=0 count
    for s in 1 2 3 4; do
      count="$(printf '%s\n' "$norm" | awk -F'\t' -v p="${slot_pane[$s]}" '$1==p' | grep -c . )"
      if [ -z "$best_slot" ] || [ "$count" -lt "$best_count" ]; then best_slot="$s"; best_count="$count"; fi
    done
    printf 'PLAN: tab %s\n' "${slot_pane[$best_slot]}"
    printf 'TITLE: %s\n' "$(layout_compose_title "impl.$best_slot" "$new_run" "$label")"
    return 0
  fi

  # aux path. Aux pane = pane with >=1 aux surface and NO impl surface (impl
  # wins mixed panes); among several, the one holding the newest aux run-id.
  local aux_pane="" aux_newest=-1 aux_reuse_ref="" aux_reuse_epoch=""
  while IFS=$'\t' read -r kind slot rid pane surface; do
    [ "$kind" = aux ] || continue
    printf '%s\n' "$managed" | awk -F'\t' -v p="$pane" '$1=="impl" && $4==p {found=1} END {exit found}' || continue
    epoch="${rid%%-*}"
    if [ "$epoch" -gt "$aux_newest" ] 2>/dev/null; then aux_newest="$epoch"; aux_pane="$pane"; fi
  done <<EOF
$managed
EOF
  if [ -n "$aux_pane" ]; then
    while IFS=$'\t' read -r kind slot rid pane surface; do
      [ "$kind" = aux ] || continue
      [ "$pane" = "$aux_pane" ] || continue
      if layout_run_finished "$rid"; then
        epoch="${rid%%-*}"
        if [ -z "$aux_reuse_ref" ] || [ "$epoch" -lt "$aux_reuse_epoch" ]; then
          aux_reuse_ref="$surface"; aux_reuse_epoch="$epoch"
        fi
      fi
    done <<EOF
$managed
EOF
    if [ -n "$aux_reuse_ref" ]; then printf 'PLAN: reuse %s\n' "$aux_reuse_ref"
    else printf 'PLAN: tab %s\n' "$aux_pane"; fi
  else
    local fb="env"
    if [ -n "${slot_ref[3]}" ]; then fb="${slot_ref[3]}"
    elif [ -n "${slot_ref[4]}" ]; then fb="${slot_ref[4]}"; fi
    printf 'PLAN: aux-create %s\n' "$fb"
  fi
  printf 'TITLE: %s\n' "$(layout_compose_title aux "$new_run" "$label")"
}
```

Note the awk membership check uses `END {exit found}` so "pane HAS an impl surface" exits non-zero → `|| continue` skips it — an aux surface sharing a pane with impl surfaces never nominates that pane as the aux pane.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash panes/adapters/cmux-layout.test.sh`
Expected: all ok, `0 failed`. If the tab tie-break case fails on the surface count, check `grep -c .` (counts non-empty lines; `wc -l` miscounts when awk emits nothing).

- [ ] **Step 5: Falsify**

Mutate: (a) reuse pick `-lt` → `-gt` (newest instead of oldest) → "finished slot reused (oldest finished)" stays green only if the fixture has ONE finished surface — first add a second finished surface (`mkdone 1700000003-1-1`, expect reuse of `surface:30`, the older epoch... note both share epoch `1700000002` vs `1700000003` — surface:30's run 1700000002-1-1 is older) and confirm the case now distinguishes; then the mutation must go RED. Revert. (b) Swap the slot-3/slot-4 split-table targets → "lowest missing slot (3) from slot1" must go RED. Revert.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x panes/adapters/cmux-layout.sh panes/adapters/cmux-layout.test.sh
git add panes/adapters/cmux-layout.sh panes/adapters/cmux-layout.test.sh coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): cmux-layout decision algorithm + title composition"
```

---

### Task 6: cmux.sh — Tier-1 degradation shell, legacy floor, derive-then-print dryrun

The adapter is rewritten in two tasks. This one lands the frame: env overrides, role mapping, run-id extraction, `derive_plan` (all Tier-1 checks), the legacy floor, and the new dryrun — with plan EXECUTION still falling to legacy (Task 7 adds it). After this task the adapter behaves exactly like v1 whenever layout can't be derived, and `adapters.test.sh` must stay green untouched.

**Files:**
- Rewrite: `panes/adapters/cmux.sh`
- Create: `panes/adapters/cmux-exec.test.sh` (harness + degradation cases)

**Interfaces:**
- Consumes: `layout_decide`/`layout_compose_title` (Task 5), `PANE_AGENT_ROLE` (Task 3).
- Produces (for Task 7): `derive_plan` (stdout `PLAN:`+`TITLE:` lines, non-zero = degrade), `legacy_open` (v1 behavior verbatim, exit 1 on failure = Tier 2), `finish_surface <ref> <title>` (send launcher — exit 1 on failure — then best-effort rename, then print ref). `$CMUX_BIN`, `$JQ_BIN`, `$role`, `$run_id`, `$title`, `$launcher` globals.

- [ ] **Step 1: Write the failing tests (fake cmux + degradation matrix)**

Create `panes/adapters/cmux-exec.test.sh`:

```bash
#!/usr/bin/env bash
# cmux-exec.test.sh — Layer-2 adapter tests against a fake cmux binary that
# logs argv and replays scripted per-subcommand responses. Asserts CALL
# SEQUENCES and the two-tier degradation matrix. Run: bash panes/adapters/cmux-exec.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PANE_STATE_DIR="$TMP/state"
RUN_ID="1700000010-1-1"
RUN_DIR="$PANE_STATE_DIR/runs/$RUN_ID"
mkdir -p "$RUN_DIR"
LAUNCHER="$RUN_DIR/launch.sh"
printf '#!/usr/bin/env bash\necho hi\n' > "$LAUNCHER"; chmod 700 "$LAUNCHER"
export PANE_CMUX_BIN="$TMP/fake-cmux"
export FAKE_DIR="$TMP/fake"; export FAKE_LOG="$TMP/fake.log"
mkdir -p "$FAKE_DIR"
unset CMUX_WORKSPACE_ID

# the fake: first non-flag arg = subcommand; response file $FAKE_DIR/<sub>,
# exit code file $FAKE_DIR/<sub>.rc (default 0). --json is a flag, skip it.
cat > "$PANE_CMUX_BIN" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
sub=""
for a in "$@"; do case "$a" in --json) ;; *) sub="$a"; break ;; esac; done
[ -f "$FAKE_DIR/$sub" ] && cat "$FAKE_DIR/$sub"
rc=0; [ -f "$FAKE_DIR/$sub.rc" ] && rc="$(cat "$FAKE_DIR/$sub.rc")"
exit "$rc"
FAKE
chmod 700 "$PANE_CMUX_BIN"

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$1"; pass=$((pass+1)); }
bad() { printf 'FAIL — %s%s\n' "$1" "${2:+ ($2)}"; fail=$((fail+1)); }
reset_fake() { rm -rf "$FAKE_DIR" "$FAKE_LOG"; mkdir -p "$FAKE_DIR"; }
adapter() { # $1 role; runs the adapter, captures out/err/rc
  OUT="$(PANE_AGENT_ROLE="$1" bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>"$TMP/err")"
  RC=$?; ERR="$(cat "$TMP/err")"
}
set_tree() { printf '%s' "$1" > "$FAKE_DIR/tree"; }
T_EMPTY='[{"workspace_ref":"workspace:1","panes":[{"pane_ref":"pane:1","surfaces":[{"surface_ref":"surface:10","title":"zsh"}]}]}]'

# --- Tier 1: tree call fails -> legacy + breadcrumb + exit 0
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"
printf 'OK surface:42 workspace:1\n' > "$FAKE_DIR/new-split"
adapter implementer
[ "$RC" -eq 0 ] && ok "tree failure -> exit 0" || bad "tree failure -> exit 0" "rc=$RC $ERR"
grep -q '^new-split down$' "$FAKE_LOG" && ok "tree failure -> legacy new-split down" || bad "tree failure -> legacy new-split down" "$(cat "$FAKE_LOG")"
printf '%s' "$ERR" | grep -q 'cmux-layout: degraded' && ok "breadcrumb on stderr" || bad "breadcrumb on stderr" "$ERR"

# --- Tier 1: unparseable tree -> legacy
reset_fake; printf 'not json' > "$FAKE_DIR/tree"
printf 'OK surface:42 workspace:1\n' > "$FAKE_DIR/new-split"
adapter implementer
[ "$RC" -eq 0 ] && grep -q '^new-split down$' "$FAKE_LOG" && ok "garbage tree -> legacy" || bad "garbage tree -> legacy" "rc=$RC"

# --- Tier 1: jq missing -> legacy
reset_fake; set_tree "$T_EMPTY"
printf 'OK surface:42 workspace:1\n' > "$FAKE_DIR/new-split"
OUT="$(PANE_AGENT_ROLE=implementer PANE_JQ_BIN=/nonexistent bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>"$TMP/err")"
RC=$?
[ "$RC" -eq 0 ] && grep -q '^new-split down$' "$FAKE_LOG" && ok "jq missing -> legacy" || bad "jq missing -> legacy" "rc=$RC"

# --- Tier 2: legacy split itself fails -> exit nonzero (dispatcher cooldown)
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"; printf '1' > "$FAKE_DIR/new-split.rc"
adapter implementer
[ "$RC" -ne 0 ] && ok "legacy split failure -> nonzero (Tier 2)" || bad "legacy split failure -> nonzero (Tier 2)"

# --- Tier 2: send fails post-creation -> exit nonzero
reset_fake; printf '1' > "$FAKE_DIR/tree.rc"
printf 'OK surface:42 workspace:1\n' > "$FAKE_DIR/new-split"; printf '1' > "$FAKE_DIR/send.rc"
adapter implementer
[ "$RC" -ne 0 ] && ok "send failure -> nonzero (Tier 2)" || bad "send failure -> nonzero (Tier 2)"

# --- dryrun without PANE_CMUX_BIN prints the legacy plan (Layer-3 compat)
OUT="$(env -u PANE_CMUX_BIN PANE_DRYRUN=1 PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'new-split down' && ok "dryrun sans fake -> legacy plan" || bad "dryrun sans fake -> legacy plan" "$OUT"

# --- dryrun WITH the fake derives and prints the plan
reset_fake; set_tree "$T_EMPTY"
OUT="$(PANE_DRYRUN=1 PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$LAUNCHER" 2>&1)"
printf '%s' "$OUT" | grep -q 'DRYRUN: PLAN: split right env' && ok "dryrun derives plan" || bad "dryrun derives plan" "$OUT"
printf '%s' "$OUT" | grep -q "DRYRUN: TITLE: impl.1:$RUN_ID lbl" && ok "dryrun composes title" || bad "dryrun composes title" "$OUT"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash panes/adapters/cmux-exec.test.sh`
Expected: FAILs across the board (v1 cmux.sh ignores `PANE_CMUX_BIN` — it calls the real app path — and knows no derive/dryrun-plan output).

- [ ] **Step 3: Rewrite cmux.sh (frame)**

Replace `panes/adapters/cmux.sh` with:

```bash
#!/usr/bin/env bash
# cmux adapter — open_pane <title> <launcher-path>; prints the new surface ref.
#
# v2 (pane-layout): derives a structured layout (main | 2x2 implementer
# quadrant | far-right aux column) live from `cmux --json tree` plus the title
# convention in cmux-layout.sh. Layout smarts only ever fail INTO the legacy
# `new-split down` path (Tier 1: one stderr breadcrumb, exit 0, never a
# cooldown); only the legacy path itself failing exits non-zero (Tier 2 ->
# dispatcher cooldown), exactly v1's semantics. PANE_CMUX_BIN/PANE_JQ_BIN are
# test-only overrides (precedent: PANE_CLAUDE_BIN — controlling the environment
# already means controlling the process).
set -u
CMUX_BIN="${PANE_CMUX_BIN:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
JQ_BIN="${PANE_JQ_BIN:-/usr/bin/jq}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/common.sh"
# shellcheck source=/dev/null
. "$HERE/cmux-layout.sh"

[ "${1:-}" = "open_pane" ] || { printf 'usage: cmux.sh open_pane <title> <launcher>\n' >&2; exit 64; }
title="${2:-}"; launcher="${3:-}"
validate_open_pane_args "$title" "$launcher" || exit 65

degraded() { printf 'cmux-layout: degraded (%s)\n' "$1" >&2; }

# Role from the dispatcher; absent/unknown -> aux with a note (spec error
# table). The raw env value never reaches a command line or title.
role="${PANE_AGENT_ROLE:-}"
case "$role" in
  implementer|aux) ;;
  "") role=aux ;;
  *) printf 'cmux: unknown PANE_AGENT_ROLE -> aux\n' >&2; role=aux ;;
esac

# run-id from the already-validated launcher path .../runs/<run-id>/launch.sh;
# extraction failure -> unprefixed (unmanaged) title, dispatch proceeds.
run_id="$(basename "$(dirname "$launcher")")"
if ! [[ "$run_id" =~ ^[0-9]+-[0-9]+-[0-9]+$ ]]; then
  printf 'cmux: no run-id in launcher path; surface will be unmanaged\n' >&2
  run_id=""
fi

derive_plan() { # stdout: PLAN:+TITLE: lines; non-zero = Tier-1 degrade
  [ -x "$JQ_BIN" ] || { degraded "jq missing"; return 1; }
  local tree out
  tree="$("$CMUX_BIN" --json tree </dev/null 2>/dev/null)" || { degraded "tree call failed"; return 1; }
  printf '%s' "$tree" | "$JQ_BIN" -e . >/dev/null 2>&1 || { degraded "tree unparseable"; return 1; }
  out="$(printf '%s' "$tree" | layout_decide "$role" "$run_id" "$title")" || { degraded "derivation failed"; return 1; }
  printf '%s\n' "$out" | grep -q '^PLAN: ' || { degraded "derivation nonsense"; return 1; }
  printf '%s\n' "$out"
}

finish_surface() { # $1 surface ref, $2 title — send launcher, stamp, print ref
  "$CMUX_BIN" send --surface "$1" -- "bash $launcher\n" >/dev/null \
    || { printf 'cmux: send failed for %s\n' "$1" >&2; exit 1; }
  # The managed title is load-bearing; if the stamp fails the surface is just
  # unmanaged (extra splits later at worst) — note it, never die for it.
  "$CMUX_BIN" rename-tab --surface "$1" -- "$2" >/dev/null 2>&1 \
    || printf 'cmux: rename failed; surface stays unmanaged\n' >&2
  printf '%s\n' "$1"
}

legacy_open() { # v1 behavior verbatim — the degradation floor (Tier 2 inside)
  local out ref
  out=$("$CMUX_BIN" new-split down </dev/null 2>&1) || { printf 'cmux: new-split failed: %s\n' "$out" >&2; exit 1; }
  ref=$(printf '%s' "$out" | awk '$1=="OK"{print $2}')
  case "$ref" in
    surface:*) ;;
    *) printf 'cmux: unexpected new-split output: %s\n' "$out" >&2; exit 1 ;;
  esac
  finish_surface "$ref" "$title"
}

if [ "${PANE_DRYRUN:-}" = "1" ]; then
  # Derivation is read-only, so dryrun derives when it can (a fake cmux via
  # PANE_CMUX_BIN, or the real app) and prints the plan; otherwise it prints
  # the legacy plan so cmux-less machines keep their existing assertions.
  if [ -n "${PANE_CMUX_BIN:-}" ] && plan_out="$(derive_plan 2>/dev/null)"; then
    printf '%s\n' "$plan_out" | sed 's/^/DRYRUN: /'
    printf 'DRYRUN: %s send --surface <ref> -- "bash %s\\n"\n' "$CMUX_BIN" "$launcher"
  else
    printf 'DRYRUN: %s new-split down\n' "$CMUX_BIN"
    printf 'DRYRUN: %s send --surface <ref> -- "bash %s\\n"\n' "$CMUX_BIN" "$launcher"
    printf 'DRYRUN: %s rename-tab --surface <ref> -- "%s"\n' "$CMUX_BIN" "$title"
  fi
  exit 0
fi

# Task 7 replaces this stanza with plan execution + TOCTOU retry. Until then:
# derive (so Tier-1 breadcrumbs are real) and always take the legacy floor.
derive_plan >/dev/null || true
legacy_open
```

- [ ] **Step 4: Run the suites**

Run: `bash panes/adapters/cmux-exec.test.sh`
Expected: every degradation and dryrun case ok EXCEPT none — all listed cases pass (execution cases arrive in Task 7). Run: `bash panes/adapters.test.sh`
Expected: `24 passed, 0 failed` — UNCHANGED file, still green (the dryrun legacy branch preserves its assertions).

- [ ] **Step 5: Falsify the Tier boundary**

Mutate `derive_plan`'s jq-missing branch to `exit 1` instead of `return 1` → "jq missing -> legacy" must go RED (adapter died instead of degrading). Revert. Mutate `legacy_open` to swallow the new-split failure (`|| true`) → "legacy split failure -> nonzero (Tier 2)" must go RED. Revert.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x panes/adapters/cmux.sh panes/adapters/cmux-exec.test.sh
git add panes/adapters/cmux.sh panes/adapters/cmux-exec.test.sh coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): cmux adapter v2 frame — tiered degradation + derive-then-print dryrun"
```

---

### Task 7: cmux.sh — plan execution with TOCTOU retry

**Files:**
- Modify: `panes/adapters/cmux.sh` (replace the Task-6 closing stanza)
- Test: `panes/adapters/cmux-exec.test.sh` (append execution cases before the summary)

**Interfaces:**
- Consumes: Task 6's `derive_plan`/`finish_surface`/`legacy_open` and Task 5's plan verbs, verbatim.
- Produces: the complete adapter. Output contract unchanged: surface ref on stdout, exit 0 (managed or Tier-1 legacy) / non-zero (Tier 2).

- [ ] **Step 1: Write the failing tests**

Append to `panes/adapters/cmux-exec.test.sh` before the summary (uses `reset_fake`/`adapter`/`set_tree`):

```bash
JSON_SPLIT='{"pane_ref":"pane:30","surface_ref":"surface:51","type":"terminal","window_ref":"window:1","workspace_ref":"workspace:1"}'
T_S1BUSY='[{"workspace_ref":"workspace:1","panes":[{"pane_ref":"pane:2","surfaces":[{"surface_ref":"surface:20","title":"impl.1:1700000011-1-1 a"}]}]}]'
T_S1DONE="$T_S1BUSY"

# --- CREATE: slot1 busy -> targeted split down + send + managed rename
mkdir -p "$PANE_STATE_DIR/runs/1700000011-1-1"   # running
reset_fake; set_tree "$T_S1BUSY"; printf '%s\n' "$JSON_SPLIT" > "$FAKE_DIR/new-split"
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:51" ] && ok "create prints json-captured ref" || bad "create prints json-captured ref" "rc=$RC out=$OUT"
grep -q -- '--json new-split down --surface surface:20' "$FAKE_LOG" && ok "slot2 split targets slot1 surface" || bad "slot2 split targets slot1 surface" "$(cat "$FAKE_LOG")"
grep -q "rename-tab --surface surface:51 -- impl.2:$RUN_ID lbl" "$FAKE_LOG" && ok "rename carries managed prefix" || bad "rename carries managed prefix" "$(cat "$FAKE_LOG")"
grep -q "send --surface surface:51" "$FAKE_LOG" && ok "send targets new surface" || bad "send targets new surface" "$(cat "$FAKE_LOG")"

# --- REUSE: finished slot -> respawn-pane, no new pane, no send
printf 'DONE\n' > "$PANE_STATE_DIR/runs/1700000011-1-1/agent-exit"
reset_fake; set_tree "$T_S1DONE"
adapter implementer
[ "$RC" -eq 0 ] && [ "$OUT" = "surface:20" ] && ok "reuse prints reused ref" || bad "reuse prints reused ref" "rc=$RC out=$OUT"
grep -q -- "respawn-pane --surface surface:20 --command bash $LAUNCHER" "$FAKE_LOG" && ok "reuse respawns with launcher" || bad "reuse respawns with launcher" "$(cat "$FAKE_LOG")"
grep -q '^new-split' "$FAKE_LOG" && bad "reuse never splits" "$(cat "$FAKE_LOG")" || ok "reuse never splits"
grep -q '^send' "$FAKE_LOG" && bad "reuse never sends (respawn carries the command)" || ok "reuse never sends (respawn carries the command)"

# --- TAB: full busy quadrant -> new-surface --pane
rm -f "$PANE_STATE_DIR/runs/1700000011-1-1/agent-exit"
for r in 1700000012-1-1 1700000013-1-1 1700000014-1-1; do mkdir -p "$PANE_STATE_DIR/runs/$r"; done
T_FULL='[{"workspace_ref":"workspace:1","panes":[{"pane_ref":"pane:2","surfaces":[{"surface_ref":"surface:20","title":"impl.1:1700000011-1-1 a"}]},{"pane_ref":"pane:3","surfaces":[{"surface_ref":"surface:30","title":"impl.2:1700000012-1-1 b"}]},{"pane_ref":"pane:4","surfaces":[{"surface_ref":"surface:40","title":"impl.3:1700000013-1-1 c"}]},{"pane_ref":"pane:5","surfaces":[{"surface_ref":"surface:50","title":"impl.4:1700000014-1-1 d"}]}]}]'
reset_fake; set_tree "$T_FULL"; printf '%s\n' "$JSON_SPLIT" > "$FAKE_DIR/new-surface"
adapter implementer
grep -q -- '--json new-surface --pane pane:2' "$FAKE_LOG" && ok "overflow tabs fewest-surfaces slot" || bad "overflow tabs fewest-surfaces slot" "$(cat "$FAKE_LOG")"

# --- AUX create: new-pane attempted, fallback split on its failure
reset_fake; set_tree "$T_FULL"
printf '1' > "$FAKE_DIR/new-pane.rc"; printf '%s\n' "$JSON_SPLIT" > "$FAKE_DIR/new-split"
adapter aux
grep -q -- '--json new-pane --direction right' "$FAKE_LOG" && ok "aux tries new-pane right" || bad "aux tries new-pane right" "$(cat "$FAKE_LOG")"
grep -q -- '--json new-split right --surface surface:40' "$FAKE_LOG" && ok "aux falls back to split right of slot3" || bad "aux falls back to split right of slot3" "$(cat "$FAKE_LOG")"
grep -q "rename-tab --surface surface:51 -- aux:$RUN_ID lbl" "$FAKE_LOG" && ok "aux rename carries aux prefix" || bad "aux rename carries aux prefix" "$(cat "$FAKE_LOG")"

# --- TOCTOU: respawn fails once -> re-derive (tree read twice) -> legacy
printf 'DONE\n' > "$PANE_STATE_DIR/runs/1700000011-1-1/agent-exit"
reset_fake; set_tree "$T_S1DONE"; printf '1' > "$FAKE_DIR/respawn-pane.rc"
printf 'OK surface:42 workspace:1\n' > "$FAKE_DIR/new-split"
adapter implementer
[ "$RC" -eq 0 ] && ok "TOCTOU path stays exit 0" || bad "TOCTOU path stays exit 0" "rc=$RC"
[ "$(grep -c '^--json tree' "$FAKE_LOG")" = "2" ] && ok "one re-derive, not a loop" || bad "one re-derive, not a loop" "$(grep -c '^--json tree' "$FAKE_LOG")"
grep -q '^new-split down$' "$FAKE_LOG" && ok "TOCTOU falls to legacy" || bad "TOCTOU falls to legacy" "$(cat "$FAKE_LOG")"
rm -f "$PANE_STATE_DIR/runs/1700000011-1-1/agent-exit"

# --- non-run-id launcher -> unmanaged bare title on the rename
ODD="$PANE_STATE_DIR/runs/oddname"; mkdir -p "$ODD"
printf '#!/usr/bin/env bash\necho hi\n' > "$ODD/launch.sh"; chmod 700 "$ODD/launch.sh"
reset_fake; set_tree "$T_S1BUSY"; printf '%s\n' "$JSON_SPLIT" > "$FAKE_DIR/new-split"
OUT="$(PANE_AGENT_ROLE=implementer bash "$HERE/cmux.sh" open_pane "lbl" "$ODD/launch.sh" 2>"$TMP/err")"
grep -q 'rename-tab --surface surface:51 -- lbl' "$FAKE_LOG" && ok "no run-id -> bare unmanaged title" || bad "no run-id -> bare unmanaged title" "$(cat "$FAKE_LOG")"
```

- [ ] **Step 2: Run to verify the new cases fail**

Run: `bash panes/adapters/cmux-exec.test.sh`
Expected: Task-6 cases green; every new execution case FAILs (the frame always takes `legacy_open`).

- [ ] **Step 3: Implement plan execution**

In `panes/adapters/cmux.sh`, replace the closing Task-6 stanza (`derive_plan >/dev/null || true` + `legacy_open`) with:

```bash
json_ref() { "$JQ_BIN" -er '.surface_ref' 2>/dev/null; }   # stdin: --json output

split_capture() { # $1.. new-split/new-pane args -> prints captured surface ref
  local out ref
  out="$("$CMUX_BIN" --json "$@" </dev/null 2>/dev/null)" || return 1
  ref="$(printf '%s' "$out" | json_ref)" || return 1
  printf '%s\n' "$ref"
}

execute_plan() { # $1 "PLAN: ..." line, $2 composed title. rc 1 = retryable
  local verb rest ref dir target
  verb="$(printf '%s' "$1" | awk '{print $2}')"
  rest="$(printf '%s' "$1" | cut -d' ' -f3-)"
  case "$verb" in
    reuse)
      # respawn relaunches the command in place — no send. Quoting semantics
      # pinned by live probe P4 before this shipped.
      "$CMUX_BIN" respawn-pane --surface "$rest" --command "bash $launcher" >/dev/null 2>&1 || return 1
      "$CMUX_BIN" rename-tab --surface "$rest" -- "$2" >/dev/null 2>&1 \
        || printf 'cmux: rename failed; surface stays unmanaged\n' >&2
      printf '%s\n' "$rest"
      ;;
    split)
      dir="${rest%% *}"; target="${rest#* }"
      if [ "$target" = env ]; then ref="$(split_capture new-split "$dir")" || return 1
      else ref="$(split_capture new-split "$dir" --surface "$target")" || return 1; fi
      finish_surface "$ref" "$2"
      ;;
    tab)
      ref="$(split_capture new-surface --pane "$rest")" || return 1
      finish_surface "$ref" "$2"
      ;;
    aux-create)
      # Primary: full-height right column (assumption 4); fallback: split right
      # of a right-column slot (imperfect geometry, functional); last: env.
      if ref="$(split_capture new-pane --direction right)"; then :
      elif [ "$rest" = env ]; then ref="$(split_capture new-split right)" || return 1
      else ref="$(split_capture new-split right --surface "$rest")" || return 1; fi
      finish_surface "$ref" "$2"
      ;;
    *) return 1 ;;
  esac
}

# Derive -> execute; a vanished target (TOCTOU) earns exactly one fresh
# derivation, then the legacy floor. Tier-2 failures inside finish_surface/
# legacy_open exit 1 directly — they are not retried (spec error table).
attempt=1
while :; do
  if ! plan_out="$(derive_plan)"; then legacy_open; exit 0; fi
  plan_line="$(printf '%s\n' "$plan_out" | grep '^PLAN: ' | head -n 1)"
  composed="$(printf '%s\n' "$plan_out" | sed -n 's/^TITLE: //p' | head -n 1)"
  [ -n "$composed" ] || composed="$title"
  if execute_plan "$plan_line" "$composed"; then exit 0; fi
  if [ "$attempt" -eq 1 ]; then
    attempt=2
    degraded "plan target vanished; re-deriving once"
    continue
  fi
  degraded "execution failed twice"
  legacy_open
  exit 0
done
```

- [ ] **Step 4: Run all suites**

Run: `bash panes/adapters/cmux-exec.test.sh && bash panes/adapters/cmux-layout.test.sh && bash panes/adapters.test.sh`
Expected: all `0 failed`.

- [ ] **Step 5: Falsify the retry bound**

Mutate the `attempt` guard to always `continue` (unbounded retry) → the "one re-derive, not a loop" case must go RED (tree read count explodes / test hangs — if it hangs, that IS the red; kill it). Revert. Mutate `execute_plan`'s reuse arm to `finish_surface` after respawn (adding a send) → "reuse never sends" must go RED. Revert.

- [ ] **Step 6: Shellcheck + commit**

```bash
shellcheck -x panes/adapters/cmux.sh panes/adapters/cmux-exec.test.sh
git add panes/adapters/cmux.sh panes/adapters/cmux-exec.test.sh coding-memory/branches/pane-layout-v2.md
git commit -m "feat(panes): cmux adapter executes layout plans with bounded TOCTOU retry"
```

---

### Task 8: skill doc, full-suite sweep, live smoke check, branch log close-out

**Files:**
- Modify: `skills/dispatching-pane-agents/SKILL.md` (Procedure section, the step-2 dispatch line)
- Modify: `coding-memory/branches/pane-layout-v2.md`

**Interfaces:**
- Consumes: everything prior.
- Produces: the shippable branch (PR follows AFTER the implementation-stage observability judge, per the judge-guard hook).

- [ ] **Step 1: Document --role in the skill**

In `skills/dispatching-pane-agents/SKILL.md`, after the Procedure step-2 line (`"$HOME"/.claude/panes/dispatch-pane-agent.sh dispatch <agent-type> --prompt-file <f> --cwd <repo-the-agent-works-in>`), add:

```markdown
   Add `--role implementer` ONLY for plan-task implementers and their
   reviewers during plan execution — they fill the 2x2 quadrant. Judges,
   handoff, and every other agent take the default (`aux`, the far-right
   column); the flag exists so the cmux layout can tell the two apart and
   is ignored by every other terminal.
```

- [ ] **Step 2: Full suite + shellcheck sweep**

Run:

```bash
bash panes/adapters.test.sh && \
bash panes/adapters/cmux-layout.test.sh && \
bash panes/adapters/cmux-exec.test.sh && \
bash panes/dispatch-pane-agent.test.sh && \
bash panes/run-pane-agent.test.sh && \
shellcheck -x panes/dispatch-pane-agent.sh panes/run-pane-agent.sh panes/handoff-wrapper.sh \
  panes/cmux-layout-probe.sh panes/adapters/cmux.sh panes/adapters/cmux-layout.sh \
  panes/adapters/cmux-layout.test.sh panes/adapters/cmux-exec.test.sh
```

Expected: every suite `0 failed`; shellcheck silent.

- [ ] **Step 3: One manual live smoke check (NOT automated)**

From a cmux pane in the main workspace: dispatch two `--role implementer` pane-echo agents and one default-role agent; visually confirm — slot 1 appears right of main, slot 2 stacks below it, the aux column lands far-right; after the implementers finish (result written), a third implementer dispatch REUSES a quadrant surface instead of splitting. Record the observation (including assumption-3 behavior if a `restore-session` happens naturally — observational only) in the branch log.

- [ ] **Step 4: Close out the branch log + commit**

Append to `coding-memory/branches/pane-layout-v2.md`: suites' final counts, the smoke-check observation, any probe-driven deviations from the spec's assumed shapes (there must be none the log doesn't explain).

```bash
git add skills/dispatching-pane-agents/SKILL.md coding-memory/branches/pane-layout-v2.md
git commit -m "docs(panes): document --role in dispatching-pane-agents; branch log close-out"
```

- [ ] **Step 5: Hand back for the implementation-stage judge**

Do NOT open a PR from this plan — the observability judge (implementation stage) runs first per `running-the-observability-judge`, and `hooks/judge-guard.sh` blocks `gh pr create` until its verdict matches HEAD.

---

## Self-Review (performed at plan-writing time)

- **Spec coverage:** requirements 1–5 → Tasks 4–7 (layout) + Gherkin scenarios mapped: slot-1 build (T5 empty-ws case), reuse-before-growth (T5+T7), overflow tab (T5 full-quadrant + T7), judge→aux (T5 aux cases), Tier-1 degrade (T6), fail_early preservation (T2), garbage `--role` fail-fast (T3), unmanaged invisibility (T4 classification + T5 duplicate-slot). Aux-reuse extension (T5), handoff rename (T3), marker (T2), probe checklist (T1), doc touch (T8). The 6-pane cap is emergent — no counting code anywhere, by design.
- **Known deliberate readings:** reuse is per-surface finished (Gherkin-pinned), not slot-level; "fewest surfaces" counts ALL surfaces on the slot's pane.
- **Type consistency:** plan verbs (`reuse`/`split`/`tab`/`aux-create`), TSV field orders, and function names are identical across Tasks 4→7; `layout_decide` argument order (role, run_id, label) matches every call site.
- **Placeholder scan:** none; the only intentionally probe-dependent lines (normalize jq, P6 surface-id format) carry explicit Task-1 gates instead of TBDs.
