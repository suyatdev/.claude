# Observability judge — `feat/tracking-feature-state` (architecting, advisory)

- **repo:** `tracking-feature-state` (worktree of `.claude`) · **branch:** `feat/tracking-feature-state`
- **HEAD:** `24ff8da6b5c07f618194c1ff8af0ec06e6cf0d56` · **base:** `origin/main`
- **stage:** `architecting` · **ts:** 2026-08-09T07:13:42Z
- **doc judged:** `docs/features/tracking-feature-state.md` (286 lines)
- **advisory only** — runs alongside a blocking compliance judge; gates nothing by itself.
- **test evidence:** I ran `uv run --with pytest --no-project pytest task-tracker/ -q` myself →
  **53 passed in 3.98s, 0 skipped, 0 failed.** Matches the number recorded in `## Verification`.

---

## What was changed

Right now, working out "what state is every feature in, which branches exist, what merges first"
means rebuilding the same survey by hand at the start of every session. Somebody already tried to
write it down once — into `.claude/session-state.md` — but that file is gitignored *and* rewritten
by a hook every session, so the note was gone by the next day. It was a shopping list written on a
whiteboard that gets wiped nightly.

This design replaces the whiteboard with a machine that regenerates the list on demand: a Python
analyzer reads the feature cards and git, writes the result into a data file, and an
already-built browser page renders it. A small local web server will later let buttons on that page
type commands into the live Claude session.

Four pieces, built in order: analyzer → data store → control server → skill. **Tasks 1–7 are
done; tasks 8–13 are not.** The unbuilt half contains the entire security surface.

## Does it do what you wanted?

**Yes, for the part that exists — and the reasoning behind it is better than average.**

The strongest signal is that the author kept catching *themselves*. Three examples I verified
independently, not just read:

| claim in the card | my check | result |
|---|---|---|
| task identity comes from one parser, `STRICT_RE` | `hooks/lib/feature_tasks.py:37` | ✓ regex matches the card verbatim |
| `cmux send --surface` precedent exists | `panes/adapters/cmux.sh:163-165` `send_launcher()` | ✓ exactly as quoted |
| the "stale ref doesn't error" comment covers `rename-tab`, **not** `send` | `cmux.sh:167-169` | ✓ the card is right to refuse the inference |
| `terminal-detect.sh` prints `none` under SSH/headless | `panes/terminal-detect.sh:14` | ✓ |

That third row is the one that matters. An earlier draft assumed `send` inherits `rename-tab`'s
silent fall-through to *the focused tab*. The card now says: we don't know, prove it before task 8,
and refuse an unconfirmed target regardless of the answer. That is the difference between a design
that works and a design that got lucky — the failure mode being guarded against is keystrokes
landing in whatever window happens to be in front.

The tests are real, not decorative. 53 of them, against purpose-built fixture repos rather than this
one, and the names read like someone trying to break their own code:
`test_prose_never_creates_a_dependency`, `test_dependency_cycle_is_a_question_not_an_infinite_loop`,
`test_analyzer_writes_nothing_to_the_analyzed_repo`,
`test_sigkill_between_temp_write_and_replace_leaves_the_store_intact`.

## What could go wrong / what I'm unsure about

**The one to fix before task 8: a secret is scheduled to be written into a file that git tracks, in
a public repo.**

Three facts, each verified separately:

1. `git ls-files task-tracker/` lists **`tracker-data.js`** — it is committed (in `37a8e38`), and
   `git check-ignore` says it is **not ignored**.
2. The committed copy is not a placeholder, it is genuine output:
   `"generatedAt": "2026-08-09T06:21:47Z"`. So the "run the tool, commit the result" loop has
   already happened once.
3. The Security section says the per-launch bearer token is *"baked into the emitted
   `tracker-data.js`"* — and `gh repo view` reports `suyatdev/.claude`, **`isPrivate: false`**.

