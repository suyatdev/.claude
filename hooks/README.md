# Hooks

**These hooks are NOT installed.** `settings.json` is untouched by design — nothing in this directory runs until you deliberately wire it up by pasting one of the JSON blocks below into a repo's `.claude/settings.json`. They were designed, tested, and left inert on purpose.

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

### `scan-secrets.sh`

Scans a file for AWS access key IDs, private key headers, generic `api_key` assignments, bearer tokens, and password assignments. Reports file, line number, and the **name** of the pattern that fired.

It deliberately does **not** print the matched text. Echoing a secret into stderr, a transcript, or a CI log is the leak we are trying to prevent; the whole point is to stop the value from propagating.

*Why an instruction cannot do this job:* "Never commit secrets" is the single most universally agreed-upon rule in software, and it is violated constantly — GitHub revokes tens of thousands of leaked keys a year, all of them written by people who knew the rule. Knowing the rule has never been the bottleneck. Noticing, in the moment, that this particular string is a live credential is the bottleneck, and that is a mechanical check.

### `scan-invisible-unicode.sh`

Scans for zero-width and bidirectional-control codepoints: U+200B/C/D, U+2060, U+FEFF appearing mid-file, the U+202A–U+202E bidi overrides, and the U+2066–U+2069 bidi isolates. Reports file, byte offset, and codepoint name. A BOM at byte 0 is legitimate and is not flagged.

*Why an instruction cannot do this job:* **this is the case where human review structurally cannot help.** These codepoints have no glyph. A hidden instruction embedded in a source file renders as nothing in a diff, nothing in a PR review, and nothing in an editor at default settings. A reviewer reading carefully and in good faith sees clean code and approves it — that is not a lapse in diligence, it is the attack working as designed.

The blast radius is what makes it urgent. The payload is not just *read* by an agent, it is *copied* by one. Once an agent treats a poisoned file as a pattern to imitate, it replicates the invisible bytes into everything it touches, and every copy is exactly as invisible as the original. One poisoned fixture becomes hundreds of poisoned files in minutes, all of them already in git history by the time anyone notices from behavior. You cannot ask a human to be the control for bytes a human cannot see.

### `checkpoint-before-modify.sh`

Verifies a rollback point exists before a batch of modifications: the directory is a git repo, it has at least one commit, and the working tree is clean. If not, it names on stderr exactly what is at risk (staged, unstaged, and untracked) and exits non-zero.

*Why an instruction cannot do this job:* the agent about to make a sweeping change is precisely the agent least likely to pause and ask whether the work it is about to overwrite is recoverable. "Commit before a big refactor" is a rule everyone endorses and nobody remembers under momentum, and the cost is asymmetric — overwritten uncommitted work is simply gone, and no apology at the end restores it.

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

The same principle is why every script was tested against both a positive and a negative fixture. A scanner that does not fire on its own bad input is worse than no scanner.

---

## Installing them

These use the `PreToolUse` matcher form, matching the shape already used by the existing `settings.json`. Paste into a repo's `.claude/settings.json`.

`$CLAUDE_PROJECT_DIR` resolves to the repo root, so no absolute paths are baked in. Claude Code passes the tool payload as JSON on stdin; each script reads `file_path` from it, and each also accepts a plain file path as `$1` so you can run it by hand.

**Note on exit codes:** exit `2` is what Claude Code treats as a *block* (stderr is fed back to the model). Exit `0` means allow. The scripts use exactly these two.

### Secret + invisible-unicode scanning on every file write

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
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

### The new-project standards gate

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

Takes a directory rather than a file path. Wire it to `Bash` only if you want a hard "commit your work first" gate; it is the most intrusive of the four, since it fires on a dirty tree regardless of what the command actually does.

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

If you add these to a `settings.json` that already has a `PreToolUse` entry (the global one has a `Bash` → `rtk hook claude` entry), append to the existing `PreToolUse` array rather than replacing it.

---

## Portability

Written for POSIX-ish bash against macOS/BSD `grep` and `sed`, using only the flag subset (`-n -o -b -a -E -i -F`) shared by BSD grep, GNU grep, and ugrep — verified against all of the above on Darwin. No GNU-only flags, no hard-coded absolute paths.

One portability trap worth recording: `git rev-parse --show-toplevel` returns a *physical* path, so anything compared against it must also be physical (`pwd -P`). On macOS `/tmp` is a symlink to `/private/tmp`, and using the logical `pwd` makes the prefix strip fail silently — which mangled the repo-relative path and defeated the `.claude/` exemption in `require-project-standards.sh` until it was caught by a fixture.
