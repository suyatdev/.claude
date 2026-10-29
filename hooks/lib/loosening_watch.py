"""The data hooks/loosening-guard.sh owns: which files it watches, and which lists in them carry a direction.

Kept apart from the logic so the part that needs a human's review (ADR 0052 decision 4) is one small
file. Nothing here is computed from the guards' code: the ALLOW/BLOCK tags below are HAND-ASSIGNED, and
a wrong tag fails in the PERMISSIVE direction -- a loosening that reads as a tightening is allowed
silently. Review DIRECTION_TABLE before trusting the watcher; it is the feature's trust root.

An entry-level direction exists only for the lists named here. Every other change inside a watched
file (a regex narrowed in place, a branch flipped, a call deleted, a list nobody tagged) is
CHANGED-DIRECTION-UNKNOWN and prompts -- ADR 0052 decision 2. Adding a row below makes MORE changes
silent, so it is a loosening of this hook and deserves the same review as one.
"""

SECRET, GIT, WORKTREE = "secret-command-guard", "git-guard", "worktree-guard"
GUARDS = (SECRET, GIT, WORKTREE)

# ADR 0052 decision 1: the fourteen-file watch set, one row per file, the guard(s) each one feeds.
WATCH = {
    "hooks/lib/classify-secret-command.py": (SECRET,),
    "hooks/secret-command-guard.sh": (SECRET,),
    "hooks/lib/secret_approval.py": (SECRET,),
    "hooks/git-guard.sh": (GIT,),
    "hooks/lib/git_quiet_class.py": (GIT,),
    "hooks/lib/git_guard_quiet.py": (GIT,),
    "hooks/lib/classify-git-command.py": (GIT, WORKTREE),
    "hooks/worktree-guard.sh": (WORKTREE,),
    "hooks/lib/worktree_guard_bash_arms.sh": (WORKTREE,),
    "hooks/lib/worktree_guard_liveness.sh": (WORKTREE,),
    "hooks/reference-transaction": (WORKTREE,),
    "hooks/reference-transaction.mode": (WORKTREE,),
    "hooks/lib/shell_segments.py": (SECRET, GIT, WORKTREE),
    "settings.json": (SECRET, GIT, WORKTREE),
}


def files_of(guard):
    """The watched files a guard's approval key covers, sorted."""
    return sorted(path for path, guards in WATCH.items() if guard in guards)


# What an ENTRY in a list means for the guard. ALLOW: adding an entry lets more through. BLOCK:
# adding an entry stops more.
ALLOW, BLOCK = "allow", "block"

# Python lists: {file: {module-level name: (direction, what it is)}}. The value must be a literal
# tuple/list/set; anything else (a comprehension, a call) is not recognised and is judged as code.
PY_LISTS = {
    "hooks/lib/classify-secret-command.py": {
        "DOTFILE_PATTERNS": (BLOCK, "secret paths the guard refuses to read"),
    },
    "hooks/lib/git_quiet_class.py": {
        "READ_SUBCOMMANDS": (ALLOW, "git subcommands quiet mode treats as read-only"),
    },
    "hooks/lib/git_guard_quiet.py": {
        "PROTECTED_BRANCHES": (BLOCK, "branches quiet mode will not silence a commit on"),
    },
    "hooks/lib/classify-git-command.py": {
        "FORCE_FLAGS": (BLOCK, "push flags read as a bare force"),
    },
}

# Shell `case` lists, found by an exact header line (after comment stripping and trimming), which must
# occur exactly once in the file. An ENTRY is a one-line arm `pat[|pat...]) <body> ;;` whose body is
# exactly `body` -- an arm with any other body is code, not an entry, and stays in the residue.
# {file: [(header, list name, direction, body, what it is)]}
SH_CASE_LISTS = {
    "hooks/git-guard.sh": [
        ('case "$f" in', "MAIN_COMMIT_ALLOWLIST", ALLOW, "",
         "paths a commit on main/master may touch"),
    ],
    "hooks/worktree-guard.sh": [
        ('case "$rel" in', "PATH_EXEMPTIONS", ALLOW, "exit 0",
         "paths exempt from the primary-checkout write guard"),
    ],
}

# settings.json: a hook registration whose command mentions one of these scripts is a BLOCK entry
# (removing it disarms the guard). env keys with this prefix, and these top-level switches, are
# watched as plain values: any change prompts.
GUARD_SCRIPTS = ("secret-command-guard.sh", "git-guard.sh", "worktree-guard.sh")
SETTINGS_ENV_PREFIX = "WORKTREE_"
SETTINGS_REGISTRATIONS = "REGISTRATIONS"
