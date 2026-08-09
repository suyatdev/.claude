# Observability verdict — `docs/verify-before-claiming` @ `31840d8`

- **Stage:** implementation (gates the PR)
- **Repo:** `verify-rule` (worktree of `~/.claude`)
- **Branch:** `docs/verify-before-claiming`
- **HEAD:** `31840d89ea65453aea1744ed3d56d05443ce44c4`
- **Base:** `origin/main` @ `8f0e884` (= `HEAD~1`)
- **Judged:** 2026-08-09T23:36:24Z
- **Risk:** low · **Confidence:** high

---

## What was changed

One sentence-group added to one paragraph of one rule file. That's the whole change: `rules/core-conduct.md`, one line replaced by one longer line.

The old rule said: *check your work before you say it's done.* The new rule adds: *and before you write it down.* Writing it down means an ADR, a memory file, a commit message, a PR body, a handoff, or a spec. It also adds the reason — a claim sitting in an audit trail reads as **settled**, so a wrong one is more expensive to pull back out than the original mistake — plus an instruction to record what you checked *and* what you didn't, and a pointer to `superpowers:verification-before-completion` for the actual procedure.

Think of it as the difference between telling a colleague "the tests pass" and writing "tests pass" into the permanent project record. The first one gets corrected in the next sentence. The second one gets believed for six months.

## Does it do what you wanted?

Yes. I checked the diff byte-for-byte and it is exactly what was described: one file, `+1/−1`, no hidden extras.

I also independently re-ran the checks the author said they ran, rather than taking their word:

- **Is this genuinely not already on `main`?** Yes. I grepped `origin/main` for the new wording — 0 hits — and then ran the *same* grep for wording I knew was there, which returned hits. That second step matters: it proves the search was capable of finding something, so "0 hits" means absent, not broken.
- **Does the skill it points at actually exist?** Yes — `superpowers/6.2.0/skills/verification-before-completion`. My first look said "missing", but I'd looked in the wrong place; it lives in the plugin cache. Not a dangling reference.
- **Did anything else touch this file and collide?** Only `67dd138`, which added a *different* paragraph. No duplication, no contradiction.
- **Does this really need a PR?** Yes. `hooks/git-guard.sh:186` allows only `CODING_MEMORY.md`, `coding-memory/*`, `docs/*.md` onto `main`. `rules/core-conduct.md` matches none of them.

**One correction to the brief I was given.** I was told item 6 was an admitted gap — that the `triaging-new-instructions` gate never ran, and to score that harshly. That is not what the record says. The commit message states *"Triaged with triaging-new-instructions"* and spends a full paragraph on the result (why a static rule and not a hook: keying on claim words would fire on every Conventional-Commits `fix:` prefix). `CODING_MEMORY.md:437-438` says the same thing independently. The gate ran at original authoring; it simply wasn't *re-run* nine days later on revival, which is a fair call for an unchanged one-line diff. So the trajectory scores better than the brief invited — but note the shape of the problem: **the live summary and the permanent record disagree about whether a gate ran.** That is precisely the failure this change exists to prevent, showing up in the change's own paperwork. It errs toward self-criticism rather than self-flattery, which is the harmless direction, but a reviewer reading only one of the two sources gets a wrong picture.

## What could go wrong / what I'm unsure about

Nothing here can break a build — it is prose in a rule file. The risks are about the record and the rent it charges.

