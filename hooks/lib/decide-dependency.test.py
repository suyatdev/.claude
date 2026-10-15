#!/usr/bin/env python3
"""Unit tests for decide-dependency.py. Run: python3 hooks/lib/decide-dependency.test.py

The helper turns classifier output into a hook decision (docs/features/dependency-vetting-guard.md,
"Hook decisions" steps 0-3, the Log paragraph and Failure handling). Expected values come from
those sections. The end-to-end behaviour -- real payloads through hooks/dependency-guard.sh, the
broken-guard paths -- is pinned by hooks/dependency-guard.test.sh; this file pins the pure
functions underneath it, so a regression names its function.

Deliberately dependency-free (no pytest), like the other suites in this directory.
"""

import contextlib
import datetime
import importlib.util
import io
import os
import subprocess
import sys
import tempfile

MARKER_SELF = os.path.abspath(__file__)
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("decide_dependency", os.path.join(_HERE, "decide-dependency.py"))
D = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(D)
LIBS = D.load_libs()
VR = LIBS.vr

PASSED = 0
FAILED = 0
NOW = datetime.datetime(2026, 10, 14, 12, 0, 0, tzinfo=datetime.timezone.utc)
VETTER = "/hooks/bin/vet-dependency"


def check(label, got, want):
    global PASSED, FAILED
    if got == want:
        PASSED += 1
        return
    FAILED += 1
    print("FAIL — {}\n       want {!r}\n       got  {!r}".format(label, want, got))


def check_in(label, needle, text):
    check(label + " [contains {!r}]".format(needle), needle in text, True)


def intent(**over):
    base = {"ecosystem": "npm", "name": "zod", "version": "3.23.8", "pinned": True, "tool": "npm",
            "runner": None, "form": "add", "source": "registry", "exempt": None, "via_package_option": False}
    base.update(over)
    return base


def write_record(store, eco="npm", name="zod", version="3.23.8", hours=24, complete=True, signals=(), reasons=()):
    VR.write_record(store, {
        "schema": 1, "ecosystem": eco, "name": name, "version": version,
        "vetted_at": VR.format_vetted_at(NOW - datetime.timedelta(hours=hours)), "complete": complete,
        "incomplete_reasons": list(reasons), "signals": list(signals), "report": "r.md"})


def signal(check_name, status):
    return {"check": check_name, "status": status, "detail": "d"}


def test_clean():
    check("tab, newline, DEL, NEL, LS, PS become ?", D.clean("a\tb\nc\x7fd\x85e f g"), "a?b?c?d?e?f?g")
    check("cut to 200", len(D.clean("x" * 500)), 200)
    check("a plain name is untouched", D.clean("@scope/name"), "@scope/name")
    check("a non-string is stringified", D.clean(None), "None")


def test_format_age():
    td = datetime.timedelta
    check("under a minute", D.format_age(td(seconds=10)), "under a minute")
    check("a future (negative) age is not negative", D.format_age(td(seconds=-5)), "under a minute")
    check("one minute", D.format_age(td(seconds=60)), "1 minute")
    check("hours", D.format_age(td(hours=5, minutes=30)), "5 hours")
    check("one day", D.format_age(td(hours=24)), "1 day")
    check("days", D.format_age(td(days=6, hours=23)), "6 days")


def test_spellings():
    ctx = D.Context(LIBS, "", NOW, VETTER)
    check("npm range keeps its real version", D.example_version(ctx, "npm", "^3.23.8"), "3.23.8")
    check("npm none is the placeholder", D.example_version(ctx, "npm", None), "<exact-version>")
    check("a malformed version is never echoed", D.example_version(ctx, "pypi", "2.32.3/../evil"), "<exact-version>")
    check("go placeholder carries the v", D.example_version(ctx, "go", "latest"), "v<exact-version>")
    check("cargo caret", D.exact_spelling(ctx, intent(ecosystem="crates.io", name="serde", version="^1.0.210")),
          "serde@=1.0.210")
    check("pip", D.exact_spelling(ctx, intent(ecosystem="pypi", name="requests", version=None, tool="pip")),
          "requests==<exact-version>")
    check("poetry", D.exact_spelling(ctx, intent(ecosystem="pypi", name="requests", version=None, tool="poetry")),
          "requests@<exact-version>")
    check("go", D.exact_spelling(ctx, intent(ecosystem="go", name="golang.org/x/text", version="latest")),
          "golang.org/x/text@v<exact-version>")
    check("gem", D.exact_spelling(ctx, intent(ecosystem="rubygems", name="rails", version=None, tool="gem")),
          "rails --version <exact-version>")


