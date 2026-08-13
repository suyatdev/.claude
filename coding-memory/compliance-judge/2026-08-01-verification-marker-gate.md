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

---

## Round 3 — 2026-08-02T05:58:22Z · **FAIL** (3 violations) · confidence: high

HEAD `6046565fbdc1d78ad264d2889af67745782a929e` · spec blob `9ecb12969b23c60edc8b7aeaddcfae8ae4f909f5`

### Layman summary

The whole-document re-derivation worked on three of the four things it targeted, and two of those
fixes are genuinely *class* fixes rather than patches.

**Closed, verified by re-measurement:**

- **`verified-scope-inventory` — closed, and closed correctly.** Re-measured today:
  `git ls-files '*.test.sh' '*.test.py'` returns **13** suites, sibling derivation yields **11 pairs
  and 2 orphans**, and all 11 rows of §Scope's table match file-for-file. The diagnosis is right —
  a frozen count is a control this feature's own three new pairs invalidate. Assertion 1 enumerates
  from `git ls-files` at run time and filters to tracked subjects, so pairs 12–14 *extend* it instead
  of contradicting it; it has a real trigger (a new paired suite that isn't wired turns the writer's
  suite red); and declining to assert orphan-set equality is correctly justified — checklist task 2
  really does commit `classify-commit-command.test.py` before its subject exists, so an equality
  assertion would make the red steps unlandable. Assertion 2 is a deliberate tripwire on the
  `cmux.sh` hole with the remedy written down. This is not a hole.
- **`api-contracts`, the `exempt` instance — closed.** The field table (raw, unsanitised,
  JSON-escaped), the hook's `^[^\x00-\x1f\x7f]{1,200}$` re-validation, door 7 `MSG_BAD_EXEMPT`, the
  fail-closed list, and all four `TEST_EXEMPT` scenarios (control characters, over-length, empty,
  honoured-and-logged) now say the same thing. The reconciliation that failed twice succeeded here.
- **`scope-boundary` — closed.** Verified: `git-guard`, `doc-guard`, `judge-guard`, `merge-guard` are
  all registered in `~/.claude/settings.json` under `PreToolUse`/matcher `Bash`, so "exactly like its
  four sibling guards" is literally true; `"model": "opus[1m]"` is present as task 13 assumes. The
  inert-unless-`hooks/lib/write-test-marker.py`-exists rule is recorded in five mutually consistent
  places (§Scope prose, flowchart node G, a correct-behaviour scenario, the accepted-open list,
  checklist tasks 12 and 14) plus the ADR. Soundly recorded.

Three things still block, and two of them are prior ids returning in the same territory — a *third*
recurrence for `api-contracts`. Both recurrences are the same signature as before: a stated component
behaviour that one of the spec's own scenarios cannot pass against.

1. **The cheap pre-filter makes a door unreachable.** §Latency says "a cheap bash pre-filter runs
   before any `python3`: if the command string cannot contain a git commit (no `git` substring, or no
   `commit` substring), the hook exits 0 immediately", with a ≤5 ms budget explicitly "pure bash, no
   subprocess". But the wire contract makes the single Python helper the *sole* payload parser —
   `kind: NOTHING_RUNNABLE` and `MSG_BAD_PAYLOAD` both come from it. A Bash payload whose command is
   absent or empty contains neither substring, so the pre-filter exits 0 and door 2
   `MSG_NOTHING_RUNNABLE` never fires; the Edge scenario "a Bash payload with nothing runnable blocks"
   cannot pass, and its mutant in the 22-mutant floor is unkillable. The flowchart says the opposite
   — it puts "Runnable command?" *before* the pre-filter — which is only implementable if `python3`
   runs on every Bash call, voiding the latency budget the pre-filter exists to protect. The spec's
   own justification sentence contains the bug: "this only skips commands that could not have been
   classified as `COMMIT` anyway" reasons about COMMIT-vs-not and forgets that `NOTHING_RUNNABLE` is
   a *blocking* non-COMMIT.
2. **ABSENT is defined against the wrong instrument for two of the three collecting forms.** The new
   second table is a real improvement and its uniform rule ("the blob the resulting commit's tree
   will hold") is right. But the operational probe is stated once, against `<base>` only, and the
   content source differs per form. Measured on git 2.50.1 today: with `foo.sh` modified+staged and
   `foo.test.sh` staged as a **deletion**, the path set is `foo.sh` alone, `git cat-file -e
   HEAD:foo.test.sh` **exits 0** (so, not ABSENT), and the resulting tree contains `foo.sh` only —
   the marker's test blob equals the base blob and the gate **allows**, while §Edges "half a pair is
   deleted while the other half changes" demands `MSG_STALE_TEST` and annotates it "the test resolves
   to ABSENT". Under `-a` with the test deleted in the worktree, the row says "worktree blob for a
   tracked path" and `git hash-object -- foo.test.sh` **exits 128** — routing a defined outcome to
   `MSG_GIT_FAILED`, the door the ABSENT paragraph was written to keep it out of. No scenario covers
   the `-a` case at all.
3. **The call-site fix rescues the values but not the writer's cwd.** §Architecture 1 correctly
   identifies that `$0` and `rev-parse` depend on the suite's cwd and mandates capturing both at the
   top. But the writer is then executed as a subprocess *from wherever the suite currently is*, and
   its own mandated resolution steps are cwd-dependent. Measured: from a throwaway repo of exactly
   `hooks/judge-guard.test.sh:13`'s shape (`cd "$TMP"`, `git init`, never cds back — confirmed, it
   never returns), `git ls-files --full-name --error-unmatch -- hooks/judge-guard.test.sh` **exits 1**
   and `git rev-parse --show-toplevel` resolves the **throwaway** repo, so the store path would land
   inside `$TMP` and be deleted by the suite's own trap. With the mandated `|| exit 1` and "a failed
   marker write **fails the suite**", wiring that suite at task 8 turns it permanently red — the
   precise failure the section was written to prevent — and §Edges "a suite that cds still writes a
   findable marker" cannot pass as specified. The Python call-site snippet compounds it: it runs
   `rev-parse` at the *bottom*, the thing the shell prose forbids.

