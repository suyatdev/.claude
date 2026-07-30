# Observability verdict — `phase-guard.sh` design, round 3 (architecting)

- **Repo:** `phase-guard-hook` (worktree of `~/.claude`)
- **Branch:** `worktree-phase-guard-hook` @ `2017dea1aba3ab968e67834b5e9c2994a18b3ccc`
- **Stage:** `architecting`, **round 3** — advisory, does not gate
- **Design judged:** `docs/features/phase-guard-hook.md` (824 lines, was 732)
- **Diffed against:** `1befe03` (+138 / −46 in the spec)
- **Timestamp:** 2026-07-25T22:34:23Z
- **Verdict:** risk `medium`, confidence `high` — no `fail`. All six round-2 items are genuinely
  closed. Risk holds at `medium`, not because the old problems came back, but because closing them
  opened four new ones, three of which are empirically demonstrable and would bite an implementer
  working under a frozen checklist.

---

## What was changed

Still nothing built. This is a design document, now on its third review pass.

The thing being designed is a **safety catch on a traffic light**. Every feature in this repo has a
planning document whose first lines say `phase: planning`, `phase: implementation`, or
`phase: review`. That is the light. Today the light exists but nothing is wired to it — a session
can be told "you're still planning" and write production code anyway. `phase-guard.sh` is the
wiring: a script the editor runs *before* every file write, which refuses the write while the light
is red.

Its best idea is unchanged: it never tries to work out *which* feature a file belongs to. It asks
the easier question — **does the branch I'm on have permission?** Branches only get created when a
gate opens, so sitting on an unclaimed branch while a red light exists is itself the signal.

Round 3 did six things, all of them requested by round 2, and I checked each one:

| Round-2 finding | Round-3 response | Genuinely closed? |
|---|---|---|
| Flag store unspecified | New seven-row "Flag contract" table | **Yes** — but see F1 |
| Tasks 1/4/5 unbuildable, examples double-assigned | List re-sequenced 13 → 16 with a preamble | **Partly** — see F2 |
| Task 13 dogfood unsatisfiable; task 10 ambiguous | Task 16 uses a throwaway `git init` repo; task 13 names `~/.claude/settings.json` | **Yes**, with a residual — see F4 |
| Sticky supersession undisclosed | New paragraph, "hard to fool and easy to disarm" | **Yes** — clean, honest |
| Two overstated claims | One corrected, one **withdrawn** | **Yes** — and see F1 |
| ~44ms vs a ~50ms threshold | Restated as a budget, ≤60ms / ≤15ms, measured by task 16 | **No** — see F3 |

## Does it do what you wanted?

The revisions are real engineering, not paperwork. Two of them are genuinely admirable:

- **The withdrawal.** Round 2 caught the claim that "`git-guard.sh` and `doc-guard.sh` still stand
  between that write and a commit." Round 3 didn't patch it — it **deleted** it and said why, in the
  document, permanently. I verified the underlying fact: `git-guard.sh:67-70` defines `on_main()`,
  and it is the only gate on both the commit block (`:90`) and the force-push block (`:82`). The
  claim really was false on isolation branches. Deleting a load-bearing reassurance rather than
  rescuing it is the right instinct and it should be said out loud.
- **The new `cat-file` framing claim is correct.** Round 3 added: a present blob emits
  `<sha> blob <size>\n`, then exactly `<size>` bytes, **then a trailing `LF`** that is framing, not
  content. I probed it byte-for-byte in a throwaway repo (`od -c`) and it is exact — including that
  a missing object echoes its request verbatim followed by ` missing`. A parser that reads `<size>`
  bytes and stops really would desynchronise on record two. That warning will save someone a day.

The task re-sequencing also did most of what it promised. A1's ten examples are now assigned exactly
once each (1–5 → task 1, 6 → task 3, 7–10 → task 7), and Group B's six scenarios partition cleanly
across tasks 3 and 7. The double-assignment defect is genuinely gone.

## What could go wrong / what I'm unsure about

**F1 — The correction traded one false claim for a different false claim, and the true precedent
went unread.** Round 3 says, to justify writing the Flag contract from scratch:

> "`pane-dispatch-guard.sh:43-50` **reads** a session flag; the **writer** is
> `panes/dispatch-pane-agent.sh:71`, and **no hook in this repo writes session state today.** This
> is therefore new ground and must be specified, not borrowed."