def test_local_copy_advice():
    ctx = D.Context(LIBS, "", NOW, VETTER)
    runner = dict(form="run", runner="npx", pinned=False, version=None, name="tsc")
    check_in("plain npx gets the advice", "node_modules/.bin/tsc", D.local_copy_advice(ctx, intent(**runner)))
    check("-p gets none", D.local_copy_advice(ctx, intent(via_package_option=True, **runner)), "")
    check("scoped gets none", D.local_copy_advice(ctx, intent(**dict(runner, name="@scope/tool"))), "")
    check("a package manager gets none", D.local_copy_advice(ctx, intent(**dict(runner, name="npm"))), "")
    check("a PyPI runner gets none", D.local_copy_advice(ctx, intent(ecosystem="pypi", **runner)), "")
    check("not a runner gets none", D.local_copy_advice(ctx, intent(pinned=False, version=None)), "")


def test_decide_intent():
    with tempfile.TemporaryDirectory() as store:
        ctx = D.Context(LIBS, store, NOW, VETTER)

        def go(**over):
            return D.decide_intent(ctx, intent(**over))

        d = go(form="run", runner="npx", name="NPM", exempt="x")
        check("step 0: runner naming a package manager is a deny, VET_EXEMPT or not", d.kind, "deny")
        check_in("step 0 names the runner and manager as written", "npx would fetch the package manager NPM", d.text)
        check("step 0a: other -> ask", go(source="other", name="./x", version=None, pinned=False).kind, "ask")
        d = go(source="requirements-file", name="requirements.txt", version=None, pinned=False, tool="pip")
        check("step 0a: requirements-file -> ask", d.kind, "ask")
        check_in("requirements ask names the file", "requirements.txt", d.text)
        d = go(source="other", name="foo", version="file:../foo", pinned=False)
        check_in("a manifest other-source names the key and the value", "foo (file:../foo)", d.text)
        d = go(pinned=False, version=None, exempt="x")
        check("step 1: unpinned is a deny even with VET_EXEMPT", d.kind, "deny")
        check("step 2: no record -> deny", go().kind, "deny")
        check_in("step 2 prints the vetter command", "run: /hooks/bin/vet-dependency npm zod 3.23.8  ", go().text)
        d = go(exempt="offline")
        check("step 2 exempt: no record -> ask", d.kind, "ask")
        check_in("exempt ask says not vetted and why", "NOT VETTED", d.text)
        check_in("exempt ask carries the reason", "VET_EXEMPT: offline", d.text)
        d = go(name="bad name")
        check("an invalid name is an ask, not a path", d.kind, "ask")
        check_in("invalid-name ask names it", '"bad name" is not a valid package name', d.text)
        try:
            go(ecosystem="nope")
            check("an unknown ecosystem raises", "returned", "raised")
        except VR.ValidationError:
            check("an unknown ecosystem raises", "raised", "raised")

        write_record(store, signals=[signal("direct_vulns", "stop"), signal("popularity", "caution"),
                                     signal("source_link", "not_run")])
        d = go()
        check("step 3: fresh record -> ask", d.kind, "ask")
        check_in("ask names stop checks", "1 stop (direct_vulns)", d.text)
        check_in("ask names caution checks, not_run is neither", "1 caution (popularity)", d.text)
        check_in("ask shows the age", "vetted 1 day ago", d.text)
        d = go(form="run", runner="npx", exempt="mirror")
        check_in("a runner's ask says so", "runs from registry", d.text)
        check_in("an exempt ask with a record still carries the reason", "VET_EXEMPT: mirror", d.text)

        write_record(store, name="left-pad", version="1.3.0", hours=2, complete=False)
        d = go(name="left-pad", version="1.3.0")
        check_in("incomplete with no reasons still says so", "INCOMPLETE: no reason recorded", d.text)
        write_record(store, name="old", version="1.0.0", hours=24 * 8)
        check("a stale record is a deny", go(name="old", version="1.0.0").kind, "deny")

        write_record(store, eco="homebrew", name="jq", version="1.7.1", complete=False, reasons=["no OSV"])
        d = go(ecosystem="homebrew", name="jq", version=None, pinned=False, tool="brew")
        check("homebrew: no pin check, newest record -> ask", d.kind, "ask")
        check_in("homebrew ask names the version", "homebrew jq@1.7.1", d.text)
        d = go(ecosystem="homebrew", name="wget", version=None, pinned=False, tool="brew")
        check_in("homebrew vetter line has no version", "run: /hooks/bin/vet-dependency homebrew wget  ", d.text)


