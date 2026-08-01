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

---

# Observability judge — RUN 9 (implementation, delta review)

- **head_sha:** `0f546221e5c02763197ae92fba6dcf5560d0b4cf`
- **prior:** RUN 8 above, at `4495bf8` (`risk=low confidence=high`) — findings carried forward, not re-litigated
- **delta:** exactly one commit, `0f54622` "docs(hooks): record the ~2.8x per-call cost that isolation buys"
- **judged:** 2026-08-01T05:00:05Z

RUN 8 is appended to rather than overwritten: it is a committed audit record, and this file is the
per-branch ledger. Destroying one verdict to write the next would defeat the point of both.

## Evidence I gathered myself

- **Delta is docs-only — proved three ways, not assumed.** `git diff --stat 4495bf8..HEAD` excluding
  `docs/` and `coding-memory/` is **empty**; and decisively, the blob hashes of both code files are
  **byte-identical** across the delta (`judge-guard.sh` `040e02e`, `judge-guard.test.sh` `0eae93b`).
  No behaviour rode along.
- `bash hooks/judge-guard.test.sh` at this HEAD → **101 passed, 0 failed** (run by me, not carried
  over). Combined with blob-identity, RUN 8's mutation evidence still applies to this exact code.
- **The ADR's numbers reproduce — third independent measurement.** 20 calls per arm:

  | measurement | RUN 8 | author's re-measure | RUN 9 (me) |
  |---|---|---|---|
  | hook per Bash call, base → HEAD | 51 → 145 | 52 → 147 | **52.6 → 138.0** |
  | `python3 -c pass` → `-I` | "roughly doubles" | 15.4 → 29.8 | **14.7 → 27.4** |
  | probe `python3 -I -c ''` | ~28 | ~30 | **29.3** |

  Every figure lands within ordinary machine noise. The base arm matches to 0.6 ms.
- JSONL line appended by the delta: valid JSON, correct 10-key schema, keyed to `4495bf8` — RUN 8's
  **real** SHA, not re-keyed to the new HEAD. The claim of no fabrication holds.
- No absolute paths or secret-shaped strings anywhere in the delta.

## What was changed

One documentation commit. Nothing that runs changed at all.

Think of ADR 0012 as the logbook for the doorman. RUN 8 noticed the doorman had got slower — he now
takes about 2.6 times as long to check every person walking through, because he re-verifies his own
ID badge on every single check. RUN 8 asked whether that belonged in the logbook. The answer was
yes, so this commit writes it down: how slow, why, what it buys, and what would make it faster later.

The same commit files RUN 8's verdict itself into the record.

## Does it do what you wanted?

Yes, and it clears the bar it set for itself. The instruction was to record a cost; what landed
records the cost, its provenance, its cause, its alternative, and its deferred fix.

Two things deserve credit because they are the parts people usually skip:

- The numbers were **re-measured rather than transcribed**, and when the two measurements disagreed
  slightly (51→145 vs 52→147) the ADR **shows both** instead of quietly picking one. My own third
  measurement agrees with both. That is what an honest number in an audit trail looks like.
- RUN 8's verdict was **not re-keyed** to the new SHA to make it look current. Re-keying would have
  been a one-character lie that no one would ever have caught.

**On the "accepted, not dismissed" framing — I checked whether it is rationalising a regression, and
it is not.** A rationalisation buries the number, quotes the flattering unit, omits the alternative,
or calls the cost unavoidable. This bullet does the opposite on all four counts: the multiplier is in
the bold heading, the cost is restated in the unit a human actually feels (+30 s per 300-call
session), the alternative is named along with what it would cost (reopening a defect that blocked
every Bash command machine-wide), and the relief is explicitly deferred *with a reason*. The claimed
alternative harm is also verifiable rather than hypothetical — it is documented with a reproduction
higher in the same file. If anything the stated "~2.8×" is at the pessimistic end of what I measured
(I get 2.6×), which errs *against* the author's own interest. That is the right direction to err.

## What could go wrong / what I'm unsure about

**1. A broken cross-reference inside the new bullet (new, minor, confirmed).** It says `-I` "retired
the `sys.path`-shadowing defect **two bullets up**". It is **four** bullets up (line 342). Two bullets
up (line 358) is the unrelated one about the chained-command gap in `git-guard.sh` and
`merge-guard.sh`. I verified the list is continuous with no intervening heading, so no alternative
reading rescues it. Trivial to fix, but it is a dead pointer in the one commit whose stated purpose
was making this reasoning findable six months from now.

**2. The ADR pins "line 66" into a permanent record (new, minor).** Accurate today — line 66 really is
the `-I` probe. But `judge-guard.sh` will keep changing and this number will silently become wrong,
pointing confidently at whatever else lands there. Every other citation in this ADR refers to
behaviour or symbol, not line number, so this is also inconsistent with its own house style.

**3. A garbled sentence (new, cosmetic).** "A slower hook is a worse day than a hook that wedges the
machine is a worse day still" is a mangled comparative. The intended meaning is clear but this is
permanent prose.

