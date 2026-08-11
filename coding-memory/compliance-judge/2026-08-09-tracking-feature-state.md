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

## Round 7 — 2026-08-10T01:58:16Z — **FAIL** (3 violations)

- **Spec:** `docs/features/tracking-feature-state.md` (blob `ce97b6972cf226cac1f94136741c5b15b062a6a3`, 933 lines)
- **Branch:** `feat/tracking-feature-state` @ `fe55b2d5052d85deb87283eab6c6545e17b56e40`
- **Rule sources read:** `rules/core-conduct.md`, `rules/gates.md`, `CLAUDE.md`,
  `skills/writing-specs/SKILL.md`, `skills/writing-secure-code/SKILL.md` (no `.claude/project-standards.md` in this repo)

### Summary in plain language

**Round 6's violation is fixed, and the class behind it is fixed too.** Criterion 13's pass condition
is now set equality against two explicit path→status tables, `/tracker-data.js` → `404` sits in run
(a)'s table where it belongs, and a correctly built server now passes. Set equality also closes the
direction the old negative wording never covered. I rebuilt both tables from the real files and every
row that is spelled out is right: the four `200`s, the two deliberate `404`s (`/tracker-data.js` in run
(a), `/favicon.ico` in both) are the only `404`s, and run (b)'s two changes are correct — I confirmed
`tracker-data-fallback.js:16` returns early when `window.TRACKER_DATA` is set, so
`tracker-data.sample.js` genuinely drops out of the observed set. `writing-specs/good-bad-edge-cases`
is **closed**.

The bad news is that the same defect species surfaced one hop further out, and this time it is on the
side of the closure the card has never examined: **not what the page requests, but what task 14's own
vendoring work adds to the servable set, and what headers those responses need.** Three concrete gaps,
all in the manifest the card insists is "an explicit list, not a grep":

1. **Static assets have no `Content-Type`.** The card specifies `Content-Type: text/html` for `GET /`
   and nothing at all for the six static rows. Chrome refuses to apply a stylesheet served with a
   non-CSS MIME type, so criterion 13's own "with the UI rendering the sample" clause depends on a
   header the contract never states. Everything else about these responses is pinned to the byte; this
   is the one field missing.
2. **The file that defines `window.__resources` is on no list.** §Security's vendoring mechanism says
   "define that map before `support.js` loads", and I verified the hook works exactly as described
   (`support.js:1149-1153`, `cdnScriptFor` reads `window.__resources[url]`). But the obvious
   implementation — an inline `<script>` in `Task Tracker.dc.html` — is **forbidden by the card's own
   CSP**: `script-src 'self' 'unsafe-eval'` carries no nonce and no `'unsafe-inline'`, so an inline
   script is blocked. The map must therefore live in a separate served file, and that file appears
   neither on the §Design 3 manifest nor in either criterion 13 table. It is not covered by the
   *"(task 14's vendored assets)"* row either — it is a new first-party shim, the same species as
   `tracker-data-fallback.js`, which the card lists as its own explicit row.
3. **Task 14 stops one hop short on the Inter font.** For `@phosphor-icons` the card correctly says
   "the icon font files they reference must come along, or the CSS resolves to nothing". For Google
   Fonts it says only "rewrite the `@import`" — but that `@import` fetches a stylesheet from
   `fonts.googleapis.com` whose `@font-face` rules point at `fonts.gstatic.com` woff2 files, so Inter
   is a **two**-hop asset where phosphor is one. Rewriting only the `@import` leaves the page still
   fetching fonts from a third-party host, failing criterion 13's "no request goes to a host other
   than `127.0.0.1`". This is verbatim the failure the card documents at lines 278-284: *"One hop was
   followed, the next was not."*

None of the three is silent — criterion 13 catches all of them, which is the design working. But they
are unbuildable-as-written instructions handed to task 14, and the card's standard is that the
implementer has nothing left to guess at.

**Second finding: the card now contradicts an ADR it defers to.** §Security:478-480 says the
parent-death check runs "on the same timer that drives the idle check". ADR 0024:38-41 says it "gets
its own interval **rather than riding the 30-minute idle timer**" — and explicitly records that "on the
idle timer" was a first-draft error it corrected. Rounds 5 and 6 both noted this as a reconcilable
wording split and did not cite it. Having now read the ADR, it is not reconcilable: the ADR names that
exact phrasing as a bug it fixed, and the card kept it. The card says at lines 123-125 that the ADRs
hold the *why* and the card holds the *what*; here the two *whats* disagree, and the card's own next
paragraph warns that the 30-minute reading "would have made the worst case half an hour of an orphaned
full-permission control channel". The card contains both the error and the warning against it, six
lines apart. **Cited this round** — this is the card's signature defect (a fact corrected in one copy
and not the other), and it has now survived two rounds as a note.

**Third finding: the bind boundary has no error behaviour.** Every other boundary in this card is
exhaustive — eleven wire-error rows, five analyzer-failure rows, a `cmux send` timeout, a store-write
failure. The first boundary the server crosses, `bind()`, has none. Port 8422 already in use is not
exotic here: `core-conduct`'s parallel-agent invariants state that multiple sessions run concurrently
in worktrees, and two sessions each running the skill collide on a fixed port. The failure is also
confusing rather than clean — the second launch dies while the user's browser still reaches the *first*
server on `http://127.0.0.1:8422/`, holding a different in-memory token, so the UI loads and every
button `403`s with the card's deliberately uninformative collapsed error.

**On the card's size, which I was asked to judge directly: no rule is breached, and I am not citing
it.** `rules/gates.md` makes a single `docs/features/<name>.md` the default and makes the `.spec.md`
split a MAY; `core-conduct`'s 400/800 limit sits under **Code Style** and governs code files. But the
trend is real — 933 lines, up from 901, 851 and 813, growing every round — and roughly 110-120 lines
(~12%) is now forensic narrative about earlier judge rounds rather than buildable requirement:
lines 18-29, 240-254, 270-289, part of 503-517, 627-630, 644-653, 676-685, 905-912, and the 20-line
§Revision history at 914-933 that exists to explain why an 86-line narrative was deleted.
`writing-specs` pulls both ways here — it calls the human review gate "the whole point" and warns that
"bloat degrades reasoning" — and the card's defence (warnings belong beside the thing that would
produce the error again) is genuinely sound for the two `grep`-scope corrections and the
`rename-tab`-vs-`send` distinction. It is much weaker for §Revision history, which narrates a deletion,
and for the round-by-round histories now duplicated in the verdict files the card itself points at.
Recommendation: trim §Revision history to two sentences and cut the round-attribution prose from
criterion 13 and §Design 3, keeping the substantive warnings. That is ~60 lines with no loss of
buildable content.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | Database schemas and API contracts — give the agent the real interface boundaries instead of letting it improvise shapes | §Design 3 "Wire contract" static manifest (card:256-291), criterion 13 runs (a)/(b) (card:655-685), task 14 (card:796-816), against the CSP at card:208 | The static-serving contract is incomplete in three ways that criterion 13's set equality cannot be run against: no `Content-Type` is specified for any static asset (only for `GET /`), though the criterion asserts the UI renders; the file that must define `window.__resources` is absent from the manifest and both expected sets, and the card's own CSP (`script-src 'self' 'unsafe-eval'`, no nonce) forbids the inline alternative; and task 14 names the phosphor font files as required but omits the equivalent second hop for Inter, whose Google Fonts stylesheet resolves to `fonts.gstatic.com` woff2 files. |
| 2 | `writing-specs/ambiguous-requirement` | `skills/writing-specs/SKILL.md` | Maintain the spec with production rigor; drift causes hallucination — a requirement must not be readable two ways | §Security, bounded-lifetime bullet (card:478-480) vs. `docs/decisions/0024-the-control-server-must-be-accountable.md:38-41` | The card says the parent-death check runs "on the same timer that drives the idle check" while ADR 0024 — which the card names as authoritative for this decision — says it "gets its own interval rather than riding the 30-minute idle timer" and records that exact phrasing as a first-draft error it corrected, so the two authoritative documents now disagree on the control's tick length. |
| 3 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Handle errors explicitly, never swallow them; validate all input at system boundaries | §Security bind bullet (card:446), port allocation (card:544), task 8 (card:732-741) | The server's first boundary has no stated failure behaviour for a port already in use, which `core-conduct`'s parallel-agent invariants make a normal case on a fixed port, and the resulting state is misleading rather than clean — the second launch dies while the browser still reaches the first server holding a different in-memory token, so every button returns the deliberately collapsed `403`. |

**`writing-specs/api-contracts` is a recurrence of the class closed at round 5** (cited rounds 1-4 for
the manifest being a `grep` rather than a table). The table fixed *how* the manifest is derived; this
round finds the table itself short three entries and one field. **`core-conduct/explicit-error-handling`
was cited at round 5 and closed at round 6** in a different territory (`500 asset_unreadable`); this is
a new instance of the same rule, not the old one reopened.

### Notes

- **Round 6's violation is closed and so is its class.** Set equality is the right instrument and both
  tables are correct as far as they are enumerated. Verified by hand: `Task Tracker.dc.html` lines
  6, 11, 12, 15, 16 are the five parser-inserted requests; `tracker-data-fallback.js:19` is the sixth
  via `document.write`, gated by the early return at line 16.
- **The `_ds/` two-file enumeration is still correct**, and the three excluded files really are
  unrequested — `find _ds -type f` returns exactly five: `styles.css` and `_ds_bundle.js` (both on the
  manifest) plus `_ds_manifest.json`, `_adherence.oxlintrc.json` and `readme.md` (correctly off it).
  `nocturne.css`'s exclusion remains correct: only the unserved Directions file loads it.
  `_ds_bundle.js` contains no `url(`, no `http`, no `fetch` — it adds no further requests.
- **Defining `window.__resources` has a side effect the card does not mention.** `support.js:158-163`
  issues a second `GET /` (`fetch(location.href)`, a template refresh) **only when
  `window.__resources` is falsy**. So task 14 suppresses it, which is what makes round 6's "out of
  scope" call correct — after task 14 there is exactly one `GET /`, matching criterion 13's tables. But
  the card presents the `__resources` hook as resolving scripts "with no edit to vendored code" and
  does not note that it also disables a runtime behaviour. Benign; worth one clause.
- **`base-uri`/`form-action` — downgrading this from a standing note to closed-as-low-value.** I
  checked the actual attack surface: `grep -c '<form'` on the served page is **0**, so `form-action`
  guards nothing, and a `<base>`-tag redirect would send relative fetches to a foreign origin where
  `default-src`/`script-src 'self'` already blocks them. Two tokens of defence-in-depth, not a gap.
- **Static-error body shape (standing note) will be resolved by violation 1.** The
  `{"ok": false, "error": "<code>"}` envelope is introduced under `POST /command` but the `404`/`405`/
  `500` rows govern static `GET`s too, so a browser receives JSON for `/favicon.ico`. Harmless, and
  specifying `Content-Type` per response class closes the ambiguity in the same edit.
- **CSP vs. the vendored page's inline attributes — unverified, and I am not claiming either way.**
  `Task Tracker.dc.html` carries one `<script type="text/x-dc">` data block (line 297) and many
  `onClick="{{ … }}"` content attributes. The data block is a non-executable script type, so CSP does
  not gate it. The `onClick` attributes are template syntax the DS runtime consumes, but the browser
  parses them as inline event handlers, which `script-src` without `'unsafe-inline'` refuses to run;
  whether Chrome compiles them before the runtime replaces the `<x-dc>` subtree I did not test.
  Criterion 13's "the UI renders" clause is what would catch it — recommend the operator reads the
  console during that run, not only the request list.
- **The `405` row is readable two ways** (card:323): "Any method other than `GET` on `/` or on a
  static-closure path, or `POST`/`OPTIONS` on `/command`" can parse as `405`-ing the only working
  route. Criterion 12 and card:334 resolve it unambiguously, so not cited — but it is a five-word fix.
