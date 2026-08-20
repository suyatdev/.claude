# Observability verdict — git-guard detached HEAD (architecting, round 4)

- **repo:** memsearch-freshness (worktree at `/Users/marksuyat/.claude/memsearch-freshness`)
- **branch:** `HEAD` (detached worktree — card named by spec slug + round per dispatch override)
- **head_sha:** `0819db75229b2b31a98a080b3edf56bef5720603`
- **spec:** `docs/features/git-guard-detached-head.md` — blob `be836773dcf21eeffcbfbd8f6e893651280b833c` (verified with `git hash-object`)
- **stage:** architecting — **advisory only, blocks nothing**
- **ts:** 2026-08-11T01:45:25Z (filename keeps the 08-10 prefix so all four rounds of this spec sort together)
- **evidence:** all figures below were produced by this judge on git 2.50.1 / bash 3.2.57,
  patching **copies** of `hooks/git-guard.sh` in `mktemp -d` repos. The judged worktree was not modified.

---

## What was changed

The hook that stops code from landing on `main` asks "which branch am I on?" with a command that
answers with the literal word `HEAD` when there is no branch. The hook compares that to `main`,
gets "no", and steps aside — so on a detached checkout every guard silently switches off. This spec
swaps in a question with one meaning (`git symbolic-ref`) and treats "no branch" as *block*, not *allow*.

Because always blocking would trap someone in the middle of a rebase or a merge conflict — git tells
them to run `git commit`, and the guard would refuse it with advice git itself rejects — the design
adds one deliberate exception: stand down while git has an operation in progress. Round 3 found that
exception re-opened the very hole being fixed (a rebase *started from main* moves main when it
finishes). Round 4 confirms that finding was fixed properly, not written around: the exception now
reads git's `head-name` file and stays switched on for a rebase that will move `main`.

Think of it as a night watchman who used to log "couldn't read the door sign, assumed it's fine."
Now he writes "sign unreadable — nobody enters," with one carve-out for the delivery already halfway
through the door. Round 4's job was to check that carve-out is the right size.

## Does it do what you wanted?

Yes, on the main question. **The `head-name` clause is correctly bounded in every state I could reach**,
including the two that worried me most:

| Probe | Result |
|---|---|
| rebase from `main` inside a **linked worktree** (the shape the real incident had) | `--git-path` resolves per-worktree; head-name `refs/heads/main`; **exit 2** ✅ |
| cross-worktree leak — rebase from main in the *main* checkout, plain detached *linked* worktree | no leak; linked worktree still **exit 2** ✅ |
| `git rebase --root` from main | head-name `refs/heads/main`; **exit 2** ✅ |
| outside a git repository (does the new helper fail open?) | **exit 2** for both the pathspec commit and `--force-with-lease` ✅ |
| rebase started *from a detached HEAD* | head-name is the literal `detached HEAD`; carved out (0) — correct, moves no branch |
| default branch `trunk` | carve-out 0 **and** named-`trunk` source commit 0 — guard is scoped to the literal names `main`/`master` end to end; no new asymmetry |

`set -u` only, no `set -e` (`git-guard.sh:42`), so the `[ -e … ] && return 0` loop idiom is safe.

**But the two bounds do not pin what the spec says they pin.** See finding 1.

## What could go wrong / what I'm unsure about

### 1. A third bound *is* missing — rows 15 and 16 do not cover the `rebase --apply` backend

Mutation test. I took the spec's exact code, produced a weakened variant that drops `rebase-apply`
from the head-name loop (a plausible "simplify — only interactive rebases write head-name" edit),
and ran both:

```
row 15 (rebase-MERGE from main):   spec code = 2    weakened = 2   <-- gap invisible
rebase --apply from main:          spec code = 2    weakened = 0   <-- hole reopens
```

Row 15 stays green under a change that reopens the apply-backend half of the hole. The spec's own
carve-out table records that cell as `— / branchless, head-name present` — **head-name presence was
observed, the hook exit was never measured**, and `measure-headname.sh` section 5 confirms it: that
section prints state and never calls `hook`. That is exactly why the gap survived to round 4.

**Severity, stated at its true size, not inflated.** I could *not* demonstrate a hand-written commit
reaching `main` through the apply backend. Measured: after `git commit` mid-`rebase --apply`,
`--continue` refuses (`hint: Resolve all conflicts manually…`) and `src/backdoor.sh` was **not** on
main. So this is a **regression-detection gap, not a currently-open path to main** — unlike row 15,
where the file demonstrably lands on main. Fix: add row 17, `rebase --apply` from main + hand
`git commit` (source staged) → 2. I measured that as 2 under the spec's code, so the row is cheap.

*(Separately confirmed: `rebase --apply` from main **can** carry an extra source file onto main —
but via `git rebase --continue`, which the classifier never raises `COMMIT` for. That is the
pre-existing residual hole the spec already commits to enumerating in ADR 0026. I reproduced it on
both backends, so that ADR obligation is well-founded.)*

### 2. The `git am` justification is measurably false

spec:153-154 — *"`git am` writes no head-name but runs on a named branch, so it never reaches this arm at all."*

Measured, `git am` conflicting on a **detached HEAD**: `rebase-apply` present, head-name **absent**,
the `""` arm **is** reached, carve-out returns 0. The outcome is safe (am on a detached HEAD moves no
branch; on named `main` the arm is never consulted — measured exit 2). But the recorded reason is
wrong, and the real one is unstated: **`rebase-apply` is a marker shared by `git am` and
`rebase --apply`, and head-name *presence* is the only thing telling them apart.** That undocumented
discriminator is precisely what finding 1 shows is easy to break. This repo's live worktree is
detached, so this is not an exotic path here.

### 3. Two states with opposite outcomes render the same message

