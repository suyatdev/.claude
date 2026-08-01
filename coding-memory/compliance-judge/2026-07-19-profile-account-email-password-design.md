# Compliance Judge — profile-account-email-password-design

Spec: `docs/superpowers/specs/2026-07-19-profile-account-email-password-design.md`
Repo: `mtg-wizard` · Branch: `main` · HEAD: `f34897368c2f05c4acfd7d1676f73c70869f3f43`
Spec blob: `bb9c18408ab53fb7c682a0110800274f91001796`

## Round 1 — 2026-07-19T16:45:38Z

**Verdict: FAIL** (3 violations, all fixable in the spec text — no redesign needed)

### Layman summary

This is one of the strongest specs I've judged in this repo. I independently checked every
code claim it makes — the `run()` helper at `SignInScreen.tsx:25-41`, the feedback
`role="alert"`/`role="status"` block at `:120-127`, the `noValidate` comment at `:95-99`, the
`session === null` avatar guard at `ProfileScreen.tsx:146`, the `<fieldset>`/Avatar insertion
point, all eleven Tailwind tokens in `tailwind.config.js`, the exact strings in
`auth/validation.ts`, and the `nonce` / `new_email` / `reauthenticate()` typings in the
installed `@supabase/auth-js` — and every single one holds up. It also does the two things
specs most often skip: it surfaces its architectural trade-offs as human-owned decisions
(§4.3 explicitly invites a reviewer to disagree about not migrating `SignInScreen`; §10.1
says a GoTrue rejection must be raised with the user, not worked around in code), and it
gates implementation on verifying a risky assumption *before* any UI gets built.

Three things still keep it from a clean pass:

1. The "Pinned versions" table hands the implementing agent caret ranges (`^19.2.1`,
   `^5.9.3`, …) for everything except Supabase. That's not academic here: `^19.2.1` has
   already drifted — the lockfile actually resolves React to **19.2.7**. The writing-specs
   skill exists precisely to stop an agent from building against a remembered version.
2. §10.2 builds a redundant second source of truth for the pending-email banner
   (`session.user.new_email ?? pendingEmail`) plus a dedicated test, to guard a LOW-rated
   risk the spec's own §4.2 says can't happen. The spec already knows the right move for an
   unverified assumption — §10.1 verifies it first. §10.2 hedges instead.
3. §4.2 types `session.user.email` as `string | undefined`, and then §5.1 renders "Signed in
   as {email}" and §7 compares the typed address against it — with no case anywhere for the
   undefined branch. The spec flagged the hole itself and then didn't close it.

None of these touch the four user-locked decisions (nonce-over-current-password, neutral
email copy, both flows in scope, per-component file layout), which I treated as approved
intent and did not re-litigate. Security is genuinely clean: no new dependency, no new
origin, no backend surface, credentials confined to component state and cleared on both
success and cancel, and §9 walks the repo's own CLAUDE.md checklist row by row.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` | "Pin Exact Versions" — "an unpinned dependency is a time machine… Pin the exact version of every library and tool" | §12 "Pinned versions" | Only `@supabase/supabase-js` is pinned exact; `react`/`react-dom` (`^19.2.1`), `vitest` (`^4.1.10`), `@testing-library/react` (`^16.3.2`), `@testing-library/user-event` (`^14.6.1`) and `typescript` (`^5.9.3`) are caret ranges, and `^19.2.1` has already drifted from the installed tree (`package-lock.json` resolves React to 19.2.7) — the fix is stating the lockfile-resolved exact versions in the table, not editing `package.json`, since a dependency bump would be its own task. |
| `core-conduct/yagni` | `~/.claude/rules/core-conduct.md` | "KISS, DRY, YAGNI"; "prefer the simplest solution that fully solves the problem" | §10.2 "`new_email` propagation", carried into §11.1 T-13 | The mitigation adds a second source of truth for one fact (`session.user.new_email ?? pendingEmail`) plus a test for the fallback path, guarding a LOW-rated hypothesis that §4.2 already asserts cannot occur ("`AuthProvider` already subscribes to `onAuthStateChange`, which fires `USER_UPDATED`, so `session.user` refreshes after `updateUser`") — the spec's own §10.1 pattern of verifying the assumption first (§11.2 step 3 already exercises exactly this banner) would settle it without the redundant branch. |
| `writing-specs/edge-cases` | `~/.claude/skills/writing-specs/SKILL.md` | "Good, bad, and edge-case scenarios… anything you leave implicit, the agent infers — and inference is where the defects come from" | §4.2 vs. §5.1, §7 and §8 | §4.2 types `session.user.email` as `string \| undefined`, but §5.1's "Signed in as {address}" line and §7's same-as-current comparison both consume it unconditionally, and §8's edge-case enumeration covers only `supabase === null` (§8.1) and `session === null` (§8.2) — leaving the implementing agent to invent what renders, and what the unchanged-email check does, when the field is undefined. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **§9's CSP row is target-conditional, stated unconditionally.** "The Supabase host is
  already in `connect-src` from 03a" is true only for the *web* build: `vite.config.web.ts`
  rewrites the meta via `build/csp.ts` from `VITE_SUPABASE_URL`, and that file's own comment
  says "the Electron build never runs these — it reads the untouched baseline meta." The
  baseline in `src/renderer/index.html` is `connect-src 'self' http://localhost:8000` with no
  Supabase origin. Not a violation and not a regression — `SignInScreen`/`AuthProvider`
  already call Supabase under the same constraint, so this feature introduces no new host —
  but §11.2's manual gate exercises only `dev:web`, so the row reads as broader verification
  than was actually done.
