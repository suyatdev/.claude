#!/usr/bin/env python3
"""Classify a raw Bash command string as "which packages does it install?".

Used by hooks/dependency-guard.sh. A pure function: command text in, a list of install intents
out (docs/features/dependency-vetting-guard.md, "Contracts" and the install-forms table). It never
touches the filesystem, so a bypass shape can be unit-tested by calling classify() directly.

The segment lexer lives in shell_segments.py, shared with the other guards; its limits (a quoted
`bash -c "..."` body is one token, variable indirection is invisible) are this module's limits and
are listed in the card's Known gaps. "Pinned" is decided only by vetting_record.is_exact_version.

Beyond classify(), two helpers carry the card's "command the lexer cannot read" rule, so the hook and
this module share one INSTALL_TOOL_WORDS list: is_unreadable() and mentions_install_tool().
"""

import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shell_segments import ASSIGN_RE, WRAPPERS, program, segments  # noqa: E402
from vetting_record import is_exact_version, is_npm_git_shorthand  # noqa: E402

__all__ = ["classify", "is_unreadable", "mentions_install_tool", "is_exact_version", "RUNNERS",
           "INSTALL_TOOL_WORDS", "MAX_READINGS"]

ECO_NPM, ECO_PYPI, ECO_CRATES, ECO_GO, ECO_GEMS, ECO_BREW = (
    "npm", "pypi", "crates.io", "go", "rubygems", "homebrew")
REGISTRY, OTHER, REQUIREMENTS_FILE = "registry", "other", "requirements-file"
UPDATE, INDIRECT, CANNOT_READ = "update", "indirect", "cannot-read"

# The plain-word allowlist for a VET_EXEMPT value. A local copy of the one at
# hooks/lib/secret_approval.py:261 (_EXEMPT_VALUE_ALLOWED_RE), not an import: that name is private to
# another guard's module, and its `^...$` form lets `$` match before a trailing newline, so this one is
# applied with fullmatch. Keep the character set in step with that line.
EXEMPT_VAR = "VET_EXEMPT"
EXEMPT_VALUE_RE = re.compile(r"[A-Za-z0-9._,:/-]+")

# The one list of commands that fetch a package and run it (card, "RUNNERS"). An intent has
# form "run" exactly when its runner is a member; _runner_name() refuses to emit anything else.
RUNNERS = ("npx", "pnpx", "pnx", "bunx", "bun x", "npm exec", "npm x", "pnpm dlx", "pn dlx", "yarn dlx",
           "yarnpkg dlx", "uvx", "uv tool run", "pipx run")

# Every program named in the install-forms table (card, "A command the lexer cannot read").
INSTALL_TOOL_WORDS = ("npm", "npx", "pnpm", "pn", "pnpx", "pnx", "yarn", "yarnpkg", "corepack", "bun", "bunx",
                      "pip", "pip3", "python", "python3", "uv", "uvx", "poetry", "pipx", "cargo", "go", "gem",
                      "brew")
_TOOL_WORD_RE = re.compile(
    r"(?<![A-Za-z0-9_.-])(?:{})(?![A-Za-z0-9_.-])".format("|".join(re.escape(w) for w in INSTALL_TOOL_WORDS)),
    re.IGNORECASE)

# Each INSTALL_TOOL_WORDS member's ecosystem (the card's install-forms table). Every update or
# indirect intent needs one, because the decider validates it before anything else.
TOOL_ECOSYSTEM = {
    "npm": ECO_NPM, "npx": ECO_NPM, "pnpm": ECO_NPM, "pn": ECO_NPM, "pnpx": ECO_NPM, "pnx": ECO_NPM,
    "yarn": ECO_NPM, "yarnpkg": ECO_NPM, "corepack": ECO_NPM, "bun": ECO_NPM, "bunx": ECO_NPM,
    "pip": ECO_PYPI, "pip3": ECO_PYPI, "python": ECO_PYPI, "python3": ECO_PYPI, "uv": ECO_PYPI, "uvx": ECO_PYPI,
    "poetry": ECO_PYPI, "pipx": ECO_PYPI, "cargo": ECO_CRATES, "go": ECO_GO, "gem": ECO_GEMS, "brew": ECO_BREW,
}
HELP_FLAGS = frozenset(["--help", "-h"])
# manager -> the subcommand words that update (card, "Updates, upgrades and indirect installs")
NODE_UPDATE_WORDS = {
    "npm": frozenset(["update", "u", "up", "upgrade", "udpate"]),
    "pnpm": frozenset(["update", "up", "upgrade"]),
    "pn": frozenset(["update", "up", "upgrade"]),
    "yarn": frozenset(["upgrade", "up", "upgrade-interactive"]),
    "yarnpkg": frozenset(["upgrade", "up", "upgrade-interactive"]),
    "bun": frozenset(["update", "upgrade"]),
}
YARN_PROGRAMS = frozenset(["yarn", "yarnpkg"])
# yarn 4 `workspaces foreach` options that take the NEXT word (--opt=value is one word); --since takes none
FOREACH_VALUE_FLAGS = frozenset(["--from", "--include", "--exclude", "-j", "--jobs"])
PNPM_PROGRAMS = frozenset(["pnpm", "pn"])
EXEC_PROGRAMS = YARN_PROGRAMS | PNPM_PROGRAMS  # `<program> exec <command>` runs <command>
WIDTH_PROGRAMS = EXEC_PROGRAMS | {"npm"}  # R9: the programs whose option widths are read both ways (bun is not)
PNPM_RECURSIVE_ALIASES = frozenset(["recursive", "multi", "m"])  # pnpm rewrites these to --recursive
SHELL_MODE_FLAGS = frozenset(["-c", "--shell-mode"])
# R3: the most readings one command may start, over every scan and every nested exec; past it, the cannot-read ask
MAX_READINGS = 64
UV_UPGRADE_FLAGS = frozenset(["-U", "--upgrade"])
UV_UPGRADE_PACKAGE_FLAGS = frozenset(["-P", "--upgrade-package"])
UV_UPGRADE_GROUP_FLAG = "--upgrade-group"
UV_UPGRADING_SUBCOMMANDS = frozenset(["lock", "sync", "add", "run"])
PIPX_UPDATE_WORDS = frozenset(["upgrade", "upgrade-all", "reinstall", "reinstall-all"])

