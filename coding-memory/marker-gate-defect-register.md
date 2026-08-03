# Marker-gate defect register — branch-per-defect

Durable home for the per-defect detail that previously lived only in the machine-local
`.claude/session-state.md`. The branch **order** and the do-not-split pairs are in
`CODING_MEMORY.md` §marker gate; the **why** for each unit is here. Created 2026-08-03 when the
handoff file had to shrink and this was the only copy.

Spec under repair: `docs/features/verification-marker-gate.md` (revision 4, `phase: planning`).
Four judge rounds failed on it; the user chose branch-per-defect over a fifth round because the
judges re-read the whole document every round and report everything regardless of what changed —
round 4 changed the grammar and its headline finding was `rtk`. A one-change round still returns
`fail` with unrelated findings attached, so the isolation is never actually delivered.

⚠️ **D1+D2 must not be split** (one cause — a single fail-closed recognition rule; two branches
would mean two rules and a fresh contradiction). ⚠️ **S1+S2 must not be split** (two halves of one
contract; fixing either alone leaves the document *more* self-contradictory than it is now).

**Exit criterion:** if a judge round still fails with ids recurring → stop specifying, build.

---

## D1+D2 · `feature/marker-gate-recognition-rule` · ONE BRANCH

**D1 (fatal).** The spec never defines the `kind: COMMIT` predicate, so it never strips wrappers.
**`rtk` is the FIRST Bash hook**, rewriting `git commit …` → `rtk git commit …` (ADR 0012), which
makes the gate **dead on arrival** — and task 14's arming check goes green over it.

**D2.** Enumerating git's option grammar cannot be completed: git accepts **any unambiguous prefix**
of a long option (`--amen` == `--amend`). Replace it with **ONE fail-closed rule** — recognise a few
**fully-spelled** forms, refuse everything else (`MSG_UNSUPPORTED_FORM`).

Closes **D3** as well: `-p`/`--patch` and `--interactive` stage content *after* the hook has run, so
no amount of parsing can see it; it must be refused.

> **Reuse `hooks/lib/shell_segments.py`** (landed with PR #35) — do not write a third lexer. It
> already handles unspaced `&&`, backslash-newline continuation, brace groups, env prefixes, and a
> `WRAPPERS` list containing `rtk`. Its accepted limits are in ADR 0012 + ADR 0013.

## S1+S2 · `fix/marker-gate-classifier-contract` · ONE BRANCH · id `api-contracts` (r1–r4)

**S1.** `form` is a closed enum validated **before** `kind`, with no value for the
`OTHER`/`NOTHING_RUNNABLE` outputs that every non-commit payload produces — so a conforming
classifier trips its own `MSG_CLASSIFIER_BAD_OUTPUT`.

**S2.** Doors row 5 routes *every* non-zero exit — including the newly added exit 3 — to
`MSG_CLASSIFIER_FAILED`.

## S3 · `fix/marker-gate-all-untracked-member` · id `commit-form-coverage` (r2–r4)

`ALL` defines outside-path-set content only "for a tracked path". An **untracked** on-disk member
has no answer: `git commit -am y` drops it from the tree while the worktree ABSENT probe reports it
present, so the gate hashes a blob the commit will not hold.

## S4 · `fix/marker-gate-python-call-site` · id `writer-call-site-cwd` (r3, r4)

The **Python** call site resolves `rev-parse` at the *bottom*, so a suite that chdirs into a
throwaway repo (pairs 12 and 13 must build one) hands the writer the wrong root and `check=True`
sees silent success. Checklist task 8 still carries round 3's **superseded** "capture `$0` at the
top" wording — no mention of an absolute `MARKER_SELF` plus `cd "$MARKER_ROOT"`.

## S5 · `fix/marker-gate-grammar-rule-2` · id `command-grammar` (new in r4)

Rule 2's unqualified "`--opt value` consumes the next token" contradicts the group naming
`--untracked-files`/`--gpg-sign` as **never** consuming one, so
`git commit -m msg --untracked-files foo.sh` re-opens the G2 fail-open. Largely superseded if D1+D2
lands first — sequence after it, or fold in.

## N1+N2 · `docs/marker-gate-narration-fixes` (my errors, cheap)

**N1.** The spec says `git diff --cached --name-only` outside a repo exits **128**; **re-measured:
129** (128 belongs to `rev-parse --show-toplevel`). Inherited from round 1, never re-measured.
**N2.** **`G10` does not exist** — the table stops at G9, yet a scenario cites it.

## O1 · `docs/marker-gate-revert-pair-7-13`

Revert pair **7↔13** is unnamed: a registered-yet-missing hook blocks **every Bash call**, a worse
blast radius than the 5↔8 pair the document already warns about.

## D4+D5 · `feature/marker-gate-audit-logging`

The exemption log is gitignored, `0700`, and machine-local, so the auditability that section argues
for is **not delivered**. Blocks are **never logged**, so there is no way to know whether the gate
has ever fired.

## O3 · `docs/marker-gate-shrink` — LAST

**1023 lines against the <400 standard.** Measurement narrative and round rationale move to an ADR;
keep the contracts, the grammar outcome, the scenarios, the doors, and the checklist. Prose
consistency at this size is what four rounds failed on — not the design.

---

## ⛔ Accepted ceilings — document, never "fix" (fixing = widening the feature, ruled out)

- **Receipt, not a grade** — it proves a test *changed*, never that it got *weaker*; gutted and
  skipped tests still earn one.
- Non-Bash writes are invisible to it.
- `panes/adapters/cmux.sh` is gated by nothing (its suite is named `cmux-exec.test.sh`).
- It cannot arm during its own development.
