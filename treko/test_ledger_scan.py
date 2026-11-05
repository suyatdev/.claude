"""C12 (docs/features/treko-ledger.spec.md section 11): the config-key table in ADR 0056 covers
git's documented list.

What the Ledger scan does to a scanned repository depends on which of git's config keys can make
git run a program. ADR 0056 section 12 records one pass over one documented list at the pinned git.
This module re-derives that list from the git installed on this machine and compares it with the
ADR's table, both ways, so a new git, a key missing from the table, or a row that claims more than
its evidence fails the suite instead of passing unnoticed.

The derivation (spec section 2, "Task 1's config-key check"):
  * the keys `git help --config` prints that have an entry of their own in git-config(1) and whose
    entry text matches one of fifteen words at the start of a word;
  * plus the three driver keys only gitattributes(5) documents.
Keys printed without an entry of their own (read only in a group entry) are not candidates.

git runs with a minimal environment and with global and system config cut off, so the derivation
does not depend on the machine's own settings.

Standard library only; run through the pinned command in spec section 15.
"""
import os
import re
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PINNED_GIT = "git version 2.50.1 (Apple Git-155)"

# Spec section 2, "Candidates, mechanically": case-insensitive, at the start of a word.
WORDS = ("program", "command", "executable", "script", "helper", "hook", "editor",
         "pager", "shell", "tool", "driver", "invok", "spawn", "execut", "run")

# Keys that section 2's probes measured naming a program (ADR 0056 section 10, probes 1-32).
PROBE_MEASURED_KEYS = (
    "core.fsmonitor", "core.hooksPath", "gpg.program", "remote.<name>.uploadpack",
    "diff.external", "diff.<driver>.textconv", "filter.<driver>.clean", "filter.<driver>.smudge",
)

# What section 2 measured on the pinned git, 2026-11-04.
EXPECTED_LISTED = 954
EXPECTED_WITH_OWN_ENTRY = 699
EXPECTED_SELECTED = 262
EXPECTED_DRIVER_KEYS = (
    "diff.<driver>.algorithm", "filter.<driver>.process", "filter.<driver>.required",
)

VERDICTS = ("does not name a program", "unreachable", "does not fire", "fires", "not measured")
TABLE_HEADER = ("Key", "Verdict", "Evidence: the quoted sentence, the probe, or the measurement",
                "Setting or decision")

# "decision D20", "the user's decision", "his decision".
DECISION_RE = re.compile(r"\bdecision D\d+\b|\b(?:user's|his) decision\b", re.IGNORECASE)
# A protective setting is a variable or a config key, not a value such as `false` or `/dev/null`.
SETTING_TOKEN_RE = re.compile(r"^(?:GIT_[A-Z_]+[A-Z0-9]|[a-z]+\.[A-Za-z]+)$")

GIT_ENV_OVERRIDES = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "LC_ALL": "C"}


def git_env():
    """The minimal environment every git call here runs under: PATH, plus the cut-offs."""
    env = {"PATH": os.environ["PATH"]}
    env.update(GIT_ENV_OVERRIDES)
    return env


def run_git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True,
                          env=git_env()).stdout


def man_page(section, name):
    return Path(run_git("--man-path").strip()) / ("man%s" % section) / ("%s.%s" % (name, section))


def unroff(line):
    line = line.replace("\\&", "").replace("\\-", "-").replace("\\(aq", "'")
    line = re.sub(r"\\f[BIRP]", "", line)
    return line.replace("\\e", "\\")