NPM_INSTALL_WORDS = frozenset(["install", "add", "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta",
                               "isntal", "isntall", "install-test", "it"])
# manager -> (words that install named packages, words that run a fetched package)
NODE_MANAGERS = {
    "npm": (NPM_INSTALL_WORDS, frozenset(["exec", "x"])),
    "pnpm": (frozenset(["add", "install", "i"]), frozenset(["dlx"])),
    "pn": (frozenset(["add", "install", "i"]), frozenset(["dlx"])),
    "yarn": (frozenset(["add", "install"]), frozenset(["dlx"])),
    "yarnpkg": (frozenset(["add", "install"]), frozenset(["dlx"])),
    "bun": (frozenset(["add", "install", "i"]), frozenset(["x"])),
}
WHOLE_PROGRAM_RUNNERS = {"npx": ECO_NPM, "pnpx": ECO_NPM, "pnx": ECO_NPM, "bunx": ECO_NPM, "uvx": ECO_PYPI}
NPM_PACKAGE_FLAGS = frozenset(["-p", "--package"])
REQUIREMENT_FLAGS = frozenset(["-r", "--requirement", "--requirements"])
EDITABLE_FLAGS = frozenset(["-e", "--editable"])
SOURCE_FLAGS = ("--git", "--path")

# Options that take a SEPARATE value; without them the value would be read as a package or as the
# subcommand. A flag missing here makes the guard miss a package behind it -- fail-open, so the set
# errs wide. Per tool, since one tool's boolean is another's valued flag (-p, -v, -c).
NODE_VALUE_FLAGS = frozenset([
    "--prefix", "-C", "--registry", "--workspace", "-w", "--cache", "--userconfig", "--globalconfig", "--loglevel",
    "--otp", "--scope", "--tag", "--omit", "--include", "--save-prefix", "--install-strategy", "--before",
    "--filter", "-F", "--dir", "--cwd", "--cache-folder", "--config"])
NPM_RUNNER_VALUE_FLAGS = NODE_VALUE_FLAGS | NPM_PACKAGE_FLAGS | frozenset(["-c", "--call"])
# pnpm 12.15.0 reads these as booleans (R9), though they take a value for npm. `dlx -c` is its --shell-mode.
PNPM_BOOLEAN_FLAGS = frozenset(["-w", "--workspace", "--config"])
PNPM_VALUE_FLAGS = NODE_VALUE_FLAGS - PNPM_BOOLEAN_FLAGS
PNPM_RUNNER_VALUE_FLAGS = NPM_RUNNER_VALUE_FLAGS - PNPM_BOOLEAN_FLAGS - frozenset(["-c"])
PIP_VALUE_FLAGS = frozenset([
    "-r", "--requirement", "-c", "--constraint", "-i", "--index-url", "--extra-index-url", "-f", "--find-links",
    "-t", "--target", "--prefix", "--root", "--python", "--platform", "--python-version", "--implementation",
    "--abi", "--proxy", "--cache-dir", "--src", "--upgrade-strategy", "--only-binary", "--no-binary",
    "--progress-bar", "--log", "--trusted-host", "--cert", "--client-cert", "--retries", "--timeout",
    "--exists-action", "-e", "--editable", "--global-option", "--config-settings", "--report",
    "--index-strategy", "--resolution", "--directory", "--project", "--config-file"])
PYPI_ADD_VALUE_FLAGS = PIP_VALUE_FLAGS | frozenset([
    "--group", "-G", "--optional", "--extra", "-E", "--extras", "-p", "--source", "--index", "--default-index",
    "--package", "--rev", "--tag", "--branch", "--git", "--path", "--requirements", "-P", "--upgrade-package",
    "--upgrade-group"])
PYPI_RUNNER_VALUE_FLAGS = PYPI_ADD_VALUE_FLAGS | frozenset([
    "--from", "--with", "-w", "--with-requirements", "--with-editable", "--spec", "--pip-args", "--suffix"])