def test_update_and_indirect():
    """Step 0a (card, "Updates, upgrades and indirect installs"): ask, whatever the record or the
    exemption, and before the unpinned deny that a version-less intent would otherwise hit."""
    UPDATE_TEXT = "an update or upgrade the guard does not vet"
    INDIRECT_TEXT = "the packages come from input the guard cannot read"
    with tempfile.TemporaryDirectory() as store:
        ctx = D.Context(LIBS, store, NOW, VETTER)

        def update(**over):
            base = dict(name="zod", version=None, pinned=False, source="update", update_form="npm update")
            base.update(over)
            return D.decide_intent(ctx, intent(**base))

        d = update()
        check("an update is an ask, not the unpinned deny", d.kind, "ask")
        check_in("update ask carries the card's wording", "npm update zod: " + UPDATE_TEXT + " " + D.DASH
                 + " check what it will change before approving", d.text)
        d = update(name="npm", update_form="npm audit fix")
        check_in("no package named: the ask says everything", "npm audit fix everything: " + UPDATE_TEXT, d.text)
        check("the log decision of an update ask is ask", d.log_decision, "ask")
        check("the log carries the ecosystem and the name", (d.ecosystem, d.name, d.version), ("npm", "npm", "-"))
        d = update(ecosystem="homebrew", tool="brew", name="jq", update_form="brew upgrade")
        check_in("homebrew update asks too", "brew upgrade jq:", d.text)
        check_in("a form with flags is printed as given", "uv lock --upgrade everything:",
                 update(ecosystem="pypi", tool="uv", name="uv", update_form="uv lock --upgrade").text)
        d = update(exempt="offline")
        check("VET_EXEMPT changes nothing: still an ask", d.kind, "ask")
        check("VET_EXEMPT changes nothing: same text", d.text, update().text)
        write_record(store)
        check("a fresh record for the same name changes nothing", update().text, d.text)
        d = update(name="bad name")
        check_in("an update is not name-validated: it names what was typed", "bad name", d.text)
        check("an update is not name-validated: ask", d.kind, "ask")

        def indirect(**over):
            base = dict(name="npm", version=None, pinned=False, tool="npm", source="indirect")
            base.update(over)
            return D.decide_intent(ctx, intent(**base))

        d = indirect()
        check("an xargs install is an ask", d.kind, "ask")
        check_in("indirect ask carries the card's wording", "xargs npm: " + INDIRECT_TEXT + " " + D.DASH
                 + " check it before approving", d.text)
        check("VET_EXEMPT changes nothing for xargs", indirect(exempt="x").text, d.text)
        check("an indirect intent is not an update ask", UPDATE_TEXT in d.text, False)
        check("an update intent is not an indirect ask", INDIRECT_TEXT in update().text, False)
        d = indirect(name="pip", tool="pip", ecosystem="pypi")
        check_in("the indirect ask names the tool as written", "xargs pip:", d.text)
        for word in LIBS.install.INSTALL_TOOL_WORDS:
            got, _ = D.decide_command(ctx, "xargs " + word)
            check("xargs {} is an ask with the xargs warning, never a guard failure".format(word),
                  [(x.kind, "xargs {}: ".format(word) in x.text) for x in got], [("ask", True)])
        got, _ = D.decide_command(ctx, "npm update zod")
        check("an update log entry: decision, ecosystem, name, version", (got[0].log_decision, got[0].ecosystem,
              got[0].name, got[0].version), ("ask", "npm", "zod", "-"))
        with tempfile.TemporaryDirectory() as state:
            check("it is appended", D.append_log(state, NOW, "sess", got), True)
            with open(os.path.join(state, D.STATE_LOG)) as handle:
                fields = handle.read().rstrip("\n").split("\t")
            check("seven fields", len(fields), 7)
            check("the line carries ask, ecosystem, name, - and the clause", fields[2:], [
                "ask", "npm", "zod", "-", got[0].text])


