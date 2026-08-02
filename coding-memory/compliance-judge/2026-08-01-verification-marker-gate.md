# Compliance judge — verification-marker-gate

Spec: `docs/features/verification-marker-gate.md` · repo `.claude` · branch `main`

---

## Round 1 — 2026-08-02T00:55:02Z · **FAIL** (4 violations) · confidence: high

HEAD `1859c307aabcf4e134a5d6e6ce19c078ea91424f` · spec blob `560b74badc17214d1bf355c804352184022e53d7`

### Layman summary

This is a strong spec. It has a real *why*, a rendered Mermaid flow, a JSON schema for the marker,
a decision table for which content gets hashed, named message constants per block door, a honestly
scoped fail-closed contract that lists what it *doesn't* catch, and Gherkin covering correct, wrong,
and edge behaviour. The three runtime versions it pins (bash 3.2.57, Python 3.9.6, git 2.50.1) were
re-checked on this machine and are all exactly right.

Three things block it, and all three are the same species of problem: the spec describes the world
accurately in prose but never counted it.

1. **The inventory is wrong.** The spec says the gate covers "9 shell pairs and 1 Python pair" and
   the checklist tells the implementer to wire the marker call into "all 10 existing suites." The
   repo actually has **10 shell pairs + 1 Python pair = 11**, across **13** test-suite files. An
   implementer who treats "10" as the done condition stops one suite early — and a subject whose
   suite never writes a marker is a subject that can never be committed again.
2. **Two test files have no sibling at all, and the design has no answer for them.**
   `panes/adapters.test.sh` tests the whole `panes/adapters/` directory, and
   `panes/adapters/cmux-exec.test.sh` tests `cmux.sh`. Neither `panes/adapters.sh` nor
   `panes/adapters/cmux-exec.sh` exists. The writer "derives the subject from the test path by the
   sibling rule," so on those two it derives a file that isn't there — and the spec's own rule that
   "a failed marker write **fails the suite**" turns wiring them up into two permanently red suites.
   The Scope section is explicitly headed "stated so nobody later assumes coverage," and this case
   is missing from it; no scenario covers it either.
3. **One of the two Python helpers has no wire contract.** The spec nails the payload parser's
   protocol to the line ("prints `OK` on line 1, command on line 2") but gives
   `classify-commit-command.py` only a Python-level `(kind, exempt)` tuple — no stdin/stdout
   framing, no type or constraint on `exempt`. That field is free text lifted out of a
   user-controlled command string and then printed. The existing `classify-pr-command.py` has to do
   `val.replace("\n", " ")` at line 96 precisely because one newline in that reason desynchronises
   the two-line protocol. The spec inherits the protocol by implication and the defence not at all.

Plus one narrow one: `shellcheck` is a gating tool in checklist task 10 (0.11.0 is what's
installed, and check sets differ across versions) but it's absent from the Pinned versions section.

**On the spec-location deviation:** judged and **accepted, not a violation.** `writing-specs` defers
to `docs/superpowers/specs/`; `rules/gates.md` one-canonical-file discipline puts feature-scale work
in `docs/features/<name>.md`. The spec names the conflict, names the winner, gives the reason, and
asserts "there is no second spec location" — which satisfies the actual hazard the `writing-specs`
rule guards (fragmentation into two indexed locations). Two sibling feature files already follow the
same convention. Adequate reconciliation.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/verified-scope-inventory` | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: break the feature into concrete requirements the agent can satisfy **and you can check**" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Session Defaults "Verify your own … outputs before calling something done" | "Scope" (§In, l.55–57) and Checklist task 8 (l.288) | The stated inventory — "9 shell pairs and 1 Python pair", "all 10 existing suites" — does not match the repo (10 shell pairs + 1 Python pair = 11, across 13 suite files), so the implementer's completion criterion is wrong by construction. |
| 2 | `writing-specs/edge-cases` | `~/.claude/skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios: … enumerate the edges. Anything you leave implicit, the agent infers" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Code Style "Handle errors explicitly, never swallow them" | "Architecture §1" writer contract (l.78–91), "Scope" §Out (l.59–66), "Edges" (l.207–243) | `panes/adapters.test.sh` and `panes/adapters/cmux-exec.test.sh` have no sibling subject, so sibling derivation resolves to a non-existent file, and the ratified "a failed marker write fails the suite" rule breaks both suites with no specified error path and no scenario. |
| 3 | `writing-specs/api-contracts` | `~/.claude/skills/writing-specs/SKILL.md` | "Database schemas and API contracts: these give the agent the real … interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Code Style "Validate all input at system boundaries" | "Architecture §3" (l.121–122, 128–129) and "Edges" exemption scenario (l.228–232) | `classify-commit-command.py`'s stdin/stdout framing is unspecified — unlike the payload parser's, which is pinned to the line — and `exempt` has no stated type or constraint even though it is free text parsed from a user-controlled command string onto a line-oriented protocol. |
| 4 | `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` | "Pin the exact version of every library and tool" (§Pin Exact Versions); `~/.claude/rules/core-conduct.md` §Existing and New Work "Pin exact library/tool versions" | "Pinned versions" (l.261–265) vs. Checklist task 10 (l.291–292) | `shellcheck` is a gating tool whose findings vary by release (0.11.0 installed here), but it is named only in the checklist and omitted from the section that pins bash, Python, and git. |

