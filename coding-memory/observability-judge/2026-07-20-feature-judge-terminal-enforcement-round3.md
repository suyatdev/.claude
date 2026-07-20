# Observability Judge — architecting verdict (round 3)

- **ts:** 2026-07-20T17:26:30Z
- **repo:** `.claude`
- **branch:** `feature/judge-terminal-enforcement`
- **head_sha:** `60581c83d5e13d08afc9777fa8e3a643a88dae17`
- **stage:** architecting (advisory, non-blocking)
- **artifact:** `docs/superpowers/specs/2026-07-20-judge-terminal-enforcement-design.md` (1036 lines; was 862 at round 2, 464 at round 1)
- **base:** `main` (merge-base `69ecd12`) · **prior rounds:** round 1 `8aed77a` (risk=medium), round 2 `ccd02fc` (risk=medium, confidence=high)
- **test command:** none supplied, and none exists — **nothing is built**. No launcher, no
  `spec-guard.sh`, no libs, no test harness. `execution` is scored against that fact and no test
  result is reported here.
- **How this was verified:** the design's load-bearing git claims were run against real `git 2.50.1`
  in throwaway repos rather than read; its claims about existing repo files were checked against
  those files.

---

## What was changed

Think of it as putting a lock on the design-review door, and moving the inspector out of your office.

Right now this repo has two quality gates. The one before a pull request is a real lock — a script
checks it and you cannot walk past it. The one after writing a spec is a sticky note that says
"please get this reviewed"; the model is free to ignore it. Round 1 proposed making the second one a
real lock too, triggered on `git commit` when a spec file is part of the commit. It also moved both
reviewers into their own terminal windows, so their work stops eating the main chat's memory
(one round of reviewing *this* spec cost ~86k tokens out of a ~100k session budget).

Round 3 changes three things on top of round 2:

- **The brake now actually works.** Round 2 added a rule: if the same complaint survives two rounds,
  stop and ask the human. But nothing was feeding the reviewer the *previous* round's complaints, so
  the reviewer had no reason to reuse the same ID — every repeat looked like a brand-new complaint
  and the brake could never engage. Round 3 has the hook pull last round's complaints out of the
  store and hand them over. The author traced this and one other failure to a single root cause:
  round 2 designed the launcher's *interface* without designing its *caller*.
- **The commit-form bug I found last round is genuinely fixed.** Round 2 claimed one precondition
  covered all three ways of making a commit. It didn't, and it was wrong in a circular way. Round 3
  replaces it with per-form detection, and — good sign — the spec now tells the implementer to test
  it *against real git, not against the table in the spec*.
- **Two of its own claims are corrected in the open**, not quietly patched, including one the author
  found himself (an "acknowledge and retry" escape that deadlocked on one branch of the rule it was
  meant to unblock).

## Does it do what you wanted?

Yes, and the reasoning has visibly improved rather than just absorbing my notes.

**I re-ran the §5.2 correction against real git rather than reading it, as asked. The table is
correct for all three forms it lists:**

```
plain `git commit`   -> records the INDEX blob      (staged v2 committed while worktree said v3)
`git commit -a`      -> records the WORKTREE blob   (never-staged spec committed; --cached was empty)
`git commit -- path` -> records the WORKTREE blob   (and a separately staged file was NOT committed)
```

So the correction is real and the round-2 defect is closed.

**But the enumeration is not exhaustive, and one command I ran walks straight through the gate.**
`git commit -i -- <other-file>` (`--include`) commits the named paths *plus everything already
staged*. Verified:

```
# spec staged as v6; other.txt modified but not staged
$ git commit -m eA -i -- other.txt
$ git show HEAD:docs/superpowers/specs/s.md
v6                       # the staged spec WAS committed
```

