#!/usr/bin/env python3
"""Unit tests for vet_checks.py -- the vetter's checks, failure handling and record assembly.
Run from the repo root: python3 hooks/lib/vet_checks.test.py

Spec: docs/features/dependency-vetting-guard.md (Checks, "Which checks run per ecosystem", D8,
Failure handling D7, the vetter Scenarios). No test touches the network: every HTTP call goes through
a replaying opener (hooks/bin/fixtures/vet-dependency/replay.py, fixtures hand-written), every
subprocess through a fake runner, and the whole run sits behind a trap that raises on any DNS lookup
or socket connect. The clock is injected. Dependency-free runner, same shape as vetting_record.test.py.
"""

import datetime
import importlib.util
import json
import os
import socket
import subprocess
import sys
import urllib.error

MARKER_SELF = os.path.abspath(__file__)
HERE = os.path.dirname(MARKER_SELF)
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE, capture_output=True,
                             text=True, check=True).stdout.strip()
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(MARKER_ROOT, "hooks", "bin", "fixtures", "vet-dependency"))

import replay  # noqa: E402
import vetting_record as vr  # noqa: E402

_SPEC = importlib.util.spec_from_file_location("vet_checks", os.path.join(HERE, "vet_checks.py"))
vc = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(vc)

fx = replay.fx
UTC = datetime.timezone.utc
NOW = datetime.datetime(2026, 10, 14, 12, 0, 0, tzinfo=UTC)
OSV = "https://api.osv.dev/v1/query"
NPM = "https://registry.npmjs.org/"
DL = "https://api.npmjs.org/downloads/point/last-week/"
PYPI = "https://pypi.org/pypi/"
CRATES = "https://crates.io/api/v1/crates/"

passed = failed = 0
TRAP = replay.NetworkTrap().install()


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL - {}\n       want {!r}, got {!r}".format(label, want, got))


def raises(label, exc_type, fn, *args):
    global passed, failed
    try:
        fn(*args)
    except exc_type as exc:
        passed += 1
        return exc
    except Exception as exc:  # noqa: BLE001 - name the wrong type
        failed += 1
        print("FAIL - {}\n       want {}, got {}: {}".format(label, exc_type.__name__, type(exc).__name__, exc))
        return None
    failed += 1
    print("FAIL - {}\n       want {}, nothing raised".format(label, exc_type.__name__))
    return None


def ctx_for(opener, runner=None, installed=()):
    return vc.Context(opener=opener, runner=runner or replay.FakeRunner(),
                      which=lambda n: "/fake/bin/" + n if n in installed else None, now=lambda: NOW)


def npm_replay(name="zod", osv="clean", pack="zod_packument", dl="downloads_zod", bulk="downloads_bulk_none_exist"):
    r = replay.Replay()
    r.add("POST", OSV, fx("osv", osv))
    r.add("GET", NPM + name.replace("/", "%2F"), fx("npm", pack) if isinstance(pack, str) else pack)
    r.add("GET", DL + name, fx("npm", dl) if isinstance(dl, str) else dl)
    r.add("GET", DL, fx("npm", bulk) if isinstance(bulk, str) else bulk, prefix=True)
    return r


def vet_npm(r, name="zod", version="3.23.8", runner=None, installed=()):
    return vc.vet(ctx_for(r, runner, installed), "npm", name, version)


def real_calls(runner):
    return [c for c in runner.calls if c[0][1:] != ["--version"]]


def sig(vetted, check_name):
    return [s for s in vetted["signals"] if s["check"] == check_name][0]


def packument(**changes):
    doc = fx("npm", "zod_packument")
    version = doc["body"]["versions"]["3.23.8"]
    for key, value in changes.items():
        target = doc["body"] if key == "time" else version
        if value is None:
            target.pop(key, None)
        elif key == "time":
            doc["body"]["time"]["3.23.8"] = value
        else:
            target[key] = value
    return doc


