# Observability Judge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dev-time observability judge — a subagent that scores each change against the evaluation and observability-governance rubrics, relays a junior-dev summary before a PR, and persists verdicts for calibration — enforced by a hook that blocks `gh pr create` until a fresh verdict exists for HEAD.

**Architecture:** A stateless subagent (`agents/observability-judge.md`) does the scoring and writes verdicts to `coding-memory/observability-judge/` (JSONL + markdown). A skill (`running-the-observability-judge`) tells the main agent when to invoke it and how to relay the result; a gate stub makes that un-skippable. A Tier-1 PreToolUse hook (`hooks/judge-guard.sh`) enforces it by blocking `gh pr create` unless a fresh implementation-stage verdict matches the current repo+branch+HEAD.

**Tech Stack:** Bash + `python3` (JSON parsing) for the hook, matching `git-guard.sh`/`doc-guard.sh`; markdown-with-frontmatter for the agent and skill; `git`/`gh` CLI. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-16-observability-judge-design.md`

## Global Constraints

- **Branch:** all work on `feature/observability-judge`. Never commit to `main`.
- **Hook exit-code contract:** exit `0` = allow (silent), exit `2` = block with reason on stderr. Nothing else.
- **Hook portability rules (from `git-guard.sh`/`doc-guard.sh`):** parse the payload with `python3` (never `sed`); read the command from `tool_input.command`; strip leading whitespace then a leading `rtk ` prefix; keep every regex in a variable, never inline in `[[ ]]`.
- **Fail closed:** `judge-guard.sh` protects against shipping un-judged code, so any inability to verify (no `python3`, not a git repo, unreadable/missing verdicts file, indeterminate repo/branch/HEAD) **blocks** (exit 2) — unlike the fail-open `doc-guard.sh`.
- **Strict freshness:** a verdict counts only if `stage == "implementation"` AND `repo`, `branch`, and the **full** `head_sha` all match the current checkout.
- **Judge honesty:** the judge evaluates the development trajectory of a change, never a live production trace. It must never fabricate a test result; if it cannot run tests, it records an execution concern and says so.
- **Judge write scope:** the agent writes only under `coding-memory/observability-judge/`.
- **doc-guard compliance:** each task whose commit stages substantial source (≥3 files or ≥20 changed lines and no doc) also stages a one-line progress note in `CODING_MEMORY.md`. This satisfies `doc-guard.sh` honestly and is required memory-keeping — do not use `Doc-Exempt:` for these non-trivial commits.
- **Storage keys:** `repo` = `basename` of `git rev-parse --show-toplevel`; `head_sha` = full `git rev-parse HEAD`; `ts` = `date -u +%Y-%m-%dT%H:%M:%SZ`.

---

### Task 1: Documentation foundation — ADR + storage schema

Creates the decision record and the storage contract that Tasks 2 and 3 both depend on. Docs-only, so it commits cleanly past `doc-guard`.

**Files:**
- Create: `docs/decisions/0001-observability-judge.md`
- Create: `coding-memory/observability-judge/README.md`

- [ ] **Step 1: Write the ADR**

Create `docs/decisions/0001-observability-judge.md`:

```markdown
# ADR 0001 — Observability Judge

**Status:** Accepted (2026-07-16)

## Context
The config carried evaluation guidance (`evaluating-agents-and-skills`) and observability
guidance (`securing-agentic-systems`, Pillar 7) but ran neither during real work. There was
no agent applying those rubrics to a change, no plain-language readout, and no record to
calibrate against. No runtime trace instrumentation exists, so a true production observability
judge is not possible here.

## Decision
Add a dev-time observability judge: a subagent that scores each change against both rubrics,
relays a junior-dev summary before a PR, and persists verdicts (JSONL + markdown) under
`coding-memory/observability-judge/`. Enforce it with a Tier-1 PreToolUse hook
(`judge-guard.sh`) that blocks `gh pr create` until a fresh implementation-stage verdict
matches the current repo+branch+HEAD (strict freshness). Invocation is driven by a skill
(`running-the-observability-judge`) and a gate stub; the hook only enforces.

## Consequences
- Every change gets a scored, human-readable verdict before it can become a PR.
- Adding a commit after judging invalidates the verdict (strict) — the judge must run last.
- Verdicts accumulate an `outcome` field (backfilled: clean/rework/bug) enabling margin-of-error
  calibration.