def test_update_decisions_end_to_end():
    """decide_command on whole commands: the strongest decision wins across the intents of a segment."""
    with tempfile.TemporaryDirectory() as store:
        ctx = D.Context(LIBS, store, NOW, VETTER)

        def kinds(command):
            decisions, _ = D.decide_command(ctx, command)
            return sorted(d.kind for d in decisions)

        check("npm update -> one ask", kinds("npm update"), ["ask"])
        check("yarn global add left-pad@1.3.0, no record -> deny", kinds("yarn global add left-pad@1.3.0"), ["deny"])
        check("go get -u m@v1.2.3, no record -> the install denies beside the update ask",
              kinds("go get -u example.com/m@v1.2.3"), ["ask", "deny"])
        rc, out = run_emit(D.decide_command(ctx, "go get -u example.com/m@v1.2.3")[0])
        check("the strongest wins: exit 2", rc, 2)
        check_in("the deny line is MSG_VET_FIRST", "has no vetting report from the last 7 days", out)
        check("the update ask is not in the deny output", "an update or upgrade" in out, False)
        check("xargs npm i -> one ask", kinds("xargs npm i"), ["ask"])
        check("an unpinned install beside an update still denies", kinds("npm update zod && npm i left-pad"),
              ["ask", "deny"])


def test_git_source():
    def other(name, version=None, eco="npm"):
        return intent(ecosystem=eco, name=name, version=version, pinned=False, source="other")

    for value in ("git+https://github.com/u/r.git", "git://h/r", "ssh://git@h/r", "git@github.com:u/r.git",
                  "github:u/r", "GitHub:u/r", "gitlab:u/r", "bitbucket:u/r", "gist:abc", "user/repo",
                  "user/repo#abc123", "https://github.com/u/r/tarball/main", "https://gist.github.com/u/abc",
                  "https://example.com/r.git", "foo@github:u/r", "foo@user/repo#abc123", "foo@npm:user/repo",
                  "npm:user/repo", "user/repo#", "my-org/my.repo_2", "foo@npm:my-org/my.repo_2"):
        check("git source: " + value, D.is_git_source(other(value)), True)
    for value in ("./local", "../x", "/abs/path", "file:../x", "link:../x", "workspace:*", "x.tgz", "dist/x.tgz",
                  "user/x.tar.gz", "https://example.com/x.tgz", "https://notgithub.com/x", "foo@file:../foo",
                  "foo@npm:./local", "@scope/name",
                  # One shape (vetting_record.NPM_GIT_SHORTHAND_RE): no dots or leading hyphen in the owner.
                  "1.2.3/evil", "user.name/repo", "-user/repo", "a/b/c", "foo@1.2.3/evil", "foo@user.name/repo",
                  "foo@npm:1.2.3/evil", "npm:user.name/repo"):
        check("not a git source: " + value, D.is_git_source(other(value)), False)
    check("pip: owner/repo is a local directory, not git", D.is_git_source(other("reqs/dev.txt", eco="pypi")), False)
    check("pip: a git+ URL is git", D.is_git_source(other("git+https://github.com/u/r", eco="pypi")), True)
    check("manifest: the value (version) decides, not the key",
          D.is_git_source(other("user/repo", version="file:../x")), False)
    check("manifest: a git value on an ordinary key", D.is_git_source(other("foo", version="github:u/r")), True)
    check_in("the warning text", D.GIT_HOST_WARNING, D.msg_not_registry(other("github:u/r")))
    check("a non-git ask carries no warning", "git host" in D.msg_not_registry(other("file:../x")), False)


