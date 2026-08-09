# Compliance judge — `docs/features/tracking-feature-state.md`

- **Repo:** `tracking-feature-state` (worktree of `.claude`) · **Branch:** `feat/tracking-feature-state`
- **HEAD:** `24ff8da6b5c07f618194c1ff8af0ec06e6cf0d56` · **Spec blob:** `28b46338ef0dbcc5c8a7722a13788423e5033879`

---

## Round 1 — 2026-08-09T07:13:40Z — **FAIL** (7 violations)

### Summary in plain language

This spec is unusually well-built in the places that normally rot. The background actually argues
*why* the feature exists, the "write claims as derivations, not stored numbers" discipline is real
and holding, and the one thing that burned two prior audits — the difference between a cmux
behaviour *documented* for `rename-tab` and the same behaviour merely *assumed* for `send` — is
handled exactly right: the spec keeps them separate, calls the `send` case unproven, and writes
criterion 9 so the requirement holds no matter which way the probe lands. None of that is cited
against.

What fails is concentrated in one place: **the part of the system that isn't built yet.** The
control server is the component this spec itself calls load-bearing, and it is the component with
no contract. Nobody has written down its URL, its request or response shape, the name of the
"custom request header" that is supposed to force a preflight, or whether an allowlisted command
can carry an argument. Task 10 has to connect the browser UI to that server, so two halves of the
feature are being asked to agree on a shape that was never written down — and "can a command carry
an argument" is not a cosmetic gap, because an argument is untrusted text flowing into a Claude
session that holds full tool permissions.

The sharpest finding is the token. The spec's plan is to bake a per-launch bearer token into
`task-tracker/tracker-data.js` — and that file is **tracked in git** today
(`git ls-files task-tracker/` lists it) with nothing in `.gitignore` covering it. The spec states no
file mode, no git exclusion and no scrub. The single credential guarding the new HTTP hop is
therefore scheduled to be written into a committed, world-readable file. The Security section's own
argument — "the socket was already reachable, what's new is the HTTP hop, so every bullet must
defend that hop" — is correct, and this is the bullet that currently doesn't.

Two smaller mechanical ones: the spec hardcodes `/Users/marksuyat/...` into a committed file, and
every tool it depends on (`pytest`, `uv`, `cmux`, Python itself) is unpinned — which is also why
the recorded "53 passed" can't be reproduced on demand.