**4. The verdict-commit recursion — the one structural thing RUN 8 did not cover (new).** The gate
requires a verdict whose `head_sha` equals current HEAD. Committing a verdict *changes* HEAD, which
invalidates the verdict just written. That is precisely why this commit staleened RUN 8 and summoned
RUN 9 — and if RUN 9's verdict is likewise committed here, it will staleen itself in exactly the same
way. This is a genuine self-invalidating loop, not a one-off. Note that the decision to append the
real verdict line to the primary store solves the *path* mismatch but **not** this recursion: an
appended line is only truthful if it is keyed to the SHA that is actually the branch tip at the moment
`gh pr create` runs. Worth an ADR line eventually — a docs-only delta arguably ought to be
verdict-preserving.

**Carried forward from RUN 8, unchanged, not re-litigated:** the ~2.6–2.8× per-call latency (real and
shipping, but now documented, which is what RUN 8 asked for); the first-arming bootstrap risk
(`~/.claude/hooks/lib/` absent); the Python-2-only hunch (still untested, no Python 2 available);
and that this PR cannot pass its own gate. On that last one I withdraw RUN 8's `JUDGE_EXEMPT`
recommendation — the user had already ruled against it, and the diagnosis is better than mine was:
the installed hook reads a fixed absolute path, so this is a *path* mismatch wearing a *freshness*
message.

## What I'd double-check before merging

1. **Fix the "two bullets up" → "four bullets up" pointer**, and consider replacing "line 66" with a
   reference to the `PY_ISOLATED` probe. Both are one touch, in the same 15 lines, and this is the
   last moment they are cheap.
2. **Key the primary-store verdict line to the actual tip.** Before `gh pr create`, confirm the
   `head_sha` on the appended line equals `git rev-parse HEAD`. If any further commit lands on this
   branch afterwards, that line becomes false and must be re-appended, not edited.
3. **Immediately after the primary checkout pulls this**, re-run RUN 8's arming check — it is still
   the highest-consequence moment in the whole branch:
   `printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}' | bash ~/.claude/hooks/judge-guard.sh; echo $?`
   → must be `0`, and `~/.claude/hooks/lib/classify-pr-command.py` must exist.

---

## Dimensions (RUN 9)

| dimension | verdict | why |
|---|---|---|
| intent | pass | The ask was to record the latency cost in ADR 0012. It is recorded, with more rigour than requested: independent re-measurement, both number sets shown, cause split into two separately-measured components. |
| execution | pass | 101/0 run by me at this HEAD; delta is provably docs-only (both hook blobs byte-identical); appended JSONL is valid and correctly schema'd. |
| trajectory | pass | Re-measuring instead of transcribing, publishing the disagreement between the two measurements, and refusing to re-key RUN 8's verdict to a fresher SHA are all deliberate integrity choices, not luck. |
| regression | concern | Carried forward, deliberately not cleared: this delta breaks nothing (zero executable change), but the branch still ships a ~2.6–2.8× per-Bash-call latency increase. Documenting a cost reduces its severity; it does not erase it. |
| context_budget | pass | No rule, skill, or prompt file touched. ADR grows 15 lines and loads on demand only. |
| traceability | concern | The one dimension this commit lands on and partly misses: a dead cross-reference ("two bullets up" → actually four) and a line number pinned into a permanent record, both inside the bullet whose purpose is future findability. Minor and one-touch, but scored where it belongs. |
| success_masking | pass | Green verified rather than trusted — I ran the suite myself, and blob-identity means RUN 8's mutation evidence applies to exactly this code. No unbounded or expensive loop introduced. |
| intent_drift | pass | Scope is exactly the ADR bullet plus the verdict files it was meant to land. No drive-by edits, no new dependencies. |
| checkpoint | pass | Single-purpose docs-only commit; a clean revert point that cannot take behaviour with it. |
| audit_trail | pass | Provenance credited to the external critic that found it, both measurement sets preserved, deferral reasoned rather than asserted, prior verdict left honestly stale. The pointer error is charged to traceability, not double-counted here. |

**risk:** low  **confidence:** high

### Concerns (short form)

- ADR cross-reference is wrong: "two bullets up" points at the chained-command-gap bullet; the `sys.path`-shadowing bullet it means is four up.
- ADR pins "line 66" into a permanent record — accurate now, goes stale on the next edit to `judge-guard.sh`; inconsistent with the ADR's own behaviour-based citation style.
- Garbled comparative sentence in the new bullet ("is a worse day than ... is a worse day still").
- Verdict-commit recursion: committing a verdict moves HEAD and invalidates the verdict just written; the primary-store line is only truthful if keyed to the actual tip at `gh pr create` time.
- Carried forward from RUN 8: ~2.6–2.8× per-Bash-call latency (now documented); first-arming bootstrap (`~/.claude/hooks/lib/` absent); Python-2-only machines untested.
