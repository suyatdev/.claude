#!/usr/bin/env python3
"""Unit tests for classify-manifest-edit.py. Run: python3 hooks/lib/classify-manifest-edit.test.py

The classifier turns an Edit/Write payload aimed at a dependency manifest into the dependencies
that edit ADDS or CHANGES (docs/features/dependency-vetting-guard.md, "Manifest edits"). The
expected values below come from that section and from the Contracts table, not from the
implementation; every shape was written down before the module existed.

File access is injected (`read_file`), so nothing here touches the real filesystem except the
final CLI cases, which use their own temporary directory.

Deliberately dependency-free (no pytest): adding a dependency is not a unilateral call, and this
has to run anywhere the hook runs.
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile

MARKER_SELF = os.path.abspath(__file__)
# cwd=dirname(MARKER_SELF), never the inherited process cwd: this file is also run as a nested
# subprocess by other suites from inside a throwaway repo (see classify-pr-command.test.py).
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

_HERE = os.path.dirname(os.path.abspath(__file__))
_MODULE_PATH = os.path.join(_HERE, "classify-manifest-edit.py")
_SPEC = importlib.util.spec_from_file_location("classify_manifest_edit", _MODULE_PATH)
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)
classify = _MOD.classify
is_exact_version = _MOD.is_exact_version

PASSED = 0
FAILED = 0


def check(label, got, want):
    global PASSED, FAILED
    if got == want:
        PASSED += 1
        return
    FAILED += 1
    print("FAIL — {}\n       want {!r}\n       got  {!r}".format(label, want, got))


def check_raises(label, exc_type, fn):
    global PASSED, FAILED
    try:
        fn()
    except exc_type:
        PASSED += 1
        return
    except Exception as exc:  # noqa: BLE001 -- the point is to report any other class
        FAILED += 1
        print("FAIL — {}\n       want {}, got {!r}".format(label, exc_type.__name__, exc))
        return
    FAILED += 1
    print("FAIL — {}\n       want {}, nothing raised".format(label, exc_type.__name__))


def run(tool, tool_input, files=None):
    files = files or {}
    return classify(tool, tool_input, read_file=lambda path: files.get(path))


def write(path, content, files=None):
    return run("Write", {"file_path": path, "content": content}, files)


def edit(path, old, new, files, replace_all=False):
    return run("Edit", {"file_path": path, "old_string": old, "new_string": new,
                        "replace_all": replace_all}, files)


def deps(result):
    """(name, version, pinned, source) for each dependency, in order."""
    return [(d["name"], d["version"], d["pinned"], d["source"]) for d in result if d["kind"] == "dependency"]


def warnings(result):
    return [w["code"] for w in result if w["kind"] == "warning"]


def pkg(**sections):
    return json.dumps(sections, indent=2) + "\n"


PJ = "/proj/package.json"

# --------------------------------------------------------------------------------------------
# package.json: add / change / remove
# --------------------------------------------------------------------------------------------


def test_package_json_add_change_remove():
    r = write(PJ, pkg(dependencies={"zod": "3.23.8"}))
    check("Write onto an absent file: every dependency is added", deps(r),
          [("zod", "3.23.8", True, "registry")])
    d = r[0]
    check("intent carries the install-intent contract keys", (
        d["ecosystem"], d["tool"], d["runner"], d["form"]), ("npm", "package.json", None, "add"))

    old = pkg(dependencies={"left-pad": "1.3.0"})
    new = pkg(dependencies={"left-pad": "1.3.0", "zod": "3.23.8"})
    check("Edit adding a key: only the new key", deps(edit(PJ, '"left-pad": "1.3.0"',
          '"left-pad": "1.3.0",\n    "zod": "3.23.8"', {PJ: old})), [("zod", "3.23.8", True, "registry")])
    check("Write over an existing file: unchanged key is not returned", deps(write(PJ, new, {PJ: old})),
          [("zod", "3.23.8", True, "registry")])

    old = pkg(dependencies={"zod": "3.22.0"})
    check("changed value is an intent for the NEW value",
          deps(write(PJ, pkg(dependencies={"zod": "3.23.8"}), {PJ: old})),
          [("zod", "3.23.8", True, "registry")])
    check("changed from pinned to a range is an unpinned intent",
          deps(write(PJ, pkg(dependencies={"zod": "^3.23.8"}), {PJ: old})),
          [("zod", "^3.23.8", False, "registry")])
    check("removed key yields nothing",
          deps(write(PJ, pkg(dependencies={}), {PJ: pkg(dependencies={"zod": "3.22.0"})})), [])
    check("rewriting the identical file yields nothing", write(PJ, old, {PJ: old}), [])
    check("a non-dependency edit yields nothing",
          write(PJ, pkg(name="x", dependencies={"zod": "3.22.0"}), {PJ: old}), [])


def test_package_json_sections():
    new = pkg(dependencies={"a": "1.0.0"}, devDependencies={"b": "2.0.0"},
              optionalDependencies={"c": "3.0.0"}, peerDependencies={"d": "4.0.0"},
              scripts={"e": "5.0.0"}, overrides={"f": "6.0.0"})
    check("the four dependency sections are read, in order; other sections are not",
          [x[0] for x in deps(write(PJ, new))], ["a", "b", "c", "d"])
    old = pkg(dependencies={"a": "1.0.0"})
    new = pkg(dependencies={}, devDependencies={"a": "1.0.0"})
    check("the same package newly listed in another section is an addition",
          deps(write(PJ, new, {PJ: old})), [("a", "1.0.0", True, "registry")])
    check("scoped names keep their scope",
          deps(write(PJ, pkg(dependencies={"@scope/pkg": "1.0.0"}))), [("@scope/pkg", "1.0.0", True, "registry")])


def test_package_json_edit_application():
    old = pkg(dependencies={"a": "0.0.1", "b": "0.0.1"})
    check("Edit without replace_all applies ONE replacement (the first)",
          [x[0] for x in deps(edit(PJ, '"0.0.1"', '"9.9.9"', {PJ: old}))], ["a"])
    check("Edit with replace_all applies every replacement",
          [x[0] for x in deps(edit(PJ, '"0.0.1"', '"9.9.9"', {PJ: old}, replace_all=True))], ["a", "b"])
    check("replace_all result carries the new value",
          [x[1] for x in deps(edit(PJ, '"0.0.1"', '"9.9.9"', {PJ: old}, replace_all=True))], ["9.9.9", "9.9.9"])
    check("Edit whose old_string is absent changes nothing (the tool itself would fail)",
          edit(PJ, "no such text", "x", {PJ: old}), [])
    check("Edit on a file that is not on disk cannot be applied: warns",
          warnings(edit(PJ, "x", "y", {})), ["unreadable-edit"])
    # Claude Code creates a file with an Edit whose old_string is empty, valid on an absent or empty
    # file only; the new content must be read or this is a way to add a dependency unseen.
    created = pkg(dependencies={"zod": "3.23.8"})
    check("empty old_string on an absent file creates it: dependencies are added",
          deps(edit(PJ, "", created, {})), [("zod", "3.23.8", True, "registry")])
    check("empty old_string on an empty file creates it",
          deps(edit(PJ, "", created, {PJ: "  \n"})), [("zod", "3.23.8", True, "registry")])
    check("empty old_string on a non-empty file changes nothing (the tool refuses)",
          edit(PJ, "", created, {PJ: old}), [])
    check("replace_all defaulting absent in tool_input behaves as False",
          [x[0] for x in deps(run("Edit", {"file_path": PJ, "old_string": '"0.0.1"',
                                           "new_string": '"9.9.9"'}, {PJ: old}))], ["a"])


def test_package_json_values():
    cases = [
        ("3.23.8", ("zod", "3.23.8", True, "registry")),
        ("1.0.0-rc.1", ("zod", "1.0.0-rc.1", True, "registry")),
        ("^3.23.8", ("zod", "^3.23.8", False, "registry")),
        ("~1.2.3", ("zod", "~1.2.3", False, "registry")),
        (">=1.0", ("zod", ">=1.0", False, "registry")),
        ("=1.2.3", ("zod", "=1.2.3", False, "registry")),
        ("1.x", ("zod", "1.x", False, "registry")),
        ("*", ("zod", "*", False, "registry")),
        ("latest", ("zod", "latest", False, "registry")),
        ("", ("zod", "", False, "registry")),
        ("v1.2.3", ("zod", "v1.2.3", False, "registry")),
        ("01.2.3", ("zod", "01.2.3", False, "registry")),
    ]
    for value, want in cases:
        check("package.json value {!r}".format(value), deps(write(PJ, pkg(dependencies={"zod": value}))), [want])


def test_package_json_non_registry_sources():
    values = ["workspace:*", "workspace:^1.0.0", "file:../foo", "link:../foo", "git+https://h/x.git",
              "git+ssh://git@h/x.git", "git://h/x.git", "git@h:x/y.git", "github:user/repo",
              "gitlab:user/repo", "bitbucket:user/repo", "gist:abc", "http://h/x.tgz", "https://h/x.tgz",
              "./local", "../local", "/abs/local", "~/local", "pkg.tgz", "dir/pkg.tar.gz",
              # Mark 2026-10-14: npm's bare `owner/repo` means GitHub, so it asks like `github:`.
              "user/repo", "user/repo#semver:^1.0.0", "user/repo#v1.2.3", "user/repo#", "a/b",
              "Owner-1/repo.js", "user/.hidden", "user/-x", "my-org/my.repo_2"]
    for value in values:
        got = deps(write(PJ, pkg(dependencies={"foo": value})))
        check("source other: {!r}".format(value), got, [("foo", value, False, "other")])


def test_package_json_shorthand_boundaries():
    # Shorthand is decided by the manifest VALUE, never the key, and never catches a scope.
    check("a scoped key with a real version stays a pinned registry package",
          deps(write(PJ, pkg(dependencies={"@scope/pkg": "1.0.0"}))), [("@scope/pkg", "1.0.0", True, "registry")])
    check("a scoped key with a range stays an unpinned registry package",
          deps(write(PJ, pkg(dependencies={"@scope/pkg": "^1.0.0"}))), [("@scope/pkg", "^1.0.0", False, "registry")])
    check("a key that looks like owner/repo does not make its version shorthand",
          deps(write(PJ, pkg(dependencies={"owner/repo": "1.0.0"}))), [("owner/repo", "1.0.0", True, "registry")])
    for value in ["@scope/name", "@scope/name#v1", "a/b/c", "1.0.0/..", "user/", "user//repo",
                  "us er/repo", "user/re po",
                  # One shape (spec, "Not from a registry"): an owner has no dots and no leading hyphen.
                  "1.2.3/evil", "user.name/repo", "o_w.n/r-e_p.o", "-user/repo"]:
        got = deps(write(PJ, pkg(dependencies={"foo": value})))
        check("not shorthand (stays unpinned registry, refused): {!r}".format(value), got,
              [("foo", value, False, "registry")])
    check("an alias to a scoped package is untouched by the shorthand rule",
          deps(write(PJ, pkg(dependencies={"foo": "npm:@s/bar@1.0.0"}))), [("@s/bar", "1.0.0", True, "registry")])
    for value, want in [("npm:bar@1.2.3/evil", ("bar", "1.2.3/evil", False, "registry")),
                        ("npm:1.2.3/evil", ("1.2.3/evil", None, False, "registry")),
                        ("npm:user.name/repo", ("user.name/repo", None, False, "registry")),
                        ("npm:bar@user.name/repo", ("bar", "user.name/repo", False, "registry"))]:
        check("an alias with a non-shorthand slash stays an unpinned registry value: {!r}".format(value),
              deps(write(PJ, pkg(dependencies={"foo": value}))), [want])
    check("an alias to owner/repo-looking text is still an alias",
          deps(write(PJ, pkg(dependencies={"foo": "npm:bar@1.0.0"}))), [("bar", "1.0.0", True, "registry")])


def test_intent_contract_fields():
    # Contracts (e0b4234): every item carries exempt and via_package_option; a manifest edit can
    # never carry VET_EXEMPT or come from -p/--package.
    results = [
        write(PJ, pkg(dependencies={"a": "1.0.0", "b": "^2", "c": "file:../c", "d": "user/repo",
                                    "e": "npm:f@1.0.0"})),
        write(REQ, "a==1.0\nb>=2\nc\n"),
        write(PP, '[project]\ndependencies = ["a==1.0", "b"]\n[tool.poetry.dependencies]\n'
                  'c = "1.0.0"\nd = {git = "https://h/d.git"}\n'),
    ]
    items = [d for r in results for d in r if d["kind"] == "dependency"]
    check("enough items to mean something", len(items) >= 12, True)
    check("every dependency item has exempt: None", [d.get("exempt", "MISSING") for d in items],
          [None] * len(items))
    check("every dependency item has via_package_option: False",
          [d.get("via_package_option", "MISSING") for d in items], [False] * len(items))
    check("the full key set of a dependency item", sorted(items[0]), sorted(
        ["kind", "ecosystem", "name", "version", "pinned", "tool", "runner", "form", "source", "exempt",
         "via_package_option"]))


def test_package_json_alias_to_non_registry_source():
    # Card "Not from a registry": such a value is `source: other` wherever it sits, including
    # after `npm:` in an alias. The item names the value as written (the whole `npm:...` string).
    for target in ["user/repo", "user/repo#v1.2.3", "github:user/repo", "gitlab:user/repo",
                   "bitbucket:user/repo", "gist:abc", "git+https://h/x.git", "git+ssh://git@h/x.git",
                   "git://h/x.git", "git@h:x/y.git", "https://h/x.tgz", "file:../x", "link:../x",
                   "workspace:*", "./local", "../local", "/abs/local", "pkg.tgz"]:
        value = "npm:" + target
        check("alias to a non-registry source: {!r}".format(value),
              deps(write(PJ, pkg(dependencies={"foo": value}))), [("foo", value, False, "other")])
    check("the alias prefix is case-insensitive here too",
          deps(write(PJ, pkg(dependencies={"foo": "NPM:user/repo"}))), [("foo", "NPM:user/repo", False, "other")])
    for version in ["user/repo", "github:user/repo", "file:../x"]:
        value = "npm:bar@" + version
        check("a non-registry source in the alias version position: {!r}".format(value),
              deps(write(PJ, pkg(dependencies={"foo": value}))), [("foo", value, False, "other")])
    check("an Edit adding such an alias asks",
          deps(edit(PJ, '"a": "1.0.0"', '"a": "1.0.0", "foo": "npm:user/repo"',
                    {PJ: pkg(dependencies={"a": "1.0.0"})})), [("foo", "npm:user/repo", False, "other")])
    # Controls: ordinary aliases must still resolve to the real package (pinned or not).
    for value, want in [("npm:bar@1.0.0", ("bar", "1.0.0", True, "registry")),
                        ("npm:@s/bar@1.0.0", ("@s/bar", "1.0.0", True, "registry")),
                        ("npm:bar@^1.0.0", ("bar", "^1.0.0", False, "registry")),
                        ("npm:bar", ("bar", None, False, "registry")),
                        ("npm:@s/bar", ("@s/bar", None, False, "registry")),
                        ("npm:@s/bar@latest", ("@s/bar", "latest", False, "registry"))]:
        check("ordinary alias still resolves: {!r}".format(value),
              deps(write(PJ, pkg(dependencies={"foo": value}))), [want])


def test_package_json_aliases():
    check("npm alias resolves to the real package",
          deps(write(PJ, pkg(dependencies={"foo": "npm:bar@1.0.0"}))), [("bar", "1.0.0", True, "registry")])
    check("scoped alias target",
          deps(write(PJ, pkg(dependencies={"foo": "npm:@s/bar@1.0.0"}))), [("@s/bar", "1.0.0", True, "registry")])
    check("alias with a range is unpinned",
          deps(write(PJ, pkg(dependencies={"foo": "npm:bar@^1.0.0"}))), [("bar", "^1.0.0", False, "registry")])
    check("alias with no version is unpinned, version null",
          deps(write(PJ, pkg(dependencies={"foo": "npm:bar"}))), [("bar", None, False, "registry")])
    check("scoped alias with no version",
          deps(write(PJ, pkg(dependencies={"foo": "npm:@s/bar"}))), [("@s/bar", None, False, "registry")])


def test_package_json_unreadable():
    check("unparseable new content asks", warnings(write(PJ, '{"dependencies": {')), ["unreadable-json"])
    check("mid-edit Edit result that stops parsing asks",
          warnings(edit(PJ, '"zod"', '"zod', {PJ: pkg(dependencies={"zod": "1.0.0"})})), ["unreadable-json"])
    check("top level that is not an object asks", warnings(write(PJ, "[]")), ["unreadable-json"])
    check("a dependency section that is not an object asks",
          warnings(write(PJ, '{"dependencies": ["zod"]}')), ["unreadable-json"])
    check("a non-string version asks", warnings(write(PJ, '{"dependencies": {"zod": 1}}')),
          ["unreadable-json"])
    check("empty content asks", warnings(write(PJ, "")), ["unreadable-json"])
    # An unparseable OLD file must not hide additions: with nothing readable to diff against,
    # every dependency in the new content counts as added.
    check("unparseable old content: new content's dependencies all count as added",
          deps(write(PJ, pkg(dependencies={"zod": "3.23.8"}), {PJ: "{not json"})),
          [("zod", "3.23.8", True, "registry")])
    r = write(PJ, "{")
    check("warning shape", (r[0]["kind"], r[0]["file"], bool(r[0]["message"])), ("warning", "package.json", True))


# --------------------------------------------------------------------------------------------
# requirements*.txt
# --------------------------------------------------------------------------------------------

REQ = "/proj/requirements.txt"


def test_requirements_specifiers():
    text = "\n".join([
        "requests==2.32.3",
        "flask>=3.0",
        "numpy",
        "a==1.*",
        "b~=1.0",
        'c==1.0 ; python_version < "3.9"',
        "d[security]==2.0",
        "e == 1.0.0",
        "f==1.0 --hash=sha256:abc",
        "g==2.1.0+cu118",
        "h===1.0",
        "i!=1.0",
        "j<2,>=1",
        "k==1.0 # note",
        "l==01.0",
        "",
    ])
    want = [
        ("requests", "2.32.3", True, "registry"),
        ("flask", ">=3.0", False, "registry"),
        ("numpy", None, False, "registry"),
        ("a", "1.*", False, "registry"),
        ("b", "~=1.0", False, "registry"),
        ("c", "1.0", True, "registry"),
        ("d", "2.0", True, "registry"),
        ("e", "1.0.0", True, "registry"),
        ("f", "1.0", True, "registry"),
        ("g", "2.1.0+cu118", True, "registry"),
        ("h", "===1.0", False, "registry"),
        ("i", "!=1.0", False, "registry"),
        ("j", "<2,>=1", False, "registry"),
        ("k", "1.0", True, "registry"),
        ("l", "01.0", True, "registry"),  # the pypi pattern is [0-9]+(\.[0-9]+)*: no leading-zero rule
    ]
    r = write(REQ, text)
    check("requirement specifiers", deps(r), want)
    check("ecosystem and tool", (r[0]["ecosystem"], r[0]["tool"], r[0]["form"], r[0]["runner"]),
          ("pypi", "requirements.txt", "add", None))


def test_requirements_add_change_remove():
    old = "requests==2.32.3\nflask==3.0.0\n"
    check("added line", deps(write(REQ, old + "zod==1.0\n", {REQ: old})), [("zod", "1.0", True, "registry")])
    check("changed line is returned with the new value",
          deps(write(REQ, "requests==2.33.0\nflask==3.0.0\n", {REQ: old})),
          [("requests", "2.33.0", True, "registry")])
    check("a line loosened to a range is returned unpinned",
          deps(write(REQ, "requests>=2\nflask==3.0.0\n", {REQ: old})), [("requests", ">=2", False, "registry")])
    check("removed line yields nothing", write(REQ, "flask==3.0.0\n", {REQ: old}), [])
    check("reordered lines yield nothing", write(REQ, "flask==3.0.0\nrequests==2.32.3\n", {REQ: old}), [])
    check("comment-only change asks (card line 531), and returns no dependency",
          (warnings(write(REQ, "# hi\n" + old, {REQ: old})), deps(write(REQ, "# hi\n" + old, {REQ: old}))),
          (["unreadable-line"], []))
    check("Edit applies against the disk text",
          deps(edit(REQ, "flask==3.0.0", "flask==3.0.0\nzod==1.0", {REQ: old})), [("zod", "1.0", True, "registry")])
    both = "a==1.0\nb==1.0\n"
    check("Edit replace_all over two lines", [x[0] for x in deps(
        edit(REQ, "==1.0", "==2.0", {REQ: both}, replace_all=True))], ["a", "b"])
    check("Edit without replace_all touches the first only", [x[0] for x in deps(
        edit(REQ, "==1.0", "==2.0", {REQ: both}))], ["a"])
    check("CRLF line endings", deps(write(REQ, "a==1.0\r\nb==2.0\r\n")),
          [("a", "1.0", True, "registry"), ("b", "2.0", True, "registry")])
    check("backslash continuation joins a requirement with its hash option",
          deps(write(REQ, "a==1.0 \\\n    --hash=sha256:abc\n")), [("a", "1.0", True, "registry")])


def test_requirements_ignored_and_asked():
    # Card line 531: "comments, -r, -e, and URLs -> ask with a general warning". A whole-line
    # comment that is added or changed asks, exactly like -r/-e/URLs. Blank lines stay ignored.
    check("blank and whitespace-only lines are ignored", write(REQ, "\n   \n\t\n"), [])
    check("an added comment line asks", warnings(write(REQ, "# a comment\n")), ["unreadable-line"])
    check("an indented comment line asks", warnings(write(REQ, "   # indented\n")), ["unreadable-line"])
    check("a commented-out requirement asks", warnings(write(REQ, "# b==1.0\n")), ["unreadable-line"])
    check("each added comment line is its own warning",
          warnings(write(REQ, "# one\n\n# two\n")), ["unreadable-line", "unreadable-line"])
    r = write(REQ, "# a comment\n")
    first = (r or [{}])[0]  # an empty result must fail this check, not crash the suite
    check("comment warning shape", (first.get("kind"), first.get("file"), bool(first.get("message")),
                                    "# a comment" in first.get("message", "")),
          ("warning", "requirements.txt", True, True))
    r = write(REQ, "# note\nzod==1.0\n")
    check("a comment beside an added dependency: both are reported", (warnings(r), [x[0] for x in deps(r)]),
          (["unreadable-line"], ["zod"]))
    check("an Edit that adds a comment line asks",
          warnings(edit(REQ, "a==1.0", "# why\na==1.0", {REQ: "a==1.0\n"})), ["unreadable-line"])
    old_c = "# pinned for the demo\na==1.0\n"
    check("a comment already on disk is not asked about again", write(REQ, old_c + "\n\n", {REQ: old_c}), [])
    check("a changed comment line asks",
          warnings(write(REQ, old_c.replace("demo", "prod"), {REQ: old_c})), ["unreadable-line"])
    check("a removed comment line yields nothing", write(REQ, "a==1.0\n", {REQ: old_c}), [])
    check("an inline comment on a requirement is not a comment line: the requirement is read",
          (warnings(write(REQ, "a==1.0 # why\n")), deps(write(REQ, "a==1.0 # why\n"))),
          ([], [("a", "1.0", True, "registry")]))
    for line in ["-r other.txt", "--requirement other.txt", "-e .", "-e git+https://h/x.git#egg=x",
                 "--extra-index-url https://h/simple", "-i https://h/simple", "-c constraints.txt",
                 "--find-links ./wheels", "https://h/x-1.0-py3-none-any.whl", "git+https://h/x.git",
                 "./local-pkg", "../local-pkg", ".", "foo @ https://h/foo-1.0.tar.gz", "/abs/pkg.whl"]:
        check("asked: {!r}".format(line), warnings(write(REQ, line + "\n")), ["unreadable-line"])
    old = "-r base.txt\na==1.0\n"
    check("an `-r` line already on disk is not asked about again",
          warnings(write(REQ, old + "b==1.0\n", {REQ: old})), [])
    check("but the dependency added beside it is returned",
          deps(write(REQ, old + "b==1.0\n", {REQ: old})), [("b", "1.0", True, "registry")])
    r = write(REQ, "-r other.txt\n")
    check("warning shape", (r[0]["kind"], r[0]["file"], bool(r[0]["message"])),
          ("warning", "requirements.txt", True))
    check("the message names the line", "-r other.txt" in r[0]["message"], True)


def test_requirements_filenames():
    for name in ["requirements.txt", "requirements-dev.txt", "requirements_test.txt", "requirements.prod.txt",
                 "Requirements.TXT"]:
        check("manifest basename {}".format(name), deps(write("/p/" + name, "a==1.0\n")),
              [("a", "1.0", True, "registry")])
    for name in ["dev-requirements.txt", "requirements.txt.bak", "requirements", "notes.txt"]:
        check("not a manifest {}".format(name), write("/p/" + name, "a==1.0\n"), [])


# --------------------------------------------------------------------------------------------
# pyproject.toml
# --------------------------------------------------------------------------------------------

PP = "/proj/pyproject.toml"


def test_pyproject_project_dependencies():
    text = '\n'.join([
        '[build-system]',
        'requires = ["setuptools==70.0.0"]',
        '',
        '[project]',
        'name = "demo"',
        'version = "0.1.0"',
        'dependencies = [',
        '    "requests==2.32.3",  # pinned',
        "    'flask>=3.0',",
        '    # a comment line',
        '    "numpy",',
        '    "d[security]==2.0",',
        ']',
        'requires-python = ">=3.9"',
    ])
    r = write(PP, text)
    check("[project] dependencies, multi-line with comments and mixed quotes", deps(r), [
        ("requests", "2.32.3", True, "registry"),
        ("flask", ">=3.0", False, "registry"),
        ("numpy", None, False, "registry"),
        ("d", "2.0", True, "registry"),
    ])
    check("ecosystem and tool", (r[0]["ecosystem"], r[0]["tool"]), ("pypi", "pyproject.toml"))
    check("single-line array", deps(write(PP, '[project]\ndependencies = ["a==1.0", "b>=2"]\n')),
          [("a", "1.0", True, "registry"), ("b", ">=2", False, "registry")])
    check("empty array", write(PP, '[project]\ndependencies = []\n'), [])
    check("TOML basic-string escapes decode",
          deps(write(PP, '[project]\ndependencies = ["a==1.0 ; python_version < \\"3.9\\""]\n')),
          [("a", "1.0", True, "registry")])
    check("direct reference in the array asks",
          warnings(write(PP, '[project]\ndependencies = ["foo @ https://h/f.tgz"]\n')), ["unreadable-line"])


def test_pyproject_diff():
    old = '[project]\ndependencies = [\n  "a==1.0",\n  "b==1.0",\n]\n'
    new_added = '[project]\ndependencies = [\n  "a==1.0",\n  "b==1.0",\n  "c==1.0",\n]\n'
    check("array: added item", deps(write(PP, new_added, {PP: old})), [("c", "1.0", True, "registry")])
    check("array: changed item", deps(write(PP, old.replace("b==1.0", "b==2.0"), {PP: old})),
          [("b", "2.0", True, "registry")])
    check("array: removed item", write(PP, '[project]\ndependencies = ["a==1.0"]\n', {PP: old}), [])
    check("array: reformatting alone", write(PP, '[project]\ndependencies = ["a==1.0", "b==1.0"]\n', {PP: old}), [])
    check("Edit with replace_all", [x[0] for x in deps(
        edit(PP, "==1.0", "==3.0", {PP: old}, replace_all=True))], ["a", "b"])
    check("Edit without replace_all", [x[0] for x in deps(edit(PP, "==1.0", "==3.0", {PP: old}))], ["a"])


def test_pyproject_poetry():
    text = '\n'.join([
        '[tool.poetry]',
        'name = "demo"',
        '',
        '[tool.poetry.dependencies]',
        'python = "^3.9"',
        'requests = "2.32.3"  # exact',
        "flask = '^3.0'",
        'a = {version = "1.2.3", extras = ["x"]}',
        'b = { version = "^1.0" }',
        'c = {git = "https://h/c.git"}',
        'd = {path = "../d"}',
        'e = {url = "https://h/e.tgz"}',
        '"foo.bar" = "1.0.0"',
        '',
        '[tool.poetry.group.dev.dependencies]',
        'pytest = "8.0.0"',
    ])
    r = write(PP, text)
    check("[tool.poetry.dependencies]; python skipped; other tables not read", deps(r), [
        ("requests", "2.32.3", True, "registry"),
        ("flask", "^3.0", False, "registry"),
        ("a", "1.2.3", True, "registry"),
        ("b", "^1.0", False, "registry"),
        ("c", "https://h/c.git", False, "other"),
        ("d", "../d", False, "other"),
        ("e", "https://h/e.tgz", False, "other"),
        ("foo.bar", "1.0.0", True, "registry"),
    ])
    old = '[tool.poetry.dependencies]\nrequests = "2.32.3"\nflask = "3.0.0"\n'
    check("poetry: changed", deps(write(PP, old.replace("3.0.0", "3.1.0"), {PP: old})),
          [("flask", "3.1.0", True, "registry")])
    check("poetry: added", deps(write(PP, old + 'zod = "1.0.0"\n', {PP: old})),
          [("zod", "1.0.0", True, "registry")])
    check("poetry: removed", write(PP, '[tool.poetry.dependencies]\nflask = "3.0.0"\n', {PP: old}), [])
    check("poetry: unchanged", write(PP, old, {PP: old}), [])


def test_pyproject_out_of_scope_tables():
    # Scoped EXACTLY as the spec says (Manifest edits): only [project] dependencies and
    # [tool.poetry.dependencies]. Optional-dependencies, poetry groups and PEP 735 groups are not
    # read, and the Known gaps section does not list them. Pinned so that widening is a decision.
    text = ('[project.optional-dependencies]\ndev = ["pytest==8.0.0"]\n'
            '[dependency-groups]\ntest = ["pytest==8.0.0"]\n'
            '[tool.poetry.group.dev.dependencies]\npytest = "8.0.0"\n')
    check("optional-dependencies, dependency-groups and poetry groups are not read", write(PP, text), [])


def test_pyproject_unreadable():
    bad = {
        "array item that is not a string": '[project]\ndependencies = [["a"]]\n',
        "unterminated array": '[project]\ndependencies = [\n  "a==1.0",\n',
        "bare word in array": '[project]\ndependencies = [a]\n',
        "multi-line string anywhere": '[project]\ndescription = """x"""\ndependencies = ["a==1.0"]\n',
        "dependencies is not an array": '[project]\ndependencies = "a==1.0"\n',
        "poetry value that is an array": '[tool.poetry.dependencies]\na = [{version = "1.0"}]\n',
        "poetry inline table with no version, git, path or url": '[tool.poetry.dependencies]\na = {extras = ["x"]}\n',
        "poetry inline table unclosed on the line": '[tool.poetry.dependencies]\na = {version = "1.0",\n',
        "poetry line that is not key = value": '[tool.poetry.dependencies]\njunk\n',
        "poetry sub-table header": '[tool.poetry.dependencies.foo]\nversion = "1.0.0"\n',
        "dotted key at root": 'project.dependencies = ["a==1.0"]\n',
        "inline project table at root": 'project = {dependencies = ["a==1.0"]}\n',
        "dotted poetry key under [tool.poetry]": '[tool.poetry]\ndependencies.a = "1.0.0"\n',
        "dependencies key under [tool.poetry]": '[tool.poetry]\ndependencies = {a = "1.0.0"}\n',
        "dotted poetry key under [tool]": '[tool]\npoetry.dependencies.a = "1.0.0"\n',
        "poetry non-string non-table value": '[tool.poetry.dependencies]\na = 1\n',
    }
    for label, text in bad.items():
        check("unreadable: " + label, warnings(write(PP, text)), ["unreadable-pyproject"])
    same = '[tool.poetry.dependencies]\njunk\n'
    check("an unreadable construct already on disk and unchanged is not asked about again",
          warnings(write(PP, same + 'zod = "1.0.0"\n', {PP: same})), [])
    check("...but the readable dependency added beside it is returned",
          deps(write(PP, same + 'zod = "1.0.0"\n', {PP: same})), [("zod", "1.0.0", True, "registry")])
    r = write(PP, '[project]\ndependencies = [[]]\n')
    check("warning shape", (r[0]["kind"], r[0]["file"], bool(r[0]["message"])),
          ("warning", "pyproject.toml", True))
    check("a pyproject with no dependency tables yields nothing", write(PP, '[tool.black]\nline-length = 100\n'), [])
    check("an empty pyproject yields nothing", write(PP, ""), [])


# --------------------------------------------------------------------------------------------
# lockfiles and unparsed manifests, basename matching, payload validation
# --------------------------------------------------------------------------------------------

ASK_FILES = ["Cargo.toml", "go.mod", "Gemfile", "Gemfile.lock", "package-lock.json", "npm-shrinkwrap.json",
             "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock", "poetry.lock", "uv.lock", "Pipfile.lock",
             "Cargo.lock", "go.sum"]


def test_unparsed_dependency_files():
    def must_not_read(path):
        raise AssertionError("unparsed files are never read: " + path)

    for name in ASK_FILES:
        for tool, payload in (("Write", {"file_path": "/p/" + name, "content": "x"}),
                              ("Edit", {"file_path": "/p/" + name, "old_string": "a", "new_string": "b"})):
            r = classify(tool, payload, read_file=must_not_read)
            check("{} {}: one general warning".format(tool, name), warnings(r), ["dependency-file-edit"])
            check("{} {}: names the file".format(tool, name), (r[0]["file"], name in r[0]["message"]),
                  (name, True))
    for name in ["CARGO.TOML", "Go.Sum", "GEMFILE", "Package-Lock.JSON"]:
        check("case-insensitive: " + name, warnings(write("/p/" + name, "x")), ["dependency-file-edit"])
    # "Any *lock* file" means exactly the listed basenames, never a substring match.
    for name in ["clock.js", "block.txt", "lock.json", "unlocked.md", "mylockfile", "Gemfile.bak",
                 "Cargo.toml.orig", "package.json.bak", "mypackage.json", "pyproject.toml.bak", "go.mod.txt"]:
        check("not a manifest: " + name, classify("Write", {"file_path": "/p/" + name, "content": "x"},
                                                  read_file=must_not_read), [])


def test_tool_and_payload_handling():
    def boom(path):
        raise AssertionError("must not read a non-manifest")

    check("non-manifest Write is never read", classify("Write", {"file_path": "/p/app.py", "content": "x"},
                                                       read_file=boom), [])
    check("non-manifest Edit is never read", classify("Edit", {"file_path": "/p/app.py", "old_string": "a",
                                                              "new_string": "b"}, read_file=boom), [])
    check("a tool that is not an edit tool", classify("Bash", {"command": "ls"}, read_file=boom), [])
    check("NotebookEdit aimed at a notebook", classify("NotebookEdit", {"notebook_path": "/p/a.ipynb",
                                                                       "new_source": "x"}, read_file=boom), [])
    check("NotebookEdit aimed at a manifest cannot be read: warns",
          warnings(classify("NotebookEdit", {"notebook_path": PJ, "new_source": "x"}, read_file=boom)),
          ["unreadable-edit"])
    check_raises("tool_input that is not an object", ValueError, lambda: classify("Write", [], read_file=boom))
    check_raises("Write with no file_path", ValueError, lambda: classify("Write", {"content": "x"}, read_file=boom))
    check_raises("file_path that is not a string", ValueError,
                 lambda: classify("Write", {"file_path": 3, "content": "x"}, read_file=boom))
    check_raises("manifest Write with no content", ValueError,
                 lambda: classify("Write", {"file_path": PJ}, read_file=lambda p: None))
    check_raises("manifest Edit with no old_string", ValueError,
                 lambda: classify("Edit", {"file_path": PJ, "new_string": "y"}, read_file=lambda p: "{}"))
    check_raises("manifest Edit with a non-string new_string", ValueError,
                 lambda: classify("Edit", {"file_path": PJ, "old_string": "x", "new_string": 4},
                                  read_file=lambda p: "{}"))
    check("a reader that raises propagates (the hook turns it into 'broken')", True, _raises_oserror())


def _raises_oserror():
    def bad_reader(path):
        raise PermissionError("denied")
    try:
        classify("Write", {"file_path": PJ, "content": "{}"}, read_file=bad_reader)
    except PermissionError:
        return True
    return False


# --------------------------------------------------------------------------------------------
# is_exact_version (re-exported from vetting_record.py; the npm and pypi rows of Contracts)
# --------------------------------------------------------------------------------------------

NPM_OK = ["3.23.8", "1.0.0-rc.1", "1.0.0+build.5", "0.0.0", "10.20.30", "1.0.0-a-b", "1.0.0-rc.1+build.5"]
PYPI_OK = ["2.32.3", "1.0rc1", "2.1.0+cu118", "2.1.0+CU118", "1.0", "24", "1.0a1", "1.0b2", "1.0.post1",
           "1.0.dev1", "1.0rc1.post2.dev3"]
REFUSED_BOTH = ["2.32.3/../evil", "^1.0.0", "1.x", "latest", "~1.2.3", "*", ">=1.0", "=1.2.3", "1.2.3/..",
                "..", "1.0.0-a..b", "1.0.0+..", "1.0.0-..", "v1.0.0-..", "３.２３.８", "3.23.8\n", "", " 1.0.0",
                "1.0.0 "]


def test_is_exact_version():
    for v in NPM_OK:
        check("npm accepts {!r}".format(v), is_exact_version("npm", v), True)
    for v in PYPI_OK:
        check("pypi accepts {!r}".format(v), is_exact_version("pypi", v), True)
    for v in REFUSED_BOTH:
        if v == "":
            continue
        check("npm refuses {!r}".format(v), is_exact_version("npm", v), False)
        check("pypi refuses {!r}".format(v), is_exact_version("pypi", v), False)
    for v in ["01.2.3", "1.02.3", "1.2", "1", "v1.2.3", "1.0.0-", "1.0.0+"]:
        check("npm refuses {!r}".format(v), is_exact_version("npm", v), False)
    for v in ["", "1.", ".1", "1..2", "1.0+", "1.0+.x", "1!2.0", "1.0.0-rc1", "1.0c1"]:
        check("pypi refuses {!r}".format(v), is_exact_version("pypi", v), False)
    check("None is never pinned", (is_exact_version("npm", None), is_exact_version("pypi", None)), (False, False))
    check_raises("an unknown ecosystem raises (ValidationError is a ValueError)", ValueError,
                 lambda: is_exact_version("nope", "1.0.0"))
    check("it is vetting_record's own function, not a copy", is_exact_version("go", "v1.2.3"), True)


# --------------------------------------------------------------------------------------------
# CLI: hook payload on stdin, JSON list on stdout
# --------------------------------------------------------------------------------------------


def run_cli(payload_text):
    return subprocess.run([sys.executable, "-I", _MODULE_PATH], input=payload_text, capture_output=True,
                          text=True)


def test_cli():
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "package.json")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(pkg(dependencies={"a": "1.0.0"}))
        payload = {"hook_event_name": "PreToolUse", "tool_name": "Edit",
                   "tool_input": {"file_path": path, "old_string": '"a": "1.0.0"',
                                  "new_string": '"a": "1.0.0", "b": "^2.0.0"'}}
        p = run_cli(json.dumps(payload))
        check("CLI Edit reads the real file", (p.returncode, [(d["name"], d["version"], d["pinned"])
              for d in json.loads(p.stdout)]), (0, [("b", "^2.0.0", False)]))
        absent = os.path.join(tmp, "sub", "package.json")
        payload = {"tool_name": "Write", "tool_input": {"file_path": absent, "content": pkg(
            dependencies={"z": "1.0.0"})}}
        p = run_cli(json.dumps(payload))
        check("CLI treats an absent file as empty", (p.returncode, [d["name"] for d in json.loads(p.stdout)]),
              (0, ["z"]))
        payload = {"tool_name": "Write", "tool_input": {"file_path": os.path.join(tmp, "app.py"), "content": "x"}}
        p = run_cli(json.dumps(payload))
        check("CLI non-manifest prints an empty list", (p.returncode, json.loads(p.stdout)), (0, []))
        p = run_cli(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": tmp + "/yarn.lock",
                                                                    "old_string": "a", "new_string": "b"}}))
        check("CLI lockfile prints one warning", [w["code"] for w in json.loads(p.stdout)],
              ["dependency-file-edit"])
    p = run_cli("not json")
    check("CLI unparseable payload exits 2 with a message", (p.returncode, p.stdout, bool(p.stderr.strip())),
          (2, "", True))
    p = run_cli(json.dumps({"tool_name": "Write", "tool_input": {"file_path": PJ}}))
    check("CLI malformed manifest payload exits 2", (p.returncode, p.stdout), (2, ""))
    p = run_cli(json.dumps([1]))
    check("CLI payload that is not an object exits 2", p.returncode, 2)


def main():
    for fn in (test_package_json_add_change_remove, test_package_json_sections,
               test_package_json_edit_application, test_package_json_values,
               test_package_json_non_registry_sources, test_package_json_shorthand_boundaries,
               test_intent_contract_fields, test_package_json_alias_to_non_registry_source,
               test_package_json_aliases,
               test_package_json_unreadable, test_requirements_specifiers,
               test_requirements_add_change_remove, test_requirements_ignored_and_asked,
               test_requirements_filenames, test_pyproject_project_dependencies, test_pyproject_diff,
               test_pyproject_poetry, test_pyproject_out_of_scope_tables, test_pyproject_unreadable,
               test_unparsed_dependency_files, test_tool_and_payload_handling, test_is_exact_version,
               test_cli):
        fn()
    print("\nmanifest-edit classifier unit: {} passed, {} failed".format(PASSED, FAILED))
    return 1 if FAILED else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