The spec's detection sees a `--` pathspec, so it classifies this as the pathspec form and lists
`git diff --name-only HEAD -- other.txt`, which names only `other.txt`. The spec is never seen and
the hook exits 0 on its fast path. `-i`, `--include` and `--only` appear nowhere in the document.
This is the *same class* of miss as the `-a` bug, one form over — which is the real lesson: a
hand-enumerated table of commit forms is the wrong shape for this. Resolving the effective file set
once (rather than per-form) would close the class instead of adding a fourth row.

**A second parsing hazard, also verified:** `git commit -ma "x"` is `-m` with the message `a`, **not**
`-a`. A parser that detects `-a` by scanning a short-flag cluster for the letter `a` misfires here.
The spec says the hook "parses `commit`'s own options far enough to detect `-a`/`--all`" but never
lists which of `commit`'s own short options take a value (`-m -c -C -F -t -u -S`). On the repo's
most-run command, that detail is not a footnote.

**One factual claim in the spec is wrong.** §6.5 states "No hook in `settings.json` sets an explicit
timeout today; every one runs on the default." Ten of the seventeen registered hook entries set
`"timeout": 10`. The substantive point survives — and actually sharpens: the only precedent in the
file is **10 seconds**, and the design proposes **900**, ninety times larger. Spike S3 remains
correctly blocking.

Everything else I spot-checked was accurate: `judge-guard.sh` genuinely has zero `-C` handling
(0 matches), `coding-memory/judge-runs/` is genuinely absent from `.gitignore`, both agent
definitions genuinely declare `Read, Grep, Glob, Bash, Write`, and every pinned version matches this
machine (`claude 2.1.215`, `tmux 3.6a`, `cmux 0.64.20 (100) [14e3400b9]`, `git 2.50.1`), including
`TERM_PROGRAM=ghostty` under cmux.

## What could go wrong / what I'm unsure about

- **Nothing is built.** Every claim here is about a document. Two spikes (S1 auth + recursion guard,
  S3 hook timeout) are correctly marked blocking and both are still unmeasured. S3's bad outcome is
  the nastiest shape available: if the harness caps the hook timeout below 840s, the gate fails open
  *silently, exactly when the judge is slow* — a commit that looks judged and never was. The spec
  says this in its own words, which is to its credit, but saying it is not measuring it.
- **Blast radius.** This hook fires on `git commit`, the most-run command in the repo. A classifier
  bug blocks every commit. The design mitigates well (substring pre-filter, fail-open on
  classification ambiguity, fail-closed only on infrastructure failure), but the `-i` gap and the
  `-ma` hazard are both in exactly the new code that carries this risk.
- **The brake's release is advisory and the spec admits it.** `SPEC_ESCALATION_ACK` is single-use per
  launch but re-suppliable every round by the agent, and the hook cannot tell a human-authorised ack
  from a fabricated one. So the loop is *detectable* but not *preventable*. §6.4 states this plainly
  instead of implying a control it can't back — that is the right call, and the risk still exists.
- **A 14-minute blocking `git commit`** is a real change to the feel of the repo. §6.7 owns this
  rather than letting it be discovered, and the cache-hit path is a store read. Still the biggest
  behavioural unknown once it ships.
- **Length.** 1036 lines, versus 333 for the next-longest spec in this repo and 235 for the
  compliance-judge design it extends. It is past the repo's own 800-line ceiling. This matters
  causally, not stylistically: the §5.2 circular argument survived two reviews by being *read*, and
  length is the medium that let it. Round 2 was 862; round 3 answered my notes by adding 174 more
  lines of prose. The prose is honest, but the growth curve is the thing to watch.

## What I'd double-check before merging

1. **Run S3 first, before any code.** Register a hook with `"timeout": 900`, sleep past it, and
   record whether the tool call is blocked or allowed, plus the effective cap. If it caps below 840s,
   take the §6.5 fork (blocking-and-retrying) *before* writing the launcher.
2. **Run S1 next.** Confirm `claude -p --agent` authenticates on subscription auth and that
   `JUDGE_SESSION=1` reaches hooks inside the judge session. If it doesn't, the design is
   deadlock-shaped and should stop there.
