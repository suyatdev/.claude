# Observability verdict — RUN 9 · `feature/phase-guard-hook`

- **ts:** 2026-07-29T21:34:27Z
- **repo:** `phase-guard-hook` (linked worktree at `/Users/marksuyat/.claude/.claude/worktrees/phase-guard-hook`)
- **branch:** `feature/phase-guard-hook`
- **head_sha:** `33bc6ae8b0212496226411d068d4eceae205029e`
- **stage:** implementation (gates the PR)
- **base:** `main` @ `8f0f16dc33d23ef07bd8cf75951df88223ba0e35` (true merge-base; `origin/main` @ `c562594` deliberately not used)
- **risk:** medium · **confidence:** high
- **prior:** RUN 8 @ `5cb0985` (risk=medium, confidence=high, no failing dimension)

## Evidence I gathered myself

- `bash hooks/phase-guard.test.sh` → **126 passed, 0 failed**. Run **twice** at this HEAD; identical
  both times, so the suite is idempotent despite its `chmod 000` fixtures. `git status --porcelain`
  clean afterwards.
- `shellcheck -x hooks/phase-guard.sh hooks/phase-guard.test.sh` → **clean, exit 0**.
- Read `hooks/phase-guard.sh` in full (543 lines). Compared its ten `# --- Step N ---` headers
  against **every** step reference in the doc (56) and the suite (28), one at a time.
- **Independent behavioural probe**, not via the suite: a throwaway repo with a `planning` card,
  driven from a cwd *outside* both repos — source write → **exit 2** with the full four-element deny
  message; `docs/notes.md` → allow; the card itself → allow; card flipped to `implementation` +
  matching `branch:` → allow; a second repo that never opted in → allow, silent. All correct.
- **Second probe:** supersession reads `refs/heads/` only. A gate opened on a branch that exists
  only as `refs/remotes/origin/<b>` does **not** supersede (verified: deny returns).
- Re-verified day-one impact: `git ls-tree -d origin/main docs/` → `docs/decisions`,
  `docs/superpowers` only. No `docs/features/` on `origin/main`. Nothing denies on merge.
- Read `hooks/judge-guard.sh` and checked the store it will actually read (see finding 5).

---

## What was changed

A safety catch for the workflow. Every feature has a card with a `phase:` on it — `planning` means
"still deciding", `implementation` means "go ahead". Until now that was an honour system.

`hooks/phase-guard.sh` runs before every file write. If the repo that owns the file being written
has a card still at `planning`, and no card names the current branch as approved, the write is
refused with an explanation. Docs, memory files and the card itself are always writable, so you can
never lock yourself out — the way to open the gate is to edit the card, which is never blocked.

**RUN 9 covers three commits since RUN 8**, all record-keeping: a new test (`21a0411`), a
comments-and-docs pass that made the step numbering single-sourced to the code (`325f70c`), and a
memory-index checkpoint (`33bc6ae`). The hook's behaviour has not changed since RUN 8 — its entire
diff over those three commits is **one comment line**.

## Does it do what you wanted?

The **code** is in the best shape it has been in. 126 tests green, linter clean, and — for the first
time in nine rounds — I drove the hook end to end myself outside its own fixtures and every path
behaved as documented. I found **no behavioural defect** at this HEAD.

The **record** is much better and still not clean, and that is the same sentence RUN 7 and RUN 8
wrote. RUN 9's root-cause work was genuinely good: it found that the doc's step list and the code's
step headers described *different* sequences, which was upstream of all six sites RUN 8 reported,
and fixing that made 20-odd references resolve correctly at once. But the enumeration was scoped to
the *token* "step N" and missed the **count** claims sitting in the same document's normative
Contracts section — which are the identical defect class, one word wider.

## What could go wrong / what I'm unsure about

### 1. The Spec's own contracts still undercount the hook's audible surface (new, unreported)

The code has **nine** distinct `warn_once` reasons — `nogitbin`, `nopython`, `nopayload`,
`noresolve`, `noreporead`, `nolist`, `noparse`, `nogit`, `detached` — and the audit table enumerates
**eleven** audible rows. Three present-tense statements in the doc still describe the old, much
smaller surface:

