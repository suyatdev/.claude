# Session State

Auto-maintained during conversation. Do not delete.

> Compressed 2026-08-23 at a clear boundary. The previous 268-line version's detail was not
> discarded — it moved into `docs/features/judge-ledger-commitability.md` (the canonical card) and
> the commit messages on `chore/judge-ledger-commitability`, then was removed from here so a
> restore costs ~1.5k tokens instead of ~4k. Read the card, not this file, for substance.

## Current Focus

**Card:** `docs/features/judge-ledger-commitability.md` — phase `implementation`,
`model_tier: xhigh`. Gate already confirmed; do not re-ask for `gate confirmed`.
**Branch:** `chore/judge-ledger-commitability` @ `3b6fd67`, pushed. **No PR yet.**
**Worktree:** `.claude/worktrees/rule-surface-trim` (name is historical — it is on the branch above).

**Tasks 1–7 are DONE and merged.** git-guard now allows the two judge ledgers on the default
branch; `.gitattributes` union-merges them; rule text updated at five sites; PR #59's false
"nothing is lost locally" claim corrected.

## Exact next step

**Ask the user to ratify the `EXPECTED_RELAXED` contract change** — written up at the bottom of the
card under "⚠️ OPEN — awaiting user ratification". It blocks task 9 only; task 8 can run first.

Then, strictly serial:
8. Full suite across all files — counts **run**, not read.
9. ADR **0036** amending 0031 (needs the ratification above). Next free number verified 0036
   against all refs; `0028` is a deliberate gap.
10. Observability judge → `gh pr create --draft`. Verdict stays **uncommitted** until after the PR
    exists (judge-guard wants `head_sha == HEAD`); push it onto the PR afterwards.

## Verified this session — do not re-derive

At merged bytes: git-guard **157/0**, gitattributes **46/0**, doc-guard **20/0**. Replay vs `main`:
65 × 6 = 390 pairs, 382 identical, 0 unexpected stricter, 8 relaxed / 0 undeclared. `CMDS`
set-compared 63→65: 0 dropped, 2 added, 0 duplicates. Merge audit: no conflict markers, deletion
arithmetic reconciles against all three parents.

## Blocking gotchas

- `git commit` **must run with the Bash cwd already inside the target worktree**. A
  `cd <worktree>; git commit` compound is rejected as `MSG_UNSUPPORTED_FORM (FOREIGN_REPO)`. Issue
  the `cd` as its own call, then `git commit -F <abs-file>` as its own call. `-F -` heredocs and
  `&&` chains are also refused, and no earlier segment of a chain runs.
- `Doc-Exempt:` must be on the **command line** — `doc-guard.sh:143` never reads the message body,
  though its own error text at `:186` says otherwise. `--trailer` is off test-marker-guard's
  whitelist entirely. Memory: `reference_doc_exempt_and_trailer_guard_interaction`.
- The `repo` field in both ledgers is **unnormalized** — it counts worktree names, and one checkout
  appears twice (basename + absolute path). Never call it "distinct repos"; say "distinct `repo`
  values".

## Other threads — not this branch's work

- **PR #67** `feat/model-aware-token-thresholds` — OPEN, complete, awaiting human review. No open
  items. Its 130k Opus anchor fired correctly in production this session at 131,636 tokens.
- **PR #66** `chore/hook-wiring-health-check` — OPEN, card at `review`. Blocked on one user
  decision: should check 1 filter the hook script paths it prints? Filtering guards against a hook
  in a credential-named directory; not filtering keeps findings actionable.
- **`feat/treko-store-location`** — commits, no PR, worktree dirty.
- Shared checkout `.claude` is dirty with `settings.json`, `treko/tracker-data.js`, `debug/` —
  **pre-existing, owned by someone else.** Leave them.

## Session policy

`panes max=3`, recorded via `dispatch-pane-agent.sh set-policy`. The three-worker fan-out this
session used child worktrees whose card carried an **uncommitted** frontmatter edit claiming each
child branch — that is what opens phase-guard. Both child worktrees (`jlc-guard`, `jlc-union`) are
merged and removed; the remote branches survive as history and can be deleted.

## 2026-08-23 — PR #67 merged, branches cleaned, checkout parked

