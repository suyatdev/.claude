"""Vetting records for dependency-guard: input validation, path containment, expiry, read/write.

Spec: docs/features/dependency-vetting-guard.md (Contracts, D8, Failure handling). This module is
the one definition of "valid package input" and of "pinned": the classifiers, the hook and the
vetter all import it, so nothing else decides either. Standard library only (Python 3.9: no tomllib).

Reading never raises on a bad store: every unreadable, corrupt, wrong-schema, misfiled or
out-of-store record is reported as `(None, reason)` -- the hook treats that as "no record" and the
reason is there for its log. Validation helpers raise `ValidationError`; writes raise on failure.
The clock is always passed in (`now`, an aware datetime), never read here.
"""

import datetime
import json
import os
import re
import tempfile
import types

ECOSYSTEMS = ("npm", "pypi", "crates.io", "go", "rubygems", "homebrew")
SCHEMA_VERSION = 1
VET_MAX_AGE_DAYS = 7
VET_MAX_AGE = datetime.timedelta(days=VET_MAX_AGE_DAYS)
DIR_MODE = 0o700
FILE_MODE = 0o600
NAME_MAX_LENGTH = 214
VETTED_AT_FORMAT = "%Y-%m-%dT%H:%M:%SZ"
SIGNAL_STATUSES = ("ok", "stop", "caution", "not_run")
RECORD_SUFFIX = ".json"
REPORT_SUFFIX = ".md"
SLASH_REPLACEMENT = "__"

# OSV names every ecosystem but Homebrew, which has none (D8).
OSV_ECOSYSTEMS = types.MappingProxyType({
    "npm": "npm", "pypi": "PyPI", "crates.io": "crates.io", "go": "Go", "rubygems": "RubyGems",
})

# Slashes a name may carry, by ecosystem; go takes module paths of any depth.
_MAX_SLASHES = {"npm": 1, "pypi": 0, "crates.io": 0, "go": None, "rubygems": 0, "homebrew": 2}

