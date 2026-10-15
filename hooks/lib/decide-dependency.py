#!/usr/bin/env python3
"""Decide a PreToolUse payload for hooks/dependency-guard.sh.

    python3 -I decide-dependency.py <hooks-dir> <state-dir>   (payload JSON on stdin)

Spec: docs/features/dependency-vetting-guard.md, "Hook decisions", "Manifest edits" and "Failure
handling (D7)". The classifiers decide WHAT is being installed; this file decides what to do about
it (steps 0-3, the cannot-read rule, the log, the broken-guard ask).

Output contract with the wrapper: exit 0 with nothing on stdout = allow; exit 0 with the one-line
`ask` object on stdout; exit 2 with the deny lines on stdout (the wrapper moves them to stderr).
Anything else -- including a crash before main() can speak -- the wrapper turns into the same
"dependency-guard is broken" ask, so a broken guard is never a silent allow.
"""

import collections
import datetime
import importlib.util
import json
import os
import re
import shlex
import sys
import urllib.parse

LIB_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_LOG = "dependency-guard.log"
STORE_DIR = "vetting"
FIELD_LIMIT = 200
LOG_FAILED = " (log write failed)"
EXACT_PLACEHOLDER = "<exact-version>"
VERSION_OPERATORS = "^~<>=! "
EVENT_PRE_TOOL_USE = "PreToolUse"
MANIFEST_TOOLS = ("Edit", "Write", "NotebookEdit")
LOG_BROKEN, LOG_CANNOT_READ, LOG_ALLOW_UNREADABLE = "broken", "cannot-read", "allow-unreadable"
NPM_ALIAS_PREFIX = "npm:"
GIT_PREFIXES = ("git+", "git://", "ssh://", "git@", "github:", "gitlab:", "bitbucket:", "gist:")
GIT_HOSTS = ("github.com", "gitlab.com", "bitbucket.org")
ARCHIVE_SUFFIXES = (".tgz", ".tar.gz", ".tar", ".zip", ".whl")
GIT_HOST_WARNING = "downloads from a git host, not vetted, and the code can change unless pinned to a commit"
NO_VALUE = "-"
SUBSTITUTE = "?"
CANNOT_READ_TEXT = ("dependency-guard cannot read this command; it may install a package "
                    "— check it before approving")
DASH = "—"
EVERYTHING = "everything"

# What one intent (or manifest warning) decided. `kind` is what the hook does; `log_decision` is
# the word written to the log, which is `kind` except for the cannot-read ask.
Decision = collections.namedtuple("Decision", "kind text log_decision ecosystem name version")