3. **Close the commit-form class, not the `-i` instance.** Handle `-i`/`--include`/`--only`, and
   enumerate which of `commit`'s own short options consume a value (`-ma` is `-m a`). Prefer one
   effective-file-set resolution over a fourth table row.
4. **Fix the §6.5 sentence** about no hook setting a timeout — ten do, at 10s.
5. **Hold §10's falsification mandate.** The two named mutations that matter most (drop
   `--prior-violations-file`; revert detection to `--cached` only) are both bugs that already shipped
   in reviewed revisions of this spec. Add a third: classify `git commit -i -- <path>`.

---

## Dimension table

| Dimension | Score | Note |
|---|---|---|
| `intent` | pass | Solves both stated problems; closes ADR-0003's deferral; both amendments to the approved design surfaced, not absorbed |
| `execution` | concern | **Nothing is built and no test was run.** Two blocking spikes unmeasured; one demonstrated detection gap in new code |
| `trajectory` | pass | Root-caused both persistent violations to one omission (interface designed without caller); self-corrected two claims; §10 mandates falsification and tells the implementer to run git, not read the table. Caveat: per-form enumeration remains the wrong shape, and one repo-fact claim is false |
| `regression` | concern | Gate sits on the repo's most-run command; `-i` bypass and `-ma` parsing hazard live in that new code; 840s inline block changes commit feel |
| `context_budget` | pass | Always-on delta is ~1 line in `rules/gates.md`; both skills are on-demand; the change *reduces* main-window cost, which is half its purpose. The 1036-line spec is an artifact-size concern, filed under trajectory rather than mis-scored here |
| `traceability` | pass | Round history, corrections attributed to how they were found, failure matrix, mermaid flows, manifest records rung/argv/pid |
| `success_masking` | concern | Cap is now able to fire (`--prior-violations-file`) and fires before launch; §10 forbids counting a test that survives its mutation. Residual: ack re-suppliable every round; S3 silent-fail-open; a green suite over three enumerated forms would overstate detection coverage |
| `intent_drift` | pass | Explicit out-of-scope column and non-goal; no new dependencies ("no `jq` dependency is introduced"); versions pinned; growth is revision depth, not scope creep |
| `checkpoint` | pass | Feature branch, one commit per round with memory recorded; nothing implemented, so revert is free; §12 requires the `.gitignore` entry to land *before* any run dir is written |
| `audit_trail` | pass | New ADR + ADR-0003 update required; every bypass echoed to stderr; ack in manifest, absent from prompt; §6.4 reasons explicitly about post-hoc reconstructibility |

## Concerns

1. `git commit -i -- <other>` commits a staged spec while detection lists only the pathspec — gate bypassed; verified against real git
2. `-i` / `--include` / `--only` appear nowhere in the spec; the per-form table is a hand enumeration, so the bypass class is open rather than closed
3. `git commit -ma "x"` is `-m a`, not `-a`; spec never lists which of `commit`'s own short options take a value
4. §6.5 claims no hook in `settings.json` sets an explicit timeout — ten of seventeen set `"timeout": 10`; the 900s proposal is 90x the only precedent
5. S3 unmeasured: if the harness caps below 840s the gate fails open silently exactly when the judge is slow
6. S1 unmeasured: without `--bare`, hooks run in the judge session and the design is deadlock-shaped if `JUDGE_SESSION=1` does not reach them
7. `SPEC_ESCALATION_ACK` is re-suppliable every round by the agent; the cap's release is advisory and unenforceable by the hook (stated plainly, deferred in §11)
8. Classifier blast radius is the repo's most-run command; a bug blocks all commits
9. A miss now blocks `git commit` inline for up to 840s — a real change to the feel of the repo
10. Spec is 1036 lines, past the repo's own 800-line ceiling and 3x the next-longest spec here; length is the medium in which the §5.2 circularity survived two reviews
11. No automated test exercises a real judge; cmux and Terminal rungs rest on a manual checklist