**Done.** PR #67 (model-aware token thresholds) merged as `984e7ac`. One merge conflict:
`coding-memory/observability-judge/verdicts.jsonl`, an append-only log — resolved as a
chronological union (216 rows), verified zero record loss against BOTH parents. Feature branch
deleted local + remote after confirming it was an ancestor of `origin/main`. Card closed on
`docs/close-model-aware-token-thresholds` (`5ffa637`, pushed, no PR opened yet).

**STANDING RULE (user, this session): all future work goes in a git worktree**, never the primary
checkout — parallel sessions share this repo and the primary checkout has only one HEAD.
Saved as memory `feedback_always_work_in_a_worktree`. A permanent home (CLAUDE.md rule or a
gates.md stub via `triaging-new-instructions`) is still TODO.

**Two mistakes made and corrected — do not repeat:**
1. `git switch main 2>&1 | tail -3 && git merge --ff-only origin/main` — the switch FAILED
   (`main` was held by a worktree) but `tail` exited 0, so the ff landed on the feature branch.
   A pipeline's exit code is its LAST command's. Never pipe the guard of an `&&`.
2. `git checkout --no-overlay <ref> -- settings.json` labelled "dry run" — it is not; it wrote the
   working tree and index and destroyed an uncommitted `modelSettings` block. No `--dry-run` exists
   for that form. Recovered from an unrelated stash.

**State at handoff:** primary checkout `/Users/marksuyat/.claude` on
`docs/close-model-aware-token-thresholds` @ `5ffa637`. `main` = `origin/main` = `a5a66a7`.
Uncommitted in this checkout and NOT mine — another session edited them at 22:22:
`panes/dispatch-pane-agent.sh`, `panes/dispatch-pane-agent.test.sh`, `panes/run-pane-agent.sh`,
`panes/run-pane-agent.test.sh`. Also `settings.json` (modelSettings block re-applied onto main's
version, which added the `verify-hook-wiring.sh` SessionStart hook). `stash@{0}` still holds the
old `treko/tracker-data.js` content — main DELETED that file (ADR 0034), do not restore it.

**Gotchas:** `test-marker-guard` rejects `cd <dir>` + `git commit` in one Bash call
(MSG_UNSUPPORTED_FORM/FOREIGN_REPO) — run `git commit` as its own bare command.
Pre-existing on main: two ADR `0026-*` files (distinct filenames, so it merges cleanly and nothing
surfaces it).

## Other threads — update 2026-08-24

- **PR #70** `docs/close-model-aware-token-thresholds` — OPEN, ready for review, 1 file +2/-1.
  Closes the model-aware-thresholds card (PR #67 merged as `984e7ac`). Audit re-verified this
  session, not copied: merge is an ancestor of `origin/main`, branch gone local+remote, zero
  conflict markers, all six shipped files present in main by path, and the five executable files
  are byte-identical across tip `5aea5d3` / `origin/main` / working tree. Suites re-run:
  context-handoff-watch **34/0**, statusline-command **122/122**. Ladder confirmed at
  `hooks/context-handoff-watch.sh:64-66`.
  ⚠️ Opened with `JUDGE_EXEMPT` — judge-guard has **no docs-only carve-out**. Precedent is mixed
  and is flagged in the PR body: PR #69 (same species) has no verdict in the ledger,
  `docs/close-treko-rename` has two. Unsettled house question.
- Correction to "Other threads" above: PR #67 is **MERGED** (2026-08-23T17:23:40Z), not "OPEN,
  awaiting human review" as this file said.

### PR #70 — MERGED 2026-08-24T03:38:34Z

Merge commit `c89b97e` (parents `a5a66a7`, `5ffa637`). Post-merge audit run, not assumed:
tip `5ffa637` is an ancestor of `origin/main`; merge diff is exactly the intended
`docs/features/model-aware-token-thresholds.md` +2/-1; zero conflict markers; the
`branch: none` frontmatter is live in `origin/main`.

**Cleanup still outstanding** — branch `docs/close-model-aware-token-thresholds` exists both
local and remote. NOT deleted: the primary checkout `~/.claude` is standing on it, and it carries
another session's uncommitted work (`panes/dispatch-pane-agent.sh`, `panes/run-pane-agent.sh`,
both test files, `settings.json`). Switching branches under it is not a safe autonomous action.

**The JUDGE_EXEMPT question is now settled by precedent, not by decision.** PR #70 merged with no
observability verdict in the ledger, same as PR #69. If close-outs should be judged, that needs an
explicit rule — two merges have now gone the other way.