- **§10.2 vs. §4.3 wiring is unstated but implementable.** `runAuthAction` returns
  `Feedback | null` and its `AuthResult` type discards `data`, so a literal reading leaves no
  path for `ChangeEmailForm` to read `data.user.new_email`. It *is* reachable — the caller's
  action closure can capture the response before returning it — but the spec never says so.
  Moot if the §10.2 violation above is resolved by deleting the fallback.
- **Re-submitting an email while a change is already pending** has no scenario in §7. The
  banner renders, the form stays available, and Supabase permits overwriting the pending
  address — whether the UI should allow, warn, or block is left to inference. Lower stakes
  than the undefined-email gap, so noted rather than cited.
- **The generic throw message** (`Something went wrong. Please try again.`) is asserted by
  §6.1's throw scenario and T-07, but is absent from §5.3's copy table, which claims to hold
  "every user-visible string." Presumably it lives in `authAction.ts` per the `SignInScreen`
  precedent; worth one line saying so.
- **DRY on the duplicated `run()` helper (§4.3) is correctly handled**, not a violation: the
  spec cites core-conduct's own "a drive-by cleanup or rename is its own task", quantifies the
  cost (one duplicated 15-line helper), records the follow-up in §13, and explicitly flags it
  as a judgment call a reviewer may overturn. That is the trade-off-surfacing behavior the
  rules ask for.
- **File-size conventions comfortably met**: largest new file estimated ~110 lines, well
  under the 400-line soft preference. Naming (`AccountSection`/`ChangePasswordForm`
  PascalCase, `ACCOUNT_HEADING` UPPER_SNAKE, `isBusy`-style booleans) matches core-conduct.
- **`writing-secure-code` was read and is in territory** (auth + credential handling). No
  violations to cite: no hardcoded secrets, no new model call or prompt path, no DB access, no
  `dangerouslySetInnerHTML`, no IDOR surface (Supabase authorizes against the session), and
  the design's central choice — a server-issued, server-verified nonce so session possession
  alone is insufficient — is a strict security improvement over the current sign-out-and-reset
  path.
- **Testing rule respected**: §11.1 states existing suites stay green and unmodified (271
  tests as of `062779d`), keeping tests as the unbiased baseline.

---

## Round 2 — 2026-07-19T16:52:28Z

Re-judge after revision. HEAD: `cfc35afd9ca13740a0bcf0754fe872916a776404` ·
Spec blob: `ff2e093e96dcfeb1d80f6029341ede71f2c2fda2`

**Verdict: PASS** (0 violations; all three round-1 violations resolved)

### Layman summary

All three round-1 findings are genuinely closed, and I re-verified each one against the
real tree rather than taking the revision note's word for it.

1. **Pinned versions — fixed and independently confirmed.** §12 now lists exact resolved
   versions, and I read all eight straight out of `apps/desktop/node_modules/<pkg>/package.json`:
   react 19.2.7, react-dom 19.2.7, vitest 4.1.10, @testing-library/react 16.3.2,
   user-event 14.6.1, jest-dom 6.9.1, typescript 5.9.3, @supabase/supabase-js 2.110.5.
   Every row matches the installed tree exactly, including the React 19.2.7 that had drifted
   in round 1. The section also correctly forbids editing `package.json` to match, which keeps
   a dependency bump as its own task.
