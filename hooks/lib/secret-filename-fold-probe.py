"""Task 3 probe (docs/features/secret-filename-case-blindness.md) -- sources
every number the card states about folding DOTFILE_PATTERNS case-insensitive.

Two independent oracles, never used to check each other:
  guard verdict  = does a pattern match a candidate token, under a given flag set
  filesystem truth = does THIS VOLUME open a homoglyph decoy as the same file

Creates decoy files under a fresh scratch directory only (removed on exit).
Never creates, reads, or names a real secret-bearing file (~/.zshrc,
~/.terminal_aliases, .env, credentials.json, ...) -- only literal-derived
candidate spellings of those names, written under a tempfile.mkdtemp() root.

Section 1 (Table A) and section 2 (disk census) replace the round-1 probe,
which derived its test spellings from each pattern's human-readable *label*
and silently produced zero test cases for the Application Support row (an
untested row printing identically to a passing one). This version derives
candidate spellings from the pattern's own literal text via
`literal_segments()`, so a pattern with no single literal name (the
Application Support row) still gets a non-empty, printed case count.

Section 4 (flag-choice sweep) is the homoglyph population from
.local/fold-probes/final_sweep.py, the "definitive prior probe" per the card,
carried over unchanged in method: union of two homoglyph-candidate
derivations, every substitution position (not just the first), and every
non-overlapping combination of confirmed same-file substitutions (not just
singles). Three earlier rounds of this card each shipped a confident table
built on a population missing one of those three.

Usage: python3 hooks/lib/secret-filename-fold-probe.py <repo-root>
"""
import importlib.util
import itertools
import os
import re
import sys
import tempfile
import unicodedata

REPO = sys.argv[1]
HOME = os.path.expanduser("~")

spec = importlib.util.spec_from_file_location(
    "clsfy", os.path.join(REPO, "hooks", "lib", "classify-secret-command.py")
)
mod = importlib.util.module_from_spec(spec)
sys.modules["clsfy"] = mod
spec.loader.exec_module(mod)

PATTERNS = mod.DOTFILE_PATTERNS  # imported, never retyped


# ---------------------------------------------------------------------------
# literal-segment extraction -- derives candidate literal text straight from
# each pattern's regex source, not from its human label. This is the fix for
# the round-1 hole: the label for the Application Support pattern
# ("*/Application Support/*/credentials*") produced an empty variant list
# under the old label-derived generator; the pattern's own regex source
# ("Application Support/[^/]*/credentials") always contains the two literal
# words, so this derivation cannot go empty the same way.
# ---------------------------------------------------------------------------
def literal_segments(pattern):
    s = pattern
    s = re.sub(r"\(\^\|/\)", "", s)          # the shared anchor-alternation group
    s = re.sub(r"\([^)]*\)\??", "", s)        # any other group, optional or not
    s = re.sub(r"\[[^\]]*\]\*?", "", s)       # character classes (e.g. [^/]*)
    s = s.replace("\\.", ".")                 # unescape literal dots
    s = s.strip("^$")
    return [seg for seg in s.split("/") if any(c.isalpha() for c in seg)]


def case_forms(seg):
    forms = []
    for f in (seg, seg.upper(), seg.lower(), seg.capitalize(), seg.swapcase()):
        if f not in forms:
            forms.append(f)
    return forms


def sample_tokens(segs):
    """Every non-all-original combination of per-segment case forms, each
    tested both bare and after a directory component (covers the "(^|/)"
    anchor). For a 2-segment pattern (Application Support), segments are
    joined by a filler path component, matching the pattern's own [^/]*."""
    forms_lists = [case_forms(s) for s in segs]
    tokens = []
    for combo in itertools.product(*forms_lists):
        if list(combo) == segs:
            continue  # identical to the original spelling; not a case test
        base = "/foo/".join(combo)
        tokens.append(base)
        tokens.append("/some/dir/" + base)
    return tokens