1. **The memory entry goes stale the moment this merges.** `CODING_MEMORY.md:434` still pins this branch as `1721a3c`, off `2b8564b`. The rebase made it `31840d8`, off `8f0e884`. Neither SHA in the permanent index will exist on the merged history. A rule about not writing down unverified claims is about to land alongside a written-down claim that is now wrong.
2. **No ADR, and there is a precedent two days old.** The last comparable change — `67dd138`, also a paragraph added to `core-conduct.md` — shipped **ADR 0019**, 78 lines, whose entire subject is *"does this belong in always-on `core-conduct` or somewhere cheaper?"* That is the same question this change answers, and it answers it only inside a commit message. In fairness, ADR 0019 is dated 2026-08-07 and this commit was authored 2026-07-31, so the precedent did not exist when the work was done. It exists now, at merge.
3. **This is always-on context, charged every turn, forever.** `CLAUDE.md:7` imports this file unconditionally. The paragraph grew `core-conduct.md` from 628 → 733 words (**+17%**); the always-on trio is now ~2,501 words. The procedure is correctly delegated to a skill, which is the right instinct — but roughly two of the five new sentences are rationale, and the file's own doctrine says "context is a budget, not a vessel to fill." Worth accepting deliberately rather than by default.
4. **There is no test evidence, and there cannot be.** I ran the stated command myself and it failed here: `memsearch/.venv/bin/python` doesn't exist in this worktree (the venv lives untracked in the primary checkout). I did **not** copy the reported "74 passed" forward. Nothing in the repo tests rule-file prose — no test references `core-conduct` at all. Low impact for a prose change, but the honest statement is *unverified by execution*, not *verified green*. Credit where due: the author disclosed the suite and explicitly declined to offer it as evidence, which is the correct handling.
5. **A trap for whoever reviews this locally.** Local `main` is **49 commits behind** `origin/main`. Running the `git diff main..HEAD` I was handed produces a **552 KB** diff across many files and looks like massive scope creep. The true parent is `HEAD~1` = `8f0e884` = `origin/main`, and against that it is `+1/−1`. The GitHub PR will be correct; a local reviewer may panic.

## What I'd double-check before merging

1. **Update `CODING_MEMORY.md:434`** to the post-rebase `31840d8` off `8f0e884`, or reword it to not pin a SHA. Cheapest fix, highest symbolic cost if skipped.
2. **Add the ADR**, following `0019`'s pattern — the rationale already exists in the commit message and only needs lifting into `docs/decisions/`. I'd do it: precedent is two days old and directly on point, and it's the artifact a future reader will look for.
3. **Consciously accept the +17% always-on cost**, or trim the two rationale sentences to one. I'd keep them — the "why" is what makes this rule survive contact with a tired agent.
4. **Tell reviewers to diff against `origin/main`, not `main`** (or fast-forward local `main` first).
5. **Leave this verdict uncommitted** until after `gh pr create` — `judge-guard.sh` compares `head_sha` by strict equality, so committing it moves HEAD and invalidates it.

---

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| `intent` | pass | Diff is exactly one file, `+1/−1`; content matches the description verbatim. |
| `execution` | concern | Stated test command unrunnable here (`memsearch/.venv` absent); I ran it and observed the failure rather than repeating the reported result. No coverage exists for rule prose. |
| `trajectory` | pass | Revived not rewritten; rebase preserved authorship; absence from `origin/main` proven with a known-positive control; allowlist read correctly; triage was performed and recorded. |
| `regression` | pass | Only `67dd138` touched the file since, adding a different paragraph; skill pointer resolves; no competing copy of the invariant in always-on context. |
| `context_budget` | concern | Always-on via `CLAUDE.md:7`; `core-conduct.md` 628 → 733 words (+17%, +643 bytes). Procedure correctly delegated; rationale is the debatable share. |
| `traceability` | pass | Commit message documents the gap, four originating incidents, why not a hook, and what was deliberately deferred; mirrored at `CODING_MEMORY.md:434-440`. |
| `success_masking` | pass | Green 74-test suite disclosed *and explicitly refused* as evidence — correct handling of the exact anti-pattern. No loops or cost exposure. |
| `intent_drift` | pass | One line, one file; no drive-by edits, no dependency changes; the stronger verification-marker gate consciously deferred, not bundled. |
| `checkpoint` | pass | Single atomic, trivially revertable commit; original authorship/date preserved; pushed and in sync with its remote. |
| `audit_trail` | concern | `CODING_MEMORY.md:434` pins the pre-rebase SHA; no ADR where predecessor `67dd138` shipped ADR 0019; live decisions summary contradicts the record on whether triage ran. |

## Concerns

- `CODING_MEMORY.md:434` pins pre-rebase `1721a3c` off `2b8564b`; stale after rebase to `31840d8`
- No ADR, though comparable predecessor `67dd138` shipped ADR 0019 for the same species of change
- +105 words (+17%) to always-on `core-conduct.md`; rationale sentences are the debatable share
- Stated test command unrunnable in this worktree (`memsearch/.venv` absent); no coverage for rule prose
- Decisions summary item 6 contradicts commit message and `CODING_MEMORY.md`: triage WAS run and recorded
- Local `main` is 49 commits behind `origin/main`; `git diff main..HEAD` shows a misleading 552KB diff
