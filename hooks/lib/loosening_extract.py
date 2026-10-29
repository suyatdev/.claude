"""Turn one watched file's bytes into a Profile, and compare two Profiles.

A Profile is (lists, residue):
  lists    {name: {entry key: how to show it}} -- the recognised permission lists (loosening_watch.py)
  residue  everything else that matters, as one comparable string

Two profiles are compared as: a list's entries are a SET (order and duplicates do not matter), and the
residue must be EQUAL. A difference in the residue means the file changed somewhere no direction can be
read from -- ADR 0052 decision 2's CHANGED-DIRECTION-UNKNOWN -- and it prompts. So the extraction can
only err toward prompting: whatever it does not recognise stays in the residue.

ParseError names a file that could not be read at all; the caller refuses (fail closed, spec section 7).
ToolError is the checker's own environment failing (no bash for `bash -n`), which is not the file's fault.
"""
import ast
import json
import os
import shutil
import subprocess

from loosening_shell import ShellScanError, case_entries, code_lines
import loosening_watch as watch

BASH_SYNTAX_TIMEOUT_SECONDS = 20


class ParseError(Exception):
    pass


class ToolError(Exception):
    pass


class Profile:
    def __init__(self, lists, residue):
        self.lists = lists
        self.residue = residue


class Findings:
    """What changed between two profiles of one file, by direction."""

    def __init__(self):
        self.loosen, self.tighten, self.unknown = [], [], []   # (list name, "+"|"-", shown) / reasons


def _flat(text):
    return " ".join(text.split())


# ---- python -------------------------------------------------------------------------------------
def _strip_docstrings(tree):
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            body = node.body
            if (body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant)
                    and isinstance(body[0].value.value, str)):
                node.body = body[1:]


def python_profile(path, text):
    try:
        tree = ast.parse(text, filename=path)
    except (SyntaxError, ValueError, RecursionError, MemoryError) as exc:
        raise ParseError("python parse failed: %s" % (exc.__class__.__name__ if not str(exc) else exc))
    specs = watch.PY_LISTS.get(path, {})
    lists, body = {}, []
    for node in tree.body:
        name = None
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            name = node.targets[0].id
        if (name in specs and name not in lists
                and isinstance(node.value, (ast.Tuple, ast.List, ast.Set))):
            lists[name] = {ast.dump(e): _flat(ast.get_source_segment(text, e) or ast.dump(e))
                           for e in node.value.elts}
            body.append(ast.Expr(value=ast.Name(id="<list:%s>" % name, ctx=ast.Load())))
        else:
            body.append(node)
    tree.body = body
    _strip_docstrings(tree)
    return Profile(lists, ast.dump(tree))


# ---- shell --------------------------------------------------------------------------------------
def _bash():
    found = os.environ.get("LG_BASH") or shutil.which("bash")
    if not found:
        raise ToolError("bash is not on PATH, so shell files cannot be syntax-checked")
    return found


def _bash_syntax_check(text):
    try:
        done = subprocess.run([_bash(), "-n"], input=text.encode("utf-8"), stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=BASH_SYNTAX_TIMEOUT_SECONDS)
    except (OSError, subprocess.SubprocessError) as exc:
        raise ToolError("bash -n could not run: %s" % exc)
    if done.returncode != 0:
        first = (done.stderr.decode("utf-8", "replace").strip().splitlines() or ["no message"])[0]
        raise ParseError("bash -n rejected it: %s" % first[:200])


def shell_profile(path, text):
    _bash_syntax_check(text)
    try:
        lines = code_lines(text)
        specs = watch.SH_CASE_LISTS.get(path, [])
        lists, claimed = {}, {}
        for header, name, _direction, body, _what in specs:
            found = case_entries(lines, header, body)
            if found:
                lists[name] = found[0]
                claimed.update({k: name for k in found[1]})
    except ShellScanError as exc:
        raise ParseError("shell scan failed: %s" % exc)
    residue, last = [], None
    for k, (line, strippable) in enumerate(lines):
        if k in claimed:
            marker = "<entries:%s>" % claimed[k]
            if last != marker:
                residue.append(marker)
            last = marker
        else:
            residue.append(line if strippable else "\x00" + line)
            last = None
    shebang = text.split("\n", 1)[0] if text.startswith("#!") else ""
    return Profile(lists, shebang + "\n" + "\n".join(residue))


