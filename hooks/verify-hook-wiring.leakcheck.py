"""Leak-rate check for verify-hook-wiring.sh's value renderer.

Run: python3 hooks/verify-hook-wiring.leakcheck.py     (exit 0 = no leaks)

Check 2 prints config values into session-start stdout, so "can a credential get
through?" is a property that has to be measured, not argued. Seven credential
families, 2000 samples each, fixed seed so a result is reproducible.

Extracts render() from the live hook rather than reimplementing it: a
reimplementation would measure this file's copy of the logic, not the thing that
actually ships.

Committed deliberately, and it has already earned its place twice. Against
2fad70f's renderer it reports 995 leaks -- 123/2000 standard base64 and
871/2000 short base64 -- which is how the deny-list approach was shown to be
unfixable rather than merely incomplete. Against the current default-deny
renderer it reports 0/14000. A number that has never been watched moving is not
evidence, so keep the falsifier: point it at an older renderer with
`git show <rev>:hooks/verify-hook-wiring.sh` and confirm it still goes red.
"""
import base64
import random
import sys

src = open("hooks/verify-hook-wiring.sh").read()
# Everything after the heredoc's opening LINE, up to the closing PY, minus the
# trailing try/main()/exit block so importing it does not run the hook.
body = src.split("<<'PY'", 1)[1].split("\n", 1)[1].rsplit("\nPY\n", 1)[0]
body = body.split("\ntry:", 1)[0]
ns = {}
exec(compile(body, "hook", "exec"), ns)
render = ns["render"]

random.seed(20260822)


def rand_bytes(n):
    return bytes(random.getrandbits(8) for _ in range(n))


FAMILIES = [
    ("std base64 (40 bytes)", lambda: base64.b64encode(rand_bytes(40)).decode()),
    ("urlsafe base64 (40 bytes)", lambda: base64.urlsafe_b64encode(rand_bytes(40)).decode()),
    ("hex (32 bytes)", lambda: rand_bytes(32).hex()),
    ("sk- style (48 chars)", lambda: "sk-" + "".join(
        random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(45))),
    ("JWT-ish", lambda: "eyJ" + base64.urlsafe_b64encode(rand_bytes(60)).decode()),
    ("short b64 (16 bytes)", lambda: base64.b64encode(rand_bytes(16)).decode()),
    ("short hex (12 bytes)", lambda: rand_bytes(12).hex()),
]

total = 0
for label, gen in FAMILIES:
    leaks = 0
    for _ in range(2000):
        secret = gen()
        out = render(secret, "defaultMode")
        # Any appearance of the secret, or of a usable prefix of it.
        if secret in out or (len(secret) >= 12 and secret[:12] in out):
            leaks += 1
    total += leaks
    print("%-28s leaked %4d / 2000" % (label, leaks))

print("\n-- values that MUST still print --")
for v in ["default", "bypassPermissions", "acceptEdits", "plan", "dark", True, 10, None]:
    print("  %-20r -> %s" % (v, render(v, "defaultMode")))

print("\nTOTAL LEAKS: %d" % total)
sys.exit(1 if total else 0)
