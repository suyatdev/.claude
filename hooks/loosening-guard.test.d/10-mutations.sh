# shellcheck shell=bash
# 10-mutations.sh — sourced by ../loosening-guard.test.sh — not runnable on its own.
# The mutation table: writes $MUTPY (a python3 helper that applies one mutation to real repo bytes, or lists ids).
# ---------------------------------------------------------------------------------------------
# Mutations on REAL bytes (needles from hooks/secret-approval-state-key.probe.sh, plus more).
# Each must occur exactly once; a miss is a HARNESS failure, never a hook failure.
# ---------------------------------------------------------------------------------------------
cat > "$MUTPY" <<'PYEOF'
import sys
SC = "hooks/lib/classify-secret-command.py"
GG = "hooks/git-guard.sh"
WG = "hooks/worktree-guard.sh"
Z = '    (r"(^|/)\\.zprofile$", "~/.zprofile"),\n'
E = '    (r"(^|/)\\.zshenv$", "~/.zshenv"),\n'
CJ = "      coding-memory/compliance-judge/verdicts.jsonl) ;;\n"
M = {
 "sec_rm_zprofile": (SC, Z, ""),
 "sec_rm_zshenv": (SC, E, ""),
 "sec_add_npmrc": (SC, E, E + '    (r"(^|/)\\.npmrc$", "~/.npmrc"),\n'),
 "sec_anchor": (SC, '(r"(^|/)credentials\\.json$"', '(r"(^|/)credentials\\.json"'),
 "sec_fold": (SC, "FOLD_FLAGS = re.IGNORECASE ", "FOLD_FLAGS = 0 "),
 "sec_exit": (SC, "fails OPEN on any exit other than 0/2/3.\n        sys.exit(1)",
              "fails OPEN on any exit other than 0/2/3.\n        sys.exit(0)"),
 "secsh_exit": ("hooks/secret-command-guard.sh", "\nexit 2\n", "\nexit 0\n"),
 "sec_hatch": ("hooks/lib/secret_approval.py", 'r"^[A-Za-z0-9._,:/-]+$"', 'r"^.+$"'),
 "git_add_ledger": (GG, CJ, CJ + "      coding-memory/third-judge/verdicts.jsonl) ;;\n"),
 "git_rm_ledger": (GG, "      coding-memory/observability-judge/verdicts.jsonl) ;;\n", ""),
 "git_exit": (GG, '"$prints_and_exits" >&2\n    exit 2', '"$prints_and_exits" >&2\n    exit 0'),
 "gq_add_stash": ("hooks/lib/git_quiet_class.py", '"for-each-ref",\n)', '"for-each-ref", "stash",\n)'),
 "gq_protected": ("hooks/lib/git_guard_quiet.py", 'PROTECTED_BRANCHES = ("main", "master")',
                  'PROTECTED_BRANCHES = ("main",)'),
 "cgc_force": ("hooks/lib/classify-git-command.py", 'FORCE_FLAGS = ("--force", "-f")',
               'FORCE_FLAGS = ("--force",)'),
 "wt_add_exempt": (WG, "  rules/*|skills/*) exit 0 ;;\n", "  rules/*|skills/*) exit 0 ;;\n  hooks/*) exit 0 ;;\n"),
 "wt_rm_exempt": (WG, "  rules/*|skills/*) exit 0 ;;\n", ""),
 "wt_no_home": (WG, "being usable at all.\nrequire_home\n", "being usable at all.\n"),
 "wta_refuse": ("hooks/lib/worktree_guard_bash_arms.sh", '  refuse "$1" "$2" "$command_line"\n', "  exit 0\n"),
 "wtl_liveness": ("hooks/lib/worktree_guard_liveness.sh", "    return 0\n  fi\n  return 1\n}",
                  "    return 0\n  fi\n  return 0\n}"),
 "rt_exit": ("hooks/reference-transaction", '"$3" 1>&2\n  exit 1\n}', '"$3" 1>&2\n  exit 0\n}'),
 "rtm_off": ("hooks/reference-transaction.mode", "\n\nlog\n", "\n\noff\n"),
 "seg_paren": ("hooks/lib/shell_segments.py", '")" in tok:\n        return False\n    return "<"',
               '")" in tok:\n        return True\n    return "<"'),
 "set_retarget": ("settings.json", "hooks/secret-command-guard.sh", "hooks/secret-command-guard.sh.disabled"),
 "cosmetic": (SC, "# (regex, human label). Anchored on the basename",
              "# (regex, human label). Anchored on the basename [reworded]"),
 "reorder": (SC, Z + E, E + Z),
}
APPEND = {"brk_py": (SC, "\ndef (:\n"), "brk_py2": (SC, "\nclass :\n"),
          "brk_sh": (GG, "\nif then fi (\n"), "brk_json": ("settings.json", "\n{{\n")}

def apply_one(repo, mid):
    if mid in APPEND:
        path, text = APPEND[mid]
        with open(repo + "/" + path, "ab") as fh:
            fh.write(text.encode("utf-8"))
        return path
    path, old, new = M[mid]
    with open(repo + "/" + path, "rb") as fh:
        body = fh.read().decode("utf-8")
    n = body.count(old)
    if n != 1:
        sys.stderr.write("mutation %s: needle occurs %d times in %s, expected 1\n" % (mid, n, path))
        sys.exit(9)
    with open(repo + "/" + path, "wb") as fh:
        fh.write(body.replace(old, new).encode("utf-8"))
    return path

if sys.argv[1] == "list":
    print("\n".join(sorted(list(M) + list(APPEND))))
else:
    print(apply_one(sys.argv[3], sys.argv[2]))
PYEOF
