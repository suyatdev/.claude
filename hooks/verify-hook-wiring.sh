#!/usr/bin/env bash
# verify-hook-wiring.sh — SessionStart hook-wiring health check (Tier 3).
#
# Answers one question at session start: can the guards that settings.json
# registers actually run, and does the live wiring still match the version that
# was reviewed. Prints nothing when both answers are yes.
#
# Why this exists. A hook that DENIES is loud — exit 2 blocks the call and its
# stderr reaches the model verbatim. A hook whose script is missing produces
# nothing at all: no stdout, no stderr, nothing under --debug, and the session
# continues exactly as if the guard had run and approved. Measured on
# claude 2.1.238, 2026-08-21 (docs/features/hook-wiring-health-check.md). Every
# script in this directory is one rename away from that state, and no
# instruction to the model can close it — the model never sees the failure.
#
# Contract, in full:
#   - Always exits 0. Unreadable file, malformed JSON, no python3, ~/.claude not
#     a git checkout, detached HEAD, mid-rebase: every one is a silent no-op.
#     This runs at the start of every session in every repo, so a false block
#     costs a whole session somewhere else.
#   - Nothing on stdout when healthy; nothing on stderr, ever. Findings go to
#     stdout, one line each, prefixed "verify-hook-wiring:" — SessionStart
#     stdout is surfaced to the session as context, which is the delivery
#     mechanism memsearch-nudge.sh already uses.
#   - Resolves everything from $HOME, never from cwd.
#
# It is a smoke alarm, not a lock. It cannot detect its own absence (if
# settings.json vanishes, so does this hook's registration — that is ADR 0032's
# job, since the file is tracked), and it cannot tell a working guard from a
# broken one that returns 0 (only that guard's own suite can).

HOME_DIR="${HOME:-}"
[ -n "$HOME_DIR" ] || exit 0

CLAUDE_DIR="$HOME_DIR/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
[ -f "$SETTINGS" ] || exit 0

# Check 2's precondition, resolved here so python never has to shell out.
# `symbolic-ref HEAD` failing is the single condition that covers both a plain
# detached HEAD and a rebase in progress: neither has a branch whose HEAD is a
# meaningful "what was reviewed". An empty HEAD_SETTINGS means "skip check 2",
# so every one of these bail-outs is the same silent path.
HEAD_JSON=""
if [ -e "$CLAUDE_DIR/.git" ] &&
   git -C "$CLAUDE_DIR" symbolic-ref -q HEAD >/dev/null 2>&1; then
  HEAD_JSON="$(git -C "$CLAUDE_DIR" show HEAD:settings.json 2>/dev/null)" || HEAD_JSON=""
fi

HEAD_SETTINGS="$HEAD_JSON" python3 - "$SETTINGS" <<'PY' 2>/dev/null
import json
import os
import re
import shlex
import sys

PREFIX = "verify-hook-wiring:"

# The keys that describe how this machine is wired, and the ones deliberately
# left out. model/effortLevel are excluded because ADR 0032 accepted that /model
# rewrites them: comparing them would make this fire after every model switch,
# and a check that cries wolf stops being read — which is the exact failure this
# feature exists to prevent. Everything else (theme, tui, notification
# preferences) is a preference, and drift there is not a safety event.
WIRING_KEYS = ("hooks", "permissions", "statusLine", "enabledPlugins")

# A leading word from this set means the script is the NEXT word. Kept
# deliberately small: an interpreter this does not know about makes the command
# unidentifiable, which is the safe answer.
INTERPRETERS = frozenset(
    ("bash", "sh", "zsh", "python3", "/bin/bash", "/bin/sh", "/bin/zsh")
)

# Any of these means the string is more than one simple command, so the script
# it ends up running cannot be identified by reading the first word or two. The
# orca entries are the live example: one `if [ -f … ] && [ -r … ]; then /bin/sh
# …; fi` carrying four references to the same path. Reporting a guess there
# would be a false alarm, and a reader who learns to ignore this output is worse
# off than one who never had it.
SHELL_METACHARACTERS = ";&|<>`()\n"

