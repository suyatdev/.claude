# Marker-gate defect checklist

Working checklist for the open defects in `docs/features/verification-marker-gate.md`.
**Re-verified against `revision: 5` (`00583c2`) on 2026-08-07** — the original register was written
against revision 4 and had gone stale in both directions.

> **Where this should end up:** these items belong in the feature file's own checklist. This file is
> a working list for branch-per-defect work; fold it in and delete this file when the work lands, so
> there is only ever one document describing the state of this feature.

**Status key:** ✅ done · ⬜ open · ❓ probably done, *verify before spending a branch* · 🚫 waived

**How to work it:** `git checkout main && git pull` → say `start <ID>` → answer the model question →
say the literal `gate confirmed` → I branch, fix, show the diff → obs judge → PR → **you merge in the
GitHub UI** → repeat. Never split the pairs marked ONE BRANCH.

---

## ✅ Done — no action

- [x] **L1 · `git-guard` chained-command fail-open.** Fixed since. `hooks/git-guard.sh:24-26` now
      documents the exact `git add … && git commit …` bug and judges flags within command segments;
      `hooks/doc-guard.sh:119` references a lexer that absorbs the `rtk git …` form. Nothing to do.
- [ ] 🚫 **S5 · `command-grammar` rule 2.** **Waived** — `waived: [writing-specs/command-grammar]` in
      the spec frontmatter. Do not re-open; a judge citing it is arguing with a decision.

---

## ⬜ Open — verified still present in revision 5

- [ ] **D1+D2 · `feature/marker-gate-recognition-rule` — ONE BRANCH, DO NOT SPLIT.** The big one.
      - **D1 (fatal):** the spec still mentions `rtk` and `WRAPPERS` **zero times** and still never
        defines the `kind: COMMIT` predicate. `rtk` is the first Bash hook and rewrites
        `git commit …` → `rtk git commit …`, so the gate would be **dead on arrival**, with task 14's
        arming check going green over it. Note the *hooks* learned this and the *spec* did not.
        Reuse `hooks/lib/classify-pr-command.py:39`
        `WRAPPERS = ("rtk","time","eval","command","builtin","exec","nohup")`.
      - **D2:** no fail-closed recognition rule exists yet (searched: "fail-closed rule",
        "refuse everything", "unrecognis" → 0 hits). Enumerating git's grammar cannot be completed —
        git accepts **any unique prefix** (`--amen` = `--amend`). Replace with one rule: recognise a
        few **fully-spelled** forms, refuse everything else with `MSG_UNSUPPORTED_FORM`.
      - Also closes **D3** — `-p`/`--patch` and `--interactive` stage content *after* the hook runs,
        which parsing can never fix; they must be refused.
- [ ] **N1 · `docs/marker-gate-narration-fixes`.** The spec still claims `git diff --cached
      --name-only` outside a repo exits **128**; **re-measured: 129**. "129" appears nowhere in the
      file. ⚠️ Careful: several *other* 128s in the document are correct
      (`rev-parse --show-toplevel`, root-commit amend) — fix only the `git diff --cached` one.
- [ ] **N2 · same branch as N1.** `G10` is still cited once, and the grammar table stops at **G9**.
      Either add the row or drop the citation.
- [ ] **O1 · `docs/marker-gate-revert-pair-7-13`.** Revert pair **7↔13** still unnamed (0 hits). A
      registered-yet-missing hook blocks **every Bash call** — worse blast radius than the 5↔8 pair
      already warned about.
- [ ] **D5 · `feature/marker-gate-audit-logging`.** Blocks are still never logged (0 hits) — no way
      to learn whether the gate fires monthly, hourly, or never.
- [ ] **D4 · same branch as D5.** `test-exempt.log` is referenced, but the defect stands: it is
      gitignored + `0700` + machine-local, so the auditability that section argues for is not
      delivered. Confirm the storage decision, not just the mention.
- [ ] **O3 · `docs/marker-gate-shrink` — DO LAST.** **Now 1166 lines**, up from 1023 at revision 4,
      against the repo's <400 standard. Move measurement narrative and round rationale to an ADR;
      keep contracts, grammar outcome, scenarios, doors, checklist. Prose consistency at this size is
      what five rounds have actually failed on — not the design.

---

## ❓ Probably closed by revision 5 — read before spending a branch

Round 5 was titled *"make the marker-gate contracts total"*, and a text search suggests these were
addressed. **Grep is not proof** — open the section and confirm before opening a branch; if it is
genuinely closed, tick it here and move on.

- [ ] **S1+S2 · classifier contract** (id `api-contracts`, cited rounds 1-4). Search shows `form`
      now carries values covering `OTHER`/`NOTHING_RUNNABLE`, and `exit 3` appears three times.
      Confirm both halves: the enum is total, **and** the doors table no longer routes exit 3 to
      `MSG_CLASSIFIER_FAILED`.
- [ ] **S3 · `ALL` row, untracked on-disk member** (id `commit-form-coverage`). "untracked member"
      now appears twice. Confirm the content source is defined, not merely mentioned.
- [ ] **S4 · Python call site** (id `writer-call-site-cwd`). `cd "$MARKER_ROOT"` appears twice, but
      that may be only the **shell** form from revision 4. Confirm specifically that (a) the *Python*
      call site no longer resolves `rev-parse` at the bottom of the suite, and (b) checklist task 8
      no longer carries the superseded "capture `$0` at the top" wording.

---

## ⛔ Not defects — never "fix" these

Accepted ceilings. Fixing them means widening the feature, which was ruled out:

- The marker is a **receipt, not a grade** — a hash proves a test *changed*, never that it got
  *weaker*. Gutted or skipped tests still earn a valid marker.
- Non-Bash writes (`sed -i`, Edit/Write, an outside editor) are invisible to it.
- `panes/adapters/cmux.sh` is gated by nothing, because its suite is named `cmux-exec.test.sh` and
  strict 1:1 cannot see the relationship.
- The gate cannot arm during its own development.

---

## Standing decisions

- **Exit criterion:** if a judge round fails again with ids recurring, **stop specifying and build** —
  remaining items become test cases, not more prose.
- **No waivers besides `command-grammar`.** Nothing else has ever been waived on this spec.
- ⚠️ A judge `wait` returning exit 2 is **not** a failure — check `ps aux | grep '[c]laude -p'` and
  `coding-memory/*/verdicts.jsonl` before re-dispatching. Compliance needs >540 s on this spec.
- **Verify before trusting this file.** It has already been stale once. Anything marked ❓ or ⬜ is a
  claim about revision 5 — re-check it if more rounds have landed since 2026-08-07.
