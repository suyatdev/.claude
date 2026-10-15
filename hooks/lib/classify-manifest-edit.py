#!/usr/bin/env python3
"""Classify an Edit/Write aimed at a dependency manifest: which dependencies does it ADD or CHANGE?

Used by hooks/dependency-guard.sh (docs/features/dependency-vetting-guard.md, "Manifest edits").
Reads a hook payload ({"tool_name", "tool_input"}) on stdin and writes one JSON list to stdout.
Exit 2 with a message on stderr when the payload is malformed or the current file cannot be read;
the hook turns that into its "dependency-guard is broken" ask.

Each list item is one of two shapes, told apart by "kind":

  {"kind": "dependency", ...}  the install-intent contract: ecosystem, name, version, pinned, tool,
                               runner (always null), form (always "add"), source. `tool` is the
                               manifest ("package.json", "requirements.txt", "pyproject.toml").
  {"kind": "warning", "code", "file", "message"}  the edit cannot be read as dependencies; the hook
                               asks Mark with `message`.

Pure apart from one injected call: `read_file(path)` returns the file's current text, or None when
it does not exist. The spec needs it to compute an Edit's result and to tell what is NEW; tests
inject a dict lookup.

"pinned" comes from `is_exact_version` in vetting_record.py, the spec's one definition.
"""

import importlib.util
import json
import os
import re
import sys

KIND_DEPENDENCY = "dependency"
KIND_WARNING = "warning"

CODE_DEPENDENCY_FILE = "dependency-file-edit"
CODE_UNREADABLE_JSON = "unreadable-json"
CODE_UNREADABLE_LINE = "unreadable-line"
CODE_UNREADABLE_PYPROJECT = "unreadable-pyproject"
CODE_UNREADABLE_EDIT = "unreadable-edit"

TOOL_EDIT, TOOL_WRITE, TOOL_NOTEBOOK = "Edit", "Write", "NotebookEdit"
MAX_QUOTED_CHARS = 200  # how much of an offending line a warning message repeats

NPM_SECTIONS = ("dependencies", "devDependencies", "optionalDependencies", "peerDependencies")
# Spec "Manifest edits": exactly these basenames, never a substring match (`clock.js`).
UNPARSED_BASENAMES = frozenset([
    "cargo.toml", "go.mod", "gemfile", "gemfile.lock", "package-lock.json", "npm-shrinkwrap.json",
    "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock", "poetry.lock", "uv.lock", "pipfile.lock",
    "cargo.lock", "go.sum"])
REQUIREMENTS_RE = re.compile(r"requirements.*\.txt")

# npm values that are not registry packages (Contracts, `source: other`). GitHub shorthand
# (`user/repo`) is deliberately absent: the spec's list omits it, so it is an unpinned registry
# value and is refused, not asked about.
NPM_OTHER_PREFIXES = ("workspace:", "file:", "link:", "git+", "git://", "git@", "ssh://", "github:",
                      "gitlab:", "bitbucket:", "gist:", "http://", "https://", "./", "../", "/", "~/")