MISSING = object()


def expand_home(path, home):
    """$HOME/~ expanded; None if any variable is left that we cannot resolve."""
    if path.startswith("~/"):
        path = home + path[1:]
    path = path.replace("${HOME}", home).replace("$HOME", home)
    return None if "$" in path else path


def script_path(command, home):
    """The script a hook command invokes, or None if it is not identifiable."""
    if any(c in command for c in SHELL_METACHARACTERS):
        return None
    try:
        words = shlex.split(command)
    except ValueError:
        return None
    if not words:
        return None
    head = words[0]
    if head in INTERPRETERS:
        if len(words) < 2:
            return None
        candidate = words[1]
    elif "=" in head:
        return None  # a leading VAR=value assignment: the script is elsewhere
    else:
        candidate = head
    if "/" not in candidate:
        return None  # a bare name resolved through PATH is not one of ours
    return expand_home(candidate, home)


def command_hooks(settings):
    """Yield (event, command) for every type:"command" hook, shape permitting."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            continue
        for group in groups:
            if not isinstance(group, dict):
                continue
            entries = group.get("hooks")
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    continue
                command = entry.get("command")
                if entry.get("type") == "command" and isinstance(command, str):
                    yield event, command


def check_registered_hooks_can_run(settings, home):
    findings = []
    for event, command in command_hooks(settings):
        path = script_path(command, home)
        if path is None:
            continue
        if not os.path.exists(path):
            findings.append(
                "%s %s hook cannot run — no such file: %s" % (PREFIX, event, path)
            )
        elif not os.access(path, os.X_OK):
            findings.append(
                "%s %s hook cannot run — not executable: %s" % (PREFIX, event, path)
            )
    return findings


def drift_line(detail):
    return "%s settings.json drift — %s" % (PREFIX, detail)


# Long enough for a mode, a plugin id, or a short command; short enough that a
# finding stays one readable line. A value longer than this is truncated rather
# than dropped: knowing a long value moved is still worth more than silence.
VALUE_LIMIT = 60

# Naming a drifted setting means printing its value into session-start stdout,
# which nothing here did before. settings.json is not supposed to carry
# credentials — `env` is excluded from WIRING_KEYS for exactly that reason — but
# "supposed to" is a convention, and a check built because conventions drift
# unobserved should not stake anything on one. Matched against the sub-key name
# AND the rendered value, so a secret is caught under an innocuous name too.
# Deliberately broad: a false redaction costs a little detail in one line, while
# a false negative writes a credential into every session transcript. "author"
# matching "auth" is a price worth paying.
SENSITIVE = re.compile(r"key|token|secret|password|credential|auth|bearer", re.I)
REDACTED = "<redacted>"
WITHHELD = "<changed>"

# The word list above only catches a LABELLED secret, and real credentials are
# usually opaque strings under ordinary names. This is the shape test for those:
# a long unbroken run of credential characters mixing letters and digits. Config
# values that a human needs to read break on "/", ".", spaces, quotes and
# brackets long before 20 characters; an API key or a JWT segment does not.
OPAQUE_RUN = re.compile(r"[A-Za-z0-9_-]{20,}")


def looks_opaque(text):
    """True if any run in text has the shape of a credential rather than a setting."""
    for run in OPAQUE_RUN.findall(text):
        if any(c.isdigit() for c in run) and any(c.isalpha() for c in run):
            return True
    return False


def render(value, name=""):
    """A one-line rendering of a config value, short enough to sit in a line.

    Over-long values are WITHHELD, never truncated. Truncating and printing the
    prefix leaks a credential just as thoroughly as printing all of it — 57
    characters of a JWT is still a JWT — and the reader learns nothing from a
    severed string anyway. The sub-key is still named either way, which is the
    part that makes the finding actionable.
    """
    text = json.dumps(value, sort_keys=True)
    if SENSITIVE.search(name) or SENSITIVE.search(text):
        return REDACTED
    if len(text) > VALUE_LIMIT or looks_opaque(text):
        return WITHHELD
    return text


def subkey_drift(key, live_value, head_value):
    """One line per differing sub-key, or None if this key cannot be split.

    "permissions differs" is the finding this feature cannot afford. The drift
    that motivated the whole check was permissions.defaultMode moving unnoticed,
    and a reader told only that "permissions" changed still has to go and diff
    the file by hand — which is the work the check was supposed to have done.
    Only one level deep: nested detail buys less than it costs in line length,
    and the sub-key plus both values is enough to decide whether to care.
    """
    if not isinstance(live_value, dict) or not isinstance(head_value, dict):
        return None
    findings = []
    for name in sorted(set(live_value) | set(head_value)):
        in_live, in_head = name in live_value, name in head_value
        if in_live and in_head:
            if live_value[name] == head_value[name]:
                continue
            findings.append(
                drift_line(
                    "%s.%s: live %s, HEAD %s"
                    % (
                        key,
                        name,
                        render(live_value[name], name),
                        render(head_value[name], name),
                    )
                )
            )
        elif in_live:
            findings.append(
                drift_line(
                    "%s.%s: present in the live file, absent from HEAD" % (key, name)
                )
            )
        else:
            findings.append(
                drift_line(
                    "%s.%s: present in HEAD, absent from the live file" % (key, name)
                )
            )
    return findings or None


def hook_drift(live, head, home):
    """Per-hook drift lines, plus whether an unnamed difference was left over."""
    live_set = set(command_hooks(live))
    head_set = set(command_hooks(head))
    findings, unnamed = [], False
    for pairs, phrasing in (
        (head_set - live_set, "%s hook %s is registered in HEAD but not in the live file"),
        (live_set - head_set, "%s hook %s is registered in the live file but not in HEAD"),
    ):
        for event, command in sorted(pairs):
            path = script_path(command, home)
            if path is None:
                unnamed = True
                continue
            findings.append(drift_line(phrasing % (event, os.path.basename(path))))
    return findings, unnamed


def check_live_matches_head(live, head, home):
    """Compare the wiring keys semantically — key order and formatting cannot
    matter, only whether a setting actually changed."""
    findings = []
    for key in WIRING_KEYS:
        live_value = live.get(key, MISSING)
        head_value = head.get(key, MISSING)
        if live_value == head_value:
            continue
        if key != "hooks":
            named = subkey_drift(key, live_value, head_value)
            # No sub-keys to name — one side stopped being an object, or is
            # absent entirely. The key-level line is still the honest answer.
            findings.extend(
                named
                or [drift_line('live "%s" differs from HEAD:settings.json' % key)]
            )
            continue
        named, unnamed = hook_drift(live, head, home)
        findings.extend(named)
        # A matcher, a timeout, or an unidentifiable command changed: the hooks
        # key really did drift, and saying so vaguely beats saying nothing.
        if unnamed or not named:
            findings.append(drift_line('live "hooks" differs from HEAD:settings.json'))
    return findings


def main():
    home = os.environ.get("HOME") or ""
    if not home:
        return
    with open(sys.argv[1]) as handle:
        live = json.load(handle)
    if not isinstance(live, dict):
        return

    findings = check_registered_hooks_can_run(live, home)

    raw_head = os.environ.get("HEAD_SETTINGS") or ""
    if raw_head:
        head = json.loads(raw_head)
        if isinstance(head, dict):
            findings.extend(check_live_matches_head(live, head, home))

    seen = set()
    for line in findings:
        if line not in seen:
            seen.add(line)
            print(line)


try:
    main()
except Exception:
    pass  # by contract: every internal failure is a silent no-op
sys.exit(0)
PY
exit 0
