# Observability judge verdict — implementation stage

- repo: `tracking-feature-state`
- branch: `feat/tracking-feature-state`
- head_sha: `a6e64b1fc8620b6f0f86a1d6682f11af7818da18`
- base: `main` @ `1b983d9` (diff via `git diff main...HEAD`)
- ts: 2026-08-12T16:29:53Z

## What was changed

This adds a local browser dashboard that surveys every feature card and git worktree in a repo —
which cards are done, which branches are ahead/behind, what order things can safely merge in — and
renders it as a page. The page also has three buttons that can type `/clear`, `/handoff`, or trigger
a re-scan straight into the Claude session that launched it, over a small local web server
(`task-tracker/server.py`) bound to `127.0.0.1:8422`. Because that last part can literally type into
a live, full-permission agent session, most of the engineering weight in this diff is security
plumbing around that one server: a one-time bearer token that never touches disk, a closed list of
exactly which files it will ever serve, an audit log line for every request, and a self-check that
kills the server if its parent (the Claude session) goes away. A large share of the ~19,000 added
lines is not authored code at all — it's vendored copies of React, a Phosphor icon font, and Inter,
copied in on purpose so the page never has to fetch anything from the internet.

## Does it do what you wanted?

Yes, on the evidence available. I re-ran all three test suites myself rather than trusting the
report, and got identical results:

- `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` → **159 passed** (108s)
- `cd memsearch && uv run pytest -q` → **74 passed, 23 deselected**
- All 8 `hooks/*.test.sh` and all 3 `hooks/lib/*.test.py` → **exit 0**

I also read `server.py` end to end against its own spec: the 16-entry static-file allowlist, the
error-code table, the audit-log format, the CSP, and the token handling all match what the design
doc promises, line for line. The riskiest design call — piping a browser button through to
`cmux send` into a live terminal — was proven with real, reproducible probes before being designed
around (including one probe that accidentally hit a different live session, which is what taught the
team that a successful send only proves *delivery*, not *destination*, and reshaped the send-time
check accordingly). That is sound engineering reasoning, not a lucky pass.

## What could go wrong / what I'm unsure about

- **Two security rules live only in a doc, not in code.** "Never launch this server detached" and
  "never redirect its error output" are both written into `SKILL.md`, not enforced by `server.py`,
  because — after checking the reasoning myself — there genuinely isn't a reliable way for the server
  to detect either mistake at its own startup (a normal `&`-backgrounded process doesn't get
  reparented immediately, so a same-moment check can't catch it). That makes this a legitimate call,
  but it also means the whole safety story rests on whoever runs the launch command reading and
  following the skill correctly, forever, with no test and no error message if they don't. I'd treat
  this the way you'd treat a "loaded weapon, safety is a Post-it note" situation: acceptable only
  because it's clearly labeled, not because it's actually enforced.
- **The mutation-testing claim (6 server defects + 7 command-handler defects, "all caught") is
  self-reported** in the commit history and checklist, not something I re-ran myself in the time
  available. I found solid secondary evidence it's real — the test suite contains explicit
  exhaustiveness checks (e.g. a function that cross-checks every audit `reason` value the code can
  actually emit against the ones the spec names) — but that's corroboration, not a re-run.
- **The command-button code for the page lives fenced inside an HTML file**, sliced out by
  string-matched comment markers and loaded under `node` for testing, because it can't be its own
  `.js` file (would need a spec change) and can't be an inline `<script>` (blocked by the page's own
  CSP). It's an unusual shape, but it's the same trick already used elsewhere in this codebase, the
  markers are asserted to appear exactly once, and I don't have a better alternative to suggest given
  the constraints — noting it as a fragility to watch, not a defect.
- Both halves of the feature's own design doc are still over this repo's line-count budget (ADR
  0017); the user has explicitly waived this twice on record, so it isn't blocking, but it's worth a
  glance if the docs grow again.

## What I'd double-check before merging

1. That whoever launches this in practice actually reads `SKILL.md`'s "never detach / never redirect
   stderr" section — since nothing will complain if they don't.
2. Spot-check one or two of the claimed mutation-tested controls yourself if you want independent
   confirmation beyond what I could corroborate here.
3. Re-run `grep -n 'x-dc'` on `Task Tracker.dc.html` after any future edit to that file, to confirm
   the node-loadable slice markers are still intact.

## Dimension scores

| Dimension | Score | Note |
|---|---|---|
| intent | pass | Implementation matches the spec's wire contract, manifest, and security posture line for line. |
| execution | pass | All three suites re-run independently by me; identical to the reported counts. |
| trajectory | pass | Injection route was spiked live before being designed around; design changed in response to real findings, not assumption. |
| regression | pass | Baseline taken from a detached `main` checkout, not reasoned about; unrelated suites (memsearch, hooks) identical before/after, confirmed by me. |
| context_budget | concern | SKILL.md + one Skills Catalog line are minimal and on-demand; but both halves of the feature's design doc remain over ADR 0017's cap (waived, re-confirmed, not newly introduced by this stage). |
| traceability | pass | Every non-obvious choice is commented with its *why* and a re-derivation command; ADRs 0022-0024 cover the structural calls. |
| success_masking | pass | No unbounded loops found (all subprocess calls and the watchdog are timeout-bounded); tests independently re-run green. Mutation-testing claim not independently re-verified by me (see concerns). |
| intent_drift | pass | The few non-server file touches (Directions.dc.html, nocturne.css, _ds/styles.css) are all in-scope vendoring path fixes, not drive-bys. |
| checkpoint | pass | Net-new feature directory plus two minimal additive edits to existing files (CLAUDE.md, PORTS.md); trivially revertible by dropping the branch. |
| audit_trail | pass | 63 scoped commits, three ADRs, a per-request server-side audit log, and a compliance-judge PASS already on record for the spec this implements. |

## Concerns

- Launch-discipline controls (no detach, no stderr redirect) are prose-only by necessity; residual risk is a silent, untestable security downgrade if the launching skill is skipped or mis-run.
- Mutation-testing claims (13 defects, all caught) are trajectory evidence I corroborated but did not re-run myself.
- Both halves of `docs/features/tracking-feature-state.{md,spec.md}` remain over their ADR 0017 size caps — waived on record, not a new issue, but worth re-checking if size grows further.
- The command-handler's HTML-fenced/node-sliced structure is unusual and depends on exact comment-marker text staying intact in `Task Tracker.dc.html`.

risk=low confidence=high