CARGO_VALUE_FLAGS = frozenset([
    "--features", "-F", "--package", "-p", "--manifest-path", "--rename", "--registry", "--index", "--target",
    "--branch", "--tag", "--rev", "--git", "--path", "--version", "--root", "--bin", "--example", "--profile",
    "--jobs", "-j", "--target-dir", "-Z", "--config", "--color"])
GO_VALUE_FLAGS = frozenset(["-C", "-tags", "-ldflags", "-gcflags", "-asmflags", "-gccgoflags", "-o", "-p", "-mod",
                            "-modfile", "-pkgdir", "-buildmode", "-compiler", "-installsuffix", "-overlay",
                            "-pgo", "-toolexec"])
GEM_VALUE_FLAGS = frozenset(["-v", "--version", "-s", "--source", "-i", "--install-dir", "-n", "--bindir",
                             "--platform", "-P", "--trust-policy", "-p", "--http-proxy", "--config-file",
                             "--build-root"])

NON_REGISTRY_PREFIXES = ("workspace:", "file:", "link:", "git+", "git:", "git@", "github:", "gitlab:",
                         "bitbucket:", "gist:", "http:", "https:", "ssh:", "./", "../", "/", "~/")
ARCHIVE_SUFFIXES = (".tgz", ".tar.gz", ".tar", ".zip", ".whl")
# Where a pip requirement's NAME ends; a `/` before this point is a directory, not a name.
PYPI_NAME_END_RE = re.compile(r"[=<>!~;@\[ ]")

# Wrappers this classifier strips beyond shell_segments.WRAPPERS (card: env, sudo, timeout, nice).
WRAPPER_VALUE_OPTS = {
    "env": frozenset(["-u", "-C", "-S", "--unset", "--chdir", "--split-string"]),
    "sudo": frozenset(["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-T", "-U", "-R", "--user", "--group",
                       "--host", "--prompt", "--chdir", "--role", "--type"]),
    "timeout": frozenset(["-s", "-k", "--signal", "--kill-after"]),
    "nice": frozenset(["-n", "--adjustment"]),
}
WRAPPER_LEADING_POSITIONALS = {"timeout": 1}  # timeout's DURATION


# ------------------------------------------------------------------------------------------ options
def _read_option(args, index, value_flags):
    """-> (flag, value, tokens consumed) for the dash-argument at args[index]."""
    arg = args[index]
    if "=" in arg:
        flag, _, value = arg.partition("=")
        if arg.startswith("--") or flag in value_flags:
            return flag, value, 1
    if arg in value_flags:
        if index + 1 < len(args):
            return arg, args[index + 1], 2
        return arg, None, 1
    if not arg.startswith("--") and len(arg) > 2 and arg[:2] in value_flags:
        return arg[:2], arg[2:], 1
    return arg, None, 1


def _scan(args, value_flags, first_only=False):
    """-> (items, rest). items is ordered: (None, positional) or (flag, value-or-None).

    first_only stops after the first positional (the subcommand, or a runner's package) and returns
    everything after it as `rest`; the words there belong to the command being run, not to us.
    """
    items = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "--":
            tail = args[i + 1:]
            if first_only:
                return (items + [(None, tail[0])], tail[1:]) if tail else (items, [])
            return items + [(None, a) for a in tail], []
        if arg.startswith("-") and len(arg) > 1:
            flag, value, step = _read_option(args, i, value_flags)
            items.append((flag, value))
            i += step
            continue
        items.append((None, arg))
        i += 1
        if first_only:
            return items, args[i:]
    return items, []


def _positionals(items):
    return [value for flag, value in items if flag is None]


def _subcommand(args, value_flags):
    items, rest = _scan(args, value_flags, first_only=True)
    found = _positionals(items)
    return (found[0] if found else None), rest


# ------------------------------------------------------------------------------------ readings
class _ReadingCapExceeded(Exception):
    """One command needed more than MAX_READINGS readings (R3)."""


class _Readings:
    """Counts the readings started for one command, across every scan and nested exec (R3). `outer` is the
    first node package manager reached; it names the cannot-read intent a spent budget turns into."""

    def __init__(self):
        self.count, self.outer = 0, None

    def spend(self):
        self.count += 1
        if self.count > MAX_READINGS:
            raise _ReadingCapExceeded()


def _merge_readings(readings):
    """R3/R9: the intents of several readings of one command. A distinct intent keeps the largest number of
    copies any ONE reading gave it, so `npm i x x` stays two intents; a single reading comes back unchanged."""
    merged, have = [], collections.Counter()
    for intents in readings:
        seen = collections.Counter()
        for intent in intents:
            key = tuple(sorted(intent.items()))
            seen[key] += 1
            if seen[key] > have[key]:
                have[key] = seen[key]
                merged.append(intent)
    return merged


def _is_option(arg):
    return arg.startswith("-") and len(arg) > 1


def _may_take_value(args, i):
    """R3/R9: an option word with no `=` and a non-option word after it may be read as taking that word."""
    return "=" not in args[i] and i + 1 < len(args) and not args[i + 1].startswith("-")


def _end_reading(budget, words, flags):
    budget.spend()
    return [(words[0], words[1:], tuple(flags))] if words else [(None, [], tuple(flags))]