def parse_config_man(path):
    """Map each key with an entry of its own in git-config(1) to the entry's text."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith('.SH "CONFIGURATION FILE"'))
    end = next(i for i, l in enumerate(lines) if l.startswith('.SH "BUGS"'))
    body = lines[start:end]
    entries = {}
    i = 0
    while i < len(body):
        if body[i] != ".PP":
            i += 1
            continue
        names = []
        j = i + 1
        while j < len(body) and not body[j].startswith("."):
            names.append(unroff(body[j]).strip().rstrip(","))
            j += 1
        if j >= len(body) or body[j] != ".RS 4" or not names:
            i += 1
            continue
        depth, k, text = 1, j + 1, []
        while k < len(body) and depth:
            line = body[k]
            if line.startswith(".RS"):
                depth += 1
            elif line.startswith(".RE"):
                depth -= 1
            elif not line.startswith("."):
                text.append(unroff(line))
            k += 1
        for name in names:
            for part in name.split(","):
                if part.strip():
                    entries.setdefault(part.strip(), " ".join(text))
        i = k
    return entries


def listed_keys():
    return [l.strip() for l in run_git("help", "--config").splitlines()
            if l.strip() and "for more information" not in l]


def attribute_driver_keys(listed):
    """Driver keys gitattributes(5) documents that `git help --config` does not print."""
    text = man_page(5, "gitattributes").read_text(encoding="utf-8", errors="replace")
    text = re.sub(r"\\f[BIRP]", "", text.replace("\\&", "").replace("\\-", "-"))
    found = set(re.findall(r"\b((?:filter|diff|merge)\.[A-Za-z<>_-]+\.[A-Za-z]+)\b", text))
    normal = {"%s.<driver>.%s" % (k.split(".")[0], k.split(".")[2]) for k in found}
    return sorted(k for k in normal if k not in set(listed))


def select_candidates(entries, listed, words):
    """Listed keys with an entry of their own whose text has one of `words` starting a word."""
    pattern = re.compile(r"\b(" + "|".join(words) + ")", re.IGNORECASE)
    return {k for k in listed if k in entries and pattern.search(entries[k])}


def derive(words=WORDS):
    """Return (listed, with_own_entry, selected, driver_keys, candidate_set)."""
    listed = listed_keys()
    entries = parse_config_man(man_page(1, "git-config"))
    with_entry = [k for k in listed if k in entries]
    selected = select_candidates(entries, listed, words)
    drivers = attribute_driver_keys(listed)
    return listed, with_entry, selected, drivers, selected | set(drivers)


def split_row(line):
    cells = re.split(r"(?<!\\)\|", line.strip())
    return [c.strip() for c in cells[1:-1]]


def plain(cell):
    """A verdict cell without its backticks or bold markers."""
    return cell.replace("`", "").replace("*", "").strip()


def key_of(cell):
    """A key cell without its backticks; `*` is part of keys such as `alias.*`."""
    return cell.replace("`", "").strip()


def adr_path():
    matches = sorted((REPO_ROOT / "docs" / "decisions").glob("0056-*.md"))
    assert len(matches) == 1, "expected exactly one docs/decisions/0056-*.md, found %r" % matches
    return matches[0]


def adr_text():
    return adr_path().read_text(encoding="utf-8")


def read_table(text, heading, prefix):
    """The header cells and body rows of the first table after `heading` that starts `prefix`."""
    at = text.index(heading)
    lines = text[at:].splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith(prefix))
    header = split_row(lines[start])
    rows = []
    for line in lines[start + 2:]:
        if not line.startswith("|"):
            break
        rows.append(split_row(line))
    return header, rows


def config_key_table(text):
    header, rows = read_table(text, "#### Config-key table", "| Key")
    return header, [dict(zip(("key", "verdict", "evidence", "setting"), r)) for r in rows]


def protective_settings(text):
    """Variables and config keys the ADR's section 9 table says stop something."""
    _, rows = read_table(text, "### 9. Git in scanned repositories", "| Variable")
    names = set()
    for row in rows:
        if len(row) < 3 or not row[2].strip():
            continue
        for cell in row[:2]:
            names.update(t for t in re.findall(r"`([^`]+)`", cell) if SETTING_TOKEN_RE.match(t))
    return names


def verdict_vocabulary(text):
    at = text.index("**Verdict vocabulary**")
    paragraph = text[at:].split("\n\n", 1)[0]
    return set(re.findall(r"`([^`]+)`", paragraph))


def compare_keys(derived, table_keys):
    """(derived keys the table lacks, table keys that are not derived)."""
    return sorted(set(derived) - set(table_keys)), sorted(set(table_keys) - set(derived))