2. **YAGNI — fixed.** The `pendingEmail` fallback and its test are gone.
   `session.user.new_email` is now the single source of truth, §10.2 explains the removal,
   names the worst case (a missing cosmetic banner), and routes the residual question to the
   §11.2 manual gate — the same verify-don't-hedge pattern §10.1 already used. This also
   dissolves round 1's non-blocking note about `runAuthAction` having no path to read
   `data.user.new_email`, exactly as that note predicted.
3. **Edge cases — fixed.** New §8.6 specifies that `AccountSection` returns `null` when
   `session.user.email` is falsy, argues why there is no half-enabled state (a password flow
   that emails a code nowhere is worse than an absent control), §4.2 now forward-references it,
   and T-15 pins it.

The advisory items folded in from the observability read also hold up under check. The test
baseline claim is exact — I ran `npm run test -- --run` at this HEAD and got **277 passed
across 35 files**, matching §11.1 verbatim; `SignInScreen.test.tsx` does contain the 11 tests
§4.3 cites. The §9 CSP row is now correctly qualified: `src/renderer/index.html`'s baseline
really is `connect-src 'self' http://localhost:8000` with no Supabase origin, and
`build/csp.ts` + `vite.config.web.ts` both exist as described, so the web-build-only framing
is accurate rather than optimistic. §8.7's accepted uncapped code re-sends carry a real
rationale (Supabase's project-level limit is the true backstop; a client timer is a weaker
second limiter a reload defeats) and T-17 pins the behavior so a future change is deliberate.

Spot-checks of code claims all still hold at this HEAD: `run()` at `SignInScreen.tsx:25-41`,
the `noValidate` comment at `:95-99`, the `role="alert"`/`role="status"` block at `:120-127`,
`ProfileScreen.tsx`'s `bg-surface` input idiom (`:115`) and secondary-button styling (`:166`),
all eleven Tailwind tokens, `auth/validation.ts`'s exact strings, the `nonce` (types.d.ts:399-403)
and `new_email` (`:357`) typings, and `02-auth-accounts.md:50`'s locked "Supabase owns
`auth.users`" rule.

The four user-locked brainstorm decisions were treated as approved intent and not re-litigated.

### Violations

None.

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **§3's architecture table under-describes `AccountSection`'s guard.** The table says it
  "returns `null` in bypass mode", but there are now three null-return conditions (§8.1
  `supabase === null`, §8.2 `session === null`, §8.6 falsy `session.user.email`). The §8
  sections are unambiguous and authoritative; the one-line table summary is just stale
  relative to them. A three-word edit if the author wants it tidy.
- **Trimming is specified for the comparison but not the submission.** §7 says the
  same-as-current check trims and is case-insensitive, and `validateEmail` trims internally,
  but the spec never says whether `updateUser({ email })` receives the raw state value or a
  trimmed one. Worst case is Supabase rejecting a padded address and the error rendering
  inline, so this is cosmetic rather than a defect — but since §7 specifies trimming for the
  adjacent operation, the silence invites two readings.
- **No "updateUser throws" scenario in the email flow.** §6.1 has one for `reauthenticate`
  (T-07), §7 has none. Behavior is nonetheless fully determined by §4.3's stated contract
  (the helper falls back to the generic message on a throw), so this is an untested path
  rather than an unspecified one — not cited for that reason.
- **§8.2's cross-reference is loose.** It says `ProfileScreen.tsx:146` "already guards its
  avatar input the same way", but that line uses `disabled={session === null}` rather than a
  null return. The precedent being invoked (don't assume `AuthGate` made the session
  non-null) is real; only the phrase "the same way" is imprecise.
- **Scope item 4 (backlog bookkeeping) bundles unrelated housekeeping.** Moving the shipped
  "Assistant chat input" idea out of `ideas.md`'s Unprocessed section belongs to PR #24, not
  this feature. It is declared in scope rather than done silently, and it is a docs-only edit,
  so this is a reviewer preference call rather than a core-conduct "drive-by cleanup"
  violation — flagged in case the author would rather split it.
- **Security posture re-confirmed.** No new dependency, no new origin, no backend surface, no
  DB access, no `dangerouslySetInnerHTML`, no IDOR surface. Credentials stay in component
  state and are cleared on both success and cancel. The nonce design remains a strict
  improvement over the sign-out-and-reset path it replaces. §9 still walks the repo
  `CLAUDE.md` checklist row by row, now with the CSP caveat stated rather than implied.
- **Round-1 notes that remain open** (both still non-blocking): §5.3's copy table claims to
  hold "every user-visible string" but omits the generic throw message
  `Something went wrong. Please try again.`, and §7 still has no scenario for re-submitting an
  email while a change is already pending.

---

## Round 3 — 2026-07-23T19:48:39Z

