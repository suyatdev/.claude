import re, collections

LOG = "/Users/marksuyat/.claude/hooks/state/reference-transaction.log"
KNOWN = {"repo", ".git", "rebasing", "detached"}
root_re = re.compile(r"^(?P<root>.*?/tmp\.[A-Za-z0-9]+)/(?P<rest>.*)$")

groups = collections.Counter()
roots = collections.defaultdict(set)
stamps = collections.defaultdict(list)

for line in open(LOG, errors="replace"):
    p = line.rstrip("\n").split("\t")
    if len(p) < 6 or not p[4].startswith("WOULD-DENY"):
        continue
    if "var/folders" not in p[5]:
        continue
    m = root_re.match(p[5])
    if not m:
        groups["NO tmp.XXXX ROOT"] += 1
        continue
    first = m.group("rest").split("/")[0]
    key = first if (first in KNOWN or first.startswith("repo.")) else f"UNATTRIBUTED: {first}"
    groups[key] += 1
    roots[key].add(m.group("root"))
    stamps[key].append(p[0])

print(f"{'group':28s} {'lines':>6s} {'roots':>6s}  first .. last")
for k in sorted(groups, key=lambda x: (not x.startswith("UNATTRIBUTED"), x)):
    s = stamps[k]
    span = f"{min(s)[:10]} .. {max(s)[:10]}" if s else ""
    print(f"{k:28s} {groups[k]:6d} {len(roots[k]):6d}  {span}")

tot = sum(groups.values())
un = sum(v for k, v in groups.items() if k.startswith("UNATTRIBUTED") or k == "NO tmp.XXXX ROOT")
print()
print("total var/folders WOULD-DENY :", tot)
print("of which UNATTRIBUTED        :", un)