The first half is right (I confirmed both line numbers). The bolded half is **wrong**.
`hooks/context-handoff-watch.sh:42-43` is a hook, on `PostToolUse` matcher `*` — the hottest path in
the system — and it does exactly this:

```
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
: > "$flag"
```

That is a once-per-session flag, written by a hook, keyed by session id, in a
`${ENV_VAR:-$HOME/...}` store. It is a near-perfect precedent, and the design concluded it did not
exist. The cost is not pedantic — the house already answered three of the Flag contract's seven rows
the *other* way, and the design overrides all three without knowing it is overriding anything:

| Question | House precedent | phase-guard chose | Argued against? |
|---|---|---|---|
| Store unwritable | `context-handoff-watch.sh:42` — **exit silently**, print nothing | **print, then continue** | No — believed novel |
| Stale flags | `dispatch-pane-agent.sh:33-36` — `find -mtime +N -delete`, added as an "obs r2 residual" | **no cleanup at all** | No |
| Where to check the flag | `context-handoff-watch.sh:9` — "**ORDERING IS LOAD-BEARING**", flag checked *before* any expensive work | checked at steps 4 and 7, *after* git and python have already run | No |

I actually think print-and-continue is the **better** choice here — a guard that silently loses its
own audibility is round 1's bug one level up, and the design says so. But it is now the only place
in the repo that behaves this way, it diverges from a sibling that made the opposite call on
observability advice, and the divergence is undocumented because the sibling was never found.

**F2 — Two of the sixteen tasks still cannot be completed as written.** This is the same class of
defect round 3 set out to fix, and it matters disproportionately because the checklist freezes at
the gate.

- **Task 3 asserts the full deny-message contract; task 4 is scoped to produce a bare exit 2.**
  Task 3 writes Group B row 1, which asserts `stderr names docs/features/a.md, names branch main,
  gives both fixes, and states that no bypass env var exists` — all four required elements. Task 4
  is "**minimal** steps 7/9/10: find `phase: planning`, read the branch, deny. **Green for task 3.**"
  A minimal deny cannot satisfy four message elements. The implementer's outs are (a) build the full
  message at task 4, which makes task 12 a no-op and puts task 11's test *after* its implementation
  — inverting the test-first rule the task preamble insists on — or (b) quietly loosen task 3. Both
  are the failure round 2 described. The same dependency hits tasks 5/6, whose A3 scenarios assert
  `stderr names good.md` and `does not name bad.md`.
- **One A3 scenario contradicts the design's own order of operations.** This one is a flat
  unsatisfiable:

  ```gherkin
  Scenario: a missing branch: key means unclaimed, not malformed
    Given docs/features/a.md has phase: implementation and no branch: key
    And the current branch is feat/a
    Then the hook exits 2
  ```

  Step 7 says: *"Collect `planning_files`; empty → ⊘."* The only file is at `implementation`, so
  `planning_files` is empty and the hook **allows**. The scenario needs a second file at
  `phase: planning` to trigger any deny at all. As written the spec asserts a deny and the algorithm
  produces an allow. It survived three rounds and two judges; it sits in frozen task 5; and its
  likely resolution under a freeze is to loosen the test rather than notice the Given is incomplete.

**F3 — The new performance budget is already breached, and the prescribed fix targets the wrong
cost.** Round 3's critique of the old threshold was exactly right — "a threshold that trips
immediately is not a threshold." It then raised the numbers (50 → 60ms guarded, implicitly 9 → 15ms
non-opted-in) **without re-measuring**, and the new numbers trip immediately too. I built a proxy of
the spec's order of operations and measured on this machine, under the concurrent-session load this
setup normally runs under:

| Path | Budget | Measured |
|---|---|---|
| Guarded write, opted-in repo (7 branches, 1 feature file) | ≤60ms | **58.9 / 60.2 / 62.4ms** (3 runs) |
| Non-opted-in repo — *every write in every repo on the machine* | ≤15ms | **18.1ms** |

The non-opted-in figure is the decisive one, because it has no headroom by construction. Its
irreducible floor is two operations the design mandates before its own step-3 early exit:

```
bash process spawn                 5.2ms
git rev-parse --show-toplevel     10.0ms
                                 -------
floor                             15.2ms   ← already over the 15ms budget
```

Per-stage breakdown of the guarded path (25–40 iterations each):

