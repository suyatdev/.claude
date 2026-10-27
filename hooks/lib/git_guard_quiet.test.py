#!/usr/bin/env python3
"""Unit tests for git_guard_quiet.py, the child process behind `git-guard quiet`.
Run: python3 hooks/lib/git_guard_quiet.test.py

Card: docs/features/git-guard-quiet.md -- D5-D9, the Line rule, "git-guard -- the quiet decision"
(Input / Timeouts / What "allow" means), "Log line", R18, R24 (child side), R25.

Every case drives the child the way git-guard does: one JSON object on stdin, a real
classify-git-command.py supplying the facts, real git repositories and linked worktrees as
fixtures, a throwaway $HOME. Nothing imports the module under test, so GIT_GUARD_QUIET_LIB can
point at a stub to falsify the suite (a run against an override never writes a test marker).

Each case asserts the ANSWER and the log together: an allow appends exactly one line, an ask
appends none. Deliberately dependency-free (no pytest), like its siblings.
"""

import datetime
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

MARKER_SELF = os.path.abspath(__file__)
_HERE = os.path.dirname(MARKER_SELF)
MARKER_ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=_HERE,
                             capture_output=True, text=True, check=True).stdout.strip()
DEFAULT_LIB = os.path.join(_HERE, "git_guard_quiet.py")
LIB = os.environ.get("GIT_GUARD_QUIET_LIB") or DEFAULT_LIB
CLASSIFIER = os.path.join(_HERE, "classify-git-command.py")
REAL_GIT = shutil.which("git")

SID = "fb455a92-bc6d-49bf-93ff-b776fb118c9c"
GIT_ENV = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
           "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"}
TIMEOUT_BOUND_SECONDS = 3
SLOW_LIMIT_SECONDS = 9

passed = failed = 0