def run_emit(decisions, log_failed=False):
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        rc = D.emit(decisions, log_failed)
    return rc, buffer.getvalue()


def test_emit():
    deny = D.Decision("deny", "d1", "deny", "npm", "a", "1")
    deny2 = D.Decision("deny", "d2", "deny", "npm", "b", "1")
    ask = D.Decision("ask", "a1", "ask", "npm", "c", "1")
    check("nothing decided -> allow, silent", run_emit([]), (0, ""))
    check("deny beats ask; one line per deny", run_emit([ask, deny, deny2]), (2, "d1\nd2\n"))
    rc, out = run_emit([ask, ask])
    check("asks are one compact line joined by '; '", (rc, out.startswith('{"hookSpecificOutput":{"hookEventName":"PreToolUse"')), (0, True))
    check_in("clauses joined", '"permissionDecisionReason":"a1; a1"', out)
    check("a failed log write is appended to a deny", run_emit([deny], True), (2, "d1 (log write failed)\n"))
    check_in("and to an ask", "a1 (log write failed)", run_emit([ask], True)[1])


def test_logging():
    with tempfile.TemporaryDirectory() as state:
        entry = D.Decision("ask", "why\twith\ntabs", "ask", "npm", "zod", "3.23.8")
        check("append succeeds", D.append_log(state, NOW, "sess", [entry, entry]), True)
        with open(os.path.join(state, D.STATE_LOG)) as handle:
            lines = handle.read().splitlines()
        check("one line per entry", len(lines), 2)
        check("seven fields", len(lines[0].split("\t")), 7)
        check("timestamp is UTC ISO", lines[0].split("\t")[0], "2026-10-14T12:00:00Z")
        check("separators in the reason are neutralised", lines[0].split("\t")[6], "why?with?tabs")
        check("mode 0600", oct(os.stat(os.path.join(state, D.STATE_LOG)).st_mode & 0o777), "0o600")
    with tempfile.TemporaryDirectory() as state:
        os.mkdir(os.path.join(state, D.STATE_LOG))
        check("an unwritable log is False, not an exception", D.append_log(state, NOW, "s", [entry]), False)


def test_session_id():
    check("payload session wins", D.session_id({"session_id": "abc"}), "abc")
    saved = os.environ.pop("CLAUDE_CODE_SESSION_ID", None)
    try:
        check("fallback literal", D.session_id({}), "nosession")
        check("a non-dict payload falls back", D.session_id(None), "nosession")
        os.environ["CLAUDE_CODE_SESSION_ID"] = "from-env"
        check("env fallback", D.session_id({"session_id": 5}), "from-env")
    finally:
        os.environ.pop("CLAUDE_CODE_SESSION_ID", None)
        if saved is not None:
            os.environ["CLAUDE_CODE_SESSION_ID"] = saved


def main():
    for fn in (test_clean, test_format_age, test_spellings, test_local_copy_advice, test_decide_intent,
               test_update_and_indirect, test_update_decisions_end_to_end, test_git_source, test_emit, test_logging, test_session_id):
        fn()
    print("\ndecide-dependency unit: {} passed, {} failed".format(PASSED, FAILED))
    return 1 if FAILED else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