def _sub_readings(prog, args, budget, flags=()):
    """R9: every reading of the words before the subcommand -> [(sub, rest, option flags seen)], today's
    reading (`_subcommand`'s) first. An option that may take a value is read as taking it and as standing
    alone, so a width the lists get wrong cannot hide the subcommand; one branch ends at the next word, so
    k such options give k + 1 readings. A program outside WIDTH_PROGRAMS (bun) keeps its single reading."""
    if prog not in WIDTH_PROGRAMS:
        budget.spend()
        sub, rest = _subcommand(args, NODE_VALUE_FLAGS)
        return [(sub, rest, ())]
    flags, i = list(flags), 0
    while i < len(args):
        if args[i] == "--":
            return _end_reading(budget, args[i + 1:], flags)
        if not _is_option(args[i]):
            return _end_reading(budget, args[i:], flags)
        flag, _value, step = _read_option(args, i, NODE_VALUE_FLAGS)
        flags.append(flag)
        if _may_take_value(args, i):
            alone = _end_reading(budget, args[i + 1:], flags)
            valued = _sub_readings(prog, args[i + 2:], budget, flags)
            return valued + alone if step == 2 else alone + valued
        i += step
    return _end_reading(budget, [], flags)


# ------------------------------------------------------------------------------------ spec parsing
def _non_registry(spec):
    if spec in (".", "..") or spec.startswith(NON_REGISTRY_PREFIXES) or "://" in spec:
        return True
    if spec.endswith(ARCHIVE_SUFFIXES):
        return True
    return False


def _parse_npm(spec):
    # npm's bare `owner/repo[#ref]` is a GitHub source (spec, "Not from a registry"). An account name
    # has no dots, so `3.23.8/../evil` is no shorthand: it stays an unpinned registry intent.
    if _non_registry(spec) or is_npm_git_shorthand(spec):
        return spec, None, OTHER
    at = spec.find("@", 1)
    if at == -1:
        return spec, None, REGISTRY
    name, version = spec[:at], spec[at + 1:]
    if version.startswith("npm:"):  # alias: the real package is what gets fetched
        return _parse_npm(version[len("npm:"):])
    if _non_registry(version) or is_npm_git_shorthand(version):
        return spec, None, OTHER
    return name, version or None, REGISTRY


_PYPI_SPEC_RE = re.compile(r"([A-Za-z0-9][A-Za-z0-9._-]*)\s*(\[[^\]]*\])?\s*(.*)")


def _pypi_parser(allow_at=False):
    """allow_at: poetry spells a version `name@1.2.3`; elsewhere `@` only starts a direct reference."""
    def parse(spec):
        if _non_registry(spec) or "/" in PYPI_NAME_END_RE.split(spec, 1)[0]:
            return spec, None, OTHER  # pip reads an argument with a `/` in its name as a directory
        match = _PYPI_SPEC_RE.fullmatch(spec.split(";", 1)[0].strip())
        if not match:
            return spec, None, REGISTRY
        name, _, rest = match.groups()
        rest = rest.strip()
        if allow_at and rest.startswith("@"):
            version = rest[1:].strip()
            return (spec, None, OTHER) if _non_registry(version) else (name, version or None, REGISTRY)
        if rest.startswith("==") and not rest.startswith("==="):
            return name, rest[2:].strip() or None, REGISTRY
        return name, rest.replace(" ", "") or None, REGISTRY
    return parse


def _cargo_parser(install, default_version):
    """The version as Cargo reads it: `=` makes it exact; `add name@1.2.3` is a caret requirement."""
    def parse(spec):
        if _non_registry(spec):
            return spec, None, OTHER
        name, at, version = spec.partition("@")
        version = (version if at else default_version or "").strip()
        if version.startswith("="):
            version = version[1:].strip()
        elif version[:1].isdigit() and not install:
            version = "^" + version
        return name, version or None, REGISTRY
    return parse


def _go_parser(spec):
    if _non_registry(spec):
        return spec, None, OTHER
    name, _, version = spec.partition("@")
    return name, version or None, REGISTRY


def _gem_parser(default_version):
    def parse(spec):
        if _non_registry(spec) or spec.endswith(".gem"):
            return spec, None, OTHER
        name, sep, version = spec.partition(":")
        return name, (version if sep else default_version) or None, REGISTRY
    return parse


def _brew_parser(spec):
    if _non_registry(spec) or spec.endswith(".rb"):
        return spec, None, OTHER
    return spec, None, REGISTRY


# --------------------------------------------------------------------------------------- intents
def _update_intent(prog, name, update_form):
    """An update or upgrade: no version the guard can vet. update_form is the tool plus the words of
    the matched table entry, the <form> of the ask text."""
    return {"ecosystem": TOOL_ECOSYSTEM[prog], "name": name, "version": None, "pinned": False, "tool": prog,
            "runner": None, "form": "add", "source": UPDATE, "exempt": None, "via_package_option": False,
            "update_form": update_form}


def _update_intents(prog, form_words, names):
    """One intent per package, or one named after the tool when there are none (it updates everything)."""
    form = " ".join([prog] + list(form_words))
    return [_update_intent(prog, name, form) for name in (names or [prog])]


