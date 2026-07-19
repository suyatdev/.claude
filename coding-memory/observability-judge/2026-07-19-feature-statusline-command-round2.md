# Observability Judge — feature/statusline-command (round 2)

- **repo:** .claude
- **branch:** feature/statusline-command
- **head_sha:** c06737b2572df8081adec74e3eada051032a830c
- **base:** main (merge-base 54b9b265f91c7b259e29f8193c9c589005e3eec5)
- **stage:** implementation
- **ts:** 2026-07-19T18:46:11Z
- **risk:** low — **confidence:** high
- **round 1:** `2026-07-19-feature-statusline-command.md` @ f0902ed (low/medium)

> Filename note: round 1's verdict is committed at `925c310` at the un-suffixed path. This file
> uses the `-round2` suffix already established on `main` by
> `2026-07-19-feature-writing-project-readmes-skill-round2.md`, so the earlier round survives in
> the working tree rather than only in git history.

## What was changed

Since round 1, four things were fixed and the work was re-cut into two commits.

The status line script no longer runs its output through `printf "%b"` (which used to expand
backslash sequences hiding in *data*). Colours are now built with `$'...'` so the escape
characters are baked in at assignment time, and the final print is `printf '%s'`. The branch log
was rewritten to stop claiming work was pushed when it wasn't. The token-count field name — which
round 1 flagged as an unverified guess — was confirmed against the official Claude Code status
line docs. And the model/theme preference changes were pulled out of the feature commit into
their own `chore(settings)` commit at the user's direction.

## Does it do what was asked

Mostly yes, with one real gap.

Three of the four round-1 findings are genuinely, verifiably closed. The fourth — the escape
injection — is **half fixed**, and both the branch log and the code comment describe it as fully
fixed.

The fix stops `printf` from *manufacturing* an escape out of the seven-character text `\x1b`. It
does nothing about an escape that arrives already formed. JSON can carry a real ESC byte directly
(`\u001b`), `jq -r` decodes it into an actual control character, and `printf '%s'` hands it
straight to the terminal. I reproduced the exact original symptom this way:

```
model.display_name = "Opus\u001b[5m4.8"   ->  output contains 9 ESC bytes (baseline: 8)
```

That is a live blink attribute reaching the terminal — the same defect, through a different door.
Also still open through that door: a real newline still splits the status line across two lines
(`workspace.current_dir = "/tmp/aa\nbb"`), a carriage return can overwrite what's already on the
line, and an OSC sequence (`\u001b]0;pwned\u0007`) rewrites the terminal title.

Think of it as fixing a door by removing the machine that builds keys, while the door itself is
still unlocked. Nobody can *make* a key any more, but anyone who already has one walks in.

Severity is genuinely low: the data comes from Claude Code itself, and git refuses control
characters in branch names, so the only realistic hostile route is a directory name inside an
untrusted repo the user happens to `cd` into. Worst case is a garbled status line or a hijacked
terminal title — no code execution, no data loss. The one-line close is stripping control bytes
from each jq-derived value before assembling the line.

## What could go wrong

**The regression tests cannot catch the remaining half.** Branch log test cases 4 and 5 use
*literal backslash* payloads (`\x1b[5m`, `aa\nbb`) — precisely the encoding the `%b` removal
neutralises by construction. They pass, and they can never fail for the real-control-byte case.
This is structurally the same trap round 1 flagged in the schema fixtures: the test contains the
assumption it is supposed to disprove. It got fixed in one place and reappeared in another.

`CODING_MEMORY.md` still says this session "documented, committed and **pushed** it." Nothing is
pushed — there is no remote branch, no upstream, and `gh pr list` is empty. That is the identical
false-completion claim round 1 flagged; it was corrected in the branch log and left standing in
the file that gets read far more often. Same file also says "Verified against 3 stdin shapes"
where the branch log now says five.

Cosmetic-only, and no longer load-bearing now that the schema is confirmed to send an integer: a
non-numeric token value renders `0 tokens` silently, `1e400` renders `infk tokens`, and a huge
float produces a ~300-character status line. No bound on output length.

## What I'd double-check before merging

1. Decide on the control-byte strip. It is one `tr -d '\000-\037\177'` on the jq outputs. If you
   ship without it, change the branch log and the code comment so they stop asserting the issue
   is resolved — a wrong record is worse than a known gap.
2. Fix the two `CODING_MEMORY.md` lines (`pushed` → not pushed; `3 stdin shapes` → 5). It is the
   permanent record and it is currently wrong.
3. Expect a round 3. Committing this verdict moves HEAD, which re-stales judge-guard's strict
   check. Prior branches on `main` show the same two-line pattern, so this is the process
   working as designed, not a new problem.

## Verification I ran myself

