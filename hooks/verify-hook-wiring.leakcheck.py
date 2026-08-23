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


ALNUM = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


def token(n):
    return "".join(random.choice(ALNUM) for _ in range(n))


def chunked(sep, chunk, count):
    """A secret pasted in groups -- how license keys and 2FA seeds are written."""
    return sep.join(token(chunk) for _ in range(count))


FAMILIES = [
    ("std base64 (40 bytes)", lambda: base64.b64encode(rand_bytes(40)).decode()),
    ("urlsafe base64 (40 bytes)", lambda: base64.urlsafe_b64encode(rand_bytes(40)).decode()),
    ("hex (32 bytes)", lambda: rand_bytes(32).hex()),
    ("sk- style (48 chars)", lambda: "sk-" + "".join(
        random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(45))),
    ("JWT-ish", lambda: "eyJ" + base64.urlsafe_b64encode(rand_bytes(60)).decode()),
    ("short b64 (16 bytes)", lambda: base64.b64encode(rand_bytes(16)).decode()),
    ("short hex (12 bytes)", lambda: rand_bytes(12).hex()),
    # Verdict 211: SAFE_VALUE permits space and dot as separators while the run
    # test treated them as breaks, so a secret written in groups slipped through
    # both. These families exist so that disagreement cannot come back unseen.
    ("space-chunked 3x15", lambda: chunked(" ", 15, 3)),
    ("space-chunked 5x8", lambda: chunked(" ", 8, 5)),
    ("dot-chunked 4x10", lambda: chunked(".", 10, 4)),
    ("hyphen-chunked 5x5 (licence key)", lambda: chunked("-", 5, 5)),
    ("underscore-chunked 4x9", lambda: chunked("_", 9, 4)),
    ("mixed separators", lambda: token(9) + " " + token(9) + "." + token(9) + "-" + token(9)),
]

# Absent in revisions before sub-key names were shape-checked. Kept optional so
# this file stays runnable against an older hook, which is how its own falsifier
# works -- a checker that cannot be pointed at known-bad code proves nothing.
render_name = ns.get("render_name")


def leaked(secret, out):
    """Any appearance of the secret, or of a usable prefix of it."""
    return secret in out or (len(secret) >= 12 and secret[:12] in out)


total = 0
print("%-34s %10s %10s" % ("family", "as value", "as sub-key"))
for label, gen in FAMILIES:
    as_value = as_name = 0
    for _ in range(2000):
        secret = gen()
        # A credential can arrive as the VALUE of an ordinary setting or as the
        # NAME of a map entry -- an API key used as a dict key is ordinary. Both
        # reach stdout, so both are measured.
        if leaked(secret, render(secret, "defaultMode")):
            as_value += 1
        if render_name is not None and leaked(secret, render_name(secret)):
            as_name += 1
    total += as_value + as_name
    print("%-34s %10d %10d" % (label, as_value, as_name))

print("\n-- values that MUST still print --")
for v in ["default", "bypassPermissions", "acceptEdits", "plan", "dark", True, 10, None]:
    print("  %-20r -> %s" % (v, render(v, "defaultMode")))

print("\nTOTAL LEAKS: %d" % total)
sys.exit(1 if total else 0)
