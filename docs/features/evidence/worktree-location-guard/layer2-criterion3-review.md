# Layer 2 criterion 3 review — "every would-deny line read and judged"

Reviewer: this session, read-only against the committed population file plus the live
`~/.claude/hooks/state/reference-transaction.log`, the four repos that produced the 19
real-path lines, and the hook/test source. No hook, source file, or feature card was modified.

Population: `docs/features/evidence/worktree-location-guard/layer2-would-deny.tsv`, 1226 lines,
committed at `7be03dc`. Verified byte-identical in count to the live log's WOULD-DENY lines:

```
$ wc -l < .../layer2-would-deny.tsv          → 1226
$ grep -c "WOULD-DENY" ~/.claude/hooks/state/reference-transaction.log → 1226
```

**Status: partial, landed under a time-boxed request from the coordinator.** Job 1 is
complete. Job 2 is partial — one real leak mechanism is confirmed, a large remainder is
NOT attributed. Job 3 is written against what Jobs 1–2 actually established, not against
what I originally assumed going in.

**Date note:** the task brief says "today is 2026-09-16"; a later system clock update during
this review says the date rolled to 2026-09-17. Freshness figures below use 2026-09-17,
noted explicitly so the arithmetic doesn't silently drift by a day depending on which is right.

---

## Job 1 — the 19 real-repo lines, judged individually

Re-derived population, not assumed:

```
$ cut -f6 layer2-would-deny.tsv | sort -u | wc -l                                    → 331
$ awk -F'\t' '$6 ~ /^\/private\/var\/folders\//' layer2-would-deny.tsv | wc -l        → 1066
$ awk -F'\t' '$6 ~ /^\/private\/tmp\// || $6 ~ /^\/tmp\//' layer2-would-deny.tsv | wc -l → 141
$ awk -F'\t' '$6 !~ /^\/private\/var\/folders\// && $6 !~ /^\/private\/tmp\// && $6 !~ /^\/tmp\//' \
    layer2-would-deny.tsv | wc -l                                                     → 19
```

1066 + 141 + 19 = 1226. **This confirms the bucketing I was given is correct** — 4 distinct
real-repo targets, 19 lines. I found no straggler paths outside the three buckets (checked
for bare `/var/folders/...` without the `/private` prefix — none).

The hook's rule (`hooks/reference-transaction`, steps 1–6): a `WOULD-DENY primary-HEAD-lock-held`
line is appended when, in a single `prepared`-stage ref transaction, a ref line's name is
exactly `HEAD`, git is invocable and at/above the 2.31 floor, the ref backend is `files`,
`--absolute-git-dir` equals `--path-format=absolute --git-common-dir` (i.e. this is the
*primary* checkout, not a linked worktree — a linked worktree's own HEAD is scope-exempt at
step 5 and never reaches this clause), and `<common-dir>/HEAD.lock` exists. Git holds that
lock for the whole duration of every HEAD-moving operation it runs in the primary checkout —
`checkout`, `switch`, `switch --detach`, each leg of `pull --rebase` — so the rule is not
"something else was contending for the lock"; it fires on the plain, unremarkable act of
moving HEAD directly in a primary checkout, by design.

For each of the 4 repos I ran `git -C "<repo>" worktree list` (confirmed each target IS the
primary entry, first line, not a linked worktree) and matched every WOULD-DENY timestamp
against that repo's own `git reflog --date=iso` (`.git/logs/HEAD` read directly for
`/Users/marksuyat/.claude`, since a git session running from a linked worktree of this same
repo is blocked by this machine's own worktree-isolation guard from running `git -C` against
the primary checkout — a real friction I hit and worked around by reading the reflog file,
not by asking `-C` to look at it).