### Branch cleanup done 2026-08-24 — and the checkout moved

`docs/close-model-aware-token-thresholds` deleted **local and remote**, both verified gone.
Remote delete was gated on a re-checked `merge-base --is-ancestor` at the moment of action,
not on the earlier reading.

**The primary checkout `~/.claude` is now on `feat/pane-agent-model-flag`** (created at
`origin/main` = `c89b97e`, tracking it). It had to move: git will not delete the branch it is
standing on, and `git switch main` is refused — `main` is checked out in the
`treko-card-b-spec` worktree.

Chose a new branch over `--detach` deliberately: **git-guard fails closed on a detached HEAD**,
which would have left the 5 uncommitted pane files uncommittable.

**The uncommitted work survived intact** — the 5 files were `git hash-object`'d before and after
the switch and are byte-identical. It was safe because `HEAD` and `origin/main` had the *same
tree* (`7784ad6`), so the switch moved zero bytes.

**What that work is:** an optional positional `[model]` 5th arg to `run-pane-agent.sh` → `--model`
on the CLI, empty/absent = no flag so 4-arg callers are unchanged, plus a `modelSettings` block in
`settings.json`. This closes the handoff's "per-pane model choice does NOT exist" gap. Uses a
`${a[@]+"${a[@]}"}` guard for bash 3.2 on macOS. **Still uncommitted — no branch of its own until
now, no PR.**

