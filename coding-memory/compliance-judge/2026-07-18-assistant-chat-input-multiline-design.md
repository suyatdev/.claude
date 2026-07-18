# Compliance Judge — assistant-chat-input-multiline-design

Spec: `docs/superpowers/specs/2026-07-18-assistant-chat-input-multiline-design.md`
Repo: `mtg-wizard` · Branch: `main` · HEAD: `aa8a26cadc6015ddb84a65f61b52384d78a82ec7`

## Round 1 — 2026-07-18T19:49:42Z

**Verdict: FAIL** (2 violations, both fixable in the spec text — no rebuild needed)

### Layman summary

This is a small, well-run spec — it came out of a real brainstorm with the user, and the
repo's own self-review already caught and fixed a placeholder sentence and a missing
`preventDefault()`. It's clean on scope discipline (explicitly rejects an unneeded dependency,
documents the trade-offs it made and confirmed with the user) and on factual accuracy (I
cross-checked every line-number citation and code-behavior claim against the actual file and
they all hold up). Two things still keep it from a clean pass:

1. The behavior itself — how Enter and Cmd/Ctrl+Enter act differently depending on whether the
   slash-menu is open — is written as prose bullets, not as the Given/When/Then scenarios the
   writing-specs skill requires for exactly this kind of state-dependent behavior.
2. That prose-only description let a real gap through: the new Cmd+Enter/Ctrl+Enter send
   shortcut is specified as firing on the modifier keys alone, without restating the guard
   (`!isStreaming && draft.trim()`) that the current plain-Enter path already enforces. As
   written, it would let the shortcut send an empty message or fire mid-stream.

Neither is a redesign — both are a paragraph-sized addition to the existing "Enter / send
behavior" section. Everything else checked out (background/why present, no placeholders/TBDs,
canonical path, no unpinned dependency because none is introduced, security skill reviewed and
correctly out of scope for this UI-only change).

### Violations