- `docs/features/phase-guard-hook.md:611` (**Contracts → Output**, normative): *"with exactly the
  exceptions enumerated in 'The exits that must not be silent' — **six of them**"*.
- `:297` (**Frontmatter contract**): *"so it is one of the **two exits that print**"*.
- `:484` (**Flag contract** table, normative): *"`<reason>` ∈ {`nopython`, `noparse`} — **two
  independent flags**"*. Seven of the nine flag names appear nowhere in that contract.

This is worth more than a stale step number: someone reading the Output contract to reason about the
hook's stderr behaviour gets a count that is wrong by nearly half, in the section that defines it.
The same table (`:483`) also still quotes `${PHASE_GUARD_STATE_DIR:-$HOME/...}` where the code ships
`${HOME:-}` — corrected at `:388` but not in the contract, which is the two-copies pattern again.

### 2. Three step references survived the "fix every site" pass

The commit message says *"Enumerated the surface rather than patching what was reported."* Three
sites remain, none of them marked as historical:

- `:426` — *"That directly contradicts **step 5's** own 'bash builtin, not a `stat` subprocess'
  reasoning."* That reasoning is the `[ -d "$root/docs/features" ]` opt-in test, which is at
  **step 4** (`phase-guard.sh:240-248`, and the doc's own list item 4 says so). Wrong under both
  numberings — and it was authored by `508c55b`, the reorder commit itself, so it cannot be excused
  as retired prose. It sits **inside the section this pass rewrote**.
- `:449` — *"that takes the silent A1 path (**step 3's** 'not applicable' reasoning, one directory
  later)"*. The "never opted in" exit is **step 4**; the suite labels the same case
  `A1.3 … (step 4)`. Unmarked pre-`508c55b` fossil.
- `:1015` — *"`tool_name` is not extracted. **Step 4** lists it."* The list item that names
  `tool_name` is **step 3**. Its immediate neighbours in the same task-checklist section (`:1122`,
  `:1154`, `:1221`) *were* renumbered by this pass, so this one is an inconsistency inside the
  pass's own blast radius, not a deliberate historical quotation.

### 3. RUN 8's `:976` finding was closed on an axis it explicitly was not about

RUN 8 wrote of `phase-guard.test.sh:976`: *"This one is **worse than a stale number**: it states
now-wrong reasoning."* `325f70c`'s message answers: *":976 was already correct under the code's
numbering — it only read wrong under the doc's."* That addresses the number, which was never the
finding.

The line still reads: *"…the hook then cannot tell a path of its own from one outside; **step 3 has
already passed, so the rule says it speaks**."* THE RULE (`phase-guard.sh:30-40`, doc `:307-314`)
keys audibility on *this repo opted in*, which is step 4's second half and has **not** run at the
`NORESOLVE` exit. That exit speaks only via `warn_if_cwd_opted_in` — the cwd fallback the hook's own
comment (`:123-128`) frames as sitting *outside* the rule precisely because there is no repo to ask
yet. Under the **pre-`508c55b`** numbering step 3 *was* the opt-in test, so the sentence was correct
then; it is a fossil whose number now reads right by coincidence while the inference does not.

`CODING_MEMORY.md` records *"All six RUN 8 items verified by hand and landed."* Five landed. This is
a much milder recurrence of the `7f2fc9e` failure than RUN 8 found — the reasoning is stated in the
commit message and is arguable rather than unchecked — but it is the same shape, in the same block
that records the lesson.

### 4. The suite still cannot detect doc↔code drift, by construction

126 green tests coexist with findings 1–3. Nothing in the suite asserts the code's step headers, the
audible-exit count, or the flag-reason set against the document; every defect this round is
invisible to the only automated signal the branch has. Fourth consecutive round where green tests
accompany a stale record.

Mitigating, and genuinely new: **A7.4 is mutation-verified** (swap the walk-up for
`warn_if_cwd_opted_in` → A7.1 stays green, A7.4 fails with 0 stderr lines). That is the first test
on this branch that pins a *rationale* rather than a behaviour, and it is exactly the right answer to
RUN 8's F3. No unbounded or expensive loops: both walk-ups terminate at `/` on absolute paths only,
and `cat-file --batch` is one subprocess regardless of branch count.