**Not cited, deliberately:** the spec's location in `docs/features/` is *correct* here — this repo's
own One-canonical-file discipline in `rules/gates.md` overrides the global `docs/superpowers/specs/`
default, and project rules win. The `tracker-data` schema is likewise judged as conformance to an
existing external contract, not as under-designed new API.

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `core-conduct/secrets-not-client-side` | `rules/core-conduct.md` | Zero-Trust: nothing sensitive lives client-side; no secrets in committed files; default-deny every generated data store | §Security → "Per-launch bearer token" | The token is baked into `task-tracker/tracker-data.js`, which is git-tracked with no `.gitignore` entry, and the spec sets no file mode, git exclusion or scrub — putting the HTTP hop's only credential in a committed file. |
| 2 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | "Database schemas and API contracts … give the agent the real interface boundaries instead of letting it improvise shapes that other components then fail to match" | §Design → "3. Control server"; §Security | No endpoint path, method, request/response schema, header name, token field name, status codes beyond 403, error body, or whether a command id carries an argument — yet task 10 must wire the UI to it and an argument would be untrusted text entering a full-permission session. |
| 3 | `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md` | "Pin the exact version of every library and tool" | §Verification; §Tasks 3–13 | `pytest`, `uv`, `cmux` and the Python interpreter are all named unversioned (only the vendored UI is pinned at `v0.4.1`), so `uv run --with pytest` resolves whatever PyPI serves that day and the collection/`addopts` behaviour the spec depends on can shift underneath it. |
| 4 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Code Style: "Handle errors explicitly, never swallow them. Validate all input at system boundaries." | §Design → 1 Analyzer, 3 Control server; criterion 9 | No stated behaviour when the target isn't a git repo, when `git worktree list`/`rev-list` fails or a branch has no upstream, when frontmatter is malformed, or when `cmux send` exits non-zero or hangs; criterion 9 says the server "refuses and reports" without saying what it returns. |
| 5 | `core-conduct/no-absolute-paths` | `rules/core-conduct.md` | Zero-Trust: "no secrets or absolute paths in committed files" | §"The output contract already exists" | The spec hardcodes `/Users/marksuyat/Other\ Docs/AI/AI_Projx/Task Progress Analysis UI` into a git-tracked file, embedding a machine- and user-specific path in version control. |
| 6 | `writing-specs/no-placeholders` | `skills/writing-specs/SKILL.md` | A spec must leave nothing to guess at — no placeholders or requirements readable two ways | §Security → "Allowlisted commands only" | The allowlist is written as "(`clear`, `handoff`, `reanalyze`, …)", so the ellipsis hands the completion of the entire authorization set to the implementer. |
| 7 | `writing-specs/diagrams` | `skills/writing-specs/SKILL.md` | "Diagrams and the required toolchain: include visual aids … Draw the visual aids as rendered Mermaid" | whole document | A four-component design that crosses browser → localhost HTTP → cmux socket → full-permission Claude session carries no rendered Mermaid, so the trust boundary a reader most needs to see is prose-only. (Lowest severity of the seven.) |

### Notes (non-blocking)

- **Gherkin shape:** 8 of 9 acceptance criteria collapse `When` into `Given` (only criterion 1 has
  all three clauses). Intent stays unambiguous and the skill's own token-economy warning partly
  excuses it, so this is not cited — but restoring the trigger clause would make each criterion
  translate directly into a test name.
- **YAGNI, human-owned:** the stated need (know the merge order across cards and worktrees) is fully
  served by components 1, 2 and 4. Component 3, the control server, is where all the risk lives.
  The control channel is inside the scope as given, so this is not a violation — but "ship the
  read-only survey first, gate the control channel separately" is a scope call worth putting to the
  user once rather than deciding silently.
- **File size:** `analyze.py` is over the 400-line target and under the 800 max; the spec names the
  split (`git_facts.py`) and correctly defers it as human-owned — compliant. Worth watching that
  `server.py` (task 8) carries bind + token + allowlist + header check + surface re-resolution +
  subprocess and will land near the same target.
- **Handled correctly, for the record:** the `rename-tab`-documented vs. `send`-assumed fall-through
  distinction is preserved in both §"Injection route" and criterion 9, with the requirement written
  to hold either way. No citation.
- **Derivations discipline holds.** The one surviving stored number ("53 passed") is stamped with its
  date and its reproducing command and explicitly marked re-run-rather-than-trust — the right shape.
  Pinning pytest (violation 3) is what would make it actually reproducible.
- **Path is correct.** `docs/features/` beats the global `docs/superpowers/specs/` default via this
  repo's One-canonical-file discipline. Explicitly not a violation.

### Waivers

None. No violation has ever been waived for this spec.

---

## Round 2 — 2026-08-09T17:26:06Z — **FAIL** (5 violations)

- **HEAD:** `badd4f81899e11528665d411e95400b2fa6eb72d` · **Spec blob:** `6d9c0f78cd9255b8f0f7094320ccada35d058c26`
- **Round 1 → 2:** 3 of 7 resolved, 4 narrowed but persisting, 1 new.

### Summary in plain language

