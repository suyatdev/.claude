# Compliance Judge — pane-layout-v2-design

Spec: `docs/superpowers/specs/2026-07-21-pane-layout-v2-design.md`
Repo: `.claude` · Branch: `feature/pane-layout-v2` · HEAD: `bb4050b90a65e24bdabe919c03c20e2a3100a362`
Spec blob: `aeb007433302761a3ce50ead699c2bc2fb507cba`

## Round 1 — 2026-07-21T18:32:03Z

**Verdict: PASS** (0 violations)

### Layman summary

This spec is the follow-on to the pane-orchestration design that passed judging earlier
today, and it holds itself to the same standard that spec only reached on its second round.
Every tool it names is pinned (cmux 0.64.20 (100), jq 1.7.1, claude CLI 2.1.216, shellcheck
0.11.0), and those pins match the against-installed-binaries verification recorded same-day
in the v1 writeup. The interfaces are all written down rather than left to improvisation:
the frozen `open_pane <title> <launcher>` adapter contract, the title grammar with an
anchored recognition regex, the three-verb action-plan shape the new pure helper returns,
the `agent-exit` marker contents, and the `--role` flag → `PANE_AGENT_ROLE` env mapping.
I checked the title grammar character-by-character against the frozen security allowlist
from PR #23 — it fits entirely inside it, and the spec correctly forbids truncation from
ever eating the recognition prefix.

The scope discipline is the strongest part. The one place the design goes beyond the user's
literal Q&A answers — reusing finished aux surfaces, not just quadrant slots — is flagged in
its own bolded paragraph for user sign-off instead of being slipped in, which is exactly how
core-conduct says architecture decisions should travel. Generality nobody asked for
(adapter-agnostic layout primitives, timeout wrappers, `close-surface` cleanup, pane
resizing) is explicitly declined with reasons. Error handling is a full table where every
layout-smarts failure degrades to today's dumb-but-working behavior and only the failures
that meant "terminal unusable" yesterday still trigger the cooldown — the blast radius of
the new smarts is provably zero new hard-failure modes. The Gherkin block covers good
(build, reuse), bad (garbage flag, derivation failure), and edge (overflow tabs, unmanaged
panes, fail_early post-mortem preservation) without boilerplate padding. Four honest
unknowns are quarantined in a flagged-assumptions section, each with a stated degrade path,
and the two "open questions" are verification tasks with named resolution mechanisms (live
probe; test fixtures), not undecided requirements — the same criterion the v1 round-2 pass
applied. What remains is note-level only: a path-shorthand imprecision, the pending aux
sign-off, and inherited low-stakes permission posture.

### Violations

None.

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- **Open questions are verification tasks, not TBDs — but they must actually get pinned.**
  Whether `respawn-pane --command` runs through a shell (quoting for `bash <launcher>`) is
  deferred to the live probe; until pinned, the exact REUSE command form is unresolved. The
  named resolution mechanism keeps this out of the violations table; skipping the probe at
  implementation start would put it back in.
- **Aux-surface reuse is pending user sign-off.** The spec surfaces it correctly; this PASS
  does not constitute that sign-off — the user review gate should confirm or strike it.
- **Path shorthand imprecision:** "All paths relative to `~/.claude/`" plus
  `state/runs/<run-id>/agent-exit` reads literally as `~/.claude/state/…`, but the real
  location is `panes/state/runs/` (verified live). Harmless in practice — the marker path is
  derived from the prompt file's `dirname` with a shape guard, not hardcoded — but one word
  (`panes/state/…`) on the next edit would close it.
- **Absolute-path default carried, not introduced:** `${PANE_CMUX_BIN:-/Applications/…}`
  keeps the pre-existing committed default (confirmed at `panes/adapters/cmux.sh:11`); the
  env override this spec adds is an improvement, and `/Applications` is the canonical macOS
  bundle location. Noted against the zero-trust "no absolute paths" line, not cited.
- **Marker store permissions inherited:** `agent-exit` carries only `DONE`/`FAILED` inside
  existing uid-scoped `panes/state/runs/<id>/` dirs — same low-stakes posture as the carried
  permissions note on the v1 spec.
- **Assumption 3 (title survival across `restore-session`) is deliberately observational** —
  degrade path is benign (everything looks unmanaged ⇒ fresh splits, never broken).
  Acceptable as designed.
- **Verified this round:** all three named test suites and both touched scripts exist;
  live run-dir names match the `[0-9]+-[0-9]+-[0-9]+` run-id grammar exactly;
  `PANE_STATE_DIR`/`PANE_CLAUDE_BIN` are real precedents in the codebase for the proposed
  `PANE_CMUX_BIN`; title grammar ⊂ frozen allowlist `[A-Za-z0-9 ._:-]`; toolchain pins match
  the same-day binary verification in the v1 round-2 writeup (binaries not re-run this
  round); spec sits at the canonical `docs/superpowers/specs/` path; Mermaid diagram present
  with a stated validation step.
