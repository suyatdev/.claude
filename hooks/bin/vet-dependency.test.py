#!/usr/bin/env python3
"""CLI-level tests for hooks/bin/vet-dependency. Run from the repo root:
    python3 hooks/bin/vet-dependency.test.py
    VET_LIVE_SMOKE=1 python3 hooks/bin/vet-dependency.test.py   # opt-in, contacts the real registries

Covers exit codes, the report and record files, and "nothing written on failure". The checks
themselves are tested in hooks/lib/vet_checks.test.py. Every record goes to a mkdtemp store, never
hooks/state/ and never $HOME; HTTP is replayed from hand-written fixtures and the whole run sits
behind a trap that raises on any connection. The live smoke test is the one exception and is skipped
unless VET_LIVE_SMOKE=1.

Not paired for the commit gate: the guard pairs only X.sh/X.test.sh and X.py/X.test.py, and
`vet-dependency` has no extension -- so this file writes no marker (hooks/lib/vet_checks.test.py does).
"""

import datetime
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE, capture_output=True, text=True,
                      check=True).stdout.strip()
SCRIPT = os.path.join(HERE, "vet-dependency")
sys.path.insert(0, os.path.join(HERE, "fixtures", "vet-dependency"))
sys.path.insert(0, os.path.join(ROOT, "hooks", "lib"))

import replay  # noqa: E402

_LOADER = importlib.machinery.SourceFileLoader("vet_dependency", SCRIPT)
_SPEC = importlib.util.spec_from_loader("vet_dependency", _LOADER)
cli = importlib.util.module_from_spec(_SPEC)
_LOADER.exec_module(cli)
vc, vr, fx = cli.vc, cli.vr, replay.fx

NOW = datetime.datetime(2026, 10, 14, 12, 0, 0, tzinfo=datetime.timezone.utc)
OSV = "https://api.osv.dev/v1/query"
NPM = "https://registry.npmjs.org/"
DL = "https://api.npmjs.org/downloads/point/last-week/"
passed = failed = skipped = 0
TRAP = replay.NetworkTrap().install()
WORK = tempfile.mkdtemp(prefix="vet-cli-test-")


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL - {}\n       want {!r}, got {!r}".format(label, want, got))


def files_under(path):
    return sorted(os.path.join(d, f) for d, _dirs, names in os.walk(path) for f in names)


def new_store():
    return tempfile.mkdtemp(prefix="store-", dir=WORK)


def run(argv, opener, runner=None, installed=(), store=None):
    store = store or new_store()
    out, err = io.StringIO(), io.StringIO()
    ctx = vc.Context(opener=opener, runner=runner or replay.FakeRunner(),
                     which=lambda n: "/fake/bin/" + n if n in installed else None, now=lambda: NOW)
    rc = cli.main(argv, ctx=ctx, store=store, stdout=out, stderr=err)
    return rc, out.getvalue(), err.getvalue(), store


def npm_replay(name="zod", osv="clean", pack="zod_packument", dl="downloads_zod", bulk="downloads_bulk_none_exist"):
    r = replay.Replay()
    r.add("POST", OSV, fx("osv", osv))
    r.add("GET", NPM + name, fx("npm", pack))
    r.add("GET", DL + name, fx("npm", dl))
    r.add("GET", DL, fx("npm", bulk), prefix=True)
    return r


def scanner_runner(scan_rc=0, scan_out="{}"):
    def npm(argv, cwd):
        with open(os.path.join(cwd, "package-lock.json"), "w") as handle:
            json.dump(fx("npm", "lock_zod"), handle)
        return 0, "", ""
    return replay.FakeRunner({"npm": npm, "osv-scanner": lambda argv, cwd: (scan_rc, scan_out, "")})


# ---------------------------------------------------------------- usage and validation: exit 2, nothing written
for label, argv in [("no arguments", []), ("one argument", ["npm"]), ("four arguments", ["npm", "zod", "3.23.8", "x"]),
                    ("unknown ecosystem", ["conda", "numpy", "1.0.0"]),
                    ("Scenario: path-traversal version", ["npm", "zod", "../../x"]),
                    ("range version", ["npm", "zod", "^3.23.8"]), ("missing version", ["npm", "zod"]),
                    ("Scenario: vetter refuses a version for Homebrew", ["homebrew", "jq", "1.7.1"]),
                    ("option-looking name", ["homebrew", "--cask"]), ("option-looking ecosystem", ["--help-me", "x", "1.0.0"])]:
    rc, out, err, store = run(argv, replay.Replay())
    check("usage error: {} -> exit 2".format(label), rc, 2)
    check("usage error: {} -> usage line on stderr".format(label), "usage: vet-dependency" in err, True)
    check("usage error: {} -> nothing written".format(label), files_under(store), [])
