# Spec: Deterministic Judge Enforcement + Per-Judge Terminal Sessions

- **Status:** draft for user review. Design of record: `coding-memory/brainstorms/2026-07-20-judge-terminal-enforcement.md` (§1–§4 approved 2026-07-20).
- **Repo:** `suyatdev/.claude` · **Branch:** `feature/judge-terminal-enforcement`
- **Amends the approved design in two places:** §2's `claude --bare` is dropped (see §4.2), and the
  terminal ladder loses its iTerm2 rung, going from five rungs to four (see §6.1, user decision
  2026-07-20). Both are surfaced here rather than absorbed silently.
- **Round 3 revision** (2026-07-20). Round 1: compliance fail, 5 violations. Round 2: 3 closed, but
  `writing-specs/api-contracts` and `gates/escalation-not-preserved` **persisted**, which tripped the
  escalation rule this spec is itself about. Escalated to the user, who directed the fix rather than
  waiving; nothing here is waived. Both persisted for one shared reason — round 2 designed the
  launcher's argument contract without designing its *caller*, so a hook could not populate it. That
  is now §6.2.1.
- **Two claims in the round 2 text were wrong and are corrected, not quietly patched:** the
  staged==worktree precondition did **not** cover `git commit -a` or pathspec commits (the reasoning
  was circular, and real git disproved it — see §5.2), and the escalation ack's id-scoping deadlocked
  the round-3 branch (§6.2.2). Round 2 also introduced, and this round fixes, a cap that could never
  fire because nothing built `--prior-violations-file`.
- **Builds on:** ADR-0001 (observability judge), ADR-0003 (compliance judge), ADR-0005 (lock discipline).

This spec is self-contained: an implementer needs nothing but this file and the repo.

---

## 1. Background — why this exists

Both judges are today invoked by *skills*. A skill is guidance the model may skip; the observability
judge is additionally backed by `hooks/judge-guard.sh`, which deterministically blocks `gh pr create`
without a fresh verdict. The compliance judge has **no** such backstop — ADR-0003 deferred it on the
grounds that no script-decidable "the spec is done" moment existed.

Two problems follow:

1. **Asymmetric enforcement.** Spec compliance depends entirely on the model choosing to run the
   judge. The one gate that is genuinely blocking is the one guarding code, not design.
2. **Judges consume the main session.** Run as in-session `Agent`-tool subagents, judge work spends
   the main window's context and token budget, and its progress is invisible except as tool output.

This change resolves both. It also **closes ADR-0003's deferral**: a `git commit` that stages a file
under `docs/superpowers/specs/` *is* the script-decidable spec-done moment.

**Explicit non-goal:** judging every implementation commit. The trigger moments are unchanged in
spirit — compliance at spec-done, observability before a PR. Ordinary code commits stay untouched.

---

## 2. Scope

| In scope | Out of scope |
|---|---|
| `bin/judge-launch.sh` — thin entrypoint, both judges | Changing either judge's rubric or scoring |
| `bin/lib/judge-*.sh` — five focused libs (§6.1) | Changing either **agent definition** (§4.1) |
| `hooks/spec-guard.sh` — new compliance gate | Judging non-spec docs (ADRs, READMEs) |
| `hooks/judge-guard.sh` — miss-branch extension | Replacing the `Agent`-tool path for ad-hoc runs |
| `settings.json` hook registration + timeouts | CI / remote enforcement |
| Both `running-the-*-judge` skills → launcher | Verdict-store schema changes (unchanged, §5) |
| `.gitignore` — `coding-memory/judge-runs/` entry | Multi-repo verdict namespacing (deferred, §11) |
| Test harnesses + falsification | |

---

## 3. Architecture

```mermaid
flowchart TD
    A["git commit staging docs/superpowers/specs/*.md<br/>OR gh pr create"] --> B{"JUDGE_SESSION=1?"}
    B -- yes --> Z["exit 0 — recursion guard"]
    B -- no --> C{"SPEC_EXEMPT / JUDGE_EXEMPT set?"}
    C -- yes --> Y["exit 0 — logged bypass"]
    C -- no --> P{"spec: index blob<br/>== worktree blob?"}
    P -- no --> P2["exit 2 — stage your edits first<br/>(nothing launched)"]
    P -- yes --> D{"fresh verdict in store?"}
    D -- yes --> Z2["exit 0 — instant, no spawn"]
    D -- no --> X{"escalation cap hit?<br/>(same id twice / round 3)"}
    X -- yes --> X2["exit 2 — ESCALATE to user<br/>(nothing launched)"]
    X -- no --> E{"acquire launch lock"}
    E -- "held by another run" --> F["piggyback-wait on that run's sentinel"]
    E -- acquired --> G["spawn judge via terminal ladder"]
    G --> H["judge session writes verdict to existing store"]
    H --> I["run.sh trap writes done sentinel"]
    F --> I
    I --> J{"re-read store before deadline?"}
    J -- pass --> Z2
    J -- fail --> K["exit 2 — cite violations, agent revises"]
    J -- "deadline / crash" --> L["exit 2 — still running or crashed"]
```

The gate never trusts terminal output. The pane is a viewport; the **verdict store is the sole
authority**, re-read after the sentinel appears.

```mermaid
sequenceDiagram
    participant H as Hook
    participant L as judge-launch.sh
    participant T as Terminal pane
    participant J as Judge claude session
    participant S as Verdict store

    H->>L: --judge X --wait --deadline 840
    L->>L: validate args, mkdir lock, write manifest
    L->>T: spawn bash run-dir/run.sh
    T->>J: claude -p --agent X --output-format json
    J->>S: append verdict JSONL + markdown
    J-->>T: exit
    T->>L: trap writes done sentinel
    loop every 10s until deadline
        L->>L: poll sentinel + liveness probe
    end
    L-->>H: exit 0 sentinel / 3 deadline / 4 preflight / 5 spawn
    H->>S: re-read store, decide 0 or 2
```

---

## 4. Toolchain — pinned

Verified on this machine 2026-07-20. An implementer must not substitute versions.

| Tool | Pinned version | Note |
|---|---|---|
| Claude Code CLI | `2.1.215` | `claude --version` |
| bash | `3.2.57(1)` (`/bin/bash`, arm64-apple-darwin25) | **No bash-4 features** — no associative arrays, no `${v,,}`, no `mapfile` |
| Python | `3.9.6` | JSON + `shlex` parsing, as existing hooks do. No `jq` dependency is introduced |
| tmux | `3.6a` | Only rung that is scriptable in tests |
| cmux | `0.64.20 (100)` (`14e3400b9`) | Ladder rung 1. CLI at `$CMUX_BUNDLED_CLI_PATH`, also on `PATH` |
| git | `2.50.1` | `git rev-parse ":<path>"` for index blob sha |

**cmux sets `TERM_PROGRAM=ghostty`, not `Apple_Terminal`** — it is built on Ghostty. Rung 3's
`TERM_PROGRAM=Apple_Terminal` test therefore cannot false-positive inside cmux, and rung ordering is
not load-bearing for correctness between those two. Verified on this machine 2026-07-20.

### 4.1 Judge agents

Both agent definitions already exist and are unchanged:

```yaml
agents:
  compliance-judge:
    path: agents/compliance-judge.md
    tools: [Read, Grep, Glob, Bash, Write]
  observability-judge:
    path: agents/observability-judge.md
    tools: [Read, Grep, Glob, Bash, Write]
```

`--allowed-tools` is pinned to exactly that declared list — the launcher must not widen it.

**"Unchanged" is a constraint on this design, not an observation.** Each definition declares inputs it
requires — compliance: `spec_path`, `round`, a context summary, optional `waived` ids, and on round > 1
the prior round's `violations` array; observability: `stage`, a decisions summary, optional spec path,
test command, base branch. A launcher that cannot supply those is not a drop-in replacement for the
`Agent`-tool path, so §6.1's argument set is designed to carry every one of them (§6.1.2). Likewise
`agents/compliance-judge.md` computes `spec_blob_sha` itself with `git hash-object <spec_path>` — a
**worktree** hash — which the gate reconciles with a precondition rather than an agent edit (§5.2).

### 4.2 The `--bare` amendment [changes the approved design]

The approved §2 specified `claude --bare -p "<prompt>" --agent <judge>`. **`--bare` must not be
used.** Its documented behaviour: *"Anthropic auth is strictly `ANTHROPIC_API_KEY` or `apiKeyHelper`
via `--settings` (OAuth and keychain are never read)."* This machine has neither set and
authenticates by subscription/OAuth, so `--bare` would fail to authenticate; making it work would
bill judge runs as API credits **separate from the subscription**, and would additionally skip
CLAUDE.md auto-discovery that the compliance judge relies on to read live rules.

**Pinned invocation:**

```
claude -p "$(cat prompt.txt)" --agent <judge> --output-format json --allowed-tools <declared list>
```

Consequence, and why the design already covers it: without `--bare`, **hooks do run inside the judge
session**. The `JUDGE_SESSION=1` recursion guard (§6.3) is therefore load-bearing, not
belt-and-braces. Spike S1 (§10) must confirm it before anything else is built.

---

## 5. Data contracts

Both stores keep their **existing schemas unchanged** — freshness keys and the calibration ledger
stay unbroken. Judge sessions write to the same files the `Agent`-tool path writes to.

```yaml
compliance_store:
  path: coding-memory/compliance-judge/verdicts.jsonl
  env_seam: SPEC_VERDICTS_FILE
  keys: [ts, repo, branch, head_sha, spec_path, spec_blob_sha, round,
          verdict, violations, notes, rule_sources_read, waived, confidence, outcome]
  freshness_key:
    match_on: [repo, spec_path, spec_blob_sha]
    require: verdict == "pass"

observability_store:
  path: coding-memory/observability-judge/verdicts.jsonl
  env_seam: JUDGE_VERDICTS_FILE          # already implemented
  keys: [ts, repo, branch, head_sha, stage, dimensions, risk, confidence, concerns, outcome]
  freshness_key:
    match_on: [repo, branch, head_sha]
    require: stage == "implementation"
```

`spec_blob_sha` already exists in the compliance schema — no migration is needed.

**Why the staged blob sha, not the worktree file:** `git rev-parse ":<path>"` returns the **index**
blob — exactly the content the commit will record. Hashing the worktree file instead would let an
unstaged edit pass a gate for content that never ships. Each revision produces a new blob sha, which
forces a new judging round; this is what makes the revise loop terminate honestly.

### 5.2 The two-hash problem, and the precondition that removes it

The gate and the judge do not compute `spec_blob_sha` the same way, and nothing above reconciles them:

| Who | How | Which content |
|---|---|---|
| `spec-guard.sh` (freshness key) | `git rev-parse ":<path>"` | **index** |
| `agents/compliance-judge.md` step 1 | `git hash-object "<spec_path>"` | **worktree** |
| `running-the-compliance-judge` skill (freshness) | `git hash-object <spec_path>` | **worktree** |

When index and worktree agree these are the same 40 characters and everything works. When they
diverge — the agent stages the spec, then edits it again before committing — the failure is not a
missed gate but a **livelock**: the hook looks up the index blob, misses, launches a judge; the judge
reads and records the *worktree* blob; the hook re-reads the store, still misses, and launches again.
Every iteration costs a full judge session. Worse, the judge would be scoring content the commit is
not going to record, which is precisely the substitution the paragraph above rejects.

**The fix is per-form, not one precondition.** An earlier revision of this spec claimed a single
staged==worktree precondition collapsed all three commit forms. That was wrong, and it was wrong
circularly: the precondition only runs once a spec is detected as *staged*, and `-a` / pathspec are
exactly the forms where nothing is staged. Tested against real git:

```
$ git diff --cached --name-only     # -> (empty)
$ git commit -aqm x                 # commits the modified spec anyway
```

The gate would have exited 0 on its fast path and never reached the precondition at all. So detection
comes first, and each form is resolved to the blob it will actually record:

| Commit form | Files it will record | Effective blob for the spec |
|---|---|---|
| `git commit` | index vs HEAD — `git diff --cached --name-only` | **index**: `git rev-parse ":<spec>"` |
| `git commit -a` / `--all` | tracked worktree mods too — `git diff --name-only HEAD` | **worktree**: `git hash-object <spec>` |
| `git commit -- <pathspec>` | worktree at those paths — `git diff --name-only HEAD -- <pathspec>` | **worktree**: `git hash-object <spec>` |

`-a` stages tracked modifications only, never untracked files, so `git diff --name-only HEAD` is the
correct listing for it. `spec-guard.sh` therefore parses `commit`'s **own** options far enough to
detect `-a`/`--all` and a `--` pathspec, and picks the listing and the hash together.

**The precondition survives, narrowed to the one form that needs it.** For a plain `git commit`, the
commit records the *index* while `agents/compliance-judge.md` hashes the *worktree*; when those
diverge the hook misses forever and relaunches the judge every round — a livelock, each iteration a
full judge session. So for that form only, the gate requires `git rev-parse ":<spec>"` to equal
`git hash-object <spec>`, and on mismatch exits 2 with *"stage your edits to `<spec>` before
committing — the gate judges staged content"*, launching nothing. The agent's fix is one `git add`.

For `-a` and pathspec the divergence cannot arise: the worktree *is* what commits, and the worktree is
what the judge hashes, so they agree by construction and no precondition applies.

Either way **neither agent definition needs to change** (§4.1) and the skill's freshness rule stays
correct as written. §10 requires all three forms tested **against real git**, not against this table —
the claim this paragraph replaces passed review twice by being read rather than run.

One parsing note, since it is a live ambiguity: `commit`'s own `-c <commit>` (reuse message) is not
git's global `-c <k=v>` (config). The global-option walker stops at the first non-option token, so it
never sees `commit`'s flags, and the two cannot be confused.

### 5.1 Run directory

Gitignored (`coding-memory/judge-runs/`) — the stores remain the sole durable record.

**Permission posture — default deny.** A run dir holds the frozen prompt, the judge's full model
output, its stderr, and the launcher's argv. Gitignore governs *committing*, not *reading*, so it is
not a control here. The launcher sets `umask 077` before creating anything and asserts the result:

```
coding-memory/judge-runs/        0700   created by the launcher, never by a rung
coding-memory/judge-runs/<id>/   0700
  every file within                0600   manifest.json, prompt.txt, run.sh, result.json, stderr.log, done
```

