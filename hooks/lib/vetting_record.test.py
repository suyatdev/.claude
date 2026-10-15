#!/usr/bin/env python3
"""Unit tests for vetting_record.py. Run: python3 hooks/lib/vetting_record.test.py

Spec: docs/features/dependency-vetting-guard.md (Contracts: Input validation, "What pinned means",
OSV ecosystem map, Vetting record; D8; Failure handling D7). Every store below is a temp dir --
never hooks/state/ and never $HOME -- and the clock is injected (`now`), so the 7-day boundary is
tested to the second with no sleeping.

Dependency-free (no pytest), same runner shape as classify-pr-command.test.py.
"""

import datetime
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile

MARKER_SELF = os.path.abspath(__file__)
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=os.path.dirname(MARKER_SELF),
                             capture_output=True, text=True, check=True).stdout.strip()

_HERE = os.path.dirname(os.path.abspath(__file__))
_SPEC = importlib.util.spec_from_file_location("vetting_record", os.path.join(_HERE, "vetting_record.py"))
vr = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(vr)

UTC = datetime.timezone.utc
NOW = datetime.datetime(2026, 10, 14, 12, 0, 0, tzinfo=UTC)
DAY = datetime.timedelta(days=1)
SECOND = datetime.timedelta(seconds=1)

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL - {}\n       want {!r}, got {!r}".format(label, want, got))


def rejects(label, fn, *args, **kwargs):
    """The call must raise vr.ValidationError -- any other exception is a bug, not a rejection."""
    global passed, failed
    try:
        result = fn(*args, **kwargs)
    except vr.ValidationError:
        passed += 1
        return
    except Exception as exc:  # noqa: BLE001 - report the wrong type, do not hide it
        failed += 1
        print("FAIL - {}\n       want ValidationError, got {}: {}".format(label, type(exc).__name__, exc))
        return
    failed += 1
    print("FAIL - {}\n       want ValidationError, got return {!r}".format(label, result))


# ---------------------------------------------------------------- constants and the OSV map

check("ECOSYSTEMS is the six literals, in spec order",
      tuple(vr.ECOSYSTEMS), ("npm", "pypi", "crates.io", "go", "rubygems", "homebrew"))
check("VET_MAX_AGE_DAYS is 7", vr.VET_MAX_AGE_DAYS, 7)
check("SCHEMA_VERSION is 1", vr.SCHEMA_VERSION, 1)
check("OSV map is exactly the five spec entries (homebrew absent)", dict(vr.OSV_ECOSYSTEMS), {
    "npm": "npm", "pypi": "PyPI", "crates.io": "crates.io", "go": "Go", "rubygems": "RubyGems"})
for eco, osv in [("npm", "npm"), ("pypi", "PyPI"), ("crates.io", "crates.io"), ("go", "Go"),
                 ("rubygems", "RubyGems")]:
    check("osv_ecosystem({})".format(eco), vr.osv_ecosystem(eco), osv)
check("osv_ecosystem(homebrew) is None (D8: no OSV ecosystem)", vr.osv_ecosystem("homebrew"), None)
rejects("osv_ecosystem of an unknown ecosystem", vr.osv_ecosystem, "maven")
try:
    vr.OSV_ECOSYSTEMS["npm"] = "x"
    check("OSV map is read-only", "mutable", "read-only")
except TypeError:
    check("OSV map is read-only", "read-only", "read-only")

# ---------------------------------------------------------------- ecosystem

for eco in vr.ECOSYSTEMS:
    check("validate_ecosystem accepts " + eco, vr.validate_ecosystem(eco), eco)
for bad in ["NPM", "PyPI", "", "maven", "npm ", "homebrew\n", "crates", None, 5, b"npm"]:
    rejects("validate_ecosystem refuses {!r}".format(bad), vr.validate_ecosystem, bad)

# ---------------------------------------------------------------- name

VALID_NAMES = [
    ("npm", "zod"), ("npm", "left-pad"), ("npm", "a"), ("npm", "@types/node"), ("npm", "@a/b"),
    ("npm", "x" * 214), ("pypi", "requests"), ("pypi", "zope.interface"), ("pypi", "a_b-c.d"),
    ("crates.io", "serde"), ("go", "golang.org/x/text"), ("go", "github.com/a/b/c/d/v2"),
    ("rubygems", "rails"), ("homebrew", "jq"), ("homebrew", "user/tap/formula"),
    ("homebrew", "python@3.12"),
]
for eco, name in VALID_NAMES:
    check("validate_name accepts {} {!r}".format(eco, name[:30]), vr.validate_name(eco, name), name)