### Notes (non-blocking)

- **Version claims re-measured, all correct.** `bash 3.2.57(1)-release (arm64-apple-darwin25)`,
  `Python 3.9.6`, `git 2.50.1 (Apple Git-155)` — verbatim matches. The `.gitignore:17` citation for
  `/hooks/state/` also checks out exactly.
- **Exemption log destination unspecified.** "exits 0 and logs the reason" (l.231) never says
  where; `judge-guard.sh:230` writes to stderr. The suite has to assert against something concrete.
- **Store file permissions unspecified.** core-conduct's "default-deny every generated data store"
  is satisfied *semantically* — read-side validation blocks on anything not exactly well-formed —
  but the spec states gitignore (not access control) and atomic replace without naming a mode. Worth
  a line given the store is the sole authority for letting a commit through.
- **Blob regex is deliberately loose.** `^[0-9a-f]{40,64}$` accepts lengths that are never valid
  hashes; harmless because the value is then equality-compared against real `git hash-object` output
  and fails closed, but `^([0-9a-f]{40}|[0-9a-f]{64})$` costs nothing.
- **Deferred helper timeout is disclosed, not hidden.** A hanging helper would stall every Bash call
  in the session; the spec names this in the fail-closed contract as accepted-open, which is the
  right handling for a human-owned trade-off even though it was not in the ratified-decisions list.
- **Strong, and worth preserving through revision:** the four reused fail-open defences
  (sentinel-guarded parse, output-validated classifier, `python3 -I`, command-decides-not-tool_name),
  the per-door message constants with a mutation check, the `git commit -a` index-vs-worktree table,
  the "`written_at` MUST NOT influence any decision" rule, and the bootstrap note. None of these were
  inferable; all were written down.
- **Gate discipline respected.** Frontmatter is `phase: planning`, `branch: none`; the checklist
  alternates Red then Green per component and isolates the 10-suite wiring into its own commit,
  satisfying core-conduct §Testing "never edit tests and implementation in the same step". Task 14
  routes to the observability judge before the PR.

### Waivers

None. No violation ids were waived for this round.

---

## Round 2 — 2026-08-02T03:32:39Z · **FAIL** (4 violations) · confidence: high

HEAD `7d8b1aae8301a8d092fb17d1c0837862f191194e` · spec blob `76fae97857f713dc391d85390e61a4d2f7fa1dc1`

### Layman summary

The revision did real work and three of round 1's four findings are genuinely closed. Re-measured on
this machine: the pair inventory is now **exactly right** — `git ls-files '*.test.sh' '*.test.py'`
returns 13 suites, sibling derivation yields **11 pairs and 2 orphans**, and all 11 rows of the new
table match file-for-file. The orphan suites now have defined behaviour in three places (writer
skips, gate never pairs, a scenario). `shellcheck 0.11.0` is pinned and is what `/opt/homebrew/bin`
actually has. Every git-semantics claim in the new form table was reproduced in throwaway repos on
git 2.50.1 and **every one of them holds**: pathspec commits ship worktree content (`v3`, not the
staged `v2`), a pathspec narrows the commit to `bar.md` alone, `git diff --cached` returns zero paths
for a `-a` commit that does contain the file, `--amend`'s base really is `HEAD^`, `HEAD^` on a root
commit exits 128, the empty-tree oid is correct, `--diff-filter=d` keeps the new half of a rename,
and `-a` plus a pathspec exits 128 without committing. That is a much stronger document than round 1.

