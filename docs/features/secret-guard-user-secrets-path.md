---
phase: review
model_tier: high
branch: fix/secret-guard-user-secrets-path
---

# `secret-command-guard` also protects the new `~/.secrets` file and `.env/` folders

Queued 2026-11-23. Mark is moving the keys out of `~/.terminal_aliases` into a dedicated
secrets file and added `Read(~/.secrets)` / `Read(**/.env*)` deny rules to `settings.json`.
Those rules stop only the **Read tool**; a shell `cat` does not go through them. The shell side
is `hooks/secret-command-guard.sh`, and it does not know the new path.

Gate: **`gate confirmed` typed by Mark 2026-11-23.** Q1 answered the same message: the file
is `~/.secrets` (so `.secret` is dropped). Q2 was not answered; the recommended default (an
ADR 0039 amendment line, no new ADR) is adopted and flagged back to him.

## Measured (2026-11-23)

`hooks/lib/classify-secret-command.py "<command>" sid`, command text only — nothing was
executed and no file was read. rc 0 = allow, 2 = block.

| Command | rc | verdict |
|---|---|---|
| `cat ~/.secrets` | 0 | **allowed** — the file Mark is creating |
| `cat ~/.secrets/api_key` | 0 | **allowed** — if it ends up a folder |
| `cat .env/cloud.env` | 0 | **allowed** — vibe-scape's real secrets live in a folder named `.env` |
| `cat .env/cloud.env.example` | 0 | allowed (correct, and must stay so) |
| `cat .secretsfoo`, `cat my.secrets` | 0 | allowed (correct: unrelated names) |

Why `.env/cloud.env` slips through: the guard matches only the **last component** of a
path (`(^|/)\.env(\.[^/]*)?$`), so a file *inside* a folder called `.env` never matches.

## Scope

1. Block a token whose trailing component is `.secrets`, or that sits **inside** a folder of
   that name (`~/.secrets/key`).
2. Block a token that sits inside a folder named `.env` (`.env/cloud.env`), keeping the
   existing `.example` / `.template` / `.sample` exemption.
3. Pin each new shape with a block assertion and each near-miss with an allow assertion in
   `hooks/secret-command-guard.test.sh`.
4. Update the `rules/gates.md` Secret-command-guard bullet's path list, and the Known-gaps
   table in `docs/features/secret-command-guard.md` if a shape stays open.

Out of scope: the deny list in `settings.json` (already done, Mark's edit), and any change to
the existing eight patterns.

## Behaviour

```gherkin
Scenario Outline: the new secrets paths are refused in a shell command
  When the agent runs "<command>"
  Then secret-command-guard blocks it (exit 2)
  Examples:
    | command                  |
    | cat ~/.secrets           |
    | cat ~/.secrets/api_key   |
    | cat .env/cloud.env       |

Scenario Outline: unrelated or example paths still pass
  When the agent runs "<command>"
  Then secret-command-guard allows it (exit 0)
  Examples:
    | command                      |
    | cat .secret                  |
    | cat .secretsfoo              |
    | cat my.secrets               |
    | cat .envrc                   |
    | cat .env/cloud.env.example   |
```

## Open questions for Mark

- **Q1 — answered:** the file is `~/.secrets`. Guard that name only; `.secret` stays allowed.
- **Q2 — unanswered, default adopted:** an amendment line on ADR 0039, no new ADR — it widens
  a path list and changes no design. Mark can overrule at review.
  **Answered later on 2026-11-23:** Mark accepted the amendment line.

## Checklist

- [x] 1. Measure current verdicts (table above).
- [x] 2. Red tests first (new block + allow assertions) — run, watch the block rows fail.
  - 2026-11-23, against unmodified code: baseline 212 passed / 0 failed; with 36 new rows
    228 passed / 20 failed. The 20 failures are exactly the 20 rows tagged `user-secrets RED`,
    each `got 0`. The other 16 (exemptions, near-misses, 2 GAP rows) already pass.
  - Ordering trap for task 3: `matches_dotfile` returns `None` on a `.env` template match, so
    `~/.secrets/.env.example` allows unless the `.secrets` pattern is consulted first (pinned).
  - For Mark: "inside a folder named `.env`" also refuses a virtualenv of that name
    (`source .env/bin/activate`), and `.secrets/` / `.env/` with a trailing slash are treated
    as inside. All three are pinned as block rows.
- [x] 3. Add the patterns to `DOTFILE_PATTERNS` — separate step from task 2.
  - 2026-11-23: data-only edit, `matches_dotfile` and the original eight untouched. `.secrets`
    is listed first (ordering trap); the folder pattern reuses the `.env` label so the template
    exemption applies to it.
- [x] 4. Full `hooks/secret-command-guard.test.sh`, read the output, report counts.
  - 2026-11-23: 248 passed / 0 failed, rc 0. 14 deliberate breakages of the new entries and the
    exemption, each run through the suite in a copy: all 14 made it fail.
  - `secret-filename-fold-probe.py` rc 0, but its Table A row for the folder pattern is **vacuous**
    (`flips=no (0/2)`): it builds `.ENV` with no trailing slash, which that pattern cannot match.
    The fold on that pattern rests on the suite rows alone. Probe not edited (out of scope).
  - For task 5, measured via the classifier, not pinned by a test: allowed —
    `bash -c "cat ~/.secrets | head -5"`, `bash -c "cat .env/cloud.env | head -5"`,
    `--file=.env/cloud.env`, `cat < .env/cloud.env`. Blocked as prose — a commit message
    mentioning `~/.secrets/` or `config/.env/`.
- [x] 5. Docs: gates.md path list, Known-gaps table, ADR 0039 amendment line (per Q2).
  - 2026-11-23: ADR 0039 amendment appended (Q2 and the `.env` virtualenv cost confirmed by Mark);
    Known-gaps table gains one row (a suffixed copy, `cat ~/.secrets.bak`). Verdicts quoted in the
    new text were re-run through the classifier by the main session.
  - Left alone: `docs/features/secret-filename-ligature-blindness.md` still says "eight protected
    patterns" (another card's text). README Roadmap line lists example paths, so it is not wrong.
- [ ] 6. Observability judge, then PR (draft) from a worktree under `~/.worktrees/.claude/`.
  - Round 1 (`a44dfe5`, Opus 5.5 xhigh): risk low, confidence high, no fails; concerns on
    regression, traceability, success_masking. Mark approved fixing them on 2026-11-24 and accepted
    the new false refusals (`jq .secrets` and kin). No behaviour change in the fix: 10 test rows,
    comments, docs. Suite 258 passed / 0 failed.
  - Three mutants that round 1 found alive at 248/0 now fail one row each: `.env/` with an unescaped
    dot, `.secrets` with an unescaped dot, the folder entry moved ahead of `.secrets`.
  - The 14 from task 4, so they can be re-run. `.secrets` entry: dropped; moved last; `$` only; `/`
    only; no end anchor; no front anchor; `secrets?`; given the `.env` label. Folder entry: dropped;
    no front anchor; own label; `.env/.` (needs a file name); slash dropped. `ENV_EXEMPT_RE`: `$`
    dropped.
  - Still unpinned: listing the folder entry second (right after `.secrets`) leaves the suite green.
    Reported by the implementer as reachable only through an `Application Support` path inside a
    `.env/` folder ending in a template suffix; not re-measured by the main session.
  - The fold probe now counts `.env` twice in its section 4 total, because two entries share that
    literal (the round 1 judge's finding: it prints 2,699, its per-name rows add up to 2,594).