def clean(value, limit=FIELD_LIMIT):
    """Every non-printable character becomes `?` and the text is cut: a crafted name cannot forge a
    log line or a deny line (spec, Log; Measured inputs on str.isprintable)."""
    return "".join(c if c.isprintable() else SUBSTITUTE for c in str(value))[:limit]


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(LIB_DIR, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    sys.modules[name] = module
    return module


def is_npm_git_shorthand(value):
    """npm's bare `owner/repo[#ref]` -- the one shape, defined in vetting_record.py. Read from
    sys.modules because load_libs() runs before any message is built; if it has not, the KeyError is
    a guard failure (main's "broken" ask), never a silent no."""
    return sys.modules["vetting_record"].is_npm_git_shorthand(value)


Libs = collections.namedtuple("Libs", "vr install manifest")


def load_libs():
    """Every lib, eagerly: a missing or unimportable one is a guard failure whatever the tool is."""
    if LIB_DIR not in sys.path:
        sys.path.insert(0, LIB_DIR)
    vr = load_module("vetting_record", "vetting_record.py")
    install = load_module("classify_install_command", "classify-install-command.py")
    manifest = load_module("classify_manifest_edit", "classify-manifest-edit.py")
    return Libs(vr, install, manifest)


Context = collections.namedtuple("Context", "libs store now vetter")


# ------------------------------------------------------------------------------------ messages
def example_version(ctx, ecosystem, version):
    """A real exact version to show in the advice when the command's own value is an operator on one
    (`^3.23.8` -> `3.23.8`), else the placeholder. Never invents a number."""
    if isinstance(version, str):
        bare = version.lstrip(VERSION_OPERATORS)
        if ctx.libs.vr.is_exact_version(ecosystem, bare):
            return bare
    return "v" + EXACT_PLACEHOLDER if ecosystem == "go" else EXACT_PLACEHOLDER


def exact_spelling(ctx, intent):
    eco, name = intent["ecosystem"], clean(intent["name"])
    version = example_version(ctx, eco, intent["version"])
    if eco == "npm":
        return "{}@{}".format(name, version)
    if eco == "pypi":
        return ("{}@{}" if intent["tool"] == "poetry" else "{}=={}").format(name, version)
    if eco == "crates.io":
        return "{}@={}".format(name, version)
    if eco == "go":
        return "{}@{}".format(name, version)
    return "{} --version {}".format(name, version)  # rubygems


def local_copy_advice(ctx, intent):
    """The sentence that replaced D9: only for an npm-registry runner's first non-option package."""
    name = intent["name"]
    npm_runner = intent["form"] == "run" and intent["ecosystem"] == "npm"
    if (not npm_runner or intent["via_package_option"] or name.startswith("@")
            or name.lower() in ctx.libs.install.INSTALL_TOOL_WORDS):
        return ""
    return (" If {n} is already installed in this project, run it directly instead: "
            "node_modules/.bin/{n}").format(n=clean(name))


def msg_unpinned(ctx, intent):
    return ("dependency-guard: {eco} {name} has no exact version {dash} pin it, e.g. {spelling}, "
            "then retry.{advice}").format(eco=intent["ecosystem"], name=clean(intent["name"]), dash=DASH,
                                          spelling=exact_spelling(ctx, intent),
                                          advice=local_copy_advice(ctx, intent))


def msg_runner_installer(intent):
    return ("dependency-guard: {runner} would fetch the package manager {name} {dash} run {name} directly "
            "so the guard can check what it installs.").format(runner=clean(intent["runner"]),
                                                               name=clean(intent["name"]), dash=DASH)


def msg_vet_first(ctx, intent):
    eco, name = intent["ecosystem"], clean(intent["name"])
    days = ctx.libs.vr.VET_MAX_AGE_DAYS
    tail = "then show Mark the report and your recommendation before retrying."
    if eco == "homebrew":  # D8: the command carries no version, so neither does the vetter line
        return ("dependency-guard: homebrew {n} has no vetting report from the last {d} days {dash} run: "
                "{v} homebrew {n}  {dash} {t}").format(n=name, d=days, v=ctx.vetter, dash=DASH, t=tail)
    version = clean(intent["version"])
    return ("dependency-guard: {e} {n}@{ver} has no vetting report from the last {d} days {dash} run: "
            "{v} {e} {n} {ver}  {dash} {t}").format(e=eco, n=name, ver=version, d=days, v=ctx.vetter,
                                                    dash=DASH, t=tail)


def source_value(intent):
    """What a `source: other` intent points at: a command carries it as `name`; a manifest carries the
    key as `name` and the source as `version`."""
    return intent["version"] or intent["name"]


def _spellings(value):
    """`value` and what is left after a leading `npm:` or a `name@` prefix (`foo@github:u/r`)."""
    pending, seen = [value], []
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        seen.append(current)
        if current.lower().startswith(NPM_ALIAS_PREFIX):
            pending.append(current[len(NPM_ALIAS_PREFIX):])
        at = current.find("@", 1)
        if at != -1:
            pending.append(current[at + 1:])
    return seen


def _is_git_spelling(ecosystem, value):
    lowered = value.lower()
    if lowered.startswith(GIT_PREFIXES):
        return True
    if lowered.startswith(("http://", "https://")):
        parsed = urllib.parse.urlparse(lowered)
        host = parsed.hostname or ""
        return parsed.path.endswith(".git") or any(host == h or host.endswith("." + h) for h in GIT_HOSTS)
    return (ecosystem == "npm" and is_npm_git_shorthand(value)
            and not lowered.split("#", 1)[0].endswith(ARCHIVE_SUFFIXES))


def is_git_source(intent):
    """A git URL or git-host shorthand (card, "Not from a registry"). npm's bare `owner/repo` means
    GitHub; for pip the same shape is a local directory, so it is not counted there."""
    return any(_is_git_spelling(intent["ecosystem"], spelling) for spelling in _spellings(source_value(intent)))


def msg_not_registry(intent):
    named = clean(intent["name"]) + (" ({})".format(clean(intent["version"])) if intent["version"] else "")
    text = ("dependency-guard: {} {} is not a registry package {} it cannot be vetted; check where it "
            "comes from before approving").format(intent["ecosystem"], named, DASH)
    return text + (" {} this source {}".format(DASH, GIT_HOST_WARNING) if is_git_source(intent) else "")


def msg_requirements_file(intent):
    return ("dependency-guard: {} installs everything listed in {}, which the guard does not parse {} read "
            "the file and check its packages before approving").format(clean(intent["tool"]),
                                                                       clean(intent["name"]), DASH)


def msg_update(intent):
    """`<form> <name>`: the tool plus the matched table words, then the package or `everything` (an
    update intent with no package argument is named after its tool)."""
    name = EVERYTHING if intent["name"] == intent["tool"] else clean(intent["name"])
    return ("dependency-guard: {} {}: an update or upgrade the guard does not vet {} check what it will "
            "change before approving").format(clean(intent["update_form"]), name, DASH)


def msg_indirect(intent):
    return ("dependency-guard: xargs {}: the packages come from input the guard cannot read {} check it "
            "before approving").format(clean(intent["name"]), DASH)


def msg_invalid_name(intent):
    return ('dependency-guard: {} "{}" is not a valid package name {} it cannot be vetted; check it '
            "before approving").format(intent["ecosystem"], clean(intent["name"]), DASH)


def format_age(delta):
    seconds = max(int(delta.total_seconds()), 0)
    for unit, size in (("day", 86400), ("hour", 3600), ("minute", 60)):
        if seconds >= size:
            count = seconds // size
            return "{} {}{}".format(count, unit, "" if count == 1 else "s")
    return "under a minute"


def count_clause(record, status):
    names = [clean(s["check"]) for s in record["signals"] if s["status"] == status]
    return "{} {}{}".format(len(names), status, " ({})".format(", ".join(names)) if names else "")


def ask_with_record(ctx, intent, record):
    """Step 3, from a fresh record."""
    eco, name = intent["ecosystem"], clean(intent["name"])
    age = format_age(ctx.now - ctx.libs.vr.parse_vetted_at(record["vetted_at"]))
    label = "{} {}@{}".format(eco, name, clean(record["version"]))
    note = " (brew installs the current stable)" if eco == "homebrew" else ""
    parts = ["{} {} vetted {} ago{}, {} / {}".format(label, DASH, age, note, count_clause(record, "stop"),
                                                     count_clause(record, "caution"))]
    if not record["complete"]:
        reasons = ", ".join(clean(r) for r in record["incomplete_reasons"]) or "no reason recorded"
        parts.append("INCOMPLETE: " + reasons)
    return finish_ask(intent, parts)


def ask_unvetted(intent):
    """Step 3 under VET_EXEMPT with no fresh record: the prompt stays, the vetting is skipped."""
    eco, name = intent["ecosystem"], clean(intent["name"])
    label = "{} {}".format(eco, name) if eco == "homebrew" else "{} {}@{}".format(eco, name, clean(intent["version"]))
    return finish_ask(intent, ["{} {} NOT VETTED (no report from the last 7 days)".format(label, DASH)])


def finish_ask(intent, parts):
    if intent["form"] == "run":
        parts.append("runs from registry")
    if intent["exempt"]:
        parts.append("VET_EXEMPT: " + clean(intent["exempt"]))
    return "dependency-guard: " + ", ".join(parts)


# ----------------------------------------------------------------------------------- decisions
def decision(kind, text, intent, log_decision=None):
    return Decision(kind, text, log_decision or kind, intent["ecosystem"], clean(intent["name"]),
                    clean(intent["version"]) if intent["version"] else NO_VALUE)


def decide_intent(ctx, intent):
    """Steps 0-3 (with 0a) for one install intent. A deny here is never a function of any other intent."""
    vr = ctx.libs.vr
    vr.validate_ecosystem(intent["ecosystem"])  # a bad ecosystem is a guard failure, not a prompt
    eco, name = intent["ecosystem"], intent["name"]
    if intent["form"] == "run" and name.lower() in ctx.libs.install.INSTALL_TOOL_WORDS:
        return decision("deny", msg_runner_installer(intent), intent)
    if intent["source"] == "other":
        return decision("ask", msg_not_registry(intent), intent)
    if intent["source"] == "requirements-file":
        return decision("ask", msg_requirements_file(intent), intent)
    if intent["source"] == "update":  # no record to read and no path built: VET_EXEMPT changes nothing
        return decision("ask", msg_update(intent), intent)
    if intent["source"] == "indirect":
        return decision("ask", msg_indirect(intent), intent)
    if eco != "homebrew" and not intent["pinned"]:
        return decision("deny", msg_unpinned(ctx, intent), intent)
    try:
        vr.validate_name(eco, name)
    except vr.ValidationError:
        return decision("ask", msg_invalid_name(intent), intent)
    if eco == "homebrew":
        record, _why = vr.newest_fresh_homebrew_record(ctx.store, name, ctx.now)
    else:
        record, _why = vr.read_fresh_record(ctx.store, eco, name, intent["version"], ctx.now)
    if record is not None:
        return decision("ask", ask_with_record(ctx, intent, record), intent)
    if intent["exempt"]:
        return decision("ask", ask_unvetted(intent), intent)
    return decision("deny", msg_vet_first(ctx, intent), intent)


def decide_manifest(ctx, payload):
    found = ctx.libs.manifest.classify(payload.get("tool_name"), payload.get("tool_input"))
    decisions = []
    for item in found:
        if item["kind"] == ctx.libs.manifest.KIND_WARNING:
            decisions.append(Decision("ask", "dependency-guard: " + clean(item["message"]), "ask",
                                      NO_VALUE, clean(item["file"]), NO_VALUE))
        else:
            decisions.append(decide_intent(ctx, item))
    return decisions, []


def decide_command(ctx, command):
    """-> (decisions, log_only). `log_only` carries the allow-unreadable line."""
    install = ctx.libs.install
    if install.is_unreadable(command):
        if install.mentions_install_tool(command):
            return [Decision("ask", CANNOT_READ_TEXT, LOG_CANNOT_READ, NO_VALUE, NO_VALUE, NO_VALUE)], []
        return [], [Decision("allow", "unreadable command, no install tool word", LOG_ALLOW_UNREADABLE,
                             NO_VALUE, NO_VALUE, NO_VALUE)]
    return [decide_intent(ctx, intent) for intent in install.classify(command)], []


def decide(ctx, payload):
    tool, tool_input = payload.get("tool_name"), payload.get("tool_input")
    if tool == "Bash":
        command = tool_input.get("command") if isinstance(tool_input, dict) else None
        return decide_command(ctx, command) if isinstance(command, str) and command else ([], [])
    if tool in MANIFEST_TOOLS:
        return decide_manifest(ctx, payload)
    return [], []


# ------------------------------------------------------------------------------------- output
def timestamp(now):
    return now.strftime("%Y-%m-%dT%H:%M:%SZ")


def append_log(state_dir, now, session, entries):
    """One line per entry, one write. -> True on success; a failure never changes the decision."""
    lines = "".join("\t".join([timestamp(now), clean(session), e.log_decision, e.ecosystem, e.name, e.version,
                               clean(e.text)]) + "\n" for e in entries)
    try:
        os.makedirs(state_dir, mode=0o700, exist_ok=True)
        descriptor = os.open(os.path.join(state_dir, STATE_LOG), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        with os.fdopen(descriptor, "a", encoding="utf-8") as handle:
            handle.write(lines)
        return True
    except OSError:
        return False


def ask_json(reason):
    return json.dumps({"hookSpecificOutput": {"hookEventName": EVENT_PRE_TOOL_USE,
                                              "permissionDecision": "ask",
                                              "permissionDecisionReason": reason}}, separators=(",", ":"))


def emit(decisions, log_failed):
    """Strongest wins: any deny -> exit 2 with one line per denied intent; else one ask, one clause each."""
    suffix = LOG_FAILED if log_failed else ""
    denies = [d.text for d in decisions if d.kind == "deny"]
    if denies:
        sys.stdout.write("\n".join(denies) + suffix + "\n")
        return 2
    asks = [d.text for d in decisions if d.kind == "ask"]
    if asks:
        sys.stdout.write(ask_json("; ".join(asks) + suffix) + "\n")
    return 0


def session_id(payload):
    value = payload.get("session_id") if isinstance(payload, dict) else None
    return value if isinstance(value, str) and value else os.environ.get("CLAUDE_CODE_SESSION_ID", "nosession")


def report_broken(state_dir, exc, session):
    first_line = (str(exc).splitlines() or [""])[0]
    reason = "dependency-guard is broken: " + clean("{}: {}".format(type(exc).__name__, first_line))
    now = datetime.datetime.now(datetime.timezone.utc)
    entry = Decision("ask", reason, LOG_BROKEN, NO_VALUE, NO_VALUE, NO_VALUE)
    logged = append_log(state_dir, now, session, [entry])
    sys.stdout.write(ask_json(reason + ("" if logged else LOG_FAILED)) + "\n")
    return 0


def main(argv):
    hooks_dir, state_dir = argv[1], argv[2]
    payload = None
    try:
        payload = json.loads(sys.stdin.read())
        if not isinstance(payload, dict):
            raise ValueError("payload is not an object")
        if payload.get("hook_event_name") != EVENT_PRE_TOOL_USE:
            return 0
        libs = load_libs()
        now = datetime.datetime.now(datetime.timezone.utc)
        vetter = shlex.quote(os.path.join(hooks_dir, "bin", "vet-dependency"))
        ctx = Context(libs, os.path.join(state_dir, STORE_DIR), now, vetter)
        decisions, log_only = decide(ctx, payload)
        logged = True
        if decisions or log_only:
            logged = append_log(state_dir, now, session_id(payload), decisions + log_only)
        return emit(decisions, not logged)
    except Exception as exc:  # noqa: BLE001 -- every failure is the same "broken" ask, never a silent allow
        return report_broken(state_dir, exc, session_id(payload))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
