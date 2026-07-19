# Branch: feature/statusline-command

Started 2026-07-19. No brainstorm doc — the user had already written the config and asked for
it to be documented and pushed, so this branch reconciles existing working-tree state rather
than designing something new.

## What this branch delivers

A Claude Code status line that reproduces the oh-my-zsh `robbyrussell` prompt the user is used
to seeing in their terminal, extended with two Claude-specific segments.

- `statusline-command.sh` — reads the status line JSON on stdin and prints
  `➜  <user>@<host> <dir> git:(<branch>) ✗  │ <model> │ <used> tokens`.
  - The `✗` dirty marker only renders when the working tree has uncommitted changes, matching
    robbyrussell's `ZSH_THEME_GIT_PROMPT_CLEAN` behaviour.
  - Git calls use `--no-optional-locks` so the status line can't contend with concurrent git
    operations (parallel agents in worktrees).
  - The model and token segments — and their `│` separators — are omitted individually when
    their JSON field is absent or null, which is the normal state before a session's first API
    response.
  - Token count is formatted by `awk`, not bash arithmetic, so a non-integer
    `total_input_tokens` can't crash the script.
- `settings.json` — registers the script via a `statusLine` command entry. Two unrelated
  preference changes made in the same sitting (default model `claude-fable-5[1m]` → `opus[1m]`,
  and `"theme": "dark"`) were split into their own `chore(settings):` commit at the user's
  direction, matching the existing precedent of keeping preference churn separate from feature
  work. User confirmed `opus[1m]` is the intended committed default.
- `README.md` — new row in the "What's in here" table. The README has no Roadmap section, so
  there was nothing to update there.

## Why the script rather than a PS1 port

The user has no `PS1` in their shell config — the robbyrussell look comes from the oh-my-zsh
theme itself, so there was no prompt string to translate. The script reconstructs the theme's
output from the fields Claude Code supplies on stdin.

## Test evidence

Manually exercised against five stdin shapes, all exit 0:

1. Full payload (git repo + model + tokens) → full line, `113.3k tokens`, `✗` present because
   the tree was dirty.
2. Payload with no `model` / `context_window` (start of session) → git prompt only, no trailing
   `│` separators left dangling.
3. Non-git dir (`/tmp`) with a low token count → no `git:(...)` segment, tokens rendered raw
   (`42 tokens`) rather than in `k` form.
4. `display_name` containing a literal `\x1b[5m` → renders as inert text.
5. Directory named `aa\nbb` (literal backslash-n) → stays on one line.

These five were the initial manual pass. They are now superseded by the committed
`statusline-command.test.sh` (20 assertions), which additionally covers the *real*-byte
encoding that cases 4-5 structurally cannot reach — see the harness section below.

The observability judge additionally ran the script against detached HEAD, a fresh repo with no
commits, and paths containing spaces: short-SHA fallback, `git:(main)`, and intact paths
respectively. It measured ~52ms per render with `git status --porcelain` staying fast even
against a large untracked tree (git collapses untracked directories).

## Escape-injection fix (found by the observability judge, over two rounds)

Terminal-escape injection through the status line, which arrives by **two independent routes**.
Round 1 closed only the first, and the log at that point wrongly called the issue resolved —
round 2 caught the overclaim.

**Route 1 — the script manufacturing escapes.** It originally ended in `printf "%b" "$out"`,
colours defined as ordinary strings containing `\033[...]`. `%b` expands backslash escapes across
the whole string, data included, so a field holding the literal seven-character text `\x1b`
became a real escape. Fixed by building colours and the `➜` glyph with `$'...'` ANSI-C quoting
(real ESC bytes embedded at assignment time) and rendering with `printf '%s'`.

**Route 2 — real control bytes passing straight through.** JSON can carry an actual control byte
via a unicode escape; `jq -r` decodes it to a real byte and `printf '%s'` forwards it untouched.
Route 1's fix does nothing about this. Demonstrated: a blink attribute, a newline splitting the
status line in two, and an OSC sequence rewriting the terminal title. Fixed by stripping C0
controls and DEL with `${v//[[:cntrl:]]/}` — pure bash, so it costs an inline expansion rather
than a fork in a script that re-renders constantly.

**Route 2b — the `$PWD` fallback, missed on the first attempt at route 2.** The strip was applied
to the jq result, but `[ -z "$cwd" ] && cwd="$PWD"` ran *after* it, so the fallback value went
out unstripped. `$PWD` is every bit as external as the JSON — it is the name of whatever
directory the shell happens to be in — and the fallback is reached by four routine stdin shapes
(`{}`, malformed JSON, `{"cwd":null}`, `{"workspace":{}}`), not just exotic ones. Fixed by
applying the fallback before the strip. This is the same class of miss as route 2 itself: the
write-up claimed "every externally-sourced value" while one path bypassed it.

