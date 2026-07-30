# Observability verdict — phase-guard-hook, RUN 5 (post-audit)

- **repo:** phase-guard-hook (worktree of `~/.claude`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `b25efdf08a5a9bb1b8153d583c0dabe9d01365dc`
- **stage:** implementation (gates the PR)
- **ts:** 2026-07-28T20:21:18Z
- **risk:** medium · **confidence:** high

> **No dimension is `fail` this round** — both RUN 4 failures are demoted to `concern`. That is a
> real improvement and I am not inflating it.
>
> **But the class is not closed, and I was asked to say so plainly.** The current suite still
> asserts silence in two cases with the *identical structure* the commit message calls "what the
> class looked like from inside" — `A1.4` and `A1.5`, sitting a few lines above the four cases the
> audit converted, in the same `$OPTED` fixture. I reproduced the hole they hide, with controls.

---

## What was changed

The night watchman analogy again. The last four inspections each found a spot where the watchman
went quiet instead of shouting — and a quiet watchman is indistinguishable from one who checked and
found nothing wrong.

This round the team stopped chasing the next quiet spot and instead **wrote down every single way
the watchman can stop early**, then decided for each one whether silence is honest ("nobody asked
me to check this building") or dishonest ("I was walking over to shout and something tripped me").
Sixteen exits, ten silent, six that now speak.

Applying that rule uniformly fixed the hole the last inspection found (the watchman can't see the
desk at all) **and four nobody had reported** — three different ways a `git` command can stumble
mid-check. Two new spoken reasons were added, each still capped at one line per session.

**The best thing in this change isn't a bug fix.** Those four git cases were not missing from the
test suite. The suite was *actively asserting that silence was correct* for them. Four inspections,
including mine, had read that suite as proof the code was fine. Finding that is worth more than any
individual patch, and the commit message says so honestly.

## Does it do what you wanted?

**Yes on method, partly on coverage.**

**Verified myself, first-hand:** the suite really runs and really passes (104 passed / 0 failed);
`shellcheck -x` is clean on both files; the tests were committed *before* the fix (`92f840c` →
`b25efdf`) so the fix had to earn its green; and the RUN 4 permission hole is genuinely closed with
controls that deny either side.

**Where it falls short — my primary assignment was "audit the audit", and the audit has two gaps:**

**1. THE RULE printed at the top of the file is not the rule the code follows.** It says the hook
speaks once it knows the repo is opted in *and* holds an un-superseded `planning` card. I tested all
three non-git warnings in a repo with **no planning card at all**:

| Warning | Planning card present? | Spoke? |
|---|---|---|
| `nopython` | no | **yes** |
| `noparse` | no | **yes** |
| `nolist` | no | **yes** |

So the operative rule is really *"opted in **and** couldn't finish the evaluation"* — a weaker,
better rule. That matters because the stated rule is the spec's whole justification for the ten
silent rows, and under the rule the code *actually* implements, one of those rows is misclassified.

**2. That misclassified row hides a fifth instance, upstream of everything — the payload parse
(step 4).** In an opted-in repo with a real un-superseded `planning` card on an unclaimed branch:

| Payload | Result |
|---|---|
| valid (control) | **exit 2**, full deny |
| truncated JSON | **exit 0, stderr EMPTY** |
| valid JSON, key renamed `file_path`→`filePath` | **exit 0, stderr EMPTY** |
| not JSON at all | **exit 0, stderr EMPTY** |
| `tool_input` missing | **exit 0, stderr EMPTY** |
| valid (control) | **exit 2**, full deny |

The spec's silent table justifies this as "Nothing to judge." The hook does not *know* there was
nothing to judge — it failed to read. This is not hypothetical: the code comment at step 4 records
that `NotebookEdit` carries `notebook_path`, not `file_path`, and that reading `file_path` alone
"would fail open on every notebook write." **That exact failure already happened once during
development** and was caught by inspection, not by a warning. A future key rename does it again,
silently, machine-wide, permanently.

**And the suite enforces it.** `allow_silent` asserts exit 0 + empty stdout + **empty stderr**.
Against `$OPTED` — the on-its-way-to-deny fixture — the suite asserts:

- `A1.4 non-empty stdin that is not JSON (step 4)` → silent
- `A1.5 neither file_path nor notebook_path (step 4)` → silent

These are the same two lines of code I falsified above, in the same fixture, a few lines above
`A1.8`–`A1.10b`. The audit reached down the file, converted four, and left two of identical shape.
That is the direct answer to "what else does the suite assert that encodes the bug?"

## What could go wrong / what I'm unsure about

Ordered by how much it should actually worry you.

- **The step-5 symlink route (assignment 3) is still open and is the worst single item.** Re-verified:
  physical path → **exit 2**; the same file addressed through a symlinked form of the repo path →
  **exit 0, silent**; physical again → **exit 2**. Blast radius is the largest of anything here —
  the guard is off for that *entire repo*, permanently, invisibly, and it looks exactly like a
  working guard. Probability depends entirely on directory layout (macOS `/tmp`→`/private/tmp` and
  `/var`→`/private/var` are the classic bite; a `~/Code` symlink to another volume is plausible;
  this repo's own path is not symlinked). **The audit that claims to enumerate every exit did not
  include it** — the silent table's row "Path outside the root | 5 | Not ours to judge" is exactly
  the false determination in this case, and the only place it is written down is a *test-fixture
  gotcha* note at spec line 879, still framed as "fixed test-only." The harness's `pwd -P` workaround
  is the tell.
- **Detached HEAD (assignment 1) is misclassified, and the stated reason is self-contradicting.**
  The spec justifies its silence as "a rebase issues many writes and a line per write is noise."
  `warn_once` exists precisely to make it **one line per session** — so the reason given is
  contradicted by the hook's own mechanism. Worse, this row *inverts* an outcome: no branch means no
  claim can match, which logically means deny; the hook allows. That fits the design's own
  definition of must-speak. Verified: `git checkout --detach` → exit 0 silent; back on `main` →
  exit 2. Two real consequences: **during any rebase, conflict-resolution edits to source are
  unguarded and unannounced**, and a one-command session-long bypass exists for a guard whose deny
  message says "There is no bypass environment variable; this guard ships without one by design."
  Literally true, but it reads as a broader assurance than it is.
- **`git` missing from PATH is silent, with the same blast radius as `python3` missing, which is
  audible.** Verified: planning card present, `git` absent → exit 0, stderr empty. The `nopython`
  message says "not being enforced in any repo until that is fixed" — identical consequence, and
  the classification is asymmetric for no forced reason (`command -v git` is as available as
  `command -v python3`).
- **`docs/features/` as a dangling symlink turns the guard off for the repo, silently.** Verified:
  live target → deny; target moved away → **exit 0 silent**; restored → deny. Same shape as
  escalation 10 (the dangling-symlink *card*) one level up, at the container. Genuinely hard to
  distinguish from "never opted in"; low probability. Reporting, not scoring heavily.
- **`HOME` unset → exit 1 on every write in every repo** (line 48, `${...:-$HOME/...}` under
  `set -u`), with a raw bash error on stderr. The file's own header says "No other exit code is
  legitimate … a fail-open path that leaks a nonzero code is a defect regardless of how the harness
  classifies it." Low probability; fails open and noisily rather than silently; but it is a
  normative statement in the spec (line 502) falsified by one command.
- **A repo with no commits prints a misleading message.** Unborn HEAD + planning card → *"a git
  query needed to finish the phase check failed"*. Nothing failed; there is simply no commit. It
  fails open and audibly — the right direction — but sends the reader hunting a git fault that does
  not exist. Diagnosability nit.
- **Assignment 5, the `length($0)` portability nit: confirmed unchanged and confirmed low.** No
  locale is pinned anywhere in the hook (`grep` for `LC_ALL`/`LANG` finds nothing) and this machine's
  awk is BWK 20200816. RUN 4 tried and failed to construct a false supersession and observed the
  failure direction as fail-*closed*. I did not re-derive that; I accept it. Severity: low, carried.
- **Honest calibration.** Every survivor is *less* reachable than the ones that were fixed. The
  permission and symlink cases need a user action or an unusual layout; the payload cases need the
  harness itself to malfunction or drift. And every failure mode here fails **open** — the worst
  outcome is "the phase gate is enforced by judgment alone", i.e. exactly today's status quo before
  this hook existed. Nothing here causes a false block or damages a session. That is why I moved
  risk from `high` to `medium` rather than holding it.
- **Still never run live** (carried from RUN 3, unchanged). Every result — the team's, RUN 4's, and
  every one of mine — comes from throwaway fixtures. I cannot close this one for you.
- **Carried, unchanged:** branch-granularity hole; rollback path 3 broken and withdrawn (exit 126,
  classification deliberately unverified); second-order cost on `main` and hotfix branches; the
  duplicate verdict files under two naming schemes (`2026-07-25-worktree-*` vs `2026-07-28-feature-*`)
  that RUN 4 flagged are still both present.

## What I'd double-check before merging

1. **Restate THE RULE to match the code**, then re-run the classification under it. The honest
   version is *"opted in, and the evaluation could not be completed."* Under that rule, step 4's
   payload exits move to audible on their own.
2. **Convert `A1.4` and `A1.5`** the way `A1.8`–`A1.10b` were converted, and route the step-4
   no-path exit through `warn_once` with its own reason. One line per session is the entire cost.
3. **Decide the step-5 symlink route explicitly** — resolve both sides (`pwd -P` / `realpath` on the
   payload path) or write it into the silent table as a named, accepted blind spot. Third round it
   has been raised; it is currently neither fixed nor specified, only worked around in the harness.
4. **Fix the detached-HEAD justification**, and decide whether that row speaks. If it stays silent,
   say the true reason ("a rebase must be able to resolve conflicts") rather than the `warn_once`-
   contradicted one, and note in the spec that a detached HEAD disables the guard.
5. **Soften or scope the deny message's last line.** "There is no bypass environment variable" is
   true; a reader will hear "there is no bypass." There are at least two.
6. **Guard `$HOME`** (`${HOME:-}` with an explicit fallback) so the hook cannot exit 1.
7. **Run it live at least once** before merge — still open from RUN 3.
8. **Surface the parallel-worktree collision in the PR description**, as already agreed.

---

## Dimensions

| Dimension | Verdict | Basis |
|---|---|---|
| `intent` | concern | The brief was "audit, don't patch the fifth instance," and the audit was genuinely done — five exits closed, four previously unreported. But its stated boundary rule is falsified by its own implementation (verified 3/3), and the audit that claims to enumerate every exit omitted the step-5 route already on the table from RUN 4. |
| `execution` | concern | I ran it: 104 passed / 0 failed, `shellcheck -x` clean, RUN 4's instance genuinely fixed with controls either side. But a silent fail-open survives at HEAD (step 4 payload parse), reproduced with passing controls. |
| `trajectory` | pass | This is the round the reasoning changed shape: enumerate rather than chase, tests before fix, four exits found that no judge had reported, and — the most valuable finding in five rounds — the recognition that the suite was *enforcing* the bug rather than missing it. The residual classification error does not undo a method that is now self-correcting. |
| `regression` | pass | 104/0, deny path intact, no new noise: the justifiably-silent exits I probed (exempt paths, outside-root, detached HEAD, not-opted-in, claimed branch) all stayed silent. Two tight commits, nothing adjacent touched. |
| `context_budget` | pass | One line in `rules/gates.md` (always-on). The 1,500-line spec is on-demand under `docs/`. |
| `traceability` | concern | **Up from `fail`.** RUN 4's two false statements are now true — I re-checked both. But THE RULE, the spec's new headline claim and the justification for all ten silent rows, is falsified by the implementation; three silent-row justifications ("Nothing to judge", "Out of scope entirely", the detached-HEAD noise argument) are wrong; and "No other exit code is legitimate" (line 502) is falsified by `HOME` unset → exit 1. Fourth consecutive round with a false normative sentence in this area — but the operational tables are now accurate, which is why this is not `fail`. |
| `success_masking` | concern | **Up from `fail`.** `A1.4`/`A1.5` still assert *empty stderr* against `$OPTED` for exactly the exits I falsified — the identical structure the commit message identifies as "what the class looked like from inside", a few lines above the four it converted. 104 green, including a group named "the fail-open audit", reads as an enumerated surface; it is not. Not `fail` because the previously-masked instance is now pinned red-then-green and the residual triggers require the harness itself to malfunction. |
| `intent_drift` | pass | Two commits, both on topic. No scope creep, no drive-by edits, no new dependencies. The fifth-instance patch was explicitly *not* written, as instructed. |
| `checkpoint` | pass | Tests committed before the fix (`92f840c` → `b25efdf`), preserving the unbiased baseline; clean granular revert points. |
| `audit_trail` | pass | Commit messages explain the *why* including the self-criticism; spec escalation 13 records the pivot; ADR 0011 stands. Minor, carried: duplicate verdict files under two naming schemes still unreconciled. |

## Concerns

- Fifth instance of the silent-guard class at HEAD: step 4's payload parse (truncated JSON, non-JSON, renamed/absent path key) exits 0 with empty stderr in an opted-in repo holding an un-superseded planning card — verified with controls denying either side.
- The suite still encodes the class: `A1.4`/`A1.5` assert empty stderr against `$OPTED`, the identical structure to the four `A1.8`–`A1.10b` cases the audit converted.
- THE RULE as stated ("opted in AND holds an un-superseded planning card") is not the rule implemented: `nopython`, `noparse` and `nolist` all speak with no planning card present — verified 3/3.
- Step-5 symlink route still open and unspecified after two rounds; largest blast radius of any survivor (whole repo, permanent, silent); documented only as a test-fixture gotcha.
- Detached HEAD misclassified as justifiably silent, with a reason (`per-write noise`) contradicted by `warn_once`; leaves rebase conflict-resolution edits unguarded and gives a one-command session-long bypass.
- `git` missing from PATH is silent with the same machine-wide blast radius as the audible `nopython` exit.
- `docs/features/` as a dangling symlink silently disables the guard for the repo.
- `HOME` unset makes the hook exit 1 on every write, falsifying the spec's "no other exit code is legitimate".
- Unborn-HEAD repo emits a misleading "git query failed" message; diagnosability nit.
- `awk length()` byte-vs-character portability with no locale pinned — carried, low, direction observed fail-closed.
- Hook has still never been run live; every result including all of mine is from fixtures.
- Parallel-worktree collision still an open user-owned decision, owed to the PR description.