- Scope is dev-time only; live-trace ingestion is explicit future work and the schema does not
  pretend to hold it.
- Escape hatch: `JUDGE_EXEMPT=<reason> gh pr create ...` (logged).
```

- [ ] **Step 2: Write the storage schema README**

Create `coding-memory/observability-judge/README.md`:

```markdown
# Observability Judge — verdict store

Written by the `observability-judge` agent. Global store (like the rest of `coding-memory/`);
verdicts are keyed by `repo` + `branch` + `head_sha`, so entries stay correct across repos.

## `verdicts.jsonl` — one JSON object per line

| field | type | notes |
|-------|------|-------|
| `ts` | string | UTC, `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `repo` | string | `basename` of the git top-level |
| `branch` | string | current branch |
| `head_sha` | string | **full** `git rev-parse HEAD` |
| `stage` | string | `architecting` (advisory) or `implementation` (gating) |
| `dimensions` | object | each of the 10 rubric keys → `pass` / `concern` / `fail` |
| `risk` | string | `low` / `medium` / `high` |
| `confidence` | string | `low` / `medium` / `high` |
| `concerns` | string[] | short concern strings |
| `outcome` | string\|null | backfilled later: `clean` / `rework` / `bug` |

Dimension keys: `intent`, `execution`, `trajectory`, `regression`, `context_budget`,
`traceability`, `success_masking`, `intent_drift`, `checkpoint`, `audit_trail`.

## `YYYY-MM-DD-<branch>.md` — human writeup
The four layman sections (what changed / does it do what you wanted / what could go wrong /
what I'd double-check), plus the dimension table and concern list.

## Calibration
`outcome` starts `null`. Backfill it when a PR's real result is known. Aggregating the JSONL by
`risk` vs `outcome` shows where the judge is mis-calibrated (e.g. `risk: low` clustering with
`outcome: bug` → thresholds too loose). Only the `implementation` stage gates a PR.
```

- [ ] **Step 3: Commit**

```bash
git add docs/decisions/0001-observability-judge.md coding-memory/observability-judge/README.md
git commit -m "docs(observability-judge): add ADR and verdict-store schema"
```

---

### Task 2: `judge-guard.sh` hook + tests + settings wiring

The deterministic, testable core. TDD: the stdin-driven test harness comes first.

**Files:**
- Create: `hooks/judge-guard.sh`
- Create: `hooks/judge-guard.test.sh`
- Modify: `settings.json` (append to the existing `PreToolUse` → `Bash` hooks array)

**Interfaces:**
- Consumes: `coding-memory/observability-judge/verdicts.jsonl` (schema from Task 1). Path is overridable via `JUDGE_VERDICTS_FILE` for testing.
- Produces: enforcement — blocks `gh pr create` (exit 2) unless a fresh implementation verdict matches.

- [ ] **Step 1: Write the failing test harness**

Create `hooks/judge-guard.test.sh`:

```bash
#!/usr/bin/env bash
# judge-guard.test.sh — unit tests for judge-guard.sh.
# Feeds PreToolUse JSON on stdin (the code path that actually runs in production),
# overriding the verdicts file and running inside a throwaway git repo so no real
# state is touched. Run: bash hooks/judge-guard.test.sh
set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/judge-guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
cd "$TMP" || exit 1
git init -q
git config user.email t@t.t
git config user.name t
git commit -q --allow-empty -m init
SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REPO="$(basename "$(git rev-parse --show-toplevel)")"

VFILE="$TMP/verdicts.jsonl"
export JUDGE_VERDICTS_FILE="$VFILE"

pass=0; fail=0
run_case() { # $1 desc, $2 want-exit, $3 command
  local desc="$1" want="$2" cmd="$3" payload got
  payload=$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then printf 'ok   — %s (exit %s)\n' "$desc" "$got"; pass=$((pass+1))
  else printf 'FAIL — %s (want %s, got %s)\n' "$desc" "$want" "$got"; fail=$((fail+1)); fi
}
line() { # emit a verdict line with given stage/repo/branch/sha
  python3 -c 'import json,sys; print(json.dumps({"stage":sys.argv[1],"repo":sys.argv[2],"branch":sys.argv[3],"head_sha":sys.argv[4]}))' "$@"
}

: > "$VFILE";                                   run_case "non-gh command passes"            0 "git status"
rm -f "$VFILE";                                 run_case "gh pr create, no verdicts -> block" 2 "gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"; run_case "fresh verdict -> pass"     0 "gh pr create --fill"
line implementation "$REPO" "$BRANCH" deadbeef > "$VFILE"; run_case "stale sha -> block"       2 "gh pr create --fill"
line implementation "$REPO" other "$SHA"      > "$VFILE"; run_case "wrong branch -> block"      2 "gh pr create --fill"
line architecting  "$REPO" "$BRANCH" "$SHA"   > "$VFILE"; run_case "architecting stage -> block" 2 "gh pr create --fill"
rm -f "$VFILE";                                 run_case "JUDGE_EXEMPT=<reason> -> pass"     0 "JUDGE_EXEMPT=hotfix gh pr create --fill"
rm -f "$VFILE";                                 run_case "JUDGE_EXEMPT= (empty) -> block"    2 "JUDGE_EXEMPT= gh pr create --fill"
line implementation "$REPO" "$BRANCH" "$SHA" > "$VFILE"; run_case "gh pr list unaffected"     0 "gh pr list"
# Regression: the phrase inside another command must NOT trigger the guard (anchored regex).
rm -f "$VFILE"
run_case "commit msg containing phrase -> ignore" 0 'git commit -m "feat: blocking gh pr create without a verdict"'
run_case "echo containing phrase -> ignore"       0 "echo gh pr create"
run_case "chained && (documented gap) -> ignore"  0 "cd /tmp && gh pr create --fill"
# Regression: a quoted-space env prefix must NOT silently bypass; a quoted JUDGE_EXEMPT works.
rm -f "$VFILE"
run_case "quoted-space env prefix, no verdict -> block" 2 'FOO="a b" gh pr create --fill'
run_case "quoted multi-word JUDGE_EXEMPT -> exempt pass" 0 'JUDGE_EXEMPT="skip, docs only" gh pr create --fill'
rm -f "$VFILE"
exempt_payload=$(python3 -c 'import json; print(json.dumps({"hook_event_name":"PreToolUse","tool_input":{"command":"JUDGE_EXEMPT=\"skip, docs only\" gh pr create --fill"}}))')
exempt_out=$(printf '%s' "$exempt_payload" | bash "$HOOK" 2>&1)
if printf '%s' "$exempt_out" | grep -q 'exempted (JUDGE_EXEMPT=skip, docs only)'; then
  printf 'ok   — quoted JUDGE_EXEMPT logs exemption\n'; pass=$((pass+1))
else
  printf 'FAIL — quoted JUDGE_EXEMPT did not log exemption (got: %s)\n' "$exempt_out"; fail=$((fail+1))
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash hooks/judge-guard.test.sh`
Expected: FAIL — the hook file does not exist yet, so every case errors (non-zero exits mismatch).

- [ ] **Step 3: Write the hook**

Create `hooks/judge-guard.sh`:

