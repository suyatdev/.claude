# Observability verdict — phase-guard-hook, RUN 6 (final)

- **repo:** phase-guard-hook (worktree of `~/.claude`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `9996c0b78f6858b3cd53a5765a064f478aaa99e1`
- **stage:** implementation (gates the PR)
- **ts:** 2026-07-28T20:36:39Z
- **risk:** medium · **confidence:** high

> **No dimension is `fail`.** All six claimed fixes are real — I verified every one myself with
> controls on both sides, on my own fixtures, not theirs.
>
> **The direct answer to the question that decides shipping: the class is NOT formally closed.**
> One silent exit of the identical shape survives *inside the code this commit added* (step 5's
> physical-resolution failure), and the same commit introduced a second silent fail-open on a
> malformed path. Both are materially weaker than any of the five closed. Separately I found a
> larger, previously unexamined surface — **the guard's repo root comes from the hook's working
> directory, not from the payload** — which no round has probed. What I probed and what I found is
> enumerated below.

---

## What was changed

The night watchman again. Five inspections found five places where he went quiet instead of
shouting — and a quiet watchman looks exactly like one who checked and found nothing.

This round closed all six items the last inspection raised: the watchman now shouts when someone
hands him an unreadable note (the payload), when the building is reached by its nickname instead of
its street address (the symlinked repo path), when he's mid-rebase with no branch under him, when
`git` is missing entirely, and he no longer falls over when `HOME` is unset. Two test commits landed
*before* each fix commit, so the fixes had to earn their green.

## Does it do what you wanted?

**Yes on all six. No on "the class is closed."**

**Verified first-hand, on my own harness:**

| Claim | My probe | Result |
|---|---|---|
| Payload parse speaks | truncated JSON, non-JSON, renamed key, missing `tool_input` — each with a **fresh flag store** so no once-per-session cross-talk | all 4 **audible**, exit 0; valid payload and `notebook_path` controls **deny** either side ✓ |
| Symlinked repo path | file via `ln -s` repo dir; via `/tmp` vs `/private/tmp`; deep not-yet-existing dirs | all **deny**; exempt `docs/*` via the symlink still silent; genuinely-outside still silent ✓ |
| Detached HEAD | `checkout --detach` → write → back to `main` | allow **+ audible**, then deny ✓ |
| `git` missing | minimal PATH with everything but `git` | **audible**; `python`-missing sibling control also audible ✓ |
| `HOME` unset | `env -u HOME` | **exit 2, full deny**, no bash error ✓ |
| Suite + lint | ran both | **108 passed / 0 failed**; `shellcheck -x` clean ✓ |

`A1.11` is genuinely gone; no two assertions in the suite now demand opposite things of one exit.

**Where it falls short.**

**1. The rule was restated in one of the three places it is written.** The spec's copy is now
correct. But `hooks/phase-guard.sh` lines 30–36 still carry the *exact sentence RUN 5 falsified* —
"once this hook knows the repo is opted in **and holds an un-superseded `planning` card**". I
confirmed the fix commit never touched that block (`git diff b25efdf..9996c0b` shows no change
there) and re-falsified it: in a repo with a `review` card and **no planning card at all**,
`nopayload`, `nolist` and `noparse` all speak. The same block is stale in its counts ("four of the
cases below were previously asserted SILENT" — it is six; "Four judge rounds" — it is five).
`hooks/phase-guard.test.sh` (~lines 845–855) carries the old rule too, and still lists *"no usable
path in the payload"* and *"detached HEAD (deliberate — a rebase issues many writes…)"* among the
justifiably-silent — contradicting `A1.4`/`A1.5`/`A4.6` in its own file.

This matters beyond tidiness: the wrong rule in the source is precisely the mechanism by which this
bug class propagated for five rounds. Someone deciding whether a *new* exit should warn will read
the hook, not the spec.

**2. The newly written exception clause is itself half false.** The spec now says "a missing `git`
or `python` speaks even though it is **upstream of the opt-in test**". `git` is checked at step 2
(upstream — verified: it speaks in a plain non-repo directory). **`python` is checked at step 4,
downstream of the step-3 opt-in test** — verified: no python, repo *not* opted in → **silent**. The
classification outcome is fine; the stated reason is wrong. Sixth consecutive round with a false
normative sentence about this one rule.

**3. A sixth instance, inside the new code.** Step 5's walk-up ends in
`[ -n "$fp_phys" ] || exit 0` — silent, downstream of the opt-in test, an inability to complete the
evaluation. That is a must-speak under the spec's *own newly restated rule*, and it is in neither
table. Reproduced with controls:

| Case | Result |
|---|---|
| symlinked route, normal path (control) | **exit 2, deny** |
| symlinked route, ancestor dir at mode 000 | **exit 0, stderr EMPTY** |
| same path, permissions restored (control) | **exit 2, deny** |

Reachability is genuinely low: it needs the symlink route *and* a non-searchable ancestor, and in
that state the write itself would fail. I am reporting it as a formal member of the class, not as a
practical hazard.

**4. A new silent fail-open the commit introduced.** A payload path with no directory component
(`"a.ts"`) makes the walk-up settle on `.`, and the reattachment concatenates without a separator.
Traced live: `fp_dir=[.] fp_phys=[/private/tmp/…/opted] phys_path=[/private/tmp/…/opteda.ts]` — the
missing slash. Result: **exit 0, silent**. The spec says payload paths are absolute, so this is
out-of-contract input — but `grep` finds **zero** relative-path cases in the 108-test suite, and
"validate input at system boundaries" is a house rule.

## What could go wrong / what I'm unsure about

Ordered by how much it should actually worry you.

- **The repo root is derived from the hook's CWD, not from the payload — nobody has probed this in
  six rounds.** Verified: with CWD outside the target repo, or in a *different* non-opted-in repo, a
  write into an opted-in repo holding an active planning card → **exit 0, silent**, while the same
  write with CWD inside denies. `grep` finds no CWD assumption in Non-goals; the only mentions are
  internal notes explaining why step 3 follows step 2. Whether this is reachable depends entirely on
  whether Claude Code always sets hook CWD to the project root — **which has never been checked
  live**. If it doesn't, this is the largest hole in the design and a one-line fix
  (`git -C "$(dirname "$file_path")" rev-parse …`). This is the item I would most want confirmed
  before merge.
- **The three-copies rule drift (above).** The single most likely cause of a seventh instance.
- **Step-5 resolution failure + the relative-path concat (above).** Formally the class, practically
  minor, both fail open.
- **Carried, re-verified unchanged:** an unreadable `.git` in an opted-in repo → silent (step 2
  cannot distinguish it from "not a repo"); a **dangling `docs/features` symlink** → silent (a live
  symlink works correctly — I checked both); an **unborn HEAD** still emits the misleading "a git
  query … failed" when nothing failed.
- **`warn_once` is not atomic.** 12 concurrent runs on one store printed **9** lines; 3 sequential
  runs printed **1**. Fails in the safe direction (more warning, never less). Cosmetic.
- **RUN 4's `awk length()` portability nit — confirmed unchanged, and I revise its direction.** No
  locale is pinned anywhere (`grep` for `LC_ALL`/`LANG`: none). This machine's awk is BWK 20200816
  and is byte-oriented — I measured it (`length("héllo")` = 6 = its byte count), so **there is no
  exposure here today**. On a gawk + UTF-8 machine `length($0)` counts characters while
  `git cat-file --batch` reports bytes, so consumption under-counts once per multibyte character —
  and these feature cards are full of em-dashes. Misalignment attributes a later blob's lines to the
  earlier path, which can mark a card superseded that isn't: **a wrong allow, i.e. fail-open**, not
  the fail-closed RUN 4 reported. I **derived** that mechanism from the code; I did **not** execute
  it — gawk is not installed here. One-line fix (`LC_ALL=C`). Severity today: none. Severity if this
  dotfiles repo ever runs on a gawk box: this same class, silently.
- **Two commit SHAs in the summary I was handed do not exist in this repo.** `ff8a02c` and
  `2b81ce1` are cited as the test commits; `git cat-file -t` cannot find either. The real ones are
  `07c1698` and `9eef24a`. I re-derived the ordering independently and the **test-before-fix
  discipline does hold** both times (`92f840c`→`b25efdf`, `07c1698`/`9eef24a`→`9996c0b`) — so the
  claim is true and the citation is wrong. Flagging it because a subagent-commit gate exists in this
  repo for exactly this failure mode.
- **Still never run live.** Confirmed. Every result — mine, and all five prior judges' — is from
  throwaway fixtures. `settings.json` registers `$HOME/.claude/hooks/phase-guard.sh`, so merging
  installs this on **every** `Edit`/`Write`/`NotebookEdit` on the machine.
- **Honest calibration.** Every survivor fails **open**. The worst outcome across all of them is
  "the phase gate is enforced by judgment alone" — which is the status quo before this hook existed.
  Nothing here causes a false block or damages a session. That is why this is `medium` and not
  `high`, and why the residuals do not, in my view, justify a sixth revise loop.
- **Carried, unchanged:** parallel-worktree collision (user-owned, owed to the PR description);
  what a non-card file in `docs/features/` means (user-owned); branch-granularity hole; rollback
  path 3 broken and withdrawn (exit 126, classification deliberately unverified); second-order cost
  on `main` and hotfix branches; duplicate verdict files under two naming schemes.

## What I'd double-check before merging

1. **Run it live once.** Sixth round this has been open, and it now also answers the CWD question
   below. One session, one deliberate blocked write, one allowed write on a claimed branch.
2. **Confirm the hook's CWD is always the repo being written to.** If it is not, fix the root
   derivation to come from the payload path. This is the only finding here with a large blast radius.
3. **Fix the rule in the hook and in the test file**, or delete both copies and point at the spec.
   Three copies of a rule that has been wrong six rounds running is the mechanism, not the symptom.
4. **Correct the exception clause** — `python` is downstream of the opt-in test, `git` is upstream.
5. **Two one-line hardening fixes** if you want the class formally closed: route step 5's
   `fp_phys=""` exit through `warn_once`, and reject a non-absolute payload path explicitly instead
   of computing a corrupt one.
6. **Pin `LC_ALL=C`** on the two awk invocations. One line, removes a portability fail-open forever.
7. **Surface the two user-owned decisions in the PR description**, as already agreed.

---

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | concern | All six assigned fixes landed and I verified every one with controls. But the headline claim "the rule now matches the code" holds in one of three places it is written; the newly-authored exception clause is half false (`python` is downstream of the opt-in test — verified silent); and the enumeration that claims completeness missed a silent exit inside its own new code. |
| `execution` | concern | I ran it: 108/0, `shellcheck -x` clean, six fixes reproduced with controls denying either side. Against that: one member of the class survives in the new step-5 code (reproduced, controls both sides), and the same commit introduced a second silent fail-open on a directory-less path (mechanism traced). Both fail open; both are materially weaker than the five closed. |
| `trajectory` | pass | The strongest dimension. Tests committed before the fix in both rounds (verified independently), five instances closed, every judge finding absorbed rather than argued, and the commit message states its own prior error plainly. Residuals get shallower each round — that is convergence, not luck. |
| `regression` | pass | 108/0. Deny path intact; exempt paths still silent *through the symlink route*; genuinely-outside still silent; justifiably-silent exits I probed added no new noise. The new concat defect touches only out-of-contract relative paths. Two tight commits, nothing adjacent touched. |
| `context_budget` | pass | One sentence added to `rules/gates.md` (always-on). The 1,585-line spec is on-demand under `docs/`. |
| `traceability` | concern | The spec's copy of THE RULE is now correct — a real improvement I re-derived from the code. But `hooks/phase-guard.sh:30-36` still carries the sentence RUN 5 falsified (untouched by this commit; re-falsified 3/3 by me), with stale counts; `phase-guard.test.sh:~845-855` carries the same stale rule and lists two exits as silent that its own assertions now prove audible; and the new exception clause is half wrong. Sixth consecutive round with a false normative sentence about this rule. Not `fail` only because the canonical doc is now right and the operational tables are accurate. |
| `success_masking` | concern | `A1.4`/`A1.5` converted and `A1.11` removed — the specific masking RUN 5 found is gone, and I confirmed no contradictory assertion pair remains. But the suite's own explanatory comment still describes the pre-fix classification, so an auditor reading the suite's prose gets the old picture; and 108 green covers none of: step-5 resolution failure, any relative payload path (grep: 0 cases), CWD-outside-repo, dangling `docs/features`. |
| `intent_drift` | pass | Four commits, all on topic. No scope creep, no drive-by edits, no new dependencies. Spec updated in place per one-canonical-file discipline. |
| `checkpoint` | pass | Tests committed before the fix in both rounds, preserving the unbiased baseline; clean granular revert points; each commit independently revertible. |
| `audit_trail` | concern | The repo's own trail is strong: honest commit messages, ADR 0011 stands, spec escalations 14–16 recorded. Deducted because the decisions summary I was handed cites two commit SHAs (`ff8a02c`, `2b81ce1`) that do not exist in this repo — the claim they support is true, but a wrong SHA in a handoff is the exact failure the subagent-commit gate exists to catch. Duplicate verdict-file naming schemes still unreconciled. |

## Concerns

- Class not formally closed: step 5's physical-resolution failure (`fp_phys=""`) exits 0 silently in an opted-in repo with an active planning card — inside the code this commit added, and a must-speak under the spec's own newly restated rule. Reproduced with controls denying either side; low reachability.
- New silent fail-open introduced by this commit: a payload path with no directory component concatenates without a separator (`$root` + `a.ts`), yielding a corrupt path and a silent allow; zero relative-path cases in the 108-test suite.
- Repo root is derived from the hook's CWD, not the payload — writes into an opted-in repo from a session whose CWD is elsewhere are silently unguarded. Unprobed in six rounds, undocumented in Non-goals, and unverified live.
- THE RULE was restated in the spec only: `hooks/phase-guard.sh:30-36` still carries the sentence RUN 5 falsified (re-falsified 3/3), with stale counts; `phase-guard.test.sh:~845-855` carries the old rule and lists two exits as silent that its own assertions prove audible.
- The new exception clause is half false: `python` is checked at step 4, downstream of the opt-in test — verified silent in a non-opted-in repo — while the spec says both `git` and `python` speak from upstream of it.
- Carried and re-verified: unreadable `.git` in an opted-in repo → silent; dangling `docs/features` symlink → silent; unborn HEAD emits a misleading "git query failed".
- `warn_once` is not atomic — 12 concurrent runs printed 9 lines vs 1 sequential; fails in the safe direction, cosmetic.
- `awk length()` byte-vs-character with no locale pinned: no exposure on this machine (BWK awk is byte-oriented, measured), but on gawk + UTF-8 the mechanism points to a wrong ALLOW (fail-open), revising RUN 4's fail-closed reading. Derived from the code, not executed — gawk is not installed here.
- Two commit SHAs cited in the decisions summary do not exist in this repo; the underlying test-before-fix claim is true and I re-derived it from the real SHAs.
- Hook has still never been run live; merging registers it on every Edit/Write/NotebookEdit machine-wide.
- Parallel-worktree collision and the meaning of a non-card file in `docs/features/` remain open, user-owned, and owed to the PR description.
