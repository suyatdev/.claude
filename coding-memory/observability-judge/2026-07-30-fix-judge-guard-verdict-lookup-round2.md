# Observability Judge Verdict — judge-guard verdict lookup + chained detection (implementation, ROUND 2)

- **Date:** 2026-07-30 (ts 2026-07-30T16:48:23Z)
- **Repo:** judge-guard-fix (worktree `/Users/marksuyat/.claude/.claude/worktrees/judge-guard-fix`)
- **Branch:** `fix/judge-guard-verdict-lookup`
- **HEAD:** `88ccb59270a19bf3d50c5d8742a28be741d844fc`
- **Base:** `main`, merge-base `8dfe05c` — diff is 4 files, +270/−23
- **Stage:** implementation (gates the PR)
- **Round 1 verdict superseded:** `2026-07-30-fix-judge-guard-verdict-lookup.md` (pinned `97752e6`,
  risk=medium confidence=high, `execution`/`success_masking` = concern)
- **Delta since round 1:** `8037f89` (3 red tests for the newline separator) → `028510a` (fix:
  translate `\n` → `;` before lexing) → `88ccb59` (memory checkpoint)
- **Design doc:** `docs/decisions/0012-judge-guard-repo-local-verdicts-and-chained-detection.md` (read in full)
- **Test command run by me:** `bash hooks/judge-guard.test.sh` → **32 passed, 0 failed** (exit 0)

## What was changed (plain English)

The repo has a doorman (`judge-guard.sh`) who is supposed to stop you opening a pull request until a
fresh review verdict exists for exactly the commit you're shipping.

Round 1 of this branch fixed two things: the doorman was reading the wrong guest list (always
`~/.claude`'s, never the project you're actually in — so outside `~/.claude` the door could *never*
be opened by any amount of correct reviewing), and he only listened to the *first* thing you said,
so `git push && gh pr create` — two orders in one breath, the normal way the command is issued —
walked straight past him.

Round 2 adds one more fix, prompted by round 1's finding: pressing **Enter** between the two orders
also walked past him. Bash treats a line break as the end of a command, but the parser being used
treated it as ordinary spacing, so both lines merged into one and `gh` never sat where the doorman
looks. Line breaks are now converted into semicolons before parsing. That conversion order is
deliberate and explained in the ADR: splitting the raw text line-by-line instead would crash on a
quoted commit message that spans lines, and a crash here lets everything through.

## Does it do what you wanted?

Largely yes, and I verified rather than assumed:

- **I ran the suite myself: 32 passed / 0 failed**, including the 6 new newline cases.
- **I probed the live hook with 32 hand-built command lines.** Correctly **blocked**: bare
  `gh pr create`; `&&`; unspaced `push&&gh`; `;`; `||`; pipe; background `&`; subshell `( … )`;
  `$( … )`; redirect; newline; blank-line-between; CRLF; tab; newline-after-a-`&&`-chain; a leading
  newline; a heredoc followed by the command. Correctly **ignored** (false-positive protection
  intact): `git commit -m "gh pr create in the message"`, `echo gh pr create`, `gh pr list`, and a
  multi-line quoted commit message.
- **The round-1 defect is genuinely closed.** `git push`⏎`gh pr create` now exits 2 where it exited 0.
- **TDD order is real and visible:** `8037f89` touches only the test file (3 red), `028510a` only the
  hook + ADR. Separately revertible.