# ---------------------------------------------------------------------------
# Section 1 -- Table A: which patterns flip under folding, with a per-pattern
# case count printed alongside every row so a zero-case row cannot read like
# a passing one.
# ---------------------------------------------------------------------------
print("=== Table A: per-pattern fold impact (case count printed per row) ===")
table_a_tokens_by_pattern = {}
compiled_plain_by_pattern = []
compiled_ic_by_pattern = []
for pat, label in PATTERNS:
    segs = literal_segments(pat)
    tokens = sample_tokens(segs)
    table_a_tokens_by_pattern[label] = tokens
    plain_rx = re.compile(pat)
    ic_rx = re.compile(pat, re.IGNORECASE)
    compiled_plain_by_pattern.append(plain_rx)
    compiled_ic_by_pattern.append(ic_rx)
    flips = [t for t in tokens if not plain_rx.search(t) and ic_rx.search(t)]
    flip_word = "yes" if flips else "no"
    sample = ", ".join(flips[:3])
    print(f"  {label:42s} cases={len(tokens):3d}  flips={flip_word:3s} ({len(flips)}/{len(tokens)})  e.g. {sample}")

all_table_a_tokens = sorted({t for toks in table_a_tokens_by_pattern.values() for t in toks})
print(f"\nunion of all Table A candidate tokens: {len(all_table_a_tokens)}")

# ---------------------------------------------------------------------------
# Section 1b -- production DOTFILE_RE must not silently drift from the
# self-compiled re.IGNORECASE column. Before task 5 lands, DOTFILE_RE is
# compiled with no flags (plain), so this is expected to disagree today; it
# is printed rather than asserted-fatal so the probe stays a measurement, not
# a test.
#
# The Table A tokens alone CANNOT discriminate the flag choice this card
# decided. They are pure-ASCII case variants, and re.IGNORECASE behaves
# identically to re.IGNORECASE|re.ASCII on those -- measured, 0 of 11 differ.
# A receipt that still reads True under the rejected flag is not a receipt.
# So the comparison population is widened with the same-file homoglyph tokens,
# where the two flags disagree on every one (6 of 6). Do not narrow it back.
# ---------------------------------------------------------------------------
# The receipt is deliberately NOT printed here -- see section 4b. It needs a
# population that can tell re.IGNORECASE from the rejected re.IGNORECASE|re.ASCII,
# and the Table A tokens cannot: they are pure-ASCII case variants, on which the
# two flags behave identically, so a receipt built from them reads True under
# either flag and proves nothing about the choice the decision rests on. The
# tokens that DO discriminate are the same-file homoglyph variants, and those are
# derived by the section 4 sweep rather than typed out here.

# ---------------------------------------------------------------------------
# Section 2 -- disk census: two walks, same method as the Task 1 probe
# (.local/fold-probes/fold_impact.py), re-derived rather than hardcoded.
# ---------------------------------------------------------------------------
def census_walk(roots, exclude_dirs, max_depth):
    seen = set()
    newly = {}
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            depth = dirpath[len(root):].count(os.sep)
            if max_depth is not None and depth >= max_depth:
                dirnames[:] = []
            if exclude_dirs:
                dirnames[:] = [d for d in dirnames if d not in exclude_dirs]
            for name in list(dirnames) + filenames:
                full = os.path.join(dirpath, name)
                rel = full.replace(HOME, "~")
                if rel in seen:
                    continue
                seen.add(rel)
                for plain_rx, ic_rx, (_, label) in zip(
                    compiled_plain_by_pattern, compiled_ic_by_pattern, PATTERNS
                ):
                    if not plain_rx.search(full) and ic_rx.search(full):
                        newly.setdefault(label, []).append(rel)
    return seen, newly


print("\n=== Section 2: disk census (names only, no file contents read) ===")
walk1_seen, walk1_newly = census_walk(
    [REPO, HOME], {".git", "node_modules", "Library"}, 4
)
print(f"  repo worktree + $HOME (excl .git/node_modules/Library, depth<4): {len(walk1_seen)} names scanned")
if walk1_newly:
    for label, hits in sorted(walk1_newly.items()):
        print(f"    newly matching under folding -- {label}: {len(hits)}")
        for h in sorted(hits)[:15]:
            print(f"      {h}")
