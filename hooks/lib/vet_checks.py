"""The vetter's checks: every signal `vet-dependency` reports, and the record built from them.

Spec: docs/features/dependency-vetting-guard.md (Checks, "Which checks run per ecosystem", D8,
Failure handling D7). `vet()` returns the signals for one package; the CLI (hooks/bin/vet-dependency)
renders the report and writes the files. Standard library only (Python 3.9).

Everything that touches the outside world comes in through `Context` -- the HTTP opener (urlopen's
shape), the subprocess runner, `which` and the clock -- so the suite replays recorded fixtures with
no network. Failure policy (spec D7): OSV failing, a registry's 404 and a Homebrew lookup failing
raise `VetError` (the CLI then writes nothing); any other source failing makes its check `not_run`,
which makes the record `complete: false`. Text that came from a registry is cut and stripped of
non-printable characters before it reaches a signal.
"""

import datetime
import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request

import vetting_record as vr

# ---- thresholds (spec Checks table) and operational limits
HTTP_TIMEOUT_SECONDS = 15
SUBPROCESS_TIMEOUT_SECONDS = 120
TYPOSQUAT_RATIO = 100
MIN_RELEASE_AGE_DAYS = 7
MIN_WEEKLY_DOWNLOADS = 1000
BULK_CHUNK = 100               # package names per bulk downloads request
MAX_EXISTENCE_PROBES = 80      # one request each, so a long PyPI/crates name is capped
MAX_RESPONSE_BYTES = 64 * 1024 * 1024
DETAIL_MAX = 300
SHOWN_NAMES = 5                # advisory ids / names listed in one detail line
INSTALL_SCRIPT_KEYS = ("preinstall", "install", "postinstall")
CHECKS = ("direct_vulns", "transitive_vulns", "deprecated", "typosquat", "release_age",
          "popularity", "install_scripts", "source_link")

OSV_URL = "https://api.osv.dev/v1/query"
NPM_URL = "https://registry.npmjs.org/"
NPM_DOWNLOADS_URL = "https://api.npmjs.org/downloads/point/last-week/"
PYPI_URL = "https://pypi.org/pypi/"
CRATES_URL = "https://crates.io/api/v1/crates/"
USER_AGENT = "vet-dependency/1 (dependency-vetting-guard)"  # crates.io refuses urllib's default
_PROBE_STORE = os.path.join(os.sep, "vet-version-probe")    # never written; only for validating a version
_TIME_RE = re.compile(r"(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.(\d+))?(Z|[+-]\d\d:\d\d)", re.ASCII)


class VetError(Exception):
    """The package cannot be vetted at all; the CLI exits non-zero and writes no record."""


class NotFoundError(VetError):
    """A registry answered 404 for the name or version."""


class OsvError(VetError):
    """OSV did not give a usable answer (spec: nothing may be read as clean)."""


class _Unavailable(Exception):
    """A source did not answer usefully; the message becomes the check's reason."""


def run_command(argv, cwd, timeout):
    proc = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, errors="replace",
                          timeout=timeout, stdin=subprocess.DEVNULL)
    return proc.returncode, proc.stdout, proc.stderr


class Context:
    def __init__(self, opener=None, runner=None, which=None, now=None):
        self.opener = opener or urllib.request.urlopen
        self.runner = runner or run_command
        self.which = which or shutil.which
        self.now = now or (lambda: datetime.datetime.now(datetime.timezone.utc))


def _clean(value, limit=DETAIL_MAX):
    text = "".join(c if c.isprintable() else "?" for c in str(value))
    return text if len(text) <= limit else text[:limit - 1] + "\u2026"


def _sig(check, status, detail, **extra):
    signal = {"check": check, "status": status, "detail": _clean(detail), "advisories": [], "notes": []}
    signal.update(extra)
    return signal


def _not_run(check, why):
    return _sig(check, "not_run", why)


def _names(items):
    shown = ", ".join(_clean(i, 80) for i in items[:SHOWN_NAMES])
    return shown + (", +{} more".format(len(items) - SHOWN_NAMES) if len(items) > SHOWN_NAMES else "")


# ---------------------------------------------------------------- HTTP and subprocess plumbing

_NOT_JSON = object()


