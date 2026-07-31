# Observability judge — RUN 4 (implementation)

- **repo:** `jg-failclosed` (worktree `~/.claude/.claude/worktrees/jg-failclosed`)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha:** `822f60f4da3377c4c2a49f9bc0650efa8bdcd4cb`
- **base:** `origin/main` (`2b8564b`) · **delta judged:** `1d3b4ed..822f60f` (documentation only)
- **ts:** 2026-07-31T17:20:40Z · **stage:** implementation

## What was changed

Nothing that runs. This commit adds **one bullet to ADR 0012** plus the RUN 3 verdict artifacts.

I verified the "no code changed" claim rather than accepting it: `git diff 1d3b4ed..HEAD -- hooks/`
is empty, so the hook, both test files and the classifier are byte-identical to the previously
judged HEAD. The delta is 3 files, +180/-1: the ADR (+7/-1), the RUN 3 markdown, one JSONL line.

The bullet restores a failure mode that had gone missing from a list. ADR 0012 said "**Two** failure
modes are knowingly deferred"; the real count was three. A classifier stub that always answers `NO`
and exits cleanly had been dropped from the list while its two siblings were fixed. The commit puts
it back and explains why it can't be caught at the call site — you'd need a canary (feed the
classifier a string you *know* is a PR command and refuse to run if it says otherwise).

## Does it do what was intended?

Yes, and the restored description is accurate — I reproduced the shape rather than trusting the
prose. Built a stub classifier that prints `NO` and exits 0, pointed a copy of the hook at it, fed
it a real `gh pr create --fill` payload:

```
stub (always NO, exit 0)  -> exit=0, no output   # gate silently disarmed
intact classifier          -> exit=2, names the missing verdict for 822f60f
```

So the mode is real, silent, and correctly described. Both suites are green at this HEAD, run by me:
`judge-guard.test.sh` **64 passed / 0 failed**, `classify-pr-command.test.py` **51 passed / 0
failed**. `shellcheck -x` reports only the pre-existing SC2181 at line **158** (RUN 3's corrected
line number is right). Working tree clean.

## What could go wrong / what I'm unsure about

**The enumeration is complete for the classifier — but the hook's headline promise is not.**

I went looking for a fourth mode as instructed. I found one, and it is not a classifier mode, which
is why the list can be defended as complete while the *document* still overclaims.

`hooks/judge-guard.sh` lines 41–53 hold a second, separate inline Python program: the JSON payload
parser. If it fails, `command_line` is empty and line 53 does `exit 0`. I isolated each of the two
inline parsers by breaking exactly one at a time:

| broken component | result |
|---|---|
| payload parser (line 42, single-quoted inline) | **exit 0, silent — every `gh pr create` passes** |
| verdict matcher (line 136, heredoc `<<'PYEOF'`) | exit 2, loud traceback — fails closed |