| Stage | ms |
|---|---|
| `python3` startup + `json.load` | **22.7** ← largest single cost |
| `cat-file --batch` stage | 23.4 |
| `git rev-parse --show-toplevel` | 10.0 |
| `git rev-parse --abbrev-ref HEAD` | 8.8 |
| `git for-each-ref` | 8.7 |
| bash spawn | 5.2 |
| `awk` frontmatter scan | 4.0 |

And the remediation the spec names — *"switch step 8 to `cat-file --batch-check` and read only the
blobs whose size warrants it"* — **would recover almost nothing.** I measured the streaming cost
directly by scaling the request set against the real 55KB feature file:

| Feature files per branch | Request lines | `cat-file` stage |
|---|---|---|
| 1 | 7 | 23.4ms |
| 5 | 35 | 23.8ms |
| 10 | 70 | 23.5ms |
| 20 | 140 | **27.0ms** |

Twenty times the streaming volume — 7.7MB — costs **3.6ms**. The cost is process startup, not bytes.
So the spec's central worry ("grows linearly as this workflow succeeds and feature files accumulate")
is **empirically false at any realistic scale**, and its stated fix aims at the 15% that doesn't
matter while ignoring the 23ms Python interpreter that does. An implementer who reaches task 16,
finds the budget blown, and applies the prescribed fix will still be over budget with no sanctioned
alternative.

*Honest caveat:* my proxy is not the hook, which does not exist. It omits the flag `stat`, the
relativization, and deny-message construction (all cheap), and adds one pipeline subshell. Round 2
measured 44/9ms on a quieter machine. The floor argument, however, does not depend on my proxy at
all — `bash` + one `git rev-parse` is 15.2ms and both are mandatory.

**F3b — the budget contradicts the spec's own reasoning about timing tests.** Group C rejects a
wall-clock assertion in as many words: *"a timing threshold is flaky on a loaded machine and would
be the kind of test that gets deleted the first time CI goes red for an unrelated reason."* Task 16
then makes a wall-clock threshold an acceptance criterion for the whole feature. The document argues
both sides of one question, one page apart. My 58.9–62.4ms spread across three consecutive runs of
the same script is the flakiness it predicted.

**F4 — Two tasks instruct actions the workflow this feature exists to enforce forbids.** Task 16
says: *"delete the path if it blocks"* (Rollback path 3) and, for the budget, *"switch step 8 to
`cat-file --batch-check`."* Both edit the Design/Spec sections of the canonical feature file. The
phase gate at `rules/gates.md:5` states **"implementation forbids spec and checklist edits."** By
task 16 the phase is `implementation`. The first feature to run under this workflow prescribes two
tasks that violate it — which is precisely the dogfooding friction the file was opened to catch, and
it is currently uncaught.

**F5 — The new flag store is untracked runtime state landing inside the repo, and nothing ignores
it.** This repo *is* `~/.claude`, so `$HOME/.claude/hooks/state/` resolves to `<repo>/hooks/state/`
— beside the tracked hook scripts. I checked `.gitignore`:

```
$ git check-ignore -v panes/state/foo
.gitignore:13:/panes/state/	panes/state/foo          ← the precedent IS ignored

$ git check-ignore -v hooks/state/phase-guard-nopython-abc
(no match)                                               ← the new one is NOT
```

`.gitignore:11-13` even carries a comment explaining exactly why `panes/state/` is ignored
("machine-local, never committed"). The Artifacts table calls the flag files "runtime, untracked",
but no `.gitignore` line is specified and **no task adds one** — and the list freezes at the gate.
Combined with the deliberate "Cleanup: none", these files accumulate forever, in `git status`,
inside a directory people `git add` wholesale. One line in `.gitignore` fixes it; there is currently
nowhere for that line to come from.

**F6 — Task 13's registration has no clean revert point.** It now correctly names
`~/.claude/settings.json` and warns that a concurrent session may hold it. But that file is the
*primary checkout's working copy, on a different branch*. Committing the registration on this
feature branch does not make the hook live; editing the primary checkout's file makes it live but
puts the change outside this feature's branch, PR, and revert. The spec notes the hazard without
resolving it, and `core-conduct.md`'s parallel-agent invariant ("never touch files outside your
assigned feature domain") points the other way. Either the PR merges a hook that was never
registered, or the registration lands somewhere `git revert` on this PR cannot reach.

**F7 — Carried over from round 2, unfixed:** task 14 still reasons about "a 26th bullet" in
`rules/gates.md`. I re-counted: **18**. The argument is sound, the number is decorative and wrong,
and it was flagged last round.