- **The inverted assertion is legible cold.** The test file carries a four-line comment naming the
  removed case and the motivating incident (PR #25 shipping unjudged), and ADR 0012's Consequences
  repeats it. A reader hitting `git log -p` will not mistake it for a silent behaviour flip.
- **Pre-existing `shellcheck` findings re-confirmed:** exactly two (SC2016 line 66, SC2181 line 169),
  both of a type predating the fork point. Leaving them is correct, not laziness.

## The question I was asked to answer: is the newline fix complete?

**No — one adjacent shape of the same class is still open, and it is the most plausible of the
remaining ones.**

```
git push -u origin br && \
gh pr create --fill
```
…exits **0**. A backslash line-continuation survives the `\n`→`;` rewrite as `\;`, which posix
`shlex` un-escapes into a literal `;` glued to the following token (`;gh`), so `gh` never reaches a
segment's command position. I confirmed the tokenization directly: `['git','push','&&',';gh','pr','create','--fill']`.

**This is not a regression.** I re-ran the same payload against the hook at `8037f89` (pre-newline-fix)
and it also exited 0; the merge-base tokenizer produced the same shape. It is a pre-existing sibling
of the gap this branch exists to close — but it is untested and unmentioned, exactly the criticism
round 1 made of the newline case.

Three further bypass classes I verified (all exit 0), in descending order of plausibility:

1. **A genuinely valid `gh` invocation:** `gh -R owner/repo pr create`. Matching requires
   `gh pr create` at positions 0–2. I verified `gh` really accepts this ordering — `gh -R cli/cli pr list`
   returned live data and `gh -R cli/cli pr create --help` exits 0. This is a *documented product
   form*, not an evasion.
2. **Backtick substitution:** `` echo `gh pr create` `` passes, while `$(gh pr create)` blocks. ADR 0012
   claims substitution is covered; it is covered for one of the two spellings.
3. **Compound-command bodies and command prefixes:** `{ gh pr create; }`, `if true; then gh pr create; fi`,
   `for … do … done`, `! gh pr create`, `time`/`env`/`command`/`nohup gh pr create`, `eval "…"`,
   `bash -c '…'`, and an absolute path `/opt/homebrew/bin/gh pr create`. These are evasion-flavoured
   and reasonably out of scope for a self-declared momentum guardrail.

**The signal, stated plainly:** two review rounds have each found one new shape, and I found four more
in fifteen minutes. That is not an indictment of the implementation — it is evidence that
*token-position matching against an open-ended shell grammar has a long tail*. The right conclusion is
not "keep patching until the tail is empty" (it never will be); it is to say so in the ADR, so the
next reader knows the gate catches the shapes an agent normally emits and is not a boundary.

## Rulings on the six carried-forward concerns

**1. Classifier fails OPEN and silently; this change adds a Python ≥3.6 requirement to that path.
→ DEFER-WITH-TRACKING, with a documentation rider I would do before merging.**
I reproduced it at this HEAD: a stub interpreter that fails only the classify call makes the guard
exit **0**, silently. An empty classifier output is likewise read as "no PR command → allow". You are
right that this is the most serious carried item *in principle* — the file header says "fails CLOSED:
any inability to verify blocks", and this is an inability to verify that allows.
I am nonetheless **not** ruling it blocking, for a reason I want on the record: the obvious fix —
treat empty/garbled classifier output as fail-closed — would block **every Bash command** whenever the
classifier hiccups, not just PR commands. That is a materially bigger behavioural change than the bug
it fixes, and it deserves its own reproduction and its own decision, not a rushed patch on a branch
about something else. Forcing it in here would itself be the drive-by this branch has otherwise
avoided.
What *is* in scope and cheap: this branch introduced the `punctuation_chars` (py≥3.6) dependency on a
fail-open path while the hook still falls back to plain `python`, and **ADR 0012 does not mention
that at all**. Either drop the `python` fallback (one line — a missing interpreter already fails
closed, so this converts a silent open into a loud closed) or add one Consequences bullet naming the
new requirement. Not reachable on this machine (no `python` on PATH; `python3` is 3.9.6), which is why
it is a tracked item rather than a blocker.

**2. `JUDGE_VERDICTS_FILE` is an unlogged bypass, and the real PR flow needs it. → DEFER-WITH-TRACKING,
and the second half of the premise is false — I disproved it.**
Unlogged: confirmed, `VERDICTS="${JUDGE_VERDICTS_FILE:-…}"` prints nothing, unlike `JUDGE_EXEMPT`.
A one-line `printf … >&2` would close it and is safe.
But the override **cannot** rescue the cross-checkout PR flow that `CODING_MEMORY.md`'s "Next" plans to
use it for. I built a sandbox repo named `.claude` and pointed `JUDGE_VERDICTS_FILE` at a store holding
a `repo: judge-guard-fix` verdict: still **exit 2**, because `repo` is derived from the *current*
checkout's root basename, not from the store. From the primary checkout the override does nothing;
from this worktree it is unnecessary, because the default already resolves to this worktree's store.
So the honest status is: it really is only a test override, the plan that says otherwise is wrong
(but fails safe, i.e. blocks), and it should still be logged.

**3. The gate reads the working-tree verdict file. → NOT-A-DEFECT.**
This is inherent, not overlooked. The verdict must exist *at the HEAD being shipped*, and committing
the verdict moves HEAD — so requiring a committed blob makes the gate unsatisfiable by construction.
Reading the working tree is the only coherent choice given strict freshness, and it is consistent with
the hook's self-description as a momentum guardrail. Worth one sentence in the ADR so the next reader
doesn't "fix" it.

**4. The judge → PR → commit-artifacts ordering is undocumented in the skill. → DEFER-WITH-TRACKING,
narrowed.**
I read `skills/running-the-observability-judge/SKILL.md`: it *does* say "Run the implementation verdict
as the last step before opening the PR, after the final commit. Freshness is strict…". What is missing
is the corollary — that the verdict artifacts themselves must be committed **after** `gh pr create`.
That is a two-line skill edit, and there is live evidence it bites: `CODING_MEMORY.md`'s "Next" tells
the next session to pin `028510a`, which the very memory commit that wrote that line invalidated. The
trap caught the document describing the trap.

**5. `git-guard.sh` / `merge-guard.sh` keep the identical gap, untracked. → DEFER-WITH-TRACKING.**
Confirmed: `merge-guard.sh` still uses `shlex.split` + `toks[0]`, `git-guard.sh` still matches a
leading normalized command. Deferring is correct engineering — `merge-guard.sh` gates `gh pr merge`
and deserves its own reproduction. But "tracked" currently means one CODING_MEMORY bullet that says
"tracking task unopened". Open the actual follow-up before the ADR paragraph goes cold; three hooks
now share one "momentum guardrail" phrase with materially different behaviour.

**6. Repo identity is a directory basename. → NOT-A-DEFECT (fails safe), with a sharper corollary.**
Combined with the new repo-local store, the operational rule is now: **open the PR from the same
checkout you judged in.** Nothing else works — and per ruling 2, `JUDGE_VERDICTS_FILE` cannot paper
over it. One Consequences line in ADR 0012 saying so would save the next person the discovery.

## Other items I was asked to scrutinize

- **The inverted assertion:** adequately legible. Test comment names the removed case and PR #25; ADR
  Consequences carries it as its own bullet. Pass.
- **The two unfixed `shellcheck` findings:** correct call. Fixing them here would be a drive-by, and
  SC2016 is a genuine false positive. The only nit is that the repo's own convention (a
  `# shellcheck disable=` line carrying a reason) is not applied — but applying it *would itself be*
  the drive-by, so leaving them is self-consistent. Not a concern.