def _fetch(ctx, method, url, body=None):
    """-> (status, parsed JSON or _NOT_JSON). Raises _Unavailable if no usable HTTP answer came."""
    data = json.dumps(body, separators=(",", ":")).encode("utf-8") if body is not None else None
    headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with ctx.opener(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            status, raw = response.status, response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as exc:  # also an OSError, so it must be caught first
        status, raw = exc.code, exc.read(MAX_RESPONSE_BYTES + 1)
        exc.close()
    except (OSError, http.client.HTTPException) as exc:  # URLError and socket.timeout are OSErrors
        timed_out = isinstance(exc, socket.timeout) or isinstance(getattr(exc, "reason", None), socket.timeout)
        raise _Unavailable("timeout" if timed_out else "{}: {}".format(type(exc).__name__, exc))
    if len(raw) > MAX_RESPONSE_BYTES:
        raise _Unavailable("response too large")
    try:
        return status, json.loads(raw.decode("utf-8"))
    except (ValueError, RecursionError):
        return status, _NOT_JSON


def _run(ctx, argv, cwd, used):
    program = os.path.basename(argv[0])
    used.add(program)
    try:
        return ctx.runner(argv, cwd, SUBPROCESS_TIMEOUT_SECONDS)
    except FileNotFoundError:
        raise _Unavailable("{} not found".format(program))
    except subprocess.TimeoutExpired:
        raise _Unavailable("{} timeout".format(program))
    except OSError as exc:
        raise _Unavailable("{}: {}".format(program, exc))


def _tool_versions(ctx, used):
    versions = {}
    for program in sorted(used):
        try:
            rc, out, _err = ctx.runner([program, "--version"], None, SUBPROCESS_TIMEOUT_SECONDS)
            line = out.strip().splitlines()[0] if rc == 0 and out.strip() else None
        except (OSError, subprocess.TimeoutExpired):
            line = None
        versions[program] = _clean(line, 80) if line else None
    return versions


# ---------------------------------------------------------------- direct_vulns (OSV)

def osv_query_body(ecosystem, name, version):
    return {"package": {"name": name, "ecosystem": vr.osv_ecosystem(ecosystem)}, "version": version}


def check_direct_vulns(ctx, ecosystem, name, version):
    """ok only for HTTP 200 with exactly `{}`; a non-empty `vulns` list is a stop; anything else raises."""
    try:
        status, body = _fetch(ctx, "POST", OSV_URL, osv_query_body(ecosystem, name, version))
    except _Unavailable as exc:
        raise OsvError("OSV unreachable: {}".format(exc))
    if status != 200:
        raise OsvError("OSV answered HTTP {}".format(status))
    if not isinstance(body, dict):
        raise OsvError("OSV answer is not a JSON object")
    if body == {}:
        return _sig("direct_vulns", "ok", "0 advisories")
    vulns = body.get("vulns")
    if not set(body) <= {"vulns", "next_page_token"} or not isinstance(vulns, list) or not vulns:
        raise OsvError("OSV answer is neither {{}} nor a list of advisories (keys: {})".format(_clean(sorted(map(str, body)), 80)))
    ids = [_clean(v["id"], 64) if isinstance(v, dict) and isinstance(v.get("id"), str) else "(id missing)" for v in vulns]
    notes = ["more advisories may exist (OSV returned a next_page_token)"] if "next_page_token" in body else []
    return _sig("direct_vulns", "stop", "{} advisor{}: {}".format(len(ids), "y" if len(ids) == 1 else "ies", _names(ids)),
                advisories=ids, notes=notes)


# ---------------------------------------------------------------- registry metadata

def _registry_doc(ctx, url, missing):
    """-> (dict, None) or (None, reason). A 404 raises NotFoundError(missing)."""
    try:
        status, doc = _fetch(ctx, "GET", url)
    except _Unavailable as exc:
        return None, str(exc)
    if status == 404:
        raise NotFoundError(missing)
    if status != 200:
        return None, "HTTP {}".format(status)
    if not isinstance(doc, dict):
        return None, "response is not a JSON object"
    return doc, None


def _parse_time(text):
    match = _TIME_RE.fullmatch(text) if isinstance(text, str) else None
    if not match:
        return None
    year, month, day, hour, minute, second, fraction, zone = match.groups()
    offset = datetime.timezone.utc if zone == "Z" else datetime.timezone(
        (1 if zone[0] == "+" else -1) * datetime.timedelta(hours=int(zone[1:3]), minutes=int(zone[4:6])))
    try:
        return datetime.datetime(int(year), int(month), int(day), int(hour), int(minute), int(second),
                                 int((fraction or "0")[:6].ljust(6, "0")), tzinfo=offset)
    except ValueError:
        return None


def _release_age(raw, now):
    published = _parse_time(raw)
    if published is None:
        return _not_run("release_age", "release time {} is missing or not a timestamp".format(_clean(raw, 40)))
    age = now - published
    threshold = "caution under {} days".format(MIN_RELEASE_AGE_DAYS)
    when = "published in the future" if age < datetime.timedelta(0) else "{} days ago".format(age.days)
    status = "caution" if age < datetime.timedelta(days=MIN_RELEASE_AGE_DAYS) else "ok"
    return _sig("release_age", status, "published {} ({}; {})".format(_clean(raw, 40), when, threshold))


def _has_link(value):
    return bool(value.strip()) if isinstance(value, str) else (
        isinstance(value, dict) and isinstance(value.get("url"), str) and bool(value["url"].strip()))


def _link_sig(value, shown):
    return _sig("source_link", "ok", "source: {}".format(shown)) if _has_link(value) else _sig(
        "source_link", "caution", "no source repository link")


def _metadata_unavailable(why):
    return {c: _not_run(c, "registry metadata unavailable: {}".format(why))
            for c in ("deprecated", "release_age", "install_scripts", "source_link")}


def _npm_metadata(ctx, name, version, now):
    missing = "npm {}@{} not found on registry.npmjs.org".format(name, version)
    doc, why = _registry_doc(ctx, NPM_URL + urllib.parse.quote(name, safe="@"), missing)
    if doc is None:
        return _metadata_unavailable(why)
    versions = doc.get("versions")
    if not isinstance(versions, dict):
        return _metadata_unavailable("packument has no versions")
    if version not in versions:
        raise NotFoundError(missing)
    entry = versions[version]
    if not isinstance(entry, dict):
        return _metadata_unavailable("version entry is malformed")
    deprecated = entry.get("deprecated")
    scripts = entry.get("scripts") if isinstance(entry.get("scripts"), dict) else {}
    present = ["{}: {}".format(k, _clean(scripts[k], 60)) for k in INSTALL_SCRIPT_KEYS if scripts.get(k)]
    times = doc.get("time")
    repo = entry.get("repository") or doc.get("repository")
    return {
        "deprecated": _sig("deprecated", "stop", "deprecated: {}".format(deprecated)) if deprecated
        else _sig("deprecated", "ok", "not deprecated"),
        "release_age": _release_age(times.get(version) if isinstance(times, dict) else None, now),
        "install_scripts": _sig("install_scripts", "caution", "install scripts present: " + "; ".join(present)) if present
        else _sig("install_scripts", "ok", "no preinstall/install/postinstall script"),
        "source_link": _link_sig(repo, repo.get("url") if isinstance(repo, dict) else repo),
    }


def _pypi_metadata(ctx, name, version, now):
    missing = "pypi {}@{} not found on pypi.org".format(name, version)
    doc, why = _registry_doc(ctx, "{}{}/{}/json".format(PYPI_URL, urllib.parse.quote(name), urllib.parse.quote(version)), missing)
    info = doc.get("info") if doc else None
    if not isinstance(info, dict):
        return _metadata_unavailable(why or "response has no info object")
    uploads = [u.get("upload_time_iso_8601") for u in doc.get("urls") or [] if isinstance(u, dict)]
    stamps = sorted((_parse_time(t), t) for t in uploads if _parse_time(t))
    links = info.get("project_urls")
    has_links = isinstance(links, dict) and any(_has_link(v) for v in links.values())
    return {
        "deprecated": _sig("deprecated", "stop", "yanked: {}".format(info.get("yanked_reason") or "no reason given"))
        if info.get("yanked") is True else _sig("deprecated", "ok", "not yanked"),
        "release_age": _release_age(stamps[0][1] if stamps else None, now),
        "source_link": _sig("source_link", "ok", "project_urls: {}".format(_names(sorted(links)))) if has_links
        else _sig("source_link", "caution", "no project_urls source link"),
    }


def _crates_metadata(ctx, name, version, now):
    missing = "crates.io {}@{} not found on crates.io".format(name, version)
    base = CRATES_URL + urllib.parse.quote(name)
    doc, why = _registry_doc(ctx, "{}/{}".format(base, urllib.parse.quote(version)), missing)
    entry = doc.get("version") if doc else None
    if not isinstance(entry, dict):
        return _metadata_unavailable(why or "response has no version object")
    result = {
        "deprecated": _sig("deprecated", "stop", "yanked") if entry.get("yanked") is True else _sig("deprecated", "ok", "not yanked"),
        "release_age": _release_age(entry.get("created_at"), now),
    }
    try:
        crate_doc, why = _registry_doc(ctx, base, missing)
    except NotFoundError:
        crate_doc, why = None, "crate endpoint answered 404"
    crate = crate_doc.get("crate") if crate_doc else None
    result["source_link"] = _link_sig(crate.get("repository"), crate.get("repository")) if isinstance(crate, dict) else _not_run(
        "source_link", "crate metadata unavailable: {}".format(why or "response has no crate object"))
    return result


_METADATA = {"npm": _npm_metadata, "pypi": _pypi_metadata, "crates.io": _crates_metadata}


# ---------------------------------------------------------------- typosquat and popularity

def name_variants(name):
    """Names this one could be a typo of: single deletion, adjacent transposition, doubled-letter
    collapse, `-`/`_`/`.` swaps, and the scope dropped. Sorted, unique, never the name itself, and
    always a valid unscoped name -- a scoped name yields only unscoped variants."""
    bare = name.split("/", 1)[1] if name.startswith("@") and "/" in name else name
    found = {bare}
    found.update(bare[:i] + bare[i + 1:] for i in range(len(bare)))
    found.update(bare[:i] + bare[i + 1] + bare[i] + bare[i + 2:] for i in range(len(bare) - 1))
    found.add(re.sub(r"(.)\1+", r"\1", bare))
    for i, char in enumerate(bare):
        if char in "-_.":
            found.update(bare[:i] + other + bare[i + 1:] for other in "-_." if other != char)
    found.update(re.sub(r"[-_.]", other, bare) for other in "-_.")
    valid = set()
    for candidate in found - {name}:
        try:
            vr.validate_name("npm", candidate)
        except vr.ValidationError:
            continue
        if not candidate.startswith("@"):
            valid.add(candidate)
    return sorted(valid)


def _weekly_downloads(body):
    count = body.get("downloads") if isinstance(body, dict) else None
    return count if isinstance(count, int) and not isinstance(count, bool) else None


def _requested_downloads(ctx, name):
    """The requested name's own count; 404 means the downloads API has no data for it (brand new)."""
    status, body = _fetch(ctx, "GET", NPM_DOWNLOADS_URL + name)
    if status == 404:
        return 0, "no download data (HTTP 404)"
    if status != 200 or _weekly_downloads(body) is None:
        raise _Unavailable("downloads answer unusable (HTTP {})".format(status))
    return _weekly_downloads(body), None


def _variant_downloads(ctx, variants):
    """name -> weekly downloads for the variants that exist, in chunks (the bulk endpoint takes unscoped names)."""
    found = {}
    for start in range(0, len(variants), BULK_CHUNK):
        chunk = variants[start:start + BULK_CHUNK]
        status, body = _fetch(ctx, "GET", NPM_DOWNLOADS_URL + ",".join(chunk))
        if len(chunk) == 1 and status == 404:
            continue
        if status != 200 or not isinstance(body, dict) or "error" in body:
            raise _Unavailable("bulk downloads answer unusable (HTTP {})".format(status))
        if len(chunk) == 1 and "downloads" in body:  # a one-name request comes back flat, not keyed by name
            body = {chunk[0]: body}
        for variant in chunk:
            count = _weekly_downloads(body.get(variant))
            if count is not None:
                found[variant] = count
    return found


def _npm_downloads_checks(ctx, name):
    try:
        requested, note = _requested_downloads(ctx, name)
    except _Unavailable as exc:
        why = "npm downloads unavailable: {}".format(exc)
        return {"popularity": _not_run("popularity", why), "typosquat": _not_run("typosquat", why)}
    status = "caution" if requested < MIN_WEEKLY_DOWNLOADS else "ok"
    popularity = _sig("popularity", status, "{} downloads last week ({}; caution under {})".format(
        requested, note or "npm downloads API", MIN_WEEKLY_DOWNLOADS))
    variants = name_variants(name)
    try:
        counts = _variant_downloads(ctx, variants)
    except _Unavailable as exc:
        return {"popularity": popularity, "typosquat": _not_run("typosquat", "variant downloads unavailable: {}".format(exc))}
    floor = TYPOSQUAT_RATIO * max(requested, 1)  # an unknown/zero count is read as 1, so a lone download is not a stop
    hits = sorted(((c, v) for v, c in counts.items() if c >= floor), reverse=True)
    if hits:
        detail = "{} may be a typo of {} ({} downloads last week vs {}; stop at {}x)".format(
            name, _names([v for _c, v in hits]), hits[0][0], requested, TYPOSQUAT_RATIO)
        return {"popularity": popularity, "typosquat": _sig("typosquat", "stop", detail)}
    detail = "no variant has {}x the {} weekly downloads ({} variants checked, {} exist)".format(
        TYPOSQUAT_RATIO, requested, len(variants), len(counts))
    return {"popularity": popularity, "typosquat": _sig("typosquat", "ok", detail)}


def _canonical(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def _existence_check(ctx, ecosystem, name):
    """PyPI/crates have no popularity source, so a similar name that exists is a caution. Separator-only
    variants are skipped: both registries treat `-`, `_` and `.` as the same name."""
    probe_url = {"pypi": lambda n: "{}{}/json".format(PYPI_URL, urllib.parse.quote(n)),
                 "crates.io": lambda n: CRATES_URL + urllib.parse.quote(n)}[ecosystem]
    candidates = [v for v in name_variants(name) if _canonical(v) != _canonical(name)]
    probed, exist, failures = candidates[:MAX_EXISTENCE_PROBES], [], 0
    for variant in probed:
        try:
            status, _body = _fetch(ctx, "GET", probe_url(variant))
        except _Unavailable:
            failures += 1
            continue
        if status == 200:
            exist.append(variant)
        elif status != 404:
            failures += 1
    notes = ["only the first {} of {} variants were checked".format(len(probed), len(candidates))] if len(probed) < len(candidates) else []
    if exist:
        return _sig("typosquat", "caution", "similar names exist: {} (no popularity data to compare)".format(_names(exist)), notes=notes)
    if failures or notes:
        return _not_run("typosquat", "{} of {} variant lookups failed or were skipped".format(
            failures + len(candidates) - len(probed), len(candidates)))
    return _sig("typosquat", "ok", "no similar name found among {} variants".format(len(candidates)))


# ---------------------------------------------------------------- transitive_vulns (npm + osv-scanner)

def _lock_package_count(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return sum(1 for key in json.load(handle)["packages"] if key)
    except (OSError, ValueError, KeyError, TypeError):
        return None


def _scanner_findings(out):
    """-> (advisory ids in order, number of packages with advisories), or None if the JSON is unusable."""
    try:
        doc = json.loads(out)
        ids, with_advisories = [], 0
        for result in doc.get("results") or []:
            for package in result.get("packages") or []:
                found = [v["id"] for v in package.get("vulnerabilities") or [] if isinstance(v.get("id"), str)]
                with_advisories += bool(found)
                ids.extend(i for i in found if i not in ids)
        return [_clean(i, 64) for i in ids], with_advisories
    except (ValueError, AttributeError, TypeError, KeyError):
        return None


def _transitive_in(ctx, scratch, name, version, scanner, used):
    step = "npm install --package-lock-only"
    with open(os.path.join(scratch, "package.json"), "w", encoding="utf-8") as handle:
        json.dump({"name": "vet-dependency-scratch", "version": "0.0.0", "private": True,
                   "dependencies": {name: version}}, handle)
    try:
        rc, _out, _err = _run(ctx, ["npm", "install", "--package-lock-only", "--ignore-scripts"], scratch, used)
    except _Unavailable as exc:
        return _not_run("transitive_vulns", "{}: {}".format(step, exc))
    lock = os.path.join(scratch, "package-lock.json")
    if rc != 0:
        return _not_run("transitive_vulns", "{} exited {}".format(step, rc))
    if not os.path.isfile(lock):
        return _not_run("transitive_vulns", "npm produced no lockfile")
    try:
        rc, out, _err = _run(ctx, [scanner, "scan", "-L", lock, "--format", "json"], scratch, used)
    except _Unavailable as exc:
        return _not_run("transitive_vulns", "osv-scanner: {}".format(exc))
    total = _lock_package_count(lock)
    if rc == 0:
        return _sig("transitive_vulns", "ok", "no advisories in {} resolved packages".format(total) if total is not None
                    else "no advisories (package count unavailable)",
                    counts={"packages": total, "with_advisories": 0} if total is not None else None)
    if rc == 128:
        return _not_run("transitive_vulns", "osv-scanner: no packages found (exit 128)")
    if rc != 1:
        return _not_run("transitive_vulns", "osv-scanner exited {}".format(rc))
    findings = _scanner_findings(out)
    if findings is None:
        return _not_run("transitive_vulns", "osv-scanner exited 1 but its output is not usable JSON")
    ids, with_advisories = findings
    if not ids:
        return _not_run("transitive_vulns", "osv-scanner exited 1 but listed no advisories")
    return _sig("transitive_vulns", "stop", "{} advisories in {} packages: {}".format(len(ids), with_advisories, _names(ids)),
                advisories=ids, counts={"packages": total, "with_advisories": with_advisories})


def check_transitive(ctx, ecosystem, name, version, used):
    if ecosystem != "npm":
        return _not_run("transitive_vulns", "transitive scan unsupported for {} in v1".format(ecosystem))
    scanner = ctx.which("osv-scanner")
    if not scanner:
        return _not_run("transitive_vulns", "osv-scanner not on PATH")
    scratch = tempfile.mkdtemp(prefix="vet-dependency-")
    try:
        return _transitive_in(ctx, scratch, name, version, scanner, used)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


# ---------------------------------------------------------------- Homebrew (D8)

def _brew_stable(ctx, name, used):
    try:
        rc, out, err = _run(ctx, ["brew", "info", "--json=v2", name], None, used)
    except _Unavailable as exc:
        raise VetError("homebrew {}: {}".format(name, exc))
    if rc != 0:
        raise VetError("homebrew {}: brew info exited {}: {}".format(name, rc, _clean((err.strip().splitlines() or [""])[0], 120)))
    try:
        stable = json.loads(out)["formulae"][0]["versions"]["stable"]
    except (ValueError, KeyError, IndexError, TypeError):
        raise VetError("homebrew {}: brew info output has no formula with a stable version".format(name))
    if not isinstance(stable, str) or not stable:
        raise VetError("homebrew {}: brew reports no stable version".format(name))
    try:
        vr.record_path(_PROBE_STORE, "homebrew", name, stable)
    except vr.ValidationError as exc:
        raise VetError("homebrew {}: stable version is not usable as a record key: {}".format(name, exc))
    return stable


# ---------------------------------------------------------------- the whole vet

def _unsupported(check, ecosystem):
    if ecosystem == "homebrew" and check in ("direct_vulns", "transitive_vulns"):
        return _not_run(check, "no OSV ecosystem for homebrew")
    return _not_run(check, "not supported for {} in v1".format(ecosystem))


def vet(ctx, ecosystem, name, version):
    """Run every check for one package. Raises vr.ValidationError for bad input (nothing is fetched),
    VetError (NotFoundError/OsvError) when it cannot be vetted, else returns the signals and the verdict inputs."""
    vr.validate_ecosystem(ecosystem)
    vr.validate_name(ecosystem, name)
    version = vr.validate_version(ecosystem, version)
    if name.startswith("-"):
        raise vr.ValidationError("package name {!r} must not start with '-'".format(name))
    now, used, got = ctx.now(), set(), {}
    if ecosystem == "homebrew":
        version = _brew_stable(ctx, name, used)
    else:
        if ecosystem in _METADATA:
            got.update(_METADATA[ecosystem](ctx, name, version, now))
        got["direct_vulns"] = check_direct_vulns(ctx, ecosystem, name, version)
        got["transitive_vulns"] = check_transitive(ctx, ecosystem, name, version, used)
        if ecosystem == "npm":
            got.update(_npm_downloads_checks(ctx, name))
        elif ecosystem in _METADATA:  # pypi, crates.io: existence only
            got["typosquat"] = _existence_check(ctx, ecosystem, name)
    signals = [got.get(check) or _unsupported(check, ecosystem) for check in CHECKS]
    reasons = ["{}: {}".format(s["check"], s["detail"]) for s in signals if s["status"] == "not_run"]
    return {"ecosystem": ecosystem, "name": name, "version": version, "vetted_at": vr.format_vetted_at(now),
            "signals": signals, "tool_versions": _tool_versions(ctx, used),
            "complete": not reasons, "incomplete_reasons": reasons}


def to_record(vetted, report):
    """The schema-1 record (Contracts): signals reduced to check/status/detail; validated before returning."""
    record = {key: vetted[key] for key in ("ecosystem", "name", "version", "vetted_at", "complete", "incomplete_reasons")}
    record.update(schema=vr.SCHEMA_VERSION, report=report,
                  signals=[{k: s[k] for k in ("check", "status", "detail")} for s in vetted["signals"]])
    return vr.validate_record(record)