Why round 1's tests could not have caught route 2: they used *literal-backslash* payloads, the
exact encoding that removing `%b` neutralises by construction. They passed and could never fail
for the real-byte case — the same trap as the round-1 schema fixtures, where the test contained
the assumption it existed to disprove. The suite now asserts against the script's own 8-escape
colour baseline, so any injected escape shows as a surplus, regardless of encoding.

Residual risk is low: the data comes from Claude Code, and git rejects control characters in ref
names (branch values are stripped anyway, so that doesn't need trusting). The realistic hostile
route is a directory name inside an untrusted repo. Worst case was a garbled bar or a hijacked
terminal title — no execution, no data loss.

Aside worth keeping: while writing this up, a literal ESC byte ended up embedded in the script's
own comment block, and the judge did the same in its verdict file. The failure mode is easy to
reproduce by accident, which is part of why stripping beats escaping here.

## Schema verification

`.context_window.total_input_tokens` was an unverified guess when the script was written — if the
key were wrong the segment would have silently never rendered, and hand-written test fixtures
could not have caught it (they contain the same guess). Checked against the official
[status line docs](https://code.claude.com/docs/en/statusline): the path is correct, and
`total_input_tokens` is current context occupancy from the latest API response, not a cumulative
total. Also available if wanted later: `context_window.used_percentage` / `remaining_percentage`,
`cost.total_cost_usd`, `session_id`, `workspace.git_worktree`, `rate_limits.*.used_percentage`.

## Not done deliberately

- **No ADR.** A status line is presentation-only — it isn't a structural/architectural
  decision, doesn't touch business logic, and doesn't pivot a feature's direction, so it
  misses all three ADR triggers in `managing-session-memory`.
- **No hook, no skill.** Nothing here is a rule or a recurring procedure.
- **`chrome/` left untracked.** Claude Code's auto-generated Chrome native-messaging wrapper —
  machine-local tooling, not repo work. Worth noting that it keeps the tree permanently dirty,
  so the new `✗` marker will always show in this repo until it's either committed or
  gitignored. Flagged to the user; not decided here.

## Test harness — declined, then reinstated

The user initially declined a `statusline-command.test.sh`, reasoning that a status line is
presentation-only, fails visibly, and that the one unfalsifiable assumption (the
`context_window` schema) was now confirmed against the docs. Sound on the information then
available — but round 2 undercut it: an injected escape does **not** fail visibly (a stripped one
is invisible, a successful one reads as a rendering quirk), and the defect regressed *within the
session*, fixed by one route while still open by another. Put back to the user with that new
information; they opted to commit it.

`statusline-command.test.sh` — 20 assertions in the style of `hooks/memsearch-nudge.test.sh`,
split into a rendering group and a control-byte injection group.

**Validated by falsification, not just by passing.** A test that cannot fail proves nothing, so
the current suite is run against every historical state of the script:

| Script version | Result | Reads as |
|---|---|---|
| `f0902ed` (original, `printf %b`) | 9/20 | both injection routes open, plus `$PWD` |
| `925c310` (route-1 fix only) | 10/20 | route 1 closed, route 2 and `$PWD` open |
| `29d6131` (route-2 fix) | 15/20 | both routes closed, `$PWD` fallback still open |
| `4d63b09` (`$PWD` ordering) | 20/20 | no leak; empty-cwd flaw cosmetic only |
| `e882659` (regression) | 19/20 | second unstripped fallback below the strip |
| current | 20/20 | closed |

The two oldest versions score *above* `29d6131` on the 20th assertion, and correctly so: with no
stripping at all, `cwd` never empties, so the fallthrough that assertion targets is never reached.

Known untested: unstripping `user` or `host` still scores 20/20, so those two strips have no
coverage. Reaching them requires control of `PATH` or the hostname, which is already game over —
recorded rather than fixed.

Each row fails exactly the assertions covering the defect it still carries, and every injection
assertion fails against at least one version — so none of them pass vacuously.

Three weaknesses the falsification runs exposed in the tests themselves, all fixed: the
carriage-return assertion passed against unfixed scripts because it counted ESC/NL/BEL but not
CR; the git-segment assertion silently depended on the script living inside a repo, so it now
builds a throwaway repo via `mktemp -d`; and `render()` swallowed stderr, which would have hidden
a jq parse error and let a rejected payload's assertion pass vacuously.

`statusline-command.falsify.py` — the falsification runner itself, committed rather than left in
a scratchpad, since round 4 pointed out that the most valuable artifact of the exercise was being
cited in docs while being unreproducible. It asserts the expected pass count per version, so a
future change that makes an assertion unfalsifiable fails the run.

### Two round-4 leftovers, both closed

- `user` and `host` (from `whoami`/`hostname -s`) were the only unstripped values, while the
  script comment claimed *every* value was stripped. Exploiting them needs control of the
  hostname or `PATH`, which is already game over — but they are stripped now, so the comment is
  true without a carve-out.
- A `cwd` consisting entirely of control bytes strips to empty, and `git -C ""` silently resolves
  to the process's own directory, so the git segment could name a different repo than the payload
  asked for.

  **This was written up as "Cosmetic, no leak" — and the fix for it introduced a real leak.**
  Adding a second `[ -z "$cwd" ] && cwd="$PWD"` *below* the strip recreated, five lines down, the
  exact defect round 3 had found at the first fallback: an unstripped `$PWD` reaching the
  terminal. Round 5 caught it and confirmed the parent commit `4d63b09` had been clean on that
  input. The false "Cosmetic, no leak" phrasing also survives in `e882659`'s commit message,
  which is already pushed and not being rewritten — this entry is the correction of record.

  Fixed properly by stripping each source *at its source* and then falling back, so no later
  assignment can reintroduce a raw value:

  ```bash
  cwd=$(echo "$input" | jq -r '...')
  cwd="${cwd//[[:cntrl:]]/}"
  [ -z "$cwd" ] && cwd="${PWD//[[:cntrl:]]/}"
  ```

  `$PWD` is always absolute, so it always keeps its slashes and can never strip to empty — that
  is what guarantees `$cwd` is non-empty and keeps `git -C "$cwd"` from silently resolving to the
  process directory.

### Extraction gotcha worth remembering

Running the falsification from the Bash tool gave a bogus *identical* result for all three
versions. Cause: the rtk proxy rewrites git commands there, and both `git show <sha>:<path>` and
`git cat-file -p <sha>:<path>` returned the **commit object** rather than the file blob — so
every version was being "tested" against the same non-script text. `rtk proxy` did not bypass it.
The check that should have caught this did not: grepping the extracted text for `cntrl` matched
the *commit message*, not the code. `statusline-command.falsify.py` now shells out to git from
Python, which the hook does not rewrite, and asserts each blob starts with `#!` before trusting
it. Its expected counts are derived from what each version *does*, with the reasoning recorded
inline — fitting them to observed output would make the harness certify whatever it saw.

## Checkpoint

Six commits on the branch:

1. `925c310 feat(statusline)` — script + `statusLine` wiring + docs.
2. `c06737b chore(settings)` — model + theme preferences, split out at the user's direction.
3. `29d6131 fix(statusline)` — route-2 control-byte stripping + the test harness.
4. `4d63b09 fix(statusline)` — the `$PWD` fallback ordering, plus four regression assertions.
5. `e882659 fix(statusline)` — `user`/`host` stripping, falsify harness committed, and the
   empty-cwd "fix" that **introduced the round-5 regression**.
6. `fix(statusline)` — strip at source; undoes 5's regression, adds the 20th assertion.

Observability judge ran five rounds, each finding something real in the round before it:

| Round | Head | Verdict | Found |
|---|---|---|---|
| 1 | `f0902ed` | risk=low conf=medium | escape injection (route 1), false "pushed" claims, unverified schema |
| 2 | `c06737b` | risk=low conf=high | route 1 fixed but route 2 open while docs claimed complete |
| 3 | `29d6131` | risk=low conf=high | route 2 fixed but `$PWD` fallback open, again while docs claimed complete |
| 4 | `4d63b09` | risk=low conf=high | code correct at last; stale counts, `user`/`host` over-claim, uncommitted falsify harness |
| 5 | `e882659` | **risk=medium conf=high** | the round-4 fix **regressed** a path its parent had closed; 11 doc mismatches incl. a false "no leak" claim |

The recurring pattern, worth carrying forward: **the write-up ran ahead of the code in every
round** — rounds 1-3 each asserted a class of defect was closed while one path still bypassed the
fix; round 4's code was right but its counts described an earlier state; round 5 found a *new*
leak introduced by the fix meant to be the last, described in the record as "Cosmetic, no leak".
The judge caught it every time; self-review did not. Worth noting too that the judge was right on
a finding I twice failed to reproduce and nearly dismissed — the `$PWD` leak — because both of my repro
attempts had their control bytes silently stripped before reaching disk.

### Scope, stated plainly

The user asked to "document and push" a status line they had already written. Five of six commits
are judge-driven, and the branch carries ~280 lines of test and harness against a 113-line
deliverable. Rounds 1-2 found a genuine defect that would otherwise have shipped and were clearly
worth it. Rounds 3-5 chased progressively narrower variants — round 3 needed a hostile directory
plus routine stdin, round 4's needed `PATH` control ("already game over" in the judge's own
words), round 5's needs a payload Claude Code cannot send — and round 5's ratchet made the code
*worse* than its parent. That is the argument for stopping, and it was taken to the user rather
than resolved unilaterally.

A sixth judge round is required before `gh pr create`: judge-guard enforces strict freshness, and
the round-5 verdict is `risk=medium` with two failing dimensions against a HEAD that has since
changed.
