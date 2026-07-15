# Hooks

**Most of these hooks are NOT installed.** Nothing in this directory runs until you deliberately wire it up by pasting one of the JSON blocks below into a repo's `.claude/settings.json`. They were designed, tested, and left inert on purpose. The one exception is `git-guard.sh`, appended to this repo's own `settings.json` — see its section below for why.

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

1. **Default-branch commit guard.** Blocks `git commit` while `main`/`master` is checked out, unless every staged file is `CODING_MEMORY.md` or under `coding-memory/` — the brainstorm-then-branch exception in `preparing-pull-requests`.
2. **Force-push guard.** Blocks a bare `git push --force`/`-f` on any branch. `--force-with-lease` is allowed, except while `main`/`master` is checked out, where it is blocked too.

It also unwraps an `rtk ` prefix before matching: the RTK hook is registered ahead of this one on the same `Bash` matcher and rewrites plain git commands, so by the time this guard runs the command it sees may already read `rtk git commit -m x`.

*Why an instruction cannot do this job:* "never commit to main" and "never force-push" are two of the most-repeated rules in `preparing-pull-requests`, and both fail the same way — under momentum, mid-session, with a confident model that has just finished a brainstorm and wants to save the result. The brainstorm-then-branch exception makes the naive version of this guard wrong (a flat "no commits on main" would also block the one commit the workflow requires), so the allowlist has to be as precise as the rule it enforces: `CODING_MEMORY.md` and `coding-memory/*`, nothing else.

Unlike the other four hooks in this file, `git-guard.sh` **is installed** — it runs in this repo's own `settings.json` today, because this repo is the global config every other repo inherits, and the two guards it enforces (`preparing-pull-requests`) apply here first.

### `require-project-standards.sh`

**The enforcement half of the `setting-up-a-new-project` skill.** Given a target file path, it blocks the write if the path is project source code, the path is inside a git repo, and `.claude/project-standards.md` does not exist.

It does **not** block:
- writes under `.claude/` — otherwise the register could never be created in the first place
- docs, markdown, and plain text — writing a README before setup is harmless
- anything outside a git repo — scratch files are not a project

*Why an instruction cannot do this job:* the skill already defines this as a "blocking gate," but a gate made of words is a gate that opens when pushed. A session can be talked out of it ("let's just get something working first"), or can simply forget it after a context compaction, and the gate then quietly does not happen — silently, with no error, which is the worst way for a control to fail. The project then accretes code with no agreed standards, which is the exact outcome the skill exists to prevent.

**The skill asks the questions; the hook makes sure they actually get asked.**

---

## They fail loud, not silent

All four **fail loud rather than silently blocking.** Every rejection prints a specific, named reason to stderr — which file, which line or byte offset, which pattern, which repo — and exits non-zero.

This is a deliberate design choice, and it is the most important property of the set. A false positive should be *visible and correctable* — you see the message, you see exactly what fired, you fix the pattern or the file and move on. What must never happen is a write that mysteriously does not land, or an agent that goes quiet and starts working around an obstacle it cannot see. **A security control that fails silently is worse than no control at all**, because it manufactures confidence it has not earned. If one of these hooks is wrong, you will know immediately, and you will know why.

The two scanners extend this to **failing closed**: if the payload will not parse, or `python3` is not on `PATH`, they print why and **exit 2**. A scanner that cannot see the content cannot certify it, and waving through what it failed to inspect is the silent failure in a different costume.

`checkpoint-before-modify.sh` is the deliberate exception — with no parser it prints a loud warning and exits **0**. It is a rollback guard, not a security control, and blocking every Bash call because an interpreter is missing would re-create the trap the allowlist exists to remove.

The same principle is why every script is tested against both a positive and a negative fixture — **through the hook path, on stdin, not just the CLI path.** A scanner that does not fire on its own bad input is worse than no scanner; a scanner tested only on a path it will never run in production is exactly that scanner.

---

## Installing them

**Step 1 — put the scripts where the config points.** This is the step that is easy to skip and guarantees a broken install if you do: a `command` pointing at a script that is not there fails with **exit 127** on every matching tool call. Pick one:

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

Reads `tool_input.command` from the payload directly — no argument, unlike the checkpoint guard above. Blocks a `git commit` on `main`/`master` unless every staged file is `CODING_MEMORY.md` or under `coding-memory/`, and blocks a bare `git push --force`/`-f` everywhere (`--force-with-lease` is also blocked on `main`/`master`). It unwraps a leading `rtk ` prefix first, so it still matches after the RTK hook above it has rewritten the command.

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
