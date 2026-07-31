# Observability judge — RUN 5 (implementation)

- **repo / branch:** `jg-failclosed` / `fix/judge-guard-fail-closed-classifier`
- **HEAD judged:** `e4a6c10638d8e5897e653d23dbac2fca70b3e95b`
- **base:** `main` (merge-base `8f0f16d`); delta judged: `822f60f..e4a6c10`
- **ts:** 2026-07-31T18:57:18Z
- **filename note:** written as `-round5` rather than the bare `<date>-<branch_slug>.md`, which is
  already occupied by RUN 1. Overwriting a prior verdict would destroy the audit trail this branch
  exists to protect; the `-roundN` suffix is the convention RUNs 2–4 already established here.

## What was changed

The hook that stops you opening a pull request before the judge has looked at your code reads a
little JSON message from Claude Code to find out *what command you just typed*. That reader had no
tests at all, and when it choked it went quiet — and quiet meant "nothing to check here, go ahead".
So a garbled message opened the gate as wide as no gate at all.

The awkward part: quiet is also the *correct* answer sometimes. A message with no command in it
isn't a command, and must pass. So the fix doesn't punish silence; it makes the reader **say its own
name before it answers** — it prints `OK` on the first line, then the command on the lines after.
No `OK`, or a non-zero exit, means the reader never got to the end, and the hook now blocks.

It's the difference between a night watchman who says nothing because there's nothing to report and
one who says nothing because he's unconscious. The `OK` is the radio check-in.

Also: the file header used to promise *"any inability to verify blocks."* It was never true — some
command shapes are deliberately not detected. The promise is now scoped to the machinery, with the
exceptions named in ADR 0012.

## Does it do what you wanted?

Yes, and I verified every number rather than taking the summary's word for it.

| claim | my measurement |
|---|---|
| `judge-guard.test.sh` 75/0 | **75 passed, 0 failed** ✔ |
| `classify-pr-command.test.py` 51/0 | **51 passed, 0 failed** ✔ |
| red commit was genuinely red | replayed `77bfbed`: **69 passed, 6 failed** ✔ |
| red = tests only, green = code only | `77bfbed` touches only the test file; `2acad5e` touches only hook + ADR ✔ |
| four fail-open shapes existed and are closed | ran the **pre-fix hook at `822f60f`** against an absent verdict store: real `gh pr create` → **2**, but truncated JSON / non-JSON / `[1,2,3]` / `"a string"` → **0, 0, 0, 0** (gate disarmed). Same five against `e4a6c10` → **2, 2, 2, 2, 2** ✔ |
| shellcheck clean but for pre-existing SC2181 | confirmed, line 201, predates the fork ✔ |
| adjacent suites green | context-handoff 19/0, memsearch 5/5, pane-dispatch 34/0, phase-guard 130/0, adapters 45/0, dispatch-pane-agent 113/0 ✔ |

**On the expansion from three shapes to four (you asked whether you over-reached): you did not.**
The two you added beyond RUN 4's list — wrong top-level shape and a failing interpreter — are real,
I reproduced both fail-open pre-fix, and they are the same class, not new scope. Completing a class
instead of patching its named instance is exactly the lesson this branch keeps writing down.

**Your five questions, answered from measurement:**

1. **Is the sentinel sufficient?** I could not break it. `OK` as the *first line of the command*
   (`OK\ngh pr create`) still blocks — the sentinel is prepended, so nothing shifts. A NUL byte
   before the command still blocks. A `python3` wrapper that prints a banner on stdout before the
   parser runs blocks. Extra top-level keys block or pass correctly. No payload I built printed `OK`
   and then disarmed the gate.
2. **Broken pass-through?** No shape I tried now blocks that should pass — but see the finding
   below: the *reason* given for the pass-through cases is false, and that matters more than the
   behaviour.
3. **A fifth fail-open?** No fifth *machinery* fail-open. Enumeration below.
4. **Is the header accurate?** Materially yes — a real improvement. One carried omission.
5. **`sed` / trailing-newline handling?** Correct. Empty command → pass; whitespace-only → pass;
   newlines-only → pass; multi-line command preserved (`gh pr create` on line 2 blocks); a leading
   blank line inside the command is preserved and still blocks. `$(...)` eats trailing newlines,
   which cannot change a classification.

