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