def check(desc, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL -- {}{}".format(desc, "\n     " + detail if detail else ""))


def git(*args, cwd=None):
    return subprocess.run([REAL_GIT] + list(args), cwd=cwd, check=True, capture_output=True, text=True,
                          env=dict(os.environ, **GIT_ENV)).stdout.strip()


def facts_for(command):
    out = subprocess.run([sys.executable, CLASSIFIER], input=command, capture_output=True,
                         text=True, check=True).stdout
    return [line for line in out.split("\n") if line]


class Fixtures:
    """M main repo; F feat/x worktree of M; T main + a tag named main; assorted bad folders."""

    def __init__(self, root):
        self.root = root
        self.home = os.path.join(root, "home")
        os.makedirs(os.path.join(self.home, ".claude", "hooks", "state", "git-guard-quiet"))
        self.log = os.path.join(self.home, ".claude", "hooks", "state", "git-guard-quiet.log")
        self.M = self.repo("M", "main")
        self.F = self.worktree("F", "feat/x")
        self.T = self.repo("T", "main")
        git("tag", "main", cwd=self.T)
        self.not_repo = os.path.join(root, "plain")
        os.makedirs(self.not_repo)
        self.detached = self.worktree("detached", None)
        self.cwd_for_relative = os.path.join(root, "rel")
        os.makedirs(self.cwd_for_relative)
        os.symlink(self.F, os.path.join(self.cwd_for_relative, "feat-rel"))
        os.symlink(self.F, os.path.join(self.home, "wt"))
        # Real feature worktrees whose folder NAME holds a character D6 forbids. Quoted in the
        # command the shell would take them literally, but the classifier cannot see quoting, so D6
        # must ask -- and only a folder that really exists can show the rule firing.
        self.odd_folders = [self.worktree(name, "feat/odd{}".format(i))
                            for i, name in enumerate(("dir$X", "dir*star", "dir?q", "dir[b]"))]

    def repo(self, name, branch):
        path = os.path.join(self.root, name)
        git("init", "-q", "-b", branch, path)
        git("commit", "-q", "--allow-empty", "-m", "seed", cwd=path)
        return path

    def worktree(self, name, branch):
        path = os.path.join(self.root, name)
        if branch:
            git("worktree", "add", "-q", "-b", branch, path, cwd=self.M)
        else:
            git("worktree", "add", "-q", "--detach", path, cwd=self.M)
        return path

    def head_named(self, name, ref):
        """A linked worktree whose HEAD names `ref` (an unborn branch is enough for symbolic-ref)."""
        path = self.worktree(name, None)
        git("symbolic-ref", "HEAD", ref, cwd=path)
        return path

    def marker_path(self, folder, marker):
        out = git("rev-parse", "--git-path", marker, cwd=folder)
        return out if os.path.isabs(out) else os.path.join(folder, out)

    def log_lines(self):
        return log_lines_of(self.home)


def log_lines_of(home):
    try:
        with open(os.path.join(home, ".claude", "hooks", "state", "git-guard-quiet.log")) as handle:
            return handle.read().splitlines()
    except FileNotFoundError:
        return []


def run_child(text, home, extra_env=None, lib=None, umask=None, proc_cwd=None):
    env = {"PATH": os.environ.get("PATH", ""), "HOME": home, "LANG": "en_US.UTF-8"}
    env.update(GIT_ENV)
    env.update(extra_env or {})
    env = {k: v for k, v in env.items() if v is not None}
    preexec = (lambda: os.umask(umask)) if umask is not None else None
    started = time.time()
    done = subprocess.run([sys.executable, "-I", lib or LIB], input=text.encode("utf-8"), env=env,
                          capture_output=True, preexec_fn=preexec, cwd=proc_cwd)
    return done.returncode, done.stdout.decode("utf-8", "replace"), done.stderr.decode("utf-8", "replace"), \
        time.time() - started


def request(command, fx, cwd=None, facts=None, session_id=SID):
    return json.dumps({"command": command, "cwd": cwd or fx.M, "session_id": session_id,
                       "facts": facts if facts is not None else facts_for(command)})


def decide(desc, text, fx, want, home=None, extra_env=None, umask=None, proc_cwd=None):
    """Run the child on `text`; assert answer, exit code and the one-line-per-allow log rule."""
    home = home or fx.home
    before = len(log_lines_of(home))
    rc, out, err, secs = run_child(text, home, extra_env=extra_env, umask=umask, proc_cwd=proc_cwd)
    after = len(log_lines_of(home))
    check("{} -> {}".format(desc, want), rc == 0 and out == want and after - before == (1 if want == "allow" else 0),
          "rc={} stdout={!r} stderr={!r} log+={}".format(rc, out, err[:200], after - before))
    return secs


def cmd_case(fx, desc, command, want, cwd=None, home=None):
    label = "{}  [{}]".format(desc, command[:90].replace("\n", "\\n"))
    return decide(label, request(command, fx, cwd=cwd), fx, want, home=home, proc_cwd=cwd)


def test_input_parsing(fx):
    good = request("git -C {} status".format(fx.F), fx)
    decide("control: well-formed read line", good, fx, "allow")
    for desc, text in (("empty stdin", ""), ("not JSON", "git -C F status"), ("JSON array", "[]"),
                       ("JSON null", "null"), ("truncated JSON", good[:-5])):
        decide("unparseable input: " + desc, text, fx, "ask")
    base = json.loads(good)
    for key in base:
        decide("missing key: " + key, json.dumps({k: v for k, v in base.items() if k != key}), fx, "ask")
    for key, value in (("command", 5), ("command", ""), ("cwd", None), ("facts", "SEG_QUIET\t0\tread"),
                       ("facts", [1]), ("facts", {}), ("session_id", 7)):
        decide("wrong type: {}={!r}".format(key, value), json.dumps(dict(base, **{key: value})), fx, "ask")
    for sid in ("", "../x", "a b", "a" * 129, "a\nb", "a/b"):
        decide("invalid session_id {!r}".format(sid[:12]), json.dumps(dict(base, session_id=sid)), fx, "ask")
    decide("session_id of 128 valid chars", json.dumps(dict(base, session_id="a" * 128)), fx, "allow")
    quiet = "SEG_QUIET\t{}\t{}".format
    for desc, facts in (("no SEG_QUIET fact", ["SCOPE_UNKNOWN\t-C"]),
                        ("a repeated index", [quiet(0, "read"), quiet(0, "read")]),
                        ("an index gap", [quiet(0, "read"), quiet(2, "read")]),
                        ("a non-numeric index", [quiet("x", "read")]),
                        ("an unknown class", [quiet(0, "write")]),
                        ("a class with a tab tail", ["SEG_QUIET\t0"]),
                        ("a fact spanning two lines", [quiet(0, "read") + "\n" + quiet(1, "read")]),
                        ("only nongit segments", [quiet(0, "nongit")])):
        decide("facts: " + desc, json.dumps(dict(base, facts=facts)), fx, "ask")
    # R27: a multi-line command whose later line looks like a fact is data, never a fact.
    forged = "SEG_QUIET\t0\tread"
    cmd_case(fx, "R27: forged fact in a commit message, folder on a feature branch",
             'git -C {} commit -m "x\n{}"'.format(fx.F, forged), "allow")
    cmd_case(fx, "R27: forged fact in a commit message, folder on main",
             'git -C {} commit -m "x\n{}"'.format(fx.M, forged), "ask")


def test_hidden_commands_and_options(fx):
    F = fx.F
    quiet = ["SEG_QUIET\t0\tread"]
    for name in ("SEG_SCOPE_OPT\t0\t-c", "SEG_ENV\t0\tGIT_DIR", "SEG_OPAQUE\t0\tgit", "SEG_GROUPED", "SEG_UNPARSED"):
        decide("D9 fact " + name.split("\t")[0], request("git -C {} status".format(F), fx, facts=quiet + [name]), fx, "ask")
    for desc, command, want in (
        ("-c after -C", "git -C {} -c core.hooksPath=/dev/null status", "ask"),
        ("-c before -C", "git -c core.hooksPath=/dev/null -C {} status", "ask"),
        ("-c on a second segment", "git -C {} status && git -c core.hooksPath=/dev/null status", "ask"),
        ("GIT_* assignment", "GIT_DIR={}/.git git -C {} status", "ask"),
        ("command substitution", 'git -C {} status -- "$(echo hi)"', "ask"),
        ("backtick", 'git -C {} status -- "`echo hi`"', "ask"),
        ("process substitution <(", "git -C {} log <(echo hi)", "ask"),
        ("process substitution >(", "git -C {} log >(cat)", "ask"),
        ("eval, read line", "eval git -C {} status", "ask"),
        ("eval, commit line", "eval git -C {} commit -m x", "ask"),
        ("eval inside a quoted string", 'git -C {} commit -m "x; eval y"', "ask"),
        ("a word merely containing eval", "git -C {} log --grep evaluate", "allow"),
        ("a plain variable (R2 shape)", 'W={}; git -C "$W" status --short; wc -l f', "allow"),
    ):
        cmd_case(fx, "D9 " + desc, command.replace("{}/.git", fx.M + "/.git").replace("{}", F), want)


def test_line_rule(fx):
    F, M = fx.F, fx.M
    for desc, command, want in (
        ("R2 cat-file", "git -C {F} cat-file -t abc", "allow"),
        ("R2 two reads and a nongit", "W={F}; git -C \"$W\" status --short; git -C \"$W\" hash-object f; wc -l f", "allow"),
        ("add alone, any folder", "git -C {M} add -- f", "allow"),
        ("read line may redirect", "git -C {F} log > /dev/null", "allow"),
        ("R3 add, commit, push", "git -C {F} add -- f && git -C {F} commit -m x -- f && git -C {F} push -u origin HEAD", "allow"),
        ("R4 wrapper judged as its command", "time git -C {F} commit -m x", "allow"),
        ("read in any folder beside a good commit", 'git -C "$W" status && git -C {F} commit -m x', "allow"),
        ("add in any folder beside a good commit", "git -C {M} add -A && git -C {F} commit -m x", "allow"),
        ("other subcommand (merge)", "git -C {F} merge feat/y", "ask"),
        ("other subcommand beside a read", "git -C {F} status && git -C {F} switch main", "ask"),
        ("R6 switch main then commit", "git -C {F} switch main && git -C {F} commit -m x", "ask"),
        ("R6 symbolic-ref", "git -C {F} symbolic-ref HEAD refs/heads/main", "ask"),
        ("R6 config", "git -C {F} config core.hooksPath /dev/null", "ask"),
        ("alias", "git -C {F} st", "ask"),
        ("R12 --output", "git -C {F} diff --output=/tmp/x", "ask"),
        ("R22 branch --no-list -D", "git -C {F} branch --list --no-list -D main", "ask"),
        ("R22 branch -M", "git -C {F} branch -l -M main old", "ask"),
        ("R22 hash-object -wt", "git -C {F} hash-object -wt blob f", "ask"),
        ("R22 worktree list --porcelain x", "git -C {F} worktree list --porcelain x", "ask"),
        ("R10 cd then commit", "cd {M} && git -C . commit -m x", "ask"),
        ("R10 pushd then commit", "pushd {M} && git -C . commit -m x", "ask"),
        ("R10 export then commit", "export GIT_DIR={M}/.git; git -C {F} commit -m x", "ask"),
        ("commit beside a script", "./run.sh; git -C {F} commit -m x", "ask"),
        ("commit beside echo", "echo hi && git -C {F} commit -m x", "ask"),
        ("R21 redirect on a commit line", "git -C {F} status > {F}/.git/HEAD && git -C {F} commit -m x", "ask"),
        ("a > inside a commit message", 'git -C {F} commit -m "a > b"', "ask"),
        ("input redirect on a commit line", "git -C {F} commit -m x < /dev/null", "ask"),
        ("plain commit beside a -C read", "git -C {F} status && git commit -m y", "ask"),
        ("second landing segment on main", "git -C {F} commit -m x && git -C {M} push origin HEAD", "ask"),
        ("R5 commit on main", "git -C {M} commit -m x", "ask"),
        ("R5 push on main", "git -C {M} push origin HEAD", "ask"),
    ):
        cmd_case(fx, desc, command.replace("{F}", F).replace("{M}", M), want)


def test_push_shapes(fx):
    F = fx.F
    for command, want in (
        ("git -C {} push origin HEAD", "allow"), ("git -C {} push -u origin HEAD", "allow"),
        ("git -C {} push --force-with-lease origin HEAD", "allow"),
        ("git -C {} push origin HEAD:refs/heads/main", "ask"), ("git -C {} push origin HEAD:main", "ask"),
        ("git -C {} push --all", "ask"), ("git -C {} push --mirror", "ask"),
        ("git -C {} push origin feat/x", "ask"), ("git -C {} push", "ask"),
        ("git -C {} push --force", "ask"), ("git -C {} push -uf origin HEAD", "ask"),
        ("git -C {} push --force-with-lease=feat/x", "ask"), ("git -C {} push --delete origin x", "ask"),
    ):
        cmd_case(fx, "D8", command.format(F), want)


def test_folder_rule(fx):
    F, H = fx.F, fx.home
    rel = "feat-rel"
    cmd_case(fx, "D6 control: absolute folder of the same worktree", "git -C {} commit -m x".format(F), "allow")
    cmd_case(fx, "Task 0: RELATIVE folder asks although it is a valid feature worktree",
             "git -C {} commit -m x".format(rel), "ask", cwd=fx.cwd_for_relative)
    cmd_case(fx, "Task 0: relative ./ folder asks", "git -C ./{} push origin HEAD".format(rel), "ask", cwd=fx.cwd_for_relative)
    cmd_case(fx, "D3: a RELATIVE folder is fine for a read", "git -C {} status".format(rel), "allow", cwd=fx.cwd_for_relative)
    cmd_case(fx, "D3: a folder that does not exist is fine for a read", "git -C /nonexistent/zz status", "allow")
    cmd_case(fx, "D6: ~/ folder (symlink to F under the fake home)", "git -C ~/wt commit -m x", "allow")
    for form in ("~root/x", "~+/x", "~-/x", "~0/x", "~+", "~-", "~root"):
        cmd_case(fx, "D6: other ~ form " + form, "git -C {} commit -m x".format(form), "ask")
    for operand in ('"$HOME/wt"', '"$W"', '"{F}$X"', '"`pwd`"', "{F}*", "{F}?", "{F}[a]"):
        cmd_case(fx, "D6: forbidden character in " + operand, "git -C {} commit -m x".format(operand.replace("{F}", F)), "ask")
    for folder in fx.odd_folders:
        cmd_case(fx, "D6: real worktree folder named " + os.path.basename(folder),
                 "git -C '{}' commit -m x".format(folder), "ask")
        cmd_case(fx, "D3 control: the same folder is fine for a read", "git -C '{}' status".format(folder), "allow")
    cmd_case(fx, "D6: two -C","git -C {} -C {} commit -m x".format(fx.M, F), "ask")
    cmd_case(fx, "D6: second -C wins nothing, even when both are good", "git -C {} -C {} commit -m x".format(F, F), "ask")
    cmd_case(fx, "D6: a commit segment with no -C of its own", "git -C {} status && git commit -m x".format(F), "ask")
    repo_home = Fixtures_home(fx, "repo-home")
    git("init", "-q", "-b", "feat/h", repo_home)
    cmd_case(fx, "D6: bare ~ (HOME itself a feature repo)", "git -C ~ commit -m x", "allow", home=repo_home)
    cmd_case(fx, "D6: ~ alone as a read folder", "git -C ~ status", "allow")


def test_branch_rule(fx):
    for desc, folder in (("detached HEAD", fx.detached), ("not a repository", fx.not_repo),
                         ("folder that does not exist", os.path.join(fx.root, "nope")), ("T: tag named main", fx.T)):
        cmd_case(fx, "D7 " + desc, "git -C {} commit -m x".format(folder), "ask")
        cmd_case(fx, "D7 " + desc + " (push)", "git -C {} push origin HEAD".format(folder), "ask")
    short = subprocess.run([REAL_GIT, "-C", fx.T, "symbolic-ref", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
    check("R23 fixture: --short prints heads/main in T (so only the full name discriminates)", short == "heads/main", short)
    for index, (name, ref) in enumerate((("Main", "Main"), ("MAIN", "MAIN"), ("master", "master"), ("MASTER", "MASTER"),
                                         ("Master", "Master"), ("long-s", "ma\u017fter"), ("fullwidth", "\uff2d\uff21\uff29\uff2e"),
                                         ("long-s-up", "MA\u017fTER"))):
        folder = fx.head_named("case{}".format(index), "refs/heads/" + ref)
        cmd_case(fx, "R25 branch spelled {!r}".format(ref), "git -C {} commit -m x".format(folder), "ask")
    for index, ref in enumerate(("main-fix", "feat/main", "domain", "mainline", "master2", "release/master")):
        folder = fx.head_named("ok{}".format(index), "refs/heads/" + ref)
        cmd_case(fx, "D7 allowed name {!r}".format(ref), "git -C {} commit -m x".format(folder), "allow")
    folder = fx.head_named("nonbranch", "refs/remotes/origin/feat-q")
    cmd_case(fx, "D7 HEAD names a non-branch ref", "git -C {} commit -m x".format(folder), "ask")
    for marker in ("rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG"):
        path = fx.marker_path(fx.F, marker)
        (os.makedirs if marker.startswith("rebase") else lambda p: open(p, "w").close())(path)
        try:
            cmd_case(fx, "R11 {} present".format(marker), "git -C {} commit -m x".format(fx.F), "ask")
        finally:
            shutil.rmtree(path) if os.path.isdir(path) else os.remove(path)
        cmd_case(fx, "R11 control after removing {}".format(marker), "git -C {} commit -m x".format(fx.F), "allow")


def stub_git(root, name, body):
    folder = os.path.join(root, name)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "git")
    with open(path, "w") as handle:
        handle.write("#!/bin/sh\n" + body + "\n")
    os.chmod(path, 0o755)
    return folder + os.pathsep + os.environ.get("PATH", "")


def test_timeouts_and_missing_git(fx):
    check("the timeout constant is named and is 3",
          re.search(r"^QUIET_GIT_CALL_TIMEOUT_SECONDS = 3$", open(LIB).read(), re.M) is not None or LIB != DEFAULT_LIB)
    command = "git -C {} commit -m x".format(fx.F)
    text = request(command, fx)
    real = "exec {} \"$@\"".format(REAL_GIT)
    decide("control: a stub that delegates to real git", text, fx, "allow",
           extra_env={"PATH": stub_git(fx.root, "delegate", real)})
    for name, body in (("sleeps on every call", "exec sleep 30"),
                       ("sleeps on rev-parse only", 'case "$*" in *symbolic-ref*) {} ;; *) exec sleep 30 ;; esac'.format(real)),
                       ("sleeps on symbolic-ref only", 'case "$*" in *rev-parse*) {} ;; *) exec sleep 30 ;; esac'.format(real))):
        secs = decide("R24 git that " + name, text, fx, "ask", extra_env={"PATH": stub_git(fx.root, "slow", body)})
        check("R24 git that {}: answered within the bound ({:.1f}s)".format(name, secs), secs < SLOW_LIMIT_SECONDS)
    decide("git missing from PATH", text, fx, "ask", extra_env={"PATH": os.path.join(fx.root, "empty-bin")})
    decide("git exits non-zero", text, fx, "ask", extra_env={"PATH": stub_git(fx.root, "fail", "exit 1")})
    decide("git prints a non-branch ref", text, fx, "ask", extra_env={"PATH": stub_git(fx.root, "lie", "echo refs/tags/x")})
    decide("git prints 6 marker lines but they exist", text, fx, "ask", extra_env={"PATH": stub_git(
        fx.root, "marker", 'case "$*" in *symbolic-ref*) echo refs/heads/feat/x ;; *) for i in 1 2 3 4 5 6; do echo /; done ;; esac')})
    decide("git answers 5 marker lines for 6 markers", text, fx, "ask", extra_env={"PATH": stub_git(
        fx.root, "short", 'case "$*" in *symbolic-ref*) echo refs/heads/feat/x ;; *) for i in 1 2 3 4 5; do echo /nonexistent$i; done ;; esac')})
    read_text = request("git -C {} status".format(fx.F), fx)
    decide("a read line never calls git (a broken git still allows)", read_text, fx, "allow",
           extra_env={"PATH": stub_git(fx.root, "never", "exit 1")})


def test_log(fx):
    token = "zq9distinctive8token"
    before = len(fx.log_lines())
    command = 'git -C {} commit -m "{}"'.format(fx.F, token)
    decide("log: an allowed commit", request(command, fx), fx, "allow")
    decide("log: an allowed read", request("git -C {} status".format(fx.F), fx), fx, "allow")
    lines = fx.log_lines()[before:]
    check("log: two allows wrote two lines", len(lines) == 2, repr(lines))
    fields = lines[0].split("\t") if lines else []
    check("log: four tab-separated fields", len(fields) == 4, repr(lines))
    if len(fields) == 4:
        stamp = datetime.datetime.strptime(fields[0], "%Y-%m-%dT%H:%M:%SZ") if re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", fields[0]) else None
        check("log: ISO-8601 UTC timestamp near now", stamp is not None and abs((datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - stamp).total_seconds()) < 120, fields[0])
        check("log: session id", fields[1] == SID, fields[1])
        check("log: lands for a commit", fields[2] == "lands", fields[2])
        check("log: SHA-256 of the raw command", fields[3] == hashlib.sha256(command.encode()).hexdigest(), fields[3])
        check("log: read for a read line", lines[1].split("\t")[2] == "read", lines[1])
    check("log: no command text anywhere in it", token not in open(fx.log).read())
    for umask in (0o022, 0o000):
        fresh = Fixtures_home(fx, "umask{}".format(umask))
        rc, out, _err, _ = run_child(request("git -C {} status".format(fx.F), fx), fresh, umask=umask)
        mode = stat.S_IMODE(os.stat(os.path.join(fresh, ".claude", "hooks", "state", "git-guard-quiet.log")).st_mode)
        check("log: created 0600 under umask {:03o}".format(umask), out == "allow" and mode == 0o600, "out={!r} mode={:o}".format(out, mode))
    # R18: a log that cannot be appended makes the child ask.
    bad_text = request("git -C {} status".format(fx.F), fx)
    blocked = Fixtures_home(fx, "log-is-dir")
    os.mkdir(os.path.join(blocked, ".claude", "hooks", "state", "git-guard-quiet.log"))
    rc, out, _e, _s = run_child(bad_text, blocked)
    check("R18: log path is a directory -> ask", rc == 0 and out == "ask", repr(out))
    readonly = Fixtures_home(fx, "state-readonly")
    state = os.path.join(readonly, ".claude", "hooks", "state")
    os.chmod(state, 0o500)
    try:
        rc, out, _e, _s = run_child(bad_text, readonly)
        check("R18: unwritable state dir -> ask", rc == 0 and out == "ask", repr(out))
    finally:
        os.chmod(state, 0o700)
    rc, out, _e, _s = run_child(bad_text, "", extra_env={"HOME": None})
    check("R18: HOME unset -> ask", rc == 0 and out == "ask", repr(out))
    rc, out, _e, _s = run_child(bad_text, "relative/home")
    check("R18: HOME relative -> ask", rc == 0 and out == "ask", repr(out))
    rc, out, _e, _s = run_child(bad_text, os.path.join(fx.root, "no-such-home"))
    check("R18: HOME without a state dir -> ask", rc == 0 and out == "ask", repr(out))


def Fixtures_home(fx, name):
    home = os.path.join(fx.root, "home-" + name)
    os.makedirs(os.path.join(home, ".claude", "hooks", "state"))
    return home


def main():
    root = tempfile.mkdtemp(prefix="git-guard-quiet-unit-")
    try:
        fx = Fixtures(os.path.realpath(root))
        for suite in (test_input_parsing, test_hidden_commands_and_options, test_line_rule, test_push_shapes,
                      test_folder_rule, test_branch_rule, test_timeouts_and_missing_git, test_log):
            try:
                suite(fx)
            except Exception as exc:  # a crashing suite is red, never a silent skip
                check("{} did not crash".format(suite.__name__), False, repr(exc))
    finally:
        for path, _dirs, _files in os.walk(root):
            try:
                os.chmod(path, 0o700)
            except OSError:
                pass
        shutil.rmtree(root, ignore_errors=True)
    print("\ngit guard quiet unit: {} passed, {} failed".format(passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    _rc = main()
    if _rc == 0 and LIB == DEFAULT_LIB:
        subprocess.run([sys.executable, "-I", "hooks/lib/write-test-marker.py", MARKER_SELF],
                       cwd=MARKER_ROOT, check=True)
    sys.exit(_rc)