## What could go wrong / what I'm unsure about

**F1 — the design's stated premise is measurably false (documentation/reasoning, not behaviour).**
`hooks/judge-guard.sh:53`, `hooks/judge-guard.test.sh:300` and ADR 0012:132 all say the same thing:
*"every Edit, Read and Write in the session arrives that way"* / *"reaches this hook"*. It doesn't.
The hook is registered with **matcher `Bash`** — in this worktree's `settings.json` and in the live
`/Users/marksuyat/.claude/settings.json` (both verified). An `Edit`, a `Read` and a `Write` never
reach `judge-guard.sh` at all; `phase-guard.sh` is the hook that sees those. Under exact-match
matcher semantics *no* non-Bash call reaches it; under unanchored-regex semantics only `BashOutput`/
`KillShell` would — and neither is an Edit, Read or Write. I cannot settle which semantics Claude
Code uses from inside this repo, so I state only what I verified: **the three named examples are
wrong.**

This is not pedantry, because the premise *chose the behaviour*. A real `Bash` tool call always
carries a `command` string. So for the actual registration, "valid JSON, no command" does not mean
"an editor call to wave through" — it means "a Bash payload whose command I could not find", which
by this hook's own fail-closed doctrine is a candidate to **block**, not pass. The fix may have
picked the right behaviour for the wrong reason, or the wrong behaviour for a stated reason that
does not hold. I am not asserting the code is wrong — the current schema always supplies `command`,
so the branch is unreachable today. I am asserting the justification cannot be relied on, and that
this is the same class RUN 4 flagged in the header, reappearing inside the fix's own commentary.
Fair provenance: RUN 4's own writeup asserted "PreToolUse fires on command-less payloads"; the
implementer inherited a judge's unverified premise rather than inventing one.

**F2 — success masking, downstream of F1.** Four green tests now *pin* "no command → allow"
(`judge-guard.test.sh:307-310`). If the payload schema ever drifts — `tool_input.command` renamed or
nested — the hook silently allows every `gh pr create`, the suite stays green, and one of the tests
positively asserts that it should. That is a fail-open with a test holding the door. Cheap
mitigation: assert on `tool_name`/`hook_event_name` shape too, so a Bash payload missing its command
is distinguishable from a genuinely command-less call.

**F3 — new machine-wide block trigger, untested.** The parse path now blocks whenever python3's
stdout is contaminated or unusable. I measured two triggers: a `python3` wrapper printing a banner
first (**rc=2**), and `PYTHONIOENCODING=ascii` with a non-ASCII command such as an em-dash in a
commit message (**rc=2**; `LC_ALL=C` and `LC_ALL=POSIX` are fine — PEP 538 coercion saves them).
Pre-fix, both merely prepended noise and let benign commands through. Post-fix, **every Bash command
on the machine blocks** until the environment is fixed. This is the intended fail-closed direction
and the error message does say so — but a conda/pyenv shim that greets you on stdout is a real-world
thing, there is no test for it, and ADR 0012's accepted-exceptions list does not name it.

**F4 — carried, unchanged by this delta.** ADR 0012's enumerated open shapes still omit shapes I
re-measured as open: `sudo gh pr create`, `xargs gh pr create`, and path-qualified invocation
(`/opt/homebrew/bin/gh pr create`, `./gh pr create`) — all classify **NO** (grep for these in ADR
0012: **0 hits**). The ADR does say the denylist is "incomplete by construction" and that the count
of gaps is not closed, so this is an enumeration gap, not a false claim. Third run to raise it.

**F5 — context budget, ninth consecutive flag.** `CODING_MEMORY.md` is **1394 lines** against the
200-line cap its own line 3 declares (+38 this delta). Deferral is ruled and recorded in-file; noted
for continuity, not re-litigated. `judge-guard.sh` is now 214 lines of which **88 are comment** — the
rationale for this one `case` statement is stated in the hook, the test, and the ADR.

**Residual fail-open surface, enumerated (you asked for this over another single finding):**