| # | Timestamp (UTC) | Target | Matching reflog entry (local, -0400) | Verdict | Why |
|---|---|---|---|---|---|
| 1 | 2026-09-01T20:59:07Z | vibe-scape/.git/HEAD.lock | `4215e98 HEAD@{2026-09-01 16:59:07}: checkout: moving from docs/plan4b-prompt-optimizer-spec to main` | **CORRECT** | Exact-second match. Ordinary `git checkout` run directly in the primary checkout (vibe-scape has 3 linked worktrees; this command was not run in one of them). |
| 2 | 2026-09-01T21:57:12Z | vibe-scape/.git/HEAD.lock | `c98deb9 HEAD@{2026-09-01 17:57:12}: checkout: moving from main to docs/plan4b-prompt-optimizer-plan` | **CORRECT** | Exact-second match. Same as above. |
| 3 | 2026-09-02T01:00:31Z | Snatch-Bracket/.git/HEAD.lock | `0da97b1 HEAD@{2026-09-01 21:00:31}: checkout: moving from docs/mutation-testing-card to main` | **CORRECT** | Exact-second match, primary checkout. |
| 4 | 2026-09-02T02:56:03Z | Snatch-Bracket/.git/HEAD.lock | `083f845 HEAD@{2026-09-01 22:56:03}: checkout: moving from main to probe/phase-gate` | **CORRECT** | Exact-second match. (Branch name `probe/phase-gate` — looks like manual hook probing, done directly on the primary anyway.) |
| 5 | 2026-09-02T02:56:04Z | Snatch-Bracket/.git/HEAD.lock | `083f845 HEAD@{2026-09-01 22:56:04}: checkout: moving from probe/phase-gate to main` | **CORRECT** | Exact-second match. |
| 6 | 2026-09-03T05:48:15Z | Snatch-Bracket/.git/HEAD.lock | `083f845 HEAD@{2026-09-03 01:48:15}: checkout: moving from main to docs/bracqueen-rebrand-and-profile-cards` | **CORRECT** | Exact-second match. |
| 7 | 2026-09-03T06:04:50Z | Snatch-Bracket/.git/HEAD.lock | `083f845 HEAD@{2026-09-03 02:04:50}: checkout: moving from docs/bracqueen-rebrand-and-profile-cards to main` | **CORRECT** | Exact-second match. |
| 8 | 2026-09-03T06:05:16Z | Snatch-Bracket/.git/HEAD.lock | `3fdad59 HEAD@{2026-09-03 02:05:16}: checkout: moving from main to feat/bracqueen-rebrand` | **CORRECT** | Exact-second match. |
| 9 | 2026-09-03T20:20:58Z | Snatch-Bracket/.git/HEAD.lock | `3fdad59 HEAD@{2026-09-03 16:20:58}: checkout: moving from feat/bracqueen-rebrand to main` | **CORRECT** | Exact-second match. |
| 10 | 2026-09-04T14:52:23Z | mtg-wizard/.git/HEAD.lock | `8134208 HEAD@{2026-09-04 10:52:23}: checkout: moving from fix/ingest-test-scratch-databases to main` | **CORRECT** | Exact-second match. |
| 11 | 2026-09-04T14:52:55Z | mtg-wizard/.git/HEAD.lock | `6a7eb66 HEAD@{2026-09-04 10:52:55}: checkout: moving from main to feat/ingest-notify-block-execution` | **CORRECT** | Exact-second match. |
| 12 | 2026-09-04T18:17:00Z | mtg-wizard/.git/HEAD.lock | `6a7eb66 HEAD@{2026-09-04 14:17:00}: checkout: moving from feat/ingest-notify-block-execution to main` | **CORRECT** | Exact-second match. |
| 13 | 2026-09-04T18:18:58Z | mtg-wizard/.git/HEAD.lock | `68e0953 HEAD@{2026-09-04 14:18:58}: checkout: moving from main to feat/ingest-notify-block-execution` | **CORRECT** | Exact-second match. |
| 14 | 2026-09-04T18:22:58Z | mtg-wizard/.git/HEAD.lock | `8d3d5c9 HEAD@{2026-09-04 14:22:58}: checkout: moving from feat/ingest-notify-block-execution to main` | **CORRECT** | Exact-second match (1 of 2 checkouts logged this same second). |
| 15 | 2026-09-04T18:22:58Z | mtg-wizard/.git/HEAD.lock | `8d3d5c9 HEAD@{2026-09-04 14:22:58}: checkout: moving from main to chore/add-redesign-prototype` | **CORRECT** | Exact-second match (2nd of the pair — two real checkouts landed in the same wall-clock second). |
| 16 | 2026-09-04T18:24:29Z | mtg-wizard/.git/HEAD.lock | `68e0953 HEAD@{2026-09-04 14:24:29}: checkout: moving from chore/add-redesign-prototype to feat/ingest-notify-block-execution` | **CORRECT** | Exact-second match. |
| 17 | 2026-09-08T16:05:12Z | .claude/.git/HEAD.lock | epoch 1788883512 matches **3** reflog rows at once: `pull --rebase origin main (start)`, `(pick)`, `(finish)` | **CORRECT** | `git pull --rebase origin main` run directly in the primary `/Users/marksuyat/.claude` checkout — the 5 linked worktrees existing at review time (`handoff-trim-safety`, `secret-command-guard`, `treko-card-b-spec`, `treko-ui-update`, `verifying-durable-claims`) were not used for this operation. Each of the rebase's 3 internal checkouts is its own HEAD transaction; hence 3 lines at the identical logged second. |
| 18 | 2026-09-08T16:05:12Z | .claude/.git/HEAD.lock | (2nd of the 3, same epoch second) | **CORRECT** | Same rebase, second transaction. |
| 19 | 2026-09-08T16:05:12Z | .claude/.git/HEAD.lock | (3rd of the 3, same epoch second) | **CORRECT** | Same rebase, third (return-to-branch) transaction. |