Re-judge after the 2026-07-23 descope (ADR-0009). Repo `mtg-wizard` ·
Branch: `feature/profile-account-email-password` · HEAD: `47c60c51b65422422a52a46a754d55d5931d0a12` ·
Spec blob: `c6725e963b614145f6e45e854ff429dcd30bd3fa`

> **Round-numbering correction.** The dispatch brief said "round 1 — no prior verdict exists in
> `verdicts.jsonl`". That is not what the ledger says: rounds 1 (FAIL) and 2 (PASS) for this exact
> `spec_path` are already recorded above and on lines 4-5 of `verdicts.jsonl`. Recorded as **round 3**
> so persistence detection stays intact. Round 2 carried zero violations, so no prior ids were
> available to reuse; the finding below is new territory and gets a new slug.

**Verdict: FAIL** (1 violation — a one-paragraph fix to the banner, no redesign)

### Layman summary

I diffed the spec against the blob that passed in round 2: **the only change is the 11-line descope
banner**. Nothing else in the 645-line document moved. So the question is narrow and answerable —
does that one banner successfully fence off the email half of a spec whose body still designs it in
full? It does not, on two counts I verified directly.

First, it mis-points. It says the superseded material includes "scope item 1's email portion", but
§2's in-scope item 1 *is* the password change and has no email portion; the email change is item 2
("Change the account email") and item 3 ("Surface the current email and any pending email change"),
and both are still sitting under a plain **In:** heading with nothing marking them dead.

Second, the enumeration is introduced as "**Every** email-change section below (…)", which reads as
exhaustive, and it is not. It never names §3's architecture table — the one part of the spec that is
an actual build instruction — which still tells an implementer to create `ChangeEmailForm.tsx`
(~85 lines) and an `AccountSection` that renders a pending-change banner. Commit `c00193f`
("refactor(account): remove in-app email change") deleted exactly those; I confirmed the shipped
tree has `AccountSection.tsx`, `ChangePasswordForm.tsx`, `messages.ts` and their tests, and no
`ChangeEmailForm` anywhere. Also unnamed by the banner: §4.1's `updateUser({ email })` contract,
§4.2's `new_email` field, §5.1's whole Email UI block, §8.5's "both forms can be expanded at once"
concurrency rule (there is one form now), and §11.1's rows T-09, T-10, T-11, T-12 and T-18 — five
test cases against a component that no longer exists. That is the writing-specs drift failure in its
literal form: an agent regenerating from this spec would rebuild the descoped feature, and would
also be committing ~85 lines of work the product owner explicitly cut (the YAGNI consequence of the
same root cause, folded into the one citation rather than double-counted).

The fix is cheap and entirely in the banner: correct the scope-item numbers and add §3, §4.1, §4.2,
§5.1, §8.5 and the T-09-T-12/T-18 rows to the fenced list (or strike those passages in place).