```bash
#!/usr/bin/env bash
#
# judge-guard.sh — PreToolUse hook (matcher: Bash).
#
# Blocks `gh pr create` unless a FRESH implementation-stage observability-judge
# verdict exists for the current repo+branch+HEAD. Strict freshness: the stored
# full head_sha must equal current HEAD, so any commit added after judging forces
# a re-run and the gate always reflects exactly what will ship.
#
# This is a safety gate (it prevents shipping un-judged code), so it fails CLOSED:
# any inability to verify blocks. Contrast doc-guard.sh, a momentum guardrail that
# fails open. Escape hatch: `JUDGE_EXEMPT=<reason> gh pr create ...` (logged).
#
# Regexes live in variables, never inline in `[[ ]]` — a bare `(` or `;` in an
# inline regex kills bash's parser and a dead script exits non-zero. Same trap and
# fix as git-guard.sh / doc-guard.sh.
#
# Exit 0 = allow (silent). Exit 2 = blocked, reason on stderr.

set -u

VERDICTS="${JUDGE_VERDICTS_FILE:-$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl}"

payload=""
if [ ! -t 0 ]; then payload=$(cat); fi
[ -n "$payload" ] || exit 0

py=$(command -v python3 || command -v python) || py=""
if [ -z "$py" ]; then
  printf 'judge-guard: python3 not on PATH; cannot verify a verdict -- failing closed.\n' >&2
  exit 2
fi

command_line=$(printf '%s' "$payload" | "$py" -c '
import json, sys
try:
    p = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
ti = p.get("tool_input")
if isinstance(ti, dict):
    v = ti.get("command")
    if isinstance(v, str):
        sys.stdout.write(v)
' 2>/dev/null)
[ -n "$command_line" ] || exit 0

# Classify the command with python — shlex handles the shell quoting a flat bash regex
# cannot. A command is guarded only when, after an optional leading `rtk` wrapper and any
# leading NAME=VALUE env-assignments, the actual command is `gh pr create`; the phrase inside
# a commit message, an echo, or a quoted string is therefore ignored. JUDGE_EXEMPT's value
# (quoted or not) is captured here. Accepted limitation: a chained `foo && gh pr create` is not
# caught — a momentum guardrail, not a security boundary, the same tradeoff git-guard makes.
classify=$(printf '%s' "$command_line" | "$py" -c '
import re, shlex, sys
try:
    toks = shlex.split(sys.stdin.read())
except ValueError:
    print("NO"); print(""); sys.exit(0)
if toks and toks[0] == "rtk":
    toks = toks[1:]
assign = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
exempt = ""
i = 0
while i < len(toks) and assign.match(toks[i]):
    name, _, val = toks[i].partition("=")
    if name == "JUDGE_EXEMPT":
        exempt = val.replace("\n", " ")
    i += 1
print("PR" if toks[i:i+3] == ["gh", "pr", "create"] else "NO")
print(exempt)
' 2>/dev/null)
kind=$(printf '%s\n' "$classify" | sed -n '1p')
exempt_reason=$(printf '%s\n' "$classify" | sed -n '2p')

[ "$kind" = "PR" ] || exit 0

# Escape hatch: a non-empty JUDGE_EXEMPT reason (quoted or not) as a leading env-assignment
# allows the PR and logs the exemption.
if [ -n "$exempt_reason" ]; then
  printf 'judge-guard: exempted (JUDGE_EXEMPT=%s); skipping verdict check.\n' "$exempt_reason" >&2
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'judge-guard: not inside a git repo; cannot verify a verdict -- failing closed.\n' >&2
  exit 2
fi

repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
head_sha=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$repo" ] || [ -z "$branch" ] || [ -z "$head_sha" ]; then
  printf 'judge-guard: could not determine repo/branch/HEAD -- failing closed.\n' >&2
  exit 2
fi

if [ ! -f "$VERDICTS" ]; then
  printf 'judge-guard: no verdict store yet (%s). Run the observability judge before opening a PR.\n' "$VERDICTS" >&2
  exit 2
fi

match=$("$py" - "$VERDICTS" "$repo" "$branch" "$head_sha" <<'PYEOF'
import json, sys
path, repo, branch, head = sys.argv[1:5]
found = False
try:
    with open(path) as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            try:
                v = json.loads(raw)
            except ValueError:
                continue
            if (v.get("stage") == "implementation" and v.get("repo") == repo
                    and v.get("branch") == branch and v.get("head_sha") == head):
                found = True
                break
except OSError:
    sys.exit(3)
sys.stdout.write("1" if found else "0")
PYEOF
)
if [ $? -ne 0 ]; then
  printf 'judge-guard: could not read the verdict store -- failing closed.\n' >&2
  exit 2
fi
if [ "$match" = "1" ]; then
  exit 0
fi

{
  printf 'judge-guard: no fresh observability-judge verdict for %s@%s (branch %s).\n' "$repo" "${head_sha:0:12}" "$branch"
  printf 'Run the observability judge on the current HEAD (see running-the-observability-judge), then retry.\n'
  printf 'To bypass a genuinely exempt PR: JUDGE_EXEMPT=<reason> gh pr create ...\n'
} >&2
exit 2
```

- [ ] **Step 4: Make it executable and run the tests to verify they pass**

Run: `chmod +x hooks/judge-guard.sh && bash hooks/judge-guard.test.sh`
Expected: `15 passed, 0 failed` (exit 0).

- [ ] **Step 5: Wire the hook into settings.json**

Modify `settings.json` — append to the **existing** `PreToolUse` → matcher `Bash` → `hooks` array (after the `doc-guard.sh` entry). Do **not** overwrite other keys or the user's other in-progress edits:

```json
{
  "type": "command",
  "command": "$HOME/.claude/hooks/judge-guard.sh"
}
```

- [ ] **Step 6: Validate settings.json parses and the wired path enforces end-to-end**

Run:
```bash
python3 -c "import json; json.load(open('settings.json')); print('settings.json OK')"
printf '%s' '{"hook_event_name":"PreToolUse","tool_input":{"command":"gh pr create --fill"}}' \
  | JUDGE_VERDICTS_FILE=/nonexistent bash "$HOME/.claude/hooks/judge-guard.sh"; echo "exit=$?"
```
Expected: `settings.json OK`, then a `judge-guard:` block message and `exit=2`.

- [ ] **Step 7: Commit**

```bash
git add hooks/judge-guard.sh hooks/judge-guard.test.sh settings.json CODING_MEMORY.md
# (add a one-line progress note to CODING_MEMORY.md before committing — see Global Constraints)
git commit -m "feat(hooks): add judge-guard.sh blocking gh pr create without a fresh verdict"
```

---

### Task 3: `observability-judge` agent

The subagent that scores a change and writes the verdict.

**Files:**
- Create: `agents/observability-judge.md`

**Interfaces:**
- Consumes (from the invocation prompt): `stage` (`architecting`|`implementation`), a decisions summary, optional design-doc path, optional test command, base branch.
- Produces: appends a line to `verdicts.jsonl` (schema from Task 1), writes `YYYY-MM-DD-<branch>.md`, and returns the four-part layman summary + risk + top concerns to the caller.

- [ ] **Step 1: Write the agent**

Create `agents/observability-judge.md`:

```markdown
---
name: observability-judge
description: Scores a single code change against the evaluation and observability-governance rubrics, writes a persisted verdict (JSONL + markdown), and returns a junior-developer layman summary. Dev-time reflection on the change's trajectory — not a live production trace.
tools: Read, Grep, Glob, Bash, Write
---

You are the observability judge. You evaluate ONE change and record a verdict. You do not fix,
refactor, or extend code — evaluation only. You judge the **development trajectory** of the change
(its design, diff, the decisions taken, and its test evidence), never a live production trace: no
runtime trace instrumentation exists here, and you must not imply otherwise.

## Inputs (from your invocation prompt)
- `stage`: `architecting` (score the design) or `implementation` (score the committed diff — this
  gates the PR).
- A **decisions summary**: the key choices and why. This is the trajectory you score — read it.
- Optional: a design/spec doc path; a test command; the base branch (default `main`).

## Procedure
1. Establish identity via Bash: `repo=$(basename "$(git rev-parse --show-toplevel)")`,
   `branch=$(git rev-parse --abbrev-ref HEAD)`, `head_sha=$(git rev-parse HEAD)` (full),
   `ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)`.
2. Gather evidence:
   - implementation: `git diff "$(git merge-base <base> HEAD)"..HEAD`.
   - architecting: read the design/spec doc.
   - If a test command was given, **run it yourself** and observe the real result. Never fabricate
     one. If it cannot run, mark `execution` a concern and say so plainly.
3. Score each dimension `pass` / `concern` / `fail`:
   - Evaluation rubric: `intent` (built what was meant), `execution` (works; tests),
     `trajectory` (sound reasoning vs. luck), `regression` (adjacent breakage),
     `context_budget` (bloats always-on context — for rule/skill/prompt changes).
   - Observability rubric: `traceability` (explainable/documented), `success_masking` (green tests
     hiding a problem; unbounded/expensive loops), `intent_drift` (scope creep, drive-by edits,
     unauthorized deps), `checkpoint` (clean revert point; checkpoint-before-modify honored),
     `audit_trail` (attributable; ADR-worthy).
4. Roll up an overall `risk` (`low`/`medium`/`high`) and your `confidence` (`low`/`medium`/`high`),
   and list short `concerns` strings.

## Output
Write ONLY under `coding-memory/observability-judge/` (never elsewhere):
1. `YYYY-MM-DD-<branch>.md` — the four layman sections below, plus the dimension table and concerns.
2. Append one line to `verdicts.jsonl`: `{ts, repo, branch, head_sha, stage, dimensions{...10},
   risk, confidence, concerns[], outcome: null}`. Append the JSONL line LAST, after the markdown
   is written.

Then RETURN to the caller (this text is the caller's data, not the persisted file):
- **What was changed** — plain English, no jargon.
- **Does it do what you wanted?**
- **What could go wrong / what I'm unsure about** — the honest concerns.
- **What I'd double-check before merging.**
- A final line: `risk=<level> confidence=<level>`.

Keep the layman summary short and analogy-friendly — the reader is a junior developer. If any dimension
is `fail`, lead with it. Do not soften a real risk to sound reassuring.
```