`run.sh` is `0600`, never `0700` — every rung invokes it as `bash <run-dir>/run.sh`, so it is read as
data by an interpreter the launcher chose, and is never itself executable. Creation is asserted after
the fact (`stat`-check the mode), not assumed from `umask`: a pre-existing directory with looser modes
would otherwise be inherited silently. A mode assertion failure is a preflight failure (exit 4).

```yaml
run_id: "<UTC ts>-<judge>-<HEAD short sha>-<launcher PID>"   # PID makes parallel launches collision-free
layout:
  coding-memory/judge-runs/<run-id>/:
    manifest.json: "written BEFORE spawn"
    prompt.txt:    "frozen prompt, built from validated args only"
    run.sh:        "the only thing any terminal rung executes"
    result.json:   "claude --output-format json, retains total_cost_usd"
    stderr.log:    "judge stderr; referenced in crash messages"
    done:          "sentinel; contains the judge's exit code"
manifest_fields: [judge, stage_or_spec_path, spec_blob_sha, repo, branch, head_sha,
                  round, waived_ids, ladder_rung, terminal_ref, argv, launcher_pid]
```

---

## 6. Component contracts

### 6.1 The launcher

#### 6.1.1 Decomposition and size budgets

Seven distinct jobs do not belong in one file. The largest hook in this repo today is
`hooks/scan-invisible-unicode.sh` at 211 lines; `judge-guard.sh` is 144. The launcher ships as a thin
entrypoint over five single-purpose libs, each sourced, each with a stated budget:

| File | Job | Budget |
|---|---|---|
| `bin/judge-launch.sh` | arg parse, orchestration, exit-code mapping | ≤ 120 |
| `bin/lib/judge-validate.sh` | argument + path validation, preflight, mode assertions | ≤ 110 |
| `bin/lib/judge-rundir.sh` | run-id, run dir, `manifest.json`, `prompt.txt`, `run.sh` | ≤ 130 |
| `bin/lib/judge-lock.sh` | acquire / stale-break / piggyback / release | ≤ 100 |
| `bin/lib/judge-spawn.sh` | the terminal ladder | ≤ 110 |
| `bin/lib/judge-wait.sh` | sentinel poll, liveness probe, deadline | ≤ 80 |

Budgets are enforced by the test harness, not by convention: `judge-launch.test.sh` fails if any file
exceeds its number. No file approaches the 400-line convention, and the libs are independently
testable — `judge-lock.sh` in particular, whose regression history (ADR-0005) is the reason it is its
own unit rather than a section of a larger script.

#### 6.1.2 Argument contract

```
judge-launch.sh --judge compliance --spec <path> --round <N>
                [--context-file <path>] [--prior-violations-file <path>]
                [--waived id,id] [--acked id,id] [--wait [--deadline <secs>]]
judge-launch.sh --judge observability --stage architecting|implementation
                [--decisions-file <path>] [--spec <path>] [--test-cmd-file <path>]
                [--wait [--deadline <secs>]]
```

The `*-file` arguments exist because the judges require inputs that no flag-sized value can carry: the
compliance judge scores YAGNI *against a stated need* and, from round 2, reuses ids from the prior
round's `violations` array; the observability judge scores the **decisions summary** as its trajectory
evidence. Passing these as files rather than as argument text is what keeps §9.2 intact — see §6.1.3.

**Every one of them is optional, and that is the point.** A launcher whose required arguments only an
interactive agent can supply is not usable by a hook, and the hook path is the whole reason this design
exists. Each optional input therefore has a **specified deterministic fallback** (§6.2.2) rather than
being merely omittable — an absent input never means the judge silently receives less than its
definition requires.

**Argument validation — fail closed on any miss:**

| Arg | Rule |
|---|---|
| `--spec` | resolves inside repo, matches `docs/superpowers/specs/*.md`, exists in the index, index blob == worktree blob (§5.2) |
| `--stage` | enum: `architecting` \| `implementation` |
| `--round` | numeric, `>= 1` |
| `--waived`, `--acked` | comma-separated, charset `^[A-Za-z0-9_.,-]+$` |
| `--*-file` | resolves inside repo or run dir, exists, regular file (not symlink/FIFO), non-empty, ≤ 64 KiB, UTF-8 decodable |
| run-dir path | launcher-generated, asserted `^[A-Za-z0-9/_.-]+$` before any interpolation |

Only the **paths** are validated; file *contents* are never validated, never parsed, and never reach a
shell — they are copied bytes-for-bytes into `prompt.txt`. The 64 KiB cap is a prompt-budget guard, not
a safety control.

#### 6.1.3 Prompt contract

`prompt.txt` is assembled by `judge-rundir.sh` from a fixed template plus the validated inputs, written
once before spawn, and never regenerated. Sections are delimited by fixed heredoc markers the launcher
emits; interpolated values come only from the validated arg set, and file contents are streamed in
whole.

```
You are judging as the <judge> agent. Inputs follow.

spec_path: <validated --spec>          # compliance: the spec to judge
round: <validated --round>             # compliance only
stage: <validated --stage>             # observability only
design_doc: <validated --spec>         # observability: optional design/spec doc
test_command: <contents of --test-cmd-file, or "none — nothing runnable at this stage">
base_branch: main
waived: <validated --waived, or "none">

--- BEGIN CONTEXT SUMMARY ---          # verbatim --context-file / --decisions-file, or the §6.2.2 fallback
<file contents>
--- END CONTEXT SUMMARY ---

--- BEGIN PRIOR VIOLATIONS (round N-1) ---       # omitted entirely when round == 1
<file contents>
--- END PRIOR VIOLATIONS ---

Follow your agent definition. Persist your verdict before returning.
```

Both judges' declared inputs are now covered: compliance's `spec_path`, `round`, context summary,
`waived`, base branch and prior violations; observability's `stage`, decisions summary, design doc,
test command and base branch. `--test-cmd-file` is a file rather than a flag value for one reason: a
test command is shell text, and a flag would invite it onto a command line. It is written into
`prompt.txt` as data, and the judge — not the launcher — decides whether to run it.

**Why this does not reopen the injection surface §9.2 closed.** The threat model there is untrusted
text becoming *terminal command text* — an AppleScript `do script` argument. Here no rung ever sees the
prompt: rungs execute `bash <run-dir>/run.sh`, and `run.sh` reads the prompt with
`"$(cat "$RUN_DIR/prompt.txt")"`, which is shell-quoted at the point of use. Content that would be
hostile as shell text is inert as file bytes. §9.3 is amended accordingly: prompts are built from the
validated argument set **and the contents of files named by validated paths**, the latter treated
strictly as data.

The residual risk is prompt injection *against the judge* — a context summary that instructs the judge
to pass. This is accepted and bounded: the summary is authored by the same main agent that authored the
spec, so it crosses no trust boundary the spec itself does not already cross, and the judge's output is
constrained by its own definition and persisted where the user reads it. Delimiters are fixed markers
so a summary containing one is visible in `prompt.txt` rather than silently structural.