def iso(delta):
    return (NOW - delta).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def scanner_runner(npm_rc=0, scan_rc=0, scan_out="{}", lock=True, seen=None):
    def npm(argv, cwd):
        if seen is not None:
            seen["cwd"] = cwd
            seen["package_json"] = json.load(open(os.path.join(cwd, "package.json")))
        if lock and npm_rc == 0:
            with open(os.path.join(cwd, "package-lock.json"), "w") as handle:
                json.dump(fx("npm", "lock_zod"), handle)
        return npm_rc, "", ""
    return replay.FakeRunner({"npm": npm, "osv-scanner": lambda argv, cwd: (scan_rc, scan_out, "")})


# ---------------------------------------------------------------- name variants
v = vc.name_variants("lodahs")
check("variants: transposition lodash", "lodash" in v, True)
check("variants: deletion lodas", "lodas" in v and "lodah" in v, True)
check("variants: never the name itself", "lodahs" in v, False)
check("variants: sorted and unique", v, sorted(set(v)))
check("variants: doubled letter collapses", "react" in vc.name_variants("reeact"), True)
check("variants: separators swap", {"foo_bar", "foo.bar", "foobar"} <= set(vc.name_variants("foo-bar")), True)
check("variants: scope dropped", "tool" in vc.name_variants("@scope/tool"), True)
check("variants: scoped name yields only unscoped variants",
      [x for x in vc.name_variants("@scope/tool") if "@" in x or "/" in x], [])
check("variants: every one is a valid npm name", all(vr.validate_name("npm", x) for x in vc.name_variants("a.b-c_d")), True)
check("variants: a one-letter name has none usable", vc.name_variants("a"), [])
check("variants: every doubled run collapses at once (not reachable by one deletion)", "abc" in vc.name_variants("aabbcc"), True)
check("variants: 'aa' has exactly one variant", vc.name_variants("aa"), ["a"])

# ---------------------------------------------------------------- direct_vulns
r = npm_replay()
vetted = vet_npm(r)
check("OSV request body", r.body_of(r.urls().index(OSV)), {"package": {"name": "zod", "ecosystem": "npm"}, "version": "3.23.8"})
check("Scenario: a clean OSV answer is read as clean", sig(vetted, "direct_vulns")["status"], "ok")
r = npm_replay(osv="lodash_vulns")
s = sig(vet_npm(r), "direct_vulns")
check("OSV advisories are a stop", s["status"], "stop")
check("OSV advisory ids listed", s["advisories"], ["GHSA-29mw-wpgm-hmr9", "GHSA-35jh-r3h4-6jhm"])
check("OSV detail counts them", "2 advisories" in s["detail"], True)
s = sig(vet_npm(npm_replay(osv="vulns_with_page_token")), "direct_vulns")
check("next_page_token with vulns is still a stop", s["status"], "stop")
check("next_page_token adds the more-may-exist note", any("more advisories may exist" in n for n in s["notes"]), True)
check("OSV request for go keeps the version as given",
      vc.osv_query_body("go", "golang.org/x/text", "v0.3.0")["version"], "v0.3.0")

for label, outcome in [
        ("Scenario: OSV 200 with an error body is not clean", fx("osv", "error_body")),
        ("Scenario: OSV answer carrying only a page token is not clean", fx("osv", "page_token_only")),
        ("OSV vulns with an extra key is a failure", fx("osv", "vulns_with_extra_key")),
        ("OSV empty vulns list is a failure", fx("osv", "empty_vulns_list")),
        ("OSV 500 is a failure", fx("osv", "server_error")),
        ("OSV 404 is a failure", {"status": 404, "body": {}}),
        ("OSV non-JSON body is a failure", {"status": 200, "raw": "<html>"}),
        ("OSV JSON array body is a failure", {"status": 200, "body": []}),
        ("Scenario: vetter cannot reach OSV (timeout)", socket.timeout("timed out")),
        ("Scenario: vetter cannot reach OSV (refused)", urllib.error.URLError("refused"))]:
    r = npm_replay()
    r.add("POST", OSV, outcome)
    raises(label, vc.OsvError, vet_npm, r)

