"""Test doubles for the vetter suites: a replaying HTTP opener, a fake subprocess runner, a network trap.

Imported by hooks/lib/vet_checks.test.py and hooks/bin/vet-dependency.test.py. Nothing here opens a
socket. The JSON beside this file (osv.json, npm.json, other.json) is HAND-WRITTEN to match the
response shapes the spec names -- none of it was fetched from a live registry or from OSV.
"""

import copy
import io
import json
import os
import socket
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
_CACHE = {}


def fx(file, name):
    """A deep copy of fixture `name` from `<file>.json` (a copy, so a test may edit it freely)."""
    if file not in _CACHE:
        with open(os.path.join(HERE, file + ".json"), encoding="utf-8") as handle:
            _CACHE[file] = json.load(handle)
    return copy.deepcopy(_CACHE[file][name])


class UnroutedRequest(AssertionError):
    """The code under test asked for a URL the test did not record -- a hidden dependency."""


class FakeResponse:
    def __init__(self, status, data):
        self.status = status
        self._data = data

    def read(self, limit=-1):
        return self._data if limit is None or limit < 0 else self._data[:limit]

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class Replay:
    """`urlopen` stand-in. Routes are (METHOD, url) -> outcome; an outcome is a fixture
    `{"status", "body"}` (or `"raw"` for a non-JSON body), an Exception instance (raised, as a
    network failure would be), or a callable taking the request body bytes.
    Like the real urlopen, a status other than 2xx raises HTTPError."""

    def __init__(self):
        self.exact = {}
        self.prefixes = []
        self.requests = []

    def add(self, method, url, outcome, prefix=False):
        if prefix:
            self.prefixes.append((method, url, outcome))
        else:
            self.exact[(method, url)] = outcome
        return self

    def _lookup(self, method, url):
        if (method, url) in self.exact:
            return self.exact[(method, url)]
        for pmethod, purl, outcome in self.prefixes:
            if pmethod == method and url.startswith(purl):
                return outcome
        raise UnroutedRequest("{} {} was not recorded".format(method, url))

    def urls(self):
        return [url for _method, url, _data in self.requests]

    def body_of(self, index):
        return json.loads(self.requests[index][2].decode("utf-8"))

    def __call__(self, request, timeout=None):
        method, url, data = request.get_method(), request.full_url, request.data
        self.requests.append((method, url, data))
        outcome = self._lookup(method, url)
        if callable(outcome):
            outcome = outcome(data)
        if isinstance(outcome, BaseException):
            raise outcome
        payload = outcome["raw"].encode("utf-8") if "raw" in outcome else json.dumps(outcome["body"]).encode("utf-8")
        status = outcome["status"]
        if 200 <= status < 300:
            return FakeResponse(status, payload)
        raise urllib.error.HTTPError(url, status, "fixture", {}, io.BytesIO(payload))


class FakeRunner:
    """`subprocess` stand-in: runner(argv, cwd, timeout) -> (returncode, stdout, stderr).
    `handlers` maps a program name to fn(argv, cwd) -> (rc, out, err); the fn may raise
    subprocess.TimeoutExpired or FileNotFoundError. A program with no handler is not installed.
    `--version` is answered for any installed program."""

    VERSIONS = {"npm": "12.0.1", "osv-scanner": "2.6.0", "brew": "6.0.14"}

    def __init__(self, handlers=None):
        self.handlers = dict(handlers or {})
        self.calls = []

    def programs(self, argv_prefix):
        return [c for c in self.calls if c[0][:len(argv_prefix)] == list(argv_prefix)]

    def __call__(self, argv, cwd=None, timeout=None):
        self.calls.append((list(argv), cwd))
        program = os.path.basename(argv[0])
        if program not in self.handlers:
            raise FileNotFoundError(argv[0])
        if argv[1:] == ["--version"]:
            return 0, self.VERSIONS.get(program, "0.0.0") + "\n", ""
        return self.handlers[program](list(argv), cwd)


class Blocked(OSError):
    """Raised by the network trap in place of a connection."""


class NetworkTrap:
    """While installed, DNS lookup and socket connect raise Blocked and are counted, so any code
    path that would really reach the network (the default urlopen included) fails and is visible."""

    def __init__(self):
        self.attempts = []
        self._saved = None

    def _blocked(self, *args, **kwargs):
        self.attempts.append(args[:2])
        raise Blocked("network access blocked by the test suite")

    def install(self):
        self._saved = (socket.getaddrinfo, socket.socket.connect)
        socket.getaddrinfo = self._blocked
        socket.socket.connect = self._blocked
        return self

    def remove(self):
        socket.getaddrinfo, socket.socket.connect = self._saved