The revision did real work, and the verification bears that out rather than taking its word for it.
I re-ran every command in the new §Toolchain table on this host: Python `3.9.6`, `uv 0.11.28`,
`pytest 9.1.1`, `cmux 0.64.20 (100) [14e3400b9]` — **all four match the spec exactly**. That is the
opposite of this card's recurring defect species, and it deserves saying. Three round-1 violations
are cleanly closed: the absolute path is gone (`grep '/Users/'` returns nothing), the allowlist
ellipsis is now a three-row table that *is* the authorization set, and the Mermaid trust-boundary
diagram is present and matches the convention four other cards in this repo already use.

What keeps this at fail is one new finding that outweighs everything else, plus four remnants.

**The new one.** The whole point of the round-1 fix was to stop the session's credential from
touching disk, by having the server inject it into the HTML it serves. That is a good move. But
nobody checked what else is in that HTML. The vendored page pulls **three executable scripts from a
public CDN at runtime** — React, ReactDOM, and `@babel/standalone`, an in-browser compiler — plus two
stylesheets (`grep -n unpkg task-tracker/support.js "task-tracker/Task Tracker.dc.html"`; lines 1143,
1145, 1147 and 13–14), with no Subresource Integrity attribute on any of them. So the page holding
the bearer token for a full-permission Claude session executes third-party code fetched over the
network on every load, from an origin the spec never mentions. Any of that code can read the
`<meta name="tracker-token">` tag and POST to `/command` — and it is *same-origin*, so the Origin
check the spec relies on waves it straight through. The spec specifies no Content-Security-Policy and
no response headers of any kind, which `writing-secure-code` §2 asks for by name on new routes. The
Mermaid diagram's `browser["Browser - untrusted execution"]` box is more literally correct than the
author intended, and the diagram draws no edge to the CDN.

**The remnants.** Each is genuinely smaller than its round-1 form; none is untouched.

- The token's "never written to disk in any form" claim still has one uncovered path: the `GET /`
  response sets no `Cache-Control: no-store`, so the browser may write the token into its own disk
  cache. Criterion 10 searches files under `task-tracker/` and the process command line — it would
  pass while the property it exists to prove is false, which is precisely the trap the criterion's
  own last sentence warns about.
- The new wire contract is a large improvement and is *checkably* incomplete: it enumerates the
  servable assets as `nocturne.css`, `support.js`, `_ds/**`, `tracker-data.js` and says "**No other
  file is reachable**" — but the vendored HTML loads `tracker-data-fallback.js` at line 16, a
  git-tracked file not on that list. Build the server exactly to spec and the page it serves 404s on
  its own script tag.