Put together: the moment task 8 lands, a routine `git add -A` publishes a live session token to a
public repository. Nothing is leaked *today* — the server doesn't exist yet — which is exactly why
this is worth saying now rather than in the implementation round. The fix is cheap at this stage
(gitignore the generated file, or put the token somewhere that isn't the data file) and awkward
later.

**Three smaller things:**

- **Green can hide a gap.** Three `test_store.py` tests are `skipif(NODE is None)`, including
  `test_store_survives_sigkill_as_loadable_js` — which *is* the proof for acceptance criterion 5.
  Node is installed here (0 skipped, confirmed), but on a machine without it the suite still prints
  green while criterion 5's strongest assertion never runs.
- **The `addopts` warning is aimed slightly off.** The card warns that `addopts` in
  `pyproject.toml` deselects the `golden` and `measurement` marks. The only such file is
  `memsearch/pyproject.toml`, which is not an ancestor of `task-tracker/` and therefore does not
  govern this suite. The warning is still *useful* for task 13 and errs safe — but an unqualified
  path is the same species of defect this card spent two audit passes eliminating.
- **One coarse commit.** `37a8e38` lands 8,339 insertions across 21 files — the vendored UI plus
  the analyzer plus the store plus both test suites, tasks 2–6 together. Every other commit on the
  branch is small and clean, so it's a lapse rather than a pattern, but there is no revert point
  between "vendored a third-party UI" and "shipped a 792-line analyzer".

**What I'm genuinely unsure about:** whether `cmux send` into a live Claude TUI behaves like `cmux
send` into a shell prompt. The card is honest that nobody has tested this and owes the probe before
task 8. I could not resolve it either — it needs a live surface.

## What I'd double-check before merging

1. **Decide where the bearer token lives, before writing `server.py`.** If the answer stays
   "`tracker-data.js`", then that file must be gitignored *and* the currently-committed copy
   removed from tracking in the same change. Verify with `git check-ignore -v
   task-tracker/tracker-data.js` returning a match.
2. **Run the outstanding probe** — `cmux send` into a live Claude TUI, not a shell prompt — and
   record the result in the card either way. A negative result changes task 8's design; a
   silently-skipped probe changes nothing until it fails in production.
3. **Confirm node is present in whatever runs task 13's before/after counts**, or compare
   skip counts per suite and not just pass counts.
4. **`analyze.py` is 792 lines against the 800 hard cap** — eight lines of headroom. The
   `git_facts.py` split is correctly deferred as a human-owned call, but nothing mechanical will
   stop task 8–10 pushing it over.
5. **Two ADR-shaped decisions have no ADR.** Ceding schema ownership to an external UI export, and
   introducing an HTTP endpoint that can drive a session holding full tool permissions, are both
   structural by `rules/gates.md`'s own wording. 21 ADRs already exist under `docs/decisions/`;
   neither of these is among them. The card holds the reasoning well, but cards get superseded and
   ADRs don't.
6. **Minor:** `tracker-data-fallback.js` says "before the first analysis that file does not
   exist" — in a fresh clone it always exists, so the shim's stated trigger is unreachable, and no
   test covers it.

---

## Dimensions

| dimension | verdict | why |
|---|---|---|
| `intent` | **pass** | Real, evidenced gap (`.gitignore:72` `/.claude/` + `hooks/live-handoff.sh` rewrite). Acceptance criteria are concrete and falsifiable; scope boundaries explicit and permanent where they should be. Tasks 1–7 as built match what is specified. |
| `execution` | **pass** | I ran the suite: **53 passed, 0 skipped**. Substantive coverage — negative cases, fixture repos, SIGKILL-mid-write, read-only assertion. Not happy-path-only. Scoped to the built half; the server is unwritten by design sequence, not by omission. |
| `trajectory` | **pass** | Reasoning, not luck. The `sort -u` union artifact was found and corrected; the `rename-tab` vs `send` inference is explicitly refused rather than assumed; "undetectable dependency becomes a question, not a confident ordering"; a defect *inside the audit itself* was recorded rather than dropped. 4/4 source citations I spot-checked held. |
| `regression` | **concern** | The analyzer's output target `tracker-data.js` is git-tracked and unignored, already carrying a real run — every future analysis dirties a tracked file, and the design routes a secret into it. Nothing outside `task-tracker/` was touched except additive edits to `.gitignore`, `PORTS.md`, `CODING_MEMORY.md`. |
| `context_budget` | **pass** | Always-on cost is one Skills Catalog line (task 12); the SKILL.md (task 11) is on-demand and explicitly *points at* `managing-session-memory` rather than restating phase rules. Decision 7 (derivations, not stored counts) actively reduces future churn. The 8,700-line diff is vendored static assets, not context. Watch: `analyze.py` at 792/800. |
| `traceability` | **pass** | Every non-obvious decision carries its evidence *and* its cost. Module docstrings hold the *why* (`analyze.py:8-22`, `store.py:15`, the `document.write` rationale in `tracker-data-fallback.js`). Docked slightly for the unqualified `pyproject.toml` reference and one committed absolute home path in the card. |
| `success_masking` | **concern** | Three `skipif(NODE is None)` tests include criterion 5's JS-loadability proof — green on a node-less host with that assertion unrun. The `addopts` deselection is documented and scheduled (credit), but its scope is mis-stated. And "53 passed" covers only the read-only half; criteria 6, 7 and 9 have no tests because the risky component isn't written. |
| `intent_drift` | **pass** | Diff confined to `task-tracker/` plus three additive edits. **No new dependency** — stdlib Python, vendored static UI, pytest pulled transiently via `uv run --with`. The identified `git_facts.py` split was deliberately *not* taken as a drive-by. "Out of scope" names the arbitrary-command endpoint as permanently out, not deferred. |
| `checkpoint` | **concern** | `37a8e38` bundles tasks 2–6 and 8,339 insertions into one commit — no revert point between vendoring the UI and shipping the analyzer. Current state is otherwise a clean checkpoint: worktree clean, frontmatter `branch:` matches the actual branch, HEAD level with its remote (7/7 vs `origin/main`). |
| `audit_trail` | **concern** | No ADR for either structural decision (external schema ownership; HTTP control channel into a fully-permissioned session), against a live 21-ADR convention. Attribution otherwise strong: scoped commit messages, sessions 49–50 archived in `CODING_MEMORY.md`, revision history naming `a854e99` as the last commit carrying unrepaired text. |

**risk: medium** — nothing built is broken and the test evidence is real, but one concrete hazard
sits directly on the path ahead (a session token routed into a tracked file in a public repo) and
the entire security surface is still unwritten. Not low because the hazard is specific and the repo
is public; not high because nothing is leaked today and the stated security posture is otherwise
unusually thorough.

**confidence: high** — I ran the test command myself, verified every source citation I checked
(4/4), and confirmed the tracked/ignored status and repository visibility directly rather than
inferring them.

## Concerns

- `tracker-data.js` is git-tracked and unignored in a public repo; design bakes the bearer token into it
- entire security surface (criteria 6, 7, 9) unbuilt — 53 green tests cover only the read-only half
- 3 store tests `skipif(NODE is None)`, incl. criterion 5's JS-loadability proof
- card cites `addopts` in `pyproject.toml`; only `memsearch/pyproject.toml` exists and does not govern this suite
- commit `37a8e38` bundles tasks 2–6 + 8.3k insertions — no revert point between them
- no ADR for schema-ownership cession or the HTTP control-channel decision
- `analyze.py` at 792/800 lines; `git_facts.py` split deferred with no mechanical trigger
- `cmux send` into a live Claude TUI still unproven (card is honest about this; probe owed before task 8)
- `tracker-data-fallback.js`'s stated trigger (file absent) unreachable in a fresh clone; untested
