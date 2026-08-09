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

---

## Round 3 — 2026-08-09T18:00:15Z — **FAIL** (2 violations)

- **HEAD:** `41b586cb07f6486feebd5f82866e56d1f69af997` · **Spec blob:** `9be9b9c20169f0faf422c969d4f297a375890f3d`
- Round 2's five: **4 resolved, 1 re-cited on corrected evidence, 1 new.** Waived: none.

### Summary in plain language

Four of round 2's five are genuinely closed, and closed well. `tracker-data-fallback.js` is on the
servable list with the grep that re-derives it; `Cache-Control: no-store` and a `Host` check now guard
the one response that carries the credential; `500 reanalyze_failed` covers the only command that does
server-side work, with the store left at its last valid state; and `node v26.5.0` is pinned. I re-read
all five toolchain rows against this host and every one matches exactly — `node v26.5.0`, `Python
3.9.6`, `uv 0.11.28`, `cmux 0.64.20 (100) [14e3400b9]`. The audit log the observability judge asked for
is the right shape: it logs the *resolved* surface, logs refusals as loudly as successes, and bans
headers, bodies and the token in the same breath as §Out of scope does.

**The disputed CSP finding: you were right about the mechanism and wrong about the conclusion.** I
verified your greps and they reproduce exactly — `Task Tracker.dc.html` contains two `https://` lines,
both `<link rel="stylesheet">` for `@phosphor-icons`, and no remote `<script src>` at all. Round 2's
description of *how* the remote code arrives was wrong, and the card is right to correct it.

But the remote JavaScript is real; it is just not in the HTML. The vendored **`task-tracker/support.js`
loads it at runtime**:

```js
// task-tracker/support.js:1143-1147
var REACT_URL = "https://unpkg.com/react@18.3.1/umd/react.production.min.js";
var REACT_DOM_URL = "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js";
var BABEL_URL = "https://unpkg.com/@babel/standalone@7.29.0/babel.min.js";
```

`loadReactUmd()` (`support.js:1838-1847`) injects the first two as `<script>` elements on boot, and
`ensureBabel()` (`support.js:1176-1192`) injects the third on first JSX import. The one escape hatch,
`window.__resources`, is **read in four places and never assigned anywhere in `task-tracker/`**, so the
CDN path is live, not dead code. `_ds_bundle.js` is 300 bytes and does not bundle React; `getReact()`
throws without `window.React`. There is a fourth remote fetch too: `_ds/…/styles.css` `@import`s
`https://fonts.googleapis.com/css2?family=Inter…`. So the page pulls **four** third-party resources,
three of them executable — and the re-derivation command the card prescribes
(`grep -n 'https://' 'task-tracker/Task Tracker.dc.html'`) cannot see any of them, because none live in
that file.

That makes two things false in the current text: task 14 does not "close the last remote fetch on the
token-bearing page", and it is not "what makes criterion 8's offline path actually pass" — with React
coming from unpkg, an offline `file://` load renders nothing at all. It also means the origin holding
the `<meta>` token executes third-party code, which is why the CSP citation stands, on better evidence
than round 2 had. In fairness to the vendored code, round 2's "with no SRI" was **wrong**: all three
URLs carry `integrity` hashes, so a substituted payload is refused by the browser. That is why I did
*not* re-open `core-conduct/secrets-not-client-side` — the token still has no on-disk representation and
a tampered CDN script cannot run.

The second header gap is framing. The card says every Security bullet defends the HTTP hop, but nothing
stops a hostile page putting `http://127.0.0.1:8422/` in an iframe and clickjacking a click onto the
`clear` or `handoff` button: that POST is same-origin, carries the real token, and passes every check
the card lists. `frame-ancestors 'none'` (or `X-Frame-Options: DENY`) on the new route is the fix, which
is the same header territory as the CSP.

### Violations