# ---------------------------------------------------------------- not found, validation
r = npm_replay(pack=fx("other", "not_found"))
exc = raises("npm 404 for the name", vc.NotFoundError, vet_npm, r, "zod")
check("not-found message", "npm zod@3.23.8 not found on" in str(exc), True)
doc = fx("npm", "zod_packument")
del doc["body"]["versions"]["3.23.8"]
raises("npm version absent from the packument is not found", vc.NotFoundError, vet_npm, npm_replay(pack=doc))
for eco, name, version, routes in [
        ("pypi", "requests", "2.32.3", [("GET", PYPI + "requests/2.32.3/json")]),
        ("crates.io", "serde", "1.0.210", [("GET", CRATES + "serde/1.0.210")])]:
    r = replay.Replay().add("POST", OSV, fx("osv", "clean"))
    for method, url in routes:
        r.add(method, url, fx("other", "not_found"))
    raises(eco + " 404 is not found", vc.NotFoundError, vc.vet, ctx_for(r), eco, name, version)
for label, args in [("unknown ecosystem", ("conda", "x", "1.0.0")), ("path-traversal version", ("npm", "zod", "../../x")),
                    ("range version", ("npm", "zod", "^3.23.8")), ("missing version", ("npm", "zod", None)),
                    ("homebrew with a version", ("homebrew", "jq", "1.7.1")), ("bad name", ("npm", "a/b/c", "1.0.0")),
                    ("leading hyphen name", ("homebrew", "--cask", None)), ("leading hyphen name npm", ("npm", "-x", "1.0.0"))]:
    raises("Scenario: invalid input is refused (" + label + ")", vr.ValidationError,
           vc.vet, ctx_for(replay.Replay()), *args)

# ---------------------------------------------------------------- typosquat and popularity (npm)
r = npm_replay(name="lodahs", pack="lodahs_packument", dl="downloads_lodahs", bulk="downloads_bulk_lodahs_variants")
vetted = vet_npm(r, "lodahs", "1.0.0")
s = sig(vetted, "typosquat")
check("Scenario: typosquat is flagged", s["status"], "stop")
check("typosquat detail names lodash", "lodash" in s["detail"], True)
bulk = [u for u in r.urls() if "," in u]
check("typosquat bulk request is one call listing every variant, unscoped",
      (len(bulk), set(bulk[0][len(DL):].split(","))), (1, set(vc.name_variants("lodahs"))))
check("popularity of the requested name", sig(vetted, "popularity")["status"], "caution")
check("lodahs: install scripts", sig(vetted, "install_scripts")["status"], "caution")
check("lodahs: no source link", sig(vetted, "source_link")["status"], "caution")


def squat(requested, variant):
    r = npm_replay(dl={"status": 200, "body": {"downloads": requested}} if requested is not None else "downloads_not_found",
                   bulk={"status": 200, "body": {"zo": {"downloads": variant}}})
    return sig(vet_npm(r), "typosquat")["status"]


check("ratio: exactly 100x is a stop", squat(170, 17000), "stop")
check("ratio: just under 100x is ok", squat(170, 16999), "ok")
check("ratio: unknown requested downloads count as 1 -> 99 ok", squat(None, 99), "ok")
check("ratio: unknown requested downloads count as 1 -> 100 stop", squat(None, 100), "stop")
check("popularity: exactly 1000 is ok", sig(vet_npm(npm_replay(dl={"status": 200, "body": {"downloads": 1000}})), "popularity")["status"], "ok")
check("popularity: 999 is a caution", sig(vet_npm(npm_replay(dl={"status": 200, "body": {"downloads": 999}})), "popularity")["status"], "caution")
check("popularity: 404 downloads = brand-new = caution", sig(vet_npm(npm_replay(dl="downloads_not_found")), "popularity")["status"], "caution")

r = npm_replay(dl={"status": 500, "body": {}})
vetted = vet_npm(r)
check("requested downloads failing -> popularity not_run", sig(vetted, "popularity")["status"], "not_run")
check("requested downloads failing -> typosquat not_run", sig(vetted, "typosquat")["status"], "not_run")
check("requested downloads failing -> incomplete", vetted["complete"], False)
vetted = vet_npm(npm_replay(bulk={"status": 500, "body": {}}))
check("bulk failing -> typosquat not_run", sig(vetted, "typosquat")["status"], "not_run")
check("bulk failing -> popularity still runs", sig(vetted, "popularity")["status"], "ok")