def row_problems(row, settings):
    """Every way one table row breaks C12's rules; an empty list means the row is sound."""
    key, verdict = key_of(row["key"]), plain(row["verdict"])
    setting = row["setting"]
    problems = []
    if verdict not in VERDICTS:
        problems.append("%s: verdict %r is not one of %r" % (key, verdict, VERDICTS))
    elif verdict == "fires":
        named = {t for t in re.findall(r"`([^`]+)`", setting) if t in settings}
        if not named and not DECISION_RE.search(setting):
            problems.append("%s: a fires row names no section 9 setting and no user decision: %r"
                            % (key, setting))
    elif verdict == "not measured" and not DECISION_RE.search(setting):
        problems.append("%s: a not-measured row does not name the user's decision: %r"
                        % (key, setting))
    return problems


def synthetic_table(keys):
    return [{"key": "`%s`" % k, "verdict": "does not fire", "evidence": "x", "setting": ""}
            for k in sorted(keys)]


class DerivationTest(unittest.TestCase):
    """The pin and the derivation itself; none of these reads the ADR."""

    @classmethod
    def setUpClass(cls):
        cls.listed, cls.with_entry, cls.selected, cls.drivers, cls.candidates = derive()

    def test_git_is_the_pinned_version(self):
        self.assertEqual(run_git("--version").strip(), PINNED_GIT,
                         "the config-key table was measured at %r (spec section 15); a different "
                         "git means ADR 0056 section 12 must be run again" % PINNED_GIT)

    def test_derivation_matches_what_section_2_measured(self):
        self.assertEqual(
            (len(self.listed), len(self.with_entry), len(self.selected), tuple(self.drivers)),
            (EXPECTED_LISTED, EXPECTED_WITH_OWN_ENTRY, EXPECTED_SELECTED, EXPECTED_DRIVER_KEYS))
        self.assertEqual(len(self.candidates), EXPECTED_SELECTED + len(EXPECTED_DRIVER_KEYS))

    def test_every_probe_measured_key_is_a_candidate(self):
        self.assertEqual([k for k in PROBE_MEASURED_KEYS if k not in self.candidates], [])

    def test_keys_without_an_entry_of_their_own_are_not_candidates(self):
        without_entry = set(self.listed) - set(self.with_entry)
        self.assertEqual(len(without_entry), EXPECTED_LISTED - EXPECTED_WITH_OWN_ENTRY)
        self.assertFalse(without_entry & self.candidates)


class TableShapeTest(unittest.TestCase):
    """The ADR's table is where C12 reads, so its shape is pinned apart from its content."""

    def test_the_table_header_and_the_vocabulary_are_intact(self):
        text = adr_text()
        header, _ = config_key_table(text)
        self.assertEqual(tuple(header), TABLE_HEADER)
        self.assertEqual(verdict_vocabulary(text), set(VERDICTS))

    def test_the_protective_settings_are_readable_from_section_9(self):
        names = protective_settings(adr_text())
        self.assertTrue({"core.fsmonitor", "core.hooksPath", "log.showSignature",
                         "GIT_OPTIONAL_LOCKS", "GIT_NO_LAZY_FETCH"} <= names, sorted(names))
        self.assertNotIn("GIT_CONFIG_COUNT", names)