`checkout_desc` takes only the branch string. A carved-out rebase from `feat/x` (allowed) and a
refused rebase from `main` (bound 1) both read `symbolic-ref=[]` → both would render
`a detached HEAD (no branch checked out)`. The one fact that decides the refusal — *this rebase will
move main* — is never printed. So the answer to "can an operator distinguish a true refusal from a
false one in every reachable refusal state?" is **no**: bound 1 is the design's only refusal an
operator will experience as arbitrary, and the message cannot explain it.

### 4. The message contract contradicts row 16's Gherkin

- spec:311-312 — the remedy line *"must say finish or abort the operation when a sequencer marker is present."*
- spec:426 — `And stderr names branch "main", not an operation in progress`

An implementer writing a literal assertion from the Gherkin contradicts the contract. This is also
the only refusal path with **no exact text** in the message table, while the other four have it —
in a spec whose stated standard is exact text.

### 5. Fixture audit (as requested) — the scripts do not assert what their header claims

- **`verify-carveout-hole.sh` asserts nothing** about the states it builds. Every check is a `printf`
  for a human to read: symbolic-ref (:70), marker presence (:71, :101), head-name (:72), post-`--continue`
  HEAD (:79), backdoor-on-main (:80), switch result (:88). Its `mkpatch` does assert the patch applied.
- **`measure-headname.sh:3` claims "Every fixture asserts the state it claims to build."** Measured
  against the file, it does not: `assert_branchless` runs in sections 1–4 and **not** in 5;
  **no head-name value is ever asserted** (printed at :77, :87, :113); CHERRY_PICK_HEAD presence is
  printed, not asserted (:97); and section 4's premise — *"no operation"*, the absence of every
  marker — is never asserted at all, so its `tight=2` result infers the premise from the outcome.
  `assert_branchless` is also non-fatal (`set -u`, no `set -e`), so a broken fixture prints
  `!! FIXTURE BROKEN` **and still emits a result row that looks like data**.
- This does not invalidate the numbers — I reproduced the substance independently — but the round-3
  evidence is **eyeball-verified, not self-verifying**. The spec's checklist already sets the right
  bar for the real test helpers ("Each helper must assert the state it claims to have built"); the
  fixtures that produced the spec's numbers do not meet it.

### 6. The cited provenance is unfollowable

spec:213 says *"re-run it rather than trusting this table"* and cites `scratchpad/measure-matrix.sh`,
`verify-carveout-hole.sh`, `measure-headname.sh` as repo-relative paths. Measured: `ls scratchpad` →
**No such file or directory**; not gitignored (it isn't there). The scripts live in an ephemeral
sandbox tmp dir (`/private/tmp/claude-501/…/scratchpad/`) that will be garbage-collected. Both also
hardcode `REPO=/Users/marksuyat/.claude/memsearch-freshness` — fine for a scratchpad, a core-conduct
violation if committed as-is.

### 7. The carve-out has no time bound (low)

Measured: an abandoned `rebase -i` from `feat/x` leaves `rebase-merge` on disk, HEAD detached, and
every source commit is allowed **indefinitely** — nothing expires the marker. Reachability to `main`
is low (that rebase moves `feat/x`, and you cannot `git switch` while it exists), but the spec
describes the carve-out as scoped to *"an operation git is waiting on the operator to finish"*, and a
stale directory is not that. One sentence in ADR 0026.

## What I'd double-check before merging

1. Add **row 17** — `rebase --apply` from `main`, hand `git commit`, source staged → **2**. Without
   it the apply backend is unpinned; I measured the mutation that proves row 15 misses it.
2. Fix the `git am` sentence to state the real discriminator: head-name *presence* separates
   `git am` from `rebase --apply` inside the shared `rebase-apply` marker.
3. Resolve the spec:311 ↔ spec:426 contradiction and give the marker-aware remedy **exact text**,
   like the other four paths.
4. Decide whether `checkout_desc` should name the operation for bound 1 — today the design's only
   arbitrary-feeling refusal is unexplainable to the person hitting it.
5. Move the three scratchpad scripts into the repo (relativized, no absolute paths) or delete the
   "re-run it" claim. Right now the implementer cannot follow it.
6. Tighten the fixtures to assert head-name, marker presence, and — for the "no operation" fixture —
   marker *absence*, and make a failed assertion fatal.

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| intent | **pass** | Closes the fail-open at both call sites; round-3 findings fixed, not documented away |
| execution | **concern** | Apply-backend cell was observed, never executed against the hook; mutation shows the specified suite misses it |
| trajectory | **pass** | `head-name` is the right shape and holds in the worktree case; one stated justification (`am`) is wrong while the design is right |
| regression | **concern** | Missing row 17 lets a future edit silently drop apply-backend coverage |
| context_budget | **pass** | No always-on surface changed; `rules/gates.md` edit is two stubs; spec self-contained |
| traceability | **concern** | Findings 2, 3, 4 — false `am` rationale, one message for two opposite outcomes, contract vs. Gherkin conflict |
| success_masking | **concern** | Finding 1 (suite green under a weakened implementation); finding 5 (fixtures print, don't assert); finding 7 |
| intent_drift | **pass** | Out-of-scope section explicit and held; no drive-by widening |
| checkpoint | **pass** | Planning phase, `branch: none`, nothing modified; checklist cuts from freshly fetched `origin/main` |
| audit_trail | **concern** | Findings 5, 6 — cited provenance paths absent from the repo; fixture header overstates what it asserts |

**risk = medium · confidence = high**

Confidence is high because I ran every figure above myself against copies of the real hook; the one
thing I could not demonstrate (a hand-commit reaching `main` via the apply backend) is recorded as
unresolved rather than assumed either way.