| # | id | Rule source | Where | Why |
|---|---|---|---|---|
| 1 | `writing-secure-code/csp` | `skills/writing-secure-code/SKILL.md` | §Design 3 → Wire contract (`GET /`); §Security | The new token-bearing route enumerates its response headers (`Content-Type`, `Cache-Control: no-store`) and specifies no CSP and no framing policy, while the page it serves injects React 18.3.1, ReactDOM 18.3.1 and `@babel/standalone` 7.29.0 from `unpkg.com` at runtime (`support.js:1143-1147, 1179, 1841-1846`) and calls `new Function` twice (`support.js:844, 1218`) — third-party code executes in the origin holding the `<meta>` token, a strict nonce-based policy is unachievable as designed, and an iframe + clickjack reaches an allowlisted command with a valid same-origin token. |
| 2 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | §Security → "No remote assets on the token-bearing page"; task 14; criterion 8 | Same species as round 2 (the card's inventory of what the served page loads is incomplete), now on the remote side: the inventory names only the two `@phosphor-icons` stylesheets and asserts "no remote JavaScript is loaded", but the page also pulls three unpkg scripts via `support.js` and a Google Fonts stylesheet via `@import` in `_ds/…/styles.css`, so task 14 does not close the last remote fetch and criterion 8's offline `file://` path cannot pass — no React, nothing renders. |

Round-2 ids **resolved** this round and not re-cited: `core-conduct/secrets-not-client-side`
(`no-store` + criterion 10's three new clauses + the audit-log ban), `writing-specs/pinned-versions`
(`node v26.5.0`, verified), `core-conduct/explicit-error-handling` (`500 reanalyze_failed`, store left
intact), and round 2's `writing-specs/api-contracts` instance (`tracker-data-fallback.js` listed).

### Notes (non-blocking)

- **Correct derivation for the remote-asset claim.** Replace the HTML-scoped grep with a tree-scoped
  one — `grep -rn 'https\?://' task-tracker/ --include='*.js' --include='*.css' --include='*.html'`.
  The current command is scoped to the one file that happens not to contain the interesting hits, which
  is how a card built on derivations still reached a false conclusion.
- **One fix closes both violations.** Vendor React/ReactDOM/Babel and the Inter font alongside the
  phosphor stylesheets, then the route can carry `default-src 'self'; connect-src 'self';
  frame-ancestors 'none'` — with the caveat that `script-src` still needs `'unsafe-eval'` for the
  dc-runtime's two `new Function` sites, so "strict nonce-based" is reachable only in the weaker sense.
  Say so explicitly rather than leaving a reader to discover it.
- **SRI correction, on the record.** All three CDN URLs carry `sha384` integrity hashes
  (`support.js:1144, 1146, 1148`). Round 2's "with no SRI" was wrong; the card's correction is right to
  push back on the round-2 wording, and this round's citation does not rest on that sub-claim.
- **`Host`-check rejection has no status code.** §Design 3 says reject a bad `Host` on `GET /` but the
  status table defines no code or body for it (the JSON error envelope belongs to `/command`). Not
  cited: the behaviour is explicit and no component consumes that response — only an attacker sees it.
  One clause would still close it.
- **`nocturne.css` is on the servable list but the page never requests it** — it loads
  `_ds/…/styles.css` (line 11). Harmless over-inclusion, not a violation.
- **The page fetches its own URL on boot.** `support.js:158-162` re-fetches `location.href` when
  `window.__resources` is unset, so the token-bearing response is retrieved twice per load. `no-store`
  covers it; a CSP would need `connect-src 'self'` for it to keep working.
- **`postMessage(…, "*")`** at `support.js:1856` fires only when the page is framed and carries boot
  metadata, not the token. Worth knowing alongside the framing gap, not a finding on its own.
- **ADRs 0022 and 0023 are consistent with the card.** No contradiction found; 0022's rejected
  alternatives match the card's §Security reasoning.
- **662 lines — the optional split is now worth considering.** The One-canonical-file discipline's
  `<name>.spec.md` half is a MAY, so this is a note only: the frontmatter + tasks would stay in the
  `.md`, and §Design/§Security/§Injection route/§Verification would move. The Revision history alone is
  ~90 lines and is read approximately never.
- **Gherkin shape**, third round running: several criteria still fold `When` into `Given`. Still not
  cited, same reasoning as rounds 1 and 2.

### Waivers

None. No violation has ever been waived for this spec.

---

## Round 4 — 2026-08-09T18:52:11Z — **FAIL** (2 violations)

- **HEAD:** `81d98dc82a8f8b622ce9cf3e39e00b2aa56d1e17` · **Spec blob:** `32a7aa93eb5a2f9d56ed1a244bc95902a8d83e7d`
- Round 3's two: **1 resolved, 1 re-cited one hop further out.** 1 new. Waived: none.

### Summary in plain language

The two things round 3 asked for were done, and done properly. I re-derived every claim in the
revision against the actual files rather than reading the card, and the numbers hold: the remote-asset
table is exactly right — six distinct assets across nine reference sites, and all three unpkg scripts
really do carry `sha384` integrity hashes (`support.js:1144, 1146, 1148`), so the card's correction of
the earlier "no SRI" claim is itself correct. Every pinned toolchain row matches this host exactly
(`Python 3.9.6`, `uv 0.11.28`, `cmux 0.64.20 (100) [14e3400b9]`, `node v26.5.0`), and the suite still
reports **53 passed**. `tracker-data.sample.js` genuinely is reachable
(`tracker-data-fallback.js:19` `document.write`s it), and `nocturne.css` genuinely is not — only
`Task Tracker Directions.dc.html:12` loads it, and that file is never served. Both calls are right.

**The CSP violation is closed, and I checked it would actually work rather than just that it exists.**
The policy is compatible with the page it protects: the two `new Function` sites are real
(`support.js:844, 1218`) so `'unsafe-eval'` is honestly earned; the served page's only apparently-inline
`<script>` is `type="text/x-dc"` at line 297, a data block the browser never executes, so nothing needs
a nonce; the one `<style>` element is covered by `style-src 'unsafe-inline'`; `bundledBlob` reads a
pre-populated `Blob` map and never mints a `blob:` script URL, so `script-src 'self'` does not trip on
it; and `support.js:159`'s `fetch(location.href)` is same-origin under `connect-src 'self'`. ADR 0024
records the `'unsafe-eval'` concession as a rejected alternative with a reason, which is the
human-owned-trade-off shape core-conduct asks for. Nothing further to cite here.

**Where the pattern is not closed.** You asked me to judge the class, not the two instances, and the
class survives one filetype out. The servable-closure rule is right; the command that implements it is
still narrower than the question. `grep -rnE '(src|href)=' --include='*.html' --include='*.js'` cannot
see a request emitted from CSS — wrong syntax for `url(...)`, and `.css` is not in the include list at
all. That is not hypothetical: this card's own task 14 vendors the two `@phosphor-icons` stylesheets
and states that "the icon font files they reference must come along", and rewrites the Inter `@import`
inside `_ds/nocturne-<uuid>/styles.css`. Both produce local files that the served page requests **from
CSS**, and the prescribed derivation returns zero rows for them. Task 8 — which builds the static
manifest and is scheduled before task 14 — is told to "re-run the derivation", pointing the implementer
at the blind command. Round 2's fix was file→repo scope; round 3's was HTML→JS scope; the surviving
gap is JS→CSS scope. Same species, one hop out, for the third round running. The hedge "plus whatever
local paths task 14's vendoring creates" is prose asking the reader to notice, which is exactly the
mechanism this card elsewhere refuses to rely on. A second, smaller leg of the same finding: `_ds/**`
is written into a set the card calls "closed" and "enumerated", but it is a glob — `_ds/` also holds
`_ds_manifest.json`, `readme.md` and `_adherence.oxlintrc.json`, none of which the page requests.

**The new finding, and the one-line test that shows it is real.** The acceptance criteria enumerate the
control server's refusals exhaustively and never once state what success looks like. Criterion 6 ends
"no command reaches the session". Criterion 9 ends "no keystroke reaches any surface". Criterion 7 ends
"no command reaches the session". Criterion 11 requires a `403`. Criterion 10 fetches HTML and greps for
a token. Nothing anywhere asserts that an authorized `clear` actually types `/clear` into the session,
that `reanalyze` through the endpoint produces a new run, that a static-closure member returns `200`, or
that the served page renders at all. The decisive check: **a server that returns `403` to every POST and
`404` to every static path, and never invokes `cmux send`, satisfies criteria 6 through 11 completely.**
The wire contract does define `200 {"ok": true, ...}`, so the shape is written down — but the criteria
are what task 9 builds tests from, and task 9's own wording ("a test that only proves the happy path
does not close this task") assumes a happy-path criterion that was never written. For a feature whose
entire stated value is the send path and the rendered survey, the good case is the one case missing.

### Violations

| # | id | Rule source | Where | Why |
|---|---|---|---|---|
| 1 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | §Design 3 → Wire contract → "The servable set is defined as a rule"; task 8 | The static-asset contract is declared a closed, enumerated closure but its prescribed derivation (`grep -rnE '(src\|href)=' --include='*.html' --include='*.js'`) cannot see a request emitted from CSS, which is precisely what task 14's vendoring of the `@phosphor-icons` font files and the Inter `@import` in `_ds/nocturne-<uuid>/styles.css` creates — and `_ds/**` is a glob covering three files the page never requests, so the manifest is neither closed nor enumerated. |
| 2 | `writing-specs/good-bad-edge-cases` | `skills/writing-specs/SKILL.md` | §Acceptance criteria (6-11); task 9 | The criteria state what wrong looks like for the new trust boundary in exhaustive detail and never state what correct looks like: no criterion asserts an authorized command reaches the session, that `reanalyze` via `POST /command` produces a new run, that a static-closure member returns `200`, or that the served page renders — so a server that refuses every request and never invokes `cmux send` satisfies criteria 6-11. |

Round-3 ids **resolved** this round and not re-cited: `writing-secure-code/csp` — the token-bearing
response now carries a full policy including `frame-ancestors 'none'`, the `'unsafe-eval'` concession is
stated as a caveat rather than glossed, ADR 0024 records it as a rejected alternative with a reason, and
I verified the policy is actually compatible with the page rather than merely present.

Round-1/2 ids still resolved and not re-cited: `core-conduct/secrets-not-client-side`,
`writing-specs/pinned-versions`, `core-conduct/explicit-error-handling`, `core-conduct/no-absolute-paths`,
`writing-specs/no-placeholders`, `writing-specs/diagrams`.

### Notes (non-blocking)

- **Correct derivation for the servable closure.** Add `.css` and the CSS syntax to the command, e.g.
  `grep -rnE '(src|href)=|url\(' task-tracker/ --include='*.html' --include='*.js' --include='*.css'`,
  and enumerate `_ds/` by the two files actually requested rather than by `**`.
- **One blind spot further out, latent today.** `support.js:1642` `ensureFetched()` builds a sibling
  request as `COMPONENT_DIR + "/" + encodeURIComponent(name) + ".dc.html"` (`COMPONENT_DIR = "."`), a
  path no `(src|href)=` grep can ever see. It does not fire for the served page — one `<x-dc>` root, no
  `x-import` — but it is the same species one hop beyond the CSS gap.
- **CSP lands before its vendoring.** Task 8 adds `script-src 'self'` and task 14 vendors the unpkg
  scripts; between them the served page cannot boot, because React/ReactDOM/Babel are blocked by the
  policy. Contained in practice (14 precedes 10, and task 9's tests are HTTP-level), but task 8 should
  say so rather than leaving it to be discovered in a browser console.
- **`base-uri` is absent and does not fall back to `default-src`.** Low impact given `script-src 'self'`,
  but it is a one-token addition to a policy that is otherwise carefully reasoned.
- **No error behaviour for a closure member missing on disk.** `tracker-data.js` does not exist before
  the first analysis — that is the whole reason `tracker-data-fallback.js` exists — yet the status table
  maps `404` only to non-members, and `GET /` states no behaviour if `Task Tracker.dc.html` is unreadable.
- **`analyze.py` is 792 lines**, eight under the 800 hard max. The card surfaces the split as a
  human-owned call and declines to schedule it, which is the right posture, but the headroom is gone.
- **The remote-asset grep returns 15 rows, not 9.** Six are `repoUrls` GitHub links in `tracker-data.js`
  and `tracker-data.sample.js` — link targets, not fetched assets. The table's "six assets across nine
  reference sites" is exactly right; a reader re-running the command needs to know to discard those six.
- **Toolchain re-verified on this host, all five rows exact:** `Python 3.9.6`, `uv 0.11.28`,
  `pytest 9.1.1`, `cmux 0.64.20 (100) [14e3400b9]`, `node v26.5.0`; suite reports **53 passed**.
- **Gherkin shape**, fourth round running: several criteria fold `When` into `Given`. Still not cited,
  same reasoning as rounds 1-3.
- **Deleting the revision history was the right call**, and the reasoning given for it generalises. The
  three warnings kept beside the thing that would reproduce the mistake are the load-bearing survivors.

### Waivers

None. No violation has ever been waived for this spec.

---

## Round 5 — 2026-08-09T19:52:32Z — **FAIL** (3 violations)

- **HEAD:** `b9ad3943939cc6034c922a7fecfa8c27c263cbc0` · **Spec blob:** `5839572c11fd1b8d0c44dca03eb0d63a31a92788`
- Round 4's two: **1 resolved (`api-contracts`, after four rounds), 1 re-cited in a new place.**
  1 promoted from a round-4 note. Waived: none, ever.

### Summary in plain language

**The structural fix worked, and I checked it the hard way.** The user's direction was to stop
narrowing the search and replace it, and that is what landed. I re-derived the manifest from the files
themselves rather than reading the table, and every row is right: `Task Tracker.dc.html` requests
exactly `support.js`, `_ds/nocturne-73641b21…/styles.css`, `_ds/nocturne-73641b21…/_ds_bundle.js`,
`tracker-data.js` and `tracker-data-fallback.js` (lines 6, 11, 12, 15, 16), and the shim
`document.write`s `tracker-data.sample.js` on the first-run path (`tracker-data-fallback.js:19`).
`nocturne.css` really is only loaded by `Task Tracker Directions.dc.html:12`, which is never served.
Enumerating `_ds/` by its two requested files is correct — the directory also holds `_ds_manifest.json`,
`_adherence.oxlintrc.json` and `readme.md`, which nothing requests. `_ds_bundle.js` contains no `url(`,
no `@import` and no absolute URLs, so it adds nothing. **There is no longer a search defining the
contract, and the contract is accurate. `writing-specs/api-contracts` is closed.**

**But the backstop the manifest now leans on cannot be run.** Criterion 13 is the whole load-bearing
idea of this revision — task 8 is told "do not re-derive it by grep, and let criterion 13 tell you if
it is wrong," and task 14 is told "criterion 13 is the proof, not the grep." Three separate things
stop it from being executable at the moment it is needed:

1. **No tool.** "Load the page and follow every request it makes at runtime" needs a browser engine.
   Task 9 assigns criterion 13 to `task-tracker/test_server.py` — a pytest file. §Toolchain pins five
   tools and none of them can drive a page; there is no Playwright, Puppeteer, Selenium or CDP harness
   anywhere in this repo (the one `Playwright` string in `PORTS.md` belongs to a different project).
   The criterion also explicitly forbids the cheap substitute. So the implementer must choose *and add*
   a browser dependency on their own, which core-conduct forbids doing unilaterally.
2. **The "before task 14" run fails by construction.** The criterion is directed to run twice, and
   before-vendoring is the run that "is the proof the manifest is complete." Before task 14 the page
   fetches six assets from `unpkg.com` and `fonts.googleapis.com` — two from the served HTML directly
   (lines 13-14) and three injected by `support.js:1143-1148` — so "no request goes to a host other
   than `127.0.0.1`" is false the moment the page loads. With the network blocked React never arrives,
   so "the UI reaches its rendered state" is false too, and task 8's `script-src 'self'` blocks those
   scripts outright regardless of the network. Task 9 (write the test) precedes task 14 (vendor).
   **At the exact point in the plan where the manifest needs checking, the grep has been demoted and
   the runtime check cannot pass.** That is the gap the whole revision was meant to close.
3. **The state the criterion runs in is never named, and it is the state that hides the bug.**
   `tracker-data.js` is committed and populated (`window.TRACKER_DATA = {…}`), so
   `tracker-data-fallback.js` returns early at its `if (window.TRACKER_DATA) return;` and
   **`tracker-data.sample.js` is never requested.** Run criterion 13 against this repo as it stands and
   it passes without ever touching the one manifest row whose omission was cited in round 4. The check
   only proves the rows the page happens to ask for in whatever state the fixture is in — which is the
   same species as the mis-scoped grep, relocated from the search to the fixture.

A fourth, smaller one: the served page carries no `<link rel="icon">`, so a browser navigating to `/`
requests `/favicon.ico`, which the wire contract answers `404` — colliding head-on with criterion 13's
"no request returns `404`". Nothing in the card resolves that either way.

**The rest of the revision is genuinely good.** Criteria 12 and 14 close round 4's "every criterion is
a refusal" finding properly — 12 asserts `cmux send` was *invoked once* rather than trusting a `200`,
and asserts `reanalyze` invokes it zero times; 14 asserts all three lifetime clauses including that the
audit line actually reaches the parent's stderr. The `5`-second poll number, the launch-method bullet,
criterion 11's in-directory half and §Out of scope's "inside the directory was never the boundary" are
all real improvements. The remote-asset table is exact for the third round running, the three unpkg
scripts do carry `sha384` (`support.js:1144, 1146, 1148`), all five toolchain rows match this host
exactly (`Python 3.9.6`, `uv 0.11.28`, `pytest 9.1.1`, `cmux 0.64.20 (100) [14e3400b9]`, `node v26.5.0`)
and the suite still reports **53 passed**.

### Violations

| # | id | Rule source | Where | Why |
|---|---|---|---|---|
| 1 | `writing-specs/pinned-versions` | `skills/writing-specs/SKILL.md` | §Toolchain — pinned; criterion 13; task 9 | Criterion 13 is now the sole proof of the static manifest and of task 14's vendoring and requires loading the page in a browser and following its runtime requests (explicitly rejecting a source search), yet no browser-automation tool is named or pinned anywhere, the repo contains none, and task 9 assigns the criterion to a pytest file — so the implementer must select and add a browser dependency unilaterally. |
| 2 | `writing-specs/good-bad-edge-cases` | `skills/writing-specs/SKILL.md` | §Acceptance criteria → criterion 13; task 14 | The criterion's states are left implicit and one directed run is unsatisfiable: run "before task 14" it must fail because the page still fetches six third-party assets and cannot render offline; run against the repo's populated `tracker-data.js` it never requests `tracker-data.sample.js`, the very manifest row round 4 cited; and the browser's automatic `/favicon.ico` request makes "no request returns `404`" contradict the wire contract's own default. |
| 3 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | §Design 3 → Wire contract → status-code table | The table enumerates nine failure codes down to `413` and `415` but states no behaviour for the static-read boundary this design introduces — a manifest member that is absent or unreadable on disk (`tracker-data.js` is generated by `store.py`, which is why `tracker-data-fallback.js` exists) or an unreadable `Task Tracker.dc.html` — so the failure falls through to an implementer default, on a route that is the feature's trust boundary. |

Round-4 id **resolved** this round and not re-cited: `writing-specs/api-contracts` — after four
consecutive rounds. The servable set is no longer derived by any search; it is an explicit manifest
that I verified row-by-row against `Task Tracker.dc.html`, `tracker-data-fallback.js`, `support.js`,
`_ds_bundle.js` and `styles.css`, `_ds/` is enumerated rather than globbed, the wire contract's `404`
row and §Out of scope now agree with it, and criterion 11 tests the in-directory half. The failure mode
did not survive in the contract — it moved into the contract's verification, which is violations 1 and 2.

Round-3 id still resolved and not re-cited: `writing-secure-code/csp`. Round-1/2 ids still resolved and
not re-cited: `core-conduct/secrets-not-client-side`, `core-conduct/no-absolute-paths`,
`writing-specs/no-placeholders`, `writing-specs/diagrams`.

### Notes (non-blocking)

- **How to make criterion 13 executable, if it helps:** pin a specific headless-browser harness with a
  version in §Toolchain; state the two fixture states it must run in (populated store *and* a store
  that leaves `window.TRACKER_DATA` unset, which is the only way the sample row is exercised); state
  that the "no non-`127.0.0.1` host" clause applies only after task 14 and reorder task 14 before task
  9 so the pre-vendoring run is not asked for at all; and say what happens to `/favicon.ico`.
- **`support.js:159` fetches `location.href` at runtime** when `window.__resources` is undefined — so
  before task 14 the page issues a second token-bearing `GET /`, and after task 14 it does not. The set
  of runtime requests therefore differs across the vendoring boundary in a way criterion 13 does not
  acknowledge. Same-origin and inside `connect-src 'self'`, so not a leak; it is a coverage point.
- **The manifest still has one open row** — *(task 14's vendored assets)* — in a table the card calls
  closed. Honest and unavoidable today, but it makes violations 1 and 2 load-bearing rather than
  cosmetic: that row's only defence is criterion 13.
- **`_ds/nocturne-<uuid>/` is a placeholder in the authorization set.** The literal is
  `73641b21-c7ad-488a-8264-a28262dfe83e` and there is exactly one such directory, so this resolves
  unambiguously and stays re-vendor-safe — not cited, but it does mean the manifest is still completed
  from the filesystem at implementation time.
- **`base-uri` is still absent from the CSP** (round-4 note, unaddressed). One token, and `default-src`
  does not cover it.
- **CSP lands before its vendoring** (round-4 note, unaddressed, and it now compounds criterion 13):
  task 8 adds `script-src 'self'`, task 14 vendors the scripts, and between them the served page cannot
  boot.
- **The remote-asset grep returns 15 rows, not 9** — six are `repoUrls` GitHub links in
  `tracker-data.js`/`tracker-data.sample.js`. The table's "six assets across nine reference sites" is
  exact; a reader re-running the command must discard those six.
- **`analyze.py` is 792 lines**, eight under the hard max; the card surfaces the split as a human-owned
  call and declines to schedule it, which remains the right posture. The card itself is 851 lines.
- **Gherkin shape**, fifth round running: several criteria fold `When` into `Given`. Still not cited,
  same reasoning as rounds 1-4.
- **Toolchain re-verified on this host, all five rows exact**; suite reports **53 passed** (2026-08-09).

### Waivers

None. No violation has ever been waived for this spec.

---

## Round 6 — 2026-08-09T20:16:51Z — **FAIL** (1 violation)

- **Spec:** `docs/features/tracking-feature-state.md` (blob `0e6efd9ea09a43659849e8befd7123c4668224b8`, 901 lines)
- **Branch:** `feat/tracking-feature-state` @ `73f9475f750e8d24c2cdfb21738270114be7e578`
- **Rule sources read:** `rules/core-conduct.md`, `rules/gates.md`, `CLAUDE.md`,
  `skills/writing-specs/SKILL.md`, `skills/writing-secure-code/SKILL.md` (no `.claude/project-standards.md` in this repo)

### Summary in plain language

Five of the six things round 5 asked for landed, and the two closed rules stayed closed — I rebuilt
the servable manifest from source again and every row is still right. One thing broke, and it broke
in the way this card keeps breaking: **the fix for round 5 collided with another fix from the same
commit.**

Criterion 13 now runs twice — once with `tracker-data.js` present, once with it moved aside — which
was exactly the right correction, and the mechanism works: I traced it and moving the file aside does
reliably produce the request for `tracker-data.sample.js`. But the same commit also added a rule
saying that when `tracker-data.js` is missing the server must answer `404` (not `500`), because that
is the normal first-run state. And criterion 13's pass condition says every request must return `200`
except `/favicon.ico`, and that **any other `404` is a failure**.

The served page asks for `tracker-data.js` unconditionally — it is a plain `<script src>` tag baked
into the HTML at line 15, and the server's only edit to that page is injecting the token. So in run
(a) the browser asks for a file the card has just finished saying should answer `404`, and criterion
13 calls that a failure. **A correctly built server cannot pass criterion 13 run (a).**

That is the same trap the card itself removed elsewhere in this very commit. It withdrew the "run
criterion 13 before task 14" instruction with the reasoning that "a criterion whose first directed run
must fail is a criterion that gets weakened until it passes" — and then re-created that exact shape one
paragraph away. The fix is one clause: run (a) must expect `/tracker-data.js` to `404` alongside
`/favicon.ico`.

Everything else I checked reproduced exactly: 53 tests pass, all five toolchain pins match this host,
the six-remote-asset table and its nine reference sites are correct, and the deliberate exclusion of
`nocturne.css` from the manifest is correct (only the unserved Directions file loads it).

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/good-bad-edge-cases` | `skills/writing-specs/SKILL.md` | Good, bad, and edge-case scenarios — state explicitly what correct looks like and enumerate the edges | Acceptance criterion 13, run (a) (card:639-661), against the wire contract's `404` row (card:322) and the `500 asset_unreadable` exception (card:327) | Criterion 13 requires that in **both** runs "no other request returns `404`", but run (a) deletes `tracker-data.js`, which `Task Tracker.dc.html:15` requests unconditionally and which the card itself specifies must answer `404` in exactly that state — so a correct implementation fails the criterion by construction. |

**Third consecutive citation of this rule — escalate to the user rather than auto-revising.**
This is a **new instance of the same class**, not the round-5 instance surviving: round 5's defect was
that criterion 13 was pinned to the populated store state and therefore never requested
`tracker-data.sample.js`. That is genuinely fixed — run (a) exists and its mechanism works. The new
defect lives *inside* the newly added run (a): its pass condition contradicts the `404` rule added by
the same commit. **The uncovered step out:** each round has patched the criterion's *precondition*
(which file exists, which state is loaded) and left its *pass condition* unexamined; the pass condition
is now the part that is wrong.

### Answering the two decisive questions

1. **Is `good-bad-edge-cases` closed?** No — see above. New instance, same class, one step out.
2. **Does criterion 13 work in both runs as written?**
   - **Mechanism: yes.** Traced against source: moving `tracker-data.js` aside → server `404`s it →
     `window.TRACKER_DATA` stays undefined → `tracker-data-fallback.js:16` falls through its early
     return → line 19 `document.write`s `tracker-data.sample.js`. Run (a) does reliably reach the row
     four rounds of greps missed.
   - **Pass condition: no.** The `404` on `/tracker-data.js` is unavoidable and disallowed.
   - **`/favicon.ico` carve-out: consistent.** The wire contract's `404` row names it explicitly and
     criterion 13 names it as the one expected `404`. The two agree. The omission is
     `/tracker-data.js`, which the same `404` row also names.
   - **Anything else still search-dependent? No.** Task 8 says do not re-derive the manifest by grep,
     task 14's grep is explicitly demoted to drafting, and criterion 13's "no request goes to a host
     other than `127.0.0.1`" is a genuine runtime proof of the remote-asset closure.

### Resolved since round 5

- **`writing-specs/pinned-versions` — closed.** §Toolchain now names the mechanism (Claude browser
  extension), records Chrome at run time, and states the cost in full: criterion 13 does not run under
  `uv run pytest`, does not run unattended, needs a connected operator, and every other criterion stays
  pinned and unattended. Judged as asked — the trade is stated honestly and completely.
- **`core-conduct/explicit-error-handling` — closed.** The `500 asset_unreadable` row now covers a
  manifest member that is absent or unreadable, logs path + `errno`, returns no filesystem detail, and
  carves out the one deliberate exception with its reason.
- **Ordering — resolved.** Task 14 runs immediately after task 8; the unsatisfiable "run criterion 13
  before task 14" instruction is withdrawn with its reasoning recorded.
- **Task 9's `cmux` fake** now states plainly that it proves the server's decision and never that
  keystrokes arrive.
- **ADR 0024** no longer leaves the tick unnamed (see note 2).
- **`writing-specs/api-contracts` (closed round 5) stays closed.** Re-verified every manifest row
  against source: `support.js`, `_ds/nocturne-73641b21-…/styles.css`, `_ds/…/_ds_bundle.js`,
  `tracker-data.js`, `tracker-data-fallback.js` are all requested by `Task Tracker.dc.html:6,11,12,15,16`;
  `tracker-data.sample.js` by the shim's `document.write`. `nocturne.css` is correctly excluded — the
  only reference is `Task Tracker Directions.dc.html:12`, which is not served. The `_ds/` glob would
  indeed also expose `_ds_manifest.json`, `_adherence.oxlintrc.json` and `readme.md`. Manifest correct.
- **`writing-secure-code/csp` (closed round 4) stays closed.** The `'unsafe-eval'` justification is
  real: two `new Function` sites at `support.js:844,1218`.

### Notes (non-blocking)

- **The new `500 asset_unreadable` row is only weakly asserted.** No numbered criterion exercises it;
  it is covered by task 9's blanket "each status code in the contract table". The table carries **two**
  `500` rows, so under a literal "each status *code*" reading a test for `reanalyze_failed` alone
  satisfies it and `asset_unreadable` goes unexercised. Not cited — the error handling itself is stated
  explicitly and the blanket does nominally cover it — but the card holds itself to a higher bar three
  paragraphs earlier ("Assert every clause"), and naming the row in task 9 would cost four words. This
  is the recurring "a control arrives with nothing asserting it" shape in its mildest form yet.
- **Card and ADR 0024 describe the parent-death timer differently.** Card §Security (card:478-480)
  says the check runs "on the same timer that drives the idle check"; ADR 0024:38-41 says it "gets its
  own interval rather than riding the 30-minute idle timer". Reconcilable — one 5-second tick loop
  evaluating a 30-minute threshold satisfies both readings, and criterion 14 cannot tell them apart —
  so not cited. One of the two sentences should still move.
- **`base-uri` still absent from the CSP** (round-4 and round-5 note, still open). `default-src` does
  not cover it; `form-action` is likewise absent. Stated here as a note, not cited: `writing-secure-code`
  requires the route to support a strict nonce-based policy, and the card's documented reason it cannot
  is verified true.
- **CSP-before-vendoring** (round-5 note) is now substantially mitigated: with task 14 moved to
  immediately after task 8, the window in which `script-src 'self'` is live but the scripts are still
  remote is one task wide, and no criterion is scheduled inside it.
- **Static-error body shape is unspecified.** The `{"ok": false, "error": "<code>"}` envelope is
  introduced under the `POST /command` heading, but the `404`, `405` and `500 asset_unreadable` rows
  govern static `GET`s too. Nothing depends on it — criterion 11 only requires that file contents not
  appear — so this is an ambiguity rather than a defect.
- **Measurements re-verified on this host, all exact:** `53 passed` (4.63s), Python `3.9.6`,
  `uv 0.11.28`, `node v26.5.0`, `cmux 0.64.20 (100) [14e3400b9]`. The §Verification correction about
  `pyproject.toml` is right — the only one is `memsearch/pyproject.toml`, and the `golden`/`measurement`
  hits under `task-tracker/` are data strings in `tracker-data.js`, not pytest marks. Three `skipif`
  guards in `test_store.py` at lines 150, 361, 412. `STRICT_RE` and `identity(match.group(1))` match the
  card's quotation exactly. `panes/adapters/cmux.sh:164` is the `send --surface` site and the
  resolution-chain comment at line 168 does document `rename-tab`, not `send` — the card's ⚠️ is correct.
- **`analyze.py` is 792 lines**, eight under the hard max. The card surfaces the split as a human-owned
  call and declines to schedule it, which is the correct posture under `core-conduct`. The card is now
  901 lines (up from 851) despite deleting the ~86-line revision narrative.
- **Gherkin shape**, sixth round running: several criteria fold `When` into `Given`. Still not cited.

### Waivers

None. No violation has ever been waived for this spec.
