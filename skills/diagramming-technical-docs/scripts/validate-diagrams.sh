#!/usr/bin/env bash
#
# validate-diagrams.sh — lint the Mermaid blocks in a Markdown file.
#
# Extracts every ```mermaid fenced block and checks each for the render-breakers
# that a reader would otherwise only discover as an error box in GitHub/Artifacts:
#   1. the first non-empty line is a recognized Mermaid diagram header
#   2. brackets ( ) [ ] { } balance by count (after ignoring quoted strings and
#      the asymmetric >flag] node shape, which is unbalanced by design)
#   3. the block is not empty
#
# This is a pre-check, not a full Mermaid parser — it will not catch semantic
# errors a real render would (e.g. an edge to an undefined node). It catches the
# overwhelmingly common failures: a typo'd header, a forgotten closing bracket,
# and two root nodes in a mindmap (surfaced as an "unbalanced" or header miss).
#
# Usage:  validate-diagrams.sh <file.md>       (or "-" to read stdin)
# Exit:   0 all blocks pass (or none found), 1 a block failed, 3 usage/IO error.

set -u

src="${1:-}"
if [ -z "$src" ]; then
  printf 'usage: validate-diagrams.sh <file.md | ->\n' >&2
  exit 3
fi

py=$(command -v python3 || command -v python) || {
  printf 'validate-diagrams: python3 not found on PATH\n' >&2
  exit 3
}

if [ "$src" != "-" ] && [ ! -f "$src" ]; then
  printf 'validate-diagrams: not a file: %s\n' "$src" >&2
  exit 3
fi

"$py" - "$src" <<'PY'
import re
import sys

src = sys.argv[1]
text = sys.stdin.read() if src == "-" else open(src, encoding="utf-8").read()

# Recognized Mermaid diagram headers (first whitespace-delimited token, lowered).
KNOWN = {
    "graph", "flowchart", "sequencediagram", "statediagram", "statediagram-v2",
    "erdiagram", "classdiagram", "mindmap", "gantt", "pie", "journey",
    "gitgraph", "timeline", "quadrantchart", "requirementdiagram", "c4context",
    "sankey-beta", "xychart-beta", "block-beta",
}

# Collect ```mermaid ... ``` blocks with their starting line number.
blocks = []
lines = text.splitlines()
i = 0
fence = re.compile(r'^\s*```\s*mermaid\s*$', re.IGNORECASE)
close = re.compile(r'^\s*```\s*$')
while i < len(lines):
    if fence.match(lines[i]):
        start = i + 1  # 1-indexed line of the opening fence
        body = []
        i += 1
        while i < len(lines) and not close.match(lines[i]):
            body.append(lines[i])
            i += 1
        blocks.append((start, "\n".join(body)))
    i += 1

if not blocks:
    print("no mermaid blocks found")
    sys.exit(0)

def check(body):
    reasons = []
    stripped = [ln for ln in body.splitlines() if ln.strip()]
    if not stripped:
        return ["empty block"]
    header = stripped[0].strip().split()[0].lower()
    if header not in KNOWN:
        reasons.append(f"unrecognized header '{header}'")
    # Ignore quoted strings before counting brackets.
    cleaned = re.sub(r'"[^"]*"', "", body)
    # Strip the asymmetric >flag] node (a lone ] by design). Require a word char
    # before the '>' so arrowheads (-->, ->>) are never mistaken for a node.
    cleaned = re.sub(r'(\w)>[^\]\n]*\]', r'\1', cleaned)
    pairs = [("(", ")", "( )"), ("[", "]", "[ ]")]
    # ER relationship cardinality uses { } (o{, |{, }o, }|) that don't balance and
    # aren't attribute braces — skip the { } check for erDiagram to avoid a false fail.
    if header != "erdiagram":
        pairs.append(("{", "}", "{ }"))
    for op, cl, name in pairs:
        if cleaned.count(op) != cleaned.count(cl):
            reasons.append(f"unbalanced {name} ({cleaned.count(op)} open / {cleaned.count(cl)} close)")
    return reasons

failed = 0
for n, (start, body) in enumerate(blocks, 1):
    reasons = check(body)
    if reasons:
        failed += 1
        print(f"FAIL  block {n} (line {start}): " + "; ".join(reasons))
    else:
        print(f"PASS  block {n} (line {start})")

print(f"\n{len(blocks)} block(s), {failed} failed")
sys.exit(1 if failed else 0)
PY