| # | surface | site | status |
|---|---|---|---|
| 1 | empty payload / stdin is a TTY → exit 0 | `judge-guard.sh:42-43` (verified rc=0) | accepted, now named in the header |
| 2 | valid JSON, no `command` → exit 0 | `judge-guard.sh:96` | **F1/F2** — accepted on a false premise |
| 3 | classifier `shlex` ValueError → `("NO","")` | `classify-pr-command.py:73-79` | deliberate fail-open, documented |
| 4 | always-`NO` classifier stub exiting 0 | — | documented deferred (needs a canary) |
| 5 | classifier that hangs | — | documented deferred (needs a timeout) |
| 6 | quoted `"$(gh pr create)"`, backticks, `eval "…"`, heredocs | classifier by design | documented open shapes |
| 7 | denylist wrappers: `env`, `timeout`, `sudo`, `xargs`, loop keywords, path-qualified `gh` | `classify-pr-command.py:39` | open; **F4** — partly undocumented |
| 8 | `JUDGE_VERDICTS_FILE` env override | `judge-guard.sh:171` | known/tracked since RUN 2; I confirmed it clears the gate when set in the hook's *own* env, and confirmed ADR 0012:258 is right that an inline `VAR=x gh pr create` prefix cannot reach it |
| 9 | a verdict whose content is `risk=high` / `execution=fail` still opens the gate | `judge-guard.sh:192-195` | **verified rc=0.** By design (existence, not outcome) but stated nowhere; the store is also agent-writable |
| 10 | `JUDGE_EXEMPT` | `judge-guard.sh:151` | by design, logged |

Items 1–7 are all disclosed somewhere on the branch. Items 8–9 are the ones a reader would not learn
from the header; 9 in particular reads as a gate on *judgment* and is a gate on *existence*.

## What I'd double-check before merging

1. **Correct the Edit/Read/Write premise in all three places** (`judge-guard.sh:53`,
   `judge-guard.test.sh:300`, ADR 0012:132) to what is actually verifiable: the hook is matched on
   `Bash`, so the no-command branch is defensive rather than load-bearing. Then decide, explicitly,
   whether a Bash payload with no command should pass or block. One sentence either way — but this
   branch's own rule is that a wrong claim left in the record reads as settled.
2. **Decide item 9 and write it down**: the gate proves a verdict *exists*, not that it *passed*.
3. Add one test for a `python3` that prints on stdout (F3), or accept it in ADR 0012's exception list.
4. Add `sudo` / `xargs` / path-qualified `gh` to ADR 0012's open-shape list (F4) — carried since RUN 2.
5. Remember the bootstrap: the installed hook in the primary checkout may still predate this fix, so
   this PR may need the same logged `JUDGE_EXEMPT` route ADR 0012:264 describes.

## Dimensions

| dimension | verdict | note |
|---|---|---|
| intent | pass | closes exactly RUN 4's finding; no scope beyond it |
| execution | pass | 75/0 + 51/0 verified by me; red replay 69/6; four fail-opens measured closed against the pre-fix hook |
| trajectory | pass | measured before fixing; found and avoided the obvious-but-wrong fix; TDD order verified commit-by-commit |
| regression | concern | six adjacent suites green, but the parse path now blocks every Bash command on contaminated python3 stdout / `PYTHONIOENCODING=ascii` (both measured), untested and unnamed in the ADR |
| context_budget | concern | `CODING_MEMORY.md` 1394 lines vs its own 200-line cap (+38); hook now 88 comment lines of 214 |
| traceability | concern | the design's stated premise (Edit/Read/Write reach this hook) is false in three places; matcher is `Bash` in both settings files |
| success_masking | concern | four green tests pin "no command → allow", which would hold a schema-drift fail-open open; always-`NO` stub and hang still uncovered |
| intent_drift | pass | diff confined to the hook, its test, ADR 0012, memory; no deps; pre-existing SC2181 deliberately left |
| checkpoint | pass | clean worktree; red/green/docs split into separate revertible commits |
| audit_trail | pass | ADR updated in place, and it *withdraws* its own earlier "stable" claim — exemplary self-correction |

**risk = medium · confidence = high**