COMMON_BAD_NAMES = ["", ".", "..", "a..b", "..a", "a..", "/a", "a/", "a//b", "a b", "a\n", "\na",
                    "a\x00b", "a;b", "a$b", "a\\b", "a\tb", "a:b", "ｚod", "é", "x" * 215,
                    "../x", "x/..", "a/../b", None, 5, b"zod"]
for eco in vr.ECOSYSTEMS:
    for bad in COMMON_BAD_NAMES:
        rejects("validate_name {} refuses {!r}".format(eco, bad), vr.validate_name, eco, bad)
rejects("go: dot-dot inside a module path", vr.validate_name, "go", "golang.org/x/../y")
rejects("go: double slash", vr.validate_name, "go", "golang.org//x")

# Slash count by ecosystem: npm <= 1 and only as @scope/name; homebrew <= 2; pypi, crates, rubygems 0.
for eco, bad in [("npm", "a/b"), ("npm", "@a/b/c"), ("npm", "@scope"), ("npm", "@/b"), ("npm", "a/@b"),
                 ("pypi", "a/b"), ("crates.io", "a/b"), ("rubygems", "a/b"),
                 ("homebrew", "a/b/c/d")]:
    rejects("slash rule: {} refuses {!r}".format(eco, bad), vr.validate_name, eco, bad)
rejects("validate_name checks the ecosystem too", vr.validate_name, "maven", "zod")

# No leading "-": as an argv element it reads as an option to `brew info` and to the vetter. Every
# ecosystem, because the vetter's own argv is shared; the first character is what matters.
for eco in vr.ECOSYSTEMS:
    for bad in ["-x", "--help", "-", "--", "-rf", "-a-b", "-golang.org/x/text"]:
        rejects("leading dash: {} refuses {!r}".format(eco, bad), vr.validate_name, eco, bad)
    for ok in ["a-", "a-b", "x--y"]:
        check("a dash after the first character is fine: {} {!r}".format(eco, ok), vr.validate_name(eco, ok), ok)
# A dash right after `@scope/` is NOT refused: the argument still starts with "@", so neither npm
# nor the vetter can read it as an option (decision recorded in the task report).
check("npm @scope/-x is accepted (argv starts with @)", vr.validate_name("npm", "@scope/-x"), "@scope/-x")
check("homebrew tap/-x is accepted (argv starts with a letter)",
      vr.validate_name("homebrew", "user/-x"), "user/-x")
rejects("record_path refuses a leading-dash name", vr.record_path, "/nonexistent-store", "npm", "-x", "1.0.0")
check("safe_name replaces / with __", vr.safe_name("golang.org/x/text"), "golang.org__x__text")
check("safe_name keeps an npm scope's @", vr.safe_name("@types/node"), "@types__node")
check("safe_name leaves a plain name alone", vr.safe_name("zod"), "zod")
# "../x" is deliberately absent: safe_name("../x") is "..__x", a legal file name; validate_name
# is what refuses it (covered above and through record_path). "." and ".." alone are refused here.
for bad in ["", ".", "..", "a b", "a\n", "a:b", "ｚod", None]:
    rejects("safe_name refuses {!r}".format(bad), vr.safe_name, bad)

# ---------------------------------------------------------------- is_exact_version (the one definition)

ACCEPT = {
    "npm": ["3.23.8", "1.0.0-rc.1", "1.0.0+build.5", "0.0.0", "10.20.30", "1.0.0-rc.1+build.5"],
    "crates.io": ["3.23.8", "1.0.0-rc.1", "1.0.0+build.5", "1.0.210"],
    "pypi": ["2.32.3", "1.0rc1", "2.1.0+cu118", "2.1.0+CU118", "1", "1.0", "1.0a1", "1.0b2",
             "1.0.post1", "1.0.dev3", "1.0rc1.post2.dev3+local.1"],
    "go": ["v0.3.8", "v1.2.3-pre.1", "v2.0.0+incompatible", "v1.2.3-pre.1+incompatible"],
    "rubygems": ["7.1.3", "1.0.0.pre", "13.0", "1.0.0.rc1"],
}
# Refused by every ecosystem's pattern (spec: "refused by all four", checked 2026-10-13).
REFUSED_EVERYWHERE = ["2.32.3/../evil", "^1.0.0", "1.x", "latest", "~1.2.3", "*", ">=1.0", "=1.2.3",
                      "1.2.3/..", "..", "1.0.0-a..b", "1.0.0+..", "1.0.0-..", "v1.0.0-..",
                      "３.２３.８", "3.23.8\n", "", " 3.23.8", "3.23.8 ", "v", "1..2"]