# ---- settings.json and the mode switch ----------------------------------------------------------
def _shape(ok, what):
    if not ok:
        raise ParseError("settings.json is not shaped as expected: %s" % what)


def settings_profile(path, text):
    try:
        doc = json.loads(text)
    except ValueError as exc:
        raise ParseError("json parse failed: %s" % exc)
    _shape(isinstance(doc, dict), "top level is not an object")
    hooks = doc.get("hooks", {})
    _shape(isinstance(hooks, dict), "hooks is not an object")
    registrations = {}
    for event, groups in hooks.items():
        _shape(isinstance(groups, list), "hooks.%s is not a list" % event)
        for group in groups:
            _shape(isinstance(group, dict) and isinstance(group.get("hooks", []), list),
                   "a hooks.%s group is malformed" % event)
            for hook in group.get("hooks", []):
                _shape(isinstance(hook, dict), "a hooks.%s entry is not an object" % event)
                command = hook.get("command")
                if isinstance(command, str) and any(s in command for s in watch.GUARD_SCRIPTS):
                    key = json.dumps([event, group.get("matcher", ""), hook], sort_keys=True)
                    registrations[key] = "%s %s: %s" % (event, group.get("matcher") or "*", command)
    env = doc.get("env", {})
    _shape(isinstance(env, dict), "env is not an object")
    watched = {
        "env": {k: v for k, v in env.items() if k.startswith(watch.SETTINGS_ENV_PREFIX)},
        "switches": {k: v for k, v in doc.items() if "hook" in k.lower() and k != "hooks"},
    }
    return Profile({watch.SETTINGS_REGISTRATIONS: registrations}, json.dumps(watched, sort_keys=True))


def mode_profile(path, text):
    kept = [s for s in (line.strip() for line in text.splitlines()) if s and not s.startswith("#")]
    return Profile({}, "\n".join(kept))


def extract(path, data):
    """Profile of one watched file's bytes. Raises ParseError / ToolError."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ParseError("not valid UTF-8: %s" % exc)
    if "\x00" in text:
        raise ParseError("contains a NUL byte")
    if path.endswith(".py"):
        return python_profile(path, text)
    if path == "settings.json":
        return settings_profile(path, text)
    if path.endswith(".mode"):
        return mode_profile(path, text)
    return shell_profile(path, text)


# ---- comparison ---------------------------------------------------------------------------------
def _direction(path, name):
    if name == watch.SETTINGS_REGISTRATIONS:
        return watch.BLOCK, "hook registrations that run a guard"
    if name in watch.PY_LISTS.get(path, {}):
        return watch.PY_LISTS[path][name]
    for _header, list_name, direction, _body, what in watch.SH_CASE_LISTS.get(path, []):
        if list_name == name:
            return direction, what
    raise ParseError("internal: list %s of %s has no direction" % (name, path))


def compare(path, base, new):
    found = Findings()
    if base.residue != new.residue:
        found.unknown.append("code outside the recognised permission lists changed")
    for name in sorted(set(base.lists) | set(new.lists)):
        if name not in base.lists or name not in new.lists:
            side = "origin/main" if name in base.lists else "the commit"
            found.unknown.append("list %s is recognised only in the %s copy" % (name, side))
            continue
        direction, what = _direction(path, name)
        added = sorted(set(new.lists[name]) - set(base.lists[name]))
        removed = sorted(set(base.lists[name]) - set(new.lists[name]))
        # ALLOW: an entry added lets more through. BLOCK: an entry removed lets more through.
        widens, narrows = (added, removed) if direction == watch.ALLOW else (removed, added)
        for keys, bucket in ((widens, found.loosen), (narrows, found.tighten)):
            for key in keys:
                sign = "+" if key in added else "-"
                shown = new.lists[name][key] if sign == "+" else base.lists[name][key]
                bucket.append((name, what, sign, shown))
    return found