**Not re-opened:** the `docs/features/` spec-location deviation stays accepted, as ruled in round 1.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/api-contracts` *(recurring, 3rd round)* | `~/.claude/skills/writing-specs/SKILL.md` | "API contracts: these give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match" (§What a Spec Must Contain); "Ambiguity surfaces early" (§Write Scenarios in BDD/Gherkin Form) | §Architecture 3 wire contract (l.288–295) and flowchart nodes B–D (l.15–21) vs. §Latency pre-filter (l.444–447), door 2 `MSG_NOTHING_RUNNABLE` (l.717) and §Edges "a Bash payload with nothing runnable blocks" (l.665–668) | The single helper is the sole payload parser, so the pre-filter that "runs before any `python3`" cannot know whether a command exists — an absent/empty Bash command contains neither substring and exits 0, making door 2, its scenario and its mutant unreachable, while the flowchart's opposite ordering is implementable only by spawning `python3` on every Bash call, voiding the ≤5 ms "pure bash, no subprocess" budget. |
| 2 | `writing-specs/commit-form-coverage` *(recurring)* | `~/.claude/skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios: … enumerate the edges. Anything you leave implicit, the agent infers — and inference is where the defects come from" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Code Style "Handle errors explicitly, never swallow them" | §"Which paths, and which content" second table (l.353–360) and the ABSENT paragraph (l.368–371) vs. §Edges "half a pair is deleted while the other half changes" (l.630–635) | ABSENT is defined solely as absence from `<base>` via `git cat-file -e`, but the post-commit content source is the index under `PLAIN` and the worktree under `ALL` — measured on git 2.50.1: a test half staged for deletion passes the base probe (exit 0) and the gate allows a commit whose tree drops it, contradicting the spec's own scenario, and `-a` with the test deleted in the worktree makes `git hash-object` exit 128 into `MSG_GIT_FAILED` instead of the stale door, with no scenario covering it. |
| 3 | `writing-specs/writer-call-site-cwd` *(new)* | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: break the feature into concrete requirements the agent can satisfy **and you can check**" and "enumerate the edges" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Session Defaults "Verify your own … outputs before calling something done" | §Architecture 1 "Call site — one line per suite" (l.211–238) and §Edges "a suite that cds still writes a findable marker" (l.682–686) | Capturing `$0` and the toplevel before the `cd` fixes the values but not the writer *process's* cwd, on which both of its mandated resolution steps depend — measured from `judge-guard.test.sh`'s post-`cd "$TMP"` shape, `git ls-files --full-name --error-unmatch` exits 1 and `rev-parse --show-toplevel` returns the throwaway repo, so the mandated `\|\| exit 1` turns one of the 14 suites task 8 must wire permanently red. |

### Notes (non-blocking)

- **Every measurable claim re-checked today holds.** 13 suites / 11 pairs / 2 orphans exact, and
  §Scope's 11 table rows match file-for-file; `bash 3.2.57(1)-release`, `Python 3.9.6`,
  `git 2.50.1 (Apple Git-155)`, `shellcheck 0.11.0`; `.gitignore:17` is literally `/hooks/state/`;
  `hooks/context-handoff-watch.sh:45` really is the `.cwd` consumer; `hooks/judge-guard.test.sh:13`
  really is `cd "$TMP" || exit 1`; the four sibling guards really are global `PreToolUse`/`Bash`;
  `"model": "opus[1m]"` is really in `settings.json`. Door count arithmetic (12 + 2 = 14) and the
  mutation floor (14 doors + 7 allow paths + 1 = 22) both check out, and the seven allow paths are
  enumerated.
- **`form`/`amend`/`paths` have no defined value when `kind != COMMIT`,** while the hook's read-side
  validation demands "every field present and inside its domain" and `form`'s domain has no
  not-applicable member. The scenarios pin the required outcomes, so TDD will force an in-domain
  filler, but the choice is currently the implementer's.
- **Assertion 1's match string is unspecified** — "contains the call line" is one thing for the shell
  form and another for the Python form; `write-test-marker.py` as the substring is the obvious
  derivation but is not written down.
- **Multi-word `TEST_EXEMPT` scenarios are not valid shell.** `TEST_EXEMPT=vendored upstream git
  commit -m msg` assigns `vendored` and runs `upstream`. Both scenarios still land on exit 0 under
  either parse, but quote handling in "the **raw** value" is unstated, which matters for the log line
  and for the 200-character boundary.
- **The fail-closed "These block" list omits a *missing* marker** (door 11 `MSG_NO_MARKER`); it names
  "an unreadable or malformed marker". Covered by the doors table and scenarios — cosmetic.
- **An adopting non-`.claude` repo needs its own `/hooks/state/` ignore rule.** The spec notes the
  cover "does not travel" but does not say what such a repo must do; harmless in v1, where only this
  repo installs the writer.