### 5. `gh pr create` will be blocked from this worktree — verified, and it is adjacent, not this diff

`hooks/judge-guard.sh:22` reads `$HOME/.claude/coding-memory/observability-judge/verdicts.jsonl` —
the **primary checkout's** store — while deriving `repo`/`branch`/`head_sha` from the **session's**
cwd. I checked that file: 43 lines, **zero** for `feature/phase-guard-hook`. This verdict's JSONL
line lands in *this worktree's* store (54 lines). So the PR will fail closed with "no fresh
observability-judge verdict" no matter what I write.

Not a defect introduced here, and out of scope to fix — but note the irony worth recording: it is
the **same identity-from-cwd bug class** this branch just fixed in `phase-guard.sh`, alive in a
sibling Tier 1 hook.

### 6. Self-disclosed items — all five verified accurate, plus one boundary they miss

1. **Branch-granularity hole** — accurate, and stated as a Non-goal.
2. **Second-order cost (stale card denies `main`)** — accurate; I reproduced it live (my probe
   denied on `main` with an active planning card).
3. **Rollback path 3 withdrawn, exit 126 unverified** — accurate, and correctly left unverified. I
   did not test it either; arming a hook that may lock the machine is not a judge's experiment.
4. **Parallel-worktree collision vs. `core-conduct.md`** — accurate, and correctly left as a
   user-owned governance trade-off.
5. **Not armed until merge** — accurate; `settings.json` registers `$HOME/.claude/hooks/...`, which
   is the primary checkout's copy, on another branch.

**The sixth, undisclosed:** supersession reads `refs/heads/` only, so a gate opened on a branch that
exists **only as a remote-tracking ref** (pushed then deleted locally, or opened from another clone)
does not supersede — the repo returns to denying every source write. Verified by probe. Realistic
exposure is narrow and the deny message is actionable, so this is a completeness note, not a defect.
Also still undisclosed and carried from RUN 8: the A7 walk-up forks one `dirname` per path level on
every write landing **outside any repo**, a path none of the recorded figures cover.

## What I'd double-check before merging

1. **Fix the three contract counts** — `:611` "six of them", `:297` "two exits that print", `:484`
   `<reason>` ∈ {nopython, noparse}. These are normative, not narrative.
2. **Fix `:426` (step 5 → 4), `:449` (step 3 → 4), `:1015` (Step 4 → 3).**
3. **Answer `:976` on its own axis** — the inference, not the number. One clause: it speaks via
   `warn_if_cwd_opted_in`'s cwd fallback, *not* because any opt-in test has passed.
4. **Correct `CODING_MEMORY.md`'s "all six items landed"** to five-of-six, or close item 2 properly.
5. **Expect `gh pr create` to be blocked** from this worktree (finding 5). Decide deliberately:
   `JUDGE_VERDICTS_FILE=$PWD/coding-memory/observability-judge/verdicts.jsonl`, or a logged
   `JUDGE_EXEMPT=<reason>` — do not "just retry the judge", which will not help.
6. **Consider one cheap structural test** that greps the doc's step list against
   `grep '# --- Step' hooks/phase-guard.sh`. Four rounds of this defect class say the record cannot
   be kept correct by care alone.

---

## Dimensions