- **`_ds/nocturne-<uuid>/` is never expanded in the card.** The real value is
  `73641b21-c7ad-488a-8264-a28262dfe83e`; the "explicit list" therefore still needs one `ls`. Consistent
  with the card's derivations discipline, so acceptable.
- **Claims re-verified against source this round, all exact:** the six remote assets across nine
  reference sites (react 1, react-dom 1, babel 1, phosphor regular 2, phosphor fill 2, Google Fonts 2)
  ✓; `new Function` in `support.js` is exactly **2** ✓; `REACT_URL`/`REACT_DOM_URL`/`BABEL_URL` at
  `support.js:1143/1145/1147` each carry a `sha384` SRI ✓; `cdnScriptFor` behaves as described (and
  drops `integrity` when a local `src` is substituted, which is correct) ✓; ADRs 0022, 0023, 0024 all
  exist ✓; `analyze.py` is **792** lines ✓.
- **`analyze.py` at 792 lines has eight lines of headroom** under `core-conduct`'s 800 hard max, and
  both tasks that write it (3 and 5) are complete, so that is its final size. The card's posture —
  split named (`git_facts.py`), explicitly not scheduled, human-owned — is correct and not a violation.
  But "raise it if the file grows again" has effectively already fired: the next edit breaches the cap.
- **Gherkin shape**, seventh round running: several criteria fold `When` into `Given`. Still not cited.

### Waivers

None. No violation has ever been waived for this spec.

---

## Round 8 — 2026-08-10T02:44:28Z — **FAIL** (2 violations)

- **Spec:** `docs/features/tracking-feature-state.md` (blob `566da22a005bf0edc466ba4a836e2740d24c52e4`, 1080 lines)
- **Branch:** `feat/tracking-feature-state` @ `ca3e07943756df628a02bd636069e4ef36a7bef0`
- **Rule sources read:** `rules/core-conduct.md`, `rules/gates.md`, `CLAUDE.md`,
  `skills/writing-specs/SKILL.md`, `skills/writing-secure-code/SKILL.md`
  (no `.claude/project-standards.md` in this repo)
- Round 7's three: **2 closed, 1 re-cited on the surface one hop past where it was fixed.**
  1 new instance of a previously-cited rule, on the control this revision introduced. Waived: none, ever.

### Summary in plain language

**Two of round 7's three are properly closed, and I checked them against the sources rather than
against the card's own account of itself.**

The ADR contradiction is gone. `docs/decisions/0024-…:38-41` says the parent-death check gets "its own
`5`-second poll (`TASK_TRACKER_POLL_SECS`, minimum 1s, may not be disabled)" and records "on the idle
timer" as a first-draft error; the card now says exactly that and names the ADR as authoritative in the
same sentence. `writing-specs/ambiguous-requirement` is **closed**.

The bind boundary is gone too. `EADDRINUSE` is a startup abort naming the port, explicitly with no
probing for a free one, any other bind error aborts naming the `errno`, and task 9 asserts it the way
that matters — second server exits non-zero having served nothing, *first server still answers with its
original token*. The reasoning for refusing to fall back (two servers, browser on the first, token from
the second, every button returning the deliberately collapsed `403`) is the right reasoning. That
instance is **closed**.

Every fresh factual claim in this revision reproduces. `support.js` really is the page's first script,
at `Task Tracker.dc.html:6`, with nothing above it — so `vendor-resources.js` genuinely has to load
ahead of it. The CSP genuinely carries no nonce and no `'unsafe-inline'` in `script-src`, so the
inline-block alternative really is forbidden by the card's own policy. I fetched the Google Fonts
stylesheet with the browser UA the card specifies: **28** woff2 URLs, `4 cyrillic, 4 cyrillic-ext,
4 greek, 4 greek-ext, 4 latin, 4 latin-ext, 4 vietnamese` — 7 subsets × 4 weights, and `latin` is
exactly 4 of them. `vendor-resources.js` appears in all five places a reader would look (manifest row,
§Design 3 prose, §Security vendoring mechanism, criterion 13 run (a), task 14) and contradicts itself
nowhere. All four re-checkable toolchain pins match this host exactly (`3.9.6`, `0.11.28`,
`0.64.20 (100) [14e3400b9]`, `v26.5.0`). `tracker-data-fallback.js:16`/`:19` are as described.

**The static contract is still not completable, and it failed at the one hop the card fixed for Inter
and not for phosphor.** §Security's own ⚠️ names both second hops in one sentence — "the phosphor icon
font files, and Inter's **28** `fonts.gstatic.com` woff2 URLs" — then task 14 gives Inter a measured
count, a reproducing command and an explicit `latin`-only scope decision, and gives phosphor the same
one-line instruction it had before: "the icon font files they reference must come along". I fetched
both phosphor stylesheets. Each declares **four** `src` formats for its family:

```
url("./Phosphor.woff2") format("woff2"), url("./Phosphor.woff") format("woff"),
url("./Phosphor.ttf") format("truetype"), url("./Phosphor.svg#Phosphor") format("svg")
```

and `fill/style.css` is the same shape for `Phosphor-Fill`. So the literal instruction adds **eight**
files, and two independent rules in this card break on them:

1. **Six of the eight carry `.woff`, `.ttf` or `.svg`,** none of which is in the fixed extension map
   (`.js`, `.css`, `.html`, `.woff2`). The card's rule for that case is not a `500` — it is
   "**aborts at startup**". Built to the card as written, the server does not start.