# a one-variant lookup is a one-name request: the API answers flat (not keyed by name), and 404 for an unknown name
one_variant_pack = {"status": 200, "body": {"versions": {"1.0.0": {}}, "time": {"1.0.0": iso(datetime.timedelta(days=30))}}}
for label, bulk, want in [("flat answer is read", {"status": 200, "body": {"downloads": 5000000, "package": "a"}}, "stop"),
                          ("404 means it does not exist", {"status": 404, "body": {"error": "package a not found"}}, "ok")]:
    r = npm_replay(name="aa", pack=one_variant_pack, dl={"status": 200, "body": {"downloads": 5000}}, bulk=bulk)
    check("single-variant lookup: " + label, sig(vet_npm(r, "aa", "1.0.0"), "typosquat")["status"], want)
    check("single-variant lookup uses the one-name URL", DL + "a" in r.urls(), True)

long_name = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz"
r = npm_replay(name=long_name, pack={"status": 200, "body": {"versions": {"1.0.0": {}}, "time": {"1.0.0": iso(datetime.timedelta(days=30))}}},
               dl={"status": 200, "body": {"downloads": 5000}}, bulk={"status": 200, "body": {}})
vc_vetted = vet_npm(r, long_name, "1.0.0")
bulk_urls = [u for u in r.urls() if u.startswith(DL) and "," in u]
check("bulk lookups are chunked", len(bulk_urls) >= 2 and all(len(u[len(DL):].split(",")) <= vc.BULK_CHUNK for u in bulk_urls), True)
check("every variant is looked up once", sum(len(u[len(DL):].split(",")) for u in bulk_urls), len(vc.name_variants(long_name)))

r = npm_replay(name="@scope/name", pack=fx("npm", "zod_packument"), dl={"status": 200, "body": {"downloads": 500}},
               bulk={"status": 200, "body": {"name": {"downloads": 90000000}}})
r.add("GET", NPM + "@scope%2Fname", {"status": 200, "body": {"time": {"3.23.8": iso(datetime.timedelta(days=90))},
      "versions": {"3.23.8": {}}, "repository": "https://example.invalid/r"}})
vetted = vet_npm(r, "@scope/name")
check("scoped: requested name fetched on its own, unbulked", DL + "@scope/name" in r.urls(), True)
check("scoped: registry URL is %2F-encoded", NPM + "@scope%2Fname" in r.urls(), True)
check("scoped: scope-dropped name is a typosquat source", (sig(vetted, "typosquat")["status"], "name" in sig(vetted, "typosquat")["detail"]), ("stop", True))

# ---------------------------------------------------------------- npm registry metadata
check("deprecated npm: set -> stop", sig(vet_npm(npm_replay(pack=packument(deprecated="use zod2"))), "deprecated")["status"], "stop")
check("deprecated npm: absent -> ok", sig(vet_npm(npm_replay()), "deprecated")["status"], "ok")
check("deprecated npm: empty string -> ok", sig(vet_npm(npm_replay(pack=packument(deprecated=""))), "deprecated")["status"], "ok")
week = datetime.timedelta(days=7)
check("release_age: exactly 7 days -> ok", sig(vet_npm(npm_replay(pack=packument(time=iso(week)))), "release_age")["status"], "ok")
s = sig(vet_npm(npm_replay(pack=packument(time=iso(week - datetime.timedelta(seconds=1))))), "release_age")
check("release_age: one second under 7 days -> caution", s["status"], "caution")
check("release_age detail shows the raw value and threshold", "6 days" in s["detail"] and "7" in s["detail"], True)
check("release_age: unparseable -> not_run", sig(vet_npm(npm_replay(pack=packument(time="yesterday"))), "release_age")["status"], "not_run")
check("release_age: missing time -> not_run", sig(vet_npm(npm_replay(pack=packument(time=None))), "release_age")["status"], "not_run")
for key in ("preinstall", "install", "postinstall"):
    s = sig(vet_npm(npm_replay(pack=packument(scripts={key: "node x.js"}))), "install_scripts")
    check("install_scripts {} -> caution".format(key), (s["status"], key in s["detail"]), ("caution", True))
