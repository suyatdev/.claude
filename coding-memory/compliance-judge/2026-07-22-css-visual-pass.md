# Compliance judge — css-visual-pass

- **Spec:** `docs/specs/2026-07-22-css-visual-pass.md`
- **Repo:** vibe-scape

## Round 1 — 2026-07-23T02:53:03Z

- **Branch:** `docs/memory-css-pass-brainstorm-parked`
- **HEAD:** `7f75e28ee211395eab497ef533ed196aa24ea1c9`
- **Spec blob:** `0abdc083f57781124f02de9e409fdadfcf01a933`
- **Verdict:** ❌ **FAIL** (1 violation)
- **Confidence:** medium

### Layman summary

The spec is a genuinely strong, tightly-scoped CSS visual pass: it pins every
design token to an exact value, enumerates edge cases (reduced motion, no-blur
fallback, non-latin/emoji glyph fallback, contrast, z-index ladder), carries a
real "why", separates test-changes from implementation for TDD, and draws a
clear out-of-scope boundary. One thing keeps it from a clean pass: the two
self-hosted fonts (Sora, JetBrains Mono) name Fontsource as their source but do
**not** pin an exact release version in the spec — the source URL and SHA-256
are deferred to be recorded in the PR at implementation time. That means the
document a human reviews before code exists contains no verifiable, reviewable
version pin for a dependency, which the "pin exact versions" rule requires. The
spec does specify strong compensating controls (vetted registry, per-file
SHA-256, license, self-hosted / no CDN), so this is a strong waiver candidate —
but it is a real, rule-backed gap, not a taste call.

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/pinned-versions` | `~/.claude/skills/writing-specs/SKILL.md` | Pin the exact version of every library and tool. | §2 File architecture — `packages/client/src/assets/fonts/` (vendored Sora + JetBrains Mono) | The vendored fonts name Fontsource as source but pin no exact release version in the spec; source URL + SHA-256 are deferred to implementation-time PR recording, so the human-reviewed spec holds no verifiable font version pin. |

### Notes (non-blocking)

- Strong compensating supply-chain controls are specified (vetted Fontsource
  registry, per-file SHA-256 integrity, SIL OFL license, self-hosted / no
  runtime CDN) — a reasonable user-waiver candidate if a hash pin recorded at
  implementation time is accepted as equivalent to a version pin.
- Spec location `docs/specs/` is compliant: project `CLAUDE.md` and
  `project-standards.md` §4 pin `docs/specs/`, overriding the global
  writing-specs `docs/superpowers/specs/` default (project rules win on conflict).
- TDD ordering in §4.2 is correct — the test-contract migration commit (red)
  precedes the implementation commit (green), satisfying the core-conduct
  test/implementation separation rule.
- Recipe exact values are referenced to the committed design bundle (named
  visual source of truth) rather than inlined; acceptable per writing-specs
  "reference by path", not a placeholder.

### Waivers

None (no user-waived ids supplied for this round).

## Round 2 — 2026-07-23T02:57:55Z

- **Branch:** `docs/memory-css-pass-brainstorm-parked`
- **HEAD:** `54c87a11fc3c8a443f5f638f488044ee12cdd696`
- **Spec blob:** `90296b42d47baf4307f1c24a65e8536f57057685`
- **Verdict:** ✅ **PASS** (0 violations)
- **Confidence:** high

### Layman summary

The one thing blocking round 1 is fixed. The two self-hosted fonts now carry
an exact, human-reviewable version pin in the spec itself —
`@fontsource/sora@5.3.0` and `@fontsource/jetbrains-mono@5.3.0` (dispatch
confirms both verified against the live npm registry) — plus the exact artifact
path (`files/<family>-latin-<weight>-normal.woff2`), the source URL pattern
(jsdelivr npm release), and the per-file SHA-256 kept as PR integrity evidence,
with no packages added as dependencies. That closes the "pin exact versions"
gap: the version now lives in the reviewed spec, not deferred to PR time.
Everything else that was already strong still holds — token layer pinned to
exact values, BDD/Gherkin scenarios (V1–V3, L1), enumerated edge cases
(reduced motion, no-blur `@supports` fallback, non-latin/emoji glyph
fallthrough, WCAG-AA contrast, z-index ladder), TDD red-before-green ordering,
file-size discipline (split `style.css` past ~400 lines), and a thorough
out-of-scope boundary. The round-2 revision also folded in the two obs-judge
advisories (new `--text-active` token; before/after PR screenshots in §7).
Clean pass.

### Violations

None.

### Notes (non-blocking)

- **Round-1 violation `writing-specs/pinned-versions` resolved:** §2 now pins
  `@fontsource/sora@5.3.0` and `@fontsource/jetbrains-mono@5.3.0` in the spec
  text (verified against the live npm registry per dispatch), names the exact
  artifact + source URL, keeps per-file SHA-256 as PR integrity evidence, and
  adds no dependencies.
- Existing repo toolchain (`npm run typecheck`/`npm test`, `rg` for the §3 grep
  gate) is not restated with versions — consistent with the "no new npm
  dependencies" stance (versions live in `package.json`) and with prior passing
  precedent (tea-room, pane-split specs).
- Spec location `docs/specs/` is compliant: project `CLAUDE.md` and
  `project-standards.md` §4 pin `docs/specs/`, overriding the global
  writing-specs `docs/superpowers/specs/` default (project rules win on conflict).
- Recipe exact values are referenced to the committed design bundle (named
  visual source of truth) rather than inlined — acceptable reference-by-path,
  not a placeholder.
- TDD ordering in §4.2 is correct — the test-contract migration commit (red)
  precedes the implementation commit (green).
- writing-secure-code rubric not deeply triggered: pure CSS + markup pass, no
  external-input / auth / DB / shell / model-call surface. The single
  supply-chain touchpoint (vendored fonts) is handled per core-conduct —
  pinned version, SHA-256 integrity, self-hosted, vetted registry, SIL OFL.

### Waivers

None (no user-waived ids supplied for this round).

## Round 1 (re-entry, post-review edit) — 2026-07-23T03:19:57Z

- **Branch:** `docs/memory-css-pass-brainstorm-parked`
- **HEAD:** `ac79ec74ef2b635e87ca3800c97b37b37539340c`
- **Spec blob:** `b36982fe7bb77aaeb99a4699fe08f8ba75db659d`
- **Verdict:** ✅ **PASS** (0 violations)
- **Confidence:** high

### Layman summary

Re-judged after the user approved one addition during their review of the
already-passing spec (blob `90296b42`). The only change is §7 verification
item 4: a mechanical grep guard requiring that, for each JS-`hidden`-toggled
container given a `display` value (`.login-sheet`, `.presence-picker`,
`.vote-sheet`, `.vote-confirm`, `.vote-done`), the branch fails unless
`style.css` carries the matching `[hidden] { display: none }` override — the
fake-DOM tests can't catch this cascade regression, so it becomes a hard grep
gate. This strengthens verification of the §2 cascade invariant that was
already in the spec; it adds no new scope, dependency, tool, placeholder, or
ambiguity, and its "Any miss fails the branch" is explicit fail-closed error
handling. The round-2 resolution still holds — the fonts remain pinned to
`@fontsource/sora@5.3.0` / `@fontsource/jetbrains-mono@5.3.0`, untouched by
this edit. Clean pass, verdict unchanged.

### Violations

None.

### Notes (non-blocking)

- Diff confirmed narrow: `git diff 90296b42 → b36982fe` is exactly the six-line
  §7 item 4 addition; nothing else changed since the round-2 PASS.
- Round-1 violation `writing-specs/pinned-versions` (resolved in round 2) stays
  resolved — the @fontsource 5.3.0 pins are outside the changed region.
- The new guard uses `rg` (already used by the §7.3 grep gate) — not a new
  dependency, consistent with the toolchain treatment in prior passing rounds.
- §7 item 4 enumerates a fixed five-selector set as a mechanical spot-check
  while §2 states the general rule for *any* such container; the general
  invariant remains the catch-all, so the fixed list is belt-and-suspenders,
  not a coverage gap — a completeness observation, not a defect.
- writing-secure-code rubric still not deeply triggered: pure CSS + markup, no
  external-input / auth / DB / shell / model-call surface.

### Waivers

None (no user-waived ids supplied for this round).