- **Retrospective narration is now a sizable share of the document** (~a dozen "Round 1 did X / Round
  2 froze Y" passages across 814 lines). Each carries genuine why-not-the-obvious-alternative value,
  so this is not a `writing-specs` §Tokenization violation — but once the spec settles it is the
  first thing to trim, since an implementer who never saw those rounds pays for them in attention.
- **`/opt/homebrew/bin/shellcheck` is an absolute path in a committed file**, which core-conduct
  §Zero-Trust names. Judged **not** a violation: it is measurement provenance for a pinned version,
  not a runtime path, and the design elsewhere is scrupulous about resolving from
  `--show-toplevel` rather than `$HOME`.
- **Still strong and worth preserving through revision 4:** the four reused fail-open defences, the
  per-door message constants with a floor that now covers allow paths as well as doors, the
  `written_at`-must-not-decide rule, `0700`/`0600` on the store, the extension-derived remedy string,
  the revert-tasks-7-and-8-as-a-pair warning, the honest accepted-open list, the bootstrap note, and
  the first-arming check at task 14. Frontmatter is still `phase: planning`, `branch: none`,
  `revision: 3`; the checklist still alternates Red→Green and keeps the wiring commit test-only.

### Waivers

None. No violation ids were waived in any round; the round-2 escalation was resolved by a directed
re-derivation, not by a waiver.

---

## Round 4 — 2026-08-02T06:31:13Z · **FAIL** (4 violations) · confidence: high

HEAD `8923951bcded352c0889e8e9f386f72efe8a57f3` · spec blob `c6b8737fd846898344e2eff75a5eaff4d576dbd7`
· `revision: 4`

### Layman summary

The narrow round did its narrow job: the grammar section is the strongest new text in the document,
and its nine measurements were spot-checked live today rather than taken on faith. Re-measured on
git 2.50.1: a bare operand ships the **worktree** blob (G2 confirmed — index held `w1`, the commit
shipped `w2`), and `git ls-files --full-name --error-unmatch -- <absolute path>` resolves correctly
from the repo root, so the absolute-`MARKER_SELF` half of the round-4 call-site fix genuinely works.
Every derivation in the two content tables follows from its G-row: `PLAIN`→index is what G3/G5 show,
`PATHSPEC`/`ALL`→worktree is what G1/G2/G4/G6/G7 show, and routing G8/G9 to `INVALID`→allow is right
because git commits nothing there.

Three of the round's four targets nevertheless still have a seam, and the fourth — the grammar — has
a fresh defect of exactly the kind the user predicted.

1. **`api-contracts`, fourth round running, and it is now in the field table itself.** The `form`
   field is a closed enum, and the hook validates *every field against its domain* (l.357) at
   flowchart node `CO` — **before** node `E` ever asks whether `kind` is `COMMIT`. But `form` has no
   defined value for `kind: OTHER` or `kind: NOTHING_RUNNABLE`, which is what the classifier must
   emit for every non-commit payload that clears the pre-filter. There is no `NONE` in the domain;
   `INVALID` means something else entirely (`-a` plus an operand). An implementer emitting `""` or
   `null` for `ls` trips their own `MSG_CLASSIFIER_BAD_OUTPUT` and blocks the call; one emitting
   `PLAIN` is inventing a shape the contract does not license. Round 4 also changed two component
   behaviours without re-reconciling the doors table: row 5 still reads "the classifier exits
   non-zero **or** prints nothing", which swallows the brand-new, load-bearing exit 3 that row 1 and
   the Edge scenario at l.852 depend on being distinguishable, and row 8 still fires only for
   `-i`/`--include`, omitting the `--pathspec-from-file` the form table and rule 4 route there.
   Finally, moving the filter to the **raw payload** silently widened the class of calls that pay
   `python3`: any Bash payload whose text anywhere contains `commit` — a `description` field reading
   "commit the fix", a `git log --grep=commit` — now spawns the classifier, so the "≤5 ms for a
   non-commit Bash call (pure bash, no subprocess)" budget is false for a real third class, and task
   10 records only "the two numbers".

2. **`commit-form-coverage`, third round running, and one cell of the new matrix is still open — the
   spec flags it itself.** The outside-path-set table's `ALL` row reads "worktree blob **for a
   tracked path**", and stops. Measured today: with `new.test.sh` untracked and on disk,
   `git commit -am y` produces a tree of `bar.md` + `foo.sh` only — the untracked member is **not**
   in the commit. So its post-commit content is ABSENT, but the ABSENT probe the spec assigns to a
   worktree source is "the path does not exist on disk", which reports it **present**; the gate would
   hash a blob the resulting tree will never hold. That contradicts the section's own uniform rule,
   "the blob the resulting commit's tree will hold". The other five cells (PLAIN in/out, PATHSPEC
   in/out, ALL in) are now correct and fail-closed — including the two the round fixed — so this is
   the last hole, not a re-derivation.

3. **`writer-call-site-cwd` — the shell form is fixed; the Python form and the checklist are not.**
   The subshell `( cd "$MARKER_ROOT" && … )` with an absolute `MARKER_SELF` is the right fix and it
   holds for a suite that cds. But the Python snippet resolves `git rev-parse --show-toplevel`
   **in `__main__`, after the tally** — the exact "use at the bottom" the shell prose forbids six
   lines earlier. `os.path.abspath(__file__)` happens to be safe (verified: on the pinned Python
   3.9.6 `__file__` is already absolute even under a relative invocation), so only the root is wrong
   — and it is wrong silently: `subprocess.run(cwd=<throwaway repo>, check=True)` **succeeds**,
   writing the marker into a temp store the suite's teardown deletes, and the gate later blocks with
   `MSG_NO_MARKER`. Today's pair 6 (`classify-pr-command.test.py`) contains no `chdir`, so this is
   latent there — but pairs 12 and 13 are *this feature's own new suites*, and §Testing requirements
   demands `write-test-marker.test.py` exercise "`--full-name` normalisation **from a subdirectory**"
   and real `git hash-object` behaviour, which is throwaway-repo work. Checklist task 8 compounds it:
   it still says "capturing `$0` and the toplevel at the top of each" — round 3's two-value form —
   and never mentions the absolute `MARKER_SELF`, the `cd "$MARKER_ROOT"` subshell, or that three of
   the fourteen suites take the Python form. §1's warning "task 8 must not paste the call blindly"
   is undercut by task 8 prescribing the old paste.

4. **The grammar's long-option rule contradicts its own flag table, and it is a fail-open.**
   Rule 2 says, unqualified: "`--opt value` consumes the next token". The flag groups four lines
   later say `-u/--untracked-files` and `-S/--gpg-sign` "must **never** consume the next token, or
   they would eat a pathspec". Both cannot hold. Measured today on git 2.50.1:
   `git commit -m msg --untracked-files foo.sh` treats `foo.sh` as a **pathspec** and ships the
   **worktree** blob (`v3`), while the index held `v2` — so a classifier following rule 2 sees no
   operand, reports `PLAIN`, hashes the index, matches a stale marker, and allows a commit shipping
   content no suite ever saw. That is G2's fail-open reborn inside the section written to close it.
   Under the charitable reading (rule 2 scoped to known value-taking long options) the contradiction
   is unresolved rather than absent, since both flags are on that list by name. Separately, the
   section defines the grammar over "tokens" but never says how the command **string** becomes
   tokens, nor how `git <global-opts> commit` is separated from `git commit <opts>` (`-C` means
   `--reuse-message` after `commit` and a repo redirect before it — the `FOREIGN` rule depends on
   telling them apart), nor how a `git add -- <path> && git commit -- <path>` chain is segmented —
   a shape §Architecture calls a **live fail-open in three sibling hooks** and which is *not* on the
   accepted-open list, so it is neither handled nor accepted.

**Not re-opened:** the `docs/features/` location (ruled adequate in round 1); the scope inventory,
edge cases, pinned versions and scope boundary, all still closed and re-verified in passing.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/api-contracts` *(recurring, 4th round)* | `~/.claude/skills/writing-specs/SKILL.md` | "Database schemas and API contracts: these give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match" (§What a Spec Must Contain) | §Architecture 3 wire-contract field table (l.340–348) + hook read-side validation (l.357) vs. flowchart nodes `CO`/`E` (l.24–29); §Fail-closed contract → The doors, rows 5 and 8 (l.915, l.918); §Latency budgets (l.579–582) | `form` is a closed enum the hook validates before it ever consults `kind`, yet the contract defines no value for the `OTHER`/`NOTHING_RUNNABLE` outputs every non-commit payload produces, so a conforming classifier trips its own `MSG_CLASSIFIER_BAD_OUTPUT`; and the doors table was not re-reconciled with this round's two component changes — row 5 still routes *every* non-zero exit, including the new exit 3, to `MSG_CLASSIFIER_FAILED`, and row 8 omits `--pathspec-from-file`. |
| 2 | `writing-specs/commit-form-coverage` *(recurring, 3rd round)* | `~/.claude/skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios: state explicitly what correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit, the agent infers — and inference is where the defects come from" (§What a Spec Must Contain) | §"Which paths, and which content" → "Post-commit content of a pair member that is NOT in the path set", `ALL` row (l.457), read against the ABSENT table's worktree row (l.475) | The `ALL` row defines the outside-path-set content only "for a tracked path", leaving an untracked member that exists on disk with no defined answer — measured on git 2.50.1, `git commit -am y` excludes it from the tree, yet the worktree ABSENT probe ("the path does not exist on disk") reports it present and the gate hashes a blob the resulting commit will not hold, contradicting the section's own uniform rule. |
| 3 | `writing-specs/writer-call-site-cwd` *(recurring, 2nd round)* | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: break the feature into concrete requirements the agent can satisfy **and you can check**" (§What a Spec Must Contain); `~/.claude/rules/core-conduct.md` §Session Defaults, "Verify your own and subagents' outputs before calling something done" | §Architecture 1 → Call site, Python form (l.250–257) and the "capture at the top, use at the bottom" rule it violates (l.262–273); Checklist task 8 (l.987–994) | The Python call site resolves `git rev-parse --show-toplevel` at the bottom of the suite, so a Python suite that chdirs into a throwaway repo — which §Testing requirements obliges pairs 12 and 13 to build — hands the writer the wrong root and `check=True` sees a silent success, and checklist task 8 still prescribes round 3's superseded "capturing `$0` and the toplevel at the top of each" with no mention of the absolute `MARKER_SELF`, the `cd "$MARKER_ROOT"` subshell, or the Python form. |
| 4 | `writing-specs/command-grammar` *(new)* | `~/.claude/skills/writing-specs/SKILL.md` | "Ambiguity surfaces early: a requirement you cannot phrase as Given/When/Then is usually a requirement you have not actually decided yet" (§Write Scenarios in BDD/Gherkin Form); "API contracts … instead of letting it improvise shapes that other components then fail to match" (§What a Spec Must Contain) | §The command grammar → "The rules the classifier implements, in order", rule 2 (l.394) vs. the "optional value, attached only" group (l.408–409); same section, tokenisation/segmentation unstated (l.389–415) | Rule 2's unqualified "`--opt value` consumes the next token" directly contradicts the group that names `--untracked-files` and `--gpg-sign` as never consuming one — measured, `git commit -m msg --untracked-files foo.sh` ships the worktree blob because `foo.sh` is a pathspec, so a rule-2 classifier reports `PLAIN`, hashes the index and re-opens the exact G2 fail-open; and the section never states how the command string becomes tokens, how `git <global-opts> commit` is told from `git commit <opts>` (which `FOREIGN`'s `-C` test depends on), or how a `git add … && git commit …` chain is segmented, a shape the spec itself calls a live fail-open in three sibling hooks and does not place on the accepted-open list. |