def _plain_update(prog, form_words, rest, value_flags, extra_names=None):
    """An update form whose packages are the positionals (plus extra_names(items), when given). A help
    invocation updates nothing."""
    items, _ = _scan(rest, value_flags)
    if any(flag in HELP_FLAGS for flag, _value in items):
        return []
    names = _positionals(items) + (extra_names(items) if extra_names else [])
    return _update_intents(prog, form_words, names)


def _indirect_intent(tool):
    return {"ecosystem": TOOL_ECOSYSTEM[tool], "name": tool, "version": None, "pinned": False, "tool": tool,
            "runner": None, "form": "add", "source": INDIRECT, "exempt": None, "via_package_option": False}


def _runner_name(prog, sub=None):
    name = prog if sub is None else "{} {}".format(prog, sub)
    if name not in RUNNERS:
        raise ValueError("runner {!r} is not in RUNNERS".format(name))
    return name


def _intent(ecosystem, parsed, tool, runner=None, via_package_option=False):
    """`exempt` is filled in by classify(), which is the only place that knows the owning segment."""
    name, version, source = parsed
    pinned = source == REGISTRY and version is not None and is_exact_version(ecosystem, version)
    return {"ecosystem": ecosystem, "name": name, "version": version, "pinned": pinned, "tool": tool,
            "runner": runner, "form": "run" if runner else "add", "source": source, "exempt": None,
            "via_package_option": via_package_option}


def _other(ecosystem, value, tool, runner=None):
    return _intent(ecosystem, (value, None, OTHER), tool, runner)


def _intents(ecosystem, specs, parse, tool, runner=None):
    return [_intent(ecosystem, parse(spec), tool, runner) for spec in specs]


# --------------------------------------------------------------------------------------- handlers
def _runner_intents(prog, runner, args, ecosystem, value_flags=None):
    """A runner fetches and runs a package. The first non-flag word names it; for npm-registry
    runners every -p/--package value does too. Words after the package are its own arguments.
    value_flags overrides the default set of the ecosystem (pnpm's widths, R9)."""
    npm_registry = ecosystem == ECO_NPM
    if value_flags is None:
        value_flags = NPM_RUNNER_VALUE_FLAGS if npm_registry else PYPI_RUNNER_VALUE_FLAGS
    items, _ = _scan(args, value_flags, first_only=True)
    parse = _parse_npm if npm_registry else _pypi_parser()
    found = []
    for flag, value in items:
        via_option = npm_registry and flag in NPM_PACKAGE_FLAGS and bool(value)
        if flag is None or via_option:
            found.append(_intent(ecosystem, parse(value), prog, runner, via_package_option=via_option))
    return found


def _yarn_wrapper(prog, sub, rest, budget):
    """-> [(wrapper words, inner sub, inner rest)]: one yarn workspace wrapper removed. `yarn workspace
    <name> <rest>` and `yarn workspaces foreach [options] <rest>` run `yarn <rest>`. yarn 1 `workspaces
    run` is a script run and `workspaces info|list` only read, so they carry no inner command (sub None).
    The `foreach` option loop keeps its single reading (R9: `--since main up` must stay allowed)."""
    found = []
    for first, after, _flags in _sub_readings(prog, rest, budget):  # the workspace name, or the verb
        if sub == "workspace":
            words, tail = ["workspace"], after
        elif first == "foreach":
            i = 0
            while i < len(after) and _is_option(after[i]):
                i += 2 if after[i] in FOREACH_VALUE_FLAGS else 1
            words, tail = ["workspaces", "foreach"], after[i:]
        else:
            found.append(([], None, []))
            continue
        found += [(words, inner, inner_rest) for inner, inner_rest, _f in _sub_readings(prog, tail, budget)]
    return found


def _unwrap(prog, words, sub, rest, flags, budget):
    """R4: -> [(words, sub, rest, flags)] with yarn workspace wrappers removed until none is left, in any
    order. `words` keeps every wrapper word, never a workspace name (R5). `yarn global add` is `add`."""
    if prog in YARN_PROGRAMS and sub in ("workspace", "workspaces"):
        return [r for inner, sub2, rest2 in _yarn_wrapper(prog, sub, rest, budget)
                for r in _unwrap(prog, words + inner, sub2, rest2, flags, budget)]
    if prog in YARN_PROGRAMS and sub == "global":
        return [(words + ["global", sub2], sub2, rest2, flags) for sub2, rest2, _f in _sub_readings(prog, rest, budget)]
    return [(words + [sub], sub, rest, flags)]


def _alias_readings(prog, reading, budget):
    """R10: pnpm's `recursive`/`multi`/`m` is `--recursive` while another positional follows, and adds no word."""
    sub, rest, flags = reading
    if prog in PNPM_PROGRAMS and sub in PNPM_RECURSIVE_ALIASES:
        inner = [r for r in _sub_readings(prog, rest, budget, flags) if r[0] is not None]
        if inner:
            return [r for each in inner for r in _alias_readings(prog, each, budget)]
    return [reading]


def _cannot_read_intent(prog):
    """R2/R3: the guard's cannot-read ask, for an exec string the lexer cannot read or a spent budget."""
    return {"ecosystem": ECO_NPM, "name": prog, "version": None, "pinned": False, "tool": prog, "runner": None,
            "form": "add", "source": CANNOT_READ, "exempt": None, "via_package_option": False}