check("install_scripts: build only -> ok", sig(vet_npm(npm_replay()), "install_scripts")["status"], "ok")
check("source_link: string repository -> ok", sig(vet_npm(npm_replay(pack=packument(repository="https://example.invalid/r"))), "source_link")["status"], "ok")
check("source_link: empty url -> caution", sig(vet_npm(npm_replay(pack=packument(repository={"url": ""}))), "source_link")["status"], "caution")
doc = packument(repository=None)
doc["body"]["repository"] = {"url": "https://example.invalid/r"}
check("source_link: packument-level repository -> ok", sig(vet_npm(npm_replay(pack=doc)), "source_link")["status"], "ok")
doc = packument(repository=None)
del doc["body"]["repository"]
check("source_link: none -> caution", sig(vet_npm(npm_replay(pack=doc)), "source_link")["status"], "caution")
for label, outcome in [("500", {"status": 500, "body": {}}), ("timeout", socket.timeout("t")), ("URLError", urllib.error.URLError("x")),
                       ("non-JSON", {"status": 200, "raw": "<html>"}), ("JSON array", {"status": 200, "body": []}),
                       ("no versions key", {"status": 200, "body": {}})]:
    r = npm_replay()
    r.add("GET", NPM + "zod", outcome)
    vetted = vet_npm(r)
    got = [sig(vetted, c)["status"] for c in ("deprecated", "release_age", "install_scripts", "source_link")]
    check("registry unreachable ({}) -> its checks not_run".format(label), got, ["not_run"] * 4)
    check("registry unreachable ({}) -> direct_vulns still runs and record incomplete".format(label),
          (sig(vetted, "direct_vulns")["status"], vetted["complete"]), ("ok", False))

# ---------------------------------------------------------------- pypi and crates
r = replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", PYPI + "requests/2.32.3/json", fx("other", "pypi_requests"))
r.add("GET", PYPI, fx("other", "not_found"), prefix=True)
vetted = vc.vet(ctx_for(r), "pypi", "requests", "2.32.3")
check("pypi: statuses", [(s["check"], s["status"]) for s in vetted["signals"]],
      [("direct_vulns", "ok"), ("transitive_vulns", "not_run"), ("deprecated", "ok"), ("typosquat", "ok"),
       ("release_age", "ok"), ("popularity", "not_run"), ("install_scripts", "not_run"), ("source_link", "ok")])
check("pypi: incomplete, reasons name the checks", (vetted["complete"], [x.split(":")[0] for x in vetted["incomplete_reasons"]]),
      (False, ["transitive_vulns", "popularity", "install_scripts"]))
check("pypi: release age uses the earliest upload", "2024-05-29T15:37:47" in sig(vetted, "release_age")["detail"], True)
yanked = fx("other", "pypi_requests")
yanked["body"]["info"]["yanked"] = True
r.add("GET", PYPI + "requests/2.32.3/json", yanked)
check("pypi: yanked -> stop", sig(vc.vet(ctx_for(r), "pypi", "requests", "2.32.3"), "deprecated")["status"], "stop")
nolinks = fx("other", "pypi_requests")
nolinks["body"]["info"]["project_urls"] = None
r.add("GET", PYPI + "requests/2.32.3/json", nolinks)
check("pypi: no project_urls -> caution", sig(vc.vet(ctx_for(r), "pypi", "requests", "2.32.3"), "source_link")["status"], "caution")
r.add("GET", PYPI + "reqests/json", fx("other", "pypi_exists"))
r.add("GET", PYPI + "requests/2.32.3/json", fx("other", "pypi_requests"))
s = sig(vc.vet(ctx_for(r), "pypi", "requests", "2.32.3"), "typosquat")
check("pypi: an existing variant is a caution naming it", (s["status"], "reqests" in s["detail"]), ("caution", True))

r = replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", PYPI + "zope-interface/5.0.0/json", fx("other", "pypi_requests"))
r.add("GET", PYPI, fx("other", "not_found"), prefix=True)
vc.vet(ctx_for(r), "pypi", "zope-interface", "5.0.0")
check("pypi: separator variants are the same project and are not probed",
      [u for u in r.urls() if u.endswith("zope_interface/json") or u.endswith("zope.interface/json")], [])
r = replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", PYPI + long_name + "/1.0.0/json", fx("other", "pypi_requests"))
r.add("GET", PYPI, fx("other", "not_found"), prefix=True)
s = sig(vc.vet(ctx_for(r), "pypi", long_name, "1.0.0"), "typosquat")
check("pypi: probes are capped and a capped miss is not_run", (len(r.urls()) - 2, s["status"]), (vc.MAX_EXISTENCE_PROBES, "not_run"))
r = replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", PYPI + "requests/2.32.3/json", fx("other", "pypi_requests"))
r.add("GET", PYPI, {"status": 500, "body": {}}, prefix=True)
check("pypi: a failed existence probe with no hit is not_run", sig(vc.vet(ctx_for(r), "pypi", "requests", "2.32.3"), "typosquat")["status"], "not_run")

r = replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", CRATES + "serde/1.0.210", fx("other", "crates_serde_version"))
r.add("GET", CRATES + "serde", fx("other", "crates_serde_crate")).add("GET", CRATES, fx("other", "not_found"), prefix=True)
vetted = vc.vet(ctx_for(r), "crates.io", "serde", "1.0.210")
check("crates: statuses", {s["check"]: s["status"] for s in vetted["signals"]},
      {"direct_vulns": "ok", "transitive_vulns": "not_run", "deprecated": "ok", "typosquat": "ok", "release_age": "ok",
       "popularity": "not_run", "install_scripts": "not_run", "source_link": "ok"})
yanked = fx("other", "crates_serde_version")
yanked["body"]["version"]["yanked"] = True
r.add("GET", CRATES + "serde/1.0.210", yanked)
check("crates: yanked -> stop", sig(vc.vet(ctx_for(r), "crates.io", "serde", "1.0.210"), "deprecated")["status"], "stop")
r.add("GET", CRATES + "serde", {"status": 500, "body": {}})
check("crates: crate endpoint failing -> source_link not_run", sig(vc.vet(ctx_for(r), "crates.io", "serde", "1.0.210"), "source_link")["status"], "not_run")
r.add("GET", CRATES + "serde", fx("other", "crates_serde_crate"))
r.add("GET", CRATES + "serd", fx("other", "crates_exists"))
check("crates: an existing variant is a caution", sig(vc.vet(ctx_for(r), "crates.io", "serde", "1.0.210"), "typosquat")["status"], "caution")

for eco, name, version in [("go", "golang.org/x/text", "v0.3.8"), ("rubygems", "rack", "2.0.0")]:
    r = replay.Replay().add("POST", OSV, fx("osv", "clean"))
    vetted = vc.vet(ctx_for(r), eco, name, version)
    check(eco + ": only direct_vulns runs", [s["check"] for s in vetted["signals"] if s["status"] != "not_run"], ["direct_vulns"])
    check(eco + ": exactly one HTTP request (OSV)", len(r.requests), 1)
    check(eco + ": incomplete", vetted["complete"], False)

# ---------------------------------------------------------------- transitive_vulns
seen = {}
runner = scanner_runner(seen=seen)
vetted = vet_npm(npm_replay(), runner=runner, installed=("osv-scanner",))
s = sig(vetted, "transitive_vulns")
check("transitive: exit 0 -> ok", s["status"], "ok")
check("transitive: counts come from the lockfile", s["counts"], {"packages": 1, "with_advisories": 0})
check("transitive: full npm run is complete", (vetted["complete"], vetted["incomplete_reasons"]), (True, []))
check("transitive: npm argv", real_calls(runner)[0][0], ["npm", "install", "--package-lock-only", "--ignore-scripts"])
check("transitive: scratch package.json holds one dependency", seen["package_json"]["dependencies"], {"zod": "3.23.8"})
check("transitive: osv-scanner argv", real_calls(runner)[1][0],
      ["/fake/bin/osv-scanner", "scan", "-L", os.path.join(seen["cwd"], "package-lock.json"), "--format", "json"])