for eco, values in ACCEPT.items():
    for value in values:
        check("is_exact_version({}, {!r}) accepted".format(eco, value), vr.is_exact_version(eco, value), True)
for eco in ["npm", "crates.io", "pypi", "go", "rubygems"]:
    for value in REFUSED_EVERYWHERE:
        check("is_exact_version({}, {!r}) refused".format(eco, value), vr.is_exact_version(eco, value), False)
# Leading zeros: refused by the N-based patterns (npm, crates.io, go, rubygems), not by pypi's.
for eco, value in [("npm", "01.2.3"), ("npm", "1.02.3"), ("crates.io", "01.2.3"), ("crates.io", "1.2.03"),
                   ("go", "v01.2.3"), ("go", "v1.02.3"), ("rubygems", "01.2.3"), ("rubygems", "1.02.3")]:
    check("is_exact_version({}, {!r}) refused (leading zero)".format(eco, value),
          vr.is_exact_version(eco, value), False)
# Each ecosystem's pattern is its own: a value valid for one is not valid for another.
for eco, value in [("npm", "v1.2.3"), ("npm", "1.0"), ("npm", "1.0rc1"), ("go", "1.2.3"), ("go", "v1.0"),
                   ("go", "v1.2.3+other"), ("pypi", "v1.0"), ("pypi", "1.0.0-rc.1"),
                   ("rubygems", "1"), ("rubygems", "1.0.0-rc.1"), ("crates.io", "1.0"),
                   ("pypi", "1.0.0+"), ("pypi", "1.0.0+a..b")]:
    check("is_exact_version({}, {!r}) refused (wrong shape)".format(eco, value),
          vr.is_exact_version(eco, value), False)
check("is_exact_version(homebrew, anything) is False (D8: never consulted)",
      [vr.is_exact_version("homebrew", v) for v in ("1.7.1", "3.23.8", None, "")], [False] * 4)
for eco in ["npm", "pypi", "crates.io", "go", "rubygems"]:
    for value in [None, 3, 3.5, b"3.23.8", ["3.23.8"], True]:
        check("is_exact_version({}, {!r}) is False for a non-string".format(eco, value),
              vr.is_exact_version(eco, value), False)
rejects("is_exact_version of an unknown ecosystem", vr.is_exact_version, "maven", "1.0.0")

# validate_version: the vetter's rule -- required, except homebrew where it must be absent (D8).
check("validate_version returns a pinned value", vr.validate_version("npm", "3.23.8"), "3.23.8")
check("validate_version(homebrew, None) is None", vr.validate_version("homebrew", None), None)
for eco, bad in [("npm", None), ("npm", "^3.23.8"), ("npm", "../../x"), ("npm", "2.32.3/../evil"),
                 ("npm", "latest"), ("pypi", "1.x"), ("homebrew", "1.7.1"), ("homebrew", "")]:
    rejects("validate_version({}, {!r})".format(eco, bad), vr.validate_version, eco, bad)

# ---------------------------------------------------------------- helpers


def make_record(ecosystem="npm", name="zod", version="3.23.8", vetted_at=None, **override):
    if vetted_at is None:
        vetted_at = NOW - DAY
    stamp = vr.format_vetted_at(vetted_at) if isinstance(vetted_at, datetime.datetime) else vetted_at
    record = {
        "schema": 1, "ecosystem": ecosystem, "name": name, "version": version, "vetted_at": stamp,
        "complete": True, "incomplete_reasons": [],
        "signals": [{"check": "direct_vulns", "status": "ok", "detail": "0 advisories"}],
        "report": "hooks/state/vetting/{}/{}/{}.md".format(ecosystem, name.replace("/", "__"), version),
    }
    record.update(override)
    return record


def plant(store, ecosystem, name, version, text):
    """Write a file where the store layout says a record lives, computing the path independently
    of vetting_record so a bug in record_path cannot make a test agree with itself."""
    directory = os.path.join(store, ecosystem, name.replace("/", "__"))
    os.makedirs(directory, exist_ok=True)
    path = os.path.join(directory, version + ".json")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def plant_record(store, record):
    return plant(store, record["ecosystem"], record["name"], record["version"], json.dumps(record))


def mode_of(path):
    return stat.S_IMODE(os.stat(path).st_mode)


# ---------------------------------------------------------------- timestamps and the 7-day boundary

check("format_vetted_at", vr.format_vetted_at(NOW), "2026-10-14T12:00:00Z")
check("format_vetted_at converts an offset to UTC",
      vr.format_vetted_at(datetime.datetime(2026, 10, 14, 14, 0, 0, tzinfo=datetime.timezone(
          datetime.timedelta(hours=2)))), "2026-10-14T12:00:00Z")
