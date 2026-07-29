# CODING_MEMORY

This is an index only, kept at or under 200 lines. Full history lives in `coding-memory/` — follow the
pointers below for detail instead of reading everything here. See `managing-session-memory` for
how this file and its linked files should be written (plain language, major changes only).

## Active Session
- **CURRENT: `phase-guard-hook` — REVIEW. Gate opened 2026-07-26; all 17 tasks done 2026-07-28.** The user answered
  **Q1 = build** with the literal phrase `gate confirmed`, which deliberately overrides ADR 0010's
  "build only when a skipped gate is observed" deferral — **task 16's ADR 0011 must record that
  override**, it is the whole reason that task exists. Model-switch checkpoint ran at the gate:
  **stay on Opus 5**, so `model_tier: high` is unchanged and deliberate — the risk sits in tasks
  9/10 (the asymmetric `cat-file --batch` parser) and the 8 fail-open exit paths, where a wrong
  exit code silently locks the repo.
  Implementation branch is **`feature/phase-guard-hook`**, forked from `worktree-phase-guard-hook`
  at `7936d80` so it carries every spec commit. The old branch was worktree isolation only and is
  now inert; do not add commits to it. Same worktree, `.claude/worktrees/phase-guard-hook`.
  **All 17 tasks are done (through `effae64`); the hook denies with the full four-element
  message, step 7 enforces the whole frontmatter contract, step 8 filters superseded files in one
  subprocess, both audible fail-opens speak once per session, the flag store is `.gitignore`d, the
  `PreToolUse` block is committed, and the `Phase gate` stub documents it.** Suite **80/0** (re-run after 14), siblings
  green (19/17/5/14), `shellcheck -x` clean, hook 318 lines. Task 12's falsification is **done** —
  8 mutations against copies, every one caught, table in the checklist annotation.
  · **13 done** (`209700d`) — `/hooks/state/` at `.gitignore:17` with its mirrored comment;
  `git check-ignore` matched nothing before and reports `:17` after.
  · **14 done** (`9024b64`) — fourth `PreToolUse` block, matcher `Edit|Write|NotebookEdit` →
  `hooks/phase-guard.sh`, shaped like the `Task|Agent` sibling (no `timeout`; only the vendored
  orca `*` hooks carry one), placed before the `*` catch-all. The scouting held: the
  `Edit|Write|NotebookEdit` a grep finds is the **PostToolUse** `post-edit-hook.sh`, untouched.
  Primary checkout's `settings.json` was clean, so no concurrent session held it.
  **The hook is NOT live** — the harness loads the primary checkout's copy, which is on another
  branch and arms only when this lands on `main` and that checkout pulls (rollback path 2).
  **⚠ NOW IN REVIEW (`phase: review`, `d7a2f8f`). All 17 tasks done; checkpoint 3 asked and
  answered 2026-07-28 — STAY ON OPUS 5, because the review backlog is fail-open/fail-closed
  judgment, not routine review.** At entry to review: HEAD `45a304e`, Suite **83/0**, `shellcheck -x`
  clean, dogfood **16/16** re-run after the step 9 fix. **Current HEAD/suite are at the end of this
  block** — every `HEAD`/`Suite` figure between here and there is the record of a round, not now.
  · **Escalation 1 (C0 placebo) FIXED** (`2adff7a`, test-only). Baselined by mutation: pre-fix, all
  three mutants (byte-count, input-order, phase-bound) escaped **all 80 tests, 0 failures**.
  **Round 4's "one fixture reorder" prescription was measured and is WRONG** — reversing alpha/beta
  still let all three escape. A desync only changes an answer if it corrupts the record that
  *decides* the outcome, so a normal trailing-newline blob must be read **before** the superseded
  one. C0 is now 3 files (alpha planning+prose `phase:` line / beta superseded, no trailing NL /
  gamma deleted → `missing` echo). C5 count 6 → 9. Hook was correct throughout.
  · **Escalation 3 (step 9 fail-open) FIXED** (test `84ed0f5` → fix `ee781d8`). Step 9 re-read files
  with unbounded `grep`+`sed`, so **prose** mentioning `phase: implementation` + `branch: X` granted
  permission on X — and feature files are exactly the docs that quote those keys. A file step 7 had
  skipped as malformed still got a vote. Parser now emits `<phase>TAB<branch>`; step 7's loop
  collects claims from the same parse; step 9 is string membership and touches no files. Falsified
  by reverting step 9 → fails exactly B2b/B2c. Also drops a grep+sed per file off the hot path.
  · **Rollback path 3 WITHDRAWN** (`45a304e`) — `chmod -x` yields **126**, may read as deny, so the
  "last resort" could lock every repo. Paths 1–2 verified and sufficient. Deliberately NOT verifying
  whether the harness reads 126 as deny: the experiment means arming a hook that may lock the
  machine, for a path we do not need.
  · **Escalations 2 and 4 CLOSED** (`8de2fba`, test-only). **A3.1b** isolates the line-1 clause that
  A3.1 could only name: junk on line 1, `phase:` above the fence. Mutation-checked against BOTH
  faithful mutants — deleting the whole rule is too blunt (41 failures), while `NR == 1 { next }`
  is caught by **A3.1b alone and A3.1 not at all**. **Flag ordering:** the two step-7 silent cases
  now pin their own session id and assert the store is untouched (`no_flag_for`); `payload_sid`
  moved up beside `payload`. Measured first — nothing writes that flag today and the `nfiles > 0`
  mutant was already caught, so this removed an unenforced order dependency, not a broken test.
  **The round-3 note's mechanism was WRONG**: A1.7 parses fine and never warns.
  · **OBS JUDGE RUN 1 (`01f011e`, 2026-07-28): risk=medium, confidence=high, no dimension failed**;
  `execution`/`regression`/`success_masking` concern. It confirmed the central reframing holds —
  it independently checked that `rules/gates.md` really does forbid branch creation during planning,
  so the unclaimed-branch premise is sound rather than lucky. It also **retracted its own first
  finding**: initial numbers suggested the hook slows as cards accumulate; controlled re-measurement
  gave a flat ~35–40 ms from 2 to 101 cards and it called its first reading a machine-load artifact.
  · **Escalation 5 (partial-skip silent fail-open) FIXED** — test `2fd0a04`-style baseline then fix.
  **Reproduced independently before touching anything**, in a throwaway repo: malformed `planning`
  card alone → allow + audible warning (promise holds); malformed `planning` card **+ one
  well-formed `review` card** → **exit 0, completely silent**. Root cause: the tally asked
  `nfiles > 0 && nparsed == 0`, and one readable card makes that false. Widened to
  `nfiles > nparsed`; `NOPARSE_MSG` reworded ("every file … failed" was false for a partial skip);
  the parser comment's "must not silently switch a CRITICAL gate off" claim reworded to the
  guarantee the code actually delivers. **The suite structurally could not see this** — every A2
  fixture makes *all* files malformed, every A3 fixture pairs the bad file with a well-formed
  *planning* file that denies regardless. Mutation-checked both directions: narrowing back fails
  A2.15 alone, widening to `nfiles > 0` fails A2.17/A1.7/B2.
  · **Escalation 6 (`nbranch > 1` untested) CLOSED by A3.5b.** The judge's mutation found the clause
  could be deleted with all 88 green. A3.5b makes the duplicate load-bearing — two `branch:` lines,
  the last claiming the branch under test, and awk keeps the last — so without the clause the deny
  becomes an allow. Catches that mutant and nothing else.
  · **RUN 2 (`f963b76`, risk=medium) found the SAME silence one stage later — in RUN 1's own fix.**
  Escalation 5 widened the tally but placed it *inside* the no-planning-files branch, and step 8's
  supersession drop can empty that list one stage further down, below a bare `exit 0`. Reproduced
  independently: superseded card + one unreadable card → silent; the unreadable card alone → warns.
  **Escalation 7** fixed it as a CLASS fix — the check moved *above every exit*, straight after the
  parse loop. Verified consequence: a deny with a skipped card now emits the warning **and** the
  full 16-line deny message (exit 2, all four elements intact). Also **8** (message asserted
  something false for a plain `README.md` in `docs/features/` — now conditional) and **9** (the spec
  still stated the pre-fix rule).
  · **RUN 3 (`4a60aa0`, risk=HIGH, 2 dimensions FAIL) found it one step EARLIER — in the counting.**
  Moving above every exit did close all nine exits; the boundary was drawn at *exits* and the hole
  was in `[ -f "$f" ] || continue`, which quietly both detected the unexpanded glob AND dropped
  every non-regular entry. A dropped entry is never counted, so `nfiles > nparsed` cannot trip.
  **Severity measured, not hypothetical:** a card symlinked into `docs/features/` denies while its
  target is present (exit 2, full message) and **exits 0 silently once the target is moved** — a
  real planning card leaving the gate without a word. **Escalation 10** fixed it with
  `[ -e "$f" ] || [ -L "$f" ]` (`-L` is required: `-e` follows the link and is false for a dangling
  one). **11** discarded awk's own stderr, which escaped the once-per-session flag entirely — 3
  lines on write 1, 2 on every write after. **12** corrected three MORE stale spec locations
  (step 7, the Output contract, the Examples table).
  · **⚠ THE PATTERN IS THE FINDING.** Three rounds, three instances of one class. Rounds 1 and 2
  were patched at the point of failure; only round 3 addressed *why the suite could not see any of
  them* — **every fixture was a readable file with malformed CONTENT, and none was an entry the
  parser could not open at all.** A2.19–A2.22 close that fixture class; the two-line `-e`/`-L`
  change is merely what it exposed. If a RUN 4 finds a fourth instance, the response is to rethink
  the fail-open surface, not to patch again.
  · **ALL TWELVE REVIEW ESCALATIONS CLOSED.** HEAD `8967723`, pushed. Suite **100/0**, shellcheck
  clean (hook + tests), dogfood **16/16**. Every repro re-run end-to-end: partial skip,
  supersession, dangling symlink, directory entry, unopenable card, moved-symlink severity case.
  **Next: obs judge RUN 4 at `8967723`, then `gh pr create --draft` → `gh pr ready`.**
  judge-guard blocks `gh pr create` without a fresh implementation-stage verdict matching HEAD.
  · **RUNS 4-6.** RUN 4 (`b25efdf`-1, risk=HIGH, `success_masking`+`traceability` FAIL) found the
  4th instance: `docs/features/` itself unlistable — at 444 the glob still yields real filenames but
  `-e`/`-L` need SEARCH permission, so every entry is dropped uncounted. **User chose the systematic
  fail-open audit over a 5th patch.** RUN 5 (med, 0 fails) audited the audit: THE RULE as written
  ("opted in AND holds a planning card") is NOT what the code does ("opted in AND could not
  finish"), and that misstatement hid the 5th instance — **the payload parse**. RUN 6 (`9996c0b`,
  med) confirmed all six RUN-5 fixes but says **the class is still not closed**.
  · **THE AUDIT'S REAL FINDING: six exits were asserted SILENT by the suite itself** — the four git
  exits (`A1.8`-`A1.10b`) and the two payload exits (`A1.4`/`A1.5`), all against `$OPTED`, which
  holds an un-superseded planning card on an unclaimed branch. Not missing tests — **enforcing**
  ones. That is why four consecutive judge rounds read the suite as evidence of correctness.
  Everything is enumerated in the spec under "The exits that must not be silent": 9 audible, 8
  silent. Also fixed: step-5 symlinked repo path (raised 3 rounds, never fixed until now), detached
  HEAD now speaks, `git` missing from PATH now speaks, `HOME` unset no longer exits 1.
  · **⚠ OPEN AND UNFIXED — RUN 6's biggest finding, verified: the hook resolves the repo from the
  SESSION'S CWD, not from the file being written.** `git rev-parse --show-toplevel` runs in the
  hook's cwd, so a write into an opted-in repo from a session sitting elsewhere exits 0, silently
  unguarded. Measured: same target file, cwd inside repoA → **exit 2**; cwd in repoB → **exit 0**.
  Pre-existing since step 2 was written; **six judge rounds never looked at it**. Biggest blast
  radius of anything found, possibly a one-line fix — but **settle it by running the hook LIVE**,
  which has never been done in six rounds. This is the next action.
  · **⚠ TWO DEFECTS I INTRODUCED IN `9996c0b`, both verified:** (1) step 5's new physical-resolution
  failure (`[ -n "$fp_phys" ] || exit 0`) is a SILENT fail-open — the same class, inside the fix for
  the class; (2) the walk-up glues a path with no directory component without a slash — relative
  `x.js` from repoA yields `…/repoAx.js`. Low reachability (payload paths are absolute by contract)
  but real, and the suite has no test for that shape.
  · **⚠ THE RULE IS WRITTEN IN THREE PLACES AND ONLY THE SPEC WAS FIXED.** `hooks/phase-guard.sh`'s
  own header still carries the sentence RUN 5 falsified, and the test file's Group A4 comment still
  lists two exits as silent that its own tests now prove audible. Three copies of a rule wrong six
  rounds running is the mechanism, not the symptom.
  · **MY ERROR, recorded:** I cited commit SHAs `ff8a02c`/`2b81ce1` in the RUN 6 prompt; neither
  exists. The real test commits are `07c1698` and `9eef24a`. The judge caught it. **Never write a
  SHA into a dispatch prompt without `git cat-file -t` first.**
  · Calibration that keeps this at medium, not high: **every survivor fails OPEN.** Worst case is
  the phase gate enforced by judgment alone — today's status quo. Nothing causes a false block.
  · Suite **108/0**, shellcheck clean, HEAD `9996c0b`, pushed.

  · **Repro trap that cost a false alarm:** a throwaway repo with **no commits** makes step 9's
  `git rev-parse --abbrev-ref HEAD` fail, so the hook fail-opens at exit 0 and EVERY scenario looks
  silent. `git commit --allow-empty` in the fixture before drawing any conclusion.
  · **OPEN, deliberately not decided — the parallel-worktree collision.** Once this merges, one
  agent opening any feature at `planning` denies source writes to every other concurrent agent on
  an unclaimed branch, and `core-conduct.md`'s parallel-agent invariant forbids that second agent
  from applying the fix the deny message names. The two rules contradict in exactly this case.
  Governance trade-off, user-owned — recorded in the feature file, not resolved.
  · **16 done** (`0f1c029`) — ADR `docs/decisions/0011-branch-scoped-write-permission.md`. 0010 left
  unedited and still Accepted; 0011 carries an `Amends:` header instead. The two grounds are
  recorded as *different kinds* of overturn on purpose: the technical objection was made
  **inapplicable** by the forward lookup (never refuted on its terms), while the process deferral was
  **overridden with its trigger condition admittedly unmet**. `validate-diagrams.sh` PASS.
  · **17 done** (`effae64`) — throwaway-repo dogfood, **16/16**. Deny fires with all four message
  elements, all six exempt paths allow, phase round-trip unblocks then re-denies.
  **⚠ ROLLBACK PATH 3 IS BROKEN — the headline finding.** `chmod -x` yields exit **126**, not the
  round-1 "skipped by the harness" claim; round 2's suspicion was right. `settings.json` registers a
  bare direct path, so that is the live shape. 126 is neither 0 nor 2 (a defect by the spec's own
  Output contract) and a `PreToolUse` harness may read it as **deny** — so the "last resort" rollback
  may lock every repo on the machine instead of disarming the guard. Paths 1–2 unaffected.
  **Recorded, not acted on** — revising Rollback is review-phase. Still unverified: whether the
  harness actually classifies 126 as deny; that needs a live check before path 3 is rewritten.
  Timings recorded, not gated: guarded ~64.1ms net, non-opted-in ~12.4ms net against a 12.3ms
  structural floor (harness overhead measured at 2.3ms/call and subtracted, not assumed).
  Suite **80/0**, `shellcheck -x` clean, re-run after 17.
  · **15 done** (`1b67516`) — two clauses appended to the `Phase gate` stub at `rules/gates.md:5`
  in place; bullet count re-verified **18**, no 19th added. The stub now states the deny rule, that
  docs and memory paths are never blocked, that no bypass variable exists, and that the
  implementation half stays judgment-only (the reverse-enforcement non-goal, made visible where a
  session would otherwise assume both directions are covered); it carries `merge-guard.sh`'s
  "momentum guardrail, not a security boundary" idiom for the unguarded Bash write surface.
  The four escalations these tasks raised are all **closed** — see the review block above.
  Do **not** re-derive the design; it is all in the feature file, which is canonical.
  · **RUN 6's cwd finding CLOSED** — the hook now resolves the repo from the **file being written**
  (user decision 2026-07-28), pinned by Group A6. Cost: never-opted 11→38ms, opted-in 35→41ms; live
  ~41.8ms non-opted / ~67ms deny. The old ~12.4ms "structural floor" is superseded — python starts
  once per write even when the repo was never opted in.
  · **RUNS 7-8 (2026-07-29). RUN 7's four findings landed (`2c39eb8` test → `97a2008` fix →
  `7f2fc9e` docs), then RUN 8 (`5cb0985`, risk=medium, no failing dimension) found the fix itself was
  the new defect.** `21a0411` test (A7.4) → `325f70c` record corrections. Suite **126/0**, shellcheck
  clean. **Five of RUN 8's six items landed, not six** — corrected by RUN 9: `:976` was closed as
  "already correct under the code's numbering", but RUN 8's point was the wrong *reasoning*, not a
  wrong number. Reinterpreted, not answered. (The first version of this entry claimed all six — the
  same overstatement `7f2fc9e` made, one round later.)
  · **Root cause, upstream of all six sites:** the doc's Order-of-operations list and the code's
  `# --- Step N ---` headers described *different* sequences while the list claimed they resolved
  against each other. Now single-sourced, with the rule stated once — **step numbers mean the code's
  headers; the code wins; never renumber code to match prose.** Canonical: 1 payload · 2 tools ·
  3 path/parse · 4 repo+opt-in · 5-10 unchanged. Four sites quoting retired prose are **marked**
  pre-`508c55b` rather than rewritten, so their quotes still match what they cite.
  · **F2 was reported closed and was not.** `7f2fc9e` claimed "all four findings" and touched **one
  file**. Enumerating beat patching again: beyond RUN 8's six sites it found two more wrong audit rows
  and **three** copies of the false-credit claim — the suite's `:989` and `phase-guard.sh:197` both
  still said six rounds missed the cwd bug. **`git show --stat` the closing commit and confirm it
  touched the file the finding named, before calling anything closed.**
  · A7.4 mutation-verified: swapping the walk-up for `warn_if_cwd_opted_in` leaves A7.1 green and
  fails A7.4 with 0 stderr lines. A7.1 alone never pinned that rationale.
  · **RUN 9 DONE 2026-07-29 @ `33bc6ae` — risk=medium, confidence=high, NO failing dimension, but
  five `concern`s** (`intent`, `trajectory`, `traceability`, `success_masking`, `audit_trail`).
  Verdict `coding-memory/observability-judge/2026-07-29-feature-phase-guard-hook-round9.md`.
  **No behavioural defect at this HEAD** — the judge re-ran the suite twice (126/0) and probed deny /
  doc-exempt / card-exempt / claimed-branch / never-opted-in by direct invocation. Every finding is a
  record defect. ⚠ **The judge did NOT complete its contract:** it wrote the markdown verdict but
  never appended to `verdicts.jsonl` and never wrote its pane result file, so no ledger row exists.
  · **Owed before the PR (RUN 9's list):** (1) three normative contract counts undercount the audible
  surface — `:611` says "six" audible exceptions vs nine `warn_once` reasons and eleven audit rows,
  `:297` still says "two exits that print", `:484` names 2 of 9 flag reasons and quotes `$HOME` where
  the code ships `${HOME:-}`; (2) three unmarked stale step refs survived the "fix every site" pass —
  `:426` (5→4, authored by the reorder commit itself), `:449` (3→4), `:1015` (Step 4→3); (3) answer
  `:976` on its own axis — it speaks via `warn_if_cwd_opted_in`'s cwd fallback, not because an opt-in
  test passed; (4) **consider one structural test** greping the doc's step list against
  `grep '# --- Step' hooks/phase-guard.sh` — four rounds say care alone cannot keep the record correct.
  · **⚠ VERIFIED ADJACENT BLOCKER — `gh pr create` will fail closed from this worktree.**
  `hooks/judge-guard.sh:22` reads `$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl`
  (the PRIMARY checkout's — 43 lines, **zero** for this branch) while resolving identity from the
  session's cwd. **Same identity-from-cwd class this branch just fixed in `phase-guard.sh`**, and it
  is exactly what the parked `fix/judge-guard-verdict-lookup` worktree exists to fix. Decide
  deliberately — `JUDGE_VERDICTS_FILE=$PWD/...`, or a logged `JUDGE_EXEMPT=<reason>`. **Re-running the
  judge does not help.** Out of scope for this diff.
  · **Undisclosed boundary RUN 9 found (owed to the PR body):** supersession reads `refs/heads/` only,
  so a gate opened on a **remote-only** branch does not supersede and the repo resumes denying
  (probe-verified). Also uncosted: one `dirname` fork per path level for writes landing outside any repo.
  **Next: the four record fixes above → obs judge RUN 10 (mandatory, HEAD will have moved) → decide the
  `judge-guard` route → `gh pr create --draft` → `gh pr ready`.** Judge prompts live in the **session** scratchpad and die
  with the session — RUN 8's was lost that way. Don't point at one; reconstruct it from this block
  plus the RUN 8 verdict file. (`scratchpad/` is not `.gitignore`d here, so nothing durable goes there
  while the branch is in review.)
- **Three findings from grounding the Spec against live prior art (2026-07-25).** (1) `NotebookEdit`
  carries **no** `file_path` — its only path key is `notebook_path`; the settled step 4 said
  `file_path` alone, which would have failed open on every notebook write. Corrected, with a
  regression scenario. (2) System `bash` is **3.2.57**, so the hook may not use associative arrays,
  `mapfile`, or `${var,,}`. (3) `git cat-file --batch` output is **asymmetric** — a blob emits
  `<sha> blob <size>` *without* echoing its request, a miss echoes the request verbatim + ` missing`
  — so the un-superseded filter must consume results in input order or it mis-attributes every blob.
- **User decisions, 2026-07-25.** Q2 **accepted** with one narrowing — the *un-superseded check*:
  a `planning` file stops denying once any branch records it as `implementation`, because its gate
  has already opened. Fixes the `main`/hotfix write-lock at the root cause (a stale copy on `main`
  is stale *by design* after the gate) while staying a forward lookup. Q6 **resolved: no bypass at
  all** — and the reason is that the hatch already exists structurally, since feature files live
  under unguarded `docs/**`, so editing the frontmatter always unlocks a locked repo. A branch-name
  allowlist was rejected on the same ground: it is `PHASE_EXEMPT` through a different door.
  Q7 (reverse direction) stays out of scope. Q1 (build at all?) still deferred to the gate.
- **APPROVED, NOT STARTED — doc-system consolidation.** Was "do this before more phase-guard work"
  (user-approved 2026-07-25); the 2026-07-26 `gate confirmed` started phase-guard implementation
  first, so that ordering is **superseded, not cancelled** — flagged to the user at the gate.
  User-approved 2026-07-25: trim this file to its own ≤200-line cap, delete the 18
  `coding-memory/branches/*.md`, drop `coding-memory/pr-tracking.md`. **These are ONE coupled
  commit, not three** — this index holds ~17 pointers into the delete targets (branches/: lines
  68,77,102,132,138,150,168,179,189,201,263 · pr-tracking: 57,69,75,201,263,266,415), so deleting
  without trimming leaves dangling pointers, and trimming removes most of them anyway. Order:
  (1) rewrite §Active Session (7–170) and §Exact Next Steps (272–432) — 325 of 432 lines, both
  accumulated history, keep current session + repo/PR pointers + next steps only; (2) `git rm` the
  19 files (all tracked → recoverable); (3) fix `skills/preparing-pull-requests/SKILL.md:43`, which
  mandates `pr-tracking.md` as a maintained running doc — PR descriptions get generated at PR time
  from the checklist + diff; (4) tick `README.md:63`, which already tracks this reconciliation.
  Inert trap: `docs/superpowers/plans/2026-07-18-compliance-judge.md:563,570` would recreate both
  deleted artifacts if ever re-executed.
- **Deferred to its own feature file `doc-system-consolidation` (amends ADR 0010 → earns an ADR).**
  (a) **Judge-output shrink:** `coding-memory/observability-judge/` is 32 files / 5,007 lines and
  compliance adds 757 — and *nothing reads them*, since `judge-guard.sh:22` consumes
  `verdicts.jsonl`, not the `.md`. Shrink to pass/fail per area + open issues on the feature file.
  (b) **Invert the canonical feature-file section order** to frontmatter → Tasks → Verification →
  Spec → rationale. Today `## Tasks` sits at line 223 of 245, so "where are we" costs a full-file
  read; reordered, a restore gets it from the first ~40 lines. The one-file design currently fights
  selective loading instead of enabling it.
- **Q2 was the crux.** ADR 0010 deferred this hook because
  "which feature file is active" is unresolvable at `branch: none`. That framing is avoidable: the
  hook never attributes a write to a feature, it asks only whether the *current branch* carries
  implementation permission. Deny when any feature file is `phase: planning` AND the branch is not
  claimed by an `implementation` file. It holds during planning precisely *because* planning forbids
  branch creation — an unclaimed branch is the signal, not ambiguity. Known holes are written down,
  not hidden: branch-granularity (not per-feature), `main` stays write-locked after the gate opens,
  and a stale `planning` file locks the repo. Q3/Q4/Q5 resolved; **Q6 found a real defect in the
  house pattern** — `JUDGE_EXEMPT`-style bypasses need a Bash command line, which `Edit`/`Write`
  payloads do not have, so `PHASE_EXEMPT` cannot work the way the other guards do.
- **Deliberate fail-mode split from `judge-guard.sh`, decided this session:** that hook fires on one
  rare command and fails closed on infrastructure errors; this one fires on *every write in every
  repo*, so it fails closed only once a `planning` file is positively identified, and fails **open**
  on missing python / unresolvable git root / unparseable frontmatter. Blast radius, not sloppiness.
- **PR #29 MERGED 2026-07-25** (`122b8a5`); branch pruned local+remote; ancestor-check verified.
  Phase-frontmatter permission system (ADR `docs/decisions/0010-phase-frontmatter-as-permission-source.md`)
  now on `main` — every feature-scale change gets a `docs/features/<name>.md` with `phase` in
  frontmatter, checked on restore. **Mechanism is still undogfooded** — no such file exists yet
  anywhere; the next feature-scale branch should be its first real user. Detail:
  `.claude/session-state.md`.
- session_origin: desktop · session_started_at: 2026-07-22 (Sonnet 5) · last_active_branch: main —
  **Q&A only, no code/architecture changes.** Answered how to manually smoke-test the pane
  dispatcher: single `pane-echo` dispatch, and a 5-pane test (4 `--role implementer` filling the
  quadrant + 1 default `aux`) was being scoped when the 75k handoff fired. **Pre-existing
  uncommitted `coding-memory/compliance-judge/verdicts.jsonl` (2-line diff) + new
  `2026-07-22-0007-tea-room.md` predate this session and are unrelated to it — still awaiting a
  user decision on whether to commit them.**
- session_origin: desktop · session_started_at: 2026-07-22 (Opus 4.8) · last_active_branch: feature/cmux-version-gate
- **PR #25 MERGED 2026-07-22 (`3491464`); branch pruned local + remote; verdict outcomes
  backfilled.** pane-layout-v2 shipped: 9 tasks, probe P8, ADR 0008, implementation judge PASSED
  over two rounds. Detail: `coding-memory/pr-tracking.md` §PR #25, resume #9 below.
- **CURRENT: `feature/cmux-version-gate`** — PR #25's agreed first post-merge follow-up, and the
  round-2 judge's top item. `check_cmux_version` in the adapter pins the verified cmux release and
  warns + leaves a durable receipt when the live binary differs, because the aux-column anchor is
  a heuristic that no test can catch drifting (every adapter test drives a FAKE binary).
  **Its own round-1 judge found a real bug by probing nine version strings: a
  `[0-9.]`-only filter silently swallowed `0.65.0-rc1`/`0.64.20-beta`** — the pre-release builds
  most likely to have moved behaviour — so the parser now tests version-SHAPED, not version-CLEAN.
  **PR #26 OPEN** (https://github.com/suyatdev/.claude/pull/26) — 3 judge rounds, all risk=low,
  none blocking; it found two real defects (the pre-release deafness above, and a `2>/dev/null`
  that does not suppress a failing *redirection* — a trap `run-pane-agent.sh:81` already
  documented). Suite 170 → 197. Log: `coding-memory/branches/cmux-version-gate.md`,
  `coding-memory/pr-tracking.md` §PR #26.
- current work: **pane-orchestration FULLY CLOSED OUT — PR #23 MERGED (8f40e05) and docs-only
  PR #24 MERGED 2026-07-21 13:05Z (23dd2e3); both branches pruned local+remote.** PR #24
  merged WITHOUT the late-pushed brainstorm checkpoint 9e16d7f (PR #21 stranding failure
  mode, 2nd occurrence) — recovered by cherry-pick onto `main` as 2d8a416 (memory-only →
  git-guard brainstorm exception; user-approved), parity verified, then pruned. Detail:
  `coding-memory/pr-tracking.md` §PR #24. Obs judge (impl @ 5c846b2) outcome=clean.
  **Remaining: post-merge watch items in Next Steps 0c.** Per-task history:
  `.superpowers/sdd/progress.md` (RUN section), `coding-memory/branches/pane-orchestration.md`.
- **CURRENT: pane-layout-v2 — USER REVIEW GATE CLEARED 2026-07-21 (resume #4, Fable 5).**
  Spec: `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md` @ blob aeb0074
  (commit bb4050b on `feature/pane-layout-v2`, pushed, no PR). Round-1 judges clean,
  pane-dispatched: compliance **pass**/high 0 violations; obs advisory **low**/high, 1
  concern = success_masking ("run folder missing = finished" infers success from absence —
  out-of-band `panes/state/runs/` cleanup could recycle a busy pane). Judge notes for
  implementation: pin `respawn-pane --command` quoting during the live probe before REUSE
  is coded; log live probes first thing; fallback tests assert the exact legacy command
  sequence. **User sign-off EXPLICIT on (a) the aux-reuse extension and (b) all 4 flagged
  assumptions — ZERO spec edits, so both verdicts remain fresh.** Spec status line
  intentionally left saying "pending" (editing the file would invalidate the blob-sha-keyed
  verdicts); the authoritative approval record is
  `coding-memory/brainstorms/2026-07-21-pane-layout-v2.md` §"User review gate". **PLAN
  WRITTEN same session (user said "continue for now" on Fable 5 = per-task planning gate
  answer; Hard Model Gate untouched):
  `docs/superpowers/plans/2026-07-21-pane-layout-v2.md` — 8 tasks, TDD, live probe FIRST
  (P1–P7 resolve the 4 assumptions + respawn quoting), unverified tree schema quarantined
  in `layout_normalize_tree` validated against a live-captured fixture; self-review caught
  and fixed a T4/T5 fixture state collision. GATES ANSWERED (do not re-ask): Opus 4.8
  in a FRESH session; subagent-driven execution, pane-routed implementers.** Full design
  history: the brainstorm file; earlier session blocks: git history of this file
  (98faa38, c252135).
- **Resume #9 (2026-07-22, Opus 4.8): probe P8 + implementation judge PASSED. PR is the only
  step left.** HEAD `e12dc06`. **P8 finally supplied the live coverage Tasks 8/9 could not**
  (`coding-memory/branches/pane-layout-v2.md` §P8, script `<scratchpad>/live-quadrant-probe.sh`):
  four sequential `--role implementer` dispatches, each plan *predicted* from the live tree
  before firing, all four matching exactly — **impl slots 3–4 are no longer fake-verified**,
  because the agents were still booting so no `agent-exit` existed and reuse could not preempt
  growth. Two corrections: **27** — `index` is traversal order over a FLAT panes array, NOT
  left-to-right (Task 8's experiment only made horizontal splits; with a real quadrant impl.2
  in the left column sorts *after* impl.3 in the right one), so `layout_rightmost_surface` is
  a heuristic and its comment now says so — logic unchanged, nothing better is exposed; **28** —
  `new-pane` *does* follow `focus-pane`, so it is anchorable after all, but that neither beats
  `new-split --surface` nor fixes height. **Aux height is ordering-dependent and accepted as a
  limitation → ADR 0008**: full-height when the column predates the quadrant (the common path —
  handoff + judges open first), half-height bottom-right when created after, unfixable because
  the tree is flat, both split verbs are pane-relative, and `--placement dock` is disabled.
  Implementation judge **PASS, risk=low confidence=high**, no dimension failed, concerns
  `success_masking` + `audit_trail`; it independently re-ran three recorded falsifications and
  re-checked the unfixability argument. **Its sharpest catch, now the branch's main latent risk:
  a future cmux changing pane-walk order lands the aux column wrong while all 170 tests still
  pass** — every test drives a fake binary, so mitigation is procedural (re-run
  `panes/cmux-layout-probe.sh` after any cmux upgrade). Live workspace restored and **diffed**
  against its captured baseline. Judge follow-up not blocking: widen the one-line stderr notice
  when the layout path degrades to legacy.
- **Resume #8 (2026-07-21, Opus 4.8): Tasks 7–9 DONE + pushed (45fee28, 1d1e3c7, 17a0f44).**
  Plan execution + verify-after-rename; Task 8's first-ever real-binary smoke check, which
  **falsified spec assumption 4** (aux landed 2nd from left — `new-pane` splits off the current
  pane); Task 9 added mid-flight to anchor aux on the rightmost pane. Also proved live: the P4
  send-not-respawn reuse deviation (same surface re-used), `--workspace` scoping, title
  stamping, the T3 handoff-wrapper rename. `--role` documented in the skill.
- **Resume #7 (2026-07-21, Opus 4.8): Task 6 DONE + pushed (aa2cc42).** Pane-dispatched
  implementer (`--role implementer`, surface:78); commit verified in-checkout, all five
  suites independently re-run, one falsification independently re-run by me. Corrections
  10–15 — detail in Next Steps 0-ACTIVE and `coding-memory/branches/pane-layout-v2.md`.
  Session note: ~82k of this session's budget went to context RESTORE before any output,
  which is the recurring cost of task-by-task execution on this branch.
- **Resume #6 (2026-07-21): Task 1 live probe EXECUTED on Opus 4.8 (ffe22d2).** Probe is
  re-runnable: `panes/cmux-layout-probe.sh`; fixture `panes/adapters/fixtures/tree-live.json`.
  Three plan corrections + one user-approved spec deviation — see Next Steps 0-ACTIVE and
  `coding-memory/branches/pane-layout-v2.md`.
- **Resume #5 (2026-07-21, Fable 5): NO execution — stopped at the model gate.** Session
  ran Fable 5 vs the answered Opus 4.8; discovered pane implementers would ALSO run
  Fable 5 (settings.json `"model": "claude-fable-5[1m]"`, dispatcher passes no model
  flag). User chose stop + relaunch on Opus 4.8. **Next session MUST be started with
  `claude --model claude-opus-4-8` (or `/model` immediately) — the handoff pane and a
  plain `claude` both inherit the Fable 5 default (handoff-wrapper.sh execs claude with
  no --model). Open: whether to pin pane implementers to Opus too (settings/dispatcher
  change, user's call) or accept Fable 5 implementers.** Then execute the plan from
  Task 1 (live probe); implementation-stage obs judge before PR.
- prior session (2026-07-20): claude-code-handoff cherry-pick SHIPPED — PRs #21+#22 MERGED;
  audit-trail recovery + 8-branch orphan sweep. Detail: ADR 0006,
  `coding-memory/branches/add-claude-code-handoff.md`, Next Steps 0.
  settings.json dual-version staging policy unchanged (Orca hooks + fable-model line stay uncommitted).
- **SUPERSEDED (was parked): judge terminal-enforcement.** Branch
  `feature/judge-terminal-enforcement` retired, NOT deleted (~3,400 lines unmerged judged
  spec work; deletion = explicit user cleanup). Reference text for any future `spec-guard`
  resurrection. ADR 0007;
  `coding-memory/brainstorms/2026-07-20-judge-terminal-enforcement.md`.
- **Session-budget preference (2026-07-20): keep each session below ~100k tokens; checkpoint memory
  after each task so the user can /clear before the next design task.**
- **CORRECTED 2026-07-21 (was stale): the Orca hooks and the fable-model line are now IN
  committed `settings.json`** (HEAD == live, last touched by a3aedc8 "Add merge guard") —
  the old "stay uncommitted / dual-version staging" policy no longer reflects reality.
  Whether committing them was intended is the user's call (flagged 2026-07-21). The Orca
  channel caveat still stands: `claude-hook.sh` sources `$ORCA_AGENT_HOOK_ENDPOINT` before
  its token check and that stdout becomes hook stdout. Untracked `chrome/`, `telemetry/`,
  `stats-cache.json` stay untracked (machine-local; gitignore an open question).
- 2026-07-19 session notes — statusline-edit authorship resolved as that session's own work,
  concurrent-session evidence, model-gate history (Sonnet 5 → Opus 4.8), `chore(settings):`
  precedent for model/theme changes: `coding-memory/branches/statusline-token-bar.md` and
  `coding-memory/session-log.md`.

## Repositories

### suyatdev/.claude
- remote: origin (git@github.com:suyatdev/.claude.git)
- PR #4 (feature/vibe-coding-standards-integration) — MERGED 2026-07-12.
- PR #3 (feature/standards-extractor-agent) — MERGED.
- PR #5 (feature/modular-coding-memory) — MERGED 2026-07-14. `main` fast-forwarded to include it.
- PR #6, #7, #8 (feature/new-project-memory-scaffold) — all MERGED. Branch deleted 2026-07-15
  (fully superseded — see `coding-memory/branches/new-project-memory-scaffold.md`).
- PR #9 (feature/rules-to-skills-restructure) — MERGED 2026-07-15 (fast-forward, user's choice to
  merge locally rather than wait for GitHub review). Branch deleted. The rules-to-skills
  restructure: 7 always-loaded rule files → core-conduct.md + gates.md + 5 new skills + git-guard
  hook. Always-on content: 4,030 → 1,151 words (~71% cut).
- feature/documentation-enforcement (2026-07-16) — documentation-enforcement backstop:
  `hooks/doc-guard.sh` (block substantial undocumented source commits + surface uncommitted
  work before compaction / at next session start), broadened `managing-session-memory` criteria
  (business-logic + direction-pivoting changes → mandatory + ADR), ADR standard/template in
  `setting-up-a-new-project`, gates stub. Verified (15-case harness). **PR #10 MERGED (2026-07-16).**
  Detail: `coding-memory/branches/documentation-enforcement.md`.
- PR #11 (chore/ports-registry-snatch-8001) — MERGED 2026-07-16. Reconciled the orphaned PORTS.md
  edit (snatch-bracket backend on port 8001) as its own commit, per user's commit-only-my-work call.
- PR #12 (feature/diagramming-skill) — MERGED 2026-07-16. New `diagramming-technical-docs` skill
  (Mermaid docs standard: SKILL.md + references/assets/scripts validator; Mermaid-not-PlantUML).
  Detail: `coding-memory/branches/diagramming-skill.md`.
- feature/observability-judge (2026-07-16) — the observability judge (16 commits, 17/17 tests):
  scoring subagent (10 dims → JSONL+markdown verdict + layman summary), `hooks/judge-guard.sh`
  blocking `gh pr create` without a fresh strict-freshness verdict, skill + gate stub + catalog,
  ADR 0001, spec, verdict store. Command detection took 2 review-driven security fixes
  (substring→anchored→python shlex, closing a quoted-env-prefix bypass). **PR #13 MERGED
  2026-07-17** (bootstrap self-gate → JUDGE_EXEMPT).
  Detail: `coding-memory/branches/observability-judge.md`; PR status: `coding-memory/pr-tracking.md`.
- feature/memory-rag-index (2026-07-17→18) — `memsearch`: local SQLite (sqlite-vec + FTS5) RAG over
  transcripts + curated docs, Qwen3 embeddings, hybrid retrieval, silent SessionStart nudge.
  60-test suite green, backfill 228 sources / 2332 chunks / 0 errors / p95 149ms, golden 16/16.
  **PR #14 MERGED 2026-07-18** (7015369). Judge (impl): risk=low conf=high, outcome=clean.
  Detail: `coding-memory/branches/memory-rag-index.md`.
- feature/compliance-judge (2026-07-18) — subagent judging ONE finished spec against live rules
  (writing-specs + core-conduct/security): blocking pass/fail, per-rule citations, JSONL+markdown
  store; skill with parallel dispatch alongside the observability judge, capped auto-revise loop,
  escalation, explicit-only waivers; gates stub + catalog, ADR 0003, golden eval 12/12.
  **PR #16 MERGED 2026-07-18** (4c2abec). Judge (impl @ 85d8982): risk=low conf=high, clean.
  Detail: `coding-memory/branches/compliance-judge.md`.
- feature/writing-project-readmes-skill (2026-07-19) — `writing-project-readmes` skill: house
  README standard from the user-supplied template (check-then-create, real facts only, `[TODO:]`
  greppable placeholders) + Roadmap upkeep as features land + trigger wiring (setting-up-a-new-
  project step 5, preparing-pull-requests bullet, CLAUDE.md catalog). TDD RED/GREEN + 8/8 routing.
  **PR #17 MERGED 2026-07-19** (merge commit d242e69); branch deleted. Judge rounds 1-2
  (3c5a826 low/medium → grep hole fixed → 0d23feb low/high), outcome=clean (backfilled).
  Detail: `coding-memory/branches/writing-project-readmes-skill.md`.
- feature/statusline-command (2026-07-19) — Claude Code status line reproducing the oh-my-zsh
  `robbyrussell` prompt (`➜ user@host dir git:(branch) ✗`) plus dimmed model + token-count
  segments: new `statusline-command.sh`, `statusLine` entry in `settings.json`, README table
  row; model → opus[1m] and theme → dark split into their own `chore(settings)` commit.
  Observability judge ran **5 rounds**, each finding something real in the round before: terminal-escape
  injection via four distinct paths (incl. a **second** unstripped fallback introduced by the fix for the
  third), false "pushed" claims, and an unverified `context_window` schema — all fixed. Test suite
  validated by falsification against all 5 historical versions rather than by passing alone
  (`statusline-command.falsify.py` makes that reproducible). Recurring lesson: **the write-up ran ahead
  of the code in every round**, including a "Cosmetic, no leak" claim about a path that did leak. Scope
  overran badly — 5 of 6 commits judge-driven; taken to the user rather than resolved unilaterally.
  No ADR (presentation-only — misses all three ADR triggers).
  Detail: `coding-memory/branches/statusline-command.md`.
- feature/statusline-token-bar (2026-07-19) — **PR #20 MERGED 2026-07-20 04:01Z.** Follow-on
  to PR #18: model name orange, context bar scaled to a fixed 100k "time to clear" reference (not the
  model's window — against 1M a 143k session rendered nearly-empty-but-red), cumulative Σ counting
  input+output only (cache traffic swamped it ~16x), purple weekly-quota segment. A cost-estimate
  feature was requested, built, then **removed entirely**: subscription plan, `costUSD: 0`, no cost
  field in the payload — any dollar figure would have been invented. Weekly quota is a percentage
  for the same reason: docs confirm `rate_limits` exposes `used_percentage` + `resets_at` only, so
  "tokens left" is uncomputable. Schema check caught a silent bug: `resets_at` is epoch seconds, not
  ISO — the countdown would have never rendered and looked merely absent.
  Judge R1 (b24d422) risk=**high**; all three findings fixed across 4 commits (fc67ab1 tests,
  888449e race repro RED, d7a2861 lock GREEN + ADR 0005, d302479 lock-recovery tests).
  Recurring lesson, now three-for-three on this branch: **writing the check is not the same as the
  check working.** The first lock regression test planted its PID file with a trailing newline —
  a condition the buggy writer cannot produce — so re-introducing the bug passed 44/44. Only the
  mutation revealed it. Every claim on this branch is now falsification-backed.
  Detail: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
- feature/verifying-subagent-commits (2026-07-18) — new skill: after a dispatched implementer/fix
  subagent reports DONE with a commit SHA, the controller independently confirms via `git log -1`
  in the target checkout that it actually landed there, before trusting the report. Harvested from
  a real trace (a subagent committed to the wrong checkout 3x in one session, despite an explicit
  dispatch-prompt self-check instruction). Not hook-enforced by design. **PR #15 MERGED
  2026-07-18** (merge commit 417e8e7); branch deleted. Judge (impl, head 367da77): risk=low
  conf=high, outcome=clean.
- feature/add-claude-code-handoff (2026-07-20) — vendored Sonovore/claude-code-handoff @
  c6cb717, then cherry-picked per the user's 15-row picks (ADR 0006): handoff SessionStart
  loader + doc-guard PreCompact removed, tracker bug patched locally (verified live),
  `/handoff` = checkpoint UX, committed memory stays authoritative. Judge R1 medium→fixed,
  R2 **low/high** @ e56c2f2. **PR #21 MERGED 2026-07-20 22:02Z (3c58363).** Judge audit trail
  committed to the branch post-merge (77b59ad) and stranded off `main`; recovered via docs-only
  **PR #22 MERGED (284478a)** — cherry-pick 7337186.
  Detail: `coding-memory/branches/add-claude-code-handoff.md`, `coding-memory/pr-tracking.md`.

## Pointers
- PR tracking (all repos, all branches): `coding-memory/pr-tracking.md`
- Session log (chronological summaries): `coding-memory/session-log.md`
- Decisions & conventions: `coding-memory/decisions.md`
- Branch implementation logs: `coding-memory/branches/`
- Brainstorm write-ups: `coding-memory/brainstorms/`

## Exact Next Steps
0-ACTIVE. **pane-layout-v2 — EXECUTING. Task 1 (live probe) DONE + pushed (ffe22d2)
   2026-07-21. Gates answered, do not re-ask: model = Opus 4.8 (user ran `/model`
   this session — satisfied); execution = SUBAGENT-DRIVEN, implementers PANE-routed.
   **Tasks 2 (ba9a91b) + 3 (0711017) DONE + pushed** — both pane-routed, commit-verified
   and independently re-run (Task 3: dispatch 39/0, siblings 24/0 10/0 9/0, shellcheck
   clean, `--role` guard falsified 37/2 → restored 39/0).
   **Task 4 (`cmux-layout.sh`) DONE + pushed (5da1cad)** — layout 12/0, siblings
   39/24/10/9 all 0 failed, `shellcheck -x` clean; all 4 falsifications RED and reverted
   (I independently re-ran the two jq ones: 7/5 and 11/1, restored byte-identical 12/0).
   **Task 5 (decide + title composition) DONE + pushed (8ad7d7a)** — layout 26/0, siblings
   39/24/10/9 all 0 failed, `shellcheck -x` clean; 3 falsifications RED and reverted (I
   re-ran the tab tie-break one myself: 25/1 → restored byte-identical 26/0).
   **Correction 8:** every Task 5 test fixture called `tree "$(pane …)"`, skipping Task 4's
   new `workspace` level — and would have PASSED anyway, because normalize uses recursive
   descent. Silent builder drift, the exact hazard Task 4 existed to kill. All 8 fixtures
   now wrap through `workspace workspace:1`. **Correction 9:** the plan's reuse
   falsification couldn't discriminate with only one finished surface; needs two.
   **Task 6 (cmux.sh v2 frame — tiered degradation, legacy floor, dryrun) DONE (aa2cc42)**
   — new `cmux-exec.test.sh` 24/0, siblings 26/39/10/9 + adapters 24/0 (file untouched),
   `shellcheck -x` clean. 5 falsifications RED and reverted; **I independently re-ran the
   workspace-scoping one** (anchor asserted to match exactly once, non-empty diff, 23/1 RED
   on that exact case, restored byte-identical by sha256 → 24/0). RED run was 5/18 with
   **all five passes vacuous** — enumerated in the branch log.
   **Corrections 10–15** (10: `T_EMPTY` in the imagined shape normalizes to 0 bytes yet
   passes every plan assertion — 3rd builder-drift occurrence, so a `T_SLOT1` fixture whose
   plan is reachable only if the tree really parsed was added; 11: tree fetch must carry
   `--workspace`, bare is window-scoped; 12: `send`/`rename-tab` carry it too, `new-split`
   deliberately does not; 13: dryrun comment contradicted its own load-bearing guard;
   **14: the plan's Step 2 RED run is UNSAFE here** — v1 hardcodes the real cmux path and
   ignores `PANE_CMUX_BIN`, so a literal RED run inside a live cmux workspace fires ~10 real
   `new-split down` calls at the user's window; run RED against a `cp -R` copy in `$TMP`
   instead — **Task 7 needs the same precaution**; 15: the plan's `legacy_open` falsification
   could not discriminate — `|| true` left the suite green because the ref-shape guard exits
   on its own).
   NEXT: **Task 7** (plan execution + verify-after-rename) → Task 8 →
   implementation-stage obs judge (OWED — not yet run; judge-guard blocks PR) → PR.
   **Still gotchas for Task 7:** `grep -c .` on empty input prints 0 but EXITS 1 —
   `layout_decide`'s tab-count loop is safe only because these files are `set -u` and NOT
   `set -e`; introducing `set -e` breaks it. **Nothing in Task 6 touched the real cmux
   binary** — every execution assertion runs against the fake, so the `--workspace`
   placement on `send`/`rename-tab` rests on `--help` + probe P5, **not** a live mutating
   call. That live confirmation is owed at Task 8 alongside Task 3's handoff-wrapper rename.
   **Task 4 = plan corrections 5–7, all verified against the live fixture before dispatch:**
   (a) the normalize selector returns EMPTY (real shape keys each level's own ref as `ref`;
   surfaces carry `pane_ref`+`title`); (b) **the workspace filter was a SILENT TOTAL
   FAILURE** — workspace objects carry `ref` and their `workspace_ref` is `null`, so
   `select(.workspace_ref? == $ws)` matched only the root `active`/`caller` objects and
   returned NOTHING whenever `CMUX_WORKSPACE_ID` was set (the normal case), degrading the
   whole feature to legacy; repaired to filter on the workspace's own `.ref`, kept as
   defence-in-depth with primary scoping SERVER-side via `tree --workspace` (P1);
   (c) the canned `pane()`/`tree()` builders were in the imagined shape and would have kept
   (a)+(b) green while live degraded — now mirror `fixtures/tree-live.json`.
   Implementer also fixed a real footgun: `layout_managed` dropped its last line when stdin
   lacked a trailing newline (Task 5 will feed it via `$(...)`, which strips it).
   Note for later tasks: the plan's `> file 2>/dev/null` idiom does NOT suppress a
   redirect failure (left-to-right); put the stderr redirect FIRST.
   **Task 3 = the plan's 4th correction:** its handoff `rename-tab --surface
   "$CMUX_SURFACE_ID"` (a UUID, and no `--workspace`) would have silently renamed the
   user's FOCUSED tab (P5+P6+P7 combined) — shipped instead with
   `--workspace "$CMUX_WORKSPACE_ID"` and NO `--surface`, resolving via the pane's own env.
   **Unverified live — confirm at Task 8.** The plan's predicted RED set was also wrong
   (the `--role` allowlist case passes vacuously pre-implementation) — exactly the failure
   the mandatory falsification rule exists to catch.
   **The probe changed the plan in three places — full verbatim findings in
   `coding-memory/branches/pane-layout-v2.md` §Live probe; read it before Tasks 4/6/7:**
   (a) the real tree JSON shape differs from the plan's assumption at EVERY level (each
   level keys its own ref as `ref`; surfaces carry `pane_ref`+`title`) — the plan's jq
   matches nothing, so Task 4 must rewrite both the jq AND the canned test builders, or
   unit tests stay green while live silently degrades to legacy; (b) `rename-tab` does
   NOT error on an unresolvable `--surface` — it silently renames the FOCUSED tab, so
   Task 7 needs verify-after-rename, not retry-once; (c) `respawn-pane` destroys the
   surface when its command exits → reuse uses `cmux send` instead (**user-approved
   deviation; spec left unedited — flag it to the implementation-stage judge**).
   Spec assumption 1 (bare tree workspace-scoped) is FALSE but the gate did not trip
   (`tree --workspace` accepts `$CMUX_WORKSPACE_ID`); assumption 4 confirmed visually.
   Also: every mutating cmux call needs an explicit `--workspace` (refs resolve relative
   to it; UUIDs work for `--workspace` but not `--pane`).
   **settings.json's `model` field tracks the ACTIVE session model — it is not a stable
   committed preference. Now `opus[1m]` (user's /model), uncommitted. Re-`grep` fresh
   rather than trusting any earlier diff.**
0. **claude-code-handoff cherry-pick (2026-07-20) — DONE. PR #21 + PR #22 both MERGED.** Picks
   applied per ADR 0006; judge R1 medium→R2 low/high; PR #21 merged 22:02Z. The audit trail
   stranded off `main` (committed post-merge as 77b59ad) was recovered via docs-only PR #22.
   **Branch cleanup DONE:** all 8 merged orphans pruned local + remote (see Orphans below).
   Ongoing duty (unchanged): add handoff state-file gitignore entries per project repo on
   first work there (recorded in `managing-session-memory`).
0b. **Judge terminal-enforcement — SUPERSEDED by pane orchestration (ADR 0007, 2026-07-21).**
   Branch retired, not deleted (user cleanup decision pending). Platform research absorbed
   into the pane-orchestration spec. Resurrect its §3 only if a skipped compliance judge is
   ever observed (spec-guard remedy).
0c. **Pane orchestration — PR #23 MERGED 2026-07-21 (8f40e05); branch pruned.** Verdict
   outcome backfilled `clean`. Open post-merge items, none blocking: (a) judge suggested a
   short ADR for the bypassPermissions rider (79495c5, user-requested, commit-message-only
   rationale) — user's call; (b) live-verify a second adapter (tmux or iTerm) — only cmux is
   live-proven, a real iTerm failure fails open + cools down silently; (c) watch for
   `adapter-failed-nosession` (shared cooldown can mute pane redirect for all env-less
   sessions up to 7 days) and the first concurrent two-implementer pane dispatch; (d) README
   has no Roadmap section (non-template, 55 lines) — standardizing via
   `writing-project-readmes` is its own task if wanted. Only chrome/chrome-native-host stays
   uncommitted (machine-local).
1. **Statusline token bar — DONE (PR #20 merged 2026-07-20 04:01Z).** Still open, deliberately
   unabsorbed: R1's `STATUSLINE_DEBUG` logging splitting "field absent" from "field present but
   unparseable" (would have caught the epoch-seconds bug on render one); cosmetics (duration floors,
   bar full at 95k, no MB rollover). Detail + lessons: `coding-memory/branches/statusline-token-bar.md`, ADR 0005.
2. **compliance-judge (post-merge reconcile DONE 2026-07-18):** remaining loose end only —
   the store is global but writeup filenames carry no repo component (final-review
   recommendation); revisit if cross-repo spec slugs ever collide. Also: backfill the
   compliance-judge verdicts' own `outcome` fields once those specs implement (calibration
   ledger, see running-the-compliance-judge SKILL.md).
3. **memsearch debt (recorded, not blocking; ledger `.superpowers/sdd/progress.md` has detail):**
   `index` exits 0 even when errors>0 (fix before wiring automation to exit codes); validate
   `ollama_url` is loopback; busy_timeout PRAGMA; fail-fast on Ollama-down backfill; `--since`
   format validation; README sentence that digest-chunk line numbers are digest-relative.
   Memsearch-nudge SessionStart line: **VERIFIED live 2026-07-18** (fired post-/clear, 2332 chunks).
4. **Live-verify** doc-guard's PreCompact injection against a real `/compact` — still pending.
   SessionStart injection **VERIFIED live 2026-07-18**: post-/clear it surfaced the uncommitted
   verdict-store + settings.json changes exactly as designed (15-case harness had covered logic only).
5. (Optional) Retire `coding-memory/decisions.md` in favour of `docs/decisions/` (now ADRs
   0001-**0005**) — the "adopt" framing was stale, the directory was never the blocker.
   Diagramming-pointers half **DONE 2026-07-19** (PR #19), wider than this item scoped it.
5a. **Watch the next 2-3 `coding-memory/` branch logs** (ADR-0004 revisit trigger). If one lands with
   real structure and no diagram, move the `managing-session-memory:18` pointer from the
   index-description bullet into the save-time procedure section. Escalation if that also fails is a
   **gate stub, never the hook** (the hook's rejection is structural; the gate's is cost/benefit).
   Evidence: **2 of 3** — `diagramming-pointers.md` has a flowchart; `statusline-token-bar.md` now
   describes a lock protocol with real structure and carries **none** (its diagram went to ADR 0005).
   The 07-20 brainstorm write-up carries its flowchart inline (counts toward the healthy side).
6. **DONE 2026-07-21** — backfilled `outcome: clean` for the three known-clean nulls
   (`feature/observability-judge` @ fdbd7b9 + @ 381bd79, memsearch architecting @ c2b23fe)
   alongside PR #23's verdict. **CALIBRATION POLICY DECIDED 2026-07-22 (user):** on a branch with
   multiple judge rounds, the **final** round that shipped is `clean` and **earlier** rounds whose
   findings changed the code or docs before merge are `rework`. Chosen over "every round on a
   merged PR is clean" precisely because that would make the calibration history show the judge
   never prompting rework, which is false and useless for tuning it. Applied to pane-layout-v2:
   e12dc06 → `rework`, ec03621 → `clean`.
   **17 nulls remain**, now resolvable under that policy but NOT bulk-applied — each needs its
   per-branch history read to identify which round was final: statusline ×6, token-bar ×4,
   handoff ×2, pane-orch architecting ×2, verifying-subagent-commits @ 8701ca8,
   compliance-judge @ cf4efc7, and pane-layout-v2 architecting @ bb4050b. **Architecting-stage
   entries are the genuinely unclear case** — there is no merge event for a design, so "did it
   ship clean" has no direct meaning; decide that sub-policy before touching them.

**Merged** (full detail: `coding-memory/pr-tracking.md`): `.claude` PRs #10–#16 (07-16→18) —
documentation-enforcement, PORTS.md reconcile, diagramming skill, observability judge (+ judge-guard
hook, live and global), memsearch RAG index, verifying-subagent-commits, compliance judge; plus
vibe-scape (Tayvyx-Lab/VibeSpace) PRs #6–#7. **07-19:** #17 (writing-project-readmes, d242e69),
#18 (statusline, b6362ff). **07-20:** #19 (diagramming reachability + ADR 0004, a735fb4),
**#20 (statusline token bar, merged 04:01Z)**, **#21 (claude-code-handoff cherry-pick, 3c58363,
22:02Z)**, **#22 (docs-only follow-up landing PR #21's stranded judge audit trail, 284478a)**.
**07-21:** **#23 (pane orchestration, 8f40e05, 12:35Z)**, **#24 (docs-only PR #23 close-out +
outcome backfills, 23dd2e3, 13:05Z; late brainstorm-checkpoint commit stranded → cherry-picked
to main as 2d8a416)**.

**Orphans: ALL PRUNED 2026-07-20.** The 8 merged orphans (`feature/statusline-command`,
`docs/diagramming-pointers`, `feature/statusline-token-bar`, `feature/add-claude-code-handoff`,
`feature/documentation-enforcement`, `feature/modular-coding-memory`,
`feature/vibe-coding-standards-integration`, `update/update-default-model`, plus local-only
`chore/ports-registry-snatch-8001` and `feature/diagramming-skill`) were deleted local + remote
after verifying each tip is reachable from `main`. Repo now holds only `main` and the active
`feature/judge-terminal-enforcement`.