| Rubric | Dimension | Verdict | Basis |
|---|---|---|---|
| Evaluation | `intent` | **concern** | Five of RUN 8's six items genuinely and verifiably closed; the sixth (`:976`) closed on the wrong axis, and the memory index asserts all six. The numbering *is* now single-sourced, which was the real ask. |
| Evaluation | `execution` | pass | 126/126 twice, shellcheck clean, suite idempotent, tree clean — all run by me at this HEAD. Independent end-to-end probe of deny / doc-exempt / card-exempt / claimed-branch / never-opted-in: all correct. No behavioural defect found. |
| Evaluation | `trajectory` | **concern** | Root cause was found genuinely upstream of the reported symptoms, and enumeration surfaced three things nobody reported. But the enumeration was scoped to the token "step N" and missed the count claims in the same doc — third consecutive round where "we enumerated it this time" was incomplete. |
| Evaluation | `regression` | pass | Hook diff since RUN 8 is one comment line. Fourth `PreToolUse` block, no existing block edited; `.gitignore` scoped to `/hooks/state/`; day-one impact re-verified nil on `origin/main`. |
| Evaluation | `context_budget` | pass | `rules/gates.md` +64 words, unchanged since RUN 8. Proportionate for a Tier 1 gate, and it discloses both the guardrail-not-boundary limit and the absence of a bypass. |
| Observability | `traceability` | **concern** | Materially improved — one numbering, stated once, resolving correctly at ~53 of 56 doc sites and every suite site but one; ADR 0011, superseded-in-place stamps, live-run record. Undercut by three normative contract statements that undercount the audible surface by half. |
| Observability | `success_masking` | **concern** | 126 green tests coexist with every defect found this round; the suite cannot observe doc↔code drift by construction. Fourth such round. Offset by A7.4, the branch's first mutation-verified rationale test. No unbounded or expensive loops. |
| Observability | `intent_drift` | pass | Three commits, each mapping to a RUN 8 item or a checkpoint. `325f70c` is comments/docs only (hook diff: one comment line); `33bc6ae` is memory only. No new dependencies, no drive-by edits. |
| Observability | `checkpoint` | pass | Clean test → docs → memory ordering; obvious revert points; `33bc6ae` is a pure checkpoint touching no code, test, or `docs/`. Rollback documented with path 3 honestly withdrawn rather than papered over. |
| Observability | `audit_trail` | **concern** | Attributable, ADR-backed, and the record self-reports the `7f2fc9e` "all four findings / one file" failure and encodes the `git show --stat` lesson — genuinely against self-interest. Undercut by "all six RUN 8 items landed" when one was reinterpreted rather than answered. |

## Concerns

1. Spec's normative Output contract (`:611`) says "six" audible exceptions; the code has nine `warn_once` reasons and the audit table eleven rows. Frontmatter contract (`:297`) still says "two exits that print"; Flag contract (`:484`) enumerates 2 of 9 flag names and quotes `$HOME` where the code ships `${HOME:-}`.
2. Three unmarked stale step references survived a pass claiming "fix every site": `:426` (step 5 → 4, authored by the reorder commit itself, inside the section this pass rewrote), `:449` (step 3 → 4), `:1015` (Step 4 → 3, while its neighbours were renumbered).
3. RUN 8's `:976` finding was about wrong *reasoning*, not a wrong number; it was closed as "already correct under the code's numbering". The line still says the rule makes it speak, when it speaks via `warn_if_cwd_opted_in`'s cwd fallback. `CODING_MEMORY.md` records all six items as landed; five did.
4. The suite cannot detect doc↔code drift by construction — 126 green tests are blind to every defect above. Fourth consecutive round with that shape.
5. Verified adjacent blocker: `judge-guard.sh:22` reads `$HOME/.claude/coding-memory/.../verdicts.jsonl` (43 lines, zero for this branch) while resolving identity from the session's cwd, so `gh pr create` from this worktree fails closed regardless of this verdict. Same identity-from-cwd class this branch fixed in `phase-guard.sh`; out of scope to fix here.
6. Undisclosed boundary: supersession reads `refs/heads/` only — a gate opened on a remote-only branch does not supersede, and the repo resumes denying (probe-verified). Also still undisclosed: one `dirname` fork per path level on writes landing outside any repo, a path no recorded figure covers.
7. Verified accurate as stated, not rediscovered: branch-granularity hole; stale-card lockout of `main` and hotfix branches until merge (reproduced live); rollback path 3 (exit 126) deliberately unverified — I did not test it either; parallel-worktree collision unresolved and user-owned; registered but not armed until merge.
8. No behavioural defect found at this HEAD: deny, doc/card exemption, branch claim, and never-opted-in silence all confirmed by direct invocation outside the suite's fixtures.