else:
    print("    newly matching under folding: 0")

library_root = os.path.join(HOME, "Library")
walk2_seen, walk2_newly = census_walk([library_root], set(), None)
print(f"  ~/Library (no exclusions, full depth): {len(walk2_seen)} names scanned")
if walk2_newly:
    for label, hits in sorted(walk2_newly.items()):
        print(f"    newly matching under folding -- {label}: {len(hits)}")
        for h in sorted(hits)[:15]:
            print(f"      {h}")
else:
    print("    newly matching under folding: 0")


# ---------------------------------------------------------------------------
# Section 3 -- filesystem premise, direct test rather than assumed.
# ---------------------------------------------------------------------------
print("\n=== Section 3: filesystem case-insensitivity premise (direct test) ===")
premise_dir = tempfile.mkdtemp(prefix="fold-premise-")
premise_path = os.path.join(premise_dir, "casetest.txt")
with open(premise_path, "w") as f:
    f.write("x")
listed = os.listdir(premise_dir)
os.remove(premise_path)
os.rmdir(premise_dir)
print(f"  wrote casetest.txt, directory listing shows: {listed}")


# ---------------------------------------------------------------------------
# Section 4 -- flag-choice sweep: the homoglyph population, carried over from
# the definitive prior probe (.local/fold-probes/final_sweep.py), fixing the
# same three holes that probe fixed (union-derived candidates, every
# substitution position, every non-overlapping combination).
# ---------------------------------------------------------------------------
print("\n=== Section 4: flag-choice sweep (homoglyph population) ===")

NAMES = [
    segs[0]
    for pat, _label in PATTERNS
    for segs in [literal_segments(pat)]
    if len(segs) == 1
]
LETTERS = sorted({c for n in NAMES for c in n if c.isalpha()})

cands = {}
for cp in range(0x20, 0x10000):
    ch = chr(cp)
    if ch.isascii():
        continue
    f = "".join(
        c for c in unicodedata.normalize("NFKD", ch).casefold() if c.isascii() and c.isalpha()
    )
    if f and all(c in LETTERS for c in f) and len(f) <= 3:
        cands.setdefault(f, set()).add(ch)
    for L in LETTERS:
        if re.fullmatch(L, ch, re.IGNORECASE):
            cands.setdefault(L, set()).add(ch)


def single_subs(name):
    """(start, runlen, char) for every position, not just the first."""
    out = []
    for run, chars in cands.items():
        start = 0
        while True:
            i = name.find(run, start)
            if i < 0:
                break
            for ch in sorted(chars):
                out.append((i, len(run), ch))
            start = i + 1
    return out


def apply_subs(name, subs):
    for start, runlen, ch in sorted(subs, key=lambda s: -s[0]):
        name = name[:start] + ch + name[start + runlen:]
    return name


sweep_tmp = tempfile.mkdtemp(prefix="fold-sweep-")


def same_file(name, variant):
    real = os.path.join(sweep_tmp, name)
    with open(real, "w") as f:
        f.write("decoy\n")
    try:
        with open(os.path.join(sweep_tmp, variant)) as f:
            r = f.read().strip() == "decoy"
    except OSError:
        r = False
    for f2 in os.listdir(sweep_tmp):
        os.remove(os.path.join(sweep_tmp, f2))
    return r


compiled_plain = [re.compile(p) for p, _ in PATTERNS]
compiled_ic = [re.compile(p, re.IGNORECASE) for p, _ in PATTERNS]
compiled_ica = [re.compile(p, re.IGNORECASE | re.ASCII) for p, _ in PATTERNS]


def hit(tok, compiled, nfkd=False):
    t = unicodedata.normalize("NFKD", tok) if nfkd else tok
    return any(rx.search(t) for rx in compiled)