Everything that earned the round-2 pass still holds. I re-read all eight pinned versions straight
out of `apps/desktop/node_modules/<pkg>/package.json` — supabase-js 2.110.5, react/react-dom
19.2.7, vitest 4.1.10, @testing-library/react 16.3.2, user-event 14.6.1, jest-dom 6.9.1, typescript
5.9.3 — every row of §12 matches the installed tree exactly. The password design itself is
untouched and still strong: eight Gherkin scenarios, six edge cases with reasoning, error handling
specified at the one boundary this feature has, no new dependency, no new origin, no backend
surface, credentials confined to component state. ADR-0009 is a well-formed human-owned decision
with three alternatives weighed, and it correctly keeps custom SMTP + a raised auth-email rate limit
as production prerequisites for the *password* nonce path rather than assuming the descope removed
them.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/spec-code-drift` | `~/.claude/skills/writing-specs/SKILL.md` | "Maintain it with production rigor"; "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists. Keeping them aligned is not tidiness; it is correctness." | Descope banner (lines 9-18), read against §2 Scope, §3 Architecture, §4.1, §4.2, §5.1, §8.5 and §11.1 rows T-09-T-12/T-18 | The banner claims to fence "every email-change section" but mis-points at "scope item 1's email portion" (item 1 is password-only; the email change is §2 items 2 and 3, both still listed under **In:**) and omits §3's build table — which still instructs creating `ChangeEmailForm.tsx` (~85 lines) and an `AccountSection` pending-change banner that commit `c00193f` deleted — along with §4.1's `updateUser({ email })` contract, §4.2's `new_email` field, §5.1's Email UI block, §8.5's two-form concurrency rule and five test rows (T-09-T-12, T-18), so an agent rebuilding from this spec would re-create the descoped feature. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **T-19 appears unimplemented.** §11.1 says T-19 "is what actually enforces §5.4's uniqueness
  requirement and detects a future label collision; without it §10.3 is a stated risk with no
  guard." I found no page-level test rendering `ProfileScreen` with the account section visible —
  `ProfileScreen.test.tsx` mentions no account labels, and `AccountSection.test.tsx` renders the
  section in isolation. The spec is correct here and T-19 stays valid for the password labels after
  the descope; this is an implementation gap, relayed for the author/observability judge rather than
  cited against the spec.
- **Stale status line.** The header still reads "**Status:** spec, awaiting user review" although
  the password path was verified live on 2026-07-22 and the descope landed 2026-07-23. The banner
  supplies the date but not the status. One-line fix worth making alongside the violation.
- **`messages.ts` drift.** The shipped file exports `PASSWORD_SECTION_HEADING = 'Password'`, which
  §5.3's table — the one that claims to hold every user-visible string — does not list (§5.1's
  sketch does show the heading). Round 1's note that the generic throw message
  `Something went wrong. Please try again.` is likewise missing from that table still stands.
- **Code trimming is shipped but unspecified.** `ChangePasswordForm` trims whitespace off the
  emailed code (test at `ChangePasswordForm.test.tsx:150`); §6 specifies only "a non-empty code
  check". A behavioural superset, not a contradiction — but the spec is now the weaker authority on
  it, and §7's trimming rule that used to cover this idiom is exactly what the descope removed.
- **Validation precedence is specified and honoured** — §6's "validatePassword, then non-empty code,
  then match" ordering is pinned by the three "(review)" tests in the shipped suite. Good alignment.
- **Security re-confirmed after the descope.** Territory is auth/credential handling, so
  `writing-secure-code` was read. Nothing to cite: no hardcoded secrets, no DB or shell surface, no
  `dangerouslySetInnerHTML`, no new dependency or origin, no IDOR surface (Supabase authorizes
  against the session), and `AccountSection`'s single all-or-nothing guard
  (`!supabase || !session?.user.email`) implements §8.1/§8.2/§8.6 fail-closed as written. Dropping
  the email half strictly reduces attack surface — ADR-0009's option 2 (single-confirm email change)
  was rejected on precisely the session-hijack argument, which is the right call.
- **Round-2 note now resolved by circumstance:** §7's unstated trim-on-submission and the missing
  "updateUser throws" email scenario are moot — that flow is descoped.
- **Scope item 4** (moving the shipped "Assistant chat input" idea out of `ideas.md`) is still
  bundled housekeeping from PR #24; unchanged reviewer-preference call from round 2, not cited.

---

## Round 4 — 2026-07-23 — FAIL

**Freshness key:** spec blob `bea6ad74c12f58abd3c8c6b183b8408ea6391986` @ HEAD `c1c6349` (`feature/profile-account-email-password`)

### Layman summary

The descope banner got much better this round. It now points at the right scope items (§2
items 2-3, not "item 1's email portion"), and it fences the six sections round 3 said it
missed: §3's build table row for the deleted `ChangeEmailForm.tsx`, §4.1's
`updateUser({ email })`, §4.2's `new_email`, §5.1's Email UI, §8.5's two-form concurrency,
§10.2, and test rows T-09-T-12/T-18. Round 3's headline defect is genuinely fixed, and the
stale "awaiting user review" status line from the round-3 notes is fixed too. T-19, which
round 3 flagged as unimplemented, now exists (`AccountSection.test.tsx:103`, commit
`9ea48dd`).

Two email leaks survive the new fence, both in the same territory as round 3's finding, so
the same violation id persists. First — and this is the blocking one — §11.1's opening
prose still tells a builder to create three test files, one of which is
`ChangeEmailForm.test.tsx`, for a component deleted in `c00193f`. The banner fences the
*rows* of §11.1's table but not the sentence above it, which reads as still-live build
instruction; the fix is exactly parallel to the §3 build-table row the banner already
handles. Second, the banner declares §2 "In" **item 3** superseded, but item 3 reads
"Surface the current email *and* any pending email change" — the current-email half
shipped: `AccountSection.tsx` renders `Signed in as {session.user.email}` from the unfenced
§5.1 line and the unfenced `SIGNED_IN_AS` constant. The banner's parenthetical gloss
("surface a pending change") quietly narrows item 3 without saying so, leaving the section
readable two ways about behaviour that is live in production code.

Everything else in the rubric passes: Gherkin scenarios (§6.1), contracts (§4) with the
correct "no API/DB by design" justification (§1), exact pinned versions (§12), good/bad/edge
cases (§6.1, §8), background (§1), canonical `docs/superpowers/specs/` path, KISS/YAGNI
(the descope strictly shrinks scope; §10.2 explicitly kills a speculative fallback),
explicit error handling at every boundary, human-owned trade-offs surfaced (§4.3, §10.1),
and no security findings.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/spec-code-drift` | `~/.claude/skills/writing-specs/SKILL.md` | "Drift causes hallucination: when the spec and the code fall out of sync, the agent starts describing and extending behavior that no longer exists. Keeping them aligned is not tidiness; it is correctness." + "no requirements readable two ways" | Descope banner (lines 11-42) read against §11.1's "New files" prose (line 569-571) and §2 "In" item 3 | The rewritten fence still misses §11.1's opening sentence, which instructs creating `ChangeEmailForm.test.tsx` for a component deleted in `c00193f` (only the table *rows* T-09-T-12/T-18 are fenced), and it marks §2 item 3 wholly superseded although its "surface the current email" half shipped as the unfenced §5.1 "Signed in as" line and `SIGNED_IN_AS` constant that `AccountSection.tsx` renders today. |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **Round-3 fixes confirmed.** Scope pointer corrected; §3/§4.1/§4.2/§5.1/§5.3/§5.4/§7/§8.5/§10.2
  and the five test rows are now explicitly fenced; the "What shipped" paragraph is a real
  improvement over the round-3 banner. The status line ("password-change shipped (verified live
  2026-07-22)") resolves a round-3 note, and T-19 now exists in `AccountSection.test.tsx` —
  resolving the other.
