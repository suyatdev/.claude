"""Read a watched file's state -- (git mode, blob id, bytes) -- from origin/main, the index, or the work tree.

The git MODE is part of the state, not an afterthought: a 100755 -> 100644 flip leaves the bytes
identical, and a 100644 hook cannot start, so a content-only comparison cannot see a hook being disarmed
(ADR 0052 decision 3; the suite's R4b and MF1 pin it).

Every git call sets GIT_OPTIONAL_LOCKS=0 so that looking never writes: a declined prompt must leave HEAD,
the index and the tree exactly as they were (spec section 6.2, third scenario).
"""
import os
import stat
import subprocess

GIT_TIMEOUT_SECONDS = 30
MODE_EXEC, MODE_FILE, MODE_LINK = "100755", "100644", "120000"


class GitError(Exception):
    pass


class Git:
    def __init__(self, cwd):
        self.cwd = cwd
        self.env = dict(os.environ, GIT_OPTIONAL_LOCKS="0")

    def run(self, *args, check=True):
        """CompletedProcess with bytes output. A non-zero exit raises GitError unless check=False."""
        try:
            done = subprocess.run(("git",) + args, cwd=self.cwd, env=self.env, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, timeout=GIT_TIMEOUT_SECONDS)
        except FileNotFoundError:
            raise GitError("git is not on PATH")
        except (OSError, subprocess.SubprocessError) as exc:
            raise GitError("git %s could not run: %s" % (" ".join(args[:2]), exc))
        if check and done.returncode != 0:
            err = done.stderr.decode("utf-8", "replace").strip().splitlines()
            raise GitError("git %s failed (exit %d)%s" % (" ".join(args[:2]), done.returncode,
                                                         ": " + err[0][:160] if err else ""))
        return done

    def ok(self, *args):
        return self.run(*args, check=False).returncode == 0

    def text(self, *args):
        return self.run(*args).stdout.decode("utf-8", "replace").strip()

    def paths(self, *args):
        """NUL-separated path output as a list of str."""
        out = self.run(*args).stdout.decode("utf-8", "surrogateescape")
        return [p for p in out.split("\0") if p]


class Snapshot:
    """One side of the comparison. kind: 'base' (a ref), 'index', or 'worktree'."""

    def __init__(self, git, kind, root, ref=None):
        self.git, self.kind, self.root, self.ref = git, kind, root, ref
        self._states, self._data = {}, {}

    def state(self, path):
        """(mode, blob id) or None when the path does not exist on this side."""
        if path not in self._states:
            self._states[path] = getattr(self, "_" + self.kind)(path)
        return self._states[path]

    def _base(self, path):
        out = self.git.run("ls-tree", "-z", self.ref, "--", path).stdout.decode("utf-8", "replace")
        if not out.strip("\0"):
            return None
        meta = out.split("\t", 1)[0].split()
        return meta[0], meta[2]

    def _index(self, path):
        out = self.git.run("ls-files", "-s", "-z", "--", path).stdout.decode("utf-8", "replace")
        if not out.strip("\0"):
            return None
        meta = out.split("\t", 1)[0].split()
        if meta[2] != "0":
            raise GitError("%s is unmerged in the index" % path)
        return meta[0], meta[1]

    def _worktree(self, path):
        full = os.path.join(self.root, path)
        try:
            mode = os.lstat(full).st_mode
        except FileNotFoundError:
            return None
        except OSError as exc:
            raise GitError("cannot stat %s: %s" % (path, exc))
        if stat.S_ISLNK(mode):
            label = MODE_LINK
        elif not stat.S_ISREG(mode):
            raise GitError("%s is not a regular file" % path)
        else:
            label = MODE_EXEC if mode & 0o111 else MODE_FILE
        return label, self.git.text("hash-object", "--", path)

    def data(self, path):
        """The bytes of a path that state() found. Raises GitError when it cannot be read."""
        if path not in self._data:
            self._data[path] = self._read(path)
        return self._data[path]

    def _read(self, path):
        st = self.state(path)
        if st is None:
            raise GitError("%s does not exist on this side" % path)
        if self.kind == "worktree":
            try:
                with open(os.path.join(self.root, path), "rb") as fh:
                    return fh.read()
            except OSError as exc:
                raise GitError("cannot read %s: %s" % (path, exc))
        return self.git.run("cat-file", "blob", st[1]).stdout