### Notes (non-blocking)

- **Dangling `G10`.** The Correct-behaviour scenario at l.648 cites "measured G10", but the grammar
  table stops at G9, and both §Testing requirements (l.966) and checklist task 2 say "G1-G9". The
  unborn-HEAD measurement it refers to *is* in the document (l.428–430), just unlabelled — either
  promote it to a G10 row or drop the label. (The dispatching prompt believes there are ten cases;
  the artifact has nine.)
- **Store-key encoding order.** §Architecture 2 (l.280) lists "`/`→`%2F`, `%`→`%25`". Applied in that
  order the map is not injective: `a/b` → `a%2Fb` → `a%252Fb`, and a literal `a%2Fb` → `a%252Fb` too,
  so two subjects share one marker file — which defeats the "one file per subject" rationale
  immediately above it. Standard percent-encoding escapes `%` **first**; say so.
- **Who re-supplies the payload.** The pre-filter now reads the raw payload, which means the hook
  consumes stdin; the classifier's contract still says "stdin: the raw PreToolUse payload". Nothing
  states that the hook re-emits its captured copy, and a bash capture is not byte-faithful (trailing
  newlines stripped, NUL impossible) while the classifier's `errors="replace"` implies undecodable
  bytes are expected. One sentence closes it.
- **`-C` is two different flags.** `git -C <dir> commit` (a `FOREIGN` trigger) and
  `git commit -C <commit>` (`--reuse-message`, a value-taking flag) collide; the spec's "anywhere
  **before** the commit" phrasing is the right rule but is never restated where the flag table lives.
- **Inert-repo asymmetry.** Flowchart node `G` (writer installed) precedes the form decision, so
  `cd /other/repo && git commit …` issued from a repo *without* the writer is allowed even when the
  target repo has it. Defensible, but it is an accepted cost that is not written down.
- **Doors row 13 vs. row 14.** Row 14 says `MSG_STALE_TEST` also covers "the test is ABSENT"; row 13
  says only "the subject blob does not match", though the ABSENT prose (l.478) routes an absent
  subject to `MSG_STALE_SUBJECT`. Symmetrise the row.
- **What is genuinely strong this round:** the grammar section is the best-argued text in the
  document and its measurements hold under spot-check; the exit-3 door split is the right shape
  (only the doors table lags); the raw-payload pre-filter really does restore `MSG_NOTHING_RUNNABLE`'s
  reachability, and its two scenarios (l.838, l.846) are the honest pair; the ABSENT-follows-the-
  content-source table fixes both round-3 defects; the 9 allow paths now match the flowchart's 9 ALLOW
  edges exactly and the 24-mutant floor is arithmetically consistent (14 + 9 + 1).