- **Stale test arithmetic.** With five rows fenced, §11.1's table carries 14 live rows, but §10.3's
  mitigation still says "the other 18 tests render the forms in isolation" and §11.2 still says "all
  19 vitest cases". Coincidentally the shipped account suite *is* 19 tests (14 in
  `ChangePasswordForm.test.tsx`, 5 in `AccountSection.test.tsx`), so these read true against the code
  and false against the fenced table. Ambiguous rather than wrong — not cited, but worth a
  parenthetical when fixing the violation.
- **Dangling cross-references into fenced material.** §6 (shipped) justifies its local busy flag with
  "see §8.5 for why it is not shared across the section", and §8.5 is now fenced in full; §10.3's
  mitigation promises T-19 "resolves every §5.3 label" when §5.3's email rows are fenced; §4.2's
  surviving `email` bullet points at "§5.1 and §7". None instruct building anything deleted, so none
  are cited — but a shipped section whose rationale lives in a "must not be built from" section is a
  readability cost.
- **§9 checklist cell is now half-stale.** "Path/identifier validation — Email validated against
  `auth/validation.ts`'s pattern before submission" describes the descoped flow; only the 6-char
  password minimum applies to shipped code. `validateEmail` survives for `SignInScreen` (ADR-0009),
  so nothing is wrong in the codebase — the cell just over-claims for this feature.
- **Security re-verified, nothing to cite.** `writing-secure-code` was read again (auth/credential
  territory). No hardcoded secrets, no DB/shell/model surface, no `dangerouslySetInnerHTML`, no new
  dependency or CSP origin, fail-closed all-or-nothing guard implemented as specced
  (`!supabase || !session?.user.email`), nonce-authorized password change unchanged. The descope
  strictly reduces attack surface.
- **ADR-0009 checked directly** and is consistent with the banner: it names the same live-gate
  failure, the same three options, and the same retained shared code (`validation.ts`,
  `authAction.ts` — both present on disk).

---

## Round 5 — 2026-07-23 — PASS

**Spec blob:** `b1c37045a8e334748e70e20203d3d7765fed25a7` · **HEAD:** `73bff19e70f80c109ca740cf6fe6595aa3854a84` ·
**Branch:** `feature/profile-account-email-password` · **Confidence:** high

### Layman summary

Clean pass. Both blocking leaks from round 4 are closed, and I confirmed each against the
shipped code rather than taking the banner's word for it.

The first leak was a sentence in §11.1 that still told a builder to create
`ChangeEmailForm.test.tsx` — a test for a component deleted in `c00193f`. That sentence now
names only the two files that actually exist (`ChangePasswordForm.test.tsx`,
`AccountSection.test.tsx`, both present on disk) and explicitly says the email test file is
superseded and was not created. Naming the file in order to rule it out is the opposite of
drift; it forecloses the ambiguity instead of leaving it.