check("transitive: scratch dir removed", os.path.exists(seen["cwd"]), False)
check("tool versions are those of the tools used", vetted["tool_versions"], {"npm": "12.0.1", "osv-scanner": "2.6.0"})
runner = scanner_runner(scan_rc=1, scan_out=json.dumps(fx("other", "osv_scanner_findings")))
vetted = vet_npm(npm_replay(), runner=runner, installed=("osv-scanner",))
s = sig(vetted, "transitive_vulns")
check("Scenario: osv-scanner finding vulnerabilities is a stop", (s["status"], s["advisories"]), ("stop", ["GHSA-aaaa-bbbb-cccc"]))
check("... and the record is complete", vetted["complete"], True)
check("... with counts", s["counts"], {"packages": 1, "with_advisories": 1})
runner = scanner_runner()
vetted = vet_npm(npm_replay(), runner=runner, installed=())
check("osv-scanner absent -> not_run and npm is never run", (sig(vetted, "transitive_vulns")["status"], runner.calls), ("not_run", []))
check("osv-scanner absent -> reason", any("osv-scanner not on PATH" in x for x in vetted["incomplete_reasons"]), True)
for label, kwargs, reason in [
        ("exit 128", dict(scan_rc=128), "no packages found"), ("exit 2", dict(scan_rc=2), "exited 2"),
        ("exit 1 with bad JSON", dict(scan_rc=1, scan_out="not json"), "JSON"),
        ("exit 1 with no advisories listed", dict(scan_rc=1, scan_out="{}"), "no advisories"),
        ("npm exit 1", dict(npm_rc=1), "exited 1"), ("npm wrote no lockfile", dict(lock=False), "lockfile")]:
    s = sig(vet_npm(npm_replay(), runner=scanner_runner(**kwargs), installed=("osv-scanner",)), "transitive_vulns")
    check("transitive {} -> not_run with reason".format(label), (s["status"], reason in s["detail"]), ("not_run", True))
for label, handlers, reason in [
        ("npm timeout", {"npm": lambda a, c: (_ for _ in ()).throw(subprocess.TimeoutExpired("npm", 120))}, "timeout"),
        ("npm missing", {}, "not found"),
        ("osv-scanner timeout", {"npm": scanner_runner().handlers["npm"], "osv-scanner": lambda a, c: (_ for _ in ()).throw(subprocess.TimeoutExpired("o", 120))}, "timeout")]:
    s = sig(vet_npm(npm_replay(), runner=replay.FakeRunner(handlers), installed=("osv-scanner",)), "transitive_vulns")
    check("transitive {} -> not_run".format(label), (s["status"], reason in s["detail"]), ("not_run", True))
runner = scanner_runner()
vc.vet(ctx_for(replay.Replay().add("POST", OSV, fx("osv", "clean")).add("GET", PYPI + "requests/2.32.3/json", fx("other", "pypi_requests"))
               .add("GET", PYPI, fx("other", "not_found"), prefix=True), runner, ("osv-scanner",)), "pypi", "requests", "2.32.3")
check("non-npm never runs npm or osv-scanner", runner.calls, [])

# ---------------------------------------------------------------- homebrew (D8)
def brew_runner(rc=0, out=None, exc=None):
    def brew(argv, cwd):
        if exc:
            raise exc
        return rc, json.dumps(fx("other", "brew_jq")) if out is None else out, ""
    return replay.FakeRunner({"brew": brew})