- **Length.** 1,023 lines, up again. The round-by-round narration ("Round 1 had…", "Round 3 said
  seven…") is now a substantial fraction of the document and belongs in this ledger, not in the
  artifact an implementer reads. Same note as round 3; still not a violation.
- **`/opt/homebrew/bin/shellcheck`** remains judged *not* a violation, consistent with round 3:
  measurement provenance for a pinned version, not a runtime path.

### Waivers

None. No violation ids have been waived in any round; both prior escalations were resolved by the
user directing a different fix.

---

## Round 5 — 2026-08-04T16:10:46Z · **FAIL** (5 violations, 1 waived) · confidence: high

HEAD `00583c21d997282f096025e9f67cdc011064c41b` · spec blob `e99b60f3a8a17a42f0b0485e8a8caec7d1c57b4a`
· 1,166 lines

### Layman summary

Round 5 was told to stop patching cells and enumerate the class. It half succeeded, and the half that
succeeded is real: **the wire contract is now genuinely total over `kind`** — `form: NONE` is a value,
all 18 cells are defined, the validation order is stated once instead of twice, and the duplicated
read-side-validation paragraph is gone. **Round 4's `writer-call-site-cwd` finding is fully closed** —
the Python and shell call sites are now true mirrors, both capture absolute values before any chdir,
both run the writer with the repo root as its cwd, and checklist task 8 finally prescribes that form
rather than round 3's superseded one. Doors rows 1, 5 and 8 are reconciled. Every count the dispatching
prompt asked me to confirm holds: **14 doors, 9 allow paths, 24-mutant floor (14 + 9 + 1)**, and the 9
allow paths still match the flowchart's 9 ALLOW edges exactly.

But the totality claim was applied to one axis and not the other, and the round-5 edits again broke a
distant section — the fifth round running.

**The three substantive findings:**

1. **The new ABSENT rule contradicts its own probe, and I measured the false block.** Round 5 correctly
   promoted ABSENT to one semantic definition — "the resulting commit's tree will have no entry at this
   path" — and demoted the probes to implementations of it, writing that "a probe that ever disagrees
   with it is a defect in the probe". Then it merged the `ALL`-outside case into the *same table row*
   as `PATHSPEC`-outside and gave the merged row a two-condition test. The second condition ("the path
   does not exist on disk") is correct for `ALL` and wrong for `PATHSPEC`. Measured on git 2.50.1 in a
   disposable repo: subject modified, sibling test deleted from the worktree but unstaged and outside
   the pathspec, `git commit -m x -- foo.sh` → **the resulting tree still contains `foo.test.sh` at its
   base content `t1`**. Not absent. The probe says absent, so the gate raises `MSG_STALE_TEST` on a
   commit that ships exactly the content the marker certified. The prose at l.563 even calls this "the
   `ALL`-outside row" — it is not a separate row, and that is the whole defect.

2. **`form` is still not a total function of its input.** The contract became total over `kind`; it did
   not become total over commands. The form-resolution rules are declared "in order" and list five
   values (`INCLUDE` → `INVALID` → `ALL` → `PATHSPEC` → `PLAIN`). `FOREIGN` is defined 160 lines later
   with **no position in that order**. `cd /other && git commit -am msg -- foo.sh` fires both the
   `FOREIGN` trigger and the `INVALID` rule, and the two answers differ at the top level of the
   flowchart: `FOREIGN` blocks, `INVALID` allows. `cd /other && git commit -m x -i -- b.md` fires both
   `FOREIGN` and `INCLUDE`, two different doors — and the suite is required to assert the *message*.
   This is the same closed-enum-not-total class that has now been cited in five consecutive rounds, at
   a fifth location. It is **not** the waived tokenisation question: precedence between enum values
   survives whatever lexer lands in `shell_segments.py`.

3. **Nothing states how the gate decides a path has a sibling test — and two scenarios need it to.**
   The flowchart says "Pair each path with its sibling test"; the only stated pairing predicate is the
   mirror of the writer's rule, which uses `git ls-files --error-unmatch`, i.e. *tracked*. Under that
   predicate, measured on git 2.50.1: a test **staged as a deletion** has no index entry, so
   `ls-files --error-unmatch` exits 1 → no pair → **allow**, contradicting the scenario at l.903 that
   demands `MSG_STALE_TEST`; and an **untracked** test on disk likewise exits 1 → no pair → **allow**,
   contradicting round 5's brand-new scenario at l.966 that demands `MSG_STALE_TEST`. Only a union
   predicate (disk ∪ index ∪ `<base>`) satisfies both plus §Scope's "files with no sibling test are
   never gated", and the spec never states one. Round 5 added the scenario without adding the rule it
   depends on.

**The two cheap ones** are one-line fixes and are listed only because the artifact is meant to be
buildable as written: §Latency now says task 10 "measures and records **all three**" budgets while
checklist task 10 still says "record the **two** numbers" — the diff confirms the prose was updated in
round 5 and the checklist was not; and the exemption log is a generated data store with no mode, in a
directory (`hooks/state/`, which does not yet exist in this repo) whose sibling store is meticulously
specified `0700`/`0600` on core-conduct's default-deny grounds.

**Not re-opened:** the `docs/features/` location (adequate, round 1); scope inventory; edge cases;
pinned versions (bash 3.2.57 / Python 3.9.6 / git 2.50.1 / shellcheck 0.11.0, all four still present
and complete); scope boundary; `writer-call-site-cwd` — **closed, verified line by line**.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/commit-form-coverage` *(recurring, 4th round)* | `~/.claude/skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios: state explicitly what correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit, the agent infers — and inference is where the defects come from" (§What a Spec Must Contain) | §"Which paths, and which content" → ABSENT probe table row 3 (l.561), read against the semantic definition (l.551), the round-5 rationale (l.563–565) and the outside-path-set content table (l.528) | Round 5 merged the `ALL`-outside case into the same `<base>`-source row as `PATHSPEC`-outside and gave the merged row the two-condition test "`cat-file -e` non-zero **or** the path does not exist on disk"; the disk condition is correct for `ALL` and wrong for `PATHSPEC`. **Measured on git 2.50.1** (disposable repo): with the sibling test deleted from the worktree, unstaged, and outside the pathspec, `git commit -m x -- foo.sh` yields a tree that **still contains `foo.test.sh` at base content**, so by the section's own definition it is not ABSENT — yet the probe reports ABSENT and the gate false-blocks with `MSG_STALE_TEST` on a commit whose content the marker certified. The prose at l.563 calls this "the `ALL`-outside row", but the table has no such row. |
| 2 | `writing-specs/api-contracts` *(recurring, 5th round)* | `~/.claude/skills/writing-specs/SKILL.md` | "Database schemas and API contracts: these give the agent the real data structures and interface boundaries to build against, instead of letting it improvise shapes that other components then fail to match" (§What a Spec Must Contain) | §"The command grammar" → "The rules the classifier implements, **in order**" (l.439, rule 4 at l.448–450); §"`FOREIGN` — which repo is this commit for?" (l.606–612); `form` domain (l.358); flowchart node `I` (l.39–43); resolution table (l.505–512) | The round-5 fix made the contract total over `kind`, but `form` is still not a total function of the command: the ordered resolution list contains five of the seven values and `FOREIGN` is defined 160 lines later with no position in it, so a command firing both triggers has two legal answers with **materially different outcomes** — `cd /other && git commit -am msg -- foo.sh` is `FOREIGN` (block, `MSG_FOREIGN_REPO`) or `INVALID` (allow), and `cd /other && git commit -m x -i -- b.md` is `FOREIGN` or `INCLUDE`, two doors whose *messages* the suite is required to assert and whose allow-path mutant (`INVALID`) is therefore underdetermined. Distinct from the waived `writing-specs/command-grammar`: enum precedence is not tokenisation and survives any shared lexer. |
| 3 | `writing-specs/pair-formation-rule` *(new)* | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: break the feature into concrete requirements the agent can satisfy and you can check" and "Anything you leave implicit, the agent infers — and inference is where the defects come from" (§What a Spec Must Contain) | Flowchart node `K` (l.45); §"Pairing rule" (l.625–629, esp. l.628); the writer's mirror (l.198–200); §Scope (l.152); scenarios at l.903–908 and l.966–973 | The spec never states the predicate that decides whether a path in the path set *has* a sibling test; the only stated pairing rule is the mirror of the writer's `git ls-files --error-unmatch` (tracked). **Measured on git 2.50.1:** a test staged as a deletion has no index entry (`ls-files --error-unmatch` exits 1) and an untracked test likewise, so under the only stated predicate both form no pair and the gate **allows** — contradicting the scenario at l.903 (`MSG_STALE_TEST`) and round 5's newly added scenario at l.966 (`MSG_STALE_TEST`). Only an unstated union of disk ∪ index ∪ `<base>` satisfies those two together with §Scope's "the gate never demands a test that does not exist". |
| 4 | `writing-specs/latency-budget-count` *(new)* | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: break the feature into concrete requirements the agent can satisfy **and you can check**" (§What a Spec Must Contain); "Maintain it with production rigor … updates when reality changes" (§The Spec Is the Source of Truth) | §Latency → Budgets (l.671) vs. Checklist task 10 (l.1140–1141) | Round 5 added a third latency budget and updated the prose to "checklist task 10 measures and records **all three**", but left task 10 reading "record the **two** numbers here" — confirmed against the round-4→5 diff, where l.671 changed and task 10 did not. An implementer working the checklist records two of three budgets and the new `kind: OTHER` row, added precisely because "an output with no budget is a cost nobody measures", goes unmeasured. |
| 5 | `core-conduct/default-deny-store` *(new)* | `~/.claude/rules/core-conduct.md` | "Secrets and PII stay behind placeholders … nothing sensitive lives client-side; **default-deny every generated data store**" (§Zero-Trust Invariants) | §"Exemption logging" (l.1074–1078) and the scenarios that write it (l.927, l.934), read against §Architecture 2 (l.297) | The feature creates `<repo>/hooks/state/` — which does not exist in this repo today — and appends the exemption audit trail to `<repo>/hooks/state/test-exempt.log`, and neither the new parent directory nor the log file is given a mode, so both fall to the ambient umask. The spec makes the default-deny argument explicitly for the sibling marker store (`0700`/`0600`, "there is no reason for it to be world-readable") and the same argument applies at least as strongly to the log that records every occasion on which verification was skipped. |

### Notes (non-blocking)

- **The ABSENT probe table keys on the wrong partition.** Its `PATHSPEC` rows say "in/outside the
  **pathspec**" while both content tables key on "in/outside the **path set**". Those differ: a
  pathspec-matched file identical to `<base>` is inside the pathspec and outside the path set. The
  row's key column (content source) resolves it, but fixing violation 1 is the moment to align the
  wording. Relatedly, the worktree row's stated coverage ("a pathspec naming a deleted file commits
  the deletion") is unreachable — `--diff-filter=d` removes it from the path set, exactly as l.567–568
  already argues for `ALL`.
- **Store-key encoding order — third round unaddressed.** l.293 still lists "`/`→`%2F`, `%`→`%25`"
  with no order. Applied left to right the map is not injective: `a/b` and a literal `a%2Fb` both land
  on `a%252Fb`, two subjects sharing one marker file, defeating the "one file per subject" rationale
  one line above. Escape `%` **first**; say so in six words.
- **`--status` has no defined input.** l.98 promises it prints "the resolved toplevel … without
  reading any payload", but l.325–327 forbids the hook's own cwd as a toplevel source and there is no
  payload in `--status` mode. Task 14 implies process cwd; state it.
- **Flowchart edge `CF -- "0 with one line"`** does not route exit 0 with *more* than one line. Prose
  step 1 catches it (`MSG_CLASSIFIER_BAD_OUTPUT`), so this is a label imprecision, not a gap.
- **Stale narration at l.1030–1032:** "with the two this round adds it is fourteen" — those two were
  added in an earlier round; at revision 5 "this round" reads wrong. Same family as the round-by-round
  archaeology flagged in rounds 3 and 4.
- **Path splitting.** Every collector is `git diff --name-only` without `-z`, consumed by bash 3.2. A
  tracked path containing a newline mis-splits. The gate is registered **globally**, so it is not this
  repo's file names that bound the risk. Not cited — it is arguably an implementation concern — but it
  is one sentence in §"Every git invocation is status-checked".
- **Call-site mirror asymmetry.** l.245 uses `python3 -I`, l.259 uses `sys.executable -I`, under a rule
  that says "a reviewer should be able to diff the two blocks and find no behavioural difference".
  `sys.executable` is the better choice; the sentence is what needs adjusting.
- **What is genuinely strong this round:** the `kind` × field totality matrix is correct and complete
  (18 cells, `NONE` as a value not an absence), and its "no per-kind special case" rationale is the
  right diagnosis of why the defect kept returning; the two-step validation order with the regex at
  node `H` is right and the scenario at l.983 pins it; the writer call-site fix is complete and
  checklist task 8 now matches it; the anti-duplication rule under the doors table (l.1051–1057) is
  the correct structural response and rows 1/5/8 are reconciled; 14 doors / 9 allow paths / 24 mutants
  all verified consistent against the flowchart.
- **Length.** 1,166 lines, up 143 from round 4. Every round adds narration about prior rounds. That
  history belongs in this ledger.
- **Measurement provenance for this round's findings:** git 2.50.1 (Apple Git-155), three disposable
  `mktemp -d` repos, no commit to any tracked repository.

### Waivers

- **`writing-specs/command-grammar`** — waived by the user (Mark Suyat) on 2026-08-04. Rationale: the
  violation is the tokenisation model, which is the question `hooks/lib/shell_segments.py` already
  answers for `git-guard`, `doc-guard` and `classify-pr-command.py`; specifying a second independent
  grammar here is how the two would drift, so the decision is made once, in the shared lexer, as
  separate work. Verified present in the artifact: the blockquote callout at l.461–477 marks the
  contradiction in place and states that implementation is blocked on that decision, frontmatter
  carries `waived: [writing-specs/command-grammar]`, and checklist task 2 (l.1117–1119) repeats the
  block. Recorded, not counted toward this verdict.

## Round 1 (re-entry, judged against spec revision 6) — 2026-08-13T01:49:34Z · **FAIL** (2 violations) · confidence: high

HEAD `287add5bd94cc07c1bf433be55e011ec4e752fda` · spec blob `a6fa6de17181d8fa527b7c8f8d6a4f72e0004bea`
· 1,419 lines · round counter restarted per the skill's re-entry rule (round 5's `fail` on revision 5
sat unaddressed for eight days before round 6 revised the document)

### Layman summary

Round 6's own closure claims hold up under re-verification. I re-derived the pairing predicate from
scratch rather than trusting the prose, and it is genuinely total (every path gets exactly one role
under the ordered suffix rule) and the subject→test / test→subject asymmetry is sound: the union
direction is the fail-closed one precisely where fail-closed is needed (a subject shipping with only
an on-disk test gets caught, not waved through), and the index-only direction is the one direction
where widening to a union would create a pair no marker could ever satisfy. I did not find the
fail-open the dispatch prompt asked me to hunt for. The M5 four-case split of the `<base>` ABSENT row
is correct and matches its own measurement table. `api-contracts`, `latency-budget-count`, and
`default-deny-store` are all closed as claimed — I checked the totality matrix, checklist task 10, and
the explicit `0700`/`0600` modes on both `hooks/state/` and `test-marker.log` line by line. The log
rename (`test-exempt.log` → `test-marker.log`) is consistent everywhere it appears; no stale spelling
survived. None of the five ids from round 5 recur.

But tracing the flowchart's actual node order — not just the prose claims about it — surfaced a
contradiction round 6 did not touch, in territory this spec has fought over before. §Scope states, in
an explicit "would be a lockout" callout, that the gate is **inert until a repo opts in**, and the
Fail-closed contract repeats this as an absolute: "any repo without the writer installed" is on the
list of things that "do not, and are accepted" as blocking. Both statements are false as the flowchart
is drawn: `MSG_NO_PYTHON`, `MSG_CLASSIFIER_MISSING`, `MSG_BAD_PAYLOAD`, `MSG_CLASSIFIER_FAILED`,
`MSG_CLASSIFIER_BAD_OUTPUT`, and `MSG_NOTHING_RUNNABLE` all sit at flowchart nodes strictly before the
toplevel-resolution node `F` and the writer-installed node `G` — meaning a broken interpreter or a
corrupted classifier in the primary checkout blocks every `git commit` whose raw payload merely
mentions "commit", in **every** repo on the machine, adopting or not. That is the exact global lockout
§Scope's callout says the opt-in design exists to prevent, just triggered by infra failure instead of
a missing writer, and the two absolute claims are never reconciled — no scenario tests the compound
case (classifier broken **and** repo never installed the writer). The same ordering leaves an
unanswered question in the logging design the dispatch prompt asked me to scrutinise: the log's field
4 is "the pairs skipped (`EXEMPT`) or the pair that failed (`BLOCK`)", but ten of the fourteen doors —
including all six named above — fire before any pair exists to name, and six of those also fire before
`<repo>` (the log's own path prefix) is known. This is the same species of defect that closed
`writing-specs/scope-boundary` in round 3 was supposed to have retired: a guarantee about non-adopting
repos stated confidently in one place and not actually delivered by the control flow. It recurred in a
different guise the earlier check did not exercise, so I am citing it fresh rather than reusing that
id — round 5's violation list (the only list this round's persistence check is scoped to) has nothing
matching it.

Separately, the dispatch prompt asked whether length is now causing violations rather than merely
being unwieldy. It is: the contradiction above is a textbook instance of the failure mode O3 itself
names as the reason to eventually shrink this file ("prose consistency at this size... is what keeps
failing") — the same guarantee asserted ~1,000 lines apart, drifted apart, unnoticed through a revision
whose stated goal was closing exactly this class of defect. Deferring O3 was a defensible call when it
was made in round 5-adjacent rounds; carrying it forward now, after the predicted failure mode has
materialised inside this very revision, is not.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/opt-in-fail-closed-conflict` *(new)* | `~/.claude/skills/writing-specs/SKILL.md` | "Requirements, not one-liners: break the feature into concrete requirements the agent can satisfy and you can check" and "Anything you leave implicit, the agent infers — and inference is where the defects come from" (§What a Spec Must Contain) | §Scope → "Where the gate is active" (l.124–134, l.197); §3 the gate → "Fail-closed contract" → "These do not, and are accepted" (l.1202–1206); flowchart nodes `NP`/`CM`/`CF`/`CO`/`C` (l.59–71) vs. `F`/`G` (l.73–76); §"Decision logging" field 4 (l.1260–1265) | §Scope asserts the gate is "inert until a repo opts in" and the Fail-closed contract repeats, unconditionally, that "any repo without the writer installed" is never blocked. The flowchart places `MSG_NO_PYTHON`, `MSG_CLASSIFIER_MISSING`, `MSG_BAD_PAYLOAD`, `MSG_CLASSIFIER_FAILED`, `MSG_CLASSIFIER_BAD_OUTPUT`, and `MSG_NOTHING_RUNNABLE` all before node `F` (toplevel resolution) and node `G` (the writer-installed / opt-in check), so a broken `python3` or a missing/corrupt classifier in the primary checkout blocks every commit containing the substring "commit", in every repo on the machine, including repos that never installed the writer — the exact lockout §Scope's own callout says opt-in prevents. The two claims are never reconciled, and the compound case (infra broken, repo not opted in) has no scenario. The same ordering leaves the log's write-target and field-4 content undefined for the ten doors that fire before a pair (and, for six of them, before `<repo>` itself) is known. |
| 2 | `core-conduct/file-size-convention` *(new)* | `~/.claude/rules/core-conduct.md` | "Many small, focused files (<400 lines, 800 max) over few large ones" (§Code Style) | Whole document, 1,419 lines; "Standing decisions → O3 — the shrink, still owed" (l.1402–1406) | The file is 3.5x the 400-line target and 1.8x the 800-line hard ceiling. O3 defers the shrink on the theory that "prose consistency at this size... is what keeps failing," and round 6 is direct evidence the theory is already right: violation 1 above is exactly that failure — the same opt-in guarantee asserted twice, ~1,000 lines apart, and drifted apart inside a revision whose explicit goal was closing this class of defect. Deferring the shrink after the predicted failure has occurred inside the deferral window is no longer a defensible sequencing call as currently framed; it needs to be re-affirmed as a decision that accounts for this evidence, not carried forward unchanged. |

### Notes (non-blocking)

- **Pairing predicate — cleared, not just re-asserted.** I traced every combination of (subject in path
  set / test in path set / sibling tracked / sibling on disk only / sibling absent entirely) against
  the writer's own `--error-unmatch` behaviour and found no case where the asymmetry lets an uncertified
  subject ship. The "block that commit forever" framing (l.784–787) is accurate for the narrow claim it
  makes — the *standard* remedy (re-run the suite) cannot satisfy it while the sibling stays untracked —
  but is not literally forever; tracking the sibling in the same commit resolves it. Not a defect, but
  the wording invites the stronger reading; worth a half-sentence in a future round, not a violation.
- **M5's four-case table (l.677–691) is reproducible reasoning**, not just plausible — cases A/B/C/D each
  isolate exactly one of the two ABSENT disjuncts for `ALL`, and the `PATHSPEC` row correctly drops the
  disk clause. No arithmetic or logic error found.
- **The rename to `test-marker.log` is complete.** Grepped every occurrence of the old and new names;
  no stale `test-exempt.log` spelling remains anywhere in the document, including the checklist and the
  Gherkin scenarios that assert log lines.
- **`hooks/lib/shell_segments.py:64`'s `WRAPPERS` tuple was checked against the file directly** (not
  just the spec's citation of it) and matches: `("rtk", "time", "eval", "command", "builtin", "exec",
  "nohup")` exists at that path.
- Confidence is **high**: every citation in this round was traced against the live flowchart text or an
  independent re-derivation, not against the round-6 callout's own account of itself, per the dispatch
  instruction to treat that callout as a claim rather than evidence.

### Waivers

- **`writing-specs/command-grammar`** — recorded in frontmatter (`waived: [writing-specs/command-grammar]`)
  and re-confirmed present in the artifact at the unresolved-callout under §"The command grammar"
  (l.531–547) and checklist task 2's cross-reference (l.1339–1341). Not re-argued; not counted toward
  this verdict.

## Round 2 (re-entry, judged against spec revision 8) — 2026-08-13T03:56:18Z · **FAIL** (1 violation) · confidence: high

HEAD `029480968e5e149abe8a7e8314a7c732a8774532` · spec blob `c32b5788eb2559fc524e32b66e2757a0f9fe2be9`
· 1,413 lines · branch `docs/post-merge-53`

### Layman summary

Round 1's finding is fixed, not just claimed fixed. I re-traced the flowchart node by node rather than
trusting the "every door except MSG_NO_PYTHON is downstream of node G" callout as evidence of itself:
the ordering is now pre-filter → python3 check → inline `cwd` JSON read → toplevel resolution → writer-
installed check → classifier, and every one of the twelve remaining blocking doors sits after the
writer-installed node. The door count (13), the allow-path count (10), and the mutation floor (24) all
still agree with each other, with the flowchart, and with the checklist. `writing-specs/opt-in-fail-
closed-conflict` is closed.

Revision 8's scope cut — deferring the decision log, `--status`, and dedicated `INCLUDE`/`FOREIGN`
forms, folding all three into existing structures — also held up under a line-by-line recheck. Nothing
in the current text refers to any of the three deferred items as though they still ship; the fold left
the foreign-repo trigger's refusal completely unchanged (it still blocks, still names itself in
`MSG_UNSUPPORTED_FORM`, still carries its own scenario); and the loss of a queryable `--status` is
disclosed rather than quietly dropped — flagged with warning callouts in §Scope, required reading in the
gates.md/README entry at checklist task 12, and given a one-off substitute at task 14. That is adequate
disclosure of an accepted cost, not a violation.

What the recheck did surface is new, and it sits exactly where this spec's own house style says a
defect like this hides: a stale number presented as a fresh measurement. §Standing decisions → O3
states the file "landed at **1,380**" lines and gives a `wc`/`grep` composition table explicitly
described as "measured... rather than estimated" — the same phrase the frontmatter comment repeats
("size measured and reported, not claimed"). `wc -l` on the actual judged file returns **1,413**, a
33-line gap the O3 section never re-measured. The internal arithmetic inside O3 is fine on its own
terms; it just no longer describes the artifact it is embedded in. This file spends real ink telling
its own implementer to re-derive rather than trust a remembered number (the `python3 -I` latency figure,
re-measured after three prior values disagreed; the mutation floor, explicitly told to be re-derived
"before running it rather than trusting this number") — and then does not hold its own size claim to
that standard. It does not reopen the waiver (either number is far past 800, and the waiver is a
settled user decision I'm not re-arguing), but it is a live, checkable inaccuracy in a durable artifact,
which is exactly what the project's own core-conduct rule on verification-before-claim exists to catch.

### Violations

| # | id | rule source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `core-conduct/verify-before-claim` *(new)* | `rules/core-conduct.md` (project layer, this worktree) | "Verification precedes both the claim and the write-down — never record that claim in a durable artifact (ADR, memory file, commit message, PR body, handoff, spec), until you have actually run it and re-read the output" (§Session Defaults) | §Standing decisions → O3, "Composition of the 1,380, measured with `wc`/`grep` rather than estimated" | The O3 section presents a specific line-count total (1,380) and a component breakdown as a completed, re-runnable measurement backing the file-size waiver, but `wc -l docs/features/verification-marker-gate.md` on the judged blob (`c32b5788e...`) returns **1,413** — a 33-line drift never re-measured after later edits (plausibly the waiver-recording text itself) grew the file past the number the derivation reports. The arithmetic inside O3 is internally consistent (1,448 − 68 = 1,380; 103 − 35 = 68) but no longer matches the file it describes — a claim recorded as settled before being re-checked, the exact failure mode this file's own recurring "measured, not estimated" callouts elsewhere (§Latency's `python3 -I` re-derivation, checklist task 9's mutation-floor re-derivation warning) exist to prevent. |

### Notes (non-blocking)

- **Round-1 fix verified, not just re-read.** Traced every flowchart edge from `A` to each terminal
  node: `D3` (`MSG_NO_PYTHON`) is the only block before node `G`; all of `D4`, `X`, `D5`, `D6`, `Y`,
  `BE`, `UF`, `U`, `Z` (2 messages), `W` (2 messages) sit strictly downstream of `G`. 13 doors, 10 allow
  paths, 24 mutation floor — all cross-checked against the door table, the allow-path enumeration, and
  checklist tasks 6/9, no drift found.
- **No surviving reference to deferred v2 items.** Grepped the whole file for `FOREIGN`, `INCLUDE`,
  `--status`, and `test-marker.log` — every occurrence outside the revision-8 callout and the
  §Follow-ups register is either historical narration or an explicit "deferred" statement; nothing
  treats a cut feature as shipping.
- **Foreign-repo behaviour unweakened by the fold.** The scenario "a commit aimed at another repo
  cannot be verified, so it blocks" still exits 2 with `MSG_UNSUPPORTED_FORM` naming the foreign-repo
  trigger; §"What `UNSUPPORTED` absorbs" states explicitly that "the folding is a prose change, never a
  licence to allow."
- **`--status` loss disclosed, not buried.** §Scope's accepted-cost callout, checklist task 12's
  documentation requirement, and task 14's one-off installed-hook arming proof together make the gap
  observable to the next reader rather than silently absent. Adequate.
- **Cross-document counts all reconciled:** 52 Gherkin scenarios (counted directly, matches O3's
  claim), 18 `kind`×field matrix cells (6 fields × 3 kinds), 14 paired suites (11 pre-existing + 3 new),
  12 doors downstream of `G` (13 total − `MSG_NO_PYTHON`) — no arithmetic disagreement found anywhere
  in the document except the one cited above.
- Confidence is **high**: the cited violation is a direct `wc -l` measurement against the exact judged
  blob, not an inference.

### Waivers

- **`writing-specs/command-grammar`** — recorded in frontmatter (`waived:
  [writing-specs/command-grammar, core-conduct/file-size-convention]`) and confirmed present in the
  artifact at the UNRESOLVED callout under §"The command grammar" and checklist task 2's cross-
  reference. Not re-argued; not counted toward this verdict.
- **`core-conduct/file-size-convention`** — recorded in the same frontmatter list, confirmed present in
  the revision-8 callout at the top of the document and restated in §Standing decisions → Waivers and
  O3. Not re-argued; not counted toward this verdict. Note for whoever next touches this file: the O3
  measurement backing this waiver is the same one flagged stale above (1,380 claimed vs. 1,413 actual)
  — the waiver itself is not in question (both figures clear 800 by a wide margin), but the next edit
  to this section should re-run the `wc`/`grep` derivation rather than adjust the number by hand.