The second leak was the banner claiming §2 "In" item 3 was wholly superseded when half of it
shipped. The banner now fences only item **2** and the **pending-email-change** half of item 3,
states plainly that the "surface the current email" half shipped, and lists it under "What
shipped" alongside §5.1's "Signed in as {email}" line and the `SIGNED_IN_AS` constant. That
matches production: `AccountSection.tsx` renders `{SIGNED_IN_AS} {session.user.email}`, and
`SIGNED_IN_AS` is live in `messages.ts`. The spec and the code now agree on what exists.

I re-walked the full rubric rather than only the delta, and spot-checked the shipped password
path against §6/§5.4: `reauthenticate()` then `updateUser({ password, nonce })`, a form-local
`isBusy` gating both buttons, `validatePassword` pre-check, `noValidate`,
`autoComplete="one-time-code"`/`"new-password"`, and `role="alert"`/`"status"` feedback — all
as specified. `ProfileScreen.tsx` gains exactly the promised import plus `<AccountSection />`.
Every file sits far under the 400-line guidance (largest: `ChangePasswordForm.tsx` at 172).
T-19, the load-bearing guard for §10.3, exists as a real page-level test. No security findings:
no new dependency, no new CSP origin, no secrets, fail-closed guard implemented verbatim.

The `writing-specs/spec-code-drift` violation is **resolved**; the persistence streak ends here.

### Violations

None.

### Waivers

None supplied; none recorded. (Round 4's escalation resulted in a user *directive to fix*, not a
waiver — both directed fixes were applied and verified.)

### Notes (non-blocking)

- **Round-4 blocking items verified against code, not prose.** `ChangeEmailForm.tsx` and
  `ChangeEmailForm.test.tsx` are confirmed deleted by `c00193f` (120 + 75 lines removed);
  `AccountSection.tsx` composes only `ChangePasswordForm` and renders no pending banner; the seven
  email strings are gone from `messages.ts`. Every banner claim I sampled is accurate.
- **Stale test arithmetic — softened, still uncited.** §10.3's "the other 18 tests" and §11.2's "all
  19 vitest cases" are not derivable from the fenced 14-row table, but the shipped account suite is
  in fact 19 `it()` cases (14 + 5) with T-19 the only page-level one — so both figures read *true*
  against the code. Round 4 flagged these as possibly stale; measuring the suite shows they are
  defensible as written. Deliberately unchanged per the user's decision, and no longer worth a fix.
- **Dangling cross-references into fenced material persist by design.** §6 still points at fenced
  §8.5 for its busy-flag rationale, and §9's "Path/identifier validation" cell still mentions email
  validation that applies only to the descoped flow. Left as-is per the user's decision. Neither
  instructs building anything deleted, so neither is blocking — a readability cost on a spec that is
  now explicitly a historical-retention document.