_NAME_RE = re.compile(r"[A-Za-z0-9._@/-]{1,%d}" % NAME_MAX_LENGTH)
_NPM_SCOPED_RE = re.compile(r"@[A-Za-z0-9._-]+/[A-Za-z0-9._-]+")
_SAFE_NAME_RE = re.compile(r"[A-Za-z0-9._@-]+")
# npm's bare `owner/repo[#ref]` GitHub shorthand: the one definition (spec, "Not from a registry").
# The owner is a GitHub account name -- letters, digits, hyphens, no dots -- so `1.2.3/evil` is a
# malformed version, not a source. A bare `#` counts (`#.*`): `owner/repo#` is still a git source,
# and refusing it would turn an ask into a deny.
NPM_GIT_SHORTHAND_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+(?:#.*)?")
# Homebrew's version is whatever `brew info` calls stable; it is only ever a file name here.
_BREW_VERSION_RE = re.compile(r"[A-Za-z0-9._+-]{1,64}")
_VETTED_AT_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")

# SemVer's dot-separated identifiers (no empty part, so no `..`) and a number with no leading zero.
_ID = r"[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*"
_N = r"(?:0|[1-9][0-9]*)"
_SEMVER = r"{n}\.{n}\.{n}(?:-{id})?(?:\+{id})?".format(n=_N, id=_ID)
_EXACT_VERSION_PATTERNS = {
    "npm": re.compile(_SEMVER, re.ASCII),
    "crates.io": re.compile(_SEMVER, re.ASCII),
    # PEP 440 subset: no epoch; a local label (+cu118, +CU118) is exact.
    "pypi": re.compile(r"[0-9]+(?:\.[0-9]+)*(?:(?:a|b|rc)[0-9]+)?(?:\.post[0-9]+)?(?:\.dev[0-9]+)?"
                       r"(?:\+[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*)?", re.ASCII),
    "go": re.compile(r"v{n}\.{n}\.{n}(?:-{id})?(?:\+incompatible)?".format(n=_N, id=_ID), re.ASCII),
    "rubygems": re.compile(r"{n}(?:\.{n})+(?:\.[0-9A-Za-z]+)*".format(n=_N), re.ASCII),
}
_RECORD_KEYS = ("schema", "ecosystem", "name", "version", "vetted_at", "complete",
                "incomplete_reasons", "signals", "report")


class ValidationError(ValueError):
    """An input or a record broke a rule in the spec's Input validation table."""


def _show(value):
    return repr(value)[:80]


# ---------------------------------------------------------------- input validation

def validate_ecosystem(ecosystem):
    if not isinstance(ecosystem, str) or ecosystem not in ECOSYSTEMS:
        raise ValidationError("unknown ecosystem {}".format(_show(ecosystem)))
    return ecosystem


def osv_ecosystem(ecosystem):
    """The OSV ecosystem name, or None for homebrew (D8)."""
    return OSV_ECOSYSTEMS.get(validate_ecosystem(ecosystem))


def validate_name(ecosystem, name):
    validate_ecosystem(ecosystem)
    if not isinstance(name, str) or not _NAME_RE.fullmatch(name):
        raise ValidationError("invalid package name {}".format(_show(name)))
    if name.startswith("-"):  # would read as an option to `brew info` and the vetter
        raise ValidationError("package name {} starts with '-'".format(_show(name)))
    if name == "." or ".." in name:
        raise ValidationError("package name {} has a dot segment".format(_show(name)))
    if name.startswith("/") or name.endswith("/") or "//" in name:
        raise ValidationError("package name {} has a misplaced slash".format(_show(name)))
    slashes = name.count("/")
    limit = _MAX_SLASHES[ecosystem]
    if limit is not None and slashes > limit:
        raise ValidationError("{} package name {} has too many slashes".format(ecosystem, _show(name)))
    if ecosystem == "npm" and (name.startswith("@") or slashes) and not _NPM_SCOPED_RE.fullmatch(name):
        raise ValidationError("npm package name {} is not name or @scope/name".format(_show(name)))
    return name


def safe_name(name):
    """The directory name for a package: `/` becomes `__`, and the result must be path-safe."""
    candidate = name.replace("/", SLASH_REPLACEMENT) if isinstance(name, str) else name
    if (not isinstance(candidate, str) or not _SAFE_NAME_RE.fullmatch(candidate)
            or candidate in (".", "..")):
        raise ValidationError("package name {} has no safe directory name".format(_show(name)))
    return candidate


def is_exact_version(ecosystem, version):
    """The one definition of "pinned". Homebrew is never consulted (D8), so it is always False."""
    validate_ecosystem(ecosystem)
    pattern = _EXACT_VERSION_PATTERNS.get(ecosystem)
    return isinstance(version, str) and pattern is not None and pattern.fullmatch(version) is not None


def is_npm_git_shorthand(value):
    """True when the whole value is npm's bare `owner/repo[#ref]` GitHub shorthand."""
    return isinstance(value, str) and NPM_GIT_SHORTHAND_RE.fullmatch(value) is not None


def validate_version(ecosystem, version):
    """The vetter's rule: an exact version is required, except for homebrew, where it must be absent."""
    validate_ecosystem(ecosystem)
    if ecosystem == "homebrew":
        if version is not None:
            raise ValidationError("homebrew takes no version (D8), got {}".format(_show(version)))
        return None
    if not is_exact_version(ecosystem, version):
        raise ValidationError("{} version {} is not an exact version".format(ecosystem, _show(version)))
    return version


def _validate_record_version(ecosystem, version):
    """A version that is going to become a file name: exact, or for homebrew a safe stable string."""
    if ecosystem != "homebrew":
        return validate_version(ecosystem, version)
    if (not isinstance(version, str) or not _BREW_VERSION_RE.fullmatch(version)
            or version == "." or ".." in version):
        raise ValidationError("homebrew record version {} is not a safe file name".format(_show(version)))
    return version


# ---------------------------------------------------------------- time

def _require_aware(moment):
    if not isinstance(moment, datetime.datetime) or moment.tzinfo is None:
        raise ValidationError("clock value must be a timezone-aware datetime")
    return moment


def format_vetted_at(now):
    return _require_aware(now).astimezone(datetime.timezone.utc).strftime(VETTED_AT_FORMAT)


def parse_vetted_at(text):
    if not isinstance(text, str) or not _VETTED_AT_RE.fullmatch(text):
        raise ValidationError("vetted_at {} is not YYYY-MM-DDTHH:MM:SSZ".format(_show(text)))
    try:
        parsed = datetime.datetime.strptime(text, VETTED_AT_FORMAT)
    except ValueError as exc:
        raise ValidationError("vetted_at {} is not a real time: {}".format(_show(text), exc))
    return parsed.replace(tzinfo=datetime.timezone.utc)


def is_fresh(record, now):
    """Fresh while 0 <= now - vetted_at < VET_MAX_AGE. A record dated in the future is not trusted."""
    age = _require_aware(now) - parse_vetted_at(record["vetted_at"])
    return datetime.timedelta(0) <= age < VET_MAX_AGE


# ---------------------------------------------------------------- record schema

def _fail(message):
    raise ValidationError("record: " + message)


def _validate_signal(signal):
    if not isinstance(signal, dict):
        _fail("signal is not an object")
    for key in ("check", "status", "detail"):
        if not isinstance(signal.get(key), str):
            _fail("signal {} is missing or not a string".format(key))
    if not signal["check"] or signal["status"] not in SIGNAL_STATUSES:
        _fail("signal {} has an empty check or unknown status {}".format(_show(signal), _show(signal["status"])))


def validate_record(record):
    """Return `record` if it matches schema 1, else raise ValidationError. Extra keys are ignored."""
    if not isinstance(record, dict):
        _fail("not an object")
    for key in _RECORD_KEYS:
        if key not in record:
            _fail("missing key " + key)
    schema = record["schema"]
    if type(schema) is not int or schema != SCHEMA_VERSION:  # type(): True == 1 in Python
        _fail("schema {} is not {}".format(_show(schema), SCHEMA_VERSION))
    validate_ecosystem(record["ecosystem"])
    validate_name(record["ecosystem"], record["name"])
    _validate_record_version(record["ecosystem"], record["version"])
    parse_vetted_at(record["vetted_at"])
    if not isinstance(record["complete"], bool):
        _fail("complete is not a boolean")
    reasons = record["incomplete_reasons"]
    if not isinstance(reasons, list) or not all(isinstance(r, str) for r in reasons):
        _fail("incomplete_reasons is not a list of strings")
    if not isinstance(record["signals"], list):
        _fail("signals is not a list")
    for signal in record["signals"]:
        _validate_signal(signal)
    if not isinstance(record["report"], str) or not record["report"]:
        _fail("report is not a non-empty string")
    return record


# ---------------------------------------------------------------- paths

def _inside_store(store, path):
    return os.path.realpath(path).startswith(os.path.realpath(store) + os.sep)


def _checked_dir(store, ecosystem, name):
    validate_name(ecosystem, name)
    directory = os.path.join(store, ecosystem, safe_name(name))
    if not _inside_store(store, directory):
        raise ValidationError("path for {} {} resolves outside the vetting store".format(ecosystem, _show(name)))
    return directory


def _entry_path(store, ecosystem, name, version, suffix):
    _validate_record_version(ecosystem, version)
    path = os.path.join(_checked_dir(store, ecosystem, name), version + suffix)
    if not _inside_store(store, path):
        raise ValidationError("path for {} {}@{} resolves outside the vetting store".format(
            ecosystem, _show(name), _show(version)))
    return path


def record_path(store, ecosystem, name, version):
    """`<store>/<ecosystem>/<safe-name>/<version>.json`, after every validation rule and containment."""
    return _entry_path(store, ecosystem, name, version, RECORD_SUFFIX)


def report_path(store, ecosystem, name, version):
    return _entry_path(store, ecosystem, name, version, REPORT_SUFFIX)


# ---------------------------------------------------------------- reading

def read_record(store, ecosystem, name, version):
    """`(record, None)` or `(None, reason)`. Never raises on a bad store: every failure is "no record"."""
    try:
        path = record_path(store, ecosystem, name, version)
    except ValidationError as exc:
        return None, "invalid key: {}".format(exc)
    try:
        with open(path, "rb") as handle:
            text = handle.read().decode("utf-8")
    except FileNotFoundError:
        return None, "no record"
    except (OSError, UnicodeDecodeError) as exc:
        return None, "unreadable: {}".format(exc)
    try:
        record = validate_record(json.loads(text))
    except (ValueError, RecursionError) as exc:  # json.JSONDecodeError and ValidationError are ValueErrors
        return None, "bad record: {}".format(exc)
    if (record["ecosystem"], record["name"], record["version"]) != (ecosystem, name, version):
        return None, "record names {} {}@{}, not the package it is filed under".format(
            record["ecosystem"], _show(record["name"]), _show(record["version"]))
    return record, None


def read_fresh_record(store, ecosystem, name, version, now):
    record, problem = read_record(store, ecosystem, name, version)
    if record is None:
        return None, problem
    if not is_fresh(record, now):
        return None, "stale: vetted_at {}".format(record["vetted_at"])
    return record, None


def newest_fresh_homebrew_record(store, name, now):
    """D8: Homebrew's command carries no version, so take the newest fresh record for the formula.

    "Newest" is by `vetted_at`; an entry that is stale, corrupt, misfiled or not a `.json` file is
    skipped rather than blocking an older valid one. Returns `(record, None)` or `(None, reason)`.
    """
    try:
        directory = _checked_dir(store, "homebrew", name)
    except ValidationError as exc:
        return None, "invalid key: {}".format(exc)
    try:
        entries = sorted(os.listdir(directory))
    except FileNotFoundError:
        return None, "no record"
    except OSError as exc:
        return None, "unreadable: {}".format(exc)
    best_key, best = None, None
    for entry in entries:
        if not entry.endswith(RECORD_SUFFIX):
            continue
        version = entry[:-len(RECORD_SUFFIX)]
        record, _problem = read_fresh_record(store, "homebrew", name, version, now)
        if record is None:
            continue
        key = (parse_vetted_at(record["vetted_at"]), version)
        if best_key is None or key > best_key:
            best_key, best = key, record
    if best is None:
        return None, "no fresh record"
    return best, None


# ---------------------------------------------------------------- writing

def _ensure_private_dir(path):
    if os.path.isdir(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        os.mkdir(path, DIR_MODE)
    except FileExistsError:
        return
    os.chmod(path, DIR_MODE)  # mkdir's mode is masked by umask


def _write_atomic(store, path, text):
    """Temp file in the target directory, then os.replace; on any failure the temp file is removed."""
    directory = os.path.dirname(path)
    levels = [store, os.path.dirname(directory), directory]
    for level in levels:
        _ensure_private_dir(level)
    descriptor, temp = tempfile.mkstemp(prefix=".write-", suffix=".tmp", dir=directory)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, FILE_MODE)
        os.replace(temp, path)
    except BaseException:
        try:
            os.remove(temp)
        except FileNotFoundError:
            pass
        raise
    return path


def write_record(store, record):
    """Validate, then write `<version>.json` atomically (dirs 0700, file 0600). Returns the path."""
    validate_record(record)
    path = record_path(store, record["ecosystem"], record["name"], record["version"])
    return _write_atomic(store, path, json.dumps(record, indent=2, sort_keys=True) + "\n")


def write_report(store, ecosystem, name, version, text):
    """Write the human-readable `<version>.md` beside the record, same atomicity and modes."""
    return _write_atomic(store, report_path(store, ecosystem, name, version), text)
