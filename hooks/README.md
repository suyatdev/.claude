# Hooks

**Four of these hooks are NOT installed.** `checkpoint-before-modify.sh`, `require-project-standards.sh`, `scan-invisible-unicode.sh` and `scan-secrets.sh` exist and pass their suites, and are registered nowhere — they never run. The two scanners in particular are advertised protection that is not currently protecting anything. Nothing inert here starts running until you deliberately wire it up by pasting one of the JSON blocks below into a `settings.json`.

**Everything else here is registered in this repo's own `settings.json` today** — the list below is derived from that file, not recalled: `git-guard.sh`, `doc-guard.sh`, `judge-guard.sh`, `merge-guard.sh`, `feature-sync-guard.sh`, `test-marker-guard.sh`, `phase-guard.sh` and `pane-dispatch-guard.sh` on `PreToolUse`; `verify-hook-wiring.sh`, `doc-guard.sh`, `memsearch-nudge.sh` and `handoff/slim-session-start.sh` on `SessionStart`; `context-handoff-watch.sh` on `PostToolUse`; and the remaining `handoff/` scripts on `PreCompact`, `UserPromptSubmit` and `PostToolUse`. See the `git-guard.sh` and `judge-guard.sh` sections below for why those two are global. `verify-hook-wiring.sh` is the one that speaks up when that list stops matching reality.

---

## Why these are hooks and not rules

Tasks 1–16 of this integration produced rules and skills. Every one of them is an *instruction*, and the standards are blunt about what an instruction is worth as a boundary:

> "Never rely solely on system-prompt instructions as a safety boundary." — Day 5
> "Write software, not rules." — Day 3
> "Hooks are the place for rules the agent should never forget but often does." — Day 1

An instruction is a suggestion with good intentions. It degrades under exactly the conditions where it matters most: a long session, a compacted context, a confident model, a user in a hurry saying "just get it working." A hook is code. It runs every time, it cannot be argued with, and it does not get tired.

Each hook below exists because the corresponding instruction has a specific, known failure mode that an instruction cannot fix.

---

## The hooks

### The two scanners read the payload, not the file on disk

`scan-secrets.sh` and `scan-invisible-unicode.sh` each run in one of two modes, and the distinction is load-bearing:

| Mode | Invocation | What it scans |
|---|---|---|
| **Hook** | no args, PreToolUse JSON on stdin | the content **about to be written** — `tool_input.content` (Write), `tool_input.new_string` (Edit), `tool_input.edits[].new_string` (MultiEdit) |
| **CLI** | `script.sh <file> [file...]` | those files **on disk** — for pre-commit and manual sweeps |

**This was a real defect, caught in final review, and it is worth stating plainly.** The first version of both scripts pulled `file_path` out of the payload and scanned *that path on disk*. But `PreToolUse` fires **before** the write lands, so the path is either a file that does not exist yet (Write) or a file that still holds the **pre-edit** text (Edit). A Write of a brand-new file containing `AKIAIOSFODNN7EXAMPLE` exited **0 — allowed**, because `[ -f "$target" ]` was false. An Edit injecting a secret into a clean file exited **0 — allowed**, because the scanner read the clean version. Both scanners enforced nothing.

They passed their tests anyway, because the tests invoked them as `script.sh <file>` — the CLI path, which was never the path in production. **Test the code path that will actually run.** A fixture that exercises a convenient path merely resembling the real one manufactures a passing result and no safety.

A real JSON parser (`python3`) does the extraction, and this is not incidental: a zero-width codepoint arrives in the payload as a six-character `\u200b` escape — plain ASCII on the wire. A `sed`- or byte-level extractor sees six harmless characters and reports the content clean, which is precisely the attack the Unicode scanner exists to stop. Only a JSON decode turns the escape back into the bytes worth scanning. Reported byte offsets are offsets **into the payload string**.

### `scan-secrets.sh`

Scans for AWS access key IDs, private key headers, generic `api_key` assignments, bearer tokens, and password assignments. Reports file, line number, and the **name** of the pattern that fired.

It deliberately does **not** print the matched text. Echoing a secret into stderr, a transcript, or a CI log is the leak we are trying to prevent; the whole point is to stop the value from propagating.