NPM_OTHER_SUFFIXES = (".tgz", ".tar.gz", ".tar")
# npm's bare `owner/repo[#ref]` means GitHub (Mark 2026-10-14). Matched against the manifest VALUE
# only: a scope (`@scope/name`) starts with `@`, and each part must start alphanumeric, so
# `1.0.0/..` and `a/b/c` are not shorthand and stay unpinned registry values.
NPM_SHORTHAND_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*(?:#.*)?")

# The one definition of "pinned" lives in vetting_record.py. Loaded by path because the hyphenated
# sibling modules are not importable by name and `python3 -I` does not put this directory on sys.path.
_VETTING_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vetting_record.py")
_VETTING_SPEC = importlib.util.spec_from_file_location("vetting_record", _VETTING_PATH)
_VETTING = importlib.util.module_from_spec(_VETTING_SPEC)
_VETTING_SPEC.loader.exec_module(_VETTING)
is_exact_version = _VETTING.is_exact_version


class _Unreadable(Exception):
    """A construct the minimal readers cannot interpret; carries the text for the warning."""


def read_current_file(path):
    """Current text of `path`, or None when it does not exist. Other errors propagate."""
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    except FileNotFoundError:
        return None


def _warning(base, code, message):
    return {"kind": KIND_WARNING, "code": code, "file": base, "message": message}


def _clip(text):
    return text if len(text) <= MAX_QUOTED_CHARS else text[:MAX_QUOTED_CHARS] + "..."


def _dependency(ecosystem, tool, name, version, source="registry"):
    return {"kind": KIND_DEPENDENCY, "ecosystem": ecosystem, "name": name, "version": version,
            "pinned": source == "registry" and is_exact_version(ecosystem, version), "tool": tool,
            "runner": None, "form": "add", "source": source,
            # A manifest edit can never carry VET_EXEMPT or come from -p/--package (Contracts).
            "exempt": None, "via_package_option": False}


# ---- package.json ---------------------------------------------------------------------------

def _load_npm_sections(text):
    try:
        doc = json.loads(text)
    except ValueError as exc:
        raise _Unreadable("not valid JSON ({})".format(exc))
    if not isinstance(doc, dict):
        raise _Unreadable("the top level is not an object")
    sections = {}
    for section in NPM_SECTIONS:
        table = doc.get(section, {})
        if not isinstance(table, dict):
            raise _Unreadable("{} is not an object".format(section))
        for key, value in table.items():
            if not isinstance(value, str):
                raise _Unreadable("{}.{} is not a string".format(section, key))
        sections[section] = table
    return sections


def _is_non_registry(spec):
    """A git URL, git-host shorthand, URL, tarball or local path -- not a registry version or name."""
    lowered = spec.lower()
    return (lowered.startswith(NPM_OTHER_PREFIXES) or lowered.endswith(NPM_OTHER_SUFFIXES)
            or NPM_SHORTHAND_RE.fullmatch(spec) is not None)


def _npm_dependency(key, value):
    if _is_non_registry(value):
        return _dependency("npm", "package.json", key, value, "other")
    if not value.lower().startswith("npm:"):
        return _dependency("npm", "package.json", key, value)
    spec = value[len("npm:"):]
    at = spec.rfind("@")
    version = spec[at + 1:] if at > 0 else None  # an index of 0 is the scope marker
    # Such a value is `source: other` wherever it sits (card, "Not from a registry"), so an alias
    # whose target or version is one is reported as written, under the manifest key.
    if _is_non_registry(spec) or (version is not None and _is_non_registry(version)):
        return _dependency("npm", "package.json", key, value, "other")
    return _dependency("npm", "package.json", spec[:at] if at > 0 else spec, version)


def _classify_package_json(base, old, new):
    try:
        new_sections = _load_npm_sections(new)
    except _Unreadable as exc:
        return [_warning(base, CODE_UNREADABLE_JSON,
                         "{} cannot be read as JSON dependencies: {}".format(base, exc))]
    try:
        old_sections = _load_npm_sections(old) if old is not None else {}
    except _Unreadable:
        old_sections = {}  # nothing readable to diff against: every dependency counts as added
    found = []
    for section in NPM_SECTIONS:
        before = old_sections.get(section, {})
        for key, value in new_sections[section].items():
            if key not in before or before[key] != value:
                found.append(_npm_dependency(key, value))
    return found


# ---- requirements.txt and PEP 508 strings ---------------------------------------------------

_COMMENT_RE = re.compile(r"(?:^|\s)#.*$")
_OPTION_RE = re.compile(r"\s--\S.*$")
_REQ_NAME_RE = re.compile(r"([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*(.*)")
_OTHER_SPECIFIER_STARTS = ("===", "!=", "~=", "<", ">", "(")


def _logical_lines(text):
    """Backslash continuations joined and blank lines dropped.

    A whole-line comment is kept as written (card line 531 asks about added or changed comments);
    a trailing comment on a requirement is stripped, so it never makes a requirement look changed."""
    joined, pending = [], ""
    for raw in text.splitlines():
        if raw.endswith("\\"):
            pending += raw[:-1] + " "
            continue
        joined.append(pending + raw)
        pending = ""
    if pending:
        joined.append(pending)
    stripped = (j.strip() for j in joined)
    return [line if line.startswith("#") else _COMMENT_RE.sub("", line).strip() for line in stripped if line]


def _parse_requirement(line, base):
    """One requirement -> a dependency, or a warning for anything not `name[extras][specifier]`."""
    unreadable = _warning(base, CODE_UNREADABLE_LINE,
                          "{} line {!r} is not a plain `name==version` requirement (a comment, option, "
                          "URL, path or direct reference); the guard cannot vet it".format(base, _clip(line)))
    if line.startswith(("-", "#")):
        return unreadable
    text = _OPTION_RE.sub("", line.split(";", 1)[0]).strip()
    match = _REQ_NAME_RE.fullmatch(text)
    if not match:
        return unreadable
    name, rest = match.group(1), match.group(2).strip()
    if not rest:
        version = None
    elif rest.startswith("==") and not rest.startswith("==="):
        version = rest[2:].strip()
    elif rest.startswith(_OTHER_SPECIFIER_STARTS):
        version = rest
    else:
        return unreadable
    return _dependency("pypi", base_tool(base), name, version)


def base_tool(base):
    return "requirements.txt" if REQUIREMENTS_RE.fullmatch(base.lower()) else base.lower()


def _classify_requirements(base, old, new):
    seen = set(_logical_lines(old or ""))
    found = []
    for line in _logical_lines(new):
        if line not in seen:
            seen.add(line)
            found.append(_parse_requirement(line, base))
    return found


# ---- pyproject.toml: a minimal line-oriented reader -----------------------------------------

POETRY_TABLE = "tool.poetry.dependencies"
_HEADER_RE = re.compile(r"(\[{1,2})([^\]]*)\]{1,2}\s*(?:#.*)?")
_STRING_TOKEN = r"\"(?:[^\"\\]|\\.)*\"|'[^']*'"
_STRING_VALUE_RE = re.compile(r"({})\s*(?:#.*)?".format(_STRING_TOKEN))
_BARE_KEY_RE = re.compile(r"[A-Za-z0-9_-]+")
_QUOTED_KEY_RE = re.compile(r"\"[^\"]*\"|'[^']*'")
_INLINE_KEY_RE = re.compile(r"(?:^\{{|,)\s*(git|path|url|version)\s*=\s*({})".format(_STRING_TOKEN))
_ROOT_KEYS = ("project", "tool", "poetry")


def _toml_string(token):
    if token.startswith("'"):
        return token[1:-1]
    try:
        return json.loads(token)  # TOML basic-string escapes are JSON's
    except ValueError:
        raise _Unreadable(token)


def _scan_array(text):
    """Strings of a TOML array of strings -> (items, closed). _Unreadable on anything else."""
    items, depth, need_separator, pos = [], 0, False, 0
    while pos < len(text):
        char = text[pos]
        if char.isspace() or (char == "," and need_separator and depth):
            need_separator = need_separator and char != ","
            pos += 1
        elif char == "#":
            pos = text.find("\n", pos) if "\n" in text[pos:] else len(text)
        elif char == "[" and depth == 0:
            depth, pos = 1, pos + 1
        elif char == "]" and depth == 1:
            tail = _COMMENT_RE.sub("", text[pos + 1:]).strip()
            if tail:
                raise _Unreadable(tail)
            return items, True
        elif char in "\"'" and depth == 1 and not need_separator:
            end = pos + 1
            while end < len(text) and text[end] != char:
                if text[end] == "\n":
                    raise _Unreadable(text[pos:end])
                end += 2 if (char == '"' and text[end] == "\\") else 1
            if end >= len(text):
                return items, False
            items.append(_toml_string(text[pos:end + 1]))
            need_separator, pos = True, end + 1
        else:
            raise _Unreadable(text[pos:pos + 20])
    return items, False


def _read_array(first, lines, index):
    """`dependencies = [...]`, possibly spanning lines -> (items, next line index)."""
    text = first
    while True:
        items, closed = _scan_array(text)
        if closed:
            return items, index
        if index >= len(lines):
            raise _Unreadable("unterminated array")
        text += "\n" + lines[index]
        index += 1


def _poetry_dependency(raw_key, value):
    """(name, (source, version)) for one `[tool.poetry.dependencies]` line."""
    key = raw_key.strip()
    if _QUOTED_KEY_RE.fullmatch(key):
        key = key[1:-1]
    elif not _BARE_KEY_RE.fullmatch(key):
        raise _Unreadable(raw_key)
    string = _STRING_VALUE_RE.fullmatch(value)
    if string:
        return key, ("registry", _toml_string(string.group(1)))
    end = value.rfind("}")
    if not value.startswith("{") or end < 0 or _COMMENT_RE.sub("", value[end + 1:]).strip():
        raise _Unreadable(value)
    fields = {k: _toml_string(v) for k, v in _INLINE_KEY_RE.findall(value[:end + 1])}
    for source_key in ("git", "path", "url"):
        if source_key in fields:
            return key, ("other", fields[source_key])
    if "version" in fields:
        return key, ("registry", fields["version"])
    raise _Unreadable(value)


def _hides_dependencies(section, key):
    """A line outside the two read tables that still declares dependencies (dotted or inline)."""
    first = key.split(".")[0].strip("\"' ")
    return "dependencies" in key or (section in ("", "tool") and first in _ROOT_KEYS)


def _read_pyproject(text):
    found = {"project": [], "poetry": {}, "unreadable": set()}
    if '"""' in text or "'''" in text:
        found["unreadable"].add("multi-line string")
    lines, section, index = text.splitlines(), "", 0
    while index < len(lines):
        stripped = lines[index].strip()
        index += 1
        if not stripped or stripped.startswith("#"):
            continue
        header = _HEADER_RE.fullmatch(stripped)
        if header:
            section = re.sub(r"[\s\"']", "", header.group(2))
            doubled = header.group(1) == "[["
            if section.startswith(POETRY_TABLE + ".") or (doubled and section in ("project", POETRY_TABLE)):
                found["unreadable"].add(stripped)
            continue
        key, equals, value = stripped.partition("=")
        key, value = key.strip(), value.strip()
        try:
            if section == POETRY_TABLE:
                if not equals:
                    raise _Unreadable(stripped)
                if key.lower() != "python":
                    name, entry = _poetry_dependency(key, value)
                    found["poetry"][name] = entry
            elif section == "project" and re.sub(r"[\s\"']", "", key) == "dependencies":
                items, index = _read_array(value, lines, index)
                found["project"].extend(items)
            elif equals and section != "project" and _hides_dependencies(section, key):
                raise _Unreadable(stripped)
        except _Unreadable:
            found["unreadable"].add("{}: {}".format(section, stripped))
    return found


def _classify_pyproject(base, old, new):
    now = _read_pyproject(new)
    before = _read_pyproject(old) if old is not None else {"project": [], "poetry": {}, "unreadable": set()}
    found = [_warning(base, CODE_UNREADABLE_PYPROJECT,
                      "{} has a dependency declaration the guard cannot read: {}".format(base, _clip(marker)))
             for marker in sorted(now["unreadable"] - before["unreadable"])]
    for item in now["project"]:
        if item not in before["project"]:
            found.append(_parse_requirement(item, base))
    for name, (source, version) in now["poetry"].items():
        if before["poetry"].get(name) != (source, version):
            found.append(_dependency("pypi", "pyproject.toml", name, version, source))
    return found


# ---- dispatch -------------------------------------------------------------------------------

def _require_str(tool_input, key):
    value = tool_input.get(key)
    if not isinstance(value, str):
        raise ValueError("tool_input.{} must be a string".format(key))
    return value


def _new_content(tool_name, tool_input, old):
    """The file text after the edit, or None when an Edit cannot be applied (file not on disk)."""
    if tool_name == TOOL_WRITE:
        return _require_str(tool_input, "content")
    target, replacement = _require_str(tool_input, "old_string"), _require_str(tool_input, "new_string")
    if target == "":  # Claude Code's create-by-Edit: only valid on an absent or empty file
        return replacement if (old is None or not old.strip()) else old
    if old is None:
        return None
    count = -1 if tool_input.get("replace_all") else 1
    return old.replace(target, replacement, count)


def classify(tool_name, tool_input, read_file=read_current_file):
    """Dependencies an Edit/Write adds or changes in a manifest, plus warnings. See module doc."""
    if tool_name not in (TOOL_EDIT, TOOL_WRITE, TOOL_NOTEBOOK):
        return []
    if not isinstance(tool_input, dict):
        raise ValueError("tool_input must be an object")
    path = _require_str(tool_input, "notebook_path" if tool_name == TOOL_NOTEBOOK else "file_path")
    base = os.path.basename(path)
    folded = base.lower()
    if folded in UNPARSED_BASENAMES:
        return [_warning(base, CODE_DEPENDENCY_FILE,
                         "{} is a dependency or lock file; the guard does not parse it, so check what "
                         "the edit changes".format(base))]
    if folded == "package.json":
        classifier = _classify_package_json
    elif folded == "pyproject.toml":
        classifier = _classify_pyproject
    elif REQUIREMENTS_RE.fullmatch(folded):
        classifier = _classify_requirements
    else:
        return []
    if tool_name == TOOL_NOTEBOOK:
        return [_warning(base, CODE_UNREADABLE_EDIT, "NotebookEdit on {} cannot be read".format(base))]
    old = read_file(path)
    new = _new_content(tool_name, tool_input, old)
    if new is None:
        return [_warning(base, CODE_UNREADABLE_EDIT,
                         "Edit on {}, which is not on disk, cannot be applied to read".format(base))]
    if new == old:
        return []
    return classifier(base, old, new)


def main():
    try:
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict):
            raise ValueError("payload is not an object")
        result = classify(payload.get("tool_name"), payload.get("tool_input"))
    except (ValueError, OSError) as exc:
        first_line = (str(exc).splitlines() or [""])[0]
        sys.stderr.write("classify-manifest-edit: {}: {}\n".format(type(exc).__name__, first_line))
        return 2
    sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