The fail-open one is *the same block ADR 0012 already flags* as still carrying the apostrophe trap —
the trap the ADR says fired **three times** on this branch, twice inside the comment warning against
it. The ADR discusses that block purely as an ergonomics scope caveat ("short, stable, never the
thing under edit"). It never says the safety consequence: when it breaks, the gate fails **open**,
which is the exact defect the entire branch exists to remove. Line 53 is the pre-fix classifier
pattern verbatim — trust that a component ran, infer from emptiness.

Meanwhile the hook's own header (lines 10–12) states: *"it fails CLOSED: any inability to verify
blocks."* I measured an inability to verify that does not block. That is the overclaim the brief
asked about, and it sits in the header rather than the deferred list.

Steelman, stated fairly: the three-item list is nested under the bullet "An UNUSABLE **classifier**
fails CLOSED," so scoped to the classifier it is complete and accurate. I'm not calling the new
bullet wrong. The gap is that the file-level "fails closed" promise has a measured exception
documented nowhere on the branch — `grep` for "fail open" in ADR 0012 returns only the unrelated
newline-splitting discussion.

**Zero test coverage.** `grep -c command_line` across both suites returns **0/0**. The one fail-open
path in the file is unpinned, so 64 green tests say nothing about it. That is mild success-masking:
the suite's green is real but narrower than the ADR's claim.

Not fixable by a one-line flip — `exit 0` there is partly *correct*, since PreToolUse fires on
payloads with no command at all and blocking those would freeze everything. Distinguishing "no
command in this payload" from "my parser is broken" needs the same status-plus-shape trick already
applied to the classifier. That's a real design task, which is precisely what makes it a *deferred*
item rather than an absent one.

**Standing item, unchanged by this delta:** `CODING_MEMORY.md` is 1356 lines against the 200-line
cap on its own line 3; this delta adds 0 lines to it. Eighth consecutive flag, deferral is ruled and
recorded — noted for continuity, not re-litigated.

## The verdict-store route (asked directly, so answered directly)

Appending the genuine verdict line to `$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl`
does **not** misrepresent anything. The verdict is real, produced here, and the keys are ones the
installed hook actually computes (`repo=jg-failclosed`, same branch, same SHA). Nothing is
fabricated and it beats a `JUDGE_EXEMPT` on the branch whose subject is not bypassing this gate.

One honest wrinkle worth recording: it plants a `jg-failclosed` entry inside `~/.claude`'s *own*
repo-local store. That is the same artifact class ADR 0012 calls out as a symptom of the bug being
fixed — the stray `Snatch-Bracket` entry it describes as "unreachable, already stale." After merge
this new line becomes stale in exactly that way. Not an objection to the route; a request that it
be one sentence in the ADR's existing bootstrap bullet ("a hook fix cannot be gated by the hook it
fixes until the primary checkout pulls it"), so a future reader meets it as explained rather than as
mystery noise.

I wrote my verdict to the **repo-local** store, which is both my mandate and where the fixed hook
looks. The `$HOME` append is the user's step, after this verdict.

## Dimensions

| dimension | score | note |
|---|---|---|
| intent | pass | restored bullet is accurate; stub shape reproduced, not trusted |
| execution | pass | 64/0 and 51/0 verified by me; hooks byte-identical to `1d3b4ed` |
| trajectory | pass | self-correcting by design; reasoning for deferral is sound |
| regression | pass | no executable change, tree clean, shellcheck unchanged |
| context_budget | concern | `CODING_MEMORY.md` 1356 vs its own 200 cap; +0 in this delta |
| traceability | concern | "any inability to verify blocks" has a measured, undocumented exception |
| success_masking | concern | 64 green tests; 0 touch the payload parser's fail-open path |
| intent_drift | pass | doc-only, one bullet + verdict artifacts, exactly scoped |
| checkpoint | pass | atomic doc commit, trivially revertible |
| audit_trail | pass | a commit whose purpose is correcting its own record |

**risk: medium · confidence: high**

## Concerns

1. Unenumerated fail-open: broken inline payload parser (`judge-guard.sh:41–53`) → `exit 0`, silent,
   every `gh pr create` passes. Isolated by breaking one parser at a time; the heredoc verdict
   matcher at :136 correctly fails closed. Same block the ADR flags as retaining the apostrophe trap
   that fired 3× on this branch, discussed only as ergonomics, never as a safety consequence.
2. Hook header claims "any inability to verify blocks" — measured exception above; no "fail open"
   mention in ADR 0012 outside the unrelated newline-splitting passage.
3. Zero test coverage of `command_line` (`grep -c` = 0 in both suites); the fail-open path is unpinned.
4. `CODING_MEMORY.md` 1356 lines vs 200-line self-declared cap; unchanged by this delta.
5. Cosmetic: the `$HOME`-store append will leave a cross-repo entry that goes stale post-merge,
   matching the `Snatch-Bracket` artifact the ADR itself describes as a symptom of the fixed bug.