class TableCoverageTest(unittest.TestCase):
    """C12 against the ADR as written. Red while the table is empty."""

    @classmethod
    def setUpClass(cls):
        cls.derived = derive()[4]
        cls.text = adr_text()
        cls.rows = config_key_table(cls.text)[1]
        cls.keys = [key_of(r["key"]) for r in cls.rows]

    def test_every_derived_key_has_a_row(self):
        missing, _ = compare_keys(self.derived, self.keys)
        self.assertEqual(missing, [], "%d of %d derived keys have no row in the ADR table; first "
                         "ten: %r" % (len(missing), len(self.derived), missing[:10]))

    def test_every_row_is_a_derived_key(self):
        self.assertTrue(self.rows, "the ADR table has no rows, so nothing was checked")
        _, extra = compare_keys(self.derived, self.keys)
        self.assertEqual(extra, [], "rows that are not in the derived set: %r" % extra)
        self.assertEqual(len(self.keys), len(set(self.keys)), "a key appears in two rows")

    def test_every_probe_measured_key_has_a_row(self):
        absent = [k for k in PROBE_MEASURED_KEYS if k not in self.keys]
        self.assertEqual(absent, [], "keys section 2's probes measured, absent from the table")

    def test_every_verdict_is_in_the_vocabulary(self):
        self.assertTrue(self.rows, "the ADR table has no rows, so nothing was checked")
        bad = [plain(r["verdict"]) for r in self.rows if plain(r["verdict"]) not in VERDICTS]
        self.assertEqual(bad, [])

    def test_fires_and_not_measured_rows_name_their_authority(self):
        self.assertTrue(self.rows, "the ADR table has no rows, so nothing was checked")
        settings = protective_settings(self.text)
        problems = [p for r in self.rows for p in row_problems(r, settings)]
        self.assertEqual(problems, [])


class FalsifierTest(unittest.TestCase):
    """Spec section 11's four falsifiers. Each builds the broken input in memory and shows that
    the check C12 uses rejects it, beside a control that it accepts, so a check that cannot
    fail cannot pass here. They hold whatever the ADR table holds."""

    @classmethod
    def setUpClass(cls):
        cls.listed, cls.with_entry, cls.selected, cls.drivers, cls.derived = derive()
        cls.entries = parse_config_man(man_page(1, "git-config"))
        cls.settings = protective_settings(adr_text())

    def test_a_table_with_one_row_removed_fails(self):
        complete = [key_of(r["key"]) for r in synthetic_table(self.derived)]
        self.assertEqual(compare_keys(self.derived, complete), ([], []))
        victim = sorted(self.derived)[0]
        missing, extra = compare_keys(self.derived, [k for k in complete if k != victim])
        self.assertEqual((missing, extra), ([victim], []))

    def test_a_derived_list_with_one_key_added_fails(self):
        complete = [key_of(r["key"]) for r in synthetic_table(self.derived)]
        missing, extra = compare_keys(set(self.derived) | {"core.invented"}, complete)
        self.assertEqual((missing, extra), (["core.invented"], []))

    def test_a_word_list_without_command_loses_the_filter_keys(self):
        narrow = tuple(w for w in WORDS if w != "command")
        lost = {"filter.<driver>.clean", "filter.<driver>.smudge"}
        control = select_candidates(self.entries, self.listed, WORDS)
        self.assertTrue(lost <= control)
        narrowed = select_candidates(self.entries, self.listed, narrow)
        self.assertEqual({k for k in PROBE_MEASURED_KEYS if k not in narrowed}, lost)
        self.assertNotEqual(len(narrowed), EXPECTED_SELECTED)

    def test_a_fires_row_that_names_no_setting_fails(self):
        def row(setting):
            return {"key": "`core.fsmonitor`", "verdict": "fires", "evidence": "x",
                    "setting": setting}
        self.assertEqual(row_problems(row("`core.fsmonitor` (section 9)"), self.settings), [])
        self.assertEqual(row_problems(row("accepted, decision D20"), self.settings), [])
        self.assertEqual(len(row_problems(row(""), self.settings)), 1)
        self.assertEqual(len(row_problems(row("`false`"), self.settings)), 1)
        self.assertEqual(len(row_problems(row("`GIT_CONFIG_COUNT`"), self.settings)), 1)

    def test_a_not_measured_row_that_names_no_decision_fails(self):
        def row(setting):
            return {"key": "`x.y`", "verdict": "not measured", "evidence": "x",
                    "setting": setting}
        self.assertEqual(row_problems(row("the user's decision, 2026-11-06"), self.settings), [])
        self.assertEqual(len(row_problems(row("core.fsmonitor"), self.settings)), 1)

    def test_a_verdict_outside_the_vocabulary_fails(self):
        bad = {"key": "`x.y`", "verdict": "checked", "evidence": "x", "setting": ""}
        self.assertEqual(len(row_problems(bad, self.settings)), 1)


if __name__ == "__main__":
    unittest.main()