*Why an instruction cannot do this job:* "Never commit secrets" is the single most universally agreed-upon rule in software, and it is violated constantly — GitHub revokes tens of thousands of leaked keys a year, all of them written by people who knew the rule. Knowing the rule has never been the bottleneck. Noticing, in the moment, that this particular string is a live credential is the bottleneck, and that is a mechanical check.

### `scan-invisible-unicode.sh`

Scans for zero-width and bidirectional-control codepoints: U+200B/C/D, U+2060, U+FEFF appearing mid-file, the U+202A–U+202E bidi overrides, and the U+2066–U+2069 bidi isolates. Reports file, byte offset, and codepoint name. A BOM at byte 0 is legitimate and is not flagged.

*Why an instruction cannot do this job:* **this is the case where human review structurally cannot help.** These codepoints have no glyph. A hidden instruction embedded in a source file renders as nothing in a diff, nothing in a PR review, and nothing in an editor at default settings. A reviewer reading carefully and in good faith sees clean code and approves it — that is not a lapse in diligence, it is the attack working as designed.

The blast radius is what makes it urgent. The payload is not just *read* by an agent, it is *copied* by one. Once an agent treats a poisoned file as a pattern to imitate, it replicates the invisible bytes into everything it touches, and every copy is exactly as invisible as the original. One poisoned fixture becomes hundreds of poisoned files in minutes, all of them already in git history by the time anyone notices from behavior. You cannot ask a human to be the control for bytes a human cannot see.

### `checkpoint-before-modify.sh`

Verifies a rollback point exists before a **destructive** command: the directory is a git repo, it has at least one commit, and the working tree is clean. If not, it names on stderr exactly what is at risk (staged, unstaged, and untracked) and exits non-zero.

*Why an instruction cannot do this job:* the agent about to make a sweeping change is precisely the agent least likely to pause and ask whether the work it is about to overwrite is recoverable. "Commit before a big refactor" is a rule everyone endorses and nobody remembers under momentum, and the cost is asymmetric — overwritten uncommitted work is simply gone, and no apology at the end restores it.

**The command allowlist — and why it had to exist.** The first version gated *every* Bash call on a clean tree. Wired to `PreToolUse` on `Bash`, that **strands the agent**: the moment the tree is dirty, `git add`, `git commit`, and `git stash` are blocked too — and those are the only actions that would satisfy the hook. It printed "commit or stash these" while blocking the commit and the stash. There was no recovering move; the user had to leave the session and open their own terminal. **A guard whose own remedy it blocks is not a guard, it is a trap.**

The hook now reads `tool_input.command` from the payload and decides per command, in this order:

1. **Recovery and read-only — always allowed, dirty tree or not.** `git add`, `commit`, `stash`, `status`, `diff`, `log`, `show`, `fetch`, `remote`, `config`, `rev-parse`, `ls-files`, `blame`; plus `ls`, `pwd`, `cat`, `head`, `tail`, `wc`, `echo`, `printf`, `grep`, `rg`, `which`, `stat`, `file`, `env`, `date`. Checked **first**, so no later pattern can shadow it — `git commit -m "stop using rm -rf"` must not be blocked by its own commit message.
2. **Destructive — requires a clean checkpoint.** `rm -r`/`-f`, `git reset --hard`, `git clean`, `git restore`, `git checkout -f`/`-- .`, `git rebase`/`merge`/`cherry-pick`/`revert`/`filter-branch`, `git push --force`, `git branch -D`, `sed -i`, `shred`, `truncate`, `dd of=`, `find|xargs … -delete`/`-exec rm`.
3. **Everything else — allowed.** Running the test suite on a dirty tree is normal work; blocking it buys nothing and costs the session.

It is a **rollback guard, not a security boundary**: it matches the leading command, so `git commit -m x && rm -rf /` gets through. Anything that must not be bypassable belongs in the permission system, not here.

Invoked with no payload (`checkpoint-before-modify.sh <repo-dir>`) it checks the tree unconditionally — the original CLI behavior, useful in a pre-commit hook.

### `git-guard.sh`

Two deterministic guards, both matched on `tool_input.command`:

1. **Default-branch commit guard.** Blocks `git commit` while `main`/`master` is checked out, unless every staged file is a **markdown file under `docs/`** (`docs/*.md`, by file type — a script under `docs/` gets no free ride) — the brainstorm-then-branch exception in `preparing-pull-requests`. Until ADR 0031 the allowlist also carried `CODING_MEMORY.md` and `coding-memory/*`; that tree is retired and untracked, so those entries were removed.
2. **Force-push guard.** Blocks a bare `git push --force`/`-f` on any branch. `--force-with-lease` is allowed, except while `main`/`master` is checked out, where it is blocked too.

