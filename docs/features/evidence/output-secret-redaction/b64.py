"""Deterministic check of the base64 offset-trim rule.

Every byte string is drawn from random.Random(7), NOT os.urandom, so the counts below
reproduce exactly on re-run. Run: python3 cache/spike/b64.py
"""
import base64, math, random

TRIALS_PER_OFFSET = 350
OFFSETS = (0, 1, 2)


def rand_bytes(rng, n):
    return bytes(rng.randrange(256) for _ in range(n))


def card_rule_v1(v, off):
    """The first attempt: 'drop the first and last encoded character'."""
    enc = base64.b64encode(bytes(off) + v).decode()
    return enc[1:-1] if off else enc


def trim_rule(v, off):
    """lead = ceil(8r/6); full = (8(r+len(v)) - 6*lead) // 6."""
    enc = base64.b64encode(bytes(off) + v).decode().rstrip("=")
    lead = math.ceil(8 * off / 6)
    full = (8 * (off + len(v)) - 6 * lead) // 6
    return enc[lead:lead + full]


results = {}
for name, rule in (("first attempt", card_rule_v1), ("trim rule", trim_rule)):
    for off in OFFSETS:
        rng = random.Random(7)          # reset per cell: each cell sees identical inputs
        hits = 0
        for _ in range(TRIALS_PER_OFFSET):
            v = rand_bytes(rng, rng.randrange(24, 49))
            pre = rand_bytes(rng, off)
            post = rand_bytes(rng, rng.randrange(0, 6))
            stream = base64.b64encode(pre + v + post).decode()
            needle = rule(v, off)
            if needle and needle in stream:
                hits += 1
        results[(name, off)] = hits

total_per_rule = TRIALS_PER_OFFSET * len(OFFSETS)
print(f"trials per cell: {TRIALS_PER_OFFSET}   cells per rule: {len(OFFSETS)}   "
      f"per-rule total: {total_per_rule}   grand total: {total_per_rule * 2}")
print()
for name in ("first attempt", "trim rule"):
    cells = " ".join(f"off{o}={results[(name, o)]}/{TRIALS_PER_OFFSET}" for o in OFFSETS)
    tot = sum(results[(name, o)] for o in OFFSETS)
    print(f"{name:14s} {cells}   total={tot}/{total_per_rule}")
print()
print("lead = ceil(8r/6) for r=0,1,2 ->", [math.ceil(8 * o / 6) for o in OFFSETS])
