# Observability judge — RUN 8 (implementation)

- **repo:** `jg-failclosed` (worktree of `~/.claude`; `basename $(git rev-parse --show-toplevel)`)
- **branch:** `fix/judge-guard-fail-closed-classifier`
- **head_sha:** `4495bf88e3458bb3a5f00aadc78ba21ae6dc7d75`
- **base:** `origin/main` (`2b8564b`), 43 commits ahead, 0 behind
- **stage:** implementation (this verdict gates the PR)
- **judged:** 2026-08-01T04:40:02Z
- **design record:** `docs/decisions/0012-judge-guard-repo-local-verdicts-and-chained-detection.md`

Evidence I gathered myself (nothing below is taken on report):

- `bash hooks/judge-guard.test.sh` → **101 passed, 0 failed** (run by me, this HEAD).
- `shellcheck -x hooks/judge-guard.sh` (0.11.0) → **1 SC2181**, and the merge-base version emits
  **the same one code**. No new lint findings. (The summary's "3 SC2016 + 2 SC2181" is a different
  shellcheck build's count; the point that matters — codes identical before and after — holds.)
- **Mutation M1 reproduced exactly.** Rerouting the "no runnable command" door to the parse-error
  message, exit code untouched: pre-C1 suite **101/0 (survived completely)**, this suite **92/9**.
- **Mutation M2 reproduced exactly.** Emptying the classifier: pre-C1 suite **66/35**, this
  suite **33/68**.
- **Byte scan of every tracked file** for control bytes: exactly one remains, the ESC at
  `2026-07-19-feature-statusline-command-round3.md:22`, and `git diff origin/main..HEAD` on that
  path is empty — pre-existing, another feature's file, correctly left alone. No file in the
  branch diff is binary to git any more.
- **Behaviour battery** against HEAD and against `origin/main`'s hook: emoji, raw ESC in text,
  CRLF, RTL override, a 200 KB heredoc, JSON-quoted args — all still pass; the two shapes that
  block (lone CR, lone private-use/ZWJ character) are the intended fail-closed door.
- Commit hygiene: no commit changes `judge-guard.sh` and `judge-guard.test.sh` in the same step
  except `832affd`, which I diffed line by line — comments only in both code files.

---

## What was changed

Think of `judge-guard.sh` as a doorman who checks that the observability judge has signed off
before you open a pull request. Previous rounds discovered the doorman had several ways of
*silently waving everyone through* when something in his own kit was broken. This branch replaces
every one of those silent waves with a loud refusal, and this round in particular does three
things:

1. **The doorman's "is this even a command?" test got fixed.** It used to only ignore spaces, so a
   command made purely of invisible control characters (a NUL byte, say) looked like a real
   command, matched nothing, and was let through. Now "real" means *at least one character that is
   neither whitespace nor a control character*, which still counts em-dashes, Chinese text and
   tab-separated commands as real.
2. **The tests now check which door slammed, not just that a door slammed.** Five different faults
   all exit with the same code `2`. Asserting the code alone proves only that *something* refused;
   asserting the message proves the guard actually read the command and judged it.
3. **Three documentation/encoding cleanups**: two hook comments that made claims the code does not
   support were corrected, and raw control bytes accidentally typed into earlier verdict files were
   escaped so those files render as text in the PR diff instead of as binary blobs.

## Does it do what you wanted?

Yes. Every claim in the decisions summary that could be checked, I checked, and all of them held —
including both mutation results, which reproduced to the exact pass/fail counts. That is unusually
strong evidence: it shows the new assertions catch a defect the old suite slept through, rather
than merely being more verbose.

The fail-closed design is coherent with its stated purpose (a momentum guardrail, not a security
boundary), the deliberately-open shapes are enumerated in ADR 0012 with measurements attached, and
the "no bypass env var on the fail-closed path" decision is argued rather than assumed.

## What could go wrong / what I'm unsure about

**1. The guard now costs about three times as much on *every* Bash command (new, measured, and not
in the ADR).** Timed twice in both orders on this machine, 20 invocations each:

| hook | per Bash call |
|---|---|
| `origin/main` | ~51–56 ms |
| this HEAD | ~141–145 ms |

Two causes, both isolated: the `-I` probe is a whole extra Python process spawned on every single
call (~28 ms of it), and `-I` itself roughly doubles interpreter startup here (classifier alone:
21 ms without `-I`, 45 ms with). It is correctness bought with latency — a session that issues 300
Bash calls now pays roughly 30 extra seconds. Nothing breaks; it is simply a real global cost that
nobody has written down, and the probe's answer is machine-static, so it is cacheable if it ever
becomes annoying.

**2. First arming is the risky moment, not the merge.** `~/.claude/hooks/` currently holds the
*old* hook and has **no `lib/` directory at all**. The new hook cannot work without
`hooks/lib/classify-pr-command.py`, and by design it blocks *every Bash command on the machine*
when that file is unusable. Normally `git pull` writes both files together and this is a non-event;
an interrupted or partial checkout is the case that hurts, and while a Bash call is blocked you
cannot use `git` to fix it. ADR 0012 names this and names the two recovery routes that survive the
block (repair with the Write tool, or unregister the hook in `settings.json`). Documented, but it
is the single highest-consequence moment in this change.

**3. This PR cannot pass through its own gate.** The installed hook still reads
`$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl`, while this verdict lands in the
worktree's store. So `gh pr create` from this worktree will report "no fresh verdict" even though a
fresh one exists, and will need the logged `JUDGE_EXEMPT=<reason>` escape hatch, exactly as PR #32
did. Already stated in ADR 0012 as "a hook fix cannot be gated by the hook it fixes"; repeated here
only so it is not mistaken for a defect in this diff at the moment it happens.

**4. Low-likelihood, and I could not test it: a machine with no `python3` but a Python 2 `python`.**
The `-I` probe correctly drops the flag on a pre-3.4 interpreter, but the parser then fails anyway,
because Python 2's `json` returns `unicode` and `isinstance(tn, str)` is False — so exit 3, block
everything. That is consistent with the fail-closed doctrine (and the old hook merely failed *open*
in the same situation), but the fallback's comment implies a graceful degradation it does not
actually deliver for Python 2. No Python 2 on this machine, so this is reasoning, not measurement.

**Not raised as findings** (checked and dismissed): the `isprintable()` predicate cannot
false-block a real command, since a single ordinary character makes the whole string runnable; the
four message constants are mutually non-substring, so no assertion can pass off the wrong door; the
`run_payload_msg` helper requires exit code *and* message, and `set -u` protects against an unset
pattern degenerating into `grep ''`. A bare `gh pr create` on its own line inside a heredoc body
still classifies as PR — I verified it behaves identically on `origin/main`, so it is pre-existing,
not introduced here (worth an ADR line someday, not a blocker).

## What I'd double-check before merging

1. **Immediately after the primary checkout pulls this**, prove the guard is armed and not wedged:
   `printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' | bash ~/.claude/hooks/judge-guard.sh; echo $?`
   → must be `0`, and `ls ~/.claude/hooks/lib/classify-pr-command.py` must exist. If it exits 2,
   every Bash call in every session is blocked and the only ways out are the Write tool or
   unregistering the hook.
2. Expect to open this PR with `JUDGE_EXEMPT=<reason>`, and say in the reason that it is the
   bootstrap case (concern 3), not a skipped judgement.
3. Decide whether the ~90 ms per-Bash-call latency is worth one line in ADR 0012 — the next person
   to notice it should find it written down rather than rediscover it with a stopwatch.

---

## Dimensions

| dimension | verdict | why |
|---|---|---|
| intent | pass | Every stated goal is present in the diff and independently verified: fail-closed classifier path with no bypass, control-character predicate, message-asserting tests, two corrected comments, escaped doc bytes. |
| execution | pass | 101/0 run by me at this HEAD; shellcheck codes identical to base; both mutations reproduced to the exact counts; behaviour battery shows no legitimate command newly blocked. |
| trajectory | pass | Reasoning, not luck: the affected surface was measured (48 assertions, not the assumed 5), each comment claim was re-measured before editing, and the third instance of the control-byte class triggered an enumeration instead of a fourth patch. |
| regression | concern | No functional regression found, but a measured ~2.8x latency increase on every Bash call (51 ms to 145 ms) is introduced and undocumented; plus the un-armed installed hook makes first arming the highest-consequence moment. |
| context_budget | pass | No rule, skill or prompt file changed; always-on context is untouched. `CODING_MEMORY.md` grew 333 lines to ~148 KB, but the memory skill loads it on demand only. Worth watching, not blocking. |
| traceability | pass | ADR 0012 carries the full decision record including deferred failure modes, blast radius and every accepted-open shape with its measurement date; hook comments explain the why and retract their own earlier false claims. |
| success_masking | pass | This round exists to remove masking, and the two mutations prove it works. Residual masking vectors (a classifier that always answers `NO`; a classifier that hangs, no timeout) are enumerated in ADR 0012 as deliberately deferred. |
| intent_drift | pass | Scope held to the hook, its tests, the ADR and this branch's own verdict files. No new dependencies (the classifier unit suite is deliberately stdlib-only). The one pre-existing control byte in another feature's file was verified unchanged against `origin/main` and left alone. |
| checkpoint | pass | 43 small, single-purpose commits with red/green test-then-fix pairs; test and implementation never edited in the same step (the one mixed commit is comments-only, verified line by line). Every step is a clean revert point. |
| audit_trail | pass | Attributable and ADR-worthy: per-round verdicts, an ADR that records its own corrections as corrections, and a memory checkpoint per landed item. |

**risk:** low  **confidence:** high

### Concerns (short form)

- Hook latency ~2.8x on every Bash call (51 ms -> 145 ms measured): the `-I` probe respawns python per call and `-I` roughly doubles interpreter startup here. Undocumented in ADR 0012.
- First arming: installed `~/.claude/hooks/` has no `lib/`, so the guard is only correct once the primary checkout pulls both files; a partial checkout blocks all Bash machine-wide.
- This PR cannot satisfy its own gate: the installed hook still reads `$HOME/.claude`'s verdict store, so `gh pr create` from this worktree needs `JUDGE_EXEMPT` (as ADR 0012 predicts).
- Python-2-only machines (no `python3`) now block every Bash call: the pre-3.4 `-I` fallback does not save the parser, since py2 `json` returns `unicode` and fails the `isinstance(..., str)` check. Untested — no Python 2 available.