It also unwraps an `rtk ` prefix before matching: the RTK hook is registered ahead of this one on the same `Bash` matcher and rewrites plain git commands, so by the time this guard runs the command it sees may already read `rtk git commit -m x`.

*Why an instruction cannot do this job:* "never commit to main" and "never force-push" are two of the most-repeated rules in `rules/gates.md`, and both fail the same way — under momentum, mid-session, with a confident model that has just finished a brainstorm and wants to save the result. The brainstorm-then-branch exception makes the naive version of this guard wrong (a flat "no commits on main" would also block the one commit the workflow requires), so the allowlist has to be as precise as the rule it enforces: `docs/*.md`, nothing else. (It was `CODING_MEMORY.md` and `coding-memory/*` until ADR 0031 retired that tree. The principle is the point, not the specific paths — when the workflow's one legal commit changes, this allowlist changes with it, or the guard starts enforcing a rule nobody follows.)

Unlike the other four hooks in this file, `git-guard.sh` **is installed** — it runs in this repo's own `settings.json` today, alongside `doc-guard.sh` and `judge-guard.sh` (see below), because this repo is the global config every other repo inherits, and the two guards it enforces (`rules/gates.md`) apply here first.

### `judge-guard.sh`

A `PreToolUse` guard matched on `tool_input.command`: it blocks `gh pr create` unless a **fresh** implementation-stage `observability-judge` verdict exists for the exact repo, branch, and full `head_sha` currently checked out. Freshness is strict — any commit added after the verdict was written moves `HEAD` and invalidates it, forcing a re-run before the PR can go out.

Like the checkpoint and git guards above, it classifies the command with `python3`'s `shlex` rather than a flat bash regex — shell quoting (an `rtk` wrapper, a quoted-space env-assignment) defeats a naive pattern match, and a gate that a quoting trick defeats is worse than no gate. Escape hatch: a leading `JUDGE_EXEMPT=<reason> gh pr create ...` lets a genuinely exempt PR through and logs the reason to stderr — see `running-the-observability-judge` for when that's appropriate.

*Why an instruction cannot do this job:* "run the judge before opening a PR" is exactly the step momentum skips — the diff is done, tests pass, and the temptation is to just ship. A hook is the only thing that reliably notices the verdict is missing or stale before the PR exists to review.

Unlike `doc-guard.sh` (a momentum guardrail that fails open when it can't verify), `judge-guard.sh` **fails closed**: if `python3` is missing, the repo/branch/HEAD can't be determined, or the verdict store can't be read, it blocks rather than allows — this is a shipping gate, not a momentum guardrail, so an unverifiable state must not default to "let it through."

`judge-guard.sh` **is installed** too, alongside `git-guard.sh` and `doc-guard.sh`, appended to this repo's own `settings.json`.

### `require-project-standards.sh`

**The enforcement half of the `setting-up-a-new-project` skill.** Given a target file path, it blocks the write if the path is project source code, the path is inside a git repo, and `.claude/project-standards.md` does not exist.

It does **not** block:
- writes under `.claude/` — otherwise the register could never be created in the first place
- docs, markdown, and plain text — writing a README before setup is harmless
- anything outside a git repo — scratch files are not a project

*Why an instruction cannot do this job:* the skill already defines this as a "blocking gate," but a gate made of words is a gate that opens when pushed. A session can be talked out of it ("let's just get something working first"), or can simply forget it after a context compaction, and the gate then quietly does not happen — silently, with no error, which is the worst way for a control to fail. The project then accretes code with no agreed standards, which is the exact outcome the skill exists to prevent.

**The skill asks the questions; the hook makes sure they actually get asked.**

### `pane-dispatch-guard.sh`

PreToolUse, matcher `Task|Agent`. Denies in-process dispatch of subagent types
listed in `panes/redirect-agents.conf` (the two judges) when
`panes/terminal-detect.sh` finds a supported terminal, redirecting the model to
`panes/dispatch-pane-agent.sh`. Fails open on parse errors, missing conf, no
terminal, `CLAUDE_PANE_AGENT=1`, or a per-session `adapter-failed-*` cooldown
flag — every fallback is today's in-process behavior. Momentum redirect, not a
security boundary.

### `context-handoff-watch.sh`

PostToolUse, matcher `*`. Once per session, when the transcript's last assistant
usage entry sums to ≥75k tokens, it writes a fired-flag, prepares a press-Enter
handoff pane (`dispatch-pane-agent.sh handoff`), and nudges the freshness
checkpoint via `additionalContext`. The fired-flag check precedes any transcript
parsing, so after firing the per-call cost is one stat. Never blocks.

### `test-marker-guard.sh`

PreToolUse, matcher `Bash`. Blocks a `git commit` that stages a file with a sibling test (the
`X.sh`↔`X.test.sh` / `X.py`↔`X.test.py` convention) at a version that test suite has never passed
against. The marker under `hooks/state/test-markers/` is a **receipt, not a grade** (ADR 0027): it
proves the suite ran against those exact bytes, never that the suite is any good. A thin bash
wrapper around one `python3` decision call in `lib/decide-commit-gate.py` (ADR 0026) — exit 2 with a
named `MSG_*` reason on stderr, silent exit 0 otherwise. Escape hatch: `TEST_EXEMPT='<reason>' git
commit ...`, 1–200 printable ASCII bytes, validated and logged to `hooks/state/test-marker.log`,
never silently discarded.

**Registered globally, but INERT until a repo opts in.** It sits on the same `Bash` matcher as
`git-guard.sh`, `doc-guard.sh`, `judge-guard.sh` and `merge-guard.sh`, so it runs for every repo on
this machine — and does nothing unless `<toplevel>/hooks/lib/write-test-marker.py` exists and is
readable. That file is the opt-in signal, deliberately a file rather than a config key: a repo with
no writer cannot be held to a receipt it has no way to issue.

**Inertness has exactly one exception: `MSG_NO_PYTHON`.** A missing or unusable `python3` fires
before the payload can be read at all, so before any repo can be identified — that one door blocks a
non-adopting repo too. It is not a new hazard: `git-guard.sh`, `judge-guard.sh` and `merge-guard.sh`
are globally registered today and all `exit 2` when the interpreter is gone. Every other door is
downstream of the opt-in check and cannot reach a repo that has not opted in.

**v1 ships no way to ask whether the gate is armed here — an accepted cost, not a stale entry.** A
hook that allows is silent, so nothing in a normal commit distinguishes "allowed, verified" from
"allowed, inert"; a `--status` subcommand was considered and remains deferred. What v1 has instead
is two partial answers: a one-off arming proof run at install time, and the decision log, whose
evidence is asymmetric — *a non-empty log proves the gate was armed and firing **as of its last
entry**; an empty one proves nothing*, since "armed and nothing has gone wrong" and "armed but
silently never pairing" look identical. Neither is a live arming check, so a gate that goes inert
*later*, in a repo where nothing has tripped it, stays invisible until someone re-runs the arming
proof by hand.

*Why an instruction cannot do this job:* "run the tests before you commit" is a rule nobody
disputes and everybody skips at exactly the moment it matters — the change is small, the suite is
slow, the session is long. The failure is not ignorance of the rule but the absence of any record of
whether it happened, and a memory of having run the tests is not evidence about the bytes now
staged. Only a mechanical check can compare the two.

### `verify-hook-wiring.sh`

SessionStart, registered first in the group. Answers one question and prints nothing when the
answer is fine: **can the guards this machine registers actually run, and does the live wiring
still match the version that was reviewed?**

Two checks, both cheap:

1. **Every registered hook command resolves to an executable file.** For each
   `hooks.<event>[].hooks[].command`, extract the script it invokes, expand `$HOME`/`~`, and require
   `os.path.exists` plus `os.access(X_OK)`. One line per failure, naming the event, the path, and
   which of the two it is — a missing file and a mode-644 file are different repairs.
2. **The live `~/.claude/settings.json` has not drifted from `HEAD:settings.json`** — parsed and
   compared semantically, so reindenting or reordering keys is not drift. Only the **wiring keys**
   are compared: `hooks`, `permissions`, `statusLine`, `enabledPlugins`. A guard that is in HEAD but
   not live (or the reverse) is named by script. Every other wiring key is descended **one level**
   and named by sub-key, with both values:

   ```
   verify-hook-wiring: settings.json drift — permissions.defaultMode: live "bypassPermissions", HEAD "default"
   ```

   That shape is the point of the check, not a nicety. The drift that motivated this whole feature
   was `permissions.defaultMode` moving unannounced, and a reader told only that *"permissions"
   differs* still has to go and diff the file by hand — which is the work the check exists to have
   already done. Values are truncated at 60 characters, because knowing a long value moved beats
   silence. One level only: deeper nesting costs line length and buys little. If a key stops being
   an object, or is absent from one side entirely, there is no sub-key to name and the key-level
   line remains.

   **A value is printed only if it is provably safe to print — default-deny.** The sub-key is named
   either way; knowing *that* a setting moved is the finding, and the value is a convenience that
   gets dropped whenever it cannot be shown safely. Printed: `null`, booleans, numbers, and a string
   matching `^[A-Za-z][A-Za-z0-9 ._-]{0,59}$` that contains no 20+ character letters-and-digits run.
   Everything else prints `<changed>`, and anything whose sub-key name or text matches
   `key|token|secret|password|credential|auth|bearer` prints `<redacted>`. Lists and objects are
   structures, not legible one-line values, and are never rendered. **Nothing is ever truncated** —
   printing a prefix leaks a credential as thoroughly as printing all of it, and a severed string
   tells the reader nothing.

   Default-deny is the second design, and the first one's failure is why. Enumerating what a
   credential *looks like* leaked twice: first a truncated JWT prefix, then standard base64, whose
   `+` and `/` split a deny-list run test into innocent-looking pieces. Enumerating what a
   *readable setting* looks like is a bounded problem; enumerating credentials is not.

   `hooks/verify-hook-wiring.leakcheck.py` measures this — seven credential families, 2000 samples
   each, fixed seed. **0 / 14000 today; 995 against the pre-fix renderer.** Re-run it rather than
   trusting this paragraph.

   **What still gets through:** a short, lowercase-only secret with no digits and no telltale word —
   `abcdefghijklmnopqrst` under an innocuous key — matches the safe-value shape and prints. That is
   not what credentials look like, but it is not zero. This is a diagnostic line, not a secret
   scanner; `hooks/scan-secrets.sh` is that tool, and is currently dormant (see the top of this
   file).

**`model` and `effortLevel` are excluded by design, and that exclusion is load-bearing.** ADR 0032
accepted that `/model` rewrites them in place, so comparing them would fire this check after every
model switch — and a check that cries wolf is one you learn to skip, which is the exact failure this
hook exists to prevent. `theme`, `tui` and the notification keys are ignored for the milder reason
that a preference is not a safety event.

**Extraction is deliberately conservative: what it cannot identify, it says nothing about.** A hook
`command` is a shell string, not a path. The orca entries are one
`if [ -f … ] && [ -r … ] && [ -x … ]; then /bin/sh …; fi` carrying four references to the same file.
Anything carrying a shell metacharacter (`;` `&` `|` `<` `>` `(` `)`, a backtick, or a newline), any
unresolvable `$VAR`, any bare name resolved through `PATH`, and any leading `VAR=value` is skipped in
silence. A false alarm here trains the
reader to ignore the output, which is strictly worse than the gap it was meant to close.

**Contract: it always exits 0, and it never writes to stderr.** Unreadable file, malformed JSON, no
`python3`, `~/.claude` not a git checkout, detached HEAD, mid-rebase — every one is a silent no-op.
`symbolic-ref HEAD` failing is the single condition covering both detached HEAD and a rebase in
progress: neither has a branch whose HEAD means "what was reviewed", so check 2 skips while check 1
still runs. Findings go to **stdout**, one line each, prefixed `verify-hook-wiring:`; SessionStart
stdout is surfaced to the session as context, which is the delivery path `memsearch-nudge.sh`
already uses. This runs at the start of every session in every repo, so a false block would cost a
whole session somewhere else — hence a smoke alarm, not a lock. It is **not** one of the fail-loud
guards described in the next section.

**Measured, not assumed** (`verify-hook-wiring.measure.sh`, 20 runs per configuration, warm cache,
this machine 2026-08-22): **40–46 ms/run**, against a stated budget of ≤150 ms. The spread covers
both configurations — check 2 short-circuiting and check 2 running both git calls and the semantic
comparison — and the difference between them is inside the run-to-run noise. About 18–20 ms is the
bare `python3 -c pass` interpreter start, so the check itself is the smaller half of its own cost.
Re-run the script rather than quoting these numbers; it labels each configuration from what it
finds, not from what was true when it was written.

**What it cannot do.** It cannot detect its own absence — if `settings.json` disappears, this hook's
registration goes with it; that is ADR 0032's job, since the file is tracked and its disappearance
is a `git status` event. It cannot tell a working guard from a broken one that returns 0; only that
guard's own suite can. And check 2 is inert wherever `HEAD:settings.json` does not exist, or where
`~/.claude` is not on a branch — a detached HEAD and a mid-rebase both skip it silently. **Do not
read a specific machine's state out of this paragraph:** this one's shared checkout had no
`HEAD:settings.json` when the feature was written and does have one now, so any sentence naming the
current state would already be wrong. `verify-hook-wiring.probe.sh` prints which of those
preconditions actually hold, then breaks a real guard in a scratch copy to prove the check still
goes red.

*Why an instruction cannot do this job:* the model never sees the failure. An instruction can only
be followed by an agent that has been told something is wrong, and a hook whose script is missing
tells nobody anything — the tool call proceeds, the runner emits no output, and the transcript is
byte-identical to one where the guard ran and approved. There is no symptom to notice, no error to
react to, and nothing to remember to check. Only something that reads the config and stats the files
can see it, and it has to run on its own schedule rather than when someone thinks to ask.

---

## They fail loud, not silent

All four **fail loud rather than silently blocking.** Every rejection prints a specific, named reason to stderr — which file, which line or byte offset, which pattern, which repo — and exits non-zero.

This is a deliberate design choice, and it is the most important property of the set. A false positive should be *visible and correctable* — you see the message, you see exactly what fired, you fix the pattern or the file and move on. What must never happen is a write that mysteriously does not land, or an agent that goes quiet and starts working around an obstacle it cannot see. **A security control that fails silently is worse than no control at all**, because it manufactures confidence it has not earned. If one of these hooks is wrong, you will know immediately, and you will know why.

The two scanners extend this to **failing closed**: if the payload will not parse, or `python3` is not on `PATH`, they print why and **exit 2**. A scanner that cannot see the content cannot certify it, and waving through what it failed to inspect is the silent failure in a different costume.

`checkpoint-before-modify.sh` is the deliberate exception — with no parser it prints a loud warning and exits **0**. It is a rollback guard, not a security control, and blocking every Bash call because an interpreter is missing would re-create the trap the allowlist exists to remove.

The same principle is why every script is tested against both a positive and a negative fixture — **through the hook path, on stdin, not just the CLI path.** A scanner that does not fire on its own bad input is worse than no scanner; a scanner tested only on a path it will never run in production is exactly that scanner.

---

## Installing them

**Step 1 — put the scripts where the config points.** This is the step that is easy to skip, and skipping it is worse than a broken install — it is an *invisible* one. A `command` pointing at a script that is not there produces **nothing**: no stdout, no stderr, nothing under `--debug`, and the session continues exactly as if the guard had run and approved. Measured on claude 2.1.238, 2026-08-21; the probe and its control table are in `docs/features/hook-wiring-health-check.md`. Only exit `2` is loud, and a runner that never started the script has no exit code to report. `verify-hook-wiring.sh` exists to close precisely this gap — but it can only report on the config it is itself registered in. Pick one:

**Option A — user-level (no copying).** The scripts already live in `~/.claude/hooks/`. Reference them from `~/.claude/settings.json` and they apply to every repo:

```
"command": "$HOME/.claude/hooks/scan-secrets.sh"
```

**Option B — per-repo (copy them in first).** For a repo that should carry its own hooks, and the only form in which `$CLAUDE_PROJECT_DIR` works:

```bash
mkdir -p "$REPO/.claude/hooks"
cp ~/.claude/hooks/*.sh "$REPO/.claude/hooks/"
chmod +x "$REPO/.claude/hooks/"*.sh
```

Then reference them as `$CLAUDE_PROJECT_DIR/.claude/hooks/<script>.sh`. `$CLAUDE_PROJECT_DIR` resolves to the repo root, so no absolute paths are baked in — **but it resolves to the repo you are working in, not to `~/.claude`.** Without the copy above there is nothing at that path. Every script is self-contained (no shared library), so copying a single file is enough if you only want one.

Each script is committed executable (`chmod +x`); re-apply it after copying if your tooling drops the mode bit.

**Step 2 — paste the matching JSON block below** into the `settings.json` you chose. If it already has a `PreToolUse` entry (the global one has a `Bash` → `rtk hook claude` entry), **append to the existing `PreToolUse` array** rather than replacing it.

**Requirements:** `bash`, `git`, and `python3` on `PATH`. `python3` parses the JSON payload — see the scanner note above for why a `sed` extractor is not an acceptable substitute.

**Note on exit codes:** exit `2` is what Claude Code treats as a *block* (stderr is fed back to the model). Exit `0` means allow. The scripts use exactly these two.

### Secret + invisible-unicode scanning on every file write

Both read the content from the payload on stdin — no argument is passed, and none should be.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/scan-secrets.sh"
          },
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/scan-invisible-unicode.sh"
          }
        ]
      }
    ]
  }
}
```

For the user-level install (Option A), the same block with `$HOME/.claude/hooks/…` in place of `$CLAUDE_PROJECT_DIR/.claude/hooks/…`.

To also scan what has already landed, call them in CLI mode from a pre-commit hook:

```bash
git diff --cached --name-only --diff-filter=ACM | xargs -r ~/.claude/hooks/scan-secrets.sh
```

### The new-project standards gate

Reads `file_path` from the payload.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/require-project-standards.sh"
          }
        ]
      }
    ]
  }
}
```