- The contract table presents itself as exhaustive ("Every failure is ... with these codes") yet has
  no code for a failed `reanalyze` — the one allowlisted command that does server-side work. If the
  analyzer aborts (its own failure table's first row) or the store write fails, the implementer
  either invents a status or returns `200`, and a `200` on a failed re-analysis serves stale data
  while reporting success. That is this card's recurring defect species reproduced at runtime.
- `node` is unpinned. It is on this host at `v26.5.0` and it is verification-load-bearing: §Verification
  requires task 13 to record `node --version`, three `test_store.py` tests skip without it, and one of
  those three is criterion 5's only proof. Node's JS parser *is* the thing under test.

**Not cited, deliberately:** scope (settled by the user), `phase: planning` (correct during revision),
and spec location (already ruled correct via this repo's One-canonical-file discipline). I also did
*not* cite an XSS violation on the data path: I checked, and `support.js`'s four `innerHTML` uses are
the design system's template compiler and a hash helper, not data interpolation, so repo text flowing
into the DOM is not demonstrably unescaped. `store.py` uses `ensure_ascii=True`, and because
`tracker-data.js` is loaded as an *external* script a `</script>` breakout does not apply.

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `writing-secure-code/csp` | `skills/writing-secure-code/SKILL.md` | §2 XSS: "ensure any new routes or headers support strict, nonce-based Content Security Policy configurations" | §Design 3 → Wire contract, `GET /`; §Security | The new token-bearing HTML route specifies no CSP or response headers, while the page it serves fetches three executable scripts from `unpkg.com` (React, ReactDOM, `@babel/standalone`) with no SRI, so third-party remote code runs same-origin with the `<meta>` token and the `/command` endpoint. |
| 2 | `core-conduct/secrets-not-client-side` | `rules/core-conduct.md` | Zero-Trust: nothing sensitive lives client-side; secrets stay out of on-disk representations | §Security → "Per-launch bearer token"; criterion 10 | The `GET /` response carrying the token sets no `Cache-Control: no-store`, so the browser's disk cache can persist it, and criterion 10 checks only `task-tracker/` files and the process command line — so it passes while "never written to disk in any form" is untrue. |
| 3 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | API contracts must give real interface boundaries "instead of letting it improvise shapes that other components then fail to match" | §Design 3 → Wire contract, `GET /` static assets | The servable-asset list omits `tracker-data-fallback.js`, which the vendored `Task Tracker.dc.html` loads at line 16, while the contract declares "No other file is reachable" — a server built to spec 404s a script its own page requests. |
| 4 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Code Style: "Handle errors explicitly, never swallow them" | §Design 3 → Wire contract status table; §Security allowlist (`reanalyze`) | The status table is written as exhaustive but defines no failure code for `reanalyze`, the only command doing server-side work, so an analyzer abort or a failed store write has no specified response and a `200` would report success while serving stale data. |
| 5 | `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md` | "Pin the exact version of every library and tool" | §Toolchain — pinned; §Verification | `node` is absent from the toolchain table though §Verification makes it verification-load-bearing (task 13 must record `node --version`; three `test_store.py` tests skip without it, one being criterion 5's only proof) — and node's JS parser is exactly what that criterion tests. |

### Resolved since round 1

| id | how it was verified |
|---|---|
| `core-conduct/no-absolute-paths` | `grep -n '/Users/\|/home/'` on the spec returns nothing. |
| `writing-specs/no-placeholders` | Allowlist is a three-row table stating that a fourth row is a spec change; remaining `...` matches are code ellipsis (`{...}`, `task_ids(...)`), not placeholders. |
| `writing-specs/diagrams` | Rendered Mermaid flowchart at line 86, matching the fenced-mermaid convention in four other cards in `docs/features/`. |

### Notes (non-blocking)

- **Toolchain table verified, not assumed.** All four pins re-read exactly on this host. This is the
  card's own derivations discipline working as designed.
- **The diagram omits the CDN edge.** The trust-boundary flowchart shows browser → server → socket →
  session but draws nothing leaving the browser outward to `unpkg.com`, which after violation 1 is the
  edge a reader most needs to see.
- **Offline/SRI.** The remote scripts also mean criterion 8's `file://` path and the headless/clipboard
  mode do not actually work without network. Vendoring the three assets locally would close violation 1
  and this at once — worth considering as the single fix rather than a CSP allow-list entry for unpkg.
- **`null` vs `0` is untested.** The spec calls this distinction "load-bearing" and argues it well, but
  no acceptance criterion pins it; criteria 1–11 never mention `null`. A criterion here would be cheap.
- **Idle timeout has no value.** "The server exits with the session and on idle timeout" states the
  property without the number, in a document that otherwise pins 5s, 1 KiB, 8422 and 32 bytes.
- **Port override vs. Origin check.** `TASK_TRACKER_PORT` overrides 8422, so the "one exact string"
  the Origin check compares against is computed at runtime; harmless, but worth one clause.
- **Gherkin shape**, as in round 1: several criteria still fold `When` into `Given`. Not cited, same
  reasoning as before.
- **Self-found corrections are sound.** I re-checked both: `task-tracker/` carries no pytest config and
  no `golden`/`measurement` marks, and the three `skipif(NODE is None)` guards in `test_store.py` are
  real. Both corrections are accurate.

### Waivers

None. No violation has ever been waived for this spec.
