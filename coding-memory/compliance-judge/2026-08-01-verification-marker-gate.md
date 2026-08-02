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