The split is clean — I checked it rather than trusting the report. `git diff f0902ed..HEAD` shows
**no `settings.json` delta at all**, so the `reset --soft` rewrite preserved that file byte for
byte; the only deltas are the four intended ones (script fix, branch log, memory correction,
verdict files). The two commits partition the settings changes correctly and each is coherent
standalone: `925c310` has only the `statusLine` block and still carries the *old* model value,
`c06737b` has only model + theme. `settings.json` parses, and has exactly the three intended
changes vs `main`. Nothing was pushed, so the history rewrite was safe and `f0902ed` remains in
the reflog. Script committed mode 100755, `bash -n` clean, no `eval`/backticks, only remaining
`printf` is the safe `%s` and awk's literal format string.

Escape probing (12 payloads, python-generated JSON): literal `\x1b[5m` and `aa\nbb` now render as
inert text — **the round-1 defect is genuinely closed for that encoding**. Real control bytes via
`\u001b` / `\u000a` / `\r` / OSC still pass through, as described above. Baseline render is
unregressed (8 ESC bytes, correct output, exit 0, empty stderr). awk's `-v` cannot leak data into
output — the value is only ever consumed by a literal `%d`/`%.1fk` format.

Schema claim spot-checked as plausible and now sourced: the branch log cites
`https://code.claude.com/docs/en/statusline` and names sibling fields
(`used_percentage`, `cost.total_cost_usd`, `workspace.git_worktree`) consistent with a real
schema read rather than a restated guess. This is what moved my confidence from medium to high.

No test suite exists for this repo's shell scripts and none was added — user's explicit decision,
reasoning recorded in the branch log.

## Dimensions

| Dimension | Verdict | Note |
|---|---|---|
| intent | pass | All four round-1 findings acted on; split was user-directed; schema verified against official docs rather than fixtures. |
| execution | concern | Works; baseline unregressed; but the escape remediation is materially incomplete — real control bytes via JSON `\u001b` still reach the terminal, reproducing the original symptom. Documented as fixed. |
| trajectory | pass | Reproduced the defect with a live ESC byte before fixing, caught that their own first repro was invalid JSON and redid it, dispatched an agent to verify schema against source, put the commit split to the user. Remaining gap is a knowledge gap (JSON can encode control bytes), not a reasoning failure. Upgraded from round 1. |
| regression | pass | `settings.json` byte-identical across the split; both commits coherent standalone; JSON valid; three original scenarios re-run and unregressed; model default now user-confirmed. Upgraded from round 1. |
| context_budget | pass | No always-on rule or prompt growth. Branch log grew ~57 lines but is on-demand; CODING_MEMORY +7 net. |
| traceability | concern | Branch log is now genuinely strong — defect, fix, schema source URL, and deliberate non-actions all explained. Undercut by `CODING_MEMORY.md` still asserting "pushed" (false) and "3 stdin shapes" (stale), and by the escape fix being described as complete. |
| success_masking | concern | Regression cases 4/5 use literal-backslash payloads that the fix neutralises by construction — they cannot fail for the live path. Same fixture-bakes-in-the-assumption trap as round 1, recurring in a new place. jq parse errors still exit 0; non-numeric tokens render `0` silently. |
| intent_drift | pass | Round 1's main drift finding fully resolved: user consulted, preferences split into `chore(settings)`, precedent matched, decision recorded. `chrome/` drive-by still correctly declined. No new deps. Upgraded from round 1. |
| checkpoint | pass | Two coherent commits, granular revert (preferences can be dropped without losing the feature), nothing pushed so the `reset --soft` was safe, `f0902ed` retained in reflog. Better than round 1. |
| audit_trail | concern | Attributable; no-ADR call still correct. But round 1's verdict sits at the exact path this run was specified to write — one `Write` from being clobbered; avoided via the repo's `-round2` precedent. Plus the inaccurate memory record enters the permanent trail. |

## Concerns

- Escape fix is incomplete: JSON-encoded real control bytes (`\u001b`, `\u000a`, `\r`, OSC) pass through `printf '%s'` untouched — reproduced the original blink-SGR symptom via `display_name`
- Code comment and branch log both assert the escape issue is fully resolved when half the path remains open
- Regression tests 4/5 use literal-backslash payloads that the fix neutralises by construction, so they cannot falsify the remaining case — same fixture trap as round 1
- `CODING_MEMORY.md` still claims the work was "pushed"; no remote branch, no upstream, no PR exists
- `CODING_MEMORY.md` says "Verified against 3 stdin shapes"; branch log now says five
- Round 1's verdict markdown occupies the default output path for this branch/date — collision trap for any future same-day re-run
- No automated test harness despite `judge-guard.test.sh` / `memsearch-nudge.test.sh` precedent (explicit user decision, reasoning recorded)
- Cosmetic: non-numeric token value renders `0 tokens` silently; `1e400` renders `infk`; no bound on rendered line length
- `✗` dirty marker still permanently lit in this repo because `chrome/` stays untracked (flagged to user, undecided)
- Committing this verdict will move HEAD and re-stale judge-guard, forcing a round 3 before `gh pr create`