**F8 — Prior-art table still has two omissions**, and one is now directly relevant. `settings.json`
already registers `$HOME/.claude/hooks/handoff/post-edit-hook.sh` on `PostToolUse` matcher
**`Edit|Write|NotebookEdit`** — the identical matcher this design adds on the Pre side. It is the
closest living relative of the proposed hook and appears nowhere in the document.
`hooks/checkpoint-before-modify.sh` (executable, 6.9K, registered nowhere) is still absent too.

**One round-2 concern I now think was overstated, in the design's favour.** Round 2 warned that
`.claude/*` being unguarded swallows this repo's worktree trees. Because step 2 uses
`git rev-parse --show-toplevel`, a session working *inside* a worktree resolves to the worktree root
and its files relativize to `hooks/x.sh` — guarded. I confirmed `--show-toplevel` returns the
worktree path from here. The hole only opens for a path reaching *into* a worktree from the primary
checkout, which is not the normal case. Narrower than I said; worth one line, not a redesign.

## What I'd double-check before merging

"Before merging" here means **before the gate opens and the checklist freezes** — after that, most
of these become expensive or forbidden.

1. **Fix the A3 "missing `branch:` key" scenario** — add a second file at `phase: planning` to its
   `Given`, or change the assertion to exit 0. It currently asserts the opposite of what step 7 does.
2. **Move the deny message earlier, or split task 3.** Either fold the four-element message into
   task 4 and delete tasks 11–12, or strip task 3's stderr assertions down to exit-2 only. Pick one;
   the current pairing cannot be satisfied and the freeze makes it costly to discover at task 4.
3. **Re-measure the budget before committing to it, or drop it to a recorded observation.** The
   ≤15ms non-opted-in figure is below the design's own floor (bash + one `git rev-parse` = 15.2ms
   measured). If the budget stays, name the real lever — the ~23ms Python interpreter, not
   `--batch-check`, which I measured as worth ~3.6ms across a 20× scale increase.
4. **Read `hooks/context-handoff-watch.sh:42-43`** and either adopt its unwritable-store behaviour
   or say in one sentence why phase-guard diverges. Delete the "no hook in this repo writes session
   state today" claim — it is false, and this document's credibility is its main asset.
5. **Add the `.gitignore` line for `/hooks/state/`** to a task now, mirroring `.gitignore:13`.
6. **Decide task 13's registration story end to end** — is the `settings.json` change committed on
   this branch, applied to the primary checkout, or both? Say how it is reverted.
7. **Resolve F4** — tasks 16's "delete the path" and "switch step 8" are spec edits during
   `implementation`. Either pre-authorise them in the feature file or move them to a review-phase
   task.
8. Trivia: fix "26th bullet" → 18; add `post-edit-hook.sh` and `checkpoint-before-modify.sh` to
   prior art.

**Is the design ready to put in front of a human for the build/defer decision?** The *thinking* is —
the core reframing is sound, the honesty is above average for this repo, and the residual risks are
all disclosed. The *task list* is not yet safe to freeze: items 1, 2 and 5 above are concrete defects
that a frozen checklist converts from five-minute edits into workflow violations. My recommendation
is one more surgical pass over the Tasks and the budget — not another full round.

---

## Dimension scores

| Dimension | Score | Basis |
|---|---|---|
| `intent` | pass | All six round-2 items substantively addressed, each verified against the text and against the repo. The sticky-supersession disclosure and the withdrawn layering claim are exemplary. |
| `execution` | concern | No code, no test command. Task 3/4 deny-message pairing unsatisfiable; one A3 scenario contradicts step 7; task 16's acceptance criterion fails on measurement. |
| `trajectory` | pass | Reasoning remains strong — withdrawal over repair, budget-with-a-task over a dead threshold, the trailing-`LF` catch. Marked down in spirit, not score, by F1: a correction that introduced a new false claim and missed the true precedent. |
| `regression` | concern | Global `PreToolUse` on every write; both budget arms measured over on this machine; new untracked state dir inside the repo with no `.gitignore` entry and no cleanup; cross-checkout `settings.json` registration. |
| `context_budget` | pass | `rules/gates.md` amended in place at `:5` (verified), no new always-on bullet. 824-line feature file is a heavy per-restore read but is on-demand, not always-on. |
| `traceability` | pass | Still exceptional — every round-3 edit tagged to a numbered finding with the citing rubric, corrections attributed by round, blob SHAs recorded. Blemishes: F1's false claim, F7's wrong bullet count. |
| `success_masking` | concern | Wall-clock budget is an acceptance criterion the spec elsewhere calls flaky (58.9–62.4ms across 3 runs); task 3 duplicates task 11's assertions so task 12 becomes a green no-op; the contradictory A3 scenario will most likely be "fixed" by loosening the test. |
| `intent_drift` | pass | +138/−46, every addition traceable to a numbered finding. No new dependencies; toolchain pinned with dialect constraints; the `git` row correctly restored after being dropped in round 2. |
| `checkpoint` | concern | Task 16's throwaway-repo fix is a genuine improvement and resolves rollback path 3. Residual: task 13's registration lands outside this branch's revert scope; tasks 16's two "if it fails, change the spec" instructions are forbidden during `implementation` by `rules/gates.md:5`. |
| `audit_trail` | pass | Task 15 writes ADR 0011 amending 0010, now including sticky supersession. Judge rounds preserved in-file with blob SHAs and per-item checkboxes. |