- **The ADR-number collision found during the merge:** good catch, and the generalised lesson ("check
  ADR numbers after every long-lived-branch merge — git will not flag it") is recorded in
  `CODING_MEMORY.md`, which is the right place. Exemplary audit behaviour.
- **The classifier python inside a single-quoted shell string:** the containment is currently a
  comment ("NOTE: no apostrophes in this block") plus a `shellcheck` SC1011 backstop, bought at the
  cost of 15 spurious test failures. That is *adequate but fragile*: the invariant is enforced by
  human attention on every future edit. My view — extracting it to `hooks/lib/classify-pr-command.py`
  would remove the trap permanently, make it directly unit-testable (all my probes above had to go
  through the whole hook), and shrink the hook. But that is a refactor, and this branch is right not
  to do it mid-fix. Recommend it as the follow-up that pairs naturally with the git-guard/merge-guard
  task, since all three hooks embed the same style of block.

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | Both original defects fixed exactly as ADR 0012 describes; round-1's newline defect closed as well. Store resolution from repo root and per-segment matching both verified live |
| execution | concern | Suite 32/0 re-run by me and 32 probes confirm the fixed shapes; but `&& \`⏎ still exits 0 (verified pre-existing, not a regression), as do backticks, `gh -R … pr create`, and compound-command bodies — untested and not in the ADR |
| trajectory | pass | Round-1 finding reproduced independently before acting, fixed in strict red→green order in two commits, and the *rejected* alternative (per-line split) is recorded with the reason it is worse (fails open). Reasoning, not luck |
| regression | pass | Diff confined to hook + test + ADR + memory; every false-positive case re-verified green by me; the continuation bypass proven pre-existing by running the hook at `8037f89`. Minor smell only: the `\n`→`;` rewrite leaves a `;`-prefixed argument token after a continuation (harmless for classification) |
| context_budget | pass | Hook code, not always-on context. No rule or skill text added; +46 lines to CODING_MEMORY's Active Session block, which is that file's purpose |
| traceability | pass | ADR 0012 carries the newline decision, its rejected alternative, and the apostrophe trap; in-code comments explain why `punctuation_chars` and translate-before-lex are load-bearing; the absent-store error names the exact path |
| success_masking | concern | 32 green tests coexist with four verified bypass shapes; no test asserts the classifier-failure path, so a crashing classifier and a healthy one produce an identical green suite. Fail-open on classifier crash re-proved at this HEAD with a stub interpreter |
| intent_drift | pass | No drive-bys (shellcheck findings verified pre-existing and left), no new dependencies (`shlex` is stdlib), sibling hooks deliberately deferred with a stated reason, ADR renumber is merge hygiene |
| checkpoint | pass | Seven small commits, red-then-green split at both rounds, revert points throughout; the only working-tree changes are this judge's own artifacts, not source |
| audit_trail | pass | ADR + CODING_MEMORY + commit messages agree; the inverted assertion is documented in two places; round 1's finding and its fix are recorded with the mechanism. One stale line: "Next" pins `028510a`, invalidated by the commit that wrote it |

## Roll-up

- **Risk:** medium (unchanged from round 1 — round 1's top concern is closed, but the same defect
  class produced another instance, and the fail-open is untouched)
- **Confidence:** high

## Concerns

1. Backslash line-continuation (`git push && \`⏎`gh pr create`) still exits 0 — verified; the newline
   fix does not cover it. Pre-existing, not a regression, but untested and unmentioned in ADR 0012.
2. `gh -R owner/repo pr create` — a valid, verified `gh` invocation — bypasses the gate, because
   matching requires `gh pr create` at positions 0–2.
3. Backtick substitution bypasses while `$( … )` blocks; ADR 0012 claims substitution is covered.
4. Classifier failure fails OPEN and silently (re-proved at this HEAD); this change adds a Python ≥3.6
   requirement to that path while the hook still falls back to plain `python`, and ADR 0012 does not
   disclose the new requirement.
5. `JUDGE_VERDICTS_FILE` is an unlogged bypass — and it provably cannot rescue the cross-checkout PR
   flow that `CODING_MEMORY.md`'s "Next" plans to use it for (repo identity is the checkout's basename).
6. The skill documents "judge last, after the final commit" but not the corollary that verdict
   artifacts must be committed *after* `gh pr create`; CODING_MEMORY's own "Next" already pins a SHA
   that trap invalidated.
7. `git-guard.sh` / `merge-guard.sh` keep the identical chained gap, still with no opened follow-up.
8. The classifier's python lives in a single-quoted shell string where one apostrophe breaks the whole
   hook; contained only by a comment plus a shellcheck backstop, and not directly unit-testable.