def _exec_readings(prog, args, shell, budget):
    """R3: -> [(shell mode, command words)], every reading of the words after `exec`. One `--` is dropped; a
    pnpm -c/--shell-mode turns shell mode on (a known boolean); any other option that may take a value is
    read as standing alone (the next word is the command) and as taking it."""
    found, i = [], 0
    while i < len(args):
        if args[i] == "--":
            i += 1
            break
        if not _is_option(args[i]):
            break
        if prog in PNPM_PROGRAMS and args[i] in SHELL_MODE_FLAGS:
            shell = True
        elif _may_take_value(args, i):
            budget.spend()
            found.append((shell, args[i + 1:]))
            i += 1
        i += 1
    if i < len(args):
        budget.spend()
        found.append((shell, args[i:]))
    return found


def _exec_command(prog, shell, words, budget):
    """R2: the command word is shell code (as in yarn 4): lexed, the arguments appended to the argv of its last
    segment, every segment classified. Shell mode joins all the words with single spaces first (as pnpm does)."""
    text, extra = (" ".join(words), []) if shell else (words[0], words[1:])
    parsed = segments(text)
    if text.strip() and not parsed:
        return [_cannot_read_intent(prog)] if mentions_install_tool(" ".join(words)) else []
    last = len(parsed) - 1
    return [intent for n, (_assigns, argv) in enumerate(parsed)
            for intent in _classify_argv(argv + (extra if n == last else []), budget)]


def _exec_intents(prog, args, flags, budget):
    shell = prog in PNPM_PROGRAMS and any(flag in SHELL_MODE_FLAGS for flag in flags)
    return _merge_readings([_exec_command(prog, sh, words, budget)
                            for sh, words in _exec_readings(prog, args, shell, budget)])


def _node_intents(prog, reading, budget):
    """The intents of one reading (words, sub, rest, flags). pnpm's own words get two widths (R9)."""
    words, sub, rest, flags = reading
    install_words, run_words = NODE_MANAGERS[prog]
    pnpm = prog in PNPM_PROGRAMS
    widths = [NODE_VALUE_FLAGS] + ([PNPM_VALUE_FLAGS] if pnpm else [])
    if sub == "exec" and prog in EXEC_PROGRAMS:
        return _exec_intents(prog, rest, flags, budget)
    if sub in run_words:
        runner = _runner_name(prog, sub)
        return _merge_readings([_runner_intents(prog, runner, rest, ECO_NPM, w)
                                for w in [NPM_RUNNER_VALUE_FLAGS] + ([PNPM_RUNNER_VALUE_FLAGS] if pnpm else [])])
    if sub in NODE_UPDATE_WORDS[prog]:
        return _merge_readings([_plain_update(prog, words, rest, w) for w in widths])
    if sub == "audit":
        return _audit_fix(prog, rest, budget)
    if sub not in install_words:
        return []
    return _merge_readings([_intents(ECO_NPM, _positionals(_scan(rest, w)[0]), _parse_npm, prog) for w in widths])


def _node_manager(prog, args, budget):
    """npm, yarn, pnpm, bun: every reading of the words before the subcommand (R9, R10, R4), merged (R3)."""
    if budget.outer is None:
        budget.outer = prog
    aliased = [r for first in _sub_readings(prog, args, budget) for r in _alias_readings(prog, first, budget)]
    readings = [r for sub, rest, flags in aliased for r in _unwrap(prog, [], sub, rest, flags, budget)]
    return _merge_readings([_node_intents(prog, reading, budget) for reading in readings])


def _audit_fix(prog, rest, budget):
    """npm `audit fix` (any options) and pnpm/pn `audit --fix` rewrite installed versions."""
    if prog == "npm":
        return _merge_readings([_plain_update(prog, ["audit", "fix"], fix_rest, NODE_VALUE_FLAGS)
                                for fix, fix_rest, _f in _sub_readings(prog, rest, budget) if fix == "fix"])
    if prog in PNPM_PROGRAMS:
        return _merge_readings([_plain_update(prog, ["audit", "--fix"], rest, w) for w in (NODE_VALUE_FLAGS, PNPM_VALUE_FLAGS)
                                if any(flag == "--fix" for flag, _value in _scan(rest, w)[0])])
    return []


def _pip_install(prog, args):
    items, _ = _scan(args, PIP_VALUE_FLAGS)
    return _pypi_items(prog, items, _pypi_parser(), skip_local_dot=True)


def _pypi_items(prog, items, parse, skip_local_dot=False):
    found = []
    for flag, value in items:
        if flag in REQUIREMENT_FLAGS and value:
            found.append(_intent(ECO_PYPI, (value, None, REQUIREMENTS_FILE), prog))
        elif flag is None or (flag in EDITABLE_FLAGS and value):
            if skip_local_dot and (value == "." or value.startswith(".[")):
                continue
            found.append(_intent(ECO_PYPI, parse(value), prog))
    return found


def _pypi_add(prog, args, allow_at=False):
    items, _ = _scan(args, PYPI_ADD_VALUE_FLAGS)
    flags = {flag: value for flag, value in items if flag}
    source_values = [flags[f] for f in SOURCE_FLAGS if flags.get(f)]
    if source_values:
        names = _positionals(items) or source_values[:1]
        return [_other(ECO_PYPI, name, prog) for name in names]
    return _pypi_items(prog, items, _pypi_parser(allow_at))


