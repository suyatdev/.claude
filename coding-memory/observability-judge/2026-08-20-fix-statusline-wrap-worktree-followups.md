# Observability verdict — fix/statusline-wrap-worktree-followups (implementation)

- **Repo:** statusline-followups (worktree of suyatdev/.claude)
- **Branch:** `fix/statusline-wrap-worktree-followups`
- **HEAD:** `7ae3b91e3cd4a68001b370d692eaeee2d1effe00`
- **Stage:** implementation
- **Judged:** 2026-08-20T23:13:29Z
- **Evidence:** `git diff main..HEAD` (4 files, +294/-87), `bash statusline-command.test.sh` → **70/70**, `python3 statusline-command.falsify.py` → **falsification intact** (exit 0), plus four independent mutation probes run by the judge (below).

## What was changed

Four leftovers from PR #43, one commit each:

1. **The "is our safety net actually working?" checker was broken.** It replayed today's tests against four old versions of the status-line script and compared *how many* tests passed. That number moved every time an unrelated feature added a test, so it had been re-tuned three times and had finally died outright: it pinned a commit (`f0902ed`) that no longer exists in the repo at all. Now it compares *which named injection tests fail* in one fenced-off section of the suite, marked with `@@GROUP2-START@@`/`@@GROUP2-END@@` sentinels. Growth elsewhere in the suite can no longer knock it over.
2. **A silent-failure hole plugged.** If git can't tell the script which checkout it's in, the status line used to look exactly like "you're safely in the main checkout" — the single most dangerous thing it could get wrong. It now prints `wt:(?)`.
3. **Noise silenced.** A ridiculous `COLUMNS` value (16+ digits) used to spill a bash arithmetic error onto stderr. Now rejected by the same guard that already rejects other junk values.
4. **A test made machine-independent.** A row-count assertion only caught its target bug when the developer's username+hostname happened to be long enough. `whoami`/`hostname` are now pinned behind a fixture shim.

## Does it do what was intended?

Yes. Every claim in the decisions summary that I could check independently held up.

## Independent verification performed

| Probe | Result |
|---|---|
| Full suite | 70/70 passed (~9s) |
| Falsify harness | `falsification intact`, all four shas `ok` (~22s) |
| `f0902ed` really gone | `git cat-file -t f0902ed` → `fatal: Not a valid object name` |
| Task 11 test is red without its fix | deleted the 16-digit case pattern → **FAIL** (`integer expression expected`), 69/70 |
| Task 10 test is red without its fix | neutralised the `[ -z "$git_dir" ]` branch → **FAIL** ("indistinguishable from the main checkout"), 69/70 |
| Task 12 assertion still catches its mutant | dropped `[ $i -gt 0 ]` (statusline-command.sh:772) → **FAIL** (`rows=7>6`), 69/70 |
| Harness detects a corrupted expectation | temp copy with one `EXPECTED` entry falsified → `MISMATCH` + precise expected/actual diff, `FALSIFICATION BROKEN` |

All probes were run on temp copies; the working tree was clean before and after (`git status --porcelain` empty).

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| intent | pass | All four tasks closed as specified in the feature file; nothing extra claimed. |
| execution | pass | Both test commands run by the judge; 70/70 and harness intact. Each new assertion proven red against its own mutant. |
| trajectory | pass | Root causes found, not symptoms: dead sha traced to a GC'd amended commit; count-based comparison replaced by name-based; a self-inflicted shim bug (`PATH=` prefix scoping to `printf` only) found by tracing and recorded. |
| regression | pass | Only additive changes to the script's two guards; a real main checkout still renders no `wt:()`, verified by the pre-existing test. No always-on config touched. |
| context_budget | pass | `CLAUDE.md`, `rules/`, `skills/`, `hooks/`, `settings.json` all untouched. |
| traceability | pass | Comments explain *why* at each edit site; the harness docstring records the f0902ed forensics and the corrected `925c310` label. |
| success_masking | pass | This branch's whole point is anti-masking, and it earns it: the green suite was probed with four mutants, and the harness itself was proven able to fail. Runtimes bounded (~9s / ~22s). |
| intent_drift | pass | Relabelling `925c310` and rewriting the docstring are inside task 9's own stated scope. No new dependencies; no drive-by edits. |
| checkpoint | pass | Five commits, one per task plus a reopen and a close; each individually revertible. |
| audit_trail | pass | Commit bodies carry the reasoning including the dead ends; the feature file's task entries were rewritten in place (one canonical file), phase moved to `review`. |

## Concerns (all minor)

- The harness docstring says every Group 2 case fails for `925c310` "except the two that pass for the right reason", but only one template is excluded from `EXPECTED`; the second is excluded from `GROUP2_TEMPLATES` for a *different* reason (no discriminating signal). Wording, not logic.
- Group 2's sentinels are now echoed into ordinary suite stdout, coupling the human-facing test output to the harness's parser. Documented in both files, but a future reformat of the group boundary will break the harness (loudly — it raises `SystemExit` if the sentinels vanish).
- Only the row-bound fixture pins `whoami`/`hostname`; other assertions still render the real machine's user@host, so some environment sensitivity remains elsewhere in the suite (out of scope for task 12, worth a future note).
- The harness runs the full suite five times (~22s) and that cost grows linearly with the suite. Bounded and cheap today; not free forever.
- `f0902ed`'s history is genuinely unrecoverable. The loss is documented honestly rather than papered over, but one historical data point is gone for good.

## Verdict

**risk=low confidence=high** — proceed to PR.