runner = brew_runner()
r = replay.Replay()
vetted = vc.vet(ctx_for(r, runner), "homebrew", "jq", None)
check("homebrew: keyed on brew's stable version", vetted["version"], "1.7.1")
check("homebrew: brew info argv", real_calls(runner)[0][0], ["brew", "info", "--json=v2", "jq"])
check("homebrew: every check not_run, record incomplete", ({s["status"] for s in vetted["signals"]}, vetted["complete"]), ({"not_run"}, False))
check("homebrew: no HTTP at all", r.requests, [])
check("homebrew: brew version recorded", vetted["tool_versions"], {"brew": "6.0.14"})
bad = fx("other", "brew_jq")
bad["formulae"][0]["versions"]["stable"] = ""
nostable = fx("other", "brew_jq")
del nostable["formulae"][0]["versions"]
traversal = fx("other", "brew_jq")
traversal["formulae"][0]["versions"]["stable"] = "../x"
for label, runner in [("Scenario: vetter cannot learn a Homebrew version (exit 1)", brew_runner(rc=1, out="")),
                      ("brew not installed", replay.FakeRunner()), ("brew timeout", brew_runner(exc=subprocess.TimeoutExpired("brew", 120))),
                      ("brew output not JSON", brew_runner(out="nope")), ("brew JSON not an object", brew_runner(out="[]")),
                      ("no formulae", brew_runner(out=json.dumps({"formulae": [], "casks": []}))),
                      ("empty stable", brew_runner(out=json.dumps(bad))), ("no versions", brew_runner(out=json.dumps(nostable))),
                      ("stable that is not a safe file name", brew_runner(out=json.dumps(traversal)))]:
    raises(label, vc.VetError, vc.vet, ctx_for(replay.Replay(), runner), "homebrew", "jq", None)

# ---------------------------------------------------------------- record assembly, sanitising, defaults
vetted = vet_npm(npm_replay(), runner=scanner_runner(), installed=("osv-scanner",))
record = vc.to_record(vetted, "hooks/state/vetting/npm/zod/3.23.8.md")
check("record validates against schema 1", vr.validate_record(record) is record, True)
check("record signals carry exactly check/status/detail", {tuple(sorted(s)) for s in record["signals"]}, {("check", "detail", "status")})
check("record signals follow the Checks table order", [s["check"] for s in record["signals"]],
      ["direct_vulns", "transitive_vulns", "deprecated", "typosquat", "release_age", "popularity", "install_scripts", "source_link"])
check("record vetted_at is the injected clock", record["vetted_at"], "2026-10-14T12:00:00Z")
nasty = "bad\nline\x00|pipe  " + "x" * 2000
s = sig(vet_npm(npm_replay(pack=packument(deprecated=nasty))), "deprecated")
check("registry text is sanitised and cut", (s["detail"].isprintable(), len(s["detail"]) <= vc.DETAIL_MAX), (True, True))
check("sanitised record still validates", vr.validate_record(vc.to_record(vet_npm(npm_replay(pack=packument(deprecated=nasty))), "r.md")) is not None, True)

ctx = vc.Context()
check("default opener is urlopen", ctx.opener.__name__, "urlopen")
check("default clock is aware UTC", ctx.now().tzinfo is not None, True)
check("default runner runs a program", vc.run_command([sys.executable, "-c", "print(7)"], None, 30), (0, "7\n", ""))
raises("default runner raises on a missing program", FileNotFoundError, vc.run_command, ["no-such-program-xq9"], None, 5)
raises("default runner raises on timeout", subprocess.TimeoutExpired, vc.run_command, [sys.executable, "-c", "import time; time.sleep(5)"], None, 0.2)

# default opener under the trap: the real urlopen path is wired, and is blocked, not reached
before = len(TRAP.attempts)
exc = raises("default opener: OSV unreachable raises OsvError", vc.OsvError, vc.vet,
             vc.Context(runner=replay.FakeRunner(), now=lambda: NOW), "npm", "zod", "3.23.8")
check("default opener really attempted a connection and the trap blocked it", len(TRAP.attempts) > before, True)

TRAP.remove()
print("\nvet_checks unit: {} passed, {} failed ({} connection attempts, all blocked by the trap)".format(
    passed, failed, len(TRAP.attempts)))
if failed == 0:
    subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF], cwd=MARKER_ROOT, check=True)
sys.exit(1 if failed else 0)