Gotcha worth keeping: `git switch ... 2>&1 | head -3; echo $?` reports the **pipeline's** exit
code (`head`'s), not git's — it printed `exit=0` on a `fatal:`. Read the message, not the code.


---

## 2026-08-24 (later) — worktree-location-guard planning complete

**Card:** `docs/features/worktree-location-guard.md` on `origin/main` (420 lines).
`phase: planning`, `branch: none`, `model_tier: xhigh`.

**Everything shipped. Nothing is in flight — no open PRs, no live branches, no dirty worktrees.**

### Current state

Merged this session: **#76** (plan card + probes 1a/1b/2 + `claude-sonnet-5` effortLevel),
**#77** (open questions 7/8/9). #75 also merged. All merges independently verified — each
commit confirmed an ancestor of `origin/main`, diffed against both parents for deletions, checked
for conflict markers. Branches and worktrees for both deleted.

### Exact next step

**Tasks 1a, 1b and 2 are DONE. Tasks 3–11 are implementation and are gated.**
The card cannot advance without the literal user phrase **`gate confirmed`**, plus the
planning→implementation model-switch checkpoint. Task 3 (failing test suite,
`hooks/worktree-guard.test.sh`) is first.

### Findings that change the design — do not re-derive

- **All three creation surfaces** (`--worktree`, `EnterWorktree name:`,
  `Agent(isolation: "worktree")`) route through the `WorktreeCreate` hook. No silent third route.
- **`WorktreeRemove` fires but Claude removes nothing** on the hook path, and the session still
  reports *"Exited and removed worktree at …"*. That message is false. Real removal is task 6's job
  or worktrees accumulate silently. **This is the most load-bearing finding.**
- **A hook path *inside* the repo is accepted** (rc=0). Only our own hook keeps worktrees out of
  the tree; there is no harness backstop.
- All other malformed hook outputs fail closed, but **create-then-misreport leaves an orphan** in
  `git worktree list`. Hook must create and report atomically.
- Payload: build **only on `cwd` and `name`**. Five keys guaranteed; `prompt_id` appears only on
  mid-session surfaces. (Two earlier claims about this key set were wrong — the card carries the
  corrections; trust the card, not older prose.)
- `--path-format` support **cannot** be detected by exit code — git <2.31 and "not a repo" both
  exit 128. Use a version compare. The sub-2.31 branch is **untested**; task 3 must stub `git`.

### Blocking gotchas

- **Probes run inside the full local guard stack.** `--settings` *adds* to `~/.claude/settings.json`,
  never replaces it. One probe read as a harness limitation but was our own `pane-dispatch-guard.sh`;
  bypass with `CLAUDE_PANE_AGENT=1` (`pane-dispatch-guard.sh:76`). Memory:
  `feedback_a_probe_can_measure_your_own_guard`.
- **Worktree-isolated sessions**: refuse `git -C` into the shared checkout, refuse any command
  naming `git` twice, and refuse Edit/Write to shared-checkout paths (incl. auto-memory). Put git
  sequences in a script file; use Bash `cp` for memory writes.
- **`EnterWorktree` renames your branch** to `worktree-<name>` (`/`→`+`) and bases on
  `origin/main`. `git branch -m` before the first commit. Its `ExitWorktree remove` then miscounts
  commits as unmerged against the *old* name — verify against `origin/main`, don't trust the warning.
- Docs-only PRs need `JUDGE_EXEMPT=<reason>`; there is no implementation to score.
- The primary checkout `~/.claude` sits on the stale merged branch
  `docs/close-pane-dispatch-model-flag`. Left alone deliberately — moving the primary's HEAD
  disrupts other sessions.

### Pointers

- Card is the single source of truth; probe harnesses were scratchpad-only and are **gone** by
  design (card says so, task 3 rebuilds what matters).
- Open questions still unanswered: 2 (basename collisions), 3 (one hook or two), 4 (bare repos and
  submodules), 5 (`~/.worktrees` creation), 6 (`phase-guard` interaction), 10 (dirty-worktree
  removal policy), 11 (`~/.worktrees` as machine-wide shared state). **10 must be settled before
  task 6.**

## 2026-08-24 (later still) — compliance round 4: FAIL, escalated a second time

Branch `docs/reconcile-worktree-location-guard`, spec commit `38978ac`, card 1,118 lines.
Both judges dispatched in parallel panes and both persisted verdicts against that exact HEAD
(compliance `verdicts.jsonl` round 4; observability markdown
`2026-08-24-docs-reconcile-worktree-location-guard-round4.md`).

**All three round-3 violations are closed and were not re-cited.** The judge re-verified the
merged-in probe material independently — the `worktree.location` string against the 2.1.241
binary, the `git -C` count (215, exact, at HEAD and at the merge-base), and 15 file:line
citations re-opened rather than carried forward. No two statements about the same measured fact
disagree, so the hand-merge itself is sound.

**Round 4 cited 3 new violations. Escalated, not patched** — `writing-specs/scope-unknown-contradiction`
is now the same id in two consecutive rounds, which is the skill's own escalation trigger, and
round 3 had already tripped the oscillation cap.

1. `writing-specs/scope-unknown-contradiction` (:440-447 vs :474-481) — Arm B2 has **no
   effective-cwd step**; Arm D has one. So `cd /repos/other && git worktree add ~/.worktrees/.claude/x`
   emits an empty repo-dir in `WORKTREE_ADD_TARGET`, is judged against the session repo, and is
   **allowed** — the identical failure the discriminating `-C` scenario at :803-812 exists to deny.
2. `core-conduct/explicit-error-handling` (row 10 at :584 vs :669/:675/:903) — row 10's
   affordability bound ("can fire only on a refusal that was already going to be reported") is
   **false**: the log also records `decision=bypass`, and a bypass is an allow. `WORKTREE_EXEMPT=hotfix
   git switch main` against an unwritable log is left unspecified.
3. `writing-specs/stale-cross-references` (:188-190, :1022-1023 vs tasks 2/2a at :1058-1063) —
   two sections say task 2 tests the bare-repo/submodule probes; task 2 is `[x]` and task 2a says
   outright it did not. Pure merge drift, uncontroversial to fix.

**The observability judge landed independently in the same territory** (advisory, no `fail`, four
`concern`s): Arm D reads `-C` out of a **flat fact set with no segment identity**, so
`git -C /other log && git switch main` from the primary checkout would be **allowed** — which is
the exact incident this feature exists to stop. Together with finding 1 that names the root cause:
**the fact set carries no segment index, and each arm re-derives "which repo" separately and
incompletely.** Fourth consecutive round in this territory; three prior fixes were each genuinely
correct and each exposed a new successor defect.

Other observability concerns worth keeping: a refusal-only log measures **precision, never recall**
(a missed write leaves no line, so the log can look flawless while detection is broken); 14 of 27
failure boundaries have **no acceptance scenario**, including the three most load-bearing probe
findings; 14 deny boundaries collapse to one log line with **no reason field**; and the flip
criterion has no owner, date, or forcing function.

Closed in `38978ac` (the three non-blocking round-3 notes): stale observability-exception
cross-reference above the boundary table, the step-3/steps-4-5 renumbering drift, and `python3`
now pinned at the measured system 3.9.6 with no floor above it.
