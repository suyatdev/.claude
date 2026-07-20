# Observability Judge — architecting verdict (round 2)

- **ts:** 2026-07-20T16:20:58Z
- **repo:** `.claude`
- **branch:** `feature/judge-terminal-enforcement`
- **head_sha:** `ccd02fca57f9dd94e356fb0545efd463c46a1d47`
- **stage:** architecting (advisory, non-blocking)
- **artifact:** `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md` (862 lines, was 464)
- **base:** `main` · **prior round:** `2026-07-20-feature-judge-terminal-enforcement.md` (head `8aed77a`, risk=medium)
- **test command:** none supplied — nothing executable exists at design stage. Verification was done by
  running the design's load-bearing git claims against real `git` 2.50.1 in throwaway repos, and by
  reading its claims about existing files back against those files.

---

## What was changed

Round 1 of this design put a real lock on the spec-review door (a `git commit` that stages a spec now
has to show a fresh compliance verdict), and moved both judges out of the main chat window into their
own terminal sessions. I flagged three things. Round 2 fixes them, and the author found a fourth
himself.

- **The revise loop got its brake back.** Before, the hook could relaunch a judge forever. Now the hook
  stops and escalates to you when the same violation shows up twice in a row, or when round 3 is still
  failing — and it stops *before* launching, so an escalation costs zero judge sessions. This is
  better than what I asked for.
- **The launcher can now actually carry what the judges need.** Round 1's argument list structurally
  couldn't pass a context summary. Now it passes files, and only the file *paths* get validated — the
  contents are copied in as bytes and never touch a shell.
- **The "we're reusing proven code" claim was corrected.** I said `judge-guard.sh` has no `git -C`
  handling; it doesn't. The spec now says plainly which parts are reuse and which are new code.
- **A livelock the author found while revising.** The gate and the judge were hashing the spec from two
  different places (staged copy vs. the file on disk). When those differ, the hook would relaunch the
  judge forever, each round a full session.

## Does it do what you wanted?

Mostly, and the revisions are real reasoning rather than box-ticking — the fix that convinces me is the
one **neither judge asked for**: the two-hash livelock in §5.2. You only find that by re-reading your
own design adversarially. The escalation cap is also better placed than I proposed (before the launch,
not after).

**But the §5.2 fix does not collapse the class it claims to, and I verified that rather than reasoned
it.** The spec says the staged-vs-worktree precondition is "load-bearing for three commit forms" and
§7 has two scenarios asserting `git commit -a` and `git commit -- <path>` are covered. In a real repo:

```
# spec modified on disk, never `git add`ed
$ git diff --cached --name-only        # -> (empty)
$ git commit -aqm x
$ git show HEAD:docs/superpowers/specs/s.md
v2                                     # the modified spec WAS committed
```