rc, out, err, _ = run(["--help"], replay.Replay())
check("--help exits 0 with the usage line on stdout", (rc, "usage: vet-dependency" in out), (0, True))

# the real executable, end to end (fails before any network is needed)
check("vet-dependency is executable", os.access(SCRIPT, os.X_OK), True)
for argv, want in [(["npm", "zod", "../../x"], 2), (["homebrew", "jq", "1.7.1"], 2), (["--help"], 0)]:
    proc = subprocess.run([SCRIPT] + argv, cwd=ROOT, capture_output=True, text=True)
    check("executable {} -> exit {}".format(argv, want), proc.returncode, want)
    check("executable {} -> usage text".format(argv), "usage: vet-dependency" in proc.stdout + proc.stderr, True)

# ---------------------------------------------------------------- success: record and report
rc, out, err, store = run(["npm", "zod", "3.23.8"], npm_replay(), scanner_runner(), ("osv-scanner",))
record_file, report_file = [os.path.join(store, "npm", "zod", "3.23.8" + s) for s in (".json", ".md")]
check("success: exit 0", (rc, err), (0, ""))
check("success: exactly the record and the report", files_under(store), [record_file, report_file])
record, problem = vr.read_fresh_record(store, "npm", "zod", "3.23.8", NOW)
check("success: record reads back fresh and valid", problem, None)
check("success: record complete with no reasons", (record["complete"], record["incomplete_reasons"]), (True, []))
check("success: record names its report", record["report"], report_file)
check("success: files are 0600", [oct(os.stat(f).st_mode & 0o777) for f in (record_file, report_file)], ["0o600", "0o600"])
report = open(report_file, encoding="utf-8").read()
for needle in ["npm zod@3.23.8", "2026-10-14T12:00:00Z", "| direct_vulns | ok |", "| transitive_vulns | ok |", "| source_link | ok |",
               "npm 12.0.1", "osv-scanner 2.6.0", "TYPOSQUAT_RATIO", "MIN_WEEKLY_DOWNLOADS", "MIN_RELEASE_AGE_DAYS", "20000000"]:
    check("report contains {!r}".format(needle), needle in report, True)
check("stdout names both files and the tally", (report_file in out, record_file in out, "0 stop" in out), (True, True, True))

# stop signals still exit 0: the vetter reports, the human decides
rc, out, err, store = run(["npm", "zod", "3.23.8"], npm_replay(osv="lodash_vulns"), scanner_runner(
    scan_rc=1, scan_out=json.dumps(fx("other", "osv_scanner_findings"))), ("osv-scanner",))
report = open(os.path.join(store, "npm", "zod", "3.23.8.md"), encoding="utf-8").read()
check("stop: exit 0", rc, 0)
for needle in ["[GHSA-29mw-wpgm-hmr9](https://osv.dev/vulnerability/GHSA-29mw-wpgm-hmr9)",
               "[GHSA-35jh-r3h4-6jhm](https://osv.dev/vulnerability/GHSA-35jh-r3h4-6jhm)",
               "[GHSA-aaaa-bbbb-cccc](https://osv.dev/vulnerability/GHSA-aaaa-bbbb-cccc)",
               "1 packages resolved, 1 with advisories", "2 stop", "direct_vulns"]:
    check("stop report contains {!r}".format(needle), needle in report + out, True)
rc, out, err, store = run(["npm", "zod", "3.23.8"], npm_replay(osv="vulns_with_page_token"))
check("page-token note is in the report", "more advisories may exist" in open(os.path.join(store, "npm", "zod", "3.23.8.md")).read(), True)
rc, out, err, store = run(["npm", "zod", "3.23.8"], npm_replay(), scanner_runner(), ())
check("incomplete run says so in report and stdout", ("INCOMPLETE" in open(os.path.join(store, "npm", "zod", "3.23.8.md")).read(), "INCOMPLETE" in out), (True, True))

# Scenario: typosquat is flagged
rc, out, err, store = run(["npm", "lodahs", "1.0.0"], npm_replay("lodahs", pack="lodahs_packument", dl="downloads_lodahs",
                                                                bulk="downloads_bulk_lodahs_variants"))
record = json.load(open(os.path.join(store, "npm", "lodahs", "1.0.0.json")))
typo = [s for s in record["signals"] if s["check"] == "typosquat"][0]
check("Scenario: typosquat stop names lodash, record written", (rc, typo["status"], "lodash" in typo["detail"]), (0, "stop", True))
check("typosquat visible in the report", "lodash" in open(os.path.join(store, "npm", "lodahs", "1.0.0.md")).read(), True)