### Checkpoint guard before shell commands

Takes the repo directory as `$1` and reads `tool_input.command` from the payload. It only blocks **destructive** commands on a dirty tree; recovery commands (`git add`/`commit`/`stash`) and ordinary work (test runs, builds) always pass — see the allowlist above.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/checkpoint-before-modify.sh \"$CLAUDE_PROJECT_DIR\""
          }
        ]
      }
    ]
  }
}
```

### Git safety guard on shell commands

Reads `tool_input.command` from the payload directly — no argument, unlike the checkpoint guard above. Blocks a `git commit` on `main`/`master` unless every staged file is a markdown file under `docs/` (`docs/*.md` — see ADR 0031; `CODING_MEMORY.md` and `coding-memory/*` were allowed here until that tree was retired), and blocks a bare `git push --force`/`-f` everywhere (`--force-with-lease` is also blocked on `main`/`master`). It unwraps a leading `rtk ` prefix first, so it still matches after the RTK hook above it has rewritten the command.

This is the one hook in this file that **is** installed — appended to this repo's own `settings.json`, after the existing `rtk hook claude` entry, because this repo is the global config every other repo inherits:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/git-guard.sh"
          }
        ]
      }
    ]
  }
}
```

---

## Portability

Written for bash 3.2+ (macOS ships 3.2) against macOS/BSD `grep` and `sed`, using only the flag subset (`-n -o -b -a -E -i -F`) shared by BSD grep, GNU grep, and ugrep — verified on Darwin. No GNU-only flags, no hard-coded absolute paths. `python3` is required for JSON payload parsing.

Three traps worth recording, each caught by a test rather than by reading:

- **`git rev-parse --show-toplevel` returns a *physical* path**, so anything compared against it must also be physical (`pwd -P`). On macOS `/tmp` is a symlink to `/private/tmp`, and using the logical `pwd` makes the prefix strip fail silently — which mangled the repo-relative path and defeated the `.claude/` exemption in `require-project-standards.sh`.
- **`[[ =~ ]]` cannot take an inline regex containing `(` or `;`.** Bash's parser reads them as shell syntax and dies with "unexpected EOF". The script then exits non-zero — which a `PreToolUse` hook reports as a *block*, so a syntax error masquerades as a working guard that blocks everything. `checkpoint-before-modify.sh` keeps its regexes in variables for exactly this reason.
- **Command substitution runs in a subshell, so `exit` inside one does not exit the script** and the `EXIT` trap does not fire. The scanners run their payload extractor with a plain redirect (`extract_segments > "$TMPROOT/segments.tsv"`) rather than `$( )`, so a fail-closed `exit 2` actually blocks the write and the temp directory still gets cleaned up.