STRATS = [
    # "pre-fix", not "today": task 5 landed re.IGNORECASE in production, so the
    # unfolded column is now a historical baseline, not a description of the guard.
    # The DOTFILE_RE agreement line above is what reports production's real strategy.
    ("plain (pre-fix)", lambda t: hit(t, compiled_plain)),
    ("re.IGNORECASE", lambda t: hit(t, compiled_ic)),
    ("IGNORECASE|ASCII", lambda t: hit(t, compiled_ica)),
    ("NFKD + IGNORECASE", lambda t: hit(t, compiled_ic, nfkd=True)),
]

same_rows, diff_rows = [], []
per_name = {}

for name in NAMES:
    subs = single_subs(name)
    same_singles = []
    tested = 0
    for s in subs:
        v = apply_subs(name, [s])
        if v == name:
            continue
        tested += 1
        if same_file(name, v):
            same_rows.append((name, v, [s]))
            same_singles.append(s)
        else:
            diff_rows.append((name, v, [s]))
    combos = 0
    by_pos = {}
    for s in same_singles:
        by_pos.setdefault(s[0], []).append(s)
    for k in range(2, len(by_pos) + 1):
        for poss in itertools.combinations(sorted(by_pos), k):
            spans = [(p, by_pos[p][0][1]) for p in poss]
            if any(a + la > b for (a, la), (b, _) in zip(spans, spans[1:])):
                continue
            for pick in itertools.product(*[by_pos[p] for p in poss]):
                v = apply_subs(name, list(pick))
                combos += 1
                if same_file(name, v):
                    same_rows.append((name, v, list(pick)))
                else:
                    diff_rows.append((name, v, list(pick)))
    per_name[name] = (tested, combos, len(same_singles))

os.rmdir(sweep_tmp)

print("per-name coverage (an untested row cannot hide as a passing one):")
print(f"  {'name':20s} {'single subs':>12s} {'combos':>8s} {'same-file singles':>18s}")
for n, (t, c, s) in per_name.items():
    print(f"  {n:20s} {t:12d} {c:8d} {s:18d}")

print(f"\ntotal variants tested on this volume: {len(same_rows) + len(diff_rows)}")
print(f"  SAME file (guard SHOULD block): {len(same_rows)}")
print(f"  DIFFERENT file (should ALLOW):  {len(diff_rows)}\n")

# ---------------------------------------------------------------------------
# Section 4b -- production DOTFILE_RE must not silently drift from the
# self-compiled re.IGNORECASE column. Printed rather than asserted-fatal, so
# the probe stays a measurement and not a test.
#
# The population is DERIVED, never typed. It is the Table A tokens plus every
# same-file variant the sweep above found on which re.IGNORECASE and the
# rejected re.IGNORECASE|re.ASCII actually disagree. A hand-typed list was used
# for one commit and removed: this file deletes a hand-sample elsewhere on the
# grounds that only a derived population is reproducible, and the same rule has
# to apply here. If the sweep ever finds no discriminating variant, the count
# below prints 0 and the receipt is announcing that it has gone blind.
# ---------------------------------------------------------------------------
discriminating = [
    v for _, v, _ in same_rows
    if hit(v, compiled_ic) != hit(v, compiled_ica)
]
# Source the claim that Table A alone cannot discriminate, rather than asserting
# it in a comment. If this ever prints non-zero, the paragraph in the card that
# explains why section 4b exists has gone stale and must be re-derived.
table_a_disc = [
    t for t in all_table_a_tokens
    if hit(t, compiled_ic) != hit(t, compiled_ica)
]
print(
    f"Table A tokens that discriminate re.IGNORECASE from re.IGNORECASE|re.ASCII: "
    f"{len(table_a_disc)} of {len(all_table_a_tokens)} "
    f"(this is why the derived same-file tokens below are added)"
)
agreement_tokens = list(all_table_a_tokens) + discriminating
mismatches = [
    tok for tok in agreement_tokens
    if any(rx.search(tok) for rx, _ in mod.DOTFILE_RE)
    != any(rx.search(tok) for rx in compiled_ic_by_pattern)
]
agrees = len(mismatches) == 0
print(
    f"production DOTFILE_RE agrees with self-compiled re.IGNORECASE column: "
    f"{agrees} ({len(mismatches)} of {len(agreement_tokens)} tokens differ, "
    f"of which {len(discriminating)} derived tokens discriminate re.IGNORECASE "
    f"from re.IGNORECASE|re.ASCII)\n"
)