def _pip(prog, args):
    sub, rest = _subcommand(args, PIP_VALUE_FLAGS)
    return _pip_install(prog, rest) if sub == "install" else []


def _python(prog, args):
    """`python [flags] -m pip install ...`; anything else python runs is not ours to read."""
    for i, arg in enumerate(args):
        module = None
        if arg == "-m" and i + 1 < len(args):
            module, rest = args[i + 1], args[i + 2:]
        elif arg.startswith("-m") and len(arg) > 2:
            module, rest = arg[2:], args[i + 1:]
        elif arg in ("-X", "-W"):
            continue
        elif not arg.startswith("-"):
            return []
        if module is not None:
            return _pip(prog, rest) if module == "pip" else []
    return []


def _uv_upgrades(prog, sub, rest):
    """`uv lock|sync|add|run` carrying an upgrade flag. For `run` only the options before the command
    are uv's own. The -P/--upgrade-package value is the package; an --upgrade-group value is not."""
    items, _ = _scan(rest, PYPI_RUNNER_VALUE_FLAGS, first_only=sub == "run")
    if any(flag in HELP_FLAGS for flag, _value in items):
        return []
    triggers = UV_UPGRADE_FLAGS | UV_UPGRADE_PACKAGE_FLAGS | {UV_UPGRADE_GROUP_FLAG}
    matched = [flag for flag, _value in items if flag in triggers]
    if not matched:
        return []
    packages = [value for flag, value in items if flag in UV_UPGRADE_PACKAGE_FLAGS and value]
    return _update_intents(prog, [sub, matched[0]], packages)


def _uv(prog, args):
    sub, rest = _subcommand(args, PYPI_RUNNER_VALUE_FLAGS)
    if sub == "pip":
        return _pip(prog, rest)
    if sub == "add":
        return _pypi_add(prog, rest) + _uv_upgrades(prog, sub, rest)
    if sub in UV_UPGRADING_SUBCOMMANDS:
        return _uv_upgrades(prog, sub, rest)
    if sub == "tool":
        tool_sub, tool_rest = _subcommand(rest, PYPI_RUNNER_VALUE_FLAGS)
        if tool_sub == "upgrade":
            return _plain_update(prog, ["tool", "upgrade"], tool_rest, PYPI_RUNNER_VALUE_FLAGS)
        if tool_sub == "run":
            return _runner_intents(prog, _runner_name(prog, "tool run"), tool_rest, ECO_PYPI)
        if tool_sub == "install":
            return _pypi_add(prog, tool_rest)
    return []


def _poetry(prog, args):
    sub, rest = _subcommand(args, PYPI_ADD_VALUE_FLAGS)
    if sub == "update":
        return _plain_update(prog, [sub], rest, PYPI_ADD_VALUE_FLAGS)
    return _pypi_add(prog, rest, allow_at=True) if sub == "add" else []


def _pipx(prog, args):
    sub, rest = _subcommand(args, PYPI_RUNNER_VALUE_FLAGS)
    if sub == "run":
        return _runner_intents(prog, _runner_name(prog, "run"), rest, ECO_PYPI)
    if sub in PIPX_UPDATE_WORDS:
        return _plain_update(prog, [sub], rest, PYPI_RUNNER_VALUE_FLAGS)
    return _pypi_add(prog, rest) if sub == "install" else []


def _cargo_package_values(items):
    return [value for flag, value in items if flag in ("-p", "--package") and value]


def _cargo(prog, args):
    while args and args[0].startswith("+"):  # `cargo +nightly ...` toolchain selector
        args = args[1:]
    sub, rest = _subcommand(args, CARGO_VALUE_FLAGS)
    if sub == "update":
        return _plain_update(prog, [sub], rest, CARGO_VALUE_FLAGS, _cargo_package_values)
    if sub not in ("add", "install"):
        return []
    items, _ = _scan(rest, CARGO_VALUE_FLAGS)
    flags = {flag: value for flag, value in items if flag}
    specs = _positionals(items)
    source_values = [flags[f] for f in SOURCE_FLAGS if flags.get(f)]
    if source_values:
        return [_other(ECO_CRATES, name, prog) for name in (specs or source_values[:1])]
    install = sub == "install"
    parse = _cargo_parser(install, flags.get("--version") if install else None)
    return _intents(ECO_CRATES, specs, parse, prog)


def _go(prog, args):
    sub, rest = _subcommand(args, GO_VALUE_FLAGS)
    if sub not in ("get", "install"):
        return []
    items, _ = _scan(rest, GO_VALUE_FLAGS)
    found = _intents(ECO_GO, _positionals(items), _go_parser, prog)
    upgrade = [flag for flag, _value in items if _is_go_upgrade_flag(flag)]
    if sub == "get" and upgrade and not any(flag in HELP_FLAGS for flag, _value in items):
        found += _update_intents(prog, ["get", upgrade[0]], _positionals(items))
    return found


def _is_go_upgrade_flag(flag):
    return bool(flag) and (flag in ("-u", "--u") or flag.startswith(("-u=", "--u=")))