Four things still block it, and two of them are the round-1 ids returning in the same territory.

1. **The inventory is right about yesterday's repo and wrong about tomorrow's.** The count was
   corrected, but this feature *itself* adds three more conforming pairs — `test-marker-guard.sh`,
   `classify-commit-command.py`, `write-test-marker.py`, each with a `.test.` sibling. Task 8 names
   the 11-row table as "the completion criterion", so an implementer wires 11 suites and leaves the
   gate's own three subjects with no marker writer — once armed, those three files can never be
   committed again. Worse, the new frozen-inventory assertion ("exactly 11 pairs, exactly 2 named
   orphans") is false at the moment it is written: at task 4 the repo has 12 pairs and 3 orphans, and
   after task 7 it has 14 pairs. That test fails → the suite fails → per the spec's own rule no marker
   is written → `write-test-marker.py` becomes uncommittable. The control added to prevent an
   uncheckable claim is itself uncheckable as specified.
2. **The `exempt` contract now says two incompatible things.** The field table says the classifier
   strips control characters and the hook re-validates against `^[^\x00-\x1f\x7f]{0,200}$`. The edge
   scenario says a `TEST_EXEMPT` containing a newline must produce exit 2 / `MSG_CLASSIFIER_BAD_OUTPUT`.
   With a correct classifier the newline is gone before the hook ever sees it, so the hook must allow.
   An implementer writing the red test for that scenario has to break the classifier to make it pass.
3. **The form table is treated as total over lexable shapes, and it isn't.** Measured: with `a.sh`
   staged and `b.md` modified, `git commit -i -- b.md` commits **both** — `a.sh` at its staged content.
   `-i`/`--include` maps to none of `PLAIN|PATHSPEC|ALL|INVALID|FOREIGN`; classified as `PATHSPEC` its
   collector returns `b.md` only and the staged pair sails through unchecked. It is lexable, so the
   "shapes the classifier cannot lex" escape clause does not cover it. Separately, the table gives
   content rules for paths *in* the path set, while the pairing rule requires hashing **both** members
   — the post-commit content of a member outside the pathspec is left undefined, and the obvious
   reading (apply the row's content source) hashes an uncommitted worktree edit and false-blocks a
   commit that ships exactly what was tested. Under this repo's mandated `git commit -- <path>` style
   that is the common path, not a corner.
4. **The gate's repo boundary is never stated.** Task 12 registers it in `~/.claude/settings.json`,
   which is where every other PreToolUse guard lives — verified: `git-guard`, `doc-guard`,
   `judge-guard`, `merge-guard` all sit there and fire in *every* repo. Nothing in the spec says
   whether this gate is `.claude`-only or global. The `.gitignore:17` cover for `/hooks/state/` (real,
   verified) exists only here, and any other repo using the same sibling-test convention would block
   every commit forever with no writer present. Both readings are implementable; the spec picks
   neither.

**Not re-opened:** the `docs/features/` spec-location deviation stays accepted, as ruled in round 1.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/verified-scope-inventory` *(recurring)* | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: … concrete requirements the agent can satisfy **and you can check**" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Session Defaults "Verify your own … outputs before calling something done" | §Scope table (l.61–78), §Architecture 1 frozen-inventory (l.131–136), §Testing requirements (l.525), Checklist task 8 (l.544–548) | The count is now correct for the pre-feature repo but wrong as a completion criterion — the feature adds 3 conforming pairs of its own, so wiring only the 11 tabled suites leaves the gate's own subjects uncommittable once armed, and the "exactly 11 pairs / 2 orphans" assertion is already false at task 4 (12 pairs, 3 orphans) and at task 7 (14 pairs). |
| 2 | `writing-specs/api-contracts` *(recurring)* | `~/.claude/skills/writing-specs/SKILL.md` | "API contracts: these give the agent the real … interface boundaries to build against" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Code Style "Validate all input at system boundaries" | §Architecture 3 field table + read-side validation (l.214–218) vs. §Edges "an exemption reason carrying control characters is rejected" (l.405–409) | The contract says the classifier strips control characters and the hook re-validates, while the scenario demands exit 2 for a newline-bearing `TEST_EXEMPT`; a correct classifier delivers a stripped value the hook must accept, so the two requirements cannot both be satisfied. |
| 3 | `writing-specs/commit-form-coverage` | `~/.claude/skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios: … enumerate the edges. Anything you leave implicit, the agent infers" (§What a Spec Must Contain) | §"Which paths, and which content" form table (l.239–245), §Pairing rule (l.274–278), §Fail-closed contract accepted-open list (l.471–474) | `git commit -i -- <paths>` is lexable but unmapped and fails open (measured on git 2.50.1: it commits staged paths outside the pathspec, which the `PATHSPEC` collector never returns), and the table defines content only for paths inside the path set while the pairing rule hashes both members, leaving a pair member outside the pathspec with no defined post-commit content. |
| 4 | `writing-specs/scope-boundary` | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: … concrete requirements the agent can satisfy and you can check" and "enumerate the edges" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Zero-Trust Invariants "validate the target against what the user supplied … default-deny every generated data store" | §Scope (l.61–101), §Architecture 2 store (l.155–165), Checklist task 12 (l.554) | The hook is registered in the global `~/.claude/settings.json` where every other PreToolUse guard runs against every repo, yet the spec never states its behaviour outside this repo — the `.gitignore:17` cover for `/hooks/state/` does not travel, and a foreign repo using the same sibling-test convention would block every commit with no marker writer present. |

### Notes (non-blocking)

- **Everything re-measured that the revision claims, checks out** except one number: 11 pairs / 2
  orphans / 13 suites exact; `bash 3.2.57(1)-release`, `Python 3.9.6`, `git 2.50.1 (Apple Git-155)`,
  `shellcheck 0.11.0` at `/opt/homebrew/bin/shellcheck`; `.gitignore:17` is literally `/hooks/state/`;
  `git ls-files --full-name` from `panes/` returns `panes/adapters/cmux-layout.test.sh` and
  `--error-unmatch` exits 1 on an untracked path; empty-tree oid `4b825dc6…` correct; root-commit
  `git rev-parse HEAD^` exits 128.
- **The one wrong number is harmless.** "outside a repo, `git diff --cached --name-only` … exits 128"
  — measured **129** (git falls into `--no-index` mode and rejects `--cached`); stdout is empty as
  claimed. The governing rule ("a non-zero exit from *any* … command → block") covers it, but a test
  asserting `128` literally would be red on arrival.
- **Percent-encoding order is unstated.** "(`/`→`%2F`, `%`→`%25`)" applied in the written order
  double-encodes a subject path containing a literal `%`. Rare, cheap to pin ("encode `%` first").
- **`git commit -C <commit>` vs `git -C <path>`.** The `FOREIGN` trigger list names "a `git -C`";
  measured, `git commit -C HEAD` is a legal message-reuse flag. Position-sensitive lexing is implied
  but not stated, and a loose match false-blocks.
- **`FOREIGN` also blocks same-repo `cd`.** `cd "$(git rev-parse --show-toplevel)" && git commit …`
  is a same-repo idiom that this rule blocks. Consistent with fail-closed and with a stated remedy —
  flagged only so the cost is a chosen one.
- **Preserved from round 1 and still strong:** the four reused fail-open defences, per-door message
  constants now enumerated at 11 with a one-mutant-per-door floor, the `written_at`-must-not-decide
  rule, `0700`/`0600` on the store, the tightened blob regex, the extension-derived remedy string,
  the revert-as-a-pair warning on tasks 7–8, and the honest accepted-open list. Frontmatter is still
  `phase: planning`, `branch: none`; the checklist still alternates Red→Green per component.

### Waivers

None. No violation ids were waived for this round.