print(f"{'strategy':20s} {'bypasses':>14s} {'false refusals':>18s}")
print("-" * 56)
for nm, fn in STRATS:
    byp = [v for _, v, _ in same_rows if not fn(v)]
    ovb = [v for _, v, _ in diff_rows if fn(v)]
    print(f"{nm:20s} {len(byp):7d}/{len(same_rows):<6d} {len(ovb):11d}/{len(diff_rows):<6d}")

print("\nEvery same-file variant, and which strategy catches it:")
print(f"  {'protected name':20s} {'variant':28s} {'codepoints':22s} plain IC ICA NFKD")
for nm, v, ss in sorted(same_rows):
    cps = " ".join(f"U+{ord(s[2]):04X}" for s in ss)
    marks = "  ".join(("Y" if fn(v) else ".") for _, fn in STRATS)
    print(f"  {nm:20s} {v:28s} {cps:22s}  {marks}")

print("\nEvery false refusal introduced by bare re.IGNORECASE:")
n = 0
for nm, v, ss in diff_rows:
    if hit(v, compiled_ic) and not hit(v, compiled_plain):
        n += 1
        cps = " ".join(f"U+{ord(s[2]):04X}" for s in ss)
        print(f"  {nm:20s} {v:28s} {cps}")
print(f"  total: {n}")


# ---------------------------------------------------------------------------
# Section 5 -- the exemption delta. Folding the patterns WIDENS what the guard
# refuses; folding the committed-template exemption NARROWS it, and the card is
# required to name both. This sweeps every case variant of the dotenv family and
# reports the delta by direction.
#
# Pre-fix behaviour is reconstructed from the two mechanisms rather than read
# out of git, so the probe stays self-contained and runnable at any checkout:
# patterns compiled with no flag, plus a case-sensitive endswith exemption.
# Post-fix behaviour comes from the live classifier. The card states these
# counts and nothing else derives them -- an earlier draft said "exactly two",
# which was a hand-picked list of 11 spellings written up as a complete delta.
# ---------------------------------------------------------------------------
print("\n=== Section 5: exemption delta over the dotenv family ===")

DOTENV_LABEL = ".env / .env.*"
EXEMPT_SUFFIXES = (".example", ".template", ".sample")
FAMILY = [".env"] + [".env" + _s for _s in EXEMPT_SUFFIXES]


def all_case_variants(name):
    slots = [(i, c) for i, c in enumerate(name) if c.isalpha()]
    out = set()
    for bits in itertools.product((0, 1), repeat=len(slots)):
        chars = list(name)
        for (i, c), b in zip(slots, bits):
            chars[i] = c.upper() if b else c.lower()
        out.add("".join(chars))
    return out


def pre_fix_blocks(tok):
    for rx, (_pat, label) in zip(compiled_plain, PATTERNS):
        if rx.search(tok):
            if label == DOTENV_LABEL and tok.endswith(EXEMPT_SUFFIXES):
                return False
            return True
    return False


family_pop = set()
for _name in FAMILY:
    family_pop |= all_case_variants(_name)

to_allow, to_block, unchanged = [], [], 0
for tok in sorted(family_pop):
    before = pre_fix_blocks(tok)
    after = mod.matches_dotfile(tok) is not None
    if before and not after:
        to_allow.append(tok)
    elif after and not before:
        to_block.append(tok)
    else:
        unchanged += 1

print(f"  population: every case variant of {', '.join(FAMILY)}")
print(f"  total basenames:                  {len(family_pop)}")
print(f"  block -> allow (newly permitted): {len(to_allow)}")
print(f"  allow -> block (the fix):         {len(to_block)}")
print(f"  unchanged:                        {unchanged}")
print("  every newly-permitted name is a template-family name: "
      f"{all(t.lower() != '.env' for t in to_allow)}")
print(f"  newly-refused names: {sorted(to_block)}")
