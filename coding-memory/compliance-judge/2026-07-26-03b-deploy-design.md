# Compliance Judge — spec 03b (Deploy web app to Cloudflare Pages + Supabase hardening)

- **Spec:** `docs/superpowers/specs/2026-07-25-03b-deploy-design.md` (blob `b8d2e9e847c33c97389237f5d14ec08f8b66a992`)
- **Repo:** mtg-wizard @ `main` (`251d6c92ed94a8ff6fb6f7ff5524998d17d76066`)
- **Rule layer:** global (`rules/core-conduct.md`, `skills/writing-specs`, `skills/writing-secure-code`) + repo `CLAUDE.md` "Security review checklist". No `.claude/project-standards.md` in this repo.

## Round 1 — 2026-07-26 — FAIL (4 violations)

### Layman summary

This spec puts the already-built web app on a public URL and turns on the production
plumbing (login providers, email, avatars). It is a strong spec — genuinely one of the
better ones in this store. Its versions are real (I checked all eight against
`package-lock.json` and they match exactly), its claims about the existing code are
accurate (I checked `csp.ts`, `vite.config.web.ts`, `index.html`, `config.py`, `main.py`),
its risk story is honest, and the three changes it makes beyond what you approved are each
flagged for you to accept or reject instead of quietly slipped in. The hardened CSP is
well-argued and the `base-uri` catch is a real one.

Four things need fixing before it is built:

1. **The avatar bucket is described in one sentence and it needs more than one.** The spec
   says "create the public `avatars` bucket". But the app uploads avatars *straight from the
   browser to Supabase*, bypassing your backend entirely — so the bucket's own permission
   rules are the only lock on that door, and the spec never says what those rules should be.
   A brand-new Supabase bucket has no rules at all, which means the smoke test ("then one
   avatar upload") will simply fail; and the obvious fix a builder would reach for — the
   one-click "let signed-in users upload" template — lets **any** signed-in user write into
   **any other user's** avatar folder and overwrite their picture. It also never caps file
   size or file type, so the bucket is an open file host on your branding.
2. **A typo in a Cloudflare dashboard field can silently strip your security headers.** The
   spec adds a check that the two URL variables are *present*, but not that they are *clean*.
   A stray newline or quote pasted into that box would flow straight into the generated
   `_headers` file, cut the header block in half, and drop the other seven security headers —
   with no error anywhere. The spec itself says this file fails silently; this is the same
   hole one notch deeper, and the same one-line `this.error()` closes it.
3. **Node isn't actually pinned.** The spec has a whole "Pinned versions" section and pins
   eight libraries to the exact patch — then lists Node as `22`, which is a range, not a
   version. Its own reasoning ("so it doesn't depend on a vendor default that can change
   under us") isn't satisfied by `22`. Same for the Cloudflare build image: the spec reasons
   about "v3" behaviour but never lists v3 as a setting to actually select.
4. (Bundled with 1 above but recorded separately because the fix differs.) The write rule on
   that bucket has to be tied to the signed-in user's own folder, and the spec should say so.

None of these is a rewrite. Items 1 and 4 are a fleshed-out §7.6; item 2 is a sentence in
§4.2 plus one test row; item 3 is a table cell.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/default-deny-data-store` | `~/.claude/rules/core-conduct.md` (Zero-Trust Invariants: "default-deny every generated data store"); reinforced by repo `CLAUDE.md` "Security review checklist" | Every generated data store defaults to deny; state its access policy explicitly | §7.6 `avatars` bucket (and §11.2 step 11) | The spec creates a **public** Supabase Storage bucket in one sentence and specifies no storage RLS policies, no allowed MIME types and no size limit, even though `apps/desktop/src/renderer/src/features/profile/avatar.ts:18` uploads client-direct to that bucket (core-api only validates the URL *prefix* after the fact), so the bucket's own rules are the sole authorization boundary and the spec leaves them for the implementer to invent. |
| `writing-secure-code/idor` | `~/.claude/skills/writing-secure-code/SKILL.md` §3 ("validate that the authenticated user owns … the requested resource ID before executing a … mutation"); repo `CLAUDE.md` "Secure sessions" (ownership checks) | Ownership must be enforced server-side on every mutation | §7.6 `avatars` bucket | Objects are written to `${userId}/<uuid><ext>` by the browser, so unless the spec requires the bucket's INSERT/UPDATE/DELETE policy be scoped to `(storage.foldername(name))[1] = auth.uid()::text`, any authenticated user can overwrite another user's avatar — and §11.2 step 11 will pass regardless, because it only tests the happy path with one account. |
| `core-conduct/validate-input-at-boundaries` | `~/.claude/rules/core-conduct.md` (Code Style: "Validate all input at system boundaries"; Zero-Trust: "fail closed on any validation failure") | Validate the shape of input crossing a boundary, not just its presence | §4.2 `buildHeadersFile` / §4.4 `[SPEC-STAGE]` env gate (sink defined in §4.1) | `toOrigin()`'s `^(https?:\/\/[^/?#]+)` negated class admits newlines, spaces and quotes, and §4.2 states the function "adds no failure mode of its own", so a malformed Pages env value is emitted verbatim into `_headers` where an embedded newline terminates the `/*` block and silently drops the remaining seven security headers — exactly the silent-failure class §4.4 exists to close, but the gate checks presence only. |
| `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` ("Pin the exact version of every library and tool"); `~/.claude/rules/core-conduct.md` ("Pin exact library/tool versions") | Every tool the spec names carries an exact version | §12 Pinned versions / §7.1 Cloudflare Pages project | `NODE_VERSION` is set to `22`, a major-version range rather than an exact version, which does not achieve §7.1's own stated goal of not "depend[ing] on a vendor default that can change under us"; and the Cloudflare Pages **build system version** — whose v3 behaviour (`Node 22.16.0` default) the same paragraph reasons from — is never listed as a setting to select. |

### Notes (non-blocking)

- **Verified accurate, and worth saying so.** All eight library versions in §12 match
  `apps/desktop/package-lock.json` exactly (vite 7.3.6, rollup 4.62.2, vitest 4.1.10,
  typescript 5.9.3, electron 39.8.10, electron-vite 5.0.0, supabase-js/auth-js 2.110.5). §4.6's
  claims check out (`config.py:25` default contains `null`; `main.py` adds `CORSMiddleware`
  with no `allow_credentials`). §4.5's "current meta content" matches
  `src/renderer/index.html` byte for byte. §4.1's description of the unchanged 03a pieces
  (`toOrigin`, Scryfall constant, Supabase omitted when unset) matches `build/csp.ts`.
  `build:web` / `preview:web` / `typecheck:web` all exist as described.
- **Nonce-based CSP is never discussed.** `writing-secure-code` §2 asks that new headers
  "support strict, nonce-based CSP configurations"; a static Cloudflare `_headers` file
  physically cannot emit a per-response nonce, and `script-src 'self'` with zero inline
  scripts and no user content on-origin is a sound posture here. Not cited as a violation —
  but a spec that carefully records *why* COEP and `X-XSS-Protection` were rejected should
  spend one line recording why nonces/`strict-dynamic` are not on the table either.
- **`<project>` and `<n>` are resolved independently at five sites.** The pages.dev origin
  feeds CORS, Supabase Site URL, the redirect allowlist, and two `curl` commands; the Cloud
  Run URL feeds `VITE_API_BASE_URL`. §10 already establishes a "record the pre-change value"
  discipline — extending it to "record the resolved origin once, then reuse" would close a
  drift class where a mismatch surfaces only as a runtime auth failure. The placeholder
  *style* is correct per core-conduct (resolved from validated state, never fabricated); it is
  the single-source-of-truth that is missing.
- **Node `22` matches the surrounding convention.** `.nvmrc` is `22` and
  `.github/workflows/ci.yml:20` sets `NODE_VERSION: "22"`. Whoever fixes the pinning violation
  should pin consistently across all three, or record explicitly why major-only is accepted —
  pinning Pages to `22.16.0` while CI floats on `22` would trade one drift for another.
- **`isDev: true` is doing two jobs.** §4.5 and T-08 define the *packaged Electron production*
  baseline as byte-identical to `buildCspContent({}, { isDev: true })`. The flag's name says
  "Vite dev server" but it now also means "Electron shell". T-08 makes any future drift fail
  loudly rather than silently, so this is naming clarity, not correctness — but a second named
  option (or a comment at the call site) would stop the next reader concluding the packaged
  app ships a dev policy by mistake.
- **`avatar.ts` builds the object path from a user-supplied filename.** The extension is
  sliced from `file.name` with no character-set or length constraint and concatenated into the
  storage path — precisely the pattern repo `CLAUDE.md` "Path/identifier validation" says to
  constrain. This is pre-existing 03a code and renderer work is explicitly out of 03b's scope,
  so it is not cited; note that a bucket-level MIME/extension allowlist (part of violation 1)
  closes it without touching renderer code.
- **Strength: the human-owned trade-offs were left human-owned.** The three `[SPEC-STAGE]`
  refinements each state their reason and their reject-path, and the host choice is carried
  from the brainstorm rather than decided in the spec. That is what core-conduct's
  "architecture trade-offs stay human-owned" looks like when done right. Follow-up 4 (an ADR
  for this deploy) correctly identifies that the record is still owed.
- **Sequencing and rollback are exemplary.** The SMTP→rate-limit→toggle lockout ordering, the
  append-never-replace CORS trap with a two-sided `curl` proof (§11.2 step 7), and the §10
  rollback table with its "these two values are unrecoverable" call-out are all above the bar
  and should survive any revision.

### Waivers

None. No violations were waived by the user in this round.

## Round 2 — 2026-07-26 — FAIL (2 violations; all 4 round-1 violations resolved)

- **Spec blob:** `535e0eabc743bda7db50634b68ea8d5c21e665fb` · **HEAD:** `cb4224b962953826d8e375ca58a38b901ee0e0fd` (`main`)

### Layman summary

The revision did what it said. I read every section the brief claimed to have changed and
checked each against the repo rather than taking the summary's word for it — all four
round-1 violations are genuinely closed:

- **The avatar bucket now has a lock on the door.** §7.6 grew from four lines to a full
  section: it says outright that the browser uploads straight to Supabase so the bucket's
  own rules are the *only* thing standing between one user and another user's photo, then
  writes the four SQL policies out in full — anyone can look, but you can only write inside
  the folder named after your own real user id. It also caps uploads at 2 MB and to three
  image types, so the bucket can't be used as a free file host. And the smoke test now needs
  **two accounts**, because a one-account test passes against a wide-open bucket and proves
  nothing. Both round-1 findings (1 and 4) are closed by this.
- **The header-stripping typo hole is closed twice over.** The URL parser is tightened to
  accept only letters, digits, dots, dashes and a port — a pasted newline or quote now throws
  and stops the build — *and* a second check sits at the point where the file is written, so
  a future loosening of the first can't silently re-open it. Three new tests pin both.
- **Node is really pinned now** — `22.16.0` in all three places that pick a Node version, with
  a table of what changes where, plus the Cloudflare build image pinned to v3. It also tells
  the implementer to re-confirm that exact patch still exists and, if not, to move all three
  to the same new number — the invariant is "exact and identical", which is the right way to
  write that.

Two new things are blocking, both found by running the spec's own instructions rather than
reading them:

1. **Step 1 of the manual gate now parks a live-credentials file where git can see it.**
   Round 1 I flagged that `rm -f .env.local` was destroying a credentials file; the fix
   renames it to `.env.local.bak` instead — but this repo ignores `.env*.local`, and
   `.env.local.bak` does not match that pattern. I confirmed with `git check-ignore`: the
   renamed file is **untracked and not ignored**, sitting in `apps/desktop/` for the whole
   test-and-deploy run, in a workflow that ends in commits and a PR. One `git add -A` and
   live credentials are in the history. The spec is otherwise strict about this — §7 says
   credentials live outside the repo "deliberately". Fix is one word: rename it to something
   ending in `.local` (e.g. `.env.bak.local`), or move it out of the repo entirely.
2. **The header-diff check in step 9 can never pass, even on a perfect deploy.** It
   lowercases the *whole line* on one side and only the *header name* on the other, so
   `includeSubDomains` and `DENY` come out different on the two sides. I ran the exact
   command against a simulated healthy response: it reports two headers as "dropped in
   transit" when nothing was dropped. That matters more than a typo normally would, because
   this is the *only* gate on the one artifact the whole spec says fails silently — and the
   likely reaction to a check that always cries wolf is to loosen it until it's quiet.

Neither is a rewrite: one word and one `tolower` respectively.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `core-conduct/secrets-out-of-repo` | `~/.claude/rules/core-conduct.md` (Zero-Trust Invariants: secrets stay behind placeholders; "no secrets or absolute paths in committed files"); repo `CLAUDE.md` "Hide sensitive info" | Credentials must not be placed anywhere git can stage them | §11.2 step 1 (manual gate) | Step 1 instructs `mv apps/desktop/.env.local apps/desktop/.env.local.bak`, but `apps/desktop/.gitignore:9` is `.env*.local`, which does not match `.env.local.bak` — verified with `git check-ignore -v` (no match, i.e. **not ignored**) — so a file the spec itself describes as holding "live credentials that exist nowhere else" sits untracked-and-unignored in the working tree across the whole build/deploy gate, one `git add -A` away from the deploy PR. |
| `writing-specs/verification-gate-correctness` | `~/.claude/skills/writing-specs/SKILL.md` ("state explicitly what correct looks like"; a design "precise enough that the agent has nothing left to guess at") | The stated pass condition of a verification step must be achievable when the system is healthy | §11.2 step 9 (and step 10, which reuses it) | The diff normalises the built side with `tolower($0)` (whole line) and the served side with `tolower($1)": "$2` (name only), so `Strict-Transport-Security: …includeSubDomains` and `X-Frame-Options: DENY` differ across the two files; executing the exact command against a simulated healthy response emits both lines under `comm -13`, which the spec labels "MUST be empty: anything here was dropped in transit" — so the only gate on the artifact §9 trap 7 calls silently-failing reports a false drop on every correct deploy and leaves the operator to guess whether to roll back or loosen the check. |

### Notes (non-blocking)

- **Round-1 fixes verified section by section, not accepted on report.** §7.6 now names four
  SQL policies with `(storage.foldername(name))[1] = auth.uid()::text` on insert/update/delete
  and a public `select`; the MIME allowlist and 2 MB limit are in the bucket-settings table;
  §11.2 step 11 requires the two-account negative test; S-15 and S-16 exist; §2 items 9/10,
  §9 traps 3/4, and the §10 rollback rows were all updated to match. §4.1 carries the tightened
  `ORIGIN_RE`; §4.2's "adds no failure mode of its own" is gone and replaced by a throwing sink
  guard; T-11/T-12/T-13 exist. §12 pins Node `22.16.0` in a current→target table plus Pages
  build system `v3`. All eight library versions still match the installed tree exactly (vite
  7.3.6, rollup 4.62.2, vitest 4.1.10, typescript 5.9.3, electron 39.8.10, electron-vite 5.0.0,
  supabase-js/auth-js 2.110.5), and `.nvmrc` = `22` / `ci.yml:20` = `"22"` confirm the
  current→target table's "current" column.
- **The §4.4 widening to all four `VITE_*` does not overreach** — asked directly, my answer is
  no. `supabaseClient.ts:5` really does compare `=== 'true'`, so a presence-only gate would
  wave through a production build with authentication disabled, which is the spec's own worst
  documented trap; closing it is "fail closed on any validation failure", not new scope.
- **Small inconsistency inside that gate:** the two CSP inputs are read from `env` (the
  `loadEnv` result) while `VITE_AUTH_ENABLED`/`VITE_SUPABASE_ANON_KEY` are read from
  `process.env`. On Cloudflare both resolve identically (Pages exports dashboard variables into
  the build environment, and `loadEnv` merges prefixed `process.env` entries), so this is
  correct as written — but a reader will wonder, and one comment would settle it. Related: the
  plugin named `mtg-wizard:csp-headers` now owns a general deployability gate; the placement is
  justified in the spec (gate immediately before `emitFile`), the name just no longer describes
  it.
- **`ORIGIN_RE` has no capture group, but the code it replaces returns `match[1]`.**
  `build/csp.ts:15-20` today does `/^(https?:\/\/[^/?#]+)/.exec(...)` then `return match[1]`;
  the new `^https?:\/\/[A-Za-z0-9.-]+(?::\d{1,5})?(?=$|[/?#])` has only a non-capturing group
  and a lookahead, so a literal constant swap yields `undefined` in every directive. T-05
  (trailing-path reduction) fails loudly the moment that happens, so this is not blocking — but
  one clause saying the origin is `match[0]` removes the guess.
- **§4.2 prose overstates its own snippet.** The text says the *composed body* is asserted to
  contain no CR/LF and to hold exactly the expected number of header lines; the code shown
  checks only `cspLine`. That is sufficient (the other seven values are literals) and T-13
  covers the count, but prose and contract should agree.
- **The UPDATE policy is correct as written** — `using` with no `with check` is fine, since
  Postgres reuses the `USING` expression for `WITH CHECK` when the latter is omitted. Recording
  it so a later reviewer does not "fix" a non-bug.
- **§7.6's heading reads "three halves, all required".** Trivial, but specs get read literally.
- **Carried strengths, unchanged:** the SMTP→rate-limit→toggle lockout ordering, the
  append-never-replace CORS trap with its two-sided `curl` proof, the §10 rollback table with
  its "these values are unrecoverable" call-out, and the three `[SPEC-STAGE]` refinements each
  carrying an explicit reject-path (architecture trade-offs left human-owned). The §5.3 nonce
  rationale, the §10 record-the-origin discipline, and follow-ups 6 and 7 all landed as
  described and none of them expanded scope.

### Waivers

None. No violations were waived by the user in this round.

---

## Round 3 — 2026-07-26 — VERDICT: **PASS**

`repo=mtg-wizard` `branch=main` `head_sha=77cbcc61f8761a80607e553cc66b31ed9ccbc9db`
`spec_blob_sha=aaefdcc5c487f77dac72fab2ca8c40bfe5117754`
Rule sources read: `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
`skills/writing-secure-code/SKILL.md`, repo `CLAUDE.md` (no `.claude/project-standards.md`
exists in this repo).

### Layman summary

Both round-2 problems are genuinely fixed, and I did not take the author's word for either —
I re-ran them.

The first was a credentials-file hazard: the spec told the operator to rename a live-secrets
file to a name the repo's ignore rules did **not** cover, leaving it sitting in the working
tree one careless `git add -A` away from a public PR. The new name is `.env.bak.local`, and
`git check-ignore -v` confirms it is ignored by `apps/desktop/.gitignore:9` while the old
`.env.local.bak` still is not. The spec now also explains *why* the suffix must stay `.local`,
so the next person cannot tidy it back into a hazard.

The second was a broken safety check. The old one compared the built headers against the
served headers using a text diff that lowercased the two sides differently, so it reported
"headers were dropped in transit!" on every *correct* deploy — a smoke alarm that goes off
when nothing is burning gets taped over, which would have left the one thing that catches a
silently-broken deploy effectively disabled. That diff is gone. The replacement,
`check-headers.sh`, checks each of the eight headers by name and compares the security policy
character for character. I extracted it verbatim and ran it against eight fixtures: a healthy
response passes cleanly (exit 0); a misconfigured "localhost" deploy, a response with two
headers stripped, a totally header-less response, a truncated block, and an HSTS carrying
`preload` each fail loudly and name the specific problem. It also survives the trap that broke
the old version — the `data: ` sitting *inside* the policy no longer confuses the parser — and
it handles both lower-case HTTP/2 and mixed-case HTTP/1.1 header names.

I also verified the two things the author flagged as uncertain. The origin-validating regex
now has its capture group and, run in Node, accepts all five origins the app actually uses
while rejecting all fourteen hostile ones (CR/LF injection, userinfo, wildcards, `javascript:`,
protocol-relative). And the storage policies that stop one user overwriting another's avatar —
I stood up a throwaway Postgres database, recreated them, and confirmed that user A cannot
insert into B's folder, cannot touch B's rows, and **cannot rename their own file into B's
folder either**; the database was dropped afterwards.

On the question the author explicitly escalated — whether pinning Node only on Cloudflare
(leaving `.nvmrc`/`ci.yml` at a floating `22`) breaks the pinned-versions rule — my answer is
**no, and the narrowing is the more rule-compliant choice.** Detail in the notes.

No blocking items. Nothing carries to the user for a decision.

### Violations

| # | id | rule_source | where | why |
|---|----|-------------|-------|-----|
| — | — | — | — | **None.** |

Prior-round violations, all re-confirmed resolved at this blob:

| id | round | status at round 3 | evidence |
|---|---|---|---|
| `core-conduct/default-deny-data-store` | 1 | resolved | §7.6 has four explicit policies + MIME allowlist + 2 MB cap; empirically default-deny |
| `writing-secure-code/idor` | 1 | resolved | owner-scoped policies proven in an isolated Postgres: cross-folder insert, cross-row update, and rename-into-B's-folder all rejected |
| `core-conduct/validate-input-at-boundaries` | 1 | resolved | `ORIGIN_RE` (boundary) + §4.2 sink guard + §4.4 four-variable env gate, all throwing |
| `writing-specs/pinned-versions` | 1 | resolved | 8/8 library versions match `apps/desktop/package-lock.json` exactly; Node pinned to exact patch at point of consumption |
| `core-conduct/secrets-out-of-repo` | 2 | resolved | `git check-ignore -v`: `.env.bak.local` → `apps/desktop/.gitignore:9`; `.env.local.bak` → not ignored |
| `writing-specs/verification-gate-correctness` | 2 | resolved | `check-headers.sh` executed against 8 fixtures; healthy → exit 0, six failure modes → exit 1 with specific diagnosis |

### Verification I actually performed

- **`check-headers.sh`, extracted verbatim from §11.2 step 9 and executed** against: healthy
  HTTP/2 response w/ CRLF (→ `OK`, exit 0); trap-2 localhost/no-Supabase (→ `CSP MISMATCH`,
  both strings printed, exit 1); COOP+CORP stripped (→ names both, exit 1); HSTS with
  `preload` (→ `HSTS carries preload`, exit 1); no security headers at all, i.e. trap 7's
  silent `_headers` failure (→ all 8 named + mismatch, exit 1); block truncated after the CSP
  line, i.e. the §4.2 CR/LF failure mode (→ names the 7 lost headers, exit 1); HTTP/1.1
  canonical mixed case (→ `OK`, exit 0); no arguments (→ `set -u` unbound variable, exit 1,
  fails closed). The `data: ` inside `img-src` no longer truncates the comparison.
- **`ORIGIN_RE` executed in Node.** 7/7 accepts (Scryfall, Supabase, Cloud Run, localhost:8000,
  explicit port, trailing path/query/fragment reduced to bare origin per T-05); 14/14 rejects
  (CRLF, bare LF, tab, embedded/trailing space, `;`, `'`, `user:pw@`, wildcard host,
  `javascript:`, `ftp://`, `//a.co`, uppercase scheme). `match[1]` is defined in every accept
  case — the round-2 capture-group defect is gone.
- **§7.6 storage policies executed** in a throwaway `judge_rls_tmp` database (created, tested,
  dropped): `pg_policy` shows the UPDATE policy's `polwithcheck` is NULL; A→B insert **denied**,
  A renaming own row into B's folder **denied**, A updating B's row **0 rows**, A updating
  within own folder **1 row**.
- **Repo cross-references spot-checked:** `src/renderer/index.html:10` meta matches the 03a
  baseline §4.5 replaces; `supabaseClient.ts:5` really is `=== 'true'`; `:22` sets
  `detectSessionInUrl: true`; `App.tsx:20` is `<HashRouter>`; `SignInScreen.tsx:80` is
  `handleOAuth` with buttons at `:162`/`:170`; `avatar.ts` builds
  `${userId}/${crypto.randomUUID()}${extension}` client-side; `config.py:15/20/25`,
  `main.py:31-36` (no `allow_credentials`), `middleware.py:1-5` all as described;
  `vite.config.web.ts` `outDir: out/web`; `.nvmrc` = `22`; `ci.yml:20` = `"22"` consumed at
  `:128`; **`build:web` appears nowhere in `ci.yml`**, confirming §12's central claim.
- **8/8 pinned versions match `package-lock.json`** exactly. No absolute paths, no
  credential-shaped strings, no TBD/TODO/FIXME in the spec. Canonical path
  `docs/superpowers/specs/`. 16 Gherkin scenarios across good/bad/edge, 2 Mermaid diagrams.

### Notes (non-blocking)

- **The Node-pin narrowing is correct, and is the answer to the escalated question.**
  `writing-specs` says pin every library and tool the spec names; the spec names Node for the
  Pages build and pins it to the exact patch `22.16.0` there, which is the only place in the
  deploy path that consumes it. I confirmed `ci.yml` contains no `build:web` invocation and
  declares its own `NODE_VERSION` at `:20`, so CI genuinely does not build the deployed
  artifact and genuinely does not read the root `.nvmrc`. Editing those two files would have
  been a change to files outside the root cause — `core-conduct`'s "fix the root cause, and
  only the root cause; a drive-by cleanup is its own task." The round-2 shape was the one in
  tension with the rules; this one is not. The residual CI/Pages float is real, harmless, and
  recorded as §13 follow-up 8, which is the "surface it as a human-owned decision" disposition
  the rules ask for. **Nothing here needs to go to the user.**
- **The three `[SPEC-STAGE]` items are legitimately open, but their resolution must land in the
  spec text.** Leaving §4.4, §6 and §7.1 for the human review gate is exactly what
  `core-conduct`'s "architecture trade-offs stay human-owned — implement once decided, don't
  decide" requires, and each states its reject-path precisely, so neither branch is ambiguous.
  The one thing to watch: once the user accepts or rejects each, edit the decision *into* the
  spec (including the §4.3/§4.4 plugin-name fork) rather than leaving the decision only in chat
  — a spec that still reads as conditional at implementation time is a spec the builder can
  read two ways.
- **§7.6's 📌 note reaches the right conclusion via a weaker reason than the real one.** It
  argues the `using`-only UPDATE policy is safe because "the path is the row's identity and is
  not being rewritten" — an assumption about caller behaviour. The actual guarantee is
  stronger and does not depend on that: Postgres reuses the `USING` expression as `WITH CHECK`
  when the latter is omitted, so a rename into another user's folder is rejected by the
  database regardless. I proved this directly (T2 above). Swapping in the stronger reason would
  make the note bulletproof, and matches what round 2 recorded.
- **Minor line-reference drift.** §7.6 and §13 follow-up 7 cite `avatar.ts:15-16` for the
  unvalidated extension; in the tree the extension is derived at `:13-14` and the path built at
  `:15`. Harmless, but line cites decay — the surrounding quoted code is unambiguous.
- **Whether `.trim()` survives in `toOrigin` is unstated.** Today's `build/csp.ts:15` trims
  before matching; §4.1 shows only the new constant, yet lists "a trailing space" among rejected
  values — implying the trim is dropped. Both readings fail closed (a stray space in a
  Cloudflare dashboard variable would abort the build rather than emit a bad policy), so this
  is not ambiguity with a safety consequence. Worth one clause anyway, because "the build
  aborted and the variable looks fine" is a confusing five minutes at §11.2 step 5.
- **Spec size.** At 1036 lines / 56.6 KB this is the largest spec in `docs/superpowers/specs/`,
  and §9's eight traps partly restate §4.4, §4.6, §6, §7.1, §7.4 and §7.6. Against
  `writing-specs`' tokenization guidance that is a fair thing to flag — but the duplication is
  a deliberate operator checklist for a change that is 90% hand-execution across four consoles,
  the traps mostly cross-reference rather than re-explain, and the density is earned by the
  subject. Not a defect; recorded so it is a considered choice rather than drift.
- **Carried strengths.** The lockout ordering, append-never-replace CORS with its two-sided
  `curl` proof, the §10 "these two values are unrecoverable" call-out, the §11.2 step 7
  `AUTH_ENABLED` check, the two-account avatar test at step 11, and the §5.3 nonce/COEP/
  `X-XSS-Protection` rejections all survive round 3 intact. §11.2 step 9's admission that the
  previous gate "was not run" — and why that mattered — is the kind of thing specs almost never
  record and should.

### Waivers

None. The user waived nothing in this round, and no violation was carried forward unwaived.

---

## Round 1 — re-entry after the round-3 pass went stale (2026-07-27)

**Spec:** `docs/superpowers/specs/2026-07-25-03b-deploy-design.md`
**Repo:** `mtg-wizard` · branch `main` · HEAD `7cebafd40942853f91a4b85a772f187a9ede52bb`
**Spec blob:** `d8bf2851bca9088a2fa23d45530fc46fdc7e3171` (round-3 pass was against `aaefdcc5…`)
**Verdict: FAIL** — 1 violation. Confidence: **high** (every claim below was executed, not reasoned about).

### Layman summary

The spec is in very good shape. Everything it says it verified, it really did verify — I
re-ran all of it and it holds up. The one thing that does not hold up is the **final safety
check itself**: the little script in §11.2 step 9 that is supposed to prove the deployed site
is actually serving its security headers.

The script's *comparison logic* is now genuinely good — I fed it six deliberately broken
deployments and it caught all six, including the sneaky one where all eight headers are
present but every value is wide open. That was the defect two earlier rounds found, and it is
fixed.

The problem is what surrounds it. The two commands the spec tells a human to type cannot both
run from the same folder (one needs to be inside `apps/desktop`, the other needs to be at the
repo root), and they refer to three variables the spec never tells anyone to set. When those
commands fail — which they will, on the first try — the shell has already created an **empty**
"expected headers" file, and the script has no guard against that. It then loops over nothing,
finds no problems, and prints:

> `OK: all 8 headers present with exact expected values, no preload`

…and exits 0. I proved this against the *wide-open* fixture: HSTS `max-age=0`,
`X-Frame-Options: ALLOWALL`, `Referrer-Policy: unsafe-url`, `Permissions-Policy: camera=*`.
The gate said OK. So the one mechanism that verifies the security headers this entire
workstream exists to ship can report success on a deployment that has none of them.

The fix is small — make the script refuse to run on an empty or missing expected file, check
the generator's exit status, and state the working directory and the variables to export.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/verification-gate-correctness` | `~/.claude/skills/writing-specs/SKILL.md` | "State explicitly what correct looks like, what wrong looks like, and enumerate the edges. Anything you leave implicit, the agent infers — and inference is where the defects come from." Compounded by `rules/core-conduct.md`: "fail closed on any validation failure." | §11.2 step 9 (`check-headers.sh` + its invocation block) | The gate's comparison logic is correct, but its harness fails **open**: with an empty or missing `expected.headers` the script prints `OK: all 8 headers present with exact expected values, no preload` and exits 0 against a wide-open deploy — and the documented command block reliably produces exactly that empty file. |

**Evidence (all executed 2026-07-27):**

1. **The comparison logic is sound — the spec's six-fixture claim is true.** I rebuilt v3
   verbatim and ran it against realistic `curl -sI` HTTP/2 output with CRLF endings and extra
   Cloudflare headers: healthy ⇒ `OK`, exit 0; trap-2 localhost/no-Supabase CSP ⇒
   `HEADER VALUE MISMATCH` printing both strings, exit 1; all eight present but weakened ⇒
   named all four (`permissions-policy`, `referrer-policy`, `strict-transport-security`,
   `x-frame-options`), exit 1; HSTS `preload` ⇒ both the mismatch and `HSTS carries preload`,
   exit 1; COOP+CORP dropped ⇒ named both, exit 1; HSTS absent ⇒ `MISSING HEADER`, exit 1.
   The `norm()` sed/awk pipeline correctly splits on the **first** `": "` only, so the CSP's
   internal `data: ` does not corrupt the field split. **Nothing to fix here.**
2. **`npm run headers:expected` cannot run from the repo root.** Confirmed there is no root
   `package.json` (§7.1 itself says so); `npm run headers:expected` at the root exits
   `ENOENT … /mtg-wizard/package.json`. But the very next line of the same block invokes
   `./apps/desktop/build/check-headers.sh`, a path that only resolves **from** the root. No
   single working directory runs the block as written, and the spec never states one.
3. **`$PREVIEW_URL`, `$VITE_API_BASE_URL`, `$VITE_SUPABASE_URL` are never defined.** They are
   Cloudflare *dashboard* variables (§7.1), not shell exports, and no step tells the operator
   to export them.
4. **The fail-open.** `> expected.headers` truncates before the generator runs, and
   `check-headers.sh` validates neither `$#`, nor the generator's exit status, nor that
   `$expected` is non-empty. With `set -uo pipefail` (no `-e`), a failed `sort "$expected"`
   only writes to stderr. The `while` loop then iterates **zero** times, the preload grep
   finds nothing, `rc` stays 0. Verified against the weakened fixture:
   - expected file **missing** ⇒ `sort: No such file or directory` (stderr) then
     `OK: all 8 headers present with exact expected values, no preload`, **exit 0**
   - expected file **empty** ⇒ same `OK`, **exit 0**
5. **The cry-wolf half, for completeness.** If the generator instead *succeeds* with empty
   flags, `build/csp.ts:23` (`env.VITE_API_BASE_URL || DEFAULT_API_BASE_URL`) and `:27`
   (`env.VITE_SUPABASE_URL ? … : []`) treat `''` as falsy, so the expectation becomes the
   **localhost fallback** — precisely the "wrong artifact" the spec's own ⚠️ warns against —
   and a perfectly healthy production deploy reports `HEADER VALUE MISMATCH:
   content-security-policy`. That is the v1 failure mode returning through the harness rather
   than the logic. Demonstrated.
6. **Disproved a suspected defect:** npm 12.0.1 writes its `> pkg script` banner to **stderr**,
   so `npm run … > expected.headers` does *not* pollute the file. That concern does not apply.

### What I re-verified and found clean

- **§4.1 `ORIGIN_RE` — every claim holds.** Ran `/^(https?:\/\/[A-Za-z0-9.-]+(?::\d{1,5})?)(?=$|[/?#])/`
  behind the retained `.trim()` (confirmed live at `build/csp.ts:15`). Accepted and reduced to
  bare origins: `https://cards.scryfall.io`, `https://<ref>.supabase.co`,
  `https://core-api-<n>.us-east1.run.app`, `http://localhost:8000`, `https://a.co:8443`, and
  values carrying a trailing path/query/fragment; **surrounding whitespace is stripped and
  accepted**, exactly as §4.1's corrected paragraph states. Threw on all ten hostile values:
  CR/LF injection, bare LF, interior space, trailing `;`, trailing `'`, `user:pw@` userinfo,
  wildcard host, `javascript:`, `ftp://`, protocol-relative `//a.co`. The capture-group caveat
  is real and correctly documented.
- **§7.6's `using`-without-`with check` — verified on PostgreSQL 16.14.** With a permissive
  SELECT policy present (as the spec has), an UPDATE policy carrying only `USING` had that
  expression reused as `WITH CHECK`: A renaming its **own** row into B's folder ⇒
  `ERROR: new row violates row-level security policy`; A updating B's row ⇒ `UPDATE 0`; A
  renaming inside its own folder ⇒ `UPDATE 1`; A inserting into B's folder ⇒ denied. The 📌
  note is correct and now rests on the strong reason, not the caller-behaviour one.
- **§4.4 `findDeployProblems` + T-14.** The failure branch is genuinely covered: T-14 asserts
  `[]` for a full env, each of the three presence checks reported **by name**, and
  `VITE_AUTH_ENABLED` of `'True'`/`'TRUE'`/`'1'`/`''`/`undefined` each producing a problem while
  `'true'` alone does not. The exact-string comparison matches
  `supabaseClient.ts:5` (`import.meta.env.VITE_AUTH_ENABLED === 'true'`, confirmed live), so
  trap 2's dangerous half is closed. `{ ...env, ...process.env }` cannot clobber a value with
  `undefined` (absent keys are not spread), so the widened gate is sound.
- **Internal consistency.** No `cspHeadersPlugin` / `mtg-wizard:csp-headers` anywhere except
  the §4.4 sentence that forbids it; §3, §4.3 and §4.4 all use `pagesBuildGatePlugin`. No
  TBD/TODO/FIXME. No option left reading as open — the three refinements are written in as
  settled. Header counts agree (§3's "header CSP + 7 headers" = the 8 of S-01/T-09/step 9).
  §4.5's target string is byte-consistent with §4.1's canonical directive order under
  `isDev: true`. Scenario ids are all unique.
- **Repo cross-references, re-checked live:** `csp.ts:15` `.trim()` ✓; `csp.ts:23/27` falsy
  fallbacks ✓; `supabaseClient.ts:5` ✓ and `:22` `detectSessionInUrl: true` ✓;
  `avatar.ts:13-15` unvalidated extension + client-built `${userId}/…` path ✓; `App.tsx:20`
  `<HashRouter>` ✓; `config.py:15` CORS default incl. `null`, `:20` `auth_enabled: bool = False`,
  `:23-25` `avatar_url_prefix: str = ""` ✓; `main.py:31-36` `CORSMiddleware` with **no**
  `allow_credentials` ✓; `index.html:10` ✓; `.gitignore:9` = `.env*.local` — `git check-ignore`
  confirms `.env.bak.local` **is** ignored and `.env.local.bak` is **not** ✓; root `.nvmrc` =
  `22` with none in `apps/desktop` ✓; `ci.yml:20` `NODE_VERSION: "22"` consumed at `:128` ✓;
  `build:web` = `npm run typecheck:web && vite build …` ✓; **38 test files** matches the step-2
  baseline ✓.
- **Previously-cited rules, all still satisfied:** `core-conduct/default-deny-data-store` (§7.6
  states the bucket's access policy explicitly and proves the deny), `writing-secure-code/idor`
  (owner-scoped policies + the two-account S-15 test), `core-conduct/validate-input-at-boundaries`
  (§4.1 boundary + §4.2 sink, both asserted), `writing-specs/pinned-versions` (§12, plus "no
  dependency is added, removed, or upgraded"), `core-conduct/secrets-out-of-repo` (§7's
  placeholder statement; nothing credential-shaped in the file). **None re-cited.**
- Files the spec edits are small — `build/csp.ts` 50 lines, `vite.config.web.ts` 52 — nowhere
  near the 400-line guidance. Canonical spec path ✓. 16 Gherkin scenarios across good/bad/edge,
  2 Mermaid diagrams, background present.

### Notes (non-blocking)

- **§4.4's last bullet slightly overclaims.** "T-14 covers its failure branch, so the abort path
  is exercised by the suite" — T-14 exercises `findDeployProblems` (the *detection*). The
  `this.error()` **abort** itself has no listed automated test; only S-06 describes it. T-14's
  own row is accurate, so this is prose drift, not a gap in the test table. Worth one clause.
- **`/tmp/_served.norm` and `/tmp/_expected.norm` are fixed, predictable paths.** With no
  `set -e`, a write that fails leaves the *previous* run's content in place — a second way the
  same script can compare against something other than what it just fetched. Same one-line fix
  as the violation (guard the inputs); mentioned separately because the cause is different.
- **Scenario ids are unique but out of numeric order** — S-15/S-16 sit in "Bad paths" ahead of
  S-09–S-14 in "Edge cases". Cosmetic; the cross-references all resolve.
- **`build/check-headers.sh` and the `headers:expected` package script are new committed repo
  files** introduced in §11.2/§4.2 but not listed in §2 Scope. Harmless, but §2 is what a
  reviewer reads to know what lands.
- **`iwqvvnrkafajdzdhbltk` in §7.1 is not a secret leak** — the Supabase project ref ships in
  every client bundle by design. Recorded so a future reader does not flag it.
- **The spec's own honesty about step 9 remains its best feature.** It records that two earlier
  versions of this gate were specified without being run, and why that mattered. This round's
  finding is in the same spirit: the logic is now right, the harness around it is not yet.

### Waivers

None. No violation on this spec has been waived by the user at any round.

---

## Round 2 — re-entry cycle — 2026-07-27 — VERDICT: **PASS**

**Spec:** `docs/superpowers/specs/2026-07-25-03b-deploy-design.md`
**Repo:** mtg-wizard · branch `main` · HEAD `aa3b07b9c52254bad390be47f2519f96e7050595`
**Spec blob at read time:** `4029a56876c29e7b2597bcce93cc6459d8c95ed0` (matches the dispatch brief)
**Rule sources read:** `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
`skills/writing-secure-code/SKILL.md`, repo `CLAUDE.md`. No `.claude/project-standards.md`
exists in this repo — confirmed, not assumed.

### Layman summary

The one thing that failed last round is genuinely fixed, and I know that because I ran it
rather than read it. The `_headers` verification gate is a shell script that compares the
security headers a real deployment serves against the headers the build says it should
serve. Last round the comparison logic was correct but the *scaffolding* around it was
not: the copy-paste block in the spec reliably produced an empty "expected" file, and an
empty expected file made the script compare nothing and cheerfully print `OK` — a deploy
with no security headers at all would have passed.

I rebuilt sixteen fixtures from scratch and ran the new script against all of them. All
seven results the author claimed reproduce exactly. More importantly, I reproduced the
original defect end to end: running the generator the old way (from the repo root, no
subshell) still exits 254 and still leaves an empty file — so the root cause was real —
and the new script now refuses that file with `FATAL … exit 2` instead of passing it. Both
halves of the fix are load-bearing and both work. I also confirmed the two repo facts the
fix depends on: there is genuinely no root `package.json` (so the `cd apps/desktop`
subshell is necessary, not decoration) and the installed npm really is 12.0.1, matching the
spec's claim about the `--silent` banner.

The four other edits the author made off the back of the advisory read are all clean. The
Supabase redirect-allowlist "append, never replace" rule in §10 is consistent with trap 1 —
it applies the same hazard to a second list, and it correctly does *not* apply it to the
Site URL, which is a single-valued field that genuinely is replaced. The §4.4 sentence that
used to overclaim what test T-14 exercises now says exactly what it does and does not cover.
No new contradictions, no new scope, nothing that reads two ways.

Three small things go in the notes rather than the violations list. None of them can turn a
broken deploy into a green check on any realistic path, and after four revisions of this one
gate I am not going to manufacture a fifth round out of cosmetics. The most interesting is
that the script's "did I compare everything?" guard counts *lines* rather than *distinct
header names*, so a hypothetical generator that emitted the same header twice could still
hide a missing one — but that requires a bug in a function two unit tests already pin.

### Violations

**None.** `violations` is empty; the verdict is `pass`.

Prior-round violation status:

| id | status |
|---|---|
| `writing-specs/verification-gate-correctness` | **RESOLVED — verified by execution, not by reading.** Not re-cited. |
| `core-conduct/default-deny-data-store` | still satisfied (§7.6 unchanged) |
| `writing-secure-code/idor` | still satisfied (owner-scoped policies + two-account S-15) |
| `core-conduct/validate-input-at-boundaries` | still satisfied (§4.1 boundary + §4.2 sink) |
| `writing-specs/pinned-versions` | still satisfied (§12; no dependency added/removed/upgraded) |
| `core-conduct/secrets-out-of-repo` | still satisfied (§7 placeholders only) |

No two-consecutive-round persistence. Nothing to escalate.

### Verification I actually performed

Script extracted verbatim from §11.2 step 9 into `/tmp/cj-r2/` (the repo was never written
to). `bash -n` clean. Sixteen fixtures, exit codes captured individually:

| # | Fixture | Result | Claimed? |
|---|---|---|---|
| A | healthy deploy, CRLF, HTTP/2, extra CF headers | `OK`, **exit 0** | ✓ matches |
| B | empty `expected` + wide-open deploy *(the v3 defect)* | `FATAL`, **exit 2** | ✓ matches |
| C | `expected` file absent | `FATAL`, **exit 2** | ✓ matches |
| D | 7-line truncated `expected` | `FATAL … want 8`, **exit 2** | ✓ matches |
| E | all 8 present but weakened | 5 mismatches named, **exit 1** | ✓ matches |
| F | HSTS carries `preload` | mismatch + `HSTS carries preload`, **exit 1** | ✓ matches |
| G | empty served file | `FATAL`, **exit 2** | ✓ matches |
| H | served names Title-Case (HTTP/1.1 proxy) | `OK`, **exit 0** — normaliser holds | new |
| I | served missing `x-frame-options` | `MISSING HEADER`, **exit 1** | new |
| J | CR/LF truncation — only CSP survives | 7 × `MISSING`, **exit 1** | new |
| K | `expected` has a **duplicated** name, served missing a header | `OK`, **exit 0** ⚠️ | new — see notes |
| L | wrapper left the two-space indent on | 8 × `MISSING`, **exit 1** | new |
| M | wrapper emitted the raw `/*` body, Title-Case | 8 × `MISSING`, **exit 1** | new |
| N | served duplicates a header, weak copy sorts second | `OK`, **exit 0** ⚠️ | new — see notes |
| O | served is an HTML error page, not headers | 8 × `MISSING`, **exit 1** | new |
| P | `expected` written with CRLF endings | mismatch (expected == served visually), **exit 1** | new |

Invocation-block behaviour, run verbatim against a stub generator in a throwaway tree:

- **Success path** — `( cd apps/desktop && npm run --silent headers:expected -- --api … --supabase … )`
  produced exactly 8 clean lines, no banner, flags passed through `--` correctly. `npm --version`
  = **12.0.1**, matching the spec's recorded value.
- **Generator-failure path** — a generator that writes partial output then exits 1: the `||`
  guard fired, deleted the truncated file, and stopped. Running the checker anyway on the
  deleted file ⇒ `FATAL … exit 2`.
- **Round-1 defect reproduction** — the *old* form (no subshell, `npm run` from the repo root)
  still exits **254** and still leaves a **0-byte** `expected.headers`. Fed to the v4 script
  that file now yields `FATAL … exit 2`. Root cause fixed *and* backstopped.

Repo facts checked directly, not taken from the brief: no root `package.json` ✓ (so the
subshell is necessary); `headers:expected` is genuinely a new script — `apps/desktop/package.json`
has 19 scripts and none of that name ✓; `apps/desktop/build/` contains `csp.ts` + `csp.test.ts`
and no `check-headers.sh` yet ✓.

Internal consistency re-checked: scenario ids **S-01…S-16 complete and contiguous**, test ids
**T-01…T-14 complete**, zero `TBD`/`TODO`/`FIXME`/placeholder markers, and the spec's claim that
the stale `cspHeadersPlugin` / `mtg-wizard:csp-headers` name "appears nowhere" holds — the only
two hits are the sentence prohibiting it. Canonical spec path ✓.

Per the brief I did **not** re-derive `ORIGIN_RE`, `findDeployProblems`/T-14, or the
`USING`-as-`WITH CHECK` behaviour; those were verified in the prior round and their sections
are unchanged.

### Notes (non-blocking)

- **The `checked -ne WANT` guard counts lines, not distinct header names (fixture K).** Its
  stated job is "the comparison was not short-circuited", and for the malformed-file case it
  does that. But if `headers:expected` ever emitted the same header name twice inside eight
  lines, `exp_n` = 8 and `checked` = 8 both pass while one real header goes entirely
  unverified — my fixture K prints `OK` against a deploy missing `x-frame-options`. This needs
  a generator defect that T-09 and T-13 already target, which is why it is a note; if the
  author wants belt-and-braces, `sort -u` on the expected names and comparing that count to
  `WANT` closes it in one line.
- **The exit-code contract contradicts itself in one branch.** Line 1023 states `2` = the check
  could not be trusted and warns that "collapsing 2 into either of the others is what made the
  previous revision fail open" — but line 1011's `FATAL: compared $checked headers … comparison
  was incomplete` sets `rc=1`, i.e. reports an untrustworthy *check* as a wrong *deploy*. The
  direction is safe (still non-zero, still blocks) and the branch is near-unreachable behind the
  `exp_n` guard, so this misdirects a debugger rather than hiding a fault. One character.
- **S-06 is the only scenario with no verification step mapped to it.** §4.4 is now honest that
  T-14 asserts the decision and not the `this.error()` abort, and that §11.2 step 5 confirms the
  wiring — but step 5 only ever observes the *success* log line. Nothing in §11.2 deliberately
  misconfigures a Preview build to watch the deploy fail. Blanking one Preview variable once,
  during step 3's preview window, would exercise the branch that guards the spec's worst trap
  for about two minutes of effort.
- **A served header duplicated with a weaker second copy is not caught (fixture N)** — `grep …
  | head -1` after `sort` takes the lexically-first value. Cloudflare Pages serves one `/*` rule
  so this is close to hypothetical, and for CSP specifically browsers intersect duplicates, which
  fails safe. Recorded for completeness only.
- **§2 scope item 5 says the Site URL + redirect allowlist are "pointed at" the pages.dev
  origin**, which reads as *replace*, while §10 now correctly requires *append* for the
  allowlist. §10 is the normative statement and is unambiguous, so this is wording drift in the
  summary section, not a conflict. Likewise the redirect-allowlist hazard lives only in §10 —
  §9's trap list, which a reader may work as the checklist, still carries only trap 1's CORS
  twin. Answering the brief's direct question: **§10's append rule is consistent with trap 1**,
  and correctly does not extend to the single-valued Site URL.
- **`build/check-headers.sh` and the `headers:expected` script are still absent from §2 Scope**
  (carried over from the prior round). Two new committed repo files that a reviewer reading §2
  would not expect; §6 also does not say which step commits them.
- **The empirical claims in this spec are now reliable.** Every fixture result the author
  reported reproduced, the npm version claim held, and the two repo facts underpinning the fix
  are true. That is a change in kind from the earlier revisions of this gate, which were
  specified without being run — and it is the reason this round is a pass.

### Waivers

None. No violation on this spec has been waived by the user at any round.

---

## Round 1 — second re-entry cycle — 2026-07-27 — VERDICT: **FAIL** (1 violation)

**Spec:** `docs/superpowers/specs/2026-07-25-03b-deploy-design.md`
**Repo:** mtg-wizard · branch `main` · HEAD `426bd4d72ec6513391d45159bef2ce5c25b0b213`
**Spec blob at read time:** `93f5d367aab4cd2c9df1ea6db5e0b87e47dd48f0` (matches the dispatch brief)
**Rule sources read:** `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
`skills/writing-secure-code/SKILL.md`, repo `CLAUDE.md`. No `.claude/project-standards.md`
exists in this repo — re-confirmed by listing `.claude/`, not assumed.

### Layman summary

The nine edits are good. I rebuilt the header-checking script from the spec character by
character and ran it against **sixteen** fixtures — the eleven the author claimed, plus five
of my own designed to break it. Every one of the author's claimed results reproduced exactly,
including the two new ones that motivated this round: a deploy sending `X-Frame-Options`
twice with contradictory values is now caught and *named* (and I checked it both ways round,
with the good copy sorting first and with the bad copy sorting first — the old version's
outcome depended on that coin flip; the new one does not), and a CR-laden expected-file now
passes cleanly instead of producing a nonsense "mismatch" between two identical-looking
strings. My five extra fixtures — an expected-file with eight distinct names but nine lines,
a duplicate served header with *identical* values, someone pasting the raw indented
`_headers` body instead of running the generator, a completely malformed expected-file, and
a 404 error page served instead of the site — all fail closed, four of them with the
`FATAL … exit 2` that means "don't trust this check" rather than "the deploy is broken".
Nothing in the five script changes introduced a new hole.

Items 6–9 are consistent. §2 item 5, §9 trap 1 and §10 now all say the same thing about the
Supabase redirect allowlist (append, never replace) and all three correctly exempt the
single-valued Site URL, which is meant to be replaced. §11.2 step 6's new claim — that it,
not the step-5 build-log read, is the real defence against a typo'd `VITE_API_BASE_URL` — is
not just consistent, it is *correct*: I traced it, and step 9's invocation block resolves its
origins "from the Cloudflare dashboard … the two origins the Pages project is actually
configured with", which is the same possibly-typo'd value that built the served headers. A
typo really would agree with itself and pass green there. That is an honest self-assessment
of the gate's own blind spot, and the mitigation is placed correctly.

One thing is wrong, and it is small, and it is in the exact contract the author asked me to
confirm. The spec now says three times, emphatically, that **every** untrustworthy-check path
exits `2` and never `1` — because collapsing those two codes is what made an earlier revision
fail open. The invocation block's code does exactly that (`exit 2`, with an inline comment
spelling out why). But the bullet list directly beneath it, headed "Three details are
load-bearing, all of them former defects", still labels that same construct
`|| { rm -f …; exit 1; }`. So the spec states the exit code of one path two different ways,
in the one contract it identifies as its most historically fragile, in a list whose whole
purpose is to tell the implementer which details must not be dropped.

I want to be plain about severity, because the author asked me to be: this is a **one-character
documentation fix**, not a design problem, and it cannot fail open — a generator failure stops
the process loudly either way, and the checker never runs. I am citing it rather than noting it
for one reason only: the spec is the artifact an agent builds from, and an agent handed "here
are the three load-bearing details" will read `exit 1` there. That is a requirement readable
two ways, which is a rule hit, and the cheapest possible kind to close.

**This is not a recurrence.** `writing-specs/verification-gate-correctness` (the fail-open
harness) is genuinely resolved — I re-verified it by execution across all sixteen fixtures. I
deliberately minted a *new* id rather than reusing that one, even though both live in §11.2
step 9, so the caller's persistence detection does not read a resolved violation as
two-rounds-running and escalate on a false positive.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/unambiguous-requirements` | `skills/writing-specs/SKILL.md` | No requirement may be readable two ways — the spec is the source of truth an agent builds from | §11.2 step 9 — "Three details are load-bearing" bullet 2 (line 1091) vs. the invocation block (line 1081) | The generator-failure path is written as `exit 2` in the code block and as `exit 1` in the bullet that labels it, contradicting the same section's stated three-valued contract that no untrustworthy-check path may return 1. |

### Fixture log — executed, not read (16 cases)

Author's eleven, all reproduced as claimed:

| # | fixture | result |
|---|---|---|
| F1 | healthy deploy (CRLF served, status line + CF extras) | `OK` / 0 |
| F2 | empty expected-file vs. healthy served | `FATAL` / 2 |
| F3 | missing expected-file | `FATAL` / 2 |
| F4 | 7-line truncated expected | `FATAL` / 2 |
| F5 | 8-line expected, 7 distinct names | `FATAL` / 2 |
| F6 | empty served-file | `FATAL` / 2 |
| F7 | `x-frame-options` served twice, `DENY` + `SAMEORIGIN` | `DUPLICATE HEADER`, both listed / 1 |
| F7b | same, bad copy (`ALLOWALL`) sorting first | `DUPLICATE HEADER`, both listed / 1 |
| F8 | CR-laden expected-file | `OK` / 0 (both sides normalised) |
| F9 | all 8 present but weakened | names all four / 1 |
| F10 | a genuinely missing header | `MISSING HEADER` / 1 |
| F11 | HSTS carrying `preload` | `HSTS carries preload` / 1 |

My five, none of which the author ran:

| # | fixture | result | verdict |
|---|---|---|---|
| A | expected: 8 distinct names but 9 lines (one name, two values) | mismatch printed, then `FATAL: compared 9 headers, want 8` / **2** | fails closed; the `checked` guard catches what `sort -u` lets through |
| B | served duplicates a header with an **identical** value | `DUPLICATE HEADER` / 1 | conservative, arguably a false positive, but errs safe |
| C | expected pasted as the raw indented `_headers` body | `FATAL: 0 distinct header names` / **2** | the "don't hand-paste it" warning is enforced, not just advised |
| D | expected entirely malformed (`name=value`) | `FATAL: 0 distinct header names` / **2** | no vacuous `OK` |
| E | served is a 404 error page (non-empty, no headers) | all 8 `MISSING HEADER` / 1 | loud |
| F | served with HTTP/1.1 mixed-case header names | `OK` / 0 | name-lowercasing works on both sides |

### Notes (non-blocking)

- **F/B above:** an identical duplicate is reported as a defect. Defensible, and I would not
  change it, but worth knowing the gate is stricter than RFC 9110 requires.
- **§11.2 step 6's redirect-allowlist survival check** doesn't say what to do when the recorded
  allowlist had no *other* entries to exercise — and §7.3 states local dev never signs in, which
  is where a pre-existing entry would most likely point. A half-sentence ("if the recorded list
  had no other entries, record that and skip") would close it. Not a contradiction, just an
  under-specified branch of a manual step.
- **A failed/redirected `curl`** that still returns a non-empty header block (e.g. a Cloudflare
  Access login interstitial) reports as `1` — "the deploy is wrong" — when the truthful answer is
  "the check couldn't reach the deploy". The `-sSI` and `-s` guards catch the empty case; this one
  slips into the wrong bucket. Very low likelihood on a public `pages.dev` preview.
- **Spec length** is now 1243 lines / 71 KB for a change that is ~10% code. The growth is
  targeted correctness prose, not padding, and three prior rounds accepted it — recording it only
  because `writing-specs` treats tokenization as a hard constraint and this is the largest spec in
  the repo by a factor of two.

### Waivers

**None.** No violation has ever been waived on this spec.

### Prior-round violation status

| id | status |
|---|---|
| `writing-specs/verification-gate-correctness` | **RESOLVED, re-verified by execution** across 16 fixtures. Not re-cited. |
| `core-conduct/default-deny-data-store` | still satisfied (§7.6 unchanged this round) |
| `writing-secure-code/idor` | still satisfied (§7.6 owner-scoped policies + two-account S-15) |
| `core-conduct/validate-input-at-boundaries` | still satisfied (§4.1 `ORIGIN_RE` + §4.2 sink guard, unchanged) |
| `writing-specs/pinned-versions` | still satisfied (§12; no dependency added/removed/upgraded) |
| `core-conduct/secrets-out-of-repo` | still satisfied (§7 placeholders only) |

No violation has now appeared in two consecutive rounds. Nothing to escalate.

---

## Round 1 (fresh cycle) — 2026-07-27T21:13:03Z — **PASS**

**Spec blob:** `b909d1784300c0ebae15ee807aef394140721a89` · **HEAD:** `c1b57a107a66eab1801795eed52b765e660646f5` · branch `main`
**Re-entry after the r3 edit** (a spec edit restarts the round counter per `running-the-compliance-judge`).

### Layman summary

The one thing I failed this spec for last round is fixed, and the new work does not break
anything. Last round the spec told the reader "exit 1" in a sentence describing a line of code
that actually said "exit 2" — small, but it sat in a list the spec itself labels "load-bearing",
so a reader following the prose would have mis-wired the one signal that distinguishes "the
deploy is broken" from "the check itself is untrustworthy". The sentence now says `exit 2`. The
only `exit 1` left anywhere in the document is the status line's own history note describing what
an earlier revision did, which is correct.

The bigger change this round is that the header-checking script now looks at the **HTTP status
line**. This mattered: Cloudflare serves those eight security headers on error pages too, so a
stale or mistyped preview URL returned a 404 whose headers were all perfect, and the previous
script printed `OK`. I rebuilt that case and confirmed it — and confirmed the fix. The script now
refuses anything that is not a final `200`.

I did not take the reported fixture results on trust. I extracted the script verbatim from the
spec and ran **28 cases** against it, including eleven the spec never claims. Every documented
case behaved exactly as documented. The most valuable new addition is **T-15**, which turns those
fixtures into a real committed test — this gate has been holed five times, every time by someone
who *ran* it and never by someone who read it, so converting the prose into something that
executes is the correct structural fix rather than a sixth round of careful reading.

**Nothing that remains fails open under the documented procedure.** The residual items below are
either explicitly disclosed by the spec or unreachable without deviating from its own commands.

### Violations

**None.** Verdict `pass`.

| id | status |
|---|---|
| `writing-specs/unambiguous-requirements` (r3) | **RESOLVED.** §11.2 step 9 bullet now reads `exit 2`, matching the code block at spec line 1110. Verified by grep: the sole surviving `exit 1` is the history note at line 6. |

### Verification by execution — 28 cases, script extracted verbatim from spec lines 992–1083

All 17 cases the spec claims (§11.1 T-15 and §11.2 step 9's v6 paragraph) reproduce exactly:

| case | got | want |
|---|---|---|
| healthy 200 / HTTP/1.1 200 OK | `OK` / 0 | 0 ✅ |
| **404 carrying eight perfect headers** | `FATAL` / **2** | 2 ✅ |
| **500 / 400 / 304 with perfect headers** | `FATAL` / 2 | fails closed ✅ |
| **redirect chain 301 → final 200** | `OK` / 0 | 0 ✅ (last-status-line logic correct) |
| **chain presenting a non-final 200 (200 → final 404)** | `FATAL` / 2 | 2 ✅ — this is the case "last" exists for |
| **served file with no status line** | `FATAL` / 2 | 2 ✅ |
| empty served / empty expected / missing expected | `FATAL` / 2 | 2 ✅ |
| truncated (7-line) expected / duplicate name in expected | `FATAL` / 2 | 2 ✅ |
| duplicate header, **both sort orders** + identical duplicate | `DUPLICATE HEADER` / 1 | 1 ✅ |
| genuinely missing header | `MISSING HEADER` / 1 | 1 ✅ |
| all eight present, four weakened | 1, **names all four** | 1 ✅ (verified verbatim) |
| HSTS `preload` | 1 | 1 ✅ |

Eleven additional adversarial cases the spec does **not** claim: 200 with zero security headers → 1;
CSP off by one directive (`frame-ancestors` dropped) → 1; header with no space after colon → 1;
obs-fold continuation → 1; lowercase `http/2 200` status → 2. All fail closed.

**Pinned versions re-verified against `apps/desktop/package-lock.json`:** vite 7.3.6, rollup
4.62.2, vitest 4.1.10, typescript 5.9.3, electron 39.8.10, electron-vite 5.0.0,
@supabase/supabase-js 2.110.5, @supabase/auth-js 2.110.5 — all ten §12 entries exact. `npm --version`
is 12.0.1, matching the inline claim in §11.2 step 9's `--silent` bullet.

### Notes (non-blocking — polish, not defects)

- **The only input I found that prints `OK` on a non-healthy response** is a redirect chain whose
  *intermediate* 301 carries the eight headers while the final 200 carries none. It is
  **unreachable under the spec's own command**: `curl -sSI` without `-L` emits exactly one
  response, and §7.1 establishes the deploy has no redirects at all (no `_redirects`, `HashRouter`
  means every request is `/`). Recording it so a future edit that adds `-L` knows the coupling.
  Not cited — it cannot occur as written.
- **Extra wide-open header alongside the correct eight** → `OK` / 0. Confirmed by execution, and
  the spec now **states this limitation explicitly** with a compensating control (eyeball the full
  `curl -sSI` once). Disclosed rather than papered over, which is exactly the right handling.
- **T-15's host file is unstated.** §11.1 is headed "`apps/desktop/build/csp.test.ts`", but T-15
  drives a bash script from `build/fixtures/headers/`. Every assertion and exit code is fully
  enumerated, so behaviour is unambiguous; only placement is implicit. An implementer will need
  `child_process` (or a sibling test file) and the script bit set. Half a sentence would close it.
- **The dedicated `preload` grep is a tripwire, not dead code.** It can only fire if the expected
  file itself carries `preload`, which `buildHeadersFile` never emits (T-09) — so it exists to
  catch the hand-pasted expected file the spec explicitly forbids. Verified it fires in that case.
- **An unreachable-but-responding deploy** (connection dies mid-headers) still reports `1`
  ("deploy is wrong") rather than `2`. Carried over from r2; loud, not open.
- **My r2 note on §11.2 step 6 was applied** — the "no other allowlist entries ⇒ say so in the PR
  body rather than reporting it as passed" branch is now written in.
- **§6 now records the "every merge to `main` republishes production" consequence** with an
  explicit expiry condition (custom domain or real users before step 10 ⇒ stop and reconsider).
  That is an architecture trade-off surfaced as human-owned, which is the correct disposition.
- **Spec is now 1286 lines.** Growth this round is T-15 plus the status-line rationale — targeted,
  not padding. Still the largest spec in the repo.

### Waivers

**None.** No violation has ever been waived on this spec.

### Prior-round violation status

| id | status |
|---|---|
| `writing-specs/unambiguous-requirements` | **RESOLVED this round** (verified by grep) |
| `writing-specs/verification-gate-correctness` | still satisfied — re-verified across 28 executed fixtures |
| `core-conduct/default-deny-data-store` | still satisfied (§7.6 unchanged) |
| `writing-secure-code/idor` | still satisfied (§7.6 owner-scoped policies + two-account S-15) |
| `core-conduct/validate-input-at-boundaries` | still satisfied (§4.1 `ORIGIN_RE` + §4.2 sink guard) |
| `writing-specs/pinned-versions` | still satisfied (§12 re-verified against package-lock) |
| `core-conduct/secrets-out-of-repo` | still satisfied (§7 placeholders; no absolute paths) |

No violation has appeared in two consecutive rounds. Nothing to escalate. **Spec is clear to
proceed to `superpowers:writing-plans`.**

---

## Round 1 — 2026-07-28 (fresh re-entry after the `b909d178` pass) — **FAIL** (1 violation)

**Identity:** repo `mtg-wizard`, branch `main`, head `6de363f4a3946852dc09cd553951dc774f0eb788`,
spec blob `71c7bd14c1a86041651bf22527ef5ed33a33e80f` (confirmed with `git hash-object` — matches
the brief), spec 1385 lines.

### Layman summary

The spec is in excellent shape and the thing everyone worried about is now genuinely fixed. I did
not read the header-verification script — I extracted it, built my own fixtures from scratch, and
**ran it 35 times**. All 17 behaviours the spec claims for it reproduced exactly, and 18 further
adversarial cases I invented to break it either failed closed or behaved correctly. **I could not
find a fail-open.** After six rounds of that gate being holed by people who ran it, v7 holds.

I also checked every factual claim the spec makes about the codebase — 20+ file/line references,
8 pinned library versions, the test baseline, and the lint baseline. **Every single one is exact.**
That is unusual and worth saying plainly.

The one thing I am failing it on is small and mechanical: the spec never says which *file* the new
`findDeployProblems` function goes in. Every other contract in §4 names its file; §4.4 alone does
not, and §11.1 then groups its test with two functions that live somewhere else. An implementer has
to guess between two defensible answers. This is a one-line fix (name the file in the §4.4 heading),
not a design problem.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/contract-missing-host-file` | `~/.claude/skills/writing-specs/SKILL.md` | "API contracts … give the agent the real interface boundaries to build against"; "the specific tools and libraries the implementation must use, so the agent is choosing within your architecture rather than picking its own" | §4.4 (`findDeployProblems`) vs §11.1 test-file table (spec:356–375, 888) | §4.4 is the only contract subsection that never names its host file, and §11.1 puts its test in `build/csp.test.ts` next to two functions that live in `build/csp.ts` — yielding two conflicting placements an implementer must choose between. |

**Why this is genuinely two-way, not pedantry.** §4.1 names `apps/desktop/build/csp.ts`; §4.2 says
"new, **same file**" precisely to disambiguate; §4.3 names `apps/desktop/vite.config.web.ts`; §4.5
names `src/renderer/index.html:10`; §4.6 says "no code". §4.4 names nothing. The two readings then
actively contradict each other:

- **`vite.config.web.ts`** — supported by §4.4's position (it follows §4.3 and its consumer snippet
  is `// inside the plugin's generateBundle`) and by §4.4's own separation-of-concerns argument:
  "this gate makes the plugin own general *deployability*, not only CSP emission — `VITE_AUTH_ENABLED`
  and `VITE_SUPABASE_ANON_KEY` have nothing to do with the CSP."
- **`build/csp.ts`** — supported by §11.1: "`apps/desktop/build/csp.test.ts` | T-01 – T-14 — the
  TypeScript units (`buildCspContent`, `buildHeadersFile`, `findDeployProblems`)", grouping it with
  two functions that are explicitly in `build/csp.ts`, and by its `CspEnv` parameter type.

Reading one forces `build/csp.test.ts` to `import … from '../vite.config.web'`, dragging a Vite
config into the unit-test graph. Reading two puts auth-flag validation inside a file named `csp`,
contradicting the spec's own argument. This is the identical defect class the spec fixed for T-15
this revision — *"T-15 was specified without one, so an implementer would have had to guess"* — left
open one section earlier.

**Not a recurrence.** The round-3 `writing-specs/unambiguous-requirements` violation (a stale
`exit 1` in §11.2 prose) is **verified fixed**: the only surviving `exit 1` string in the spec is the
compliance-history header at line 6 describing that past fix. Different territory, so this carries a
new id rather than reusing that slug.

### The gate: executed, not read — 35 cases, no fail-open

Script extracted verbatim from §11.2 step 9 to `/tmp/judge-r1/check-headers.sh`; fixtures rebuilt
independently from §4.2's stated body (CF noise headers, CRLF line endings, real curl shape).

**All 16 documented cases + arg handling reproduced exactly (17/17):**

| case | want | got | case | want | got |
|---|---|---|---|---|---|
| healthy 200 | 0 | ✅ 0 | dup-name expected (8-line) | 2 | ✅ 2 |
| 301+200-with-NO-headers | 2 | ✅ 2 | dup-name expected (9-line) | 2 | ✅ 2 |
| 301+200-WITH-headers | 2 | ✅ 2 | all eight weakened | 1 | ✅ 1 (names all 8) |
| 404 w/ 8 perfect headers | 2 | ✅ 2 | genuinely missing header | 1 | ✅ 1 |
| no status line | 2 | ✅ 2 | dup conflicting (DENY first) | 1 | ✅ 1 |
| empty served | 2 | ✅ 2 | dup conflicting (reverse sort) | 1 | ✅ 1 |
| empty expected | 2 | ✅ 2 | HSTS preload | 1 | ✅ 1 |
| missing expected | 2 | ✅ 2 | CR-laden expected | 0 | ✅ 0 |
| 7-line truncated expected | 2 | ✅ 2 | no args / one arg | 2 | ✅ 2 |

**18 adversarial probes I invented** (hunting exit 0 where the check cannot be trusted):

| probe | exit | assessment |
|---|---|---|
| P1 expected is raw `_headers` body (indented + `/*`) | 2 | fail-closed ✅ |
| P2 expected is usage text, generator exited 0 | 2 | fail-closed ✅ |
| P3 `HTTP/1.1 200 OK` | 0 | correct ✅ |
| P4 `103` Early Hints + `200` (no `-L`) | 2 | fail-closed; message misattributes to `-L` → **note** |
| P5 extra wide-open header alongside the correct 8 | 0 | **documented** known limitation w/ compensating control ✅ |
| P6 served header indented | 1 | fail-closed ✅ |
| P7 expected w/o trailing newline | 0 | correct (`sort` re-adds) ✅ |
| P8 served blank value | 1 | correct ✅ |
| P9 args swapped | 2 | fail-closed ✅ |
| P10 curl file as both args | 2 | fail-closed ✅ |
| P11 expected = 8 junk names | 1 | correct ✅ |
| P12 status line last | 0 | not curl-producible; benign |
| P13 `200` then `500` status lines | 2 | fail-closed ✅ |
| P14 CSP missing `upgrade-insecure-requests` | 1 | correct ✅ |
| P15 CSP missing `frame-ancestors` | 1 | correct ✅ |
| P16 expected is a directory | 2 | fail-closed ✅ |
| P17 status w/ trailing junk | 0 | correct (it is a 200) ✅ |
| P18 single `301` status | 2 | fail-closed ✅ |

**Verdict on the gate: no fail-open exists.** The v6 pooling hole is closed by the exactly-one-status-line
guard, and it also closes P4/P13 that I built to slip past it.

### Repo claims — every one verified exact

| claim | result |
|---|---|
| `csp.ts:15` — `.trim()` before match, 03a regex `^(https?:\/\/[^/?#]+)` | ✅ exact |
| `src/renderer/index.html:10` — baseline meta content | ✅ exact |
| `App.tsx:20` — `<HashRouter>` | ✅ exact |
| `supabaseClient.ts:5` — `=== 'true'`; `:22` — `detectSessionInUrl: true` | ✅ both exact |
| `SignInScreen.tsx:80` `handleOAuth`; buttons `:162`/`:170`; `SignInScreen.test.tsx:144` | ✅ all exact |
| `avatar.ts:9-22` `uploadAvatar`; `:13-15` unvalidated extension; `:20` `getPublicUrl` | ✅ all exact |
| `main.py:31-36` CORSMiddleware, **no `allow_credentials`** | ✅ exact |
| `config.py:15` (`null` in default), `:20` (`auth_enabled: bool = False`), `:23-25` (`avatar_url_prefix`) | ✅ all exact |
| `middleware.py:1-5` — the 3 mirrored header values | ✅ exact |
| `vite.config.web.ts:48` — `outDir: resolve('out/web')` | ✅ exact |
| `.gitignore:9` = `.env*.local`; `.env.bak.local` ignored / `.env.local.bak` NOT | ✅ verified via `git check-ignore -v` |
| `ci.yml:20` `NODE_VERSION: "22"`, `:128` consumes it | ✅ exact |
| 8 pinned versions vs `package-lock.json` (vite 7.3.6, rollup 4.62.2, vitest 4.1.10, ts 5.9.3, electron 39.8.10, electron-vite 5.0.0, supabase-js/auth-js 2.110.5) | ✅ all 8 exact |
| npm 12.0.1; local Node 26 | ✅ both exact |
| baseline **300 tests / 38 files** | ✅ ran it: `300 passed (300)` / `38 passed (38)` |
| baseline lint **0 errors / 7 warnings** | ✅ ran it: `0 errors, 7 warnings in 3 files` |
| `build/**/*` in `tsconfig.node.json`; `build/*.test.ts` already collected | ✅ both (`build/csp.test.ts` is one of the 38) |
| no `cspHeadersPlugin` naming drift | ✅ appears only where explicitly disallowed (spec:398–399) |
| follow-up renumber (fu 11 = `build:web` CI, fu 12 = `AUTH_ENABLED`) | ✅ no stale citation anywhere |
| "FOUR places" corrected in both sites | ✅ spec:1061 + spec:1358; "three places" survives only as the historical note at 1366 |
| spec at canonical `docs/superpowers/specs/` | ✅ |
| no absolute paths; no real credentials | ✅ anon key is a placeholder; project ref `iwqvvnrkafajdzdhbltk` is a public identifier already in 6 committed files |

### Brief verification

The orchestrator's brief is **accurate on every point I could check** — blob sha, the five applied
fixes (v7 script, two test files, T-15 detail, FOUR-places correction, fu 11/12 renumber), and the
prior-violation list. No correction required. One clarification: the brief cites the spec as 1384
lines; it is **1385**. Immaterial.

### Notes (non-blocking)

- **Early Hints false FATAL.** A Cloudflare `103` informational response produces two `HTTP/` lines
  with no `-L` involved, so the gate exits 2 with a message blaming `curl -L`. Direction is safe
  (fail-closed) and Early Hints is opt-in/off by default on Pages, so this is not a defect — but one
  clause in the fatal message ("or a `103` Early Hints response") would save a confusing debug.
- **The HSTS `preload` check is effectively redundant.** Because `buildHeadersFile` never emits
  `preload`, a served `preload` already trips `HEADER VALUE MISMATCH` before the dedicated grep runs.
  Harmless defence-in-depth; worth keeping.
- **S-02's dev-server assertion has no manual step.** T-02/T-03 cover the policy content as units,
  but "the app's `http://localhost:8000` API calls succeed" is not in §11.2's gate. Continuous dev
  usage covers it in practice.
- **`headers:expected` flag parsing is untested.** Its failure mode is fail-closed (wrong origins ⇒
  `HEADER VALUE MISMATCH`/1), so this is not a hole — just an untested seam in a gate that is
  otherwise fully covered by T-15.
- **Spec is 1385 lines / 82 KB**, the largest in the repo. Justified by the six-round history on the
  header gate, but the tokenization guidance in `writing-specs` is worth remembering if it grows again.

### Waivers

**None.** No violation has ever been waived on this spec.

### Prior-round violation status — all seven remain fixed

| id | status |
|---|---|
| `writing-specs/verification-gate-correctness` | **still satisfied** — re-verified across 35 executed fixtures, incl. 18 new adversarial ones |
| `writing-specs/unambiguous-requirements` | **still satisfied** — stale `exit 1` verified gone |
| `core-conduct/default-deny-data-store` | still satisfied (§7.6 four owner-scoped policies) |
| `writing-secure-code/idor` | still satisfied (§7.6 + two-account S-15 at step 11) |
| `core-conduct/validate-input-at-boundaries` | still satisfied (§4.1 `ORIGIN_RE` + §4.2 sink guard) |
| `writing-specs/pinned-versions` | still satisfied (all 8 re-verified against `package-lock.json`) |
| `core-conduct/secrets-out-of-repo` | still satisfied (placeholders; `~/.mtg-wizard/cloud.env`; no absolute paths) |

**No violation has recurred. Nothing to escalate.** The single new finding is a one-line editorial
fix; once §4.4 names its host file the spec is clear for `superpowers:writing-plans`.

---

## Round 2 — 2026-07-28T04:08:44Z — **FAIL** (1 violation)

- **Spec blob:** `ec6b0cc44c9c964a009dea98dc1c13c5b47fd10f` (observed via `git hash-object`; matches the brief)
- **Repo/branch/HEAD:** `mtg-wizard` / `main` / `ace90013fb87ac17a6c5ae53cec4ee1df21234d0`
- **Waived:** none (nothing has ever been waived on this spec)
- **Confidence:** high — the gate, the regex, the suite, the lint baseline and every line citation were *executed*, not read.

### Layman summary

The round-1 problem is genuinely fixed: §4.4 now names both host files in its heading and adds a
paragraph explaining the pure-logic/wiring split, so `findDeployProblems` has exactly one home.

I then did the thing this spec keeps asking for: I extracted `check-headers.sh` v7, built my own
fixtures from scratch, and ran **42 cases** — the 17 the spec declares plus 25 adversarial probes it
never mentions. **It held on every one.** No fail-open. The three-valued contract (0/1/2) is honoured
everywhere, including a 304, a proxy `CONNECT` preamble, a trailing 500, an HTML error body, swapped
arguments, an expected-file whose names are all junk, and an expected-file with 8 distinct names but
9 lines. This is the first round where the gate has been independently confirmed sound; the six-holes
streak looks genuinely broken. I also executed the tightened `ORIGIN_RE` across 29 accept/reject
cases and ran the real test suite, lint and typecheck.

The one remaining defect is small and mechanical, but it is the *same* defect class this spec has
been failed for before: when round 2 added the 103 Early Hints case, it updated the fixture count
from "sixteen" to "seventeen" in two places and missed two others. The spec now states T-15's fixture
count three different ways — 17, 16, and (by arithmetic) 15. One editorial pass fixes it.

### Violations

| id | rule_source | where | why |
|---|---|---|---|
| `writing-specs/unambiguous-requirements` | `~/.claude/skills/writing-specs/SKILL.md` | §11.1 T-15 detail (line 978) and §11.2 step 9 "Current behaviour, v7" (line 1237), against the authoritative 17-case enumeration at line 967 | The round-2 edit updated "sixteen"→"seventeen" at lines 925 and 967 but left line 978's "~316 … a 16-case matrix" and line 1237's "seventeen fixtures … the twelve carried forward, two redirect-chain cases, and a `103` Early Hints case" (12+2+1 = 15) stale, so T-15's fixture count is stated as 17, 16 and 15 within the same document. |

**Recurrence:** this id was last cited at blob `93f5d367` (stale `exit 1` in prose contradicting the
script) and fixed. Same rule, same territory (verification-gate prose), same failure mode — prose
numerics going stale after an edit to the fixture set. **Second citation of this rule across cycles.**

Proof of staleness, from the round-1 blob `71c7bd14`:

```
914: … assert the exit code for each of the sixteen cases below …
948: The sixteen cases, all exit codes: …
958: ~316** to the suite baseline; `spawnSync` on a 16-case matrix …   <- unchanged in r2
1213: verified across sixteen fixtures — the twelve carried forward … <- "twelve" unchanged in r2
```

Correct values: the enumeration lists **17** cases; minus the three multi-response cases
(301+200-no-headers, 301+200-with-headers, 103 Early Hints) leaves **fourteen** carried forward, not
twelve; and 300 + 17 = **~317**, on a **17-case** matrix.

### Round-1 violation — resolved

| prior id | status |
|---|---|
| `writing-specs/contract-missing-host-file` | **FIXED.** §4.4's heading names `findDeployProblems` in `apps/desktop/build/csp.ts`, wired in `vite.config.web.ts`; the "Where each half lives" paragraph states the split, justifies it by the §4.1–§4.3 rule, and ties it to T-14's placement. Not recurring. |

### Older prior violations — all still satisfied

| id | status |
|---|---|
| `core-conduct/default-deny-data-store` | satisfied — §7.6 four owner-scoped policies, MIME allowlist, 2 MB cap |
| `writing-secure-code/idor` | satisfied — `(storage.foldername(name))[1] = auth.uid()::text`, S-15 two-account test, USING-as-WITH-CHECK verified |
| `core-conduct/validate-input-at-boundaries` | satisfied — **re-verified by execution**, see below |
| `writing-specs/pinned-versions` | satisfied — all 8 re-verified against `package-lock.json`; Node `22.16.0`; Pages `v3` |
| `core-conduct/secrets-out-of-repo` | satisfied — `mv` not `rm`; `.gitignore` behaviour re-verified with `git check-ignore` |
| `writing-specs/verification-gate-correctness` | **satisfied — independently confirmed this round, see the 42-case run** |

### What I executed

**1. `check-headers.sh` v7 — 42 cases, my own fixtures. All correct.**

All 17 declared cases matched their declared exit codes. My 25 additional probes:

| probe | exit | verdict |
|---|---|---|
| 304 carrying 8 perfect headers | 2 | correct |
| proxy `200 Connection established` + 200 | 2 | correct |
| 200 then trailing 500 | 2 | correct |
| HTML body instead of headers | 2 | correct |
| served file is a directory / only blank lines | 2 | correct |
| args swapped; one arg; no args | 2 | correct |
| expected-file all-junk but non-empty | 2 | correct |
| expected-file 9 lines / 8 distinct names | 2 | correct |
| Title-Case header names over HTTP/1.1 | 0 | correct (names lowercased) |
| HTTP/3 200; shuffled order; LF-only; obs-fold; extra `ACAO: *` | 0 | correct |
| value case flipped (`deny` vs `DENY`) | 1 | correct |
| CSP weakened by one directive; report-only swap; trailing space on a value | 1 | correct |
| header value with no space after colon | 1 | fail-safe |

**No path that should exit 2 exits 0.** The documented limitation (extra headers unpoliced) is real
and correctly disclosed.

**2. `ORIGIN_RE` — 29 cases.** Accepts all four real origins plus port/path/query/fragment forms;
rejects CR/LF injection, bare LF, interior space, tab, `;`, `'`, `"`, userinfo, wildcard host,
`javascript:`, `data:`, `ftp://`, protocol-relative, 6-digit port, uppercase scheme. The one case
that surprised me — a *trailing* CR — is stripped by the retained `.trim()` and yields a clean
origin, which is exactly what §4.1 already documents (it even records that an earlier draft got this
wrong). Spec is more precise than my prior.

**3. Repo claims — every one accurate.** `main.py:31-36`, `config.py:15/:20/:23-25`, `csp.ts:15`,
`.gitignore:9`, `ci.yml:20`/`:128`, `vite.config.web.ts:48`, `src/renderer/index.html:10`,
`middleware.py:1-5`, `supabaseClient.ts:5/:22`, `App.tsx:20` (`<HashRouter>`),
`SignInScreen.tsx:80/:162/:170`, `SignInScreen.test.tsx:144`, `avatar.ts:9-22/:13-15/:20`,
`schemas.py:24`. No root `package.json`; `build:web` absent from CI; `build/**/*` in
`tsconfig.node.json`; `build/*.test.ts` collected by `vitest.config.ts`.

**4. §11.2 step 2 baselines — exact.** `npm run test -- --run` → **38 files / 300 tests passed**.
`npm run typecheck` → 0 errors. `eslint` → **0 errors, 7 warnings in 3 files**. All eight
`package-lock.json` versions match §12 exactly.

**5. `git check-ignore`** confirms `.env.bak.local` ignored, `.env.local.bak` **not** — precisely as
§11.2 step 1 warns.

### Notes (non-blocking)

1. **Brief-vs-primary-source conflicts, stated as required.** The brief claims the 103 case makes it
   "T-15's seventeenth fixture. Re-verified: **19/19** including proxy-CONNECT and 200-then-500."
   The **spec pins 17**, not 19: proxy-`CONNECT` and trailing-500 appear only in §11.2's narrative
   (line 1243-1245) as claimed behaviours, never in T-15's enumerated fixture list. **Primary source
   wins — 17.** I verified both behave correctly (exit 2), so this is a pinning gap, not a
   correctness gap; folding them in would make T-15 19 cases and would match the brief.
2. **Brief path shorthand.** The brief asks to check `csp.ts:15`, `App.tsx:20` etc. The spec's
   short-form renderer paths (`auth/SignInScreen.tsx:80`, `features/profile/avatar.ts:9-22`,
   `App.tsx:20`) resolve under `apps/desktop/src/renderer/**src**/`, not
   `apps/desktop/src/renderer/`. All correct once that prefix is applied; consider writing them
   repo-relative once.
3. **§4.3's plugin wiring has no automated test** — `generateBundle`/`emitFile` and
   `cspHtmlPlugin`'s `configResolved` are covered only by §11.2 steps 3/5. The spec states this
   boundary explicitly ("T-14 … does **not** invoke `this.error()`"), so it is a disclosed choice,
   not a silence. Not cited.
4. **Scenario numbering.** S-15 and S-16 sit in the "Bad paths" block after S-08, so the block reads
   S-06, S-07, S-08, S-15, S-16 while S-09–S-14 are edge cases. Numerically jarring but
   unambiguous; renumbering would churn cross-references.
5. **`cspHeadersPlugin` appears only in the sentence forbidding it** (lines 409-410). The
   self-reference is fine.
6. **Follow-up renumber is clean.** §13 cross-references point at fu 6, 7, 8, 9, 10 only; nothing
   still cites the old fu 11. The "FOUR places" `WANT` coupling is consistent at both sites.
7. **Pattern worth naming.** `writing-specs/unambiguous-requirements` has now been cited twice in
   this spec's history, both times for a numeric/prose fact going stale after a targeted edit. A
   mechanical "grep every count you changed" pass at the end of each revision would close the class.
8. **Strength.** The gate is now genuinely hardened. Six revisions were holed by people who ran it;
   v7 survived 42 independently-built cases including cases it never anticipated. T-15's decision to
   *derive* the healthy fixture from `buildHeadersFile` rather than commit it is the right fix and
   is what makes the `WANT=8` coupling fail loudly instead of silently.

---

## Round 3 — 2026-07-28 — VERDICT: **PASS** (0 violations)

**Spec:** `docs/superpowers/specs/2026-07-25-03b-deploy-design.md`
**blob** `314dd8a539e6c4c7845b31c0030b62d24c091737` (observed; matches the brief)
**repo** mtg-wizard · **branch** main · **head** `95ea8402669122b4c54c0c912fffc19d4df0ae8f`
**Waived:** none, ever.
**Round 3 was the escalation tripwire.** It closes clean, so nothing escalates to the user.

### In plain language

This was the last round before the decision went to a human, so I re-derived everything
rather than trusting the hand-off. Three things needed to be true, and all three are.

**The count really is seventeen.** The orchestrator fixed this by hand last round and
explicitly asked me not to take its word for it. I parsed the enumeration
programmatically: **17 `⇒` clauses, one per fixture, no packing.** All four coupled sites
agree — T-15's row ("seventeen cases"), the enumeration ("The seventeen cases"), the
suite-cost line ("**17**-case matrix", "~317"), and §11.2's behaviour paragraph
("seventeen fixtures"). The arithmetic closes twice over: 14 carried forward + 2
redirect-chain + 1 Early-Hints = 17, and 300 + 17 = 317 against a baseline I measured
myself. The two surviving mentions of "sixteen" (line 998) and "three places" (line 1440)
are both *historical narrative describing superseded revisions* — correct as written, not
stale claims.

**The gate holds.** I extracted the script, built 17 fixtures of my own from §4.2's stated
output (never reusing the orchestrator's), and ran it: **17/17 exit codes match the
documented contract exactly.** I then threw 21 adversarial probes at it hunting for the
fail-open the brief warned is the highest-severity finding here. Every realistic input
behaves correctly. One crafted input does not — see note 1 — but it cannot be produced by
the documented procedure, so it is a hardening note, not a violation.

**The spec still describes the real repo.** Every `file:line` claim resolves and says what
the spec says it says, the eight version pins match `package-lock.json` byte for byte, the
test baseline is exactly 300/38 as claimed, and CI genuinely never runs `build:web`.

### Violations

**None.** All seven historical violation ids remain fixed; neither of this cycle's two
recurs.

| prior id | status this round |
|---|---|
| `writing-specs/unambiguous-requirements` (r2) | **fixed — independently re-counted, 17 everywhere** |
| `writing-specs/contract-missing-host-file` (r1) | fixed — §4.4 names both `apps/desktop/build/csp.ts` and `apps/desktop/vite.config.web.ts` |
| `writing-specs/verification-gate-correctness` | fixed — 17/17 documented cases reproduced by execution |
| `core-conduct/default-deny-data-store` | fixed — §7.6 owner-scoped policies, MIME allowlist, 2 MB cap |
| `writing-secure-code/idor` | fixed — S-15 + §11.2 step 11's two-account proof |
| `core-conduct/validate-input-at-boundaries` | fixed — `ORIGIN_RE` + §4.2 sink guard, T-11/T-12 |
| `writing-specs/pinned-versions` | fixed — all 8 pins verified against `package-lock.json`; Node `22.16.0` |
| `core-conduct/secrets-out-of-repo` | fixed — `mv` not `rm`; `.env.bak.local` confirmed ignored |

### Evidence

**1. Gate execution — 17 documented cases, all correct.** Fixtures built independently
from §4.2's declared `_headers` body, served side in real `curl -sSI` CRLF shape.

| case | exit | want | case | exit | want |
|---|---|---|---|---|---|
| healthy 200 | 0 | 0 ✓ | duplicate-named expected | 2 | 2 ✓ |
| 301(8 hdrs)+200(none) | 2 | 2 ✓ | all eight weakened | 1 | 1 ✓ |
| 301(none)+200(8 hdrs) | 2 | 2 ✓ | genuinely missing header | 1 | 1 ✓ |
| 103 Early Hints + 200 | 2 | 2 ✓ | dup conflicting (DENY first) | 1 | 1 ✓ |
| 404 w/ 8 perfect hdrs | 2 | 2 ✓ | dup conflicting (reverse sort) | 1 | 1 ✓ |
| no status line | 2 | 2 ✓ | HSTS preload | 1 | 1 ✓ |
| empty served | 2 | 2 ✓ | CR-laden expected | 0 | 0 ✓ |
| empty expected | 2 | 2 ✓ | missing expected | 2 | 2 ✓ |
| 7-line truncated expected | 2 | 2 ✓ | | | |

**2. Adversarial probes (21, mine).** Correct on all but one crafted case: header served
with no space after colon ⇒ 1; expected 8 names/9 lines ⇒ 2; HTTP/1.1 capitalised names
⇒ 0; 200 carrying zero headers ⇒ 1; duplicate differing only by name case ⇒ 1; lowercase
`http/2 200` status ⇒ 2; LF-only served file ⇒ 0; no-args ⇒ 2. Status sweep with 8
*perfect* headers attached: `HTTP/2 500`, `HTTP/2 404`, `HTTP/1.1 500 Internal Server
Error`, `HTTP/1.1 502 Bad Gateway`, `HTTP/1.1 304 Not Modified` — **all correctly 2**.
Both disclosed paste behaviours reproduced exactly as §11.2 claims: whole-response paste
⇒ 2 (11 distinct names > `WANT`), single-value paste ⇒ 0.

**3. Live confirmation of the 103 case.** `curl -sSI https://www.cloudflare.com` returned
`HTTP/2 103` as its first line. The Early-Hints fixture is not theoretical — it is what
Cloudflare actually emits, and the guard catches it.

**4. Repo claims — all accurate.** `main.py:31-36` (CORSMiddleware, no `allow_credentials`),
`config.py:15/:20/:23-25`, `csp.ts:15` (the `.trim()`), `csp.test.ts:5-11` (exact 03a
string — will go red as §11.1 warns) and `:13-20` (`toContain`, survives),
`.gitignore:9`, `ci.yml:20`/`:128`, `vite.config.web.ts:48`, `src/renderer/index.html:10`,
`middleware.py:1-5`, `supabaseClient.ts:5/:22`, `App.tsx:20` (`<HashRouter>`),
`SignInScreen.tsx:80/:162/:170`, `SignInScreen.test.tsx:144`, `avatar.ts:9-22/:13-15/:20`.

**5. Baselines re-measured.** Suite run: **300 passed / 0 failed**, **38 test files** on
disk — §11.2 step 2's numbers exactly. All eight `package-lock.json` versions match §12.
`build/**/*` in `tsconfig.node.json`; `vitest.config.ts` sets no `include`, so both
`build/csp.test.ts` and the new `build/check-headers.test.ts` are collected with no config
change, as §11.1 claims. No `envDir` in `vitest.config.ts` — follow-up 6's premise holds.

**6. Internal consistency.** S-01…S-16 all present, no gaps or duplicates. Follow-ups
1–12 present, no duplicates; prose cites only fu 6, 7, 8, 9, 10 — nothing still points at
the pre-renumber fu 11. `WANT=8` "FOUR places" consistent at both sites. §4.5's Electron
string is byte-identical to `buildCspContent({}, {isDev:true})` under §4.1's canonical
directive order, and §4.2's CSP line is §4.1's production string + `; frame-ancestors
'none'` — so T-07, T-08 and S-04 are mutually consistent. No TBD/TODO/FIXME anywhere.

### Notes (non-blocking — would-prefer, not must-fix)

1. **One crafted status line fails open — worth a one-line hardening, but unreachable in
   the documented procedure.** `case "$status" in HTTP/*\ 200*)` matches any status line
   *containing* " 200" anywhere, so a hand-built `HTTP/1.1 500 Backend said 200` carrying
   eight perfect headers printed `OK`/0 where the guard's stated invariant ("not 200 →
   fatal") wants 2. **Why this is a note and not a violation:** Cloudflare Pages serves
   HTTP/2, and HTTP/2 has no reason phrase at all — the status line is literally
   `HTTP/2 <code>`, so " 200" appears only when the code *is* 200 (confirmed live above).
   Every standard HTTP/1.1 reason phrase I tested — 500, 502, 404, 304 — correctly exits
   2. Reaching this needs a server emitting a non-standard reason phrase containing " 200",
   which our own deployment cannot do. Cheap fix if the author wants belt-and-braces:
   extract the code rather than glob the line —
   `code=$(printf '%s' "$status" | awk '{print $2}')` then `[ "$code" = 200 ] || fatal …`.
   Recommend recording it under §11.2's existing "Known limitation" block if not fixed.
2. **Brief-vs-primary-source conflicts, stated as required.** (a) The brief says the spec
   is 1458 lines; it is **1459**. (b) The brief again describes the gate as "verified
   19/19"; the **spec pins 17**, and 17 is what T-15 enumerates — primary source wins, as
   in round 2. Proxy-`CONNECT` and trailing-500 remain narrative-only claims (both verified
   correct by me), so folding them into T-15 would make it 19 and reconcile the two. (c)
   The brief says the spec is committed to `main` at `3a2b0c8` — accurate as the commit
   that last *touched* the spec, but HEAD is `95ea840`. Recorded as observed.
3. **Renderer path shorthand persists** (carried from round 2, still not cited).
   `App.tsx:20`, `auth/supabaseClient.ts:5`, `features/profile/avatar.ts:9-22` resolve
   under `apps/desktop/src/renderer/**src**/`. Every one is correct once that prefix is
   applied, and the files the spec actually *changes* are all fully pathed — so this is
   cosmetic.
4. **§4.3's plugin wiring still has no unit test** — disclosed and reasoned in the spec
   ("T-14 … does **not** invoke `this.error()`"), covered by §11.2 steps 3/5. Deliberate
   boundary, not a silence. Not cited, unchanged from round 2.
5. **Portability of the gate script is fine.** Every construct used — `grep -c`, BRE
   `sed`, POSIX `awk` (`tolower`/`sub`), `sort -u`, `cut`, `mktemp`, `tr`, `trap EXIT`,
   `set -uo pipefail` under a `bash` shebang — is portable BSD↔GNU. Verified by execution
   on BSD userland.
6. **Strength worth recording.** Across three rounds this gate has now survived 17
   documented + 21 adversarial cases from me alone, on top of the 35 and 23 from prior
   judges. The structural fix — deriving T-15's healthy fixture from `buildHeadersFile`
   instead of committing it — is what converts the `WANT=8` coupling from a silent drift
   into a loud local test failure, and it is the reason this round found nothing new in
   the places the previous six revisions broke.

---

## 2026-07-28 — cycle 3, round 1 — **FAIL** (2 violations)

**Spec blob:** `85be9612554a5bf888e55a072a0fcd59ef3b7eed` (matched the brief exactly — no
moving target). **HEAD:** `e652fdf` on `main`, repo `mtg-wizard`. Waived: **none, ever.**

### Layman summary

The commit under review (`e652fdf`, docs-only) did the right thing: it gave
`npm run headers:expected` a real home, a real runner, and a test (T-16). Both previously
cited defects stay fixed — `§4.4` still names both host files, and the fixture count is
consistently **seventeen** in all four places (I counted the `⇒` clauses: exactly 17).

But giving the wrapper a runner introduced two new claims, and **both are false when you
run them** — which is the same failure pattern this spec keeps catching in itself: the
runtime half was verified by execution, the toolchain half was verified by reading.

1. **"Neither does CI [run this script]" is no longer true** — the same commit added T-16,
   which spawns `node build/headers-expected.ts` from inside the default vitest suite, and
   CI's `desktop` job runs that suite. So CI *does* run it, on a Node the spec never pins.
   Worse, §13 follow-up 8 tells a future engineer to align CI's Node to the Pages pin
   `22.16.0` — which §4.2 itself says cannot run the wrapper without a flag. Following the
   spec's own follow-up would turn T-16 red.
2. **"Typechecked by the existing `npm run typecheck:node` with no config change" is false.**
   Node's type-stripping requires the import to be written `./csp.ts`; the repo's inherited
   tsconfig rejects exactly that with **TS5097**. The two forms that typecheck fail at
   runtime. There is no specifier that satisfies both — the implementation needs
   `allowImportingTsExtensions: true`, which the spec says is not needed. An implementer
   following §4.2 literally gets a red `npm run typecheck` on their first run, which is
   also §11.2 step 2's own gate.

Everything else I could execute, I executed, and it held: all 17 gate fixtures, 8 fresh
adversarial probes, the CSP regex, the runner's stdout/stderr split, and the whole step-9
pipeline end to end.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` | Pin the exact version of every library and tool the implementation must use | §4.2 (`headers:expected` runner) + §11.1 T-16 + §12 + §13 follow-up 8 | §4.2 asserts "Pages never runs this script and neither does CI", but T-16 spawns `node build/headers-expected.ts` inside the default vitest suite that CI's `desktop` job runs (`ci.yml:143`), and no minimum Node for unflagged type-stripping is pinned anywhere — while §13 follow-up 8 directs aligning CI to the Pages pin `22.16.0`, which §4.2 itself says needs `--experimental-strip-types`. |
| `writing-specs/required-toolchain` | `~/.claude/skills/writing-specs/SKILL.md` | State the specific tools **and configuration** the implementation must use, so the agent builds inside your architecture rather than improvising | §4.2, closing paragraph | Executed against the repo's own `tsc 5.9.3` and inherited `tsconfig.node.json`: the `./csp.ts` specifier the runner requires fails with **TS5097**, while `./csp` and `./csp.js` typecheck but fail at runtime with `ERR_MODULE_NOT_FOUND` — so "no config change" is false and the required `allowImportingTsExtensions: true` is unspecified. |

### Evidence — executed, not read

**Finding 1 (CI runs the wrapper).** `.github/workflows/ci.yml:20` = `NODE_VERSION: "22"`,
consumed at `:128`; the `desktop` job's last step is `npm run test -- --run`.
`apps/desktop/vitest.config.ts` sets no `include`, so vitest's default glob picks up
`build/headers-expected.test.ts` (it already picks up `build/csp.test.ts`). §11.1 line 1092
confirms the intent: T-16 "spawns once, so neither needs quarantining from the default run."

**Finding 2 (the import-specifier trap).** tsconfig chain read in full:
`apps/desktop/tsconfig.node.json` → `@electron-toolkit/tsconfig/tsconfig.node.json` →
`./tsconfig.json` (`moduleResolution: "bundler"`, **no** `allowImportingTsExtensions`).
Reconstructed §4.1/§4.2's `csp.ts` + wrapper in `/tmp`, ran the repo's own `tsc` against a
config extending that same installed base:

| import specifier | `node build/headers-expected.ts` | `tsc --noEmit -p tsconfig.node.json` |
|---|---|---|
| `./csp.ts` | **exit 0**, correct policy | **TS5097** — "can only end with '.ts' when `allowImportingTsExtensions` is enabled" |
| `./csp` | `ERR_MODULE_NOT_FOUND` | exit 0 |
| `./csp.js` | `ERR_MODULE_NOT_FOUND` | exit 0 |

The spec's own 2026-07-28 probe used `./csp.ts` — the runnable-but-untypecheckable form.
`build/**/*` **is** in `tsconfig.node.json` (verified), which is precisely why the new file
lands in the failing typecheck rather than escaping it.

**The gate script itself — all 17 documented fixtures, exit codes exactly as specified:**
healthy ⇒ 0; 301+200-no-headers ⇒ 2; 301+200-with-headers ⇒ 2; 103+200 ⇒ 2; 404-with-8 ⇒ 2;
no status line ⇒ 2; empty served ⇒ 2; empty expected ⇒ 2; missing expected ⇒ 2; 7-line
truncated ⇒ 2; expected duplicate at **conflicting** values ⇒ 2 (confirmed caught by the
`checked` counter — "compared 9 headers, want 8" — *not* by the distinct-name guard, exactly
as §11.1 claims); four weakened ⇒ 1 naming all four; missing header ⇒ 1; served duplicate ⇒ 1
in **both** sort orders; HSTS `preload` ⇒ 1; CR-laden expected ⇒ 0. Identical expected-file
duplicate ⇒ 0, as claimed.

**8 fresh adversarial probes, none supplied by the spec — all fail closed:** obs-fold
continuation line ⇒ 1; header with empty value ⇒ 1; lowercase `http/2 200` status ⇒ 2;
200 carrying zero of the eight ⇒ 1; whole served response pasted into expected ⇒ 2 (11
distinct names); 200-then-500 ⇒ 2; whitespace-only served ⇒ 2; **one value pasted into
expected ⇒ 0/OK — reproducing the hole §11.2 openly admits**, which confirms the written
prohibition really is the only control there.

**§4.1 `ORIGIN_RE`:** all 9 claimed origins accepted and reduced correctly; all 13 hostile
values rejected (CR/LF, bare LF, tab, space, `;`, `'`, userinfo, wildcard, `javascript:`,
`ftp://`, `//a.co`, comma-joined). The recorded capture-group defect reproduces: the
non-capturing variant returns `match[1] === undefined`.

**§4.2 runner mechanics:** `node build/headers-expected.ts` exits 0 with a typeless
`package.json`; `MODULE_TYPELESS_PACKAGE_JSON` goes to **stderr**, leaving stdout as exactly
8 clean lowercase `name: value` lines with no indent and no `/*` — the T-16 contract.
`npm run --silent headers:expected -- --api … --supabase …` forwards args correctly, and
feeding its stdout into `check-headers.sh` against a served file derived from
`buildHeadersFile` prints `OK`/0 end to end.

**§12:** every pinned version matches `package-lock.json` (vite 7.3.6, rollup 4.62.2,
vitest 4.1.10, typescript 5.9.3, electron 39.8.10, electron-vite 5.0.0, supabase-js /
auth-js 2.110.5). `tsx`, `ts-node`, `vite-node` genuinely absent; `esbuild` 0.25.12 present
**transitively only** — all three rejected-runner claims hold.

**Counts/structure:** 17 `⇒` clauses = seventeen fixtures; "three test files" matches the
three-row table; T-01–T-16 consistent; the decayed `~317` total is gone, replaced by a
property; 38 test files on disk matches §11.2 step 2's baseline; 16 Gherkin scenarios across
good/bad/edge; 2 Mermaid diagrams; no TBD/TODO/FIXME; no secrets; no absolute paths; spec is
at the canonical `docs/superpowers/specs/` path.

### Notes (non-blocking)

1. **Prior round's status-line note reproduces and was not applied.** `HTTP/1.1 500 Backend
   said 200` carrying eight perfect headers still exits **0**. Unreachable on Cloudflare
   (HTTP/2 has no reason phrase — `HTTP/2 500` correctly exits 2, verified), so still a
   note, not a violation. The earlier recommendation to record it under §11.2's "Known
   limitation" block has not been taken up.
2. **§11.1's "all eight weakened ⇒ 1, naming all four"** reads as self-contradictory in
   isolation; only §11.1's earlier "weaken four values" resolves it. Both variants exit 1
   under execution (verified), so it is cosmetic — suggest "all eight present, four
   weakened".
3. **Renderer path shorthand persists** (third round running, still not cited):
   `App.tsx:20`, `auth/supabaseClient.ts:5`, `avatar.ts:13-15` resolve under
   `apps/desktop/src/renderer/`**`src`**`/`. Every line number verified correct.
4. **Repo citations spot-checked and accurate:** `csp.ts:15` (`.trim()`),
   `supabaseClient.ts:5` (`=== 'true'`), `config.py:15/20/23-25`, `App.tsx:20`
   (`HashRouter`), `.gitignore:9` (`.env*.local`), `vite.config.web.ts:48` (`out/web`),
   `csp.test.ts:5-11` (the exact-string 03a assertion that must be rewritten),
   `index.html:10` (the baseline meta).
5. **No error found in the dispatch brief this round** — blob sha, HEAD, round number,
   waiver status and the four-edit description of `e652fdf` all matched primary sources.
   `e652fdf` is docs-only (1 file, +145/−38), so no implementation exists yet and both
   findings are still cheap paragraph-level fixes.
6. **`.claude/project-standards.md` does not exist in this repo**; the repo layer judged was
   `CLAUDE.md` only.
7. **Read-only contract honoured.** No repo file was created, edited, or checked out; all
   fixtures and probes live in `/tmp/hj-03b/`. One unrelated modified file was present in
   the working tree on arrival (`coding-memory/observability-judge/2026-07-28-main.md`) and
   was left untouched.

---

## 2026-07-28 — cycle 3, round 2 — **FAIL** (1 violation)

- **Spec blob:** `d9b6cadfebfee6696f20ef82d5da25cf4cef9c84` (matched the brief exactly)
- **Repo/branch:** mtg-wizard / `main` · **HEAD at write time:** `a9592dc9019ac1eae0b9ab4fe5010b9cb126a6c1`
  (the brief said `1b66b52`; `a9592dc` landed mid-evaluation and is **memory-only** —
  `CODING_MEMORY.md` + `coding-memory/*`. `git diff 1b66b52 a9592dc` does not touch the spec,
  so the artifact judged is exactly the target blob.)
- **Waived:** none, in any cycle.
- **Rule sources read:** `rules/core-conduct.md`, `skills/writing-specs/SKILL.md`,
  `skills/writing-secure-code/SKILL.md`, repo `CLAUDE.md`. No `.claude/project-standards.md`
  in this repo.

### Layman summary

Both round-1 findings are genuinely fixed, and I confirmed each by running it rather than
reading it. The Node floor is real: on Node 22.13.1 the wrapper refuses to start, on 23.7.0
and 26.5.0 it runs unflagged — so the spec's warning that pinning CI down to 22.16.0 would
break the new test is correct, not theoretical. The tsconfig flag also works: with
`allowImportingTsExtensions` added, `npm run typecheck` **and** the full `npm run build`
both come back green, and the TS5096 caveat the spec records is a real thing that really
happens if you emit instead of `--noEmit`. I also rebuilt the header-checking script from
the spec's own text and ran all seventeen of its fixtures plus fourteen adversarial cases of
my own; every single one behaved exactly as the spec says. This is the first round where I
could not hole that script.

What fails the round is much smaller and entirely mechanical: the spec points at
**`ci.yml:143`** three times, and that line does not exist — the workflow file is 138 lines
long and has been since the single commit that created it. The claim the citation supports
("CI runs this on every PR") is **true**; only the pointer is wrong. It matters because it is
the evidence for the fix to round 1's version finding, it was introduced by that very fix
commit, and it makes §4.2 the third consecutive revision to ship a false statement about CI.
The fix is one number in three places and changes nothing about the design.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/spec-code-drift` | `skills/writing-specs/SKILL.md` | "Drift causes hallucination… keeping them aligned is not tidiness; it is correctness" — a spec's citations into the codebase must resolve | §Status block (L37), §4.2 "Node floor" paragraph (L357), §13 follow-up 8 (L1651) | `ci.yml:143` is cited three times as the line running `npm run test -- --run`; the file is 138 lines total and has been since its only commit (`59f0879`), so the pointer has never resolved — the actual line is **138**. |

**Deliberately a new id, not a reuse.** Neither prior id recurs:
`writing-specs/pinned-versions` is fixed (a floor is pinned, in two sections, with fu 8
guarding it) and `writing-specs/required-toolchain` is fixed (executed matrix, mandated
specifier, named config change). Filing this under `pinned-versions` because it shares a
sentence would falsely signal that the Node-floor violation persisted.

### What I verified by execution (not by reading)

**Round-1 violation 1 — `writing-specs/pinned-versions` → FIXED.**
Three Node runtimes were available locally, which brackets the floor from both sides:

| Node | `node build/headers-expected.ts` unflagged | with `--experimental-strip-types` |
|---|---|---|
| 22.13.1 | ❌ exit 1 `ERR_UNKNOWN_FILE_EXTENSION` | ✅ exit 0 |
| 23.7.0 | ✅ exit 0, correct policy | ✅ exit 0 |
| 26.5.0 | ✅ exit 0, correct policy | ✅ exit 0 |

Consistent with the documented 22.18.0 / 23.6.0 arrival the spec names, and it independently
confirms §13 fu 8's hazard: a sub-floor 22.x genuinely cannot run the wrapper. The spec's own
hedge ("what was verified is 26.5.0, not where the boundary sits — confirm at implementation")
is honest and now has a second data point. `stdout` purity re-confirmed: 201 bytes, exactly
the emitted line; `MODULE_TYPELESS_PACKAGE_JSON` goes to stderr.

**Round-1 violation 2 — `writing-specs/required-toolchain` → FIXED.**
§4.2's three-way matrix reproduces *exactly*, run against a faithful copy of the real node
project (tsc 5.9.3, inherited `tsconfig.node.json`, `src/main` + `src/preload` present so
node globals resolve — no TS2591 on `process`):

| Import in `headers-expected.ts` | `node build/headers-expected.ts` | `tsc --noEmit -p tsconfig.node.json --composite false` |
|---|---|---|
| `./csp.ts` | ✅ exit 0, correct policy | ❌ TS5097 |
| `./csp` | ❌ `ERR_MODULE_NOT_FOUND` | ✅ clean |
| `./csp.js` | ❌ `ERR_MODULE_NOT_FOUND` | ✅ clean |

With `"allowImportingTsExtensions": true` added to `tsconfig.node.json` and the `./csp.ts`
specifier in place — **answering the caller's two direct questions**:

- `typecheck:node` → **exit 0**; `typecheck:web` → **exit 0** (i.e. `npm run typecheck` green)
- `electron-vite build` → **exit 0**, renderer + main + preload all built (i.e. `npm run build` green)
- TS5096 caveat is **real and reproduces**: plain emitting `tsc -p tsconfig.node.json` → TS5096,
  and `tsc --build tsconfig.json` → TS5096. Nothing in the repo runs either (no script, no CI
  step, no husky/lint-staged) — so the spec's scoping of the caveat is accurate.
- `build/csp.ts` is fully erasable (no `enum`/`namespace`/`declare`/parameter properties) ✓.
- Rejected runners confirmed: `tsx`/`ts-node`/`vite-node` absent from `node_modules/.bin`;
  `esbuild` present at **0.25.12**, and **not** a direct dependency ✓.

**§11.2 step 9's gate — extracted verbatim from the spec and executed.** All **17** documented
fixtures returned the documented exit code, on **bash 3.2.57** (the oldest realistic shell, so
GNU bash in CI is safe): healthy⇒0; 301+200-no-headers⇒2; 301+200-with-headers⇒2; 103 Early
Hints⇒2; 404-with-8-perfect⇒2; no-status⇒2; empty-served⇒2; empty-expected⇒2; missing-expected⇒2;
7-line-truncated⇒2; expected-dup-at-conflicting-values⇒2; four-weakened⇒1 (output names all
four); missing-header⇒1; served-dup-conflicting⇒1; reverse-sort-order⇒1; HSTS-preload⇒1;
CR-laden-expected⇒0. Both documented asymmetries hold (identical dup in *expected* ⇒ 0;
identical dup in *served* ⇒ 1).

**Fourteen adversarial probes of my own** — all matched the spec: whole-served-response pasted
as expected ⇒ 2 (Cloudflare's `cf-ray`/`server`/`date`/`nel` push distinct names past `WANT`,
exactly as claimed); **one value pasted ⇒ 0** (the documented uncaught half, correctly written
as a prohibition); extra CF headers on a healthy 200 ⇒ 0 (documented limitation); LF-only
served file ⇒ 0; no-space-after-colon ⇒ 1; value case-flip ⇒ 1; blank line in expected ⇒ 0;
`HTTP/1.1 200 OK` ⇒ 0; healthy 200 then trailing 500 ⇒ 2; proxy `200 Connection established`
⇒ 2; typo'd expected header name ⇒ 1; served CSP re-adding `'unsafe-inline'` ⇒ 1.
**v7 survived; I could not hole it.** (Two initial "divergences" were my own fixture bugs —
Python universal-newline translation — not script defects.)

**§4.1's tightened `ORIGIN_RE`** executed against its own claim list: all eight claimed
accepts return the right bare origin; all of interior CR/LF, bare LF, embedded space, trailing
`;`, trailing `'`, `"`, userinfo, wildcard host, `javascript:`, `ftp://`, protocol-relative
`//a.co`, and comma-separated injection **throw** — i.e. every case T-11 names. A trailing-only
CR is stripped by the retained `.trim()` and returns a clean origin, which is precisely what the
spec documents ("stripped and accepted, not rejected… both readings fail closed").

**Baseline and citation accuracy.** `npm run test -- --run` in an isolated copy →
**38 files / 300 tests, all passing** — §11.2 step 2's stated baseline is exact. §12's eight
pinned versions all match the installed tree exactly (vite 7.3.6, rollup 4.62.2, vitest 4.1.10,
typescript 5.9.3, electron 39.8.10, electron-vite 5.0.0, both Supabase packages 2.110.5); npm is
12.0.1. §5.2's security evidence for dropping `'unsafe-inline'` is exact: **22** `style={{`
props, **zero** `dangerouslySetInnerHTML`/`innerHTML`/style injection. Roughly 25 `file:line`
citations were checked and every one but `ci.yml:143` is correct — `csp.ts:15`, `csp.test.ts:5-11`
and `:13-20`, `index.html:10`, `.gitignore:9` (plus the `git check-ignore` claim that
`.env.bak.local` is ignored and `.env.local.bak` is not), `vite.config.web.ts:48`,
`supabaseClient.ts:5`/`:22`, `SignInScreen.tsx:80`/`:162`/`:170`, `SignInScreen.test.tsx:144`,
`App.tsx:20`, `avatar.ts:9-22`/`:13-15`/`:20`, `config.py:15`/`:20`/`:23-25`, `main.py:31-36`,
`middleware.py:1-5`, `ci.yml:20`/`:128`. `.env.local` is indeed absent from this checkout, so
§11.2 step 1's new conditional is justified. All linked docs exist (ADR-0009, ADR-0010,
`docs/Backlog/03-web-app.md` Tasks 3/5 + §Verification, `coding-memory/web-app-03.md`).

**Last cycle's count defect has not recurred:** exactly **17** `⇒` clauses, one per fixture, and
all five enumerated sites say "seventeen", with site 5's arithmetic (14+2+1) correct. The
surviving "sixteen"/"fifteen" mentions are historical prose about the old defect.

### Advisory (non-blocking — for the user, not auto-applied)

1. **§4.2's PSL line number (`public_suffix_list.dat` line 12732) is the one factual claim I
   could not check** — it needs network access. The substantive claim (`pages.dev` is on the
   Public Suffix List, so `includeSubDomains` is safe and `preload` is not ours to set) is
   independently well-established; only the line number is unverified here.
2. **Spec length.** 1,708 lines, of which ~60 in the header are compliance-round history
   (which round cited what, in which cycle), plus a dozen in-body "an earlier revision claimed
   X, that was false" paragraphs. Nearly all of it duplicates `coding-memory/web-app-03.md`.
   `writing-specs` treats tokenization as a hard constraint ("padding can degrade reasoning
   quality even under a generous context window") and grounds the whole practice in an artifact
   "small enough for a human to actually read end to end". Not cited — the failure-mode
   narratives are load-bearing (they are *why* T-15/T-16 exist) — but the judge-round ledger in
   the header is process metadata that would lose nothing by living only in coding-memory.
3. **"Luck, not a guarantee" slightly overstates the CI risk.** `actions/setup-node` with
   `node-version: "22"` resolves to the *latest* 22.x, which cannot move backwards below
   22.18.0, so the floor holds for any future 22.x. The record and fu 8's guard are still right;
   only the framing is pessimistic.
4. **The TS5096 caveat could name the solution config specifically.** `apps/desktop/tsconfig.json`
   (`"files": []` + `references`) exists precisely to be driven by `tsc --build`, and that is the
   invocation an IDE or a future contributor is most likely to reach for. §4.2 says "a future
   `tsc --build`" generically; naming `tsconfig.json` would make the trap findable. Verified: no
   script, CI step, or git hook runs it today.
5. **Renderer path shorthand persists** (fourth round running, still not cited): `App.tsx:20`,
   `auth/supabaseClient.ts:5`, `avatar.ts:13-15` all resolve under
   `apps/desktop/src/renderer/`**`src`**`/`.
6. **Portability datum for §13 fu 9** (scheduled CI run of the gate): the script is clean on
   bash 3.2.57 and uses no GNU-only flags, so moving it to an ubuntu runner needs no changes.
7. **No error found in the dispatch brief's substance** — blob sha, round number, waiver status
   and both round-1 descriptions matched primary sources. One drift: the brief's HEAD (`1b66b52`)
   was superseded by `a9592dc` during evaluation; the spec blob is unchanged, so the judgement
   stands.
8. **Read-only contract honoured.** No repo file was created, edited, or checked out; no
   `git checkout`. All probes live in `/tmp/judge-*`, `/tmp/hdrfix`, `/tmp/check-headers.sh`.
   The `npm run build` verification ran against a `tar`-copied tree in `/tmp/judge-build` with
   `node_modules` symlinked, so no build artifact touched the repo. `git status` at entry and
   exit shows only the pre-existing unrelated modification to
   `coding-memory/observability-judge/2026-07-28-main.md`, which I left untouched.

---

## 2026-07-28 — cycle 3, round 3 — **PASS** (0 violations)

- **spec_blob_sha:** `014e664da877aa3d1f3498628db7601bebbc3679`
- **repo/branch/HEAD:** mtg-wizard / `main` / `f94894675e1a2d91e0f5c6288a318c941c9dabcb`
- **Waived:** none (nothing has ever been waived on this spec, any cycle)
- **Prior ids this cycle:** r1 `writing-specs/pinned-versions`, `writing-specs/required-toolchain`
  (both confirmed fixed at r2); r2 `writing-specs/spec-code-drift`. **None recurred.**

### Layman summary

The spec passes. The one blocking defect from last round — a line-number pointer at
`ci.yml:143` in a 138-line file — is fixed at all three live sites, and I confirmed by
opening the file that line 138 really is the line that runs the test suite. I did not take
the change list on trust: I rebuilt the spec's code in a throwaway copy of the app and ran
it. Every claim the spec makes about what happens when you actually execute something turned
out to be true.

The riskiest new claim was the two-line TypeScript config change. The spec says you need
*both* `allowImportingTsExtensions` and `noEmit`, and that adding only the first breaks a
build command the repo uses today. That is exactly what happened: with one line the project
build fails with error TS5096; with both lines it exits clean, and typecheck, lint and the
full Electron build all pass. The spec had previously described this as a "future" risk and
has now correctly re-scoped it as a present one.

I also attacked the header-verification script — the one that has shipped broken six times.
I extracted it from the spec, built all seventeen fixtures it claims to handle, and ran
them: seventeen for seventeen, exact exit codes. Then I built eleven adversarial cases of my
own that the spec never mentions (a trailing 500, a proxy CONNECT preamble, mixed-case header
names, a pasted-in Cloudflare response, and others). All eleven behaved as the spec's prose
predicts, including the two holes the spec openly admits it cannot close. I could not hole
it. This is the second consecutive round in which v7 has survived an independent attempt.

The fixture count now reads consistently at exactly five places, the enumeration really does
contain seventeen arrow-clauses, and site 5's internal arithmetic (14 + 2 + 1) adds up.

One thing the brief asked me to check did turn up a small flaw — see advisory 1. It is not
blocking: it is an over-broad sentence in a new navigation aid, not a broken pointer, and the
citation it fails to cover still resolves correctly from the sentence around it.

### Verification performed (execution, not reading)

| Claim | Method | Result |
|---|---|---|
| `ci.yml:138` = `run: npm run test -- --run` | read file, 3 live sites | ✅ (the 4th `:143` is historical narrative, correct as-is) |
| `ci.yml:20` floating major, consumed at `:128` | read file | ✅ |
| `tsconfig.json` is `files: []` + `references` solution file | read file | ✅ |
| §4.2 three-way import matrix (`./csp.ts` / `./csp` / `./csp.js`) | fresh sandbox per case, tsc 5.9.3 + node | ✅ exactly as tabled (TS5097 / ERR_MODULE_NOT_FOUND ×2) |
| `allowImportingTsExtensions` alone ⇒ `tsc --build` TS5096 | clean tree | ✅ **not hypothetical — reproduced** |
| both lines ⇒ `tsc --build` exit 0 | clean tree | ✅ |
| `npm run typecheck` (both halves) | sandbox | ✅ exit 0 |
| `npm run lint` = 0 errors / 7 warnings | sandbox | ✅ exact baseline |
| `npm run build` (electron-vite, 3 bundles) | sandbox | ✅ exit 0 |
| §11.2 step 2 baseline 300 tests / 38 files | vitest run | ✅ exact |
| `build/*.test.ts` runs under existing vitest config | vitest run | ✅ discovered, no config change |
| `csp.test.ts:5-11` goes red on the hardened string | vitest run | ✅ fails at `:6`, as predicted |
| `check-headers.sh` — all 17 fixtures | extracted from spec, fixtures derived from `buildHeadersFile` | ✅ **17/17 exact exit codes** |
| 11 adversarial probes beyond the 17 | own fixtures | ✅ all match documented behaviour |
| §4.1 tightened regex: 7 accepts / 10 rejects | node | ✅ all hold; non-capturing variant → `undefined` (defect note correct) |
| §4.1 exact production CSP string | string compare | ✅ byte-match |
| §4.5 meta ≡ `buildCspContent({},{isDev:true})` | string compare | ✅ byte-identical |
| wrapper stdout clean, `MODULE_TYPELESS_PACKAGE_JSON` → stderr | redirect test | ✅ 8 lines, 8 distinct names |
| Node floor rows 22.13.1 / 23.7.0 / 26.5.0 | local nvm runtimes | ✅ ❌-with-flag-✅ / ✅ / ✅ |
| esbuild 0.25.12 transitive; tsx/ts-node/vite-node absent | package.json + .bin | ✅ |
| no root `package.json`; root `.nvmrc` = `22`, none in `apps/desktop` | fs | ✅ (trap 4 holds) |
| `.env.bak.local` ignored, `.env.local.bak` not | `git check-ignore -v` | ✅ |
| every `file:line` citation in the document | resolved each against the repo | ✅ all resolve to correct content |
| §/T-nn/S-nn cross-references | enumerated | ✅ contiguous, all defined, no dangling refs |
| fixture count at five sites + 17 `⇒` clauses | grep + count | ✅ consistent; 14+2+1=17 |

### Violations

**None.** `violations: []`.

### Advisory (non-blocking) — for the user, not auto-applied

1. **§4 path-conventions box over-claims universality.** It opens "they apply to every
   `file:line` in this document", but its Python row enumerates only `main.py`, `config.py`,
   `middleware.py` → `services/core-api/core_api/`. §13 follow-up 5's `schemas.py:24` is
   **ai-service** (`services/ai-service/ai_service/schemas.py:24` = `provider: Literal["anthropic",
   "ollama"] …`, which is the line the sentence means); resolved against core-api, line 24 is
   `legalities: dict[str, str]`. Several bare-basename shorthands (`csp.ts:15`,
   `csp.test.ts:5-11`, `avatar.ts:13-15`, `supabaseClient.ts:5`, `SignInScreen.test.tsx:144`)
   also fall outside the box's three rules, though **all of them resolve correctly** from
   their section context — I checked each. Cheapest fix: add an ai-service row, or soften
   "every" to "every citation not already fully qualified in its own section". Not blocking:
   nothing here changes what gets built, and no pointer is dangling. *(The brief predicted
   this box was the likeliest site of a fresh error — that judgement was right.)*
2. **Header length — carried, still open.** ~85 lines of judge-round history duplicating
   `coding-memory/web-app-03.md`. The user has explicitly deferred this to a post-pass
   decision rather than pruning mid-cycle; recorded as still-open, not re-litigated.
3. **PSL line 12732 unverified** (needs network) — carried unchanged from prior rounds.
4. **Node floor boundary rows not independently re-bracketed.** 22.17.1 / 22.18.0 / 23.5.0 /
   23.6.0 need runtime installs (no network). The three rows runnable locally all match, so
   the table is consistent with everything checkable here.
5. **§12's "Confirm at implementation, do not assume" survives — correctly.** It is about the
   Cloudflare v3 image's Node default (a vendor-side fact) and states the invariant ("an
   exact patch"), so it is *not* the §4.2 hedge that was deleted this round. Noting so a
   future round does not mistake one for the other.

### Waiver record

Nothing waived, this round or any prior round, in any cycle.