**Exit codes** (`2` is deliberately unused, reserved so a launcher status can never be mistaken for a
hook's own `exit 2`):

| Code | Meaning | Hook mapping |
|---|---|---|
| 0 | sentinel observed; caller re-reads store | continue to store re-check |
| 1 | usage / validation error | exit 2, "gate misconfigured" |
| 3 | deadline expired, judge still running | exit 2, "still running in `<ref>`" |
| 4 | preflight failed (`claude` absent, agent def missing, run-dir mode assertion) | exit 2, naming the missing piece |
| 5 | spawn failed on every rung | exit 2, "could not start judge" |

**`run.sh` contract** — the indirection that removes the AppleScript injection risk. No rung ever
interpolates a prompt; every rung executes only `bash <run-dir>/run.sh`.

```bash
set -euo pipefail
RUN_DIR=<absolute run-dir>                 # absolute: cwd is the repo root, not the run dir
cd <repo root>                             # judge must resolve repo-relative paths
export JUDGE_SESSION=1
trap 'echo $? > "$RUN_DIR/done"' EXIT      # sentinel on every path, including crash
claude -p "$(cat "$RUN_DIR/prompt.txt")" --agent <judge> --output-format json \
       --allowed-tools <declared list> \
       > "$RUN_DIR/result.json" 2> "$RUN_DIR/stderr.log"
```

Every run-dir path here is **absolute**. `run.sh` deliberately runs with the repo root as its cwd so
the judge resolves repo-relative paths like `docs/superpowers/specs/...`; relative artifact paths
would therefore land in the repo root, not the run dir.

**Terminal ladder** — first available rung wins; the chosen rung is recorded in the manifest:

| # | Detected by | Spawn | `terminal_ref` | Liveness probe |
|---|---|---|---|---|
| 1 | `CMUX_WORKSPACE_ID` | `cmux new-workspace --name "judge: <judge>" --cwd <repo root> --command "bash <run-dir>/run.sh" --focus false` | workspace ref on stdout | `cmux list-workspaces`, ref still present |
| 2 | `TMUX` | `tmux split-window -d bash <run-dir>/run.sh` | pane id | `tmux list-panes`, id still present |
| 3 | `TERM_PROGRAM=Apple_Terminal` | Terminal `do script "bash <run-dir>/run.sh"` via `osascript` | window id | none available — deadline only |
| 4 | — (always available) | `nohup bash <run-dir>/run.sh &` (`mode=headless`) | PID | `kill -0 <pid>` |

Every rung executes the identical string `bash <run-dir>/run.sh` and differs only in how it is
delivered. Note that rung 1's `--command` takes *text*, so it is an interpolation point exactly like
rung 3's AppleScript — which is why §6.1.2 charset-asserts the launcher-generated run-dir path before
any rung sees it, and why the indirection matters on the first rung as much as the third.

**Why each rung exists:** 1 is the user's primary environment; 2 is in active use and the only rung
scriptable in tests (§10); 3 is the only rung when neither multiplexer is running; 4 is the
correctness floor — the gate must still work when detection fails, which is what keeps S2 a
non-blocking spike.

**Four rungs, not five — and each answers a need the user actually has.** iTerm2 is dropped: the user
does not run it, so a fifth rung would have been speculative surface. The remaining three named rungs
each correspond to a terminal the user works in daily, and rung 4 is not a convenience — it is what
makes S2 (env-var inheritance, §10) a non-blocking spike rather than a blocking one. If detection
silently fails, the judge still runs; only its visibility degrades.

**The `osascript` surface does not go away with iTerm2.** Terminal's `do script` is AppleScript, so
rung 3 keeps the injection surface that §9.2 exists to close, and the `run.sh` indirection stays
load-bearing — justified on the Terminal rung specifically, not on the dropped one. A future change
that removed rung 3 could revisit the indirection; nothing else here can.

**Wait mode:** poll the sentinel every **10s**; deadline default **840s**. On each poll also run a
best-effort liveness probe for the chosen rung (tmux pane still exists / headless PID alive) so a
SIGKILLed pane — which leaves no trap and therefore no sentinel — exits early as
"terminated without completing" rather than burning the full deadline.

**Launch lock** — `mkdir`-atomic, per `judge + repo + target-key`:

- Lock dir holds the owning `run-id` and launcher PID.
- A second caller for the same target **piggyback-waits on the first run's sentinel** instead of
  duplicating the judge.
- Stale-lock break re-verifies its justifier (owner PID actually dead) **immediately before**
  breaking, per ADR-0005. Use `mkdir` where "create or fail" is meant — never `mv`, which nests when
  the destination exists.

### 6.2 `hooks/spec-guard.sh` [new]

PreToolUse / Bash.

**Detection — what is reused and what is new.** Reused from `judge-guard.sh` unchanged: the python
`shlex` split, the leading `rtk` strip, the leading `NAME=VALUE` env-assignment walk, and the anchored
subcommand match. **New code, not reuse:** all git global-option handling. `judge-guard.sh` contains no
`-C` handling whatsoever — it matches a three-token `gh pr create` and never needed any. Describing the
`-C` path as "verbatim" reuse would have sent an implementer looking for a function that does not exist.

That distinction matters because the blast radius changes shape. `gh pr create` is rare; `git commit`
is the most-run command in this repo, so a classifier bug here blocks *all* commits rather than an
occasional PR. Global options are therefore handled explicitly:

| Form | Handling |
|---|---|
| `-C <dir>`, `-c <k=v>`, `--git-dir=<d>`, `--work-tree=<d>`, `--namespace=<n>`, `--exec-path=<p>`, `--config-env=<e>` | Consumed with their value; **passed through** to every `git` the hook itself runs (§5.2's hash comparison and the staged-file listing must target the same repo the commit targets) |
| Flag-only globals (`--no-pager`, `--paginate`, `--bare`, `--literal-pathspecs`, …) | Skipped generically as a leading `-*` token |
| An unrecognized **value-taking** option | Unclassifiable → `exit 0` with a logged warning (see below) |
| First non-option token | Must be exactly `commit`, else `exit 0` |

**Two failure directions, deliberately treated differently.** Infrastructure failure — python absent,
store unreadable — **fails closed** (block), matching judge-guard. *Classification ambiguity* on an
exotic git invocation **fails open with a log line**, because this is a momentum guardrail rather than a
security boundary, and blocking every commit in the repo on an unparseable global option is a worse
outcome than missing one gate. This is the same posture as the accepted chained-command limitation
(`foo && git commit`) in judge-guard and git-guard; it is named in §11 rather than left implicit.

**Fast path — a necessary-condition pre-filter.** Before spawning python at all, the hook checks
whether the raw command string contains the substring `commit`; if not, `exit 0` immediately. A second
PreToolUse/Bash hook would otherwise add a python spawn to *every* Bash tool call. This is safe
specifically because it can only ever *skip* work: no string lacking `commit` can be classified as
`git commit` by the anchored classifier, so the filter removes no block that would otherwise happen.
The distinction is load-bearing — this repo has already shipped a substring bug where the substring
*decided* rather than pre-filtered — so the invariant is stated as a test: **every block decision is
made by the anchored classifier; the substring appears in no decision path.** Past the pre-filter, a
commit staging no `docs/superpowers/specs/*.md` file exits 0 after one `git diff --cached --name-only`.

**Decision order:** `JUDGE_SESSION` → `SPEC_EXEMPT` → staged==worktree precondition (§5.2) → freshness
→ **escalation check** → launch → re-verify.

#### 6.2.1 How the hook populates the launcher's arguments

Round 2 specified the launcher's argument contract but never said where a *hook* — running
non-interactively inside a `git commit`, with no conversation to draw on — obtains those arguments.
Both of round 1's persistent violations trace to that single omission: the interface was designed
without its caller. Every argument the hook passes is derived deterministically from the repo and the
store, with no main-agent input at any point.

| Argument | How the hook produces it |
|---|---|
| `--spec` | the staged/effective spec path from detection (§5.2) |
| `--round` | `max(stored round for repo + spec_path) + 1`, or `1` if none (§6.2.2) |
| `--prior-violations-file` | **built from the store**: the hook extracts the `violations` array of the most recent stored round for this repo + spec_path and writes it to `<run-dir>/prior-violations.json`. Omitted only when `round == 1`. Uses the python it already runs to parse the store — no new dependency |
| `--waived` | the union of `waived` ids across this spec's stored verdicts |
| `--acked` | `SPEC_ESCALATION_ACK`, when set (§6.2.2) |
| `--context-file` | **not passed** — see below |
| `--decisions-file` | **not passed** on the `judge-guard` path — see below |

**`--prior-violations-file` is what makes the cap real.** The "same id in two consecutive rounds"
tripwire depends on the judge *reusing* violation ids, and `agents/compliance-judge.md` only reuses
ids when handed the prior round's array. Without this row the tripwire silently no-ops: it would
compare ids that the judge had no reason to keep stable, so persistence would read as novelty and the
loop would never escalate. The store already holds the array, so this is an extraction, not new state.

**Why the hook passes no `--context-file`, and why that is better than passing one.** The compliance
judge scores YAGNI against a *stated need*. On the hook path the stated need is already in the
artifact under judgment: §1 Background gives the why, §2 Scope gives the boundaries, and this spec
claims on line 1 to be self-contained. When `--context-file` is absent the launcher emits, in the
context slot, a fixed instruction to read the spec's own Background and Scope as the stated need.

That is not a degradation. An agent-authored summary is precisely the injection vector §6.1.3 flags —
the agent that wrote the spec would also be writing the standard the spec is judged against, and a
summary that quietly restates a speculative feature as a requirement turns a YAGNI violation into a
pass. Judging the spec on its own terms removes that lever. The `--context-file` argument survives for
the skill path, where a human-directed summary carries genuine information the spec cannot (for
example: *"the user does not use iTerm2"*), and the skill continues to supply it.

**Same reasoning for `--decisions-file` on the `judge-guard` path.** When absent, the launcher's
fallback names the deterministic trajectory evidence that already exists: the branch's commit messages
(`git log <base>..HEAD`) and the branch log under `coding-memory/branches/`. This repo writes commit
messages that state decisions and their reasons, so the evidence is real rather than a placeholder.
The skill path keeps passing an explicit summary.

**The fallback text is a launcher constant, not a runtime string.** It is compiled into
`judge-rundir.sh`, never derived from the command being gated, so it introduces no new input to
validate.

#### 6.2.2 Round accounting and the escalation cap

`rules/gates.md` requires that persistent violations escalate to the user and are never silently
waived. Today that cap lives in `running-the-compliance-judge`: escalate when the same violation `id`
is cited in two consecutive rounds, or when round 3 completes with anything outstanding. **The whole
premise of this change is that a skill is skippable**, so the deterministic path inherits none of it —
moving the loop into the hook without moving the cap would leave an unbounded loop whose every
iteration costs a full judge session and up to 14 minutes. The cap moves with the loop.

**No new storage is needed.** The compliance store already carries `round` and `violations` per
`spec_blob_sha`, keyed by `repo` + `spec_path`, so attempt history is reconstructible from the file the
hook already reads.

- `round` = `max(stored round for this repo + spec_path) + 1`, and **`1` when the spec has no stored
  verdicts** — the empty case is defined, not inferred.
- Rounds are counted per `spec_path`, deliberately **not** per `spec_blob_sha`: each revision produces
  a new blob, so per-blob counting would reset the cap on every revision and never fire.

**Escalation fires before the launch, not after** — the point is to stop spending judge sessions:

```mermaid
flowchart TD
    A["spec-guard: freshness miss"] --> B["read stored rounds for repo + spec_path"]
    B --> C{"same violation id in the<br/>two most recent rounds?"}
    C -- yes --> E["exit 2: ESCALATE — stop revising,<br/>put it to the user. No judge launched."]
    C -- no --> D{"last stored round >= 3<br/>and still failing?"}
    D -- yes --> E
    D -- no --> F["launch judge at round = max + 1"]
    F --> G{"verdict"}
    G -- pass --> H["exit 0"]
    G -- fail --> I["exit 2: cite violations, agent revises"]
    E --> J["user decides"]
    J -- "waives" --> K["SPEC_EXEMPT=... (logged bypass)"]
    J -- "directs a different fix" --> L["SPEC_ESCALATION_ACK=id,id<br/>on the retry commit"]
    L --> F
```

**Releasing an escalation — `SPEC_ESCALATION_ACK=<id,id>`.** Without an escape the cap deadlocks: the
history that triggered escalation is immutable, so every subsequent attempt would re-escalate without
ever launching. The ack is the agent's assertion that *the user has been consulted about these exact
ids*. It is parsed exactly like `SPEC_EXEMPT` (leading env-assignment, value logged to stderr),
suppresses the escalation check and is **single-use**: it authorises one launch and is recorded in the
run manifest. It is not persisted as state, so if the same id recurs on a later round the ack is no
longer set and the escalation fires again — each escalation costs a fresh human decision, which is the
intended price.

**The ack releases both escalation branches, not just the id-scoped one.** An earlier revision said the
ack was scoped "to precisely the listed ids" while the round-3 branch has no ids in its predicate —
read strictly, a spec that reached round 3 failing could never launch a judge again, which is the same
deadlock the ack exists to prevent, merely relocated. Resolved explicitly: a set `SPEC_ESCALATION_ACK`
suppresses the escalation check for that one launch, whichever branch fired. The listed ids are
recorded for attribution, not used as a filter.

**The ack is deliberately not passed to the judge.** It reaches the manifest and the hook's stderr, but
never `prompt.txt`. Telling a judge "the user has been consulted about `core-conduct/yagni`" is an
invitation to soften on exactly the violation under dispute, and the judge's contract is to score the
spec as it stands. Keeping the ack out of the prompt also keeps §4.1 true: the compliance agent's input
list stays exactly what its definition declares, with no undeclared field to interpret.

An ack is **not** a waiver and must not be used as one: it does not suppress the violation, and the
judge still cites it. Only `SPEC_EXEMPT` bypasses the gate, and only the user supplies it.

**Ownership, stated once:** on the deterministic path the **hook owns the cap**; the skill keeps its own
for `Agent`-tool and ad-hoc runs. They cannot drift apart on history, because both derive it from the
same store — but the thresholds are duplicated in two places, and §10 requires a test asserting they
agree.

On a freshness miss that clears the escalation check: launcher `--wait` → re-read the store → `exit 0`,
or `exit 2` with the stored violations on stderr so the main agent revises and retries.

### 6.3 `hooks/judge-guard.sh` [extended]

Unchanged through detection, `JUDGE_EXEMPT`, and the freshness check. Only the terminal
"no fresh verdict → exit 2" branch changes: it now launches `--stage implementation --wait`,
re-checks, then exits 0 or 2. Adds the `JUDGE_SESSION=1` short-circuit.

It passes no `--decisions-file`, taking the §6.2.1 fallback (branch commit messages plus the branch
log) for the same reason `spec-guard` passes no `--context-file`: a hook has no conversation to
summarise, and a summary it could fabricate would be worse than the evidence already in the repo.
`judge-guard` has **no escalation cap** — its loop is bounded by the PR attempt itself rather than by
rounds, and `stage: implementation` verdicts key on `head_sha`, so each retry follows a new commit.

### 6.4 Exemptions

**Separate `SPEC_EXEMPT=<reason>`**, parsed exactly like `JUDGE_EXEMPT` (leading env-assignment,
value logged to stderr). Each gate keeps its own key so a bypass stays as narrow as the gate it
opens — per-door keys, not a master key.

Three keys exist and they are not interchangeable. The distinction is what keeps "nothing is waived
silently" true:

| Key | Opens | Authorised source |
|---|---|---|
| `SPEC_EXEMPT=<reason>` | the whole spec gate, once | user |
| `JUDGE_EXEMPT=<reason>` | the whole PR gate, once | user |
| `SPEC_ESCALATION_ACK=<ids>` | the escalation cap only, once (§6.2.2) | agent, **after** consulting the user |

`SPEC_ESCALATION_ACK` never suppresses a violation and never allows an unjudged commit — the judge
still runs and still cites.

**"Authorised source" is a convention, not an enforcement, and the spec says so rather than implying
otherwise.** All three are indistinguishable leading env-assignments; the hook cannot tell whether a
human or the agent set one, and nothing prevents an agent from re-supplying an ack every round to keep
a loop alive indefinitely. This is stated plainly because the alternative — writing the table as though
the hook enforced provenance — would be a claim the code cannot back, and this branch has already
shipped one of those.

What the design does provide is **visibility, not prevention**: every key's value is echoed to stderr
where the user sees it, the ack is recorded in the run manifest, and every round is a store row with a
timestamp, so a fabricated ack or a spinning loop is reconstructible after the fact. The deterministic
part of the cap is the *detection*; the release is advisory by construction, for the same reason
`SPEC_EXEMPT` is — a gate whose bypass cannot be reached is a gate that gets deleted. Making the
release enforceable would require provenance the hook does not have, and is listed in §11 rather than
pretended here.

### 6.5 `settings.json`

Register `spec-guard.sh` on PreToolUse/Bash alongside `judge-guard.sh`. Both judge hooks get an
explicit `"timeout": 900`, with the launcher's `--deadline 840` deliberately **below** it.

**Why the ordering matters:** a hook that hits the harness timeout **fails OPEN** — the tool call
proceeds. If the harness timer fired first, a slow judge would silently *allow* the very commit the
gate exists to block. Our own 840s deadline guarantees the hook exits 2 under its own control first.

**Both halves of that sentence are assumptions, and neither has been measured here — see blocking
spike S3 (§10).** No hook in `settings.json` sets an explicit timeout today; every one runs on the
default, so `900` is unprecedented in this repo. Two things must hold: that the harness honours a
900s hook timeout at all (rather than silently capping it lower), and that a timed-out hook fails open
(rather than blocking, which would be a different but survivable failure). If the harness caps below
840s, the gate fails open **exactly when the judge is slow** — the case it exists for — and it fails
open *silently*, producing a commit that looks judged and never was. That is the worst available
shape, which is why S3 blocks implementation alongside S1 rather than being verified afterwards.

If S3 shows a lower effective cap, the deadline is not simply lowered to fit: a judge that cannot
finish inside the real cap makes the wait-inline model unworkable, and the fallback is to exit 2
immediately on a freshness miss ("judge launched in `<ref>`; re-run the commit when it finishes"),
turning the gate from blocking-and-waiting into blocking-and-retrying. That is a design fork, so it is
resolved by measurement before implementation, not during it.

### 6.6 Skills

Both `running-the-*-judge` skills change "dispatch subagent (Agent tool)" → "run the launcher as a
background Bash task". At spec-done both judges still launch in parallel (two windows); the main
window receives the harness background-task notification on each exit, then reads the stores.

The skills keep supplying `--context-file` / `--decisions-file` explicitly: a human-directed summary
carries information the artifact genuinely cannot (*"the user does not use iTerm2"* decided this
design's ladder), which is exactly why those arguments exist even though the hook path declines them
(§6.2.1). Each skill also keeps its own capped loop for the `Agent`-tool and ad-hoc paths, with
thresholds identical to §6.2.2's. `running-the-compliance-judge`'s freshness sentence — *"a verdict is fresh only while its
`spec_blob_sha` matches `git hash-object <spec_path>`"* — stays correct as written **only under §5.2's
staged==worktree precondition**, and the skill gains a sentence saying so.

### 6.7 What the operator sees

A `git commit` that stages a spec can now block for **up to 840 seconds**. That is a real change to the
feel of the most-run command in the repo, and it is stated here rather than discovered:

- **Cache hit (the common case):** no spawn, no wait — the freshness check is a store read.
- **Miss:** the commit blocks while a judge runs in its own visible pane. The main session shows the
  Bash tool call pending; the launcher emits a single stderr line naming the run dir and the pane
  (`terminal_ref`) before it starts polling, so the wait is attributable rather than a hang.
- **Escalation:** no wait at all — the cap fires before the launch, so the slow path is never paid to
  reach a conclusion the user must arbitrate anyway.

The wait is inline and blocking by design: a non-blocking gate on `git commit` is one the agent walks
past, which is the failure this whole change exists to fix. The escape for a genuinely urgent commit is
`SPEC_EXEMPT`, logged.

---

## 7. Scenarios

### Good paths

```gherkin
Scenario: Fresh verdict short-circuits
  Given a pass verdict exists for this spec's staged blob sha
  When the agent runs `git commit` staging that spec
  Then spec-guard exits 0 without spawning anything

Scenario: Miss launches, judge passes, commit proceeds
  Given no verdict exists for the staged blob sha
  When the agent runs `git commit` staging that spec
  Then a judge session starts in its own pane
  And spec-guard waits for the sentinel, re-reads the store, and exits 0

Scenario: Parallel spec-done launches both judges
  Given the skill launches compliance and observability together
  Then each gets its own run-id and its own window
  And neither lock blocks the other, because the target keys differ
```

### Bad paths

```gherkin
Scenario: Judge fails the spec
  Given the judge writes a fail verdict citing two violations
  When spec-guard re-reads the store
  Then it exits 2 with both violations on stderr
  And the commit is blocked so the agent can revise and retry

Scenario: Judge crashes
  Given the judge process dies non-zero
  Then the trap still writes the sentinel with that exit code
  And the hook message says "crashed", points at stderr.log,
    and is distinguishable from "ran and failed the spec"

Scenario: python3 is unavailable
  Then spec-guard cannot classify the command and exits 2 — fail closed

Scenario: The spec has unstaged edits
  Given the spec's index blob differs from its worktree blob
  When the agent runs `git commit` staging that spec
  Then spec-guard exits 2 telling the agent to stage its edits first
  And no judge is launched, because the two hashes would never reconcile

Scenario: The same violation survives the revision meant to fix it
  Given `core-conduct/yagni` was cited in the two most recent stored rounds
  When the agent runs `git commit` staging the revised spec
  Then spec-guard exits 2 with an ESCALATE message naming that id
  And no judge is launched, so no session is spent on a decision the user owns

Scenario: Round 3 completes with anything outstanding
  Given the last stored round is 3 and its verdict is fail
  Then spec-guard escalates on the same terms, whatever the ids are
```

### Edge cases

```gherkin
Scenario: The judge's own session hits the same hook
  Given run.sh exported JUDGE_SESSION=1
  When the judge session runs any git commit
  Then both guards exit 0 immediately, and no judge launches a judge

Scenario: Pane killed with SIGKILL, no trap, no sentinel
  Then the liveness probe reports the pane gone
  And the launcher exits early rather than waiting the full 840s

Scenario: A second commit races the first for the same spec
  Then the second caller finds the lock held
  And waits on the FIRST run's sentinel rather than launching a duplicate

Scenario: Deadline expires with the judge still working
  Then the launcher exits 3 and the hook exits 2 "still running in <ref>"
  And the harness 900s timeout never fires, so the gate never fails open

Scenario: Store is being appended to while the hook reads it
  Then unparseable (mid-append) lines are skipped, not treated as corruption

Scenario: Commit stages a spec AND source files
  Then the spec gate still applies — staging extra files is not an escape hatch

Scenario: Commit stages no spec file
  Then spec-guard exits 0 silently on the fast path

Scenario: The user is consulted and directs a different fix
  Given an escalation fired for `core-conduct/yagni`
  And the user directed a different fix rather than waiving it
  When the agent retries with SPEC_ESCALATION_ACK=core-conduct/yagni
  Then the escalation check is suppressed for that id only
  And a judge launches at round max+1
  And the ack is recorded in the run manifest but absent from prompt.txt

Scenario: An acknowledged violation recurs on a later round
  Given the ack authorised exactly one launch and was not persisted
  When the same id is cited again
  Then spec-guard escalates again, because a fresh human decision is required

Scenario: An ack is used where a waiver was meant
  Given SPEC_ESCALATION_ACK lists an id the judge still cites
  Then the violation is still cited and the commit is still blocked
  And only SPEC_EXEMPT can bypass the gate itself

Scenario: Commit uses -a with the spec modified but never staged
  Given `git diff --cached --name-only` is empty, so the fast path would exit 0
  When the agent runs `git commit -am "..."`
  Then detection uses `git diff --name-only HEAD` instead, and sees the spec
  And the effective blob is the worktree hash, matching what the judge records
  And the gate applies — -a is not an escape hatch

Scenario: Commit names a pathspec
  When the agent runs `git commit -- docs/superpowers/specs/x.md`
  Then detection lists `git diff --name-only HEAD -- <pathspec>` and sees the spec
  And the worktree blob is used, because that is what the commit will record

Scenario: Pathspec stages an unrelated file alongside a modified spec
  Given a non-empty staged listing would let the fast path proceed
  Then detection still resolves the effective file set for the actual form
  And a spec that will be committed is never missed because something else was staged

Scenario: An escalation fires on the round-3 branch, which cites no ids
  When the agent retries with SPEC_ESCALATION_ACK set
  Then the escalation check is suppressed for that launch regardless of branch
  And the loop is not deadlocked by an id-scoped release

Scenario: Commit runs against another repo via -C
  When the agent runs `git -C ../other commit`
  Then the hook's own hash comparison and staged-file listing use -C ../other too
  And the gate reasons about the repo the commit actually targets

Scenario: An unrecognized value-taking global option appears
  Then the command is unclassifiable, spec-guard exits 0 and logs a warning
  And the ambiguity is visible rather than silently blocking every commit

Scenario: A Bash command that cannot be a commit
  Given the raw command string contains no "commit" substring
  Then spec-guard exits 0 without spawning python
  And no block decision was made by the substring — only by the anchored classifier
```

---

## 8. Failure matrix

| Failure | Detection | Result |
|---|---|---|
| Judge crash | trap writes sentinel + non-zero code | exit 2, "crashed", cites `stderr.log` |
| Pane SIGKILLed | liveness probe | exit 2 early, "terminated without completing" |
| Deadline hit | 840s timer | exit 2, "still running in `<ref>`" |
| Duplicate launch | `mkdir` lock held | piggyback-wait, no duplicate |
| Stale lock | owner PID dead, re-verified at break time | break, then acquire |
| Spawn failure | rung returns non-zero | fall through ladder toward headless; failures recorded |
| `claude` missing | preflight | exit 4, distinct message |
| Run-dir mode wrong | `stat` assertion after create | exit 4, "run dir not private" |
| Store unreadable | read error | exit 2, fail closed |
| Spec staged ≠ worktree (plain `commit` only) | hash comparison (§5.2) | exit 2, "stage your edits first"; nothing launched |
| Spec committed via `-a` / pathspec | per-form detection + worktree blob (§5.2) | gate applies normally; no precondition needed |
| Violation survives its fix | same id in two most recent rounds | exit 2 ESCALATE; nothing launched |
| Loop reaches round 3 failing | stored round ≥ 3, verdict fail | exit 2 ESCALATE; nothing launched |
| Exotic git global option | classifier cannot resolve | exit 0 + logged warning (open, by §6.2's stated posture) |
| Harness caps hook timeout < 840s | **S3, unmeasured** | would fail OPEN silently — blocks implementation until measured |

Every path ends in a **closed gate or a clear message — never a hang** — with one exception that is
called out rather than absorbed: an unclassifiable git invocation exits open by design (§6.2), and the
S3 row is a known unknown, not a handled case.

---

## 9. Security invariants

1. **The store is the only authority.** Never parse PASS/FAIL from terminal output.
2. **No interpolation of untrusted text into a terminal command.** Prompts reach the judge only via
   `prompt.txt`; rungs execute only `bash <run-dir>/run.sh`. This is what removes the AppleScript
   injection surface on **rung 3** (Terminal `do script`) — the one rung that still uses `osascript`
   now that iTerm2 is dropped, and therefore the reason the indirection stays (§6.1).
3. **Validated args and validated file paths only.** Prompts are built from the validated argument set
   in §6.1.2 and the *contents* of files named by validated paths, streamed in as data (§6.1.3). Never
   from raw command text. Contents never reach a shell.
4. **Least privilege.** `--allowed-tools` pinned to each agent's declared list.
5. **Fail closed on inability to verify** — missing python, unreadable store, failed mode assertion.
   Distinct from *classification ambiguity*, which fails open with a log line (§6.2); the two are not
   the same failure and are not treated the same way.
6. **Run dirs are default-deny**: `umask 077`, dir `0700`, files `0600`, asserted after creation
   (§5.1). Gitignoring `coding-memory/judge-runs/` governs committing, not reading, and is a
   supplementary control rather than the mechanism.
7. **Every bypass is logged and attributable.** `SPEC_EXEMPT`, `JUDGE_EXEMPT`, and
   `SPEC_ESCALATION_ACK` all write their value to stderr; none is silent and none is persistent.

---

## 10. Testing

New harnesses `hooks/spec-guard.test.sh` and `bin/judge-launch.test.sh`, alongside the existing
`hooks/judge-guard.test.sh`.

**Falsification is mandatory.** Every regression test must be validated by *mutating the code to
re-introduce the bug class* and confirming the test then fails. This branch's history is the reason:
a lock regression test once planted a PID file with a trailing newline — a state the real writer
cannot produce — so re-introducing the bug still passed 44/44. **Lock tests must plant state exactly
as the real writer produces it.**

**Seams:** `SPEC_VERDICTS_FILE`, `JUDGE_VERDICTS_FILE`, `JUDGE_LAUNCH_MODE=headless` (force a rung),
and a fake `claude` injected on `PATH` that writes canned verdicts — enabling full end-to-end runs
with tiny deadlines and zero token cost.

**Integration cases:** block-with-violations, pass→allowed, `JUDGE_SESSION=1` short-circuit,
`SPEC_EXEMPT` logged bypass, deadline expiry, crash-vs-fail distinction, piggyback-wait, staged-blob
vs worktree divergence.

**Cases the round-2 revisions add, each mapped to the scenario it encodes:**

| Case | Asserts |
|---|---|
| Escalation: same id in two most recent rounds | exit 2 ESCALATE **and no judge spawned** (assert on the run-dir count, not just the exit code) |
| Escalation: stored round ≥ 3 still failing | same, independent of ids |
| Ack releases exactly one launch | judge runs; a second attempt without the ack escalates again |
| Ack is not a waiver | violation still cited, commit still blocked |
| Ack never reaches the judge | id present in `manifest.json`, absent from `prompt.txt` |
| Skill/hook threshold agreement | the two-consecutive and round-3 constants match across `spec-guard.sh` and `running-the-compliance-judge` |
| Precondition: unstaged spec edit on a plain `commit` | exit 2, nothing launched |
| **`git commit -am` with the spec modified, never staged** | gate applies; **written against real git**, not against §7's wording — this exact case passed review twice by being read rather than run |
| `git commit -- <pathspec>`, and pathspec + unrelated staged file | gate applies; effective blob is the worktree hash |
| `--prior-violations-file` is built and passed | round 2 launch carries round 1's array; its absence is what silently disabled the cap in an earlier revision |
| Context/decisions fallback | with no `--context-file`, `prompt.txt` contains the fixed instruction, not an empty section |
| Ack releases the round-3 branch | escalation with no cited ids is released by a set ack |
| Global options `-C` / `-c` / `--git-dir` / `--work-tree` | consumed **and passed through** to the hook's own git calls |
| Unrecognized value-taking global option | exit 0 + warning logged |
| Pre-filter | no python spawn without the substring; **no block decision reachable from the substring** |
| Run-dir modes | `0700` / `0600` asserted; a pre-loosened dir fails preflight (exit 4) |
| File-arg validation | symlink, FIFO, empty, > 64 KiB, non-UTF-8 each rejected |
| Lib size budgets | every file in §6.1.1 within its stated budget |

**Falsification targets for the new logic.** Per the mandate above, each of these is validated by
re-introducing the bug class: count rounds per `spec_blob_sha` instead of per `spec_path` (cap never
fires); persist the ack (escalation never re-fires); let the substring pre-filter decide a block
(bypass returns); drop `-C` pass-through (hook reasons about the wrong repo); **stop passing
`--prior-violations-file`** (ids drift, persistence reads as novelty, the cap silently no-ops);
**revert detection to `git diff --cached --name-only` only** (`git commit -am` walks through the gate).
A test that still passes under its mutation does not count as coverage.

The last two mutations matter most, because both bugs were *present in a reviewed revision of this
spec* and neither was caught by reading it. The `-am` case in particular was found only by running git.

**Spikes — do these first, they gate the design:**

- **S1 [blocking]:** confirm a real `claude -p --agent` run authenticates on subscription auth, and
  that `JUDGE_SESSION=1` exported by `run.sh` reaches the hooks inside the judge session. If the
  guard does not hold, **stop** — without `--bare`, hooks run in the judge session and the design is
  deadlock-shaped.
- **S2 [non-blocking]:** confirm hooks inherit `TMUX` / `TERM_PROGRAM` / `CMUX_WORKSPACE_ID`.
  Undocumented; the headless rung covers a miss, so this bounds visibility, not correctness.
  *Partial evidence, not a result:* a Bash **tool call** in this session does see `CMUX_WORKSPACE_ID`,
  `CMUX_BUNDLED_CLI_PATH` and `TERM_PROGRAM=ghostty` (observed 2026-07-20). A tool call's environment
  is not proven identical to a hook's, so this raises the prior and does not close the spike — the
  measurement is still owed.
- **S3 [blocking]:** register a hook with `"timeout": 900`, make it sleep past that, and observe
  whether the tool call is **blocked or allowed**. All of §6.5 rests on the answer and no hook in this
  repo has ever set an explicit timeout. Record the measured effective cap. If it is below 840s, take
  the §6.5 fork (blocking-and-retrying) before writing the launcher — not after.

Terminal rungs cmux and Terminal are verified by a manual live checklist recorded in the branch log;
only tmux is scriptable, and no automated test exercises a real judge (the fake `claude` on `PATH`
writes canned verdicts). Both limits are accepted, and both are named in §11 rather than implied by
a green suite.

---

## 11. Deferred

- Multi-repo verdict namespacing (writeup filenames carry no repo component) — revisit if cross-repo
  spec slugs collide.
- Chained-command detection (`foo && git commit`) — accepted limitation, consistent with existing hooks.
- Exotic git global options failing open rather than closed (§6.2) — accepted; revisit if a real
  invocation is ever seen slipping the gate.
- **Enforcing the provenance of `SPEC_ESCALATION_ACK`** (§6.4). The hook cannot distinguish a
  user-authorised ack from an agent-fabricated one, so the release is advisory and audited rather than
  prevented. Closing this needs provenance the hook does not have; revisit if the audit trail ever
  shows an ack that no user decision backs.
- **Round counting resets on a spec rename**, because rounds key on `spec_path`. A rename mid-loop
  restarts the count at 1 and clears the cap. Accepted: renames are rare and visible in the store's
  history; keying on content instead would defeat the cap entirely (§6.2.2).
- No automated test exercises a real judge; rungs cmux and Terminal rest on a manual checklist (§10).
- A `spec-guard` equivalent for ADRs and READMEs.

## 12. Documentation obligations

- **New ADR** for this decision (class (a), structural).
- **Update ADR-0003** — its "no script-decidable spec-done moment" deferral is resolved here.
- Update `rules/gates.md` (spec-compliance gate becomes hook-enforced) and both judge skills —
  including the freshness sentence in `running-the-compliance-judge` that §5.2's precondition makes
  true (§6.6).
- **Add `coding-memory/judge-runs/` to `.gitignore`** — verified absent as of this revision, and it
  must land *before* any run dir is written, not alongside the launcher.