- [ ] **Step 2: Validate with a dry run on a sample change**

From the repo root, invoke the agent (via the executing agent's Agent tool, `subagent_type: observability-judge`) with `stage: implementation`, a one-paragraph decisions summary describing this very branch's diff, base branch `main`, and no test command. Then assert the verdict landed:

```bash
tail -1 coding-memory/observability-judge/verdicts.jsonl \
  | python3 -c 'import json,sys; v=json.load(sys.stdin); assert v["stage"]=="implementation" and v["repo"] and v["branch"] and len(v["head_sha"])>=7 and set(v["dimensions"])=={"intent","execution","trajectory","regression","context_budget","traceability","success_masking","intent_drift","checkpoint","audit_trail"}; print("verdict OK:", v["risk"], v["confidence"])'
ls coding-memory/observability-judge/*-"$(git rev-parse --abbrev-ref HEAD)".md
```
Expected: `verdict OK: <risk> <confidence>` and the markdown file listed. Confirm the returned summary has all four layman sections.

- [ ] **Step 3: Commit**

```bash
git add agents/observability-judge.md coding-memory/observability-judge/ CODING_MEMORY.md
# (the dry-run verdict is a legitimate first dogfood entry; keep it. Add a CODING_MEMORY.md note.)
git commit -m "feat(agents): add observability-judge subagent"
```

---

### Task 4: `running-the-observability-judge` skill

Tells the main agent when to invoke the judge and how to relay its result.

**Files:**
- Create: `skills/running-the-observability-judge/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `skills/running-the-observability-judge/SKILL.md`:

```markdown
---
name: running-the-observability-judge
description: Use after architecting a design and after implementing a change, before opening a PR — invoke the observability-judge subagent to score the change against the evaluation and observability rubrics, relay its junior-dev summary, and record a verdict. Not for production runtime tracing or ordinary unit testing.
---

# Running the Observability Judge

A verdict that only lives in a session is a verdict that never calibrates anything. This skill is
how the main agent runs the `observability-judge` subagent at the two moments that matter and turns
its output into something you can act on and learn from. The judge scores the *development
trajectory* of a change; it cannot see a live production trace, and neither can you here — do not
imply otherwise.

## When to run it
- **After architecting** — once a design/spec exists, run the judge with `stage: architecting` for an
  advisory read on the design. Not gated; surface it and move on.
- **After implementing** — once the change is committed on the feature branch, run the judge with
  `stage: implementation`. This verdict gates the PR.

Run the implementation verdict as the **last step before opening the PR**, after the final commit.
Freshness is strict: any commit added afterward moves HEAD and invalidates the verdict, and
`judge-guard.sh` will block `gh pr create` until you re-run it.

## How to invoke
Dispatch the `observability-judge` subagent (Agent tool, `subagent_type: observability-judge`). In the
prompt, give it: the `stage`, a short **decisions summary** (the key choices and why — this is the
trajectory it scores, and it cannot see your session), the design/spec doc path if one exists, the
project's test command if there is one, and the base branch.

## How to relay the result
The subagent's return value is data, not a user-facing message. Relay its four layman sections to the
user in plain language — *what changed · does it do what you wanted · what could go wrong · what I'd
double-check* — and state the `risk`/`confidence`. The full scored verdict is already persisted under
`coding-memory/observability-judge/`.

## Fail closed
If the subagent errors or returns malformed output, write no verdict and fabricate none — report the
failure to the user. With no verdict the hook keeps the PR blocked, which is correct.

## Calibration
Verdicts carry `outcome: null`. When a PR's real result is known, backfill it (`clean`/`rework`/`bug`)
in `verdicts.jsonl` so the risk-vs-outcome history shows where the judge needs tightening.

<!-- Triggers (verified before shipping):
positive: "run the observability judge", "score this change before the PR", "judge the design I just wrote"
negative: "set up OpenTelemetry tracing" (no runtime tracing here), "write unit tests for this function"
(that's core-conduct testing), "review this PR on GitHub" (that's /review) -->
```

- [ ] **Step 2: Validate frontmatter parses and name matches the directory**

Run:
```bash
python3 -c "import re,sys; b=open('skills/running-the-observability-judge/SKILL.md').read(); m=re.search(r'name:\s*(\S+)', b); assert m and m.group(1)=='running-the-observability-judge', m; print('frontmatter name OK')"
```
Expected: `frontmatter name OK`.

- [ ] **Step 3: Commit**

```bash
git add skills/running-the-observability-judge/SKILL.md CODING_MEMORY.md
git commit -m "feat(skills): add running-the-observability-judge"
```

---

### Task 5: Wire the gate stub and catalog entry

Makes the judge discoverable and un-skippable. Final integration.

**Files:**
- Modify: `rules/gates.md` (add one gate stub)
- Modify: `CLAUDE.md` (add one Skills Catalog line)
- Modify: `CODING_MEMORY.md` (index pointer to the new artifacts)

- [ ] **Step 1: Add the gate stub to `rules/gates.md`**

Append this bullet to the gates list:

```markdown
- **Observability-judge gate:** after architecting a design and after implementing a change, run the observability judge before opening a PR — it scores the change against the evaluation and observability rubrics, relays a junior-dev summary, and records a verdict. Enforced by `hooks/judge-guard.sh` (Tier 1), which blocks `gh pr create` until a fresh implementation-stage verdict matches the current HEAD (strict); bypass a genuinely exempt PR with `JUDGE_EXEMPT=<reason>`. Procedure: `running-the-observability-judge`.
```

- [ ] **Step 2: Add the catalog line to `CLAUDE.md`**

Add under the Skills Catalog list:

```markdown
- `running-the-observability-judge` — scoring a change against the evaluation + observability rubrics, relaying a junior-dev summary, and recording a verdict before a PR.
```

- [ ] **Step 3: Add an index pointer to `CODING_MEMORY.md`**

Add a short line under the appropriate repo/branch section noting the observability-judge feature landed (agent + skill + `judge-guard.sh` hook + verdict store), pointing at the ADR and spec.

- [ ] **Step 4: Validate the referenced files all exist**

Run:
```bash
for f in agents/observability-judge.md skills/running-the-observability-judge/SKILL.md hooks/judge-guard.sh docs/decisions/0001-observability-judge.md coding-memory/observability-judge/README.md; do
  test -f "$f" && echo "ok $f" || echo "MISSING $f"
done
grep -q "Observability-judge gate" rules/gates.md && echo "gate stub OK"
grep -q "running-the-observability-judge" CLAUDE.md && echo "catalog OK"
```
Expected: five `ok` lines, `gate stub OK`, `catalog OK`.

- [ ] **Step 5: Commit**

```bash
git add rules/gates.md CLAUDE.md CODING_MEMORY.md
git commit -m "feat(rules,docs): wire observability-judge gate and catalog entry"
```

---

## Self-Review

**1. Spec coverage:**
- 4 artifacts (agent, skill, gate stub, hook) → Tasks 3, 4, 5, 2. ✓
- Two rubrics with the 10 named dimensions → Task 3 agent body + Task 1 schema. ✓
- Dev-trajectory scope + honesty caveat → Task 1 ADR/README, Task 3 agent, Task 4 skill. ✓
- Trigger points (architecting advisory / implementation gating) → Task 3, Task 4. ✓
- Layman report (4 parts) → Task 3 output contract, Task 4 relay. ✓
- Storage JSONL + markdown + calibration `outcome` → Task 1 README, Task 3 output. ✓
- Strict freshness → Global Constraints + Task 2 hook + tests (stale/wrong-branch/architecting cases). ✓
- Fail-closed + `JUDGE_EXEMPT` hatch → Task 2 hook + tests. ✓
- Hook unit tests on the real stdin path → Task 2 Step 1. ✓
- Future work (trace ingestion, `/judge-outcome`) left out of scope → ADR consequences. ✓

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". All code blocks are complete; the one `<base>`/`<default-branch>` token is an explicit parameter, defined in the agent inputs and defaulting to `main`.

**3. Type consistency:** The 10 dimension keys are identical across Task 1 (README table), Task 2 (implicit — hook only reads `stage`/`repo`/`branch`/`head_sha`), Task 3 (agent scoring + validation assertion set), and the JSONL schema. `stage` values (`architecting`/`implementation`), `risk`/`confidence` levels, and `outcome` values (`clean`/`rework`/`bug`) match across ADR, README, agent, and skill. Hook match keys (`stage`,`repo`,`branch`,`head_sha`) match what the agent writes and the test emits.