def _gem(prog, args):
    sub, rest = _subcommand(args, GEM_VALUE_FLAGS)
    if sub == "update":
        return _plain_update(prog, [sub], rest, GEM_VALUE_FLAGS)
    if sub != "install":
        return []
    if "--" in rest:  # build options follow
        rest = rest[:rest.index("--")]
    items, _ = _scan(rest, GEM_VALUE_FLAGS)
    flags = {flag: value for flag, value in items if flag}
    version = flags.get("-v") or flags.get("--version")
    return _intents(ECO_GEMS, _positionals(items), _gem_parser(version), prog)


def _brew(prog, args):
    sub, rest = _subcommand(args, frozenset())
    if sub == "upgrade":
        return _plain_update(prog, [sub], rest, frozenset())
    if sub not in ("install", "reinstall"):
        return []
    items, _ = _scan(rest, frozenset())
    return _intents(ECO_BREW, _positionals(items), _brew_parser, prog)


def _corepack(args, budget):
    """`corepack <manager>[@<version>] <args>` runs that manager; read it as the manager."""
    sub, rest = _subcommand(args, frozenset())
    if sub is None:
        return []
    return _classify_argv([sub.split("@", 1)[0]] + rest, budget)


# -------------------------------------------------------------------------------------- dispatch
def _family(prog):
    """pip3.11 -> pip, python3.12 -> python; anything else is its own name."""
    if re.fullmatch(r"pip[0-9]*(\.[0-9]+)*", prog):
        return "pip"
    if re.fullmatch(r"python[0-9]*(\.[0-9]+)*", prog):
        return "python"
    return prog


def _skip_wrapper(prog, args):
    value_opts = WRAPPER_VALUE_OPTS[prog]
    leading = WRAPPER_LEADING_POSITIONALS.get(prog, 0)
    options_done = False
    i = 0
    while i < len(args):
        arg = args[i]
        if not options_done and arg == "--":
            options_done = True
        elif not options_done and arg.startswith("-") and len(arg) > 1:
            i += 1 if "=" in arg or arg not in value_opts else 2
            continue
        elif ASSIGN_RE.match(arg):
            pass
        elif leading:
            leading -= 1
        else:
            break
        i += 1
    return args[i:]


def _strip_wrappers(argv):
    while argv:
        prog = program(argv[0])
        if prog in WRAPPERS:
            argv = argv[1:]
        elif prog in WRAPPER_VALUE_OPTS:
            argv = _skip_wrapper(prog, argv[1:])
        else:
            break
        while argv and ASSIGN_RE.match(argv[0]):
            argv = argv[1:]
    return argv


def _xargs(args):
    """An xargs segment naming an install tool word anywhere after it (card: options are not parsed, so
    an xargs that merely mentions one also asks -- accepted). <tool> is the first such word."""
    for word in args:
        tool = program(word)
        if tool in INSTALL_TOOL_WORDS:
            return [_indirect_intent(tool)]
    return []


def _classify_argv(argv, budget):
    argv = _strip_wrappers(argv)
    if not argv:
        return []
    prog, args = program(argv[0]), argv[1:]
    family = _family(prog)
    if prog == "xargs":
        return _xargs(args)
    if prog in NODE_MANAGERS:
        return _node_manager(prog, args, budget)
    if prog in WHOLE_PROGRAM_RUNNERS:
        return _runner_intents(prog, _runner_name(prog), args, WHOLE_PROGRAM_RUNNERS[prog])
    if family == "pip":
        return _pip(prog, args)
    if family == "python":
        return _python(prog, args)
    handlers = {"uv": _uv, "poetry": _poetry, "pipx": _pipx, "cargo": _cargo, "go": _go, "gem": _gem,
                "brew": _brew}
    if prog == "corepack":
        return _corepack(args, budget)
    return handlers[prog](prog, args) if prog in handlers else []


# ---------------------------------------------------------------------------------------- public
def _exempt_value(assigns):
    """The VET_EXEMPT value from THIS segment's own prefix assignments, else None. Exact name only;
    an assignment made by env or sudo is not the segment's own and is not read."""
    value = assigns.get(EXEMPT_VAR, "")
    return value if EXEMPT_VALUE_RE.fullmatch(value) else None


def _classify_segment(argv):
    """The intents of one segment. One that needs more than MAX_READINGS readings (R3) is replaced, whole, by
    the cannot-read intent: asking is the fail-safe answer, and it can never hide a deny."""
    budget = _Readings()
    try:
        return _classify_argv(argv, budget)
    except _ReadingCapExceeded:
        return [_cannot_read_intent(budget.outer)]


def classify(src):
    """Return the install intents of every segment of `src`, in command order. [] when there are none
    -- including when the lexer cannot read `src` (see is_unreadable)."""
    intents = []
    for assigns, argv in segments(src):
        exempt = _exempt_value(assigns)
        intents.extend(dict(intent, exempt=exempt) for intent in _classify_segment(argv))
    return intents


def is_unreadable(src):
    """True when `src` has text but the lexer cannot read it (segments() == [])."""
    return bool(src.strip()) and segments(src) == []


def mentions_install_tool(src):
    """True when `src` holds an INSTALL_TOOL_WORDS member as a whole word, in any letter case."""
    return _TOOL_WORD_RE.search(src) is not None
