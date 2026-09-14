import math, hashlib, collections
def H(s):
    c=collections.Counter(s); n=len(s)
    return -sum((v/n)*math.log2(v/n) for v in c.values())
hexes=[hashlib.sha256(str(i).encode()).hexdigest() for i in range(500)]
vals=[H(h) for h in hexes]
print("64-char hex (500 sha256 digests): mean=%.2f min=%.2f max=%.2f"%(sum(vals)/len(vals),min(vals),max(vals)))
print("theoretical max for 16 symbols = %.2f"%math.log2(16))
for s in ("s3cr3t","localhost","https://api.example.com/v1/resource"):
    print("%-38r H=%.2f"%(s,H(s)))