2. **A browser fetches exactly one format from a `src:` list** — the first it supports, i.e. the
   woff2. So six vendored files are never requested, while criterion 13's expected set says
   "each of task 14's vendored assets | `200`". The pass condition is set equality. **A correct
   implementation fails criterion 13.** That is verbatim the round-6 shape ("a correctly built server
   cannot pass criterion 13 run (a)"), relocated from the store state to the vendored rows. The same
   hazard applies to Inter: `@font-face` files are fetched lazily per weight actually rendered, so
   four vendored latin weights are not four guaranteed requests.

Two smaller members of the same gap: the rewritten Inter `@import` has no stated target — a served
`inter.css` (a new manifest row, needing a `Content-Type`) or `@font-face` blocks inlined into
`styles.css` are different servers — and the vendored assets have no stated paths, so the row that
completes the manifest cannot be predicted, only discovered.

**The second finding is the newest control in the card, and it arrived the way the audit log, the
parent-death check and `asset_unreadable` each arrived: described in prose, absent from every table.**
Task 1's fourth probe was the important one — a ref that resolved, at exit 0, with `OK` on stdout, to
the **wrong live Claude session**. The card draws the right conclusion and promotes send-time
**identity** confirmation to the primary control, demoting criterion 9's re-resolution to defence in
depth. But that control introduces a new subprocess boundary — reading the target surface — and it has:

- **no status row.** The table's `409 unresolved_surface` is defined as "ref did not re-resolve"; the
  failure this control exists for is a ref that *does* re-resolve. There is no code for it.
- **no audit `reason` value.** The enumeration is `bad_token, unknown_id, origin_mismatch,
  host_mismatch, malformed, too_large, unsupported_media_type, unresolved_surface, send_failed,
  reanalyze_failed, -`. The log's stated purpose is letting an operator tell one refusal from another,
  and the single most important refusal this card added cannot be written down.
- **no behaviour when the read itself fails** — non-zero exit, or a timeout (`cmux send` has a
  5-second one; the read has none). The card documents at line 456 that `read-screen` exits 1 against
  an `agent-session` surface, so this is a case it has already met and not routed.
- **no comparison basis.** "Verify it is the intended session" does not say what is compared, nor
  where the intended target comes from. §Verification records that `cmux identify` returned
  `surface_ref: null` on this host, which removes the obvious mechanism; §"Injection route" mentions
  `$CMUX_SURFACE_ID` is inherited but only as the *default* an omitted `--surface` falls back to.
  Task 9 says "assert the identity confirmation itself" — with no definition, two implementers write
  two different checks and both pass their own test.

**On card size, asked directly: no rule is breached and I am not citing it, for the third round
running.** `rules/gates.md` makes `docs/features/<name>.md` the default and the `.spec.md` split a
**MAY**; `core-conduct`'s 400/800 limit sits under **Code Style** and governs code files. But 1080
lines is +147 this round and the sixth consecutive rise, and I now put the round-attribution and
forensic-narrative content near ~130 lines. The author's reasoning for keeping the two `grep`-scope
warnings and the `rename-tab`-vs-`send` distinction beside the code that would reproduce them is
sound and I would keep those. §Revision history (20 lines narrating a deletion) and the round
attributions inside criterion 13 and §Design 3 are a third copy of what these verdict files and the
commit messages already hold. `writing-specs` calls the human review gate "the whole point" — the
argument for trimming is that a reviewer must finish the document, not that the document is illegal.
Recommendation unchanged from round 7: ~60 lines, no buildable content lost.

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `writing-specs/api-contracts` | `skills/writing-specs/SKILL.md` | Database schemas and API contracts — give the agent the real interface boundaries instead of letting it improvise shapes | §Design 3 static manifest + fixed extension map (card:256-275), criterion 13 runs (a)/(b) (card:741-772), task 14 phosphor bullet (card:921-922), §Security asset table ⚠️ (card:618-623) | The phosphor second hop is still unenumerated while Inter's now is: each `@phosphor-icons/web@2.1.1` stylesheet declares four `src` formats (`.woff2`, `.woff`, `.ttf`, `.svg` — verified live 2026-08-10), so task 14's literal "the icon font files they reference must come along" adds eight rows, six of them carrying extensions absent from the fixed `Content-Type` map — which the card says **aborts the server at startup** — and six of them never requested by a browser, which fails criterion 13's set equality against "each of task 14's vendored assets → `200`" for a *correct* implementation; the rewritten Inter `@import`'s target file and the vendored assets' served paths are likewise unnamed, so the manifest still cannot be completed before the work rather than during it. |
| 2 | `core-conduct/explicit-error-handling` | `rules/core-conduct.md` | Handle errors explicitly, never swallow them; validate all input at system boundaries | §"Injection route" identity paragraph (card:441-451), §Security "Confirm the target surface at send time" (card:627-628), §Design 3 status table (card:339-349) and audit `reason` enumeration (card:383-384), task 8 (card:830-832), task 9 (card:867-875) | Send-time identity confirmation — promoted this revision to the primary safety control — introduces a new subprocess boundary with no stated failure behaviour: no status row (`409 unresolved_surface` covers a ref that did **not** resolve, not one that resolves to the wrong session), no `reason` value so the log cannot record this card's most important refusal, no timeout and no stated outcome when the read exits non-zero (which the card itself documents happens against an `agent-session` surface), and no definition of what "the intended session" is compared against — the mechanism the card's own §Verification rules out (`cmux identify` returning `surface_ref: null`) being the obvious one. |

**Recurrence, stated plainly for the escalation decision.** Both ids are second consecutive citations,
and neither is the round-7 instance reopened:

- `writing-specs/api-contracts` — cited rounds 1-4 (manifest derived by `grep`), closed round 5,
  re-cited round 7 (no `Content-Type`, missing `__resources` file, Inter's second hop), all three of
  which are **fixed and verified fixed**. This round is the *fourth* distinct instance of one class:
  the static-asset contract is complete for everything the page requests today and incomplete for
  everything task 14 will add. The territory is identical, so the id is reused.
- `core-conduct/explicit-error-handling` — cited round 5 (`asset_unreadable`), closed round 6;
  cited round 7 (bind), **closed this round**; cited now on the send-path identity check. Three
  instances, three different boundaries, one class: a control lands in prose in the round that
  introduces it and reaches the tables a round later. Id reused for that class, per the round-7
  precedent in this file.

Closed this round and not re-cited: `writing-specs/ambiguous-requirement` (round 7 — card now defers
to ADR 0024 explicitly and the wording matches). Still closed: `writing-specs/good-bad-edge-cases`
(round 7), `writing-specs/pinned-versions` (round 6), `writing-secure-code/csp` (round 4),
`core-conduct/secrets-not-client-side`, `core-conduct/no-absolute-paths`,
`writing-specs/no-placeholders`, `writing-specs/diagrams` (rounds 1-2).

### Notes

- **The round-7 UNVERIFIED CSP note is now resolved, and it resolves benign.** `support.js:318` maps
  `onclick → onClick` inside `encodeCase`, the `<x-dc>` subtree is lifted via `template.innerHTML`
  (`support.js:468-470`) and compiled through Babel into `React.createElement` calls
  (`support.js:1211-1218`), so the handlers the user actually clicks are React props, not DOM inline
  handlers — `script-src` without `'unsafe-inline'` does not gate them. What the browser *will* do is
  refuse to compile the literal `onClick="{{ … }}"` content attributes it parsed, emitting CSP
  violations to the console for markup that is template source and is replaced before it matters
  (and `{{ t.toggle }}` is not valid JS anyway, so nothing is lost). **Worth one clause in the card:**
  criterion 13's operator will see red console errors on a passing run, and an unexplained console
  error is how a correct run gets reported as a failure.
- **`base-uri`/`form-action` — reconfirmed closed as low-value**, on the same evidence as round 7: no
  `<form>` on the served page, and a `<base>` redirect sends relative fetches to an origin
  `default-src`/`script-src 'self'` already blocks.
- **Static-error body shape (standing note) is now half-resolved.** Violation 1's `Content-Type` work
  landed for the success path; the `404`/`405`/`500` rows still govern static `GET`s, so
  `/favicon.ico` receives a JSON envelope. Harmless, one sentence to state.
- **Set equality has a lazy-fetch assumption the card should state once**, beyond violation 1: font
  files are requested per weight/format actually rendered, so any expected-set row for a font is a
  claim about rendering, not about vendoring. Naming that is what stops the next round rediscovering
  it from the other side.
- **`.svg` deserves a decision, not a map entry.** If phosphor's SVG fallback is vendored and served
  from the token-bearing origin, `image/svg+xml` from `'self'` is script-capable markup on the origin
  that holds the credential. Dropping the `.svg` and `.ttf` sources (rewriting the `src:` list to
  woff2-only) is the smaller-surface answer and matches the Inter `latin`-only precedent.
- **Claims re-verified against source this round, all exact:** `support.js` is the first script,
  `Task Tracker.dc.html:6` ✓; `_ds/nocturne-73641b21-c7ad-488a-8264-a28262dfe83e/` is the single
  `_ds` directory, `styles.css` + `_ds_bundle.js` requested at lines 11-12 ✓; CSP has no nonce and no
  `'unsafe-inline'` in `script-src` ✓; Inter = 28 woff2, 7 subsets × 4 weights, `latin` = 4 ✓;
  `tracker-data-fallback.js:16` early return, `:19` `document.write` of `tracker-data.sample.js` ✓;
  `window.TRACKER_DATA_SOURCE = 'sample'` at `:18`, matching criterion 13(a) ✓; ADR 0024's 5-second
  own-poll wording ✓; Python `3.9.6`, `uv 0.11.28`, `cmux 0.64.20 (100) [14e3400b9]`, `node v26.5.0` ✓.
- **`analyze.py` remains at 792 lines**, eight under the hard max, split named and explicitly
  unscheduled as a human-owned call. Correct posture, unchanged.
- **Gherkin shape**, eighth round running: several criteria fold `When` into `Given`. Still not cited.

### Waivers

None. No violation has ever been waived for this spec.

---

## Round 9 — 2026-08-10 — **PASS** (terminal round, user-authorised)

`head_sha` `4775afd4e09392415a074a4c2dde6e34db6f0521` · branch `feat/tracking-feature-state` ·
spec blob `716548b733199ec75719163774aed75b389a938e` · confidence **high**

### Layman summary

Both problems the last round found are genuinely fixed, and I checked them by re-running the
measurements myself rather than reading the card's word for it.

The first problem was that the spec's own pass/fail test was impossible to pass. It told the
implementer to bring along "the icon font files" a stylesheet references, and left the list of those
files blank for a later task to fill in — so a developer who followed the instruction exactly would
ship eight font files when the test only expected two, and would fail. The spec now names all nine
files up front, and makes an explicit decision to ship only the modern `.woff2` format. I fetched the
real stylesheets to check: the icon stylesheet does list four formats in one line as claimed, and the
Google Fonts stylesheet really does contain 28 references that resolve to only 7 actual files — the
card's earlier "4 files, one per weight" was wrong and the corrected "one file" is right. I then
diffed the spec's two copies of the file list against each other: identical.

The second problem was the safety control that stops the server typing into the wrong Claude session.
Last round it said "confirm the target" without saying what the target was compared *against*, what
happens if the check errors, or how long to wait. The fix is better than a patch — it deletes the
guesswork entirely. The server now takes the session's own ID from the environment it was launched
in, rather than trying to work out which session it belongs to. I confirmed that environment variable
is set and holds the right kind of value. Every failure now has a stated outcome: three ways the
server refuses to even start, three ways a send is refused, each with an HTTP code, a log reason, and
a matching test in the same task that builds it. Critically, "I couldn't check" is treated as "refuse",
not "probably fine" — which is the failure that would otherwise be silent.

The card grew again (1080 → 1204 lines), the seventh straight round. I am not scoring that a
violation, and I say why below rather than leaving it implied.

### Violations

**None.** Both persistent ids from round 8 are closed on the merits.

| Prior id | Status | Evidence I re-measured |
|---|---|---|
| `writing-specs/api-contracts` | **closed** | Phosphor `regular/style.css`: exactly 1 `@font-face`, 4 `src` formats (`./Phosphor.woff2`, `.woff`, `.ttf`, `.svg#Phosphor`) — the card's "delete the three non-woff2 `src` entries so the relative `./` resolves unchanged" is exactly right. Inter: 28 `woff2` references / **7** distinct files / 28 `@font-face` blocks, and the `latin` subset is **one** file shared by all four weights. `diff` of the §Design 3 manifest (16 rows) against criterion 13 run (a) (18 rows) minus `/` and `/favicon.ico`: **identical**. All manifest extensions (`.js`/`.css`/`.woff2`) present in the fixed map. Six remote assets across nine reference sites; phosphor `<link>`s at `*.dc.html:13-14` in **both** files; Inter `@import` at line 2 of **both** `nocturne.css` and `_ds/nocturne-<uuid>/styles.css`. A correctly built server now passes criterion 13. |
| `core-conduct/explicit-error-handling` | **closed** | The basis of comparison now exists: `$CMUX_SURFACE_ID` verified live in this environment as a bare UUID (`7C0A4E33-…`), inherited rather than inferred. Three startup aborts (unset/empty; `read-screen` non-zero, which folds in the `agent-session` case; probe >5s), each naming its cause and serving nothing. Three send-time outcomes tabulated with wire code + audit `reason` + `sent` value; `confirm_failed`/`confirm_timeout` added to the `reason` enumeration (card:400) and to the `502` row (card:364). Could-not-confirm is **refused**, not assumed fine (card:700-703) — the one branch whose absence would have been silent. Six matching assertions in task 9 (card:966-977), in the same task that builds the control. |

### Notes (non-blocking)

- **Card growth, scored plainly: not a violation, and here is the honest arithmetic.** 1080 → 1204,
  a seventh consecutive rise. `writing-specs` §"Tokenization Is a Hard Constraint" names *redundant
  `Given/When/Then` blocks* as the offender it is aimed at; this growth is ~180 lines of two
  enumerated **contracts** — the nine `vendor/` rows written into both lists, and the two
  surface-check tables — which were the literal substance of both cited violations. Neither is
  boilerplate, and removing either re-opens a violation. Against that, ~55 lines of round-forensics
  prose came out. Net verdict: length earned. **But the trend now warrants a human call rather than
  another judge round**: `rules/gates.md`'s `.spec.md` split is a MAY keyed to "the checklist file
  stops reading comfortably in one pass", and at 1204 lines that threshold is arguably met. The
  standing trim candidate is unchanged — the ⚠️ paragraphs narrating how prior rounds got things
  wrong (roughly card:240-251, 272-279, 302-325, 802-808, 835-859) are ~120 lines of forensics that
  a `.spec.md` half could carry.
- **Gherkin shape — DROPPED, permanently, with reasoning; future rounds should not carry it.**
  Criteria 2, 3, 4 and 5 fold `When` into `Given`. I decline to cite it, and this is a resolution
  rather than another deferral: in all four the trigger is unambiguous from context (the analyzer
  running; the re-analysis; the interrupted write, whose `When` sits in its own assert clause), so
  the rule's stated purpose — "the format exposes the gap while it is still cheap to close" — is
  already served. `writing-specs` simultaneously names redundant `Given/When/Then` as the primary
  token offender, so enforcing the literal shape here would trade tokens for zero correctness gain.
  Eight rounds of carrying it as a note was the wrong disposition; it is closed.
- **CSP `onClick` — now VERIFIED (round 8 left it inferred), and the card should say one sentence.**
  `<x-dc>` at `Task Tracker.dc.html:9` is a **live element in the body**, not a
  `<script type="text/x-dc">` — that type appears only at line 297, on a nested props block — so the
  HTML parser does parse the 20 `onClick` attributes into `onclick` inline handlers on real DOM.
  Under this card's CSP (no `'unsafe-inline'` in `script-src`) Chrome refuses them and logs console
  violations. `support.js:318` maps `onclick → onClick` in `encodeCase` and the subtree is lifted via
  `template.innerHTML` (`:468-470`) and compiled through Babel (`:1211`), so the *live* handlers are
  React props and the UI works — the violations are console noise only. Recommend one clause in
  criterion 13 so the operator does not report a passing run as a failure.
- **Host-mismatch has an audit `reason` but no wire status row.** Card:231 states the behaviour
  ("Reject any request whose `Host` header is not `127.0.0.1:<port>`") and card:399 lists
  `host_mismatch` among audit reasons, but the §Design 3 `403 forbidden` row enumerates a **closed**
  list of three causes that does not include it. `403` is safely inferable from the neighbouring
  reasons; the gap is that the table claims completeness. One-word fix, not cited.
- **`reanalyze` is the one subprocess boundary the tightening pass did not reach.** `cmux send`,
  `read-screen` and `cmux tree` each carry an explicit 5-second bound; the analyzer invoked by
  `reanalyze` carries none, so a wedged `git` (plausible in a repo that deliberately runs parallel
  agents across worktrees) hangs the request. The card's own standard argues for a bound —
  "never awaited indefinitely" (card:375) and "an unbounded probe is a server that neither starts nor
  reports why" (card:685). Low materiality: a hang is visible to the operator, not silent, which is
  why it is a note and not a citation.
- **`.html` in the fixed extension map is unused.** No manifest row is `.html` (`GET /` sets
  `text/html` directly at card:201), so "those four extensions cover every row above with none left
  over" (card:290) holds in one direction only. Harmless.
- **Inter `unicode-range` is unstated.** Task 14 (card:1074-1075) says to write four `@font-face`
  blocks pointing at the single latin file, but omits `unicode-range`. Without it the face claims
  every codepoint and non-Latin glyphs render as tofu rather than "falling back to the system stack",
  which is the outcome card:1071 says to expect. Google's own latin block — which the card's `curl`
  reproducer already prints — carries the range verbatim.
- **Round 8's own note was wrong where the card was wrong.** It recorded "Inter = 28 woff2, 7 subsets
  × 4 weights, `latin` = 4 ✓" — the `latin = 4` half repeated the card's error rather than catching
  it. `sort -u` on the live stylesheet returns **one** latin file. Recorded because it is this
  card's documented failure species (a stored result reproduced from the artifact under review)
  reappearing inside the judge's own audit trail.
- **Claims re-verified live today, all exact:** `support.js` first script at `Task Tracker.dc.html:6`;
  single `_ds` directory `nocturne-73641b21-c7ad-488a-8264-a28262dfe83e`; `analyze.py` at **792**
  lines, eight under the hard max, split named and explicitly unscheduled as a human-owned call —
  correct posture, unchanged; no `TBD`/`TODO`/`FIXME`/placeholder anywhere in the card; no absolute
  path (`/Users/`, `/home/`) committed.
- **Spec path:** `docs/features/` rather than `writing-specs`' `docs/superpowers/specs/`. Not cited —
  `rules/gates.md`'s one-canonical-file discipline is the repo layer and takes precedence on conflict.

### Waivers

**None.** No violation has been waived for this spec in any of the nine rounds, and none is needed:
round 9 passes clean, so the waiver conversation the user pre-authorised does not arise.

---

## Round 10 — 2026-08-10T22:17:22Z — **FAIL** (3 violations)

`head_sha` `7be4aec8b2337bf1b67190e16f96a72e5046cd45` · branch `feat/tracking-feature-state` ·
spec blobs `772e5fc1f8d35a4af11dcbfb90212fb1714d7954` (`.md`) /
`e41e1f8bf2ad35be5e4731f1c526acef535953dd` (`.spec.md`) · confidence **high**

First round judging the pair as one document, and a fresh judgement of the current text rather than a
re-litigation. Round 9's two closed ids stay closed — I checked both territories and neither reopened.
All three findings below are new, and **two were introduced by the split itself**. (A first round-10
run died on a spend limit before writing anything; this is the only round-10 verdict.)

### Layman summary

The card was cut into two files so a session no longer has to load 1,204 lines at start-up. That part
worked — start-up reading is now 326 lines. But the cut was made in a shape this repo has a *live
hook* to forbid, and the reasoning written down to justify the cut is factually wrong about the tool
it names.

**One.** This repo already allows a feature to live in two files, but only on one condition: the two
halves must list the same tasks, so they cannot silently drift apart. That condition is not advice —
it is enforced by `hooks/feature-sync-guard.sh`, which is registered and running in the live settings
file, and which blocks any `git commit` that would record a mismatched pair. This split put all
fourteen tasks in one half and none in the other. I ran the exact comparison the hook runs: it exits
3 and reports all fourteen ids missing from the spec half, which means the hook exits 2 and blocks.
The repo's only other split pair, `memory-system-split`, carries the same task ids in both halves and
compares clean — that is the house shape, and this split did the opposite of it. There is a second
symptom that needs no hook: the analyzer this very feature builds already flags its own card in
`questions[]` as *"Which half of `tracking-feature-state` is right?"*.

**Two.** Both halves explain that the spec half is safe from being double-counted because it "carries
no `phase:` key, so it is not a card and the analyzer skips it". I built a throwaway repo and ran the
shipped analyzer against it. A feature file with no frontmatter at all is **not** skipped — it comes
out in `features[]` like any other card. What actually excludes the spec half is its *filename*: the
analyzer drops `*.spec.md` by suffix. So the stated safety mechanism is not the real one, and the
card's own acceptance criterion 1 describes a rule the code it says is already built and tested does
not implement. This is the card's signature defect — a confident claim about behaviour that nobody
re-ran — sitting inside the paragraph that justifies this round's biggest change.

**Three.** The card is unusually good at hunting down "controls written in prose that nothing tests",
and this round closed four of them. One is left, one field over from the one just fixed. The audit
log records `sent=yes|no|unknown`, and the card says `unknown` — meaning the keystroke command was
actually launched and then failed or timed out — is "the value that keeps [the log] honest", covering
"the worst failure this feature has". No acceptance criterion and no task-9 assertion ever produces
it: the only failing-send test drives the *pre-send* check, which the card fixes at `sent=no`.

Nothing security-relevant regressed, no content was lost in the move, and every cross-file `§`
reference resolves. The fixes are small: give the spec half the matching task ids (or fold back),
correct one sentence about how the analyzer excludes files, and add one test.

### Violations

| id | Rule source | Where | Why | Evidence I ran |
|---|---|---|---|---|
| `gates/split-half-sync` | `rules/gates.md` — one-canonical-file discipline: "A **synced** `<name>.spec.md` half **MAY** be split off"; the sync condition is encoded in `hooks/lib/feature_tasks.py:compare` and the registered Tier-1 `hooks/feature-sync-guard.sh` | the split itself — `tracking-feature-state.spec.md` (zero task lines) against `tracking-feature-state.md` §Tasks (ids 1–14) | The pair shape is permitted only while the two halves' task lists cannot silently diverge, and this pair's lists disagree on every id, so a registered blocking hook now stands between this card and every future commit. | `python3 hooks/lib/feature_tasks.py docs/features/tracking-feature-state.md docs/features/tracking-feature-state.spec.md tracking-feature-state` → **exit 3**, "in `tracking-feature-state.md` but missing from `tracking-feature-state.spec.md`: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14" (`feature-sync-guard.sh:204-226` turns status 3 into exit 2 + block). `$HOME/.claude/hooks/feature-sync-guard.sh` exists and is **REGISTERED LIVE** in `$HOME/.claude/settings.json` (`PreToolUse`/`Bash`); on `main` since `7f9bb6f`. The same call inside `analyze.py:568-577` already emits *"Which half of `tracking-feature-state` is right?"* when the analyzer is run against this worktree. Contrast `memory-system-split`: task ids `- [x] 1 …`, `- [x] 11 …` present in **both** halves, compare **exit 0**. Neither half mentions `feature-sync-guard`, `FEATURE_SYNC_EXEMPT`, or the sync contract anywhere, so this is unacknowledged rather than an accepted trade. |
| `writing-specs/spec-code-drift` | `skills/writing-specs/SKILL.md` — "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists. Keeping them aligned is not tidiness; it is correctness." | criterion 1's parenthetical; §Design 1 failure table row "Frontmatter malformed or unparseable"; the header note at `.md:9-12` and the `.spec.md` HTML comment | Both halves stake the split's no-double-count guarantee on a rule the shipped analyzer does not implement, and the criterion stating that rule is already ticked `[x]` as closed by tasks 3–4. | Fixture repo `/tmp/cj10fix` with `docs/features/orphan-nophase.md` (no frontmatter at all) → `python3 task-tracker/analyze.py` emits `features: [('orphan-nophase', '0/1', …), ('real-card', '1/2', …)]` — the phase-less file **is** a card, not skipped; it only raises a question. The actual exclusion is by filename: `SPEC_SUFFIX = ".spec.md"` (`analyze.py:36`) filtered in `_card_paths` (`analyze.py:192`), present since the analyzer's first commit `37a8e38`, and the same filename convention is used by `phase-guard.sh:372`. So adding a `phase:` key to the spec half would **not** make it a second card, and no test in `test_analyze.py` covers a card without a `phase:` key (the fixture helper at `test_analyze.py:94` always writes one). |
| `writing-specs/good-bad-edge-cases` | `skills/writing-specs/SKILL.md` — "state explicitly what correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit, the agent infers — and inference is where the defects come from." | §Design 3 status table `502 send_failed` row + §"Audit log" `sent=<yes\|no\|unknown>`, against task 9's assertion list and criterion 12 | The one path that yields `sent=unknown` — a `cmux send` that was actually invoked and then exited non-zero or hit its 5-second timeout — has no criterion and no task-9 assertion, so the value the card calls the record of "the worst failure this feature has" is produced by nothing. | `grep -n 'sent=' docs/features/*.md`: the only prescribed assertions are `sent=yes` (criterion 12), `sent=no` (criterion 12's `reanalyze`, task 9's two confirm failures). Task 9's only `502` driver is the **pre-send** confirmation failure, which §Security fixes at `sent=no`; `reason=send_failed` is likewise never driven. The card's own precedent forbids leaning on "each status code" here — it already rules that the two `500` rows are "satisfied by neither on its own", and the `502` row carries two causes with different `sent` values. Same species as the four controls closed this round, one field over from the `reason` enum that was just fixed. |

### Waivers

**None.** No violation has been waived for this spec in any of the ten rounds, and the waived-id list
is still empty. Round 9's two long-running ids (`writing-specs/api-contracts`,
`core-conduct/explicit-error-handling`) were closed on the merits and remain closed — I checked both
territories in the current text and neither has reopened.

### Notes (non-blocking)

- **`§Verification` staying in the `.md` is the right call** and is *not* what trips the sync guard —
  the guard compares task ids only. `gates.md` assigns the `.md` "frontmatter + task list"; a
  measurement record is neither that nor spec/Gherkin detail, and task 13 writes into it during
  implementation, when the phase gate forbids editing a spec. Keep it where it is.
- **Nothing was lost in the move.** Of the 1,204 lines at `4775afd`, 11 are absent from the union of
  the two halves at `3ca4daf`, and all 11 are lines that same commit deliberately rewrote (the `403`
  row, the `reanalyze` row, the audit-log format, task 9's `asset_unreadable` bullet, task 14's
  subset paragraph). Zero unintended loss.
- **Every cross-file reference resolves.** All `§Design 1–4`, `§Security`, `§"Injection route"`,
  `§"Audit log"` (a `####` heading), `§Out of scope`, `§Toolchain` map to headings in the spec half;
  `§Verification` maps to the `.md`. No dangling pointer in either direction.
- **Duplication across halves is small and mostly well-handled.** Only two substantive lines appear
  verbatim in both files: the wide `grep -rn 'https\?://'` derivation and the canonical
  `uv run --with pytest==9.1.1 …` invocation — and the second names `§Toolchain` authoritative on
  disagreement, which is the correct way to duplicate. The governing "no pinned counts / check your
  derivation's scope" preamble is restated in both halves in *different words* and has already
  drifted slightly (the `.md` adds "once inside a judge's own verdict"; the spec half omits it).
  Acceptable for a two-reader document, but that paragraph is the drift surface to watch.
- **The `.md` preamble contradicts its own `§Verification`.** "no count, test total or phase tally is
  pinned anywhere" is falsified ~270 lines later by "It reported **53 passed** on 2026-08-09" and by
  task 13's mandate to record counts. The spec half's phrasing carves out exactly that exception
  ("measurements that must be recorded … are stamped with their date and their reproducing command").
  Copy the spec half's sentence into the `.md`.
- **Task 9's `reason` bijection instruction is readable two ways.** "require every value to be
  reachable" suggests a runtime exercise; the spec half restates it as "every row has a value, every
  value has a row" — a static table↔enum check. Under the static reading `host_mismatch`,
  `send_failed` and both `confirm_*` values are never exercised. One clarifying clause fixes it, and
  the runtime reading would also close most of violation 3.
- **Criterion 14's idle clause implies a ≥60-second test.** It says "drive both with short overrides",
  while §Security fixes `TASK_TRACKER_IDLE_SECS` at a 60s minimum that "may not be disabled". Not a
  contradiction (60s ≪ 30 min), but state the expected runtime so nobody weakens the minimum to make
  the suite fast.
- **Extension map still carries `.html` with no manifest row** (`GET /` sets `text/html` directly), so
  "those four extensions cover every row above with none left over" holds in one direction only.
  Same harmless imprecision recorded in round 9; unchanged.
- **Spec path** is `docs/features/` rather than `writing-specs`' `docs/superpowers/specs/`. Not cited —
  `rules/gates.md`'s one-canonical-file discipline is the repo layer and takes precedence.
- **Security territory re-checked** (the design touches external input, shell execution, a localhost
  server and a credential): no request data reaches a command line (allowlist id only; `--surface`
  from a captured env UUID), no error body echoes input, the token stays memory-only with the stderr
  clause asserted in criterion 10, boundary validation covers method/content-type/size/schema/
  traversal, and the `'unsafe-eval'` CSP shortfall remains a stated human-owned trade with ADR 0024
  behind it. Nothing new, nothing regressed.
- **Context trend, honestly.** Session-start load 1,204 → **326** lines, which is what the split was
  for and it delivered. But the two halves total **1,312**, ~108 lines *more* than the pre-split card,
  so the document is still growing round over round — the eighth consecutive rise in total size. Not
  cited (the growth is enumerated contract and assertions, not boilerplate), but the trend is now the
  single best argument for a human to call a trim rather than another judge round.
- **`analyze.py` is 792 lines** against the 800 hard max, with `task-tracker/git_facts.py` named as
  the clean split and explicitly unscheduled as a human-owned call — correct posture, unchanged.
- **Re-verified live at `7be4aec`:** no `TBD`/`TODO`/`FIXME`/placeholder in either half; no absolute
  path (`/Users/`, `/home/`) committed; `analyze.py` 792 lines; `feature_tasks.compare` exit 3 on this
  pair and exit 0 on `memory-system-split`; `feature-sync-guard.sh` present and registered in the live
  `$HOME/.claude/settings.json`.

## Round 11 — 2026-08-11T02:04:51Z — **FAIL** (2 violations)

`head_sha` `7ba5e0f13993c16b00ed5e7bb1b37b58530f694b` · branch `feat/tracking-feature-state` ·
spec blobs `a164665959e9e58d56a3986aa747fd227c50d5ea` (`.md`) /
`6ba15cf2cf9cf8974a3fcc9a535f9ddf31be5530` (`.spec.md`) · confidence **high**

All three round-10 findings are **closed on the merits**, each re-verified against the code rather
than against the commit message that claimed it. Both round-11 findings are new, and both rest on
territory no earlier round examined: the first cites **ADR 0017**, a rule source that appears
nowhere in the previous ten rounds of this file; the second is the *client* side of an error
boundary whose server side was cited and closed five rounds ago.

### Layman summary

The re-split worked. The card is genuinely two files behaving as one document: the checklist half is
112 lines, every cross-reference points at something that exists, and the machine check that keeps
the two task lists equal both passes and — the part that matters — can still fail. I deleted a task
from one half and it failed immediately with the right message, so the clean result is a real result
and not a check that is blind by construction.

Two things are still wrong, and neither is a re-run of an old finding.

The first is size. The repo's own decision record, ADR 0017, is the document that *created* this
two-file shape, and it sets a number for each half: the checklist file at most 200 lines, the spec
file at most 800. The checklist half is comfortably inside its budget at 112. The spec half is
**1,261** — over half again as long as the cap it is measured against, and longer than before the
re-split, because the re-split moved per-task detail into it. Three earlier rounds looked at this
card's length and declined to cite it, and they were right on the rules they used: the general
"800 lines maximum" in `core-conduct.md` sits under **Code Style** and reads as a rule about code,
and the split itself is permitted. But none of those rounds cited ADR 0017, and ADR 0017 is not
about code — it is about exactly this artifact, and it only started binding when the card actually
became a pair. The card knows how to handle an overrun properly: task 3 says `analyze.py` is past
its 400-line target, names the clean split, and explicitly hands the decision to a human. The spec
half extends itself no such courtesy — it is 58% over a documented cap with no recorded decision at
all, which makes the overrun something the card decided quietly rather than something a person
signed off.

The second is the browser. This feature exists to let a button in a web page drive a Claude session,
and the card specifies the server side of that conversation to an unusual standard — every status
code, every audit field, what happens when a subprocess hangs. It never says what the *page* does
when the answer comes back wrong. If the token is stale the server returns a deliberately vague
`403`, and §Security itself points out that with parallel sessions this is the normal case, not an
edge one, and that the operator will read it as a broken feature. The card stops there. There is one
sentence telling the UI to surface a failed re-analysis, and it belongs to no task and is checked by
no acceptance criterion. Nothing in the card says what a user sees when a `clear` is refused, when
the session has ended, or when the fetch simply fails — and no criterion ever presses a button
against a running server, so an implementer can ship a button that silently does nothing and pass
every test in the document.

Everything else I checked held. Five pinned tool versions re-read exactly as written on this host,
`pytest==9.1.1` resolves, the suite reports the same 53 passed the card records, and `analyze.py` is
unchanged at 792 lines.

### What I re-verified from source (not from the commit messages)

| Claim under test | Method | Result |
|---|---|---|
| Round 10 #1 `gates/split-half-sync` fixed | `python3 hooks/lib/feature_tasks.py <md> <spec.md> tracking-feature-state` | exit **0**, no output |
| …and the check can still fail | same, with task 12 deleted from the `.md` copy only | exit **3**, "in …spec.md but missing from …md: 12" |
| …and the split follows the prescribed axis | ADR 0017 decision 4 vs. the two halves | `.md` = frontmatter + terse list; `.spec.md` = spec + per-task rationale ✓ |
| `feature-sync-guard.sh` registered | `grep -n feature-sync-guard settings.json` | line 29, registered ✓ |
| Round 10 #2 `writing-specs/spec-code-drift` fixed | `grep -n SPEC_SUFFIX task-tracker/analyze.py`; read `_card_paths` (analyze.py:187-193) | selection is `glob("*.md")` minus `endswith(".spec.md")` — criterion 1's new wording matches the code exactly ✓ |
| …both directions of that selector are real | ran the analyzer against two throwaway repos | a card with **no frontmatter** → in `features[]`, `questions[]` says "No closing `---` delimiter…"; a card with frontmatter but **no `phase:`** → in `features[]`, `questions[]` says "phase: ''" — both match §Design 1's failure table ✓ |
| Round 10 #3 `writing-specs/good-bad-edge-cases` fixed | read task 9 (spec:1124-1132) against §Security's send-time table (spec:726-729) | the fourth outcome is genuinely **post-send** — "After a confirmation that *succeeded*, make the faked `cmux send` exit non-zero … require `502`, `reason=send_failed`, `sent=unknown`" — not a re-spelling of the pre-send `confirm_*` failure ✓ **Not cited again; no escalation fires.** |
| Line counts | `wc -l`, and `git show <sha>:<path> \| wc -l` for the trend | `.md` **112** (cap 200 ✓, down from **326** at round 10 — over cap then) · `.spec.md` **1261** (cap 800 ✗; 986 → 993 → 1261 across `7be4aec`→`5b7cdcc`→`bbaae5b`) · `analyze.py` **792** (max 800 ✓, unchanged) |
| Every `§` reference resolves | enumerated all 67 `§` references (58 in the spec half, 9 in the `.md`) against the heading list | all resolve; `§Verification` is the `.md`'s own section, as both halves state ✓ |
| Task summaries agree across halves | compared all 14 `.md` bullets to their `§Tasks` entries | no disagreement ✓ |
| Toolchain pins are real | `python3 -V`, `uv --version`, `node --version`, `cmux --version`, `uv run --with pytest==9.1.1 … --version` | `3.9.6`, `0.11.28`, `v26.5.0`, `0.64.20 (100) [14e3400b9]`, `pytest 9.1.1` — **all five exact** ✓ |
| The recorded test count | `uv run --with pytest==9.1.1 --no-project pytest task-tracker/ -q` | **53 passed** in 4.35s — matches §Verification ✓ |
| Manifest ↔ extension map | counted the 16 manifest rows' extensions | `.js` 9, `.css` 4, `.woff2` 3; `.html` covers **zero** rows (see notes) |
| No secrets / absolute paths committed | `grep -nE '/Users/\|\$HOME\|/home/\|password\|api[_-]?key'` both halves | clean; the only `$HOME` is a generic warning, and the card deliberately records no export path ✓ |
| Task 4's re-opened wording | read spec:1010-1017 against `test_analyze.py:157-172` and the `repo.card` helper | accurate — the fixture writes `phase:` on every card, so only the "skipped despite `phase:`" direction is pinned; the bullet names the missing assertion and both things it must require ✓ |

### Violations

| # | id | rule_source | rule | where | why |
|---|---|---|---|---|---|
| 1 | `adr-0017/spec-half-size-budget` | `docs/decisions/0017-session-state-restore-and-synced-pair-feature-files.md` | Size rule for the synced pair: "`<name>.md` ≤200 lines; `<name>.spec.md` ≤800" (three-artifact table); `rules/core-conduct.md` Code Style's "800 max" concurs | `tracking-feature-state.spec.md`, whole file — §Tasks (268 lines) and §Design 3 (274 lines) carry the bulk | The spec half is **1,261 lines against the ADR's ≤800 cap for exactly this artifact** — 58% over, and rising: 986 at round 10's head, 993 immediately before the re-split, 1,261 now — and no human-owned exception is recorded anywhere in the card, unlike the smaller `analyze.py` overrun that task 3 explicitly defers to a person. |
| 2 | `core-conduct/ui-error-boundary` | `rules/core-conduct.md` | Code Style: "Handle errors explicitly, never swallow them" — at every boundary the design introduces | §Design 3 status table (`500 reanalyze_failed` row); §Tasks task 10; §Acceptance criteria | The browser→server edge this feature exists to create has **no stated client-side behaviour for `403`, `409`, `502` or a failed fetch**; the single "the UI must surface the failure" clause covers `reanalyze_failed` only, is owned by no task bullet and asserted by no criterion, so a button that silently does nothing on the stale-token `403` that §Security itself calls the normal case would pass every criterion in the card. |

**Why violation 1 is not a reversal of rounds 7, 8 and 10.** Those rounds answered a different
question with a different rule set. Round 7: "`core-conduct`'s 400/800 limit sits under **Code
Style** and governs code files"; round 8 repeated it verbatim; round 10 recorded the growth as a
trend note. All three are correct about `core-conduct` and about `gates.md` making the split a MAY.
None of them cites ADR 0017, which appears **nowhere** in the previous ten rounds of this file
(`grep -c 0017` = 0 before this section). ADR 0017 is not a code-style rule — it is the decision
that created this exact two-file shape and it states a per-file line budget as part of the shape.
It could not bind before the card was a pair; it binds now, and the half it governs is 1,261 lines.

**Why violation 2 is not `core-conduct/explicit-error-handling` reopening.** That id was cited in
rounds 1, 2, 5, 7 and 8 and closed in round 8. Every one of those citations was **server-side**:
the analyzer's git/frontmatter failures (r1), `reanalyze`'s missing status code (r2), the static-read
boundary (r5), `EADDRINUSE` (r7), send-time identity confirmation (r8). None touched the client. The
territory here is task 10 and the page's response handling, which no round has examined; a new id
keeps persistence detection honest in both directions.

### Waivers

**None.** No violation has ever been waived on this card, and nothing was waived this round. The
`waived` array is empty for the eleventh consecutive round.

### Notes (non-blocking)

- **`.html` is in the extension map and matches no manifest row.** §Design 3 lists the map as `.js`,
  `.css`, `.html`, `.woff2` and then claims "those four extensions cover every row above with none
  left over, and that is a property to re-check rather than assume". I re-checked: the 16 manifest
  rows are `.js`×9, `.css`×4, `.woff2`×3 — `.html` covers zero, because `GET /` is a dynamic route
  that sets `text/html` directly. The sentence is true under the reading "no *row* is left
  uncovered" and false under "no *extension* is left over", and the second is the informative one.
  Nothing an implementer builds changes either way (the startup abort is one-directional, on
  unmapped manifest rows), which is why this is a note and not a violation — but it is the third
  round it has survived, and the fix is four words. Carried unchanged from rounds 9 and 10.
- **Task 9's `reason`-bijection bullet still reads static-or-runtime**, and it is weaker than round
  10 implied. "Walk the contract table … require every value to be reachable" (spec:1088) points at
  runtime; §"Audit log"'s restatement, "every row has a value, every value has a row" (spec:435),
  points at a documentary check. What rescues it is task 9's opening line — "including every
  negative case and **each status code in the contract table**" — which forces the drives, so the
  runtime reading is recoverable from the whole task. Not citable on that basis; still worth one
  clause ("drive a request that produces each value").
- **Criterion 14's idle clause costs ≥60 seconds of wall clock.** It says "drive both with short
  overrides so the test does not take 30 minutes", while §Security fixes `TASK_TRACKER_IDLE_SECS`
  at a 60s minimum that "may not be disabled". Satisfiable (60s ≪ 30 min) and therefore not cited,
  but say the number out loud, or an implementer under time pressure lowers the floor to make the
  suite fast and quietly weakens a lifetime control.
- **The governing discipline preamble is duplicated across both halves in diverged wording**, and
  the divergence has already produced one inconsistency. The `.md` copy (lines 28-36) drops the
  spec half's reconciling clause — "measurements that must be recorded (test counts, tool versions)
  are stamped with their date and their reproducing command" — so the `.md` flatly asserts "no
  count, test total or phase tally is pinned anywhere" and then records "**53 passed** on
  2026-08-09" fifty lines later in its own §Verification. The file already models the right fix one
  section down: §Verification duplicates the canonical pytest invocation *and names §Toolchain
  authoritative if the two disagree*. Do the same here, or copy the missing clause. This is the
  duplication surface the pair shape creates, and it is the one the re-split left behind.
- **Cross-file coherence otherwise holds.** All 67 `§` references resolve, all 14 task summaries
  agree with their `§Tasks` detail, and the only other cross-half duplication (the pytest
  invocation) carries an explicit authority rule. The re-split did not introduce a new instance of
  the round-9 "the fix creates the next defect" pattern.
- **Task 4 is stated precisely enough to implement.** One mechanical consequence the bullet does
  not name: `repo.card(...)` writes `phase:` unconditionally, so the fixture helper must gain a way
  to emit a card without it before the new assertion can be written. Also worth deciding
  deliberately — "carrying no `phase:` key" has two distinct code paths (no frontmatter block at
  all → the unclosed-delimiter question; well-formed frontmatter minus the key → the `phase: ''`
  question). I ran both: each lands in `features[]` with its own `questions[]` entry, so either
  satisfies the assertion's purpose, but naming which one is intended would stop two implementers
  writing two different tests.
- **Spec path** is `docs/features/`, not `writing-specs`' `docs/superpowers/specs/`. Not cited, for
  the same reason as every prior round: `rules/gates.md`'s one-canonical-file discipline plus ADR
  0017 are the repo layer and take precedence on conflict.
- **Security territory re-checked** (external input, shell execution, a localhost server, a
  credential). Nothing regressed: the wire still carries an allowlist id and never text, `--surface`
  comes from a captured env UUID and never from a request, no error body echoes input, the token is
  memory-only with the stderr clause asserted in criterion 10, boundary validation covers
  method/content-type/size/schema/traversal/`Host`, every subprocess has a timeout, and the
  `'unsafe-eval'` shortfall remains a stated human-owned trade backed by ADR 0024.
- **`analyze.py` at 792 lines is unchanged**, eight under the hard max, with `git_facts.py` named as
  the clean split and explicitly unscheduled as a human call. Correct posture; no source was touched
  this round, as expected.
- **Trend, stated plainly since two judges now track it.** Session-start load is 112 lines, which is
  what the split was for and it delivered handsomely. Total across both halves is 1,373, up from
  1,312 at round 10 — the ninth consecutive rise. Violation 1 is the point at which that trend stops
  being a note and becomes a rule question, and the answer to it is a human's, not another revision.

## Round 1 (re-entry) — 2026-08-11T05:45:33Z — **FAIL** (4 violations)

`head_sha` `ab799e102894d470abe99dc4d3efac6356582a9d` · branch `feat/tracking-feature-state` ·
spec blobs `2adcec23a1db0034562416650f84f966d70014d6` (`.md`) /
`788a8aaed0fbdaaa8f694da0cfb48a1a98fbc45f` (`.spec.md`) · confidence **high**

Round numbering restarts here: `e24727d` invalidated every prior verdict under the
`spec_blob_sha` freshness contract, so this is round 1 of a new loop, not round 12. The tree
moved under this judgement — the `.md` edits were uncommitted when the run started and landed as
`ab799e1` (`phase: implementation`, task 14 ticked) mid-run; identity was re-derived at the moment
of writing and the blob judged is the blob recorded.

### Layman summary

The spec revision this round was asked to check does what it claimed. Removing `babel.min.js` from
the browser criterion was the right call and is not a hole: the file genuinely cannot be requested
by any view (both the page and the design-system bundle contain zero `x-import` occurrences, so the
lazy `ensureBabel()` path is unreachable), which means the row was unpassable by any correct
implementation and was verifying nothing. The replacement is real — task 9 now sweeps every manifest
row and asserts `GET /vendor/babel.min.js` → `200` with its `Content-Type`. What the replacement
does *not* carry is the other half of what vendoring means: nothing anywhere asserts that
`vendor-resources.js` actually points Babel's CDN URL at the local copy. React and ReactDOM get that
for free because the browser fetches them; Babel's entry is now checked by nobody, on a page whose
`file://` mode has no CSP to catch the fallback.

The other three findings are all one species, and it is this card's signature one: a number written
down that stopped being true. The checklist half has grown to **215 lines** against ADR 0017's
**≤200** cap for that artifact — and the spec half, in the very paragraph recording the user's
waiver of the *other* half's overrun, still says the checklist half "is inside its cap" at
"112 lines". That figure was true at `bbaae5b` and has nearly doubled since; it is also the ground
the user accepted the waiver on, so its falsification is not cosmetic. In the same file, the
paragraph explaining why task 14's box is unticked survives next to a ticked box and a frontmatter
that no longer says `planning`. And the pointer at the top still advertises "fourteen acceptance
criteria" nine lines above its own reference to criterion 15.

None of the four needs a design change. Three are sentences to correct or delete; one is a clause to
add to task 9. The size overrun is the only one that may need a human — see the note under
violation 1.

### Violations

| # | id | Rule source | Where | Why |
|---|---|---|---|---|
| 1 | `adr-0017/md-half-size-budget` | `docs/decisions/0017-session-state-restore-and-synced-pair-feature-files.md` (repo layer, via `rules/gates.md` one-canonical-file discipline) | `docs/features/tracking-feature-state.md` — whole file; `## Verification` (lines 64-215) carries all of the growth | The checklist half is 215 lines against ADR 0017:39's `≤200` for exactly this artifact, and it crossed the cap in the same pair of commits that recorded the user's acceptance of the *spec* half's overrun on the ground that this half had moved the right way. |
| 2 | `writing-specs/stale-recorded-claim` | `~/.claude/skills/writing-specs/SKILL.md` — "Maintain it with production rigor … updates when reality changes"; "Drift causes hallucination" | `.spec.md` preamble, ADR-0017 size paragraph (lines 43, 49-52); `.md` `## Verification` RESOLUTION paragraph (lines 206-208) against frontmatter line 2 and task 14 (line 62) | Two recorded claims are false at this revision: the spec half states "As of 2026-08-11 the `.md` half is inside its cap" and pins it at "112 lines" when `wc -l` reads 215, and the `.md` states "Task 14's box is still unticked here … the card is at `phase: planning`" while the box is ticked and the frontmatter reads `implementation`. |
| 3 | `gates/split-half-sync` | `rules/gates.md` (one-canonical-file discipline) + ADR 0017 | `.md` half preamble, line 10, against `.spec.md` §Acceptance criteria (1-15) and the `.md`'s own task 10 entry (line 58) | The pointer half advertises "all fourteen acceptance criteria" in the half that carries fifteen — nine lines above its own "Owns criterion 15" — so a reader who trusts the index stops one criterion short of the contract. |
| 4 | `writing-specs/good-bad-edge-cases` | `~/.claude/skills/writing-specs/SKILL.md` — "state explicitly what correct looks like … anything you leave implicit, the agent infers" | Criterion 13's babel note (`.spec.md` 991-1008), task 9's manifest-sweep bullet (1220-1228), task 14's `window.__resources` bullet (1354-1360) | The replacement for the removed babel row covers the serve-side fact only; nothing asserts that `vendor-resources.js` maps `BABEL_URL` to `vendor/babel.min.js`, so the third of three vendoring hooks is written down and checked by nothing — the exact pattern task 9's own bullet list exists to close. |

### Verification of the revision under judgement (what the caller asked to be checked hardest)

- **Babel removal — replacement is real and sufficient for what it replaces.** Re-derived, not
  read: `grep -c 'x-import' 'task-tracker/Task Tracker.dc.html' task-tracker/_ds/*/_ds_bundle.js`
  → `0`, `0`. `ensureBabel()` is reachable only from `load(kind === "jsx")`, so no view can produce
  the request and the row was unpassable — removing it loses no live check, because there was none.
  Task 9's manifest sweep (spec 1220-1228) plus criterion 13's own pointer (1006) plus task 14's
  restatement (1345-1347) all name the same assertion, and it is table-driven over the manifest
  rather than a hand-list, so it does not rot. **The gap is one step to the left of where the
  revision looked** — see violation 4.
- **The spec's stated mechanism for keeping Babel local is wrong**, which is probably why the gap
  survived the edit: "the manifest is what makes the CDN unreachable, not the request count"
  (spec 1002-1004). The manifest makes the *local copy servable*; the CSP `script-src 'self'` is
  what makes `unpkg.com` unreachable on the served page; and `window.__resources` is what redirects
  the URL. On criterion 8's `file://` path there is no CSP at all, so the map is the only thing
  between a future `x-import` and a live remote fetch.
- **`path_escape` closes the enum both ways.** Walked the bijection by hand: every row of the
  §Design 3 status table now has a `reason` value and every value has a row (`403` fans out to
  `bad_token`/`unknown_id`/`origin_mismatch`/`host_mismatch`/`path_escape`; `502` to
  `send_failed`/`confirm_failed`/`confirm_timeout`). The fourth-instance defect — a value with no
  row — is genuinely closed.
- **The re-score arithmetic reproduces.** §Design 3 manifest = 16 rows; criterion 13(a) = 17 rows;
  17 − `/favicon.ico` (audit-log-scored) = 16 observed; 16 − `/tracker-data.sample.js` = 15 for
  run (b). Both match the recorded enumerations. The `/favicon.ico` scoping and the two
  `read_network_requests` caveats are each stated with the falsifying evidence beside them.
- **No spec-code drift in the manifest.** `STATIC_MANIFEST` in `task-tracker/server.py` is the same
  16 paths in the same order as the spec table; `EXTENSION_TYPES` is the deliberate one-directional
  superset the spec describes, `.html` unused by any row exactly as stated.

### Notes (non-blocking)

- **Violation 1 may be a human's call, not a revision's.** All 151 lines of growth are
  `## Verification`, which ADR 0017 deliberately keeps in the `.md` half because task 13 writes into
  it while the phase gate forbids editing a spec. Trimming it means deleting evidence; moving it
  means breaking the ADR's own division. The honest options are (a) compress the criterion-13
  narrative now that it resolves, or (b) raise the cap question with the user the way the spec-half
  overrun was raised. Recommend (a) first — the standing "FAILS — expected 200" table plus its
  RESOLUTION paragraph is the largest single block and is now describing a closed finding.
- The `.md` §Verification's babel row still reads **"FAILS — expected 200"** in its status column.
  It is explicitly framed two paragraphs down as retained evidence and is not cited on that basis,
  but a reader skimming the table alone reads a live failure in a card whose task 14 is ticked.
- Waiver honoured: **`adr-0017/spec-half-size-budget`** is recorded as waived (user decision
  2026-08-11, commit `2c66fab`) and is not re-cited. The spec half measures 1,442 lines; violation 1
  is a different half against a different row of the same ADR and is not covered by that waiver.
- Spec path under `docs/features/` is not cited, for the same reason as every prior round: the repo
  layer (`rules/gates.md` + ADR 0017) takes precedence over `writing-specs`' `docs/superpowers/specs/`.
- Security territory re-checked against `writing-secure-code` (external input, shell execution, a
  localhost server, a credential). Nothing regressed this revision: the wire still carries an
  allowlist id and never text, `--surface` still comes from a captured env UUID, no error body
  echoes input, the token remains memory-only with the stderr clause in criterion 10, every
  subprocess carries a timeout, and the traversal rule now has both a `403` row and a `reason`.
- `grep -c skipif task-tracker/*.py` → `test_store.py:3`, everything else `0`, so §Verification's
  node-guard wording is still accurate as of this round.
- Trend: 1,657 lines across both halves, up from 1,373 at round 11 — the tenth consecutive rise, and
  the first round in which the *session-start* half is the one over its cap.

---

## Round 2 — 2026-08-11T14:21:10Z — **FAIL** (1 violation)

`head_sha` `1d5481629feb6e6dde41f656bdf926d1809358d4` · branch `feat/tracking-feature-state` ·
spec blobs `cf48cee15777ed282b5d71aca09dc08b6401aaf1` (`.md`) /
`41a4d26348b00501226fcb9b51621e6cf042a11c` (`.spec.md`) · confidence **high**

### Layman summary

The four things this round was asked to check all check out. The mapping test task 9 gained —
"every CDN URL `support.js` can request must be a `vendor-resources.js` key that resolves to a
manifest row" — is real, not aspirational: I read `support.js` directly and its three URL
constants (`REACT_URL`, `REACT_DOM_URL`, `BABEL_URL`) match `vendor-resources.js`'s
`window.__resources` map key-for-key, byte-for-byte, and each value names a file that is on
`server.py`'s static manifest and actually exists under `task-tracker/vendor/`. The spec also
requires the test to be *falsified* (mutate one key by a character, confirm it fails), which is
what keeps this from being another "written down and checked by nothing" control. The other two
closures hold up under re-run: the acceptance-criteria count derivation returns exactly `15`, and
`hooks/lib/feature_tasks.py` exits `0` on the current pair — the two halves' task lists genuinely
match. I also diffed the `## Verification` compression (215 → 206 lines, confirmed by `wc -l`) line
by line against its prior form: the babel-row reasoning, the `read_network_requests` 503-vs-404
corroboration, and the `/favicon.ico` audit-log scoping are all still present, just consolidated —
nothing measurable was cut.

**One new defect, introduced by this round's own fix.** Closing the "task 14 still unticked … the
card is at `phase: planning`" false claim (round 1's violation 2) was done two ways at once: the
prose was corrected (it now just says "task 14 is ticked above," which is true), *and* the
frontmatter's actual `phase:` value was changed from `implementation` to `planning` — a change the
commit message explains ("implementation forbids spec edits, and this card's own revision set the
precedent") but the document itself never states. Nothing else moved: `branch:` still names the real
branch we are sitting in, and 9 of 14 checklist tasks are still ticked against real, tested, shipped
code (`task-tracker/*.py`, nine vendored files under `vendor/`, 54 passing tests). I checked every
other feature card in this repo: every single one with `phase: planning` also has `branch: none`
and zero completed tasks (`falsify-harness-signatures.md`, `verification-marker-gate.md`); every
card with any task done is `implementation` or `review` with a real branch. This card is now the
sole exception — its own frontmatter answers "is this planning or nine tasks into implementation?"
two different ways, in the same document, with nothing to reconcile them. Same species round 1
already caught here twice (a recorded claim that stopped matching reality) in a new location:
the field itself, not a sentence describing it.

### Violations

| # | id | rule_source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `gates/phase-branch-mismatch` | `rules/gates.md` | Phase gate: frontmatter `phase` is "the single source of truth for what work is permitted"; Gate transition: branch creation happens "on confirmation" alongside phase becoming `implementation`, and reopening it "needs the literal `gate confirmed` again" | `docs/features/tracking-feature-state.md` frontmatter (lines 1-4) against `## Tasks` (lines 43-64, 9/14 done) and `branch:` (line 4) | This round's revision (`6e17fd9`) reverted `phase: implementation` → `planning` to justify editing the spec/checklist, but left `branch: feat/tracking-feature-state` populated and 9 of 14 tasks ticked against real shipped code (`task-tracker/*.py`, `vendor/*`, `uv run … pytest task-tracker/ -q` → 54 passed) — both of which, per this same rule, should exist only once the gate has been confirmed. Every other `phase: planning` card in `docs/features/*.md` pairs it with `branch: none` and zero completed tasks; this is the sole, unexplained exception, and nothing in the card's own text addresses the contradiction. |

### Closed since round 1 (re-entry) — verified, not assumed

| id | how it was verified |
|---|---|
| `writing-specs/stale-recorded-claim` | Grepped both halves for every stale figure named in round 1 and round 1's own closing commit (`112 lines`, `215 lines`, `fourteen`, bare `"passed"` claims without a date): none remain outside historical/explanatory context. The spec half now says "both halves are over their caps" with no false number; the `.md` RESOLUTION now says "task 14 is ticked above," which is true. |
| `gates/split-half-sync` | Re-ran the card's own derivation: `awk '/^## Acceptance criteria/{f=1;next} f&&/^## /{exit} f&&/^[0-9]+\. /{n++} END{print n}'` over the spec half → `15`, matching the `.md`'s stated figure exactly. Independently ran `python3 hooks/lib/feature_tasks.py docs/features/tracking-feature-state.md docs/features/tracking-feature-state.spec.md tracking-feature-state` → exit `0`. |
| `writing-specs/good-bad-edge-cases` | Read `task-tracker/support.js:1143,1145,1147` and `task-tracker/vendor-resources.js` directly: the three `window.__resources` keys are byte-identical to `REACT_URL`/`REACT_DOM_URL`/`BABEL_URL`, and each value (`vendor/react.production.min.js`, `vendor/react-dom.production.min.js`, `vendor/babel.min.js`) is both a real file under `task-tracker/vendor/` and a row of `server.py`'s static manifest. Task 9's falsification instruction ("mutate one key by a character, confirm the test fails") is present and would catch a test that reads both sides from the same source without asserting anything. |

### Waivers (carried forward, not re-cited)

| id | attribution |
|---|---|
| `adr-0017/md-half-size-budget` | User decision 2026-08-11, recorded in commit `1d54816`. Re-verified: `.md` half is `206` lines (`wc -l`) against ADR 0017:39's `≤200`, down from `215` at round 1; the waiver text in the spec half correctly scopes it to the residue only, states it is not licence to move `## Verification` out or stop deleting duplication, and names an ADR amendment as the escalation if the gap widens. |
| `adr-0017/spec-half-size-budget` | User decision 2026-08-11, recorded in commit `2c66fab` (round-11 era). Unchanged this round; spec half is `1473` lines against the same ADR row's `≤800`. |

### Notes (non-blocking)

- **`model_tier` also changed, `low` → `high`, alongside the `phase` flip, unexplained in the text.**
  Session-management metadata, not spec content — not cited, but it is the second frontmatter field
  this round changed without a stated reason, both in the same edit.
- **Test count moved and that is fine, by the card's own rule.** `uv run --with pytest==9.1.1
  --no-project pytest task-tracker/ -q` now reports `54 passed`, not the recorded `53`. This is
  exactly what the card's own discipline anticipates (a dated measurement, not a contract) — noted
  here as evidence the discipline is working, not as a finding.
- **Toolchain re-verified on this host:** Python `3.9.6`, `uv 0.11.28`, `node v26.5.0` all match
  §Toolchain exactly.
- **Criterion 15 has not reopened.** Diffed this round's edits against the prior blob: nothing
  touches §Acceptance criteria's criterion 15 or §Design 3's "What the page does with a failure"
  table. Still four assertions, still intact.
- **No fourth stale claim found.** Searched both halves for residual hardcoded totals from earlier
  rounds (`1,442`, `1,373`, `1,657`, `112 lines`, `215 lines`, `206 lines`) — none remain outside
  this writeup itself.
- Spec path under `docs/features/` is not cited: the repo layer (`rules/gates.md` + ADR 0017) takes
  precedence over `writing-specs`' `docs/superpowers/specs/` default, as every prior round has held.
- Security territory re-checked (external input, shell execution, a localhost server, a credential):
  nothing regressed this round — the only functional change was task 9's mapping-check bullet, which
  strengthens rather than weakens the boundary.

---

## Round 3 — 2026-08-11T15:35:59Z — **PASS** (0 violations)

`head_sha` `128e79c0f3d5a243252262b41ab6001f71d41875` · branch `feat/tracking-feature-state` ·
spec blobs `c8f8cd7c4172752e392ab4714feb271157d374a6` (`.md`) /
`41a4d26348b00501226fcb9b51621e6cf042a11c` (`.spec.md`) · confidence **high**

### Layman summary

This is round 3, the cap for this re-entry — whatever is still outstanding when this round ends
goes to the user rather than to a round 4. Round 2 found exactly one problem: the card's frontmatter
said `phase: planning` (normally a fresh, unstarted card) while also carrying a real branch and 9 of
14 tasks ticked — a combination no other `planning` card in the repo has, and nothing in the text
explained it. The fix under judgment this round is a ~10-line warning block added to the top of the
`.md` half: it states plainly that this is not a fresh planning card but an implementation paused
mid-stream for a legal spec revision, names the enforcement mechanism that makes that safe
(`phase-guard.sh` blocking source writes), names the literal exit condition (`gate confirmed`), and
explains why a fourth phase state wasn't invented for it. I did not take that explanation on faith —
I independently grepped `phase:`/`branch:` across all 15 feature cards in `docs/features/*.md` and
confirmed the two other `planning` cards (`falsify-harness-signatures.md`,
`verification-marker-gate.md`) do carry `branch: none` and zero ticked tasks, exactly as the new
paragraph claims. The underlying rule this closes against (`rules/gates.md`'s phase gate and gate
transition) is explicitly a judgment-based checkpoint, not a hard invariant with one textual
reading — its own header calls these "judgment-based checkpoints," and its forward-direction wording
("until [gate confirmed]: no branch, no first task") describes a fresh feature's first pass through
the gate, not a card revisiting planning after already passing it once. Given that, removing the
ambiguity by documenting the state, its mechanism, and its exit condition is the correct way to close
a judgment-grounded finding — changing the frontmatter itself was never the ask. I re-read both
halves in full this round (not just the diff) and reran the load-bearing derivations myself rather
than trusting the prose: the acceptance-criteria count is exactly 15, the two halves' task-number
sets are identical (1–14 in both), `SPEC_SUFFIX = ".spec.md"` in `analyze.py` matches what the card
describes, no `TBD`/`TODO`/`FIXME`/placeholder markers remain outside historical narrative context,
and no absolute path or hardcoded secret leaked into either file. Nothing new surfaced. **Verdict:
pass — nothing is outstanding, so the round-3 escalation tripwire does not fire.**

### Violations

None this round.

### Closed since round 2 — verified, not assumed

| id | how it was verified |
|---|---|
| `gates/phase-branch-mismatch` | Read the new preamble (`.md` lines 9–17) added in `128e79c`. Independently ran `grep -m1 '^phase:\|^branch:' docs/features/*.md` across all 15 cards: confirmed the two other `phase: planning` cards (`falsify-harness-signatures.md`, `verification-marker-gate.md`) both carry `branch: none` and `grep -c '^\- \[[xX]\]'` returns `0` for each, exactly as the preamble states. The rule cited (`rules/gates.md` Phase gate / Gate transition) is a judgment-based checkpoint whose "until [gate confirmed]: no branch, no first task" wording governs a fresh feature's first pass through the gate, not a card reopening planning after already passing it — so documenting the paused-for-revision state, its enforcing mechanism (`phase-guard.sh` blocking writes to source while unconfirmed), and its exit condition (the literal phrase `gate confirmed`) is a legitimate closure, not a workaround. The preamble also correctly declines to invent a fourth phase state for a single-card edge case, which is the YAGNI-consistent choice `rules/core-conduct.md` Code Style would favor over a speculative schema change. |

### Waivers (carried forward, not re-cited)

| id | attribution |
|---|---|
| `adr-0017/md-half-size-budget` | User decision 2026-08-11, recorded in commit `1d54816`. The round-2 fix (`128e79c`) added ~10 lines to the `.md` half (now 216 lines, `wc -l`), so the overrun against ADR 0017's `≤200` is slightly larger than when waived. The waiver text still stands per the escalation instructions; not re-cited. |
| `adr-0017/spec-half-size-budget` | User decision 2026-08-11, recorded in commit `2c66fab`; accepted on the ground that the figure the pair shape exists to control is the session-start load. Spec half is 1,473 lines (`wc -l`) against the same `≤800` row. Unchanged this round. |

### Notes (non-blocking)

- **Escalation tripwire, stated explicitly per instructions:** round 3 was the cap for this
  re-entry. Verdict is `pass` with zero outstanding violations, so there is nothing to hand to the
  user for a decision — the tripwire does not fire.
- Re-derived the acceptance-criteria count myself: `awk` over `## Acceptance criteria` in the spec
  half returns `15`, matching the `.md` half's stated figure.
- Re-derived task-number sync myself rather than trusting `hooks/lib/feature_tasks.py`'s prior
  clean exit: both halves' checklists enumerate exactly `1..14` with no gaps or extras.
- Confirmed `task-tracker/analyze.py:36` defines `SPEC_SUFFIX = ".spec.md"` and every citation of it
  in the card (selection-by-filename, both directions) matches the source at the lines quoted.
- Scanned both halves for `TBD`/`TODO`/`FIXME`/`placeholder`/`XXX`: the only two hits are narrative
  references to a *past* placeholder row that was since replaced with a real, enumerated table — not
  a live placeholder.
- Scanned both halves for `/Users/`/`/home/` and secret-shaped strings: none found beyond the
  design's own references to `secrets.token_urlsafe` and the `X-Tracker-Token` header name, both of
  which are mechanism descriptions, not literal values.
- Security territory re-checked against `writing-secure-code` (external input, shell execution, a
  localhost server, a bearer credential): unchanged from round 2's clean read — allowlist-id-only
  wire, no error echoes input, token is memory-only with an explicit no-disk/no-argv/no-log-line
  guarantee, every subprocess call carries a timeout, path traversal and the `path_escape` reason
  are both defined and cross-checked against the status table.
- Spec path under `docs/features/` is not cited, as every prior round has held: the repo layer
  (`rules/gates.md` + ADR 0017) takes precedence over `writing-specs`' `docs/superpowers/specs/`
  default.
- Toolchain versions in `§Toolchain` were read, not re-verified against this host this round (no
  code changed since round 2's toolchain re-verification); no drift is implied by that.

## Round 1 (re-entry) — 2026-08-11T18:34:03Z — **FAIL** (1 violation)

`head_sha` `01f0c45ba7e998448183b175a438156203b33dd0` · branch `feat/tracking-feature-state` ·
spec blobs `c8f8cd7c4172752e392ab4714feb271157d374a6` (`.md`, byte-identical to round 3's pass) /
`9260312665dd622dd33b3feae0b32fbb11ae2fb2` (`.spec.md`) · confidence **high**

### Layman summary

Round 3 of the last cycle passed clean. Since then, two more commits touched only the `.spec.md`
half, which invalidates that pass under the freshness rule and restarts the counter here at round 1.
The first commit (`686057d`) fixed three real wording defects the observability judge had caught two
days earlier and that had survived a full compliance round unfixed: a `405` table row that could be
misread as making `POST /command` — the one state-changing route — a `405`; a claim that a failed
`cmux send`'s exit code is "logged server-side" when the structured audit line actually carries no
such field (it goes out as a separate `stderr.write`); and a "bijection" label for the
reason-to-status relationship where the code actually emits five reasons for `403` and two for `502`,
not one each. I re-read the server's routing logic and its `_fail`/`audit` calls directly rather than
trusting the corrected prose, and all three now match the code exactly. The second commit (`01f0c45`)
recorded a genuinely new finding from that same re-derivation exercise: the audit value
`confirm_timeout`, named in four places including a test task 9 must drive an actual request for,
cannot currently be emitted — `confirm_surface()` collapses a non-zero exit and a timeout into one
`"unrunnable"` state. I confirmed this against `task-tracker/server.py:236-253` directly: no code path
produces `confirm_timeout`. The spec handles this correctly — it names the gap as a **blocking
prerequisite**, records the user's decision that the code changes (split the state) before the
assertion is written, and requires that edit to land as its own commit ahead of the test. That is not
cited as a violation; it is exactly the human-owned-decision discipline this card asks for elsewhere.

One real gap survived the fix pass, and it is not new: the observability judge flagged it on
2026-08-11 (its "what I'd double-check" item 3) and the fix commit that closed three sibling findings
from the same list did not touch it. Task 8 (`server.py`) is ticked done, and the file measures **694
lines** (`wc -l`, re-derived) — 73% past the 400-line soft target this card applies to itself. Its own
task-8 entry still reads in the future tense — "will land near the 400-line target. If it crosses,
the split is `serve_static.py`; raise it rather than taking it as a drive-by" — as if the crossing
were still hypothetical. Task 3's entry for `analyze.py` (792 lines, the same over-400-under-800
territory) shows what this card's own convention requires once the number is known: an explicit,
present-tense "not scheduled — a structural split is a human-owned call" note recording the actual
decision. `server.py`'s entry never made that transition. The decision itself may well be "defer,
same as `analyze.py`" — but the card doesn't say so, and this is the one component it calls the
highest-value target in the repo.

### Violations

| # | id | rule source | rule | where | why |
|---|----|-------------|------|-------|-----|
| 1 | `core-conduct/file-size-decision-unsurfaced` | `rules/core-conduct.md` | Code Style: "Many small, focused files (<400 lines, 800 max) over few large ones"; Existing and New Work: "Architecture trade-offs … stay human-owned — implement once decided, don't decide." | `tracking-feature-state.spec.md` §Tasks, task 8 detail | Task 8 is ticked complete and `task-tracker/server.py` measures 694 lines (`wc -l`, re-derived 2026-08-11), well past the 400-line soft target, yet its entry still reads in future/hypothetical tense ("will land near the 400-line target. If it crosses…") rather than recording the actual count and an explicit present-tense human decision to split or defer — the treatment task 3's analogous `analyze.py` overrun (792 lines) received. The same standard this card applies to one file is unapplied to the other, for the component it itself calls the highest-value target in the repo. |

### Verified clean, re-derived from source (not from prior verdicts)

| Claim | Method | Result |
|---|---|---|
| `405` table now matches the server's routing | Read `do_GET`/`do_OPTIONS`/`do_POST` (`server.py:384-411`) against the table's "other than" wording and precedence note | Exact match: `GET /command`→405, `POST /`→405, `POST` on a manifest path→405, `OPTIONS` on any non-`/command` path→405, `POST /command` and `OPTIONS /command` are not 405, unknown path is 404 regardless of method |
| Exit-code claim now matches the audit format | Read `audit()` (`server.py:125-138`) and the `cmux send exited %d` write (`server.py:273`) | The structured line carries no exit-code field; the exit code goes to a separate `stderr.write`, exactly as the corrected prose now states |
| "Bijection" replaced with the accurate property | Derived `grep -oE '_fail\([0-9]+, "[a-z_]+", "[a-z_]+"' task-tracker/server.py \| sed ... \| sort -u` plus the `send_failed` audit call outside `_fail` | `403`→5 reasons, `500`→2, `502`→2 (`confirm_failed`, `send_failed`); no one-to-one pairing exists, matching "total coverage in both directions," not a bijection |
| `confirm_timeout` cannot be emitted (the recorded blocking prerequisite) | Read `confirm_surface()` (`server.py:236-253`) and its call site (`server.py:568-575`) | Confirmed: both a non-zero `cmux tree` exit and a `TimeoutExpired` return `"unrunnable"`, mapped to `reason="confirm_failed"` only — no path emits `confirm_timeout`. Matches the spec's own claim exactly |
| Acceptance-criteria count | `awk` over `## Acceptance criteria` in the spec half | **15**, matching the `.md` half's stated figure |
| Task-number sync | `python3 hooks/lib/feature_tasks.py <.md> <.spec.md> tracking-feature-state` | exit **0** |
| Cross-file pointers (`PORTS.md`, ADR 0022, ADR 0023) | grepped each for the `.spec.md` filename | All three correctly point at `tracking-feature-state.spec.md` |
| No placeholders/TBD/secrets/absolute paths | grepped both halves for `TBD`/`TODO`/`FIXME`/`placeholder`/`/Users/`/`/home/` | The two `placeholder` hits are narrative references to a past, since-replaced row — not live placeholders. Nothing else found |
| Security territory (`writing-secure-code`) | Re-read §Security, the wire contract, and the corresponding `server.py` handlers | Unchanged clean read: single-key allowlist body, no error-body echo, memory-only token compared with `hmac.compare_digest`, every subprocess call carries a timeout, `Origin`/`Host`/CSP checks present and matching the code |

### Waivers (carried forward, not re-cited)

| id | attribution |
|---|---|
| `adr-0017/md-half-size-budget` | User decision 2026-08-11, recorded in commit `1d54816`. `.md` half unchanged at 216 lines (byte-identical blob to round 3's pass) against ADR 0017's `≤200`. |
| `adr-0017/spec-half-size-budget` | User decision 2026-08-11, recorded in commit `2c66fab`; **re-confirmed 2026-08-11 at commit `686057d`** after the observability judge measured the growth since the accepting commit (1,278 → then further, now 1,506 lines, `wc -l`) and put it back to the user, who left the waiver standing on the ground that it was never about this half's size, only the session-start half staying small. Not re-cited. |

### Notes (non-blocking)

- **The `.spec.md` size continues to grow past the figure it was last re-confirmed against.** At
  `686057d` (the re-confirmation commit) the file was smaller than its current 1,506 lines — this
  round's own edits (the `confirm_timeout` paragraph) added to it further. The waiver's *ground*
  (session-start half staying small) still holds — the `.md` half is unchanged — so this is not raised
  as a violation, per the dispatch instructions. Flagging for the user's awareness only: if this
  becomes a pattern where every fix pass adds more to the half than it removes, the "re-confirm on
  request" model may need to become "re-confirm above a stated delta" instead.
- Several acceptance criteria (e.g. 2, 3) still collapse an explicit `When` clause into `Given`,
  consistent with every prior round's non-blocking treatment (token economy, intent stays
  unambiguous). Not cited, per that standing precedent.
- The `confirm_timeout` blocking-prerequisite paragraph is a model instance of this card's own
  discipline: it names the gap, cites the exact code line, records the human decision, and orders the
  code change ahead of the test that depends on it in its own commit — the same shape task 8's entry
  is missing for its own file-size question.
- Phase/branch documentation (`gates/phase-branch-mismatch`, closed round 2 of the prior cycle) is
  unchanged and still correct on independent re-check: the preamble's claim that every other
  `phase: planning` card carries `branch: none` and zero ticked tasks still holds
  (`grep -m1 '^phase:\|^branch:' docs/features/*.md`).
- Spec path under `docs/features/` is not cited, per every prior round: the repo layer (`rules/gates.md`
  + ADR 0017) takes precedence over `writing-specs`' `docs/superpowers/specs/` default.