**Roll-up:** risk `medium`, confidence `high`. No `fail`; 4 `concern`, 6 `pass`.

Confidence is `high` because every load-bearing claim below was executed, not read.

## Empirical checks performed

| Claim | Result |
|---|---|
| `context-handoff-watch.sh:14` uses the `${PANE_STATE_DIR:-...}` shape the Flag contract mirrors | **Holds** — exact line |
| `pane-dispatch-guard.sh:43-50` only *reads* the flag; `dispatch-pane-agent.sh:71` writes it | **Holds** — round 3's correction is accurate |
| `nosession` is "the siblings' fallback" | **Holds** — `dispatch-pane-agent.sh:70` `${CLAUDE_CODE_SESSION_ID:-nosession}` |
| **"No hook in this repo writes session state today"** | **FALSE** — `context-handoff-watch.sh:42-43` does exactly that, with the opposite unwritable-store behaviour |
| Sibling flag stores have no cleanup | **FALSE** — `dispatch-pane-agent.sh:33-36` deletes state older than `STALE_DAYS`, added as an "obs r2 residual" |
| `$CLAUDE_CODE_SESSION_ID` is present in this environment (the `nopython` key) | **Holds** — `3805bfe2-…`; the `nosession` degenerate path is rare |
| `hooks/state/` is covered by `.gitignore` | **FALSE** — `panes/state/` is ignored at `.gitignore:13`; `hooks/state/` matches nothing |
| `cat-file --batch` blob framing = `<sha> blob <size>\n`, `<size>` bytes, **trailing `LF`** | **Holds** — verified byte-for-byte with `od -c` |
| `cat-file --batch` missing form echoes the request verbatim + ` missing` | **Holds** |
| `git-guard.sh` guards `main`/`master` only (the withdrawn claim) | **Holds** — `on_main()` at `:67-70`, sole gate at `:82` and `:90` |
| `doc-guard.sh:149` is the source/doc classification | **Holds** — exact line |
| `settings.json` `PreToolUse` has exactly 3 matchers, so this is a 4th | **Holds** (`Bash`, `Task\|Agent`, `*`) |
| `PostToolUse` already carries an `Edit\|Write\|NotebookEdit` matcher | **Holds** — `handoff/post-edit-hook.sh`, absent from prior art |
| `rules/gates.md:5` is the `Phase gate` stub (task 14) | **Holds** |
| `rules/gates.md` bullet count ("26th bullet") | **18** — unchanged since round 2 |
| A1's 10 examples each assigned exactly once across tasks 1/3/7 | **Holds** — the double-assignment defect is genuinely fixed |
| Group B's 6 scenarios partition across tasks 3 and 7 | **Holds** |
| A3 "missing `branch:` key" scenario is satisfiable | **FALSE** — asserts exit 2; step 7 yields empty `planning_files` → allow |
| Guarded hot path vs. the new ≤60ms budget | **58.9 / 60.2 / 62.4ms** — at or over, 3 runs |
| Non-opted-in path vs. the new ≤15ms budget | **18.1ms**; floor of bash + `rev-parse` alone = **15.2ms** |
| "Cost grows linearly as feature files accumulate" / `--batch-check` is the fix | **Effectively FALSE** — 20× the streaming volume (7.7MB) costs **+3.6ms**; the cost is process startup (`python3` = 22.7ms) |
| `.claude/*` exemption swallows worktree trees (round-2 finding) | **Overstated** — `--show-toplevel` resolves to the worktree root from inside it |