check("parse_vetted_at round-trips", vr.parse_vetted_at("2026-10-14T12:00:00Z"), NOW)
for bad in ["2026-10-14", "2026-10-14T12:00:00", "2026-10-14T12:00:00+00:00", "2026-10-14T12:00:00z",
            "2026-10-14T12:00:00Z\n", "2026-1-4T1:0:0Z", "2026-13-14T12:00:00Z", "2026-10-14 12:00:00Z",
            "", None, 20261014]:
    rejects("parse_vetted_at refuses {!r}".format(bad), vr.parse_vetted_at, bad)
rejects("format_vetted_at refuses a naive datetime", vr.format_vetted_at, datetime.datetime(2026, 10, 14))

week = datetime.timedelta(days=7)
for label, age, fresh in [
        ("0 seconds old", datetime.timedelta(0), True),
        ("1 day old", DAY, True),
        ("7 days minus 1 second", week - SECOND, True),
        ("EXACTLY 7 days -- stale (spec: fresh while now - vetted_at < 7 days)", week, False),
        ("7 days plus 1 second", week + SECOND, False),
        ("8 days", 8 * DAY, False),
        ("1 second in the future -- not trusted (a forged date must not live forever)", -SECOND, False),
        ("30 days in the future", -30 * DAY, False)]:
    check("is_fresh: " + label, vr.is_fresh(make_record(vetted_at=NOW - age), NOW), fresh)
rejects("is_fresh refuses a naive clock", vr.is_fresh, make_record(), datetime.datetime(2026, 10, 14))

# ---------------------------------------------------------------- validate_record (schema)

good = make_record()
check("validate_record returns a good record", vr.validate_record(good), good)
check("validate_record accepts incomplete with reasons",
      vr.validate_record(make_record(complete=False, incomplete_reasons=["transitive scan unsupported for pypi"]))["complete"],
      False)
check("validate_record accepts a homebrew record keyed on brew's stable version",
      vr.validate_record(make_record("homebrew", "jq", "1.7.1", complete=False,
                                     incomplete_reasons=["no OSV ecosystem"]))["version"], "1.7.1")
check("validate_record accepts every signal status",
      len(vr.validate_record(make_record(signals=[
          {"check": "c" + s, "status": s, "detail": "d"} for s in ("ok", "stop", "caution", "not_run")]))["signals"]),
      4)
check("validate_record accepts an empty signals list", vr.validate_record(make_record(signals=[]))["signals"], [])

BAD_RECORDS = [
    ("schema 2", make_record(schema=2)),
    ("schema '1' (string)", make_record(schema="1")),
    ("schema True (bool == 1 in Python)", make_record(schema=True)),
    ("schema 1.0 (float)", make_record(schema=1.0)),
    ("ecosystem unknown", make_record(ecosystem="maven")),
    ("name has ..", make_record(name="a..b")),
    ("name npm unscoped slash", make_record(name="a/b")),
    ("name with a leading dash", make_record(name="-x")),
    ("version a range", make_record(version="^3.23.8")),
    ("version with path parts", make_record(version="2.32.3/../evil")),
    ("homebrew version with a slash", make_record("homebrew", "jq", "1.7/../x")),
    ("homebrew version ..", make_record("homebrew", "jq", "..")),
    ("homebrew version empty", make_record("homebrew", "jq", "")),
    ("vetted_at with an offset", make_record(vetted_at="2026-10-13T12:00:00+00:00")),
    ("vetted_at not a string", make_record(vetted_at=1760443200)),
    ("complete not a bool", make_record(complete="true")),
    ("complete an int", make_record(complete=1)),
    ("incomplete_reasons not a list", make_record(incomplete_reasons="none")),
    ("incomplete_reasons holds a non-string", make_record(incomplete_reasons=[1])),
    ("signals not a list", make_record(signals={})),
    ("signal not an object", make_record(signals=["ok"])),
    ("signal status unknown", make_record(signals=[{"check": "c", "status": "fine", "detail": "d"}])),
    ("signal missing detail", make_record(signals=[{"check": "c", "status": "ok"}])),
    ("signal check not a string", make_record(signals=[{"check": 1, "status": "ok", "detail": "d"}])),
    ("report not a string", make_record(report=None)),
    ("report empty", make_record(report="")),
]
for key in ["schema", "ecosystem", "name", "version", "vetted_at", "complete", "incomplete_reasons",
            "signals", "report"]:
    missing = make_record()
    del missing[key]
    BAD_RECORDS.append(("missing key " + key, missing))
for label, record in BAD_RECORDS:
    rejects("validate_record refuses: " + label, vr.validate_record, record)
