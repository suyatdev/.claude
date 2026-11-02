"""Do the nine needles of one secret share 20-grams? Deterministic (Random(23)).

Motivates the `gram -> list of (needle, label)` index: a plain dict keyed on gram would
silently drop owners. Run: python3 docs/features/evidence/output-secret-redaction/grams.py
"""
import base64, math, random, urllib.parse
from collections import Counter, defaultdict

W = 20
TRIALS = 300


def needles_for(v: bytes):
    """The nine needles defined in the card's Matching mechanics table."""
    out = [v.decode("latin-1")]
    for alphabet in ("std", "url"):
        for r in (0, 1, 2):
            enc = (base64.b64encode if alphabet == "std" else base64.urlsafe_b64encode)(
                bytes(r) + v).decode().rstrip("=")
            lead = math.ceil(8 * r / 6)
            full = (8 * (r + len(v)) - 6 * lead) // 6
            out.append(enc[lead:lead + full])
    out.append(base64.b64encode(v).decode().rstrip("="))
    out.append(urllib.parse.quote(v, safe=""))
    return [n for n in out if len(n) >= W]


rng = random.Random(23)
shared_any = 0
shared_gram_counts = []
example = None

for t in range(TRIALS):
    v = bytes(rng.randrange(256) for _ in range(rng.randrange(24, 49)))
    nds = needles_for(v)
    owners = defaultdict(set)
    for i, nd in enumerate(nds):
        for j in range(len(nd) - W + 1):
            owners[nd[j:j + W]].add(i)
    multi = [g for g, o in owners.items() if len(o) > 1]
    if multi:
        shared_any += 1
    shared_gram_counts.append((len(multi), len(owners)))
    if example is None and multi:
        example = (len(multi), len(owners), len(nds))

print(f"trials: {TRIALS}   window: {W}   needles built per value: "
      f"{Counter(len(needles_for(bytes(rng.randrange(256) for _ in range(32)))) for _ in range(20)).most_common()}")
print(f"values with >=1 gram owned by 2+ of their OWN needles: {shared_any}/{TRIALS}")
tot_multi = sum(m for m, _ in shared_gram_counts)
tot_all = sum(a for _, a in shared_gram_counts)
print(f"shared grams / total grams, summed: {tot_multi:,} / {tot_all:,} "
      f"({100.0 * tot_multi / tot_all:.1f}%)")
print(f"first example: {example[0]} shared of {example[1]} grams, across {example[2]} needles")
