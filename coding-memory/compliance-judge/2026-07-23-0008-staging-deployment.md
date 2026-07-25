# Compliance Judge — spec 0008 (Staging Deployment, Render free tier)

- **Spec:** `docs/specs/0008-staging-deployment.md` (blob `328a9ea8f7b967228297ddb8438f9cdbad4f798d`)
- **Companion ADR:** `docs/decisions/0017-staging-free-tier-local-worker.md` (blob `1e164f29ee7619b5775a5f4e75595b970edd1fc4`)
- **Repo:** Snatch-Bracket @ `main` (`6d8c6755fcdde6e72fe22cc78c0ed5e8768e24fe`)

## Round 1 — 2026-07-23 — FAIL (1 violation)

### Layman summary

This spec puts the app on the internet for the first time — a free, personal test
copy on Render that Mark can open from his phone. It's a well-behaved spec: it
builds only what the $0 budget decision needs, writes down every trade-off (cold
starts, the database that gets wiped every 30 days, the scoring worker staying on
the laptop), keeps all passwords/keys out of the committed files, and hardens the
seed script so it can't accidentally write to a remote database without you typing
the database's name twice. One real gap: the deployment file never says which
Postgres version to create. The diagram promises Postgres 16 (what local dev and CI
use), but Render would just pick its own current default — so staging could quietly
end up on a different database version than everything else. One line in
`render.yaml` fixes it.

### Violations

| id | rule source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` (also `rules/core-conduct.md` "Pin exact library/tool versions") | Pin the exact version of every library and tool the spec names | §3 Architecture / §4 Blueprint contract / §8 Toolchain | The architecture names Postgres 16, but the `render.yaml` `databases:` block declares no Postgres version (e.g. `postgresMajorVersion`), so Render's current default major would silently diverge from the Postgres 16 pinned by local compose and the CI service container. |

### Notes (non-blocking)

- **Staging DB access posture unstated:** the design requires external connections
  (laptop worker, seed, `psql`) to the new Render Postgres but never states its
  network access-control posture. Access is credential-gated + `sslmode=require`,
  so this is not cited as a `default-deny` violation, but runbook §6.1 should add
  Render's DB IP allow-list step (Mark's laptop) or record explicit acceptance of
  allow-any-IP-with-credentials.
- **Start-time migration failure only implicit:** `alembic upgrade head && uvicorn …`
  short-circuits and the deploy fails health check; a troubleshooting line in
  runbook §6.6 stating what a red deploy after a bad migration looks like would
  make the boundary explicit.
- **Spec location is compliant:** `docs/specs/` conflicts with the global
  `docs/superpowers/specs/` convention, but project-standards §4 fixes spec
  location at `docs/specs/` and project rules take precedence — not a violation.
- **Cosmetic Gherkin:** the "Scores recompute only when the laptop worker runs"
  scenario uses Given→Then→When ordering; meaning is unambiguous.

### Waivers

None requested; none applied.

## Round 2 — 2026-07-23 — PASS (0 violations)

- **Spec blob this round:** `a4ef6ac0ad6c697534d60b79e9f9aa6cbf67e8d2` (revised since
  round 1; ADR 0017 blob unchanged at `1e164f29ee7619b5775a5f4e75595b970edd1fc4`)

### Layman summary

Round 1's single blocker is fixed: the deployment file now tells Render to create
Postgres 16 (`postgresMajorVersion: "16"`) — the same version local dev and CI use —
and the toolchain table records the pin. The revision also folded in every round-1
suggestion: the spec now states plainly what being on the public internet means for
this staging copy (anyone who finds the URL can read everything, sign up, and post
in the Tea Room — accepted because the data is disposable seed data, and flagged for
revisit before production), tells Mark to add his laptop's IP to the database's
allow-list, explains what a failed start-time migration looks like in the deploy
logs, makes the rebuild command refuse to run against a remote database unless the
seed script's opt-in variable is set, and fixes the out-of-order Gherkin scenario.
No rule violations remain — verdict: pass.

### Violations

None.

### Notes (non-blocking)

- **Rebuild guard checks presence, not host match:** the `staging-rebuild` recipe
  guards only that `SEED_ALLOW_REMOTE` is non-empty before running `alembic upgrade`
  — a mistyped remote `DATABASE_URL` could still receive migrations that the seed
  step then refuses (exact-host matching lives inside `seed_demo.py`). Low stakes
  (migrations are additive; data writes stay protected by the exact match), but
  validating the exact host before alembic too would close the last gap.
- **§4 "verify at implementation" items are not TBDs:** each (blueprint-declared
  free Postgres, corepack in the Node build image) carries a stated fallback path,
  so they read as verification steps with defined outcomes.

### Waivers

None requested; none applied.

## Round 3 — 2026-07-23 — PASS (0 violations)

- **Spec blob this round:** `66fc19028b9a4587f7f77d0d6e0c84a731df0ab7` (user-directed
  edit during the review gate; ADR 0017 blob unchanged at
  `1e164f29ee7619b5775a5f4e75595b970edd1fc4`)

### Layman summary

Mark asked for exactly one change after the round-2 pass: close the loose end both
judges had noted — the rebuild command used to check only that the remote-database
permission variable *existed*, not that it named the *right* database, before running
schema migrations. The fix is clean: the seed script gains a check-only mode
(`--guard-only`) that runs the identical host-matching guard and reports pass/fail
without ever touching the database, and the rebuild recipe now runs that check first.
So migrations can no longer reach any remote database unless `SEED_ALLOW_REMOTE`
names the exact target host — the same rule, enforced by the same code, as seeding
itself. A new Gherkin scenario pins the behavior and the guard test matrix was
extended to cover the new flag. Nothing else changed since the round-2 pass, and the
change is the opposite of scope creep: it's a directed hardening that reuses existing
code rather than duplicating the policy. No violations — verdict: pass.

### Violations

None.

### Notes (non-blocking)

- **Recipe fail-fast is load-bearing:** the new scenario's "guard exits non-zero
  *before* alembic runs" relies on `just`'s default behavior of aborting a recipe
  when a line exits non-zero. That holds for §5.3 as written; noted only so a future
  edit doesn't prefix the guard line with `-` (ignore-error) and silently defeat it.
- **Round-2 notes reconciled:** the "rebuild guard checks presence, not host match"
  note is closed by this edit; the "§4 verify-at-implementation items carry stated
  fallbacks, not TBDs" note stands unchanged.

### Waivers

None requested; none applied.