| id | rule_source | rule | where | why |
|---|---|---|---|---|
| `writing-specs/bdd-gherkin-scenarios` | `~/.claude/skills/writing-specs/SKILL.md` | "Write Scenarios in BDD/Gherkin Form" — Scenario/Given/When/Then forces state → action → outcome and surfaces ambiguity while it's cheap to close | Design §3 "Enter / send behavior"; "Testing" section | Enter-key behavior branches on slash-menu-open state and on which modifier key is held, but is described only as prose bullets, never as Given/When/Then scenarios — exactly the structure the skill says would have forced the missing streaming/empty-draft guard (next row) to be decided explicitly instead of left implicit. |
| `core-conduct/error-handling-boundary` | `~/.claude/rules/core-conduct.md` | "Handle errors explicitly, never swallow them"; every boundary a design introduces needs stated error handling | Design §3 "Enter / send behavior" | The new Cmd+Enter/Ctrl+Enter path is specified as calling `event.preventDefault()` then `handleSend()` on `event.metaKey \|\| event.ctrlKey` alone, without restating the `!isStreaming && draft.trim()` guard the current Enter-to-send path enforces (`AssistantPanel.tsx:164`). As written, the shortcut could send an empty/whitespace draft (bypassing the Send button's `disabled={!draft.trim()}`) or fire while streaming (bypassing the Stop-button state swap that currently makes the Send button unreachable mid-stream). |

### Waivers

None supplied; none recorded.

### Notes (non-blocking)

- Sizing values ("~2 rows tall", "capped at ~8 rows") use approximate language rather than a
  named constant. Acceptable for a cosmetic auto-grow value and the Testing section already
  reasons carefully about jsdom's `scrollHeight` limitation — not blocking, but worth pinning
  down if review disagrees on the exact number.
- Testing section leaves whether the resize logic gets extracted into a testable helper as a
  conditional ("if extracted... rather than...") rather than a firm decision. Low risk — it's a
  test-authoring choice, not a behavior decision — so left as a note, not a violation.
- `AssistantPanel.tsx` is already 454 lines, over the core-conduct "many small files" ~400-line
  soft preference, before this change. The additions here (new button, hint caption, auto-grow
  effect) will grow it further but stay comfortably under the 800-line hard cap. Not this spec's
  debt to pay down, but worth watching before the next feature lands on this file.
- `writing-secure-code` skill was read and judged not in this spec's territory: the change is
  presentation/input-mechanics only (`<input>` → `<textarea>`, keybindings), doesn't touch the
  SSE/model-call boundary, sanitization pipeline, auth, or DB — `useAssistant.ts` and the backend
  are explicitly out of scope in the spec itself. No security violations to cite.
- No diagram included, and none required here under YAGNI: this is a small, single-file,
  no-new-dependency UI change, consistent with this repo's established convention for
  similarly-scoped design docs (e.g. `2026-07-16-signin-signup-prominence-design.md`), none of
  which include diagrams either.
- Factual accuracy verified directly against the source: the `AssistantPanel.tsx:161-165` and
  `:285-292` line citations, the current placeholder text, the `slashQuery` regex baseline, and
  the `SLASH_ACTIONS`/`selectSlashAction` "fill" pattern all match the live file exactly.

### Metadata

- `spec_blob_sha`: `4b5bda5717f0de393bd5b3eab892a15e9e87d54c`
- `rule_sources_read`: `~/.claude/rules/core-conduct.md`, `~/.claude/skills/writing-specs/SKILL.md`, `~/.claude/skills/writing-secure-code/SKILL.md` (read per gate, judged not-applicable), repo `CLAUDE.md` (no `.claude/project-standards.md` present in this repo)
- `confidence`: high

## Round 2 — 2026-07-18T19:55:48Z

**Verdict: PASS** (0 violations)

### Layman summary

Both Round 1 gaps are fixed, and the fix is done the right way rather than patched over. Section
3 ("Enter / send behavior") is now four explicit Given/When/Then scenarios — slash-menu-open,
plain-Enter, Cmd/Ctrl+Enter-with-valid-draft, and Cmd/Ctrl+Enter-with-guard-failure — instead of
prose bullets. That fourth scenario is exactly the one that was missing before: it restates the
existing `!isStreaming && draft.trim()` guard from `AssistantPanel.tsx:172` and spells out that a
failed guard falls through to plain newline insertion rather than silently doing nothing or
sending anyway. The Testing section was updated in lockstep to assert that fallback explicitly. I
re-verified every line-number and behavior citation in the spec (`:161-165`, `:172`, `:285-292`,
the placeholder text, the `slashQuery` regex baseline) against the live file — all still accurate.
No new issues were introduced by the fix: the four scenarios cover complementary branches rather
than padding with redundant blocks, and nothing outside §3/Testing changed. Everything that passed
in Round 1 (YAGNI discipline on the rejected dependency, background/why, canonical path, no
placeholders, security skill correctly judged out of scope) still holds.

### Violations

None.

### Waivers

None supplied; none recorded.

### Notes (non-blocking, carried from Round 1, unchanged)

- Sizing values ("~2 rows", "~8 rows") remain approximate rather than named constants — still
  acceptable for a cosmetic auto-grow value.
- Testing section still leaves whether the resize logic is extracted into a testable helper as a
  conditional rather than a firm decision — test-authoring detail, not a behavior gap.
- `AssistantPanel.tsx` is 454 lines before this change (over the ~400-line soft preference), and
  this design adds a button, a caption, an auto-grow effect, and expanded key-handling branches on
  top of that. Still comfortably under the 800-line hard cap, but worth watching before the next
  feature lands on this file.
- `writing-secure-code` skill re-read and re-judged not in this spec's territory: no change to
  scope since Round 1 (UI/input-mechanics only; `useAssistant.ts`, the SSE path, and the backend
  remain explicitly out of scope).

### Metadata

- `spec_blob_sha`: `88a2623b8fd50763b98f667c75a4ab0902df2699`
- `head_sha`: `9d7b5d69ae4e157f93618654cd37bd080290101e`
- `rule_sources_read`: `~/.claude/rules/core-conduct.md`, `~/.claude/skills/writing-specs/SKILL.md`, `~/.claude/skills/writing-secure-code/SKILL.md` (read per gate, judged not-applicable), repo `CLAUDE.md` (no `.claude/project-standards.md` present in this repo)
- `confidence`: high
