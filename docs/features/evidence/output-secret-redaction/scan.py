"""Cost of the two scan strategies for >=20-char partial matching. Deterministic (Random(11))."""
import random, string, time

W = 20                      # partial-match floor
N_SECRETS = 40
NEEDLES_PER_SECRET = 9
OUTPUT_BYTES = 100_000

rng = random.Random(11)
alpha = string.ascii_letters + string.digits + "+/-_"


def mk(n):
    return "".join(rng.choice(alpha) for _ in range(n))


needles = [mk(rng.randrange(24, 49)) for _ in range(N_SECRETS * NEEDLES_PER_SECRET)]
short_needles = [mk(rng.randrange(6, 19)) for _ in range(N_SECRETS)]
output = mk(OUTPUT_BYTES)
# plant one real partial hit so both strategies do the replace work
output = output[:50_000] + needles[3][5:5 + 30] + output[50_000:]


def strat_enumerate(text, needles):
    """What 'any >=20-char contiguous substring' means literally, via str.replace."""
    passes = 0
    for nd in needles:
        for i in range(len(nd) - W + 1):
            passes += 1
            sub = nd[i:i + W]
            if sub in text:
                text = text.replace(sub, "[R]")
    return text, passes


def strat_gram_index(text, needles):
    """One pass over the output; needle count does not enter the loop."""
    index = {}
    for nd in needles:
        for i in range(len(nd) - W + 1):
            index.setdefault(nd[i:i + W], nd)
    hits = 0
    out = []
    i = 0
    n = len(text)
    while i <= n - W:
        owner = index.get(text[i:i + W])
        if owner is None:
            out.append(text[i]); i += 1; continue
        hits += 1
        out.append("[R]")
        i += W
    out.append(text[max(0, n - W + 1):])
    return "".join(out), hits


t0 = time.perf_counter(); _, passes = strat_enumerate(output, needles); t1 = time.perf_counter()
t2 = time.perf_counter(); _, hits = strat_gram_index(output, needles); t3 = time.perf_counter()

t4 = time.perf_counter()
tx = output
for nd in sorted(short_needles, key=len, reverse=True):
    tx = tx.replace(nd, "[R]")
t5 = time.perf_counter()

print(f"needles (>=20): {len(needles)}   output: {len(output):,} chars   window: {W}")
print(f"A. enumerate substrings + str.replace : {passes:,} replace passes   {(t1-t0)*1000:8.2f} ms")
print(f"B. 20-gram index, one pass over output: {hits} hit(s)              {(t3-t2)*1000:8.2f} ms")
print(f"C. short needles (<20), whole-only     : {len(short_needles)} passes            {(t5-t4)*1000:8.2f} ms")
print(f"   index size: {sum(len(nd)-W+1 for nd in needles):,} grams")

# --- short-needle strategy: str.replace loop vs one compiled alternation ---
import re as _re
_rounds = 5
_t_rep = _t_rx = 0.0
_rx = _re.compile("|".join(_re.escape(n) for n in sorted(short_needles, key=len, reverse=True)))
for _ in range(_rounds):
    _a = time.perf_counter()
    _tx = output
    for _nd in sorted(short_needles, key=len, reverse=True):
        _tx = _tx.replace(_nd, "[R]")
    _b = time.perf_counter()
    _rx.sub("[R]", output)
    _c = time.perf_counter()
    _t_rep += _b - _a
    _t_rx += _c - _b
print()
print(f"D. short needles, {len(short_needles)} x str.replace : {_t_rep/_rounds*1000:6.2f} ms (mean of {_rounds})")
print(f"E. short needles, 1 compiled alternation  : {_t_rx/_rounds*1000:6.2f} ms (mean of {_rounds})")