- **One undocumented constant.** `messages.ts` exports `PASSWORD_SECTION_HEADING = 'Password'`, which
  is not a §5.3 table row. The code comment self-documents the gap, and §5.1's structure diagram does
  show a "Password" block (named in the banner's "What shipped" list), so the string is spec-derived
  even if not tabulated. Too minor to cite; noted only so a future round does not read it as new drift.
- **Rubric re-walked in full.** Gherkin (§6.1), contracts (§4) with the correct "no API/DB by design"
  justification (§1), exact pinned versions (§12, eight packages, no new dependency), good/bad/edge
  cases (§6.1, §8.1–8.7), background (§1), canonical `docs/superpowers/specs/` path, Mermaid state
  diagram (§6), KISS/DRY/YAGNI (§10.2 kills a speculative fallback; §4.3 refuses a drive-by refactor;
  §8.7 refuses a weaker second rate limiter), explicit error handling at every boundary, and
  human-owned trade-offs surfaced rather than decided (§4.3, §10.1, ADR-0009).

---

## Round 6 — 2026-07-23T20:24:13Z — PASS

**Spec blob:** `97bd2df34972ef0654e09e7150cde120fd02b5f8` · **HEAD:** `3132b9b1682c6f0708cea1519ae820f8ba342709` ·
**Branch:** `feature/profile-account-email-password` · **Confidence:** high

### Layman summary

Re-judge after the only change since the round-5 pass: the implementation-stage observability
judge caught that §9's old claim — "session possession alone is not sufficient" — overstated
the as-deployed guarantee, since this project runs with Supabase's "Secure password change"
setting **off**. The user chose to fix the spec's wording rather than flip the dashboard toggle
right now, and that is exactly what commit `3132b9b` does: it rewrites §9's nonce paragraph and
§13 follow-up 2 to say plainly that the nonce is **client-enforced (UI-level defense-in-depth),
not server-enforced** while the setting is off, that a caller bypassing the UI with a valid
session could change the password without a code, and that enabling the toggle (tracked as
§13 follow-up 2) is what would make it a real server-side requirement.

I checked this rewrite for internal consistency rather than taking it at face value, against
three anchor points the dispatch brief named:

- **§10.1** (the pre-implementation risk entry) is untouched this round, and correctly so —
  it frames the original uncertainty ("do we know whether GoTrue accepts or rejects the nonce
  when the setting is off?") in the past tense of design-time, while §9 reports the resolved
  finding from the live probe ("§10.1's live probe confirmed the setting is currently off").
  These are two honest snapshots of the same fact at different points in time, not a
  contradiction — §9 explicitly cites §10.1 by number rather than silently duplicating or
  overriding it.
- **§4.1**'s reasoning for rejecting `current_password` ("collecting it without that setting
  on would be decorative security") is not undermined by choosing the nonce instead, because
  the two are not analogous the way a careless read might suggest: §6.1's T-05 scenario
  ("Supabase rejects the code" → "Token has expired or is invalid") proves the nonce, when
  supplied, *is* validated for correctness even with the setting off — what's not enforced is
  only that supplying one is *mandatory*. §9's new text says exactly this ("at this UI it
  raises the bar... someone at an unattended, signed-in session cannot change the password
  without also reaching the mailbox"), so the nonce remains a real (UI-scoped) barrier, unlike
  the purely decorative `current_password` field that was rejected.
- **§13 follow-up 2** now mirrors §9's framing verbatim in substance (accepted-not-required,
  client-enforced, one-click dashboard fix) rather than the round-5 phrasing ("if §10.1 forces
  it"), and the cross-reference numbering (`tracked as §13 follow-up 2`) is correct — item 2 in
  the current §13 list is indeed the "Secure password change" toggle.

No code changed this round (confirmed via `git show 3132b9b` — the diff touches only the two
named spec sections), so there is no new opportunity for spec/code drift, and I found none: the
new prose's description of the client's call sequence (`reauthenticate()` →
`updateUser({ password, nonce })`) matches §4.1's contract and §6's flow, both unchanged and
previously verified against the shipped code.

This edit is also the correct instance of the core-conduct rule "architecture trade-offs...
stay human-owned — implement once decided, don't decide": the choice not to flip the Supabase
toggle right now is stated as the user's explicit decision, the resulting known gap (nonce
bypassable via direct API call with a valid session) is disclosed rather than hidden, and it is
tracked as a concrete, numbered follow-up rather than left to accumulate silently. That is a
more accurate and more transparent spec than round 5's, not a weaker one.

### Violations

None.

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **§9's "Secure sessions" checklist row doesn't cross-reference the nonce-guarantee
  paragraph below the table.** The detailed discussion lives in prose immediately under the
  table and is referenced correctly from §13, so nothing is missing from the document — a
  reader scanning only the table row would not see the caveat, though. A one-line pointer from
  the table row to the paragraph would be tidier; not cited, since the information is present
  and correctly cross-referenced elsewhere.
- **No ADR was opened for this edit.** ADR-0009 (the email-change descope) does not mention
  the "Secure password change" toggle finding. Whether this specific correction rises to the
  "direction-pivoting" bar that earns its own ADR is a `managing-session-memory`/session-gate
  question, not a writing-specs or core-conduct rule this judge enforces — noted for the
  orchestrating session, not cited as a spec violation.
- **Full rubric re-walked, not just the delta.** Gherkin scenarios (§6.1, §7-historical),
  contracts (§4) with the "no API/DB by design" justification (§1), exact pinned versions
  (§12, unchanged), good/bad/edge cases (§8.1-8.7), background (§1), canonical
  `docs/superpowers/specs/` path, Mermaid state diagram (§6), KISS/DRY/YAGNI (§4.3, §8.5,
  §10.2), explicit error handling at the one boundary this feature has, and file-size
  conventions (largest file ~172 lines, per round 5's live check) all still hold.
- **Security re-verified** (`writing-secure-code` is in territory — auth/credential
  handling): no hardcoded secrets, no DB/shell/model-call surface, no `dangerouslySetInnerHTML`,
  no new dependency or CSP origin, fail-closed all-or-nothing guard unchanged
  (`!supabase || !session?.user.email`). The one thing this round's edit changes is the
  *honesty* of the nonce's documented guarantee, which is a strict improvement in accuracy, not
  a new vulnerability — the underlying deployed behavior (setting off) predates this edit and
  is unchanged by it.