for label, value in [("a list", []), ("a string", "x"), ("None", None), ("a number", 1)]:
    rejects("validate_record refuses " + label, vr.validate_record, value)

# ---------------------------------------------------------------- record_path (validation + containment)

WORK = tempfile.mkdtemp(prefix="vetting-record-test-")


def fresh_store():
    path = tempfile.mkdtemp(dir=WORK)
    return os.path.join(path, "vetting")


try:
    store = fresh_store()
    real_store = os.path.realpath(store)
    check("record_path lays out <eco>/<safe-name>/<version>.json",
          vr.record_path(store, "npm", "zod", "3.23.8"), os.path.join(store, "npm", "zod", "3.23.8.json"))
    check("record_path uses safe-name for a scope",
          vr.record_path(store, "npm", "@types/node", "20.1.0"),
          os.path.join(store, "npm", "@types__node", "20.1.0.json"))
    check("record_path uses safe-name for a go module",
          vr.record_path(store, "go", "golang.org/x/text", "v0.3.8"),
          os.path.join(store, "go", "golang.org__x__text", "v0.3.8.json"))
    check("record_path takes a homebrew version as the key",
          vr.record_path(store, "homebrew", "jq", "1.7.1"), os.path.join(store, "homebrew", "jq", "1.7.1.json"))
    check("report_path is the .md beside the record",
          vr.report_path(store, "npm", "zod", "3.23.8"), os.path.join(store, "npm", "zod", "3.23.8.md"))
    check("record_path result stays inside the real store",
          os.path.realpath(vr.record_path(store, "npm", "zod", "3.23.8")).startswith(real_store + os.sep), True)
    rejects("record_path: version ../../x", vr.record_path, store, "npm", "zod", "../../x")
    rejects("record_path: version with / and ..", vr.record_path, store, "npm", "zod", "2.32.3/../evil")
    rejects("record_path: version with a bare /", vr.record_path, store, "pypi", "requests", "2.32.3/x")
    rejects("record_path: version None for npm", vr.record_path, store, "npm", "zod", None)
    rejects("record_path: version None for homebrew", vr.record_path, store, "homebrew", "jq", None)
    rejects("record_path: name ../x", vr.record_path, store, "npm", "../x", "1.0.0")
    rejects("record_path: name with ..", vr.record_path, store, "go", "a/../../b", "v1.0.0")
    rejects("record_path: unknown ecosystem", vr.record_path, store, "maven", "zod", "1.0.0")
    rejects("record_path: homebrew version with /", vr.record_path, store, "homebrew", "jq", "1/2")
    rejects("record_path: homebrew version ..", vr.record_path, store, "homebrew", "jq", "..")
    rejects("record_path: homebrew version .", vr.record_path, store, "homebrew", "jq", ".")

    # A path that resolves OUTSIDE the store: a symlinked ecosystem dir, name dir and record file.
    outside = os.path.join(WORK, "outside")
    os.makedirs(outside)
    os.makedirs(store)
    os.symlink(outside, os.path.join(store, "pypi"))
    rejects("record_path: ecosystem dir symlinked outside the store",
            vr.record_path, store, "pypi", "requests", "2.32.3")
    os.makedirs(os.path.join(store, "npm"))
    os.symlink(outside, os.path.join(store, "npm", "evil"))
    rejects("record_path: name dir symlinked outside the store", vr.record_path, store, "npm", "evil", "1.0.0")
    os.makedirs(os.path.join(store, "npm", "zod"))
    os.symlink(os.path.join(outside, "x.json"), os.path.join(store, "npm", "zod", "3.23.8.json"))
    rejects("record_path: record file symlinked outside the store",
            vr.record_path, store, "npm", "zod", "3.23.8")
    rejects("report_path: containment applies to the report too",
            vr.report_path, store, "pypi", "requests", "2.32.3")

    # ------------------------------------------------------------ read_record

    store = fresh_store()
    record = make_record()
    plant_record(store, record)
    check("read_record returns a good record", vr.read_record(store, "npm", "zod", "3.23.8"), (record, None))
    got, problem = vr.read_record(store, "npm", "zod", "9.9.9")
    check("read_record: no file -> (None, reason)", (got, isinstance(problem, str) and bool(problem)), (None, True))
    got, problem = vr.read_record(store, "npm", "zod", "../../x")
    check("read_record: invalid key -> (None, reason), never raises",
          (got, isinstance(problem, str) and bool(problem)), (None, True))
    got, problem = vr.read_record(store, "maven", "zod", "1.0.0")
    check("read_record: invalid ecosystem -> (None, reason)", (got, bool(problem)), (None, True))

    BAD_FILES = [
        ("empty file", ""),
        ("not JSON", "this is not json"),
        ("truncated JSON", json.dumps(record)[:40]),
        ("JSON null", "null"),
        ("JSON list", "[]"),
        ("JSON string", '"hi"'),
        ("wrong schema number", json.dumps(make_record(schema=2))),
        ("wrong schema type", json.dumps(make_record(schema="1"))),
        ("a field with the wrong type", json.dumps(make_record(complete="yes"))),
        ("a missing field", json.dumps({k: v for k, v in record.items() if k != "signals"})),
        ("deeply nested JSON", "[" * 100000),
    ]
    for label, text in BAD_FILES:
        sandbox = fresh_store()
        plant(sandbox, "npm", "zod", "3.23.8", text)
        got, problem = vr.read_record(sandbox, "npm", "zod", "3.23.8")
        check("read_record: {} -> no record".format(label), (got, bool(problem)), (None, True))
    sandbox = fresh_store()
    directory = os.path.join(sandbox, "npm", "zod")
    os.makedirs(directory)
    with open(os.path.join(directory, "3.23.8.json"), "wb") as fh:
        fh.write(b"\xff\xfe\x00not utf-8")
    got, problem = vr.read_record(sandbox, "npm", "zod", "3.23.8")
    check("read_record: undecodable bytes -> no record", (got, bool(problem)), (None, True))
    sandbox = fresh_store()
    os.makedirs(os.path.join(sandbox, "npm", "zod", "3.23.8.json"))
    got, problem = vr.read_record(sandbox, "npm", "zod", "3.23.8")
    check("read_record: a directory where the file belongs -> no record", (got, bool(problem)), (None, True))

    # A valid record filed under the wrong key must not answer for that key.
    for label, wrong in [("wrong name", make_record(name="left-pad")),
                         ("wrong version", make_record(version="3.23.9")),
                         ("wrong ecosystem", make_record(ecosystem="pypi", name="zod", version="3.23.8"))]:
        sandbox = fresh_store()
        plant(sandbox, "npm", "zod", "3.23.8", json.dumps(wrong))
        got, problem = vr.read_record(sandbox, "npm", "zod", "3.23.8")
        check("read_record: record filed under another key ({}) -> no record".format(label),
              (got, bool(problem)), (None, True))

    # Symlinked record file pointing outside the store: valid JSON, but outside -> no record.
    sandbox = fresh_store()
    os.makedirs(os.path.join(sandbox, "npm", "zod"))
    target = os.path.join(WORK, "outside", "planted.json")
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(record))
    os.symlink(target, os.path.join(sandbox, "npm", "zod", "3.23.8.json"))
    got, problem = vr.read_record(sandbox, "npm", "zod", "3.23.8")
    check("read_record: symlink to a file outside the store -> no record", (got, bool(problem)), (None, True))

    # ------------------------------------------------------------ read_fresh_record (expiry at the boundary)

    for label, age, fresh in [("6 days", 6 * DAY, True), ("7 days minus 1 second", week - SECOND, True),
                              ("exactly 7 days", week, False), ("7 days plus 1 second", week + SECOND, False),
                              ("8 days", 8 * DAY, False)]:
        sandbox = fresh_store()
        stored = make_record(vetted_at=NOW - age)
        plant_record(sandbox, stored)
        got, problem = vr.read_fresh_record(sandbox, "npm", "zod", "3.23.8", NOW)
        if fresh:
            check("read_fresh_record: {} -> record".format(label), (got, problem), (stored, None))
        else:
            check("read_fresh_record: {} -> stale".format(label),
                  (got, isinstance(problem, str) and problem.startswith("stale")), (None, True))
    got, problem = vr.read_fresh_record(store, "npm", "zod", "9.9.9", NOW)
    check("read_fresh_record: no file -> no record", (got, bool(problem)), (None, True))
    sandbox = fresh_store()
    plant(sandbox, "npm", "zod", "3.23.8", "not json")
    got, problem = vr.read_fresh_record(sandbox, "npm", "zod", "3.23.8", NOW)
    check("read_fresh_record: bad JSON -> no record", (got, bool(problem)), (None, True))

    # ------------------------------------------------------------ Homebrew newest-fresh-record lookup (D8)

    store = fresh_store()
    for version, age in [("1.6", 5 * DAY), ("1.7.1", DAY), ("1.7", 9 * DAY)]:
        plant_record(store, make_record("homebrew", "jq", version, vetted_at=NOW - age, complete=False,
                                        incomplete_reasons=["no OSV ecosystem"]))
    plant_record(store, make_record("homebrew", "jqx", "9.9", vetted_at=NOW))
    plant_record(store, make_record("npm", "jq", "1.0.0", vetted_at=NOW))
    got, problem = vr.newest_fresh_homebrew_record(store, "jq", NOW)
    check("homebrew lookup picks the newest fresh record by vetted_at",
          (got["version"] if got else None, problem), ("1.7.1", None))
    check("homebrew lookup ignores another formula's records and other ecosystems",
          got["name"] if got else None, "jq")

    sandbox = fresh_store()
    # "1.9" sorts after "1.10" as a string, so a lookup keyed on the version picks the wrong one.
    for version, age in [("1.9", 3 * DAY), ("1.10", DAY)]:
        plant_record(sandbox, make_record("homebrew", "jq", version, vetted_at=NOW - age))
    got, _ = vr.newest_fresh_homebrew_record(sandbox, "jq", NOW)
    check("homebrew lookup orders by vetted_at, not by version string",
          got["version"] if got else None, "1.10")

    sandbox = fresh_store()
    plant_record(sandbox, make_record("homebrew", "jq", "1.7", vetted_at=NOW - week))
    plant_record(sandbox, make_record("homebrew", "jq", "1.6", vetted_at=NOW - week - DAY))
    got, problem = vr.newest_fresh_homebrew_record(sandbox, "jq", NOW)
    check("homebrew lookup: only stale records (one exactly 7 days old) -> none",
          (got, bool(problem)), (None, True))

    got, problem = vr.newest_fresh_homebrew_record(store, "wget", NOW)
    check("homebrew lookup: no directory for the formula -> none", (got, bool(problem)), (None, True))
    got, problem = vr.newest_fresh_homebrew_record(fresh_store(), "jq", NOW)
    check("homebrew lookup: no store at all -> none", (got, bool(problem)), (None, True))

    sandbox = fresh_store()
    plant_record(sandbox, make_record("homebrew", "jq", "1.6", vetted_at=NOW - 2 * DAY))
    plant(sandbox, "homebrew", "jq", "1.8", "not json")                       # newer name, corrupt
    plant(sandbox, "homebrew", "jq", "1.9", json.dumps(make_record(schema=2)))  # wrong schema
    plant(sandbox, "homebrew", "jq", "2.0", json.dumps(make_record("homebrew", "jq", "9.9",
                                                                    vetted_at=NOW)))  # filed under wrong key
    with open(os.path.join(sandbox, "homebrew", "jq", "1.6.md"), "w", encoding="utf-8") as fh:
        fh.write("report, not a record")
    with open(os.path.join(sandbox, "homebrew", "jq", ".record-x.tmp"), "w", encoding="utf-8") as fh:
        fh.write("{}")
    got, problem = vr.newest_fresh_homebrew_record(sandbox, "jq", NOW)
    check("homebrew lookup skips corrupt, wrong-schema, misfiled and non-.json entries",
          (got["version"] if got else None, problem), ("1.6", None))

    sandbox = fresh_store()
    plant(sandbox, "homebrew", "jq", "1.6", "not json")
    got, problem = vr.newest_fresh_homebrew_record(sandbox, "jq", NOW)
    check("homebrew lookup: only corrupt records -> none", (got, bool(problem)), (None, True))

    for bad in ["../x", "a/b/c/d", "", ".", "a b", None]:
        got, problem = vr.newest_fresh_homebrew_record(store, bad, NOW)
        check("homebrew lookup: invalid name {!r} -> none, never raises".format(bad),
              (got, bool(problem)), (None, True))

    sandbox = fresh_store()
    os.makedirs(sandbox)
    elsewhere = os.path.join(WORK, "elsewhere")
    os.makedirs(os.path.join(elsewhere, "jq"))
    with open(os.path.join(elsewhere, "jq", "1.7.1.json"), "w", encoding="utf-8") as fh:
        fh.write(json.dumps(make_record("homebrew", "jq", "1.7.1")))
    os.symlink(elsewhere, os.path.join(sandbox, "homebrew"))
    got, problem = vr.newest_fresh_homebrew_record(sandbox, "jq", NOW)
    check("homebrew lookup: ecosystem dir symlinked outside the store -> none", (got, bool(problem)), (None, True))

    # a user/tap/formula name is stored under safe-name
    sandbox = fresh_store()
    plant_record(sandbox, make_record("homebrew", "user/tap/formula", "2.0", vetted_at=NOW - DAY))
    got, _ = vr.newest_fresh_homebrew_record(sandbox, "user/tap/formula", NOW)
    check("homebrew lookup works for a tap-qualified name", got["version"] if got else None, "2.0")

    # ------------------------------------------------------------ write_record

    old_umask = os.umask(0)  # hostile umask: modes must come from the code, not the environment
    try:
        store = fresh_store()
        record = make_record("npm", "@types/node", "20.1.0")
        path = vr.write_record(store, record)
        check("write_record returns the record path", path, vr.record_path(store, "npm", "@types/node", "20.1.0"))
        check("write_record lands where the layout says",
              path, os.path.join(store, "npm", "@types__node", "20.1.0.json"))
        check("write_record file is mode 0600", mode_of(path), 0o600)
        for level in [store, os.path.join(store, "npm"), os.path.join(store, "npm", "@types__node")]:
            check("write_record dir {} is mode 0700".format(os.path.relpath(level, store)), mode_of(level), 0o700)
        check("write_record round-trips through read_record",
              vr.read_record(store, "npm", "@types/node", "20.1.0"), (record, None))
        check("write_record leaves no temp files",
              sorted(os.listdir(os.path.dirname(path))), ["20.1.0.json"])
        with open(path, encoding="utf-8") as fh:
            check("write_record writes JSON ending in a newline", fh.read().endswith("}\n"), True)

        newer = make_record("npm", "@types/node", "20.1.0", complete=False, incomplete_reasons=["x"])
        vr.write_record(store, newer)
        check("write_record replaces an existing record", vr.read_record(store, "npm", "@types/node", "20.1.0")[0],
              newer)
        check("write_record overwrite keeps mode 0600", mode_of(path), 0o600)

        brew = make_record("homebrew", "jq", "1.7.1", complete=False, incomplete_reasons=["no OSV ecosystem"])
        vr.write_record(store, brew)
        check("write_record: homebrew record is found by the lookup",
              vr.newest_fresh_homebrew_record(store, "jq", NOW), (brew, None))

        # pre-existing directories keep their mode (only directories the code creates are set 0700)
        existing = fresh_store()
        os.makedirs(existing, mode=0o755)
        vr.write_record(existing, make_record())
        check("write_record does not re-chmod a store that already exists", mode_of(existing), 0o755)

        # invalid input writes nothing
        sandbox = fresh_store()
        rejects("write_record refuses a bad record", vr.write_record, sandbox, make_record(schema=2))
        rejects("write_record refuses a range version", vr.write_record, sandbox, make_record(version="^1.0.0"))
        rejects("write_record refuses a traversal version",
                vr.write_record, sandbox, make_record(version="2.32.3/../evil"))
        rejects("write_record refuses a non-dict", vr.write_record, sandbox, [])
        check("write_record of invalid input creates nothing", os.path.exists(sandbox), False)

        # a path that resolves outside the store writes nothing outside it
        sandbox = fresh_store()
        stray = os.path.join(WORK, "stray")
        os.makedirs(stray)
        os.makedirs(sandbox)
        os.symlink(stray, os.path.join(sandbox, "npm"))
        rejects("write_record refuses an ecosystem dir symlinked outside the store",
                vr.write_record, sandbox, make_record())
        check("write_record writes nothing outside the store", os.listdir(stray), [])

        # a write failure removes its temp file and raises (never swallowed)
        if os.geteuid() != 0:
            sandbox = fresh_store()
            vr.write_record(sandbox, make_record())
            locked = os.path.join(sandbox, "npm", "zod")
            os.chmod(locked, 0o500)
            try:
                try:
                    vr.write_record(sandbox, make_record(complete=False, incomplete_reasons=["y"]))
                    check("write_record into a read-only dir raises", "returned", "raised")
                except OSError:
                    check("write_record into a read-only dir raises", "raised", "raised")
            finally:
                os.chmod(locked, 0o700)
            check("a failed write leaves the old record and no temp file",
                  sorted(os.listdir(locked)), ["3.23.8.json"])
            check("a failed write leaves the old record unchanged",
                  vr.read_record(sandbox, "npm", "zod", "3.23.8")[0]["complete"], True)

        # reports
        sandbox = fresh_store()
        report = vr.write_report(sandbox, "npm", "zod", "3.23.8", "# report\n")
        check("write_report path", report, os.path.join(sandbox, "npm", "zod", "3.23.8.md"))
        check("write_report is mode 0600", mode_of(report), 0o600)
        with open(report, encoding="utf-8") as fh:
            check("write_report content", fh.read(), "# report\n")
        rejects("write_report refuses a traversal version",
                vr.write_report, sandbox, "npm", "zod", "../../x", "x")
        check("a report is not mistaken for a homebrew record",
              vr.newest_fresh_homebrew_record(sandbox, "zod", NOW)[0], None)
    finally:
        os.umask(old_umask)
finally:
    shutil.rmtree(WORK, ignore_errors=True)


def main():
    print("\nvetting_record unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