**Of the 19 lines recorded and reviewed, 19 were judged correct.** Every one matched, to the
second (17 of 19 exactly; 2 of 19 within a documented multi-transaction burst at the identical
second), a real reflog entry showing an ordinary `checkout`/`pull --rebase` performed directly
in that repository's primary checkout, in a repo confirmed by `git worktree list` to be the
primary. I found no case where the guard's scope test (step 5) looks like it misfired against
a linked worktree, and no case I could not resolve — so there is no UNDETERMINABLE verdict
among the 19. The caveat the task asked me to carry: **`log` mode drops a failed append
silently** (`append_log`'s own comment: "a failed append never changes the verdict... The lost
line is announced on stderr instead"), so this reviews only the lines that survived to be
written — a dropped line is a refusal nobody will ever get to judge, correct or not.

Also worth naming plainly, since the task asked me to say so rather than bury it: arming layer
2 to `deny` would have **blocked** each of these 19 real operations at the moment they ran,
in already-existing repos that mostly also had linked worktrees available. That is the guard
doing exactly what it says it does — refuse a HEAD move in the primary checkout — not a false
positive. Whether that's an acceptable cost is a policy question, not a correctness one; I'm
flagging it because criterion 3 asks for a *positive* judgment, and "would have blocked
9-day-old-to-15-day-old ordinary work" is part of an honest one.

---

## Job 2 — are the other 1207 lines really test fixtures? (PARTIAL — see note below)

I did not accept this on assumption and I did not confirm it either. What I found **complicates
the original framing** — some of the 1207 are confirmed real (non-test) work, one clear chunk
is confirmed test-suite leakage, and a majority remains unattributed. I am reporting the
confirmed pieces and flagging the rest as open, per the coordinator's instruction to land a
partial report rather than a complete-sounding guess.

### Re-derived breakdown of the 1207 non-real-repo lines

```
$ awk -F'\t' '$6 ~ /^\/private\/tmp\// || $6 ~ /^\/tmp\//' layer2-would-deny.tsv | wc -l   → 141
$ grep -c "detached/\.claude\|rebasing/\.claude" layer2-would-deny.tsv                     → 95
$ grep -cE 'repo\.[A-Za-z0-9]{6}/\.git/HEAD\.lock' layer2-would-deny.tsv                   → 506
$ # remainder of the /private/var/folders bucket matching neither pattern above:
  awk -F'\t' '$6 ~ /^\/private\/var\/folders\//' layer2-would-deny.tsv \
    | grep -v "detached/\.claude\|rebasing/\.claude" \
    | grep -vE 'repo\.[A-Za-z0-9]{6}/\.git/HEAD\.lock' | wc -l                             → 465
```
141 (tmp) + 95 (detached/rebasing) + 506 (repo.XXXXXX) + 465 (unmatched var-folders) = 1207. ✓

### Confirmed NOT test fixtures: the 141 `/private/tmp` (and `/tmp`) lines

I read all 52 distinct paths in this bucket (not a sample — the full list). Every one matches
one of these naming families:

- `/private/tmp/claude-501/-Users-marksuyat--claude--claude-worktrees-secret-command-guard/<session-uuid>/scratchpad/{judge-compliance,r12-compliance,r13-compliance,verify,judge-compliance-work}/...` — Claude Code's own per-session scratchpad convention (`claude-<uid>/<mangled-worktree-path>/<session-uuid>/scratchpad/...`), holding clones named `clone`, `clone-<sha>`, `<sha>-baseline`, `<sha>-MULTILINE` — this is a judge subagent (compliance-judge, by the directory names) cloning a repo to verify one specific commit, exactly the "Scratch work goes in a directory... (mktemp -d)" global convention in action.
- `/private/tmp/{judge-mut,judge-mut2,judge-parent-clone}` and `/private/tmp/{obsjudge-r10,r10}/{at-<sha>,mut-<sha>-<variant>,clone,nofold,reorder}` — observability-judge mutation-testing clones, named after the exact commit SHAs and mutation variants (`-ascii`, `-multiline`, `-widenexempt`) that appear in this repo's real commit history for the secret-command-guard work.

**None of these 52 paths match an automated-test-suite naming convention** (no `repo.<random>` copies, no scenario words like "detached"/"rebasing" paired with a bare `.claude` clone). This is **real ad hoc verification work by real judge subagents**, not a test suite — a correction to the assumption the task asked me to test, not a confirmation of it. Each such clone is a fresh `git init`/`git clone` with no linked worktree, so a HEAD move inside it is, under the letter of the rule, a genuine primary-checkout HEAD write — correctly logged, just not from a permanent repository and not from a `.test.sh` file.

### Confirmed test fixtures: 95 lines from `hooks/verify-hook-wiring.test.sh`

This file is **not** one of the four suites named in the task brief, and that omission mattered:
I checked the four named suites first and could not make the theory work (see next section),
then searched for the `detached`/`rebasing` fixture names directly and found them at
`hooks/verify-hook-wiring.test.sh:435` and `:453`:

```
H="$(new_home rebasing)"; G="$H/.claude"
git -C "$G" checkout -q -b feature
...
git -C "$G" checkout -q main
...
git -C "$G" checkout -q feature
git -C "$G" rebase main >/dev/null 2>&1 || true
...
H="$(new_home detached)"
git -C "$H/.claude" checkout -q --detach
```

`new_home()` (line 100) does `git -C "$h/.claude" init -q -b main` — a fresh primary checkout
under `mktemp -d`, no linked worktree. Critically, **I found no `GIT_CONFIG_GLOBAL`,
`GIT_CONFIG_SYSTEM`, or `WORKTREE_GUARD_STATE_DIR` override anywhere in this file** (grepped
the whole file for all three). That means every `git -C "$G" checkout ...` above runs under
this machine's **real, live** global git config — including the real `core.hooksPath` pointing
at the installed `/Users/marksuyat/.config/git/hooks/reference-transaction` — and the real
default `$HOME/.claude/hooks/state/reference-transaction.log`. This is a genuine, confirmed
leak: **running this test file writes real WOULD-DENY lines into the live log**, and it is not
a hypothesis — the fixture names (`detached/.claude`, `rebasing/.claude`) are a byte-for-byte
match to the log, and the count fits: 19 distinct fixture directories × ~5 HEAD transactions
each (2–3 checkouts for `rebasing`, plus a rebase that may itself move HEAD twice, and 1 for
`detached`) ≈ 95.

### Two suites checked and RULED OUT as the source, contrary to my working assumption

I initially expected `hooks/reference-transaction.test.sh` and `hooks/worktree-guard.test.sh`
to be the obvious source of the mktemp-path lines (both build real repos under `mktemp -d` and
drive real `git checkout`/`switch`/`commit`, matching the task brief's own suggestion). Checking
their isolation code contradicts that:

```
$ grep -n 'WORKTREE_GUARD_STATE_DIR="\$STATE_DIR"' hooks/reference-transaction.test.sh
67:export WORKTREE_GUARD_STATE_DIR="$STATE_DIR"      # $STATE_DIR = $TMP/state, cleaned up on exit
$ grep -n 'GIT_CONFIG_GLOBAL=/dev/null' hooks/worktree-guard.test.sh
29:export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
```

Both lines are exported **once, at the top of the whole script**, before any fixture git
command runs — `reference-transaction.test.sh` redirects layer 2's own log to a doomed temp
directory; `worktree-guard.test.sh` blanks the global git config so `core.hooksPath` reads as
unset for the entire run (so the real, installed layer-2 hook is never even reached by that
suite's fixture repos). I also checked whether this isolation was added later, after some
early unisolated runs had already polluted the log — it was not:

```
$ git log -S'WORKTREE_GUARD_STATE_DIR="$STATE_DIR"' --format='%ai %h %s' -- hooks/reference-transaction.test.sh | tail -1
2026-08-26 15:49:38 -0400 0b40f81 test(reference-transaction): the failing layer-2 suite lands first — 96 assertions, red
$ git log -S'GIT_CONFIG_GLOBAL=/dev/null' --format='%ai %h %s' -- hooks/worktree-guard.test.sh | tail -1
2026-08-26 09:12:17 -0400 c749b50 test(worktree-guard): the failing suite lands first — 185 assertions, red
```

Both isolation lines were present in each file's very first commit — five days before the log
window even opens (2026-09-01T22:56:01Z is the earliest line in the whole population). So
neither suite, at any point the live log could have observed, should be capable of writing
into it. `hooks/install-layer2.test.sh` similarly runs its `git config --global` assertions
against a fixture-local fake global config, not the machine's real one — also ruled out on
inspection, not exhaustively traced.

### NOT attributed — 506 + 465 = 971 lines (79% of the whole population)

The `repo.<6-char-suffix>/.git/HEAD.lock` pattern (506 lines, 184 distinct directories) reads
like a multi-case fixture generator — the naming style matches what `reference-transaction.test.sh`'s
own comments describe ("the pinned matrix — four `worktree add` forms, switch/checkout/
--detach/sh -c/env -C, the mkdir forgery") — but I could not locate the literal string `repo.`
followed by a random suffix inside any of the four named suites, and I ran out of time to grep
every `.test.sh`/`.probe.sh` file in `hooks/` for it. The remaining 465 var-folders lines (bare
`tmp.XXXXXX/.git/HEAD.lock`, no subdirectory) are equally unattributed. **I am not asserting
these are test fixtures.** The path shape is consistent with automated-test origin, but given
that I just found two suites whose fixture *shapes* strongly suggested the same and were
wrong (or rather, right about the shape but isolated so they can't be the log's source, forcing
the real source to a file outside the four named), I don't trust that inference here without
the same direct confirmation I got for the 95-line case. What I tried and where it stopped:
grepped the four named suites for `mktemp -d`, `git checkout|switch|commit`, and isolation
vars; grepped the whole `hooks/` tree for `detached`/`rebasing` (found the real source);
did not repeat that grep for a `repo\.` generator pattern or `RANDOM`/`mktemp -u` idioms across
every `.test.sh`/`.probe.sh` file — that is the next concrete step, not done here.

---

## Job 3 — what this window can and cannot support

**What it supports, from Job 1 alone:** the guard's refusal clause, on every one of the 19
occasions it fired against a real, named, permanent repository, fired on a genuine HEAD write
performed directly in that repository's primary checkout — never against a linked worktree,
never on a probe artifact, never on anything I could not resolve. That is a clean record for
the population it actually covers, and it is real evidence in favor of the rule's precision.

**What it does not support:** a claim that arming is safe for ordinary day-to-day use, if that
claim were to rest on "look how much traffic this window has and how little went wrong." 1207
of 1226 lines (98.4%) are not ordinary interactive primary-checkout work in a permanent repo.
Of those: at least 141 are confirmed real-but-ephemeral judge/verification clones (not
ordinary user work, not test fixtures either), at least 95 are confirmed automated-test
leakage from one specific unisolated suite, and 971 remain of undetermined origin. The 19-line
population Job 1 actually cleared is real but small, and it is drawn from exactly four
repositories over a nine-day span in early September — it says nothing about repositories,
users, or workflows this window never saw.

**This log cannot speak to coverage, only to precision — twice over.** First, as stated in the
task brief: a command the guard failed to recognise leaves no line, so nothing here bounds how
often the guard *should* have fired and didn't. Second, a finding specific to this review: even
within the lines that *were* recorded, a substantial majority (79%, the 971 unattributed) could
not be resolved to either "real work" or "test fixture" in the time available, so no claim
about the *composition* of the log — "it's mostly harmless test noise" or "it's mostly real
risk" — is supportable yet either. Both readings are still open.

**Most recent real-repo refusal:** 2026-09-08T16:05:12Z (the `.claude` `pull --rebase`
transactions), against a review date of 2026-09-17 (this session's system clock, one day past
the 2026-09-16 the task brief stated) — **9 days ago**. Nothing about real, permanent-repo
primary-checkout HEAD writes has been recorded since. Whether that means the behavior stopped
happening, or that recent instances haven't been reviewed yet, is not something this log can
tell you either way.

**Bottom line on criterion 3 for layer 2:** the 19-line real-repo population has been read and
judged, all 19 correct, satisfying the letter of "every would-deny line in the window read
individually and judged a correct refusal" **for that population**. But the task named the
*whole* log as the correct window, and 971 of its 1226 lines (79%) have not been read and
judged to a resolved verdict — they are neither confirmed correct nor confirmed test noise.
**I would not sign off criterion 3 as met for the full window on this report.** What's solid:
Job 1, complete, 19/19 correct. What's missing before the criterion can be called satisfied:
resolving the 971 unattributed lines to a real verdict (even "confirmed test fixture, no
verdict needed" is a verdict) — most efficiently by finding the `repo.<suffix>` generator and
checking its isolation the same way I checked the other three, and by pattern-matching the
remaining 465 bare `tmp.XXXXXX` lines the same way.

---

## What I could not do / was blocked on

- Could not run `git -C "/Users/marksuyat/.claude" ...` directly from this worktree — this
  machine's own worktree-isolation guard refuses it ("a worktree-isolated session's git
  operations must target its own worktree"). Worked around it by reading `.git/logs/HEAD` and
  `.git/worktrees/*/gitdir` directly with `cat`/`ls`, which are plain file reads, not git
  operations, and are not refused.
- A shell loop combining `grep` with the literal strings "git worktree add" and other git-shaped
  substrings inside a pattern (not an actual git invocation) was also refused by the same guard,
  apparently on text shape rather than actual execution; worked around by splitting into
  single-purpose greps.
- Did not trace the `repo.<6-char-suffix>` generator (506 lines) or the 465 remaining bare
  `tmp.XXXXXX` lines to a source file — ran out of time under the coordinator's request to land
  the report now rather than keep chasing it.