The hook decides "is a spec staged?" from `git diff --cached --name-only` (§6.2's fast path) and exits 0
when nothing spec-shaped is listed. For `-a` and for `git commit -- <path>`, the spec is committed from
the **worktree** and never appears in that listing — so the hook exits 0 and the §5.2 precondition is
never reached. The second case is worse: staging an unrelated file makes the listing non-empty, so the
hook proceeds and still sees no spec.

```
$ git add other.txt && git commit -qm y -- docs/superpowers/specs/s.md
$ git diff --cached --name-only        # -> other.txt   (no spec)
$ git show HEAD:docs/superpowers/specs/s.md
v2                                     # unjudged spec content landed
```

The reasoning in §5.2 is circular: the precondition only *runs* once a spec is detected as staged, but
the two forms it claims to resolve are exactly the forms where the spec is never staged. The
precondition genuinely fixes the livelock it was written for — that part holds — it just doesn't cover
`-a` or pathspec commits. Detection has to understand the commit *subcommand's* options, not only git's
global ones.

## What could go wrong / what I'm unsure about

**Lead concern — two common commit forms walk past the gate** (above). This is the "deterministic"
promise the whole change exists to make, and it has a hole in it that a routine `git commit -am` falls
straight through. Not fatal: §10 already lists a test case for both forms, and if that test is written
against real git rather than against the scenario's wording, it catches this before merge.

**The cap is bounded; its release is not.** You asked directly, so plainly:

- *Is the cap bounded?* Yes. Rounds are counted per `spec_path` (correct — per-blob would reset every
  revision and never fire), and the round-3 branch fires regardless of ids, so the loop tops out at
  ~3 judge sessions per human decision. That is a real brake.
- *Can the ack be abused?* Yes, in one specific way the spec doesn't name. `SPEC_ESCALATION_ACK` is
  "single-use" only in the sense that it authorises one launch — nothing stops an agent from supplying
  it again on the next attempt. An agent that sets it on every retry disables the cap entirely. The
  spec's protection is *"if the same id recurs on a later round the ack is no longer set"*, which
  assumes the agent chooses not to re-set it. That is an assumption of agent good behaviour inside a
  mechanism whose founding premise is that agents skip guidance. The cap is deterministic; the release
  is convention.
- Related: the §6.4 table's "Who may set it" column (`user only` vs `agent, after consulting the user`)
  is not enforceable — all three are just env assignments on a Bash call, indistinguishable to the
  hook. That's already true of `JUDGE_EXEMPT`, so it's consistent, but the ack is the first key an
  agent is *authorised* to set itself, which changes who can advance the loop. Logging to stderr and
  the manifest makes it attributable after the fact, which is a genuine mitigation, not a fix.

**A possible new deadlock, from an ambiguity.** The ack "suppresses the escalation check for precisely
the listed ids", but the round-3 branch has **no ids in its predicate** — it fires "whatever the ids
are" (§7). So: does acking one id release a round-3 escalation that also carries two unacked ids? The
mermaid diagram says yes (both branches flow to the ack); the prose says id-scoped. If an implementer
reads the prose strictly, a spec that reaches round 3 failing can *never* launch a judge again, because
stored rounds only increase — and the only escape left is `SPEC_EXEMPT`, which skips judging entirely.
That is the same deadlock the ack was introduced to prevent, relocated to the other branch. Cheap to
close with one sentence; expensive to discover in implementation.

**Cap resets on rename.** Rounds are keyed on `spec_path`. Renaming the spec resets the counter to 1.
Deliberate per-path counting is right; the rename escape isn't mentioned, and a scope-change rename is
an ordinary thing to do mid-revision.

**Carried over from round 1, correctly handled but still unresolved.** S3 is now blocking, with the
design fork (blocking-and-retrying) spelled out — that's exactly what I asked for. It remains
*unmeasured*, so the whole of §6.5 is still an assumption. Same for S1. Both are honestly labelled.

**Smaller.** The substring pre-filter is well argued and the invariant ("the substring can only skip
work, never decide a block") is stated as a test, grounded in a real past bug in this repo — good. The
threshold duplication between hook and skill is named rather than hidden, with a test asserting
agreement. The spec is now 862 lines, past the repo's own 800 ceiling; it's a doc rather than source,
but it is getting hard to hold in one head, and §5.2's circularity is the kind of thing length hides.

## What I'd double-check before merging

1. **Fix the `-a` / pathspec detection, or drop the claim.** Detection must parse `commit`'s own
   options and pathspec arguments, not just git's globals — for `-a`, the relevant comparison is
   worktree vs. `HEAD` for tracked specs. Then write the §10 test case against real git, not against
   §7's wording; as written, a test derived from the scenario would pass while the gate is bypassable.
2. **State whether the ack releases the round-3 branch.** One sentence, either way. Right now the
   diagram and the prose disagree.
3. **Decide what stops an agent re-supplying the ack every round.** Options: refuse an ack whose ids
   were already acked in the store, or accept it and say out loud that the release is advisory. Either
   is fine; silence is not.
4. **Run S3 and S1 before any launcher code.** The spec already says this; it's still the thing most
   likely to invalidate §6.5 wholesale.
5. Note that a spec rename resets the round counter, and decide if you care.

---

## Dimension table

| Dimension | Verdict | Note |
|---|---|---|
| intent | concern | Core deterministic-gate promise has a verified hole: `git commit -a` and `git commit -- <path>` never reach the §5.2 precondition, because detection short-circuits on an empty staged-file listing. Spec asserts the opposite in §5.2 and §7. |
| execution | concern | Nothing runnable. S3 correctly promoted to blocking with a stated design fork (round-1 ask met), but §6.5 is still entirely unmeasured, as is S1. |
| trajectory | pass | Revisions are substantive, not responsive: the cap moved *before* the launch (better than asked), the "verbatim reuse" overclaim was corrected with the right reasoning, and the two-hash livelock was self-found. Per-`spec_path` round counting is reasoned from why per-blob would fail. |
| regression | concern | Two common commit forms bypass the gate; classifier blast radius is the highest-frequency command in the repo; global-option handling is new code (correctly relabelled). Pre-filter invariant is well stated. |
| context_budget | pass | Net positive — moves judge work out of the main window. No always-on rule growth. Spec doc is 862 lines (past the repo's 800 ceiling) but is not always-on context. |
| traceability | pass | Diagrams, exit-code table, failure matrix, manifest fields, pinned toolchain, §11 deferrals, §12 doc obligations, round-2 deltas surfaced in the header rather than absorbed. |
| success_masking | concern | §7's `-a`/pathspec scenarios encode a belief real git contradicts, so a test written from them passes while the gate is bypassable. Ack re-supply makes a deterministic cap advisory. Round-3 branch may be unreleasable under a strict reading. |
| intent_drift | pass | Scope table unchanged; the one self-found fix is in-scope and declared; no new deps; iTerm2 removal is a recorded user decision with its consequence (osascript surface remains) honestly retained. |
| checkpoint | pass | Docs-only, one new commit on a feature branch, trivially revertible. |
| audit_trail | pass | Round-2 changes attributed to specific round-1 findings; §12 lists the new ADR plus the ADR-0003 update. Ack is recorded in the manifest and stderr. |

## Concerns

- `git commit -a` with a never-staged spec: staged-file listing is empty, hook exits 0, unjudged spec content is committed — verified against real git
- `git commit -- <spec>` with an unrelated file staged: listing shows only the other file, hook proceeds, spec is never seen — verified
- §5.2's claim to be "load-bearing for three commit forms" is circular: the precondition only runs after a spec is detected as staged, which is exactly what `-a` and pathspec commits skip
- Detection handles git's global options but not the `commit` subcommand's own options or pathspec arguments
- `SPEC_ESCALATION_ACK` is single-use per launch but re-suppliable every round; an agent that always sets it disables the cap entirely
- Ack ambiguity: the round-3 escalation branch has no ids in its predicate, so whether an id-scoped ack releases it is undefined — prose says id-scoped, diagram says released
- Under a strict id-scoped reading, a spec that reaches round 3 failing can never launch a judge again; only SPEC_EXEMPT escapes, and that skips judging entirely
- §6.4's "Who may set it" column is convention, not a control — all three keys are indistinguishable env assignments to the hook
- Round counting per `spec_path` resets on a spec rename, silently clearing the cap
- S3 (900s hook timeout honoured; timed-out hook fails open) is correctly blocking but still unmeasured; all of §6.5 rests on it
- S1 (`JUDGE_SESSION=1` reaches hooks inside the judge session) still unmeasured; design is deadlock-shaped if it fails
- Spec doc is 862 lines, past the repo's own 800-line ceiling; §5.2's circular reasoning is the kind of defect that length conceals

**risk:** medium · **confidence:** high