# untrusted registry text cannot break the table or smuggle control characters
nasty = fx("npm", "zod_packument")
nasty["body"]["versions"]["3.23.8"]["deprecated"] = "bad\nline | pipe\x00 "
r = npm_replay()
r.add("GET", NPM + "zod", nasty)
rc, out, err, store = run(["npm", "zod", "3.23.8"], r)
lines = open(os.path.join(store, "npm", "zod", "3.23.8.md"), encoding="utf-8").read().splitlines()
table = [l for l in lines if l.startswith("| ")]
check("sanitised: every table row has exactly 3 cells", {l.count(" | ") for l in table if not l.startswith("| ---")}, {2})
check("sanitised: no control characters in report", all(l.isprintable() for l in lines), True)

# Homebrew (D8)
def brew_ok(argv, cwd):
    return 0, json.dumps(fx("other", "brew_jq")), ""


rc, out, err, store = run(["homebrew", "jq"], replay.Replay(), replay.FakeRunner({"brew": brew_ok}))
record, problem = vr.newest_fresh_homebrew_record(store, "jq", NOW)
check("homebrew: record keyed on brew's stable, incomplete", (rc, problem, record["version"], record["complete"]), (0, None, "1.7.1", False))
rc, out, err, store = run(["homebrew", "zz-no-such-formula"], replay.Replay(), replay.FakeRunner({"brew": lambda a, c: (1, "", "Error: No available formula")}))
check("Scenario: vetter cannot learn a Homebrew version -> non-zero, no record", (rc != 0, files_under(store)), (True, []))

# ---------------------------------------------------------------- failures: exit 1, nothing written
for label, osv in [("Scenario: vetter cannot reach OSV (URLError)", urllib.error.URLError("unreachable")),
                   ("OSV timeout", socket.timeout("timed out")), ("OSV 500", fx("osv", "server_error")),
                   ("Scenario: OSV 200 with an error body", fx("osv", "error_body")),
                   ("Scenario: OSV page token only", fx("osv", "page_token_only"))]:
    r = npm_replay()
    r.add("POST", OSV, osv)
    rc, out, err, store = run(["npm", "zod", "3.23.8"], r)
    check(label + ": exit non-zero (1)", rc, 1)
    check(label + ": message on stderr, none on stdout", ("vet-dependency:" in err, out), (True, ""))
    check(label + ": no record file exists afterwards", files_under(store), [])
r = replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", NPM + "lodahs-xq9", fx("other", "not_found"))
rc, out, err, store = run(["npm", "lodahs-xq9", "1.0.0"], r)
check("Scenario: package that does not exist -> exit 1, 'not found', nothing written", (rc, "not found" in err, files_under(store)), (1, True, []))

# a write failure leaves no record and no partial report
real_write_record, real_write_report = vr.write_record, vr.write_report
for label, attr, original in [("record write fails", "write_record", real_write_record), ("report write fails", "write_report", real_write_report)]:
    def failing(*args, **kwargs):
        raise OSError("disk full")
    setattr(vr, attr, failing)
    try:
        rc, out, err, store = run(["npm", "zod", "3.23.8"], npm_replay())
    finally:
        setattr(vr, attr, original)
    check(label + ": exit 1 and the cause is named", (rc, "disk full" in err), (1, True))
    check(label + ": no record, no report, no temp file", files_under(store), [])

# ---------------------------------------------------------------- helpers, defaults
check("default store is hooks/state/vetting beside bin/", cli.DEFAULT_STORE, os.path.join(ROOT, "hooks", "state", "vetting"))
check("report reference inside the repo is repo-relative",
      cli.report_reference(os.path.join(ROOT, "hooks", "state", "vetting", "npm", "zod", "3.23.8.md")),
      "hooks/state/vetting/npm/zod/3.23.8.md")
check("report reference outside the repo is absolute", cli.report_reference("/tmp/x/a.md"), "/tmp/x/a.md")

# ---------------------------------------------------------------- opt-in live smoke test
TRAP.remove()
if os.environ.get("VET_LIVE_SMOKE") == "1":
    store = new_store()
    rc = cli.main(["npm", "zod", "3.23.8"], store=store)
    record, problem = vr.read_fresh_record(store, "npm", "zod", "3.23.8", datetime.datetime.now(datetime.timezone.utc))
    check("LIVE smoke: npm zod 3.23.8 exits 0 and writes a fresh valid record", (rc, problem), (0, None))
else:
    skipped += 1
    print("SKIP live smoke test (set VET_LIVE_SMOKE=1 to contact the real registries and run npm)")

shutil.rmtree(WORK, ignore_errors=True)
print("\nvet-dependency CLI: {} passed, {} failed, {} skipped ({} connection attempts)".format(
    passed, failed, skipped, len(TRAP.attempts)))
sys.exit(1 if failed else 0)
