"""A quote-aware canonicaliser for shell source, used by loosening_extract.py.

It is NOT a shell parser. It answers one question: "if two versions of this file differ only in
comments, blank lines, indentation or the order of entries in a recognised list, do they compare
equal -- and if they differ in anything else, do they compare different?" Everything it cannot be
sure of stays in the text, so an unrecognised construct makes a diff LOUDER (a prompt), never quieter.

What it strips: comments (a `#` that begins a word, outside every quote, to end of line), blank
lines, leading/trailing whitespace on code lines, and backslash-newline joins. What it keeps verbatim:
the body of every quoted string and every here-document, because those can be code (`awk '...'`,
`bash -c "..."`) and a message edit is a cheap prompt. Known limits, stated rather than hidden: a case
pattern's unbalanced `)` inside `$( ... )` mis-counts the substitution depth; ADR 0052 M8 (a stray quote
that pairs with a later one into a different-but-valid program) is not detected by this scan either --
`bash -n` in loosening_extract.py is the only syntax gate, and it shares that blindness.
"""
import re

COMMENT_PRECEDERS = " \t;&|("
# `<<WORD`, `<<-WORD`, `<<'WORD'`, `<<"WORD"`. The delimiter must START with a letter or underscore, so
# `1 << 3` is never a here-document; arithmetic contexts are excluded separately.
HEREDOC_RE = re.compile(r"<<(-?)[ \t]*(?:'([^']*)'|\"([^\"]*)\"|\\?([A-Za-z_][A-Za-z0-9_]*))")
CASE_OPEN_RE = re.compile(r"^case\b.*\bin$")
ESAC_RE = re.compile(r"^esac(\s|;|$)")
# One-line case arm: `pat[|pat...]) body ;;`. A pattern with a quote, `$`, backtick, backslash,
# redirect or paren is not a plain path glob, so it is not an ENTRY and stays in the residue.
_PAT = r"[^\s()|;&<>\"'`$\\]+"
ENTRY_RE = re.compile(r"^(" + _PAT + r"(?:\|" + _PAT + r")*)\)\s*(.*?)\s*;;$")


class ShellScanError(Exception):
    pass


def canonical_lines(text):
    """-> [(line, strippable)]. A line that begins inside a quote or here-document is not strippable."""
    out, buf = [], []
    stack = [["n", 0]]          # [kind, paren depth]; kinds: n sub arith dq sq ansi bt
    pending = []                # here-documents whose bodies start after the current line
    cur_verbatim = False
    i, n = 0, len(text)

    def flush():
        out.append(("".join(buf), not cur_verbatim))
        del buf[:]

    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        kind = stack[-1][0]
        if kind in ("n", "sub", "arith", "dq"):
            if c == "\\":
                if nxt == "\n":     # line continuation: shell joins the lines, in double quotes too
                    i += 2
                    continue
                buf.append(c + nxt)
                i += 2
                continue
            if c == "$" and nxt == "(" and kind != "sq":
                if text[i + 2:i + 3] == "(":
                    stack.append(["arith", 2]); buf.append("$((")
                    i += 3
                else:
                    stack.append(["sub", 1]); buf.append("$(")
                    i += 2
                continue
            if c == "`":
                stack.append(["bt", 0]); buf.append(c); i += 1
                continue
        if kind == "dq":
            if c == '"':
                stack.pop()
        elif kind in ("n", "sub", "arith"):
            if c == "'":
                stack.append(["sq", 0])
            elif c == '"':
                stack.append(["dq", 0])
            elif c == "$" and nxt == "'":
                stack.append(["ansi", 0]); buf.append("$'")
                i += 2
                continue
            elif c == "#" and (not buf or buf[-1] in COMMENT_PRECEDERS):
                while i < n and text[i] != "\n":
                    i += 1
                continue
            elif kind != "n" and c == "(":
                stack[-1][1] += 1
            elif kind != "n" and c == ")":
                stack[-1][1] -= 1
                if stack[-1][1] == 0:
                    stack.pop()
            elif c == "<" and text.startswith("<<<", i):      # here-string: consume all three
                buf.append("<<<")
                i += 3
                continue
            elif c == "<" and text.startswith("<<", i) and not any(s[0] == "arith" for s in stack):
                m = HEREDOC_RE.match(text, i)
                if m:
                    delim = m.group(2) if m.group(2) is not None else (
                        m.group(3) if m.group(3) is not None else m.group(4))
                    pending.append((delim, m.group(1) == "-"))
                    buf.append(m.group(0))
                    i = m.end()
                    continue
        elif kind in ("sq", "ansi", "bt"):
            if c == "\\" and kind != "sq":
                buf.append(c + nxt)
                i += 2
                continue
            if (kind == "sq" and c == "'") or (kind == "ansi" and c == "'") or (kind == "bt" and c == "`"):
                stack.pop()
        if c == "\n":
            flush()
            cur_verbatim = stack[-1][0] in ("dq", "sq", "ansi", "bt")
            i += 1
            for delim, strip_tabs in pending:
                while True:
                    if i >= n:
                        raise ShellScanError("unterminated here-document <<%s" % delim)
                    j = text.find("\n", i)
                    j = n if j < 0 else j
                    line = text[i:j]
                    i = min(j + 1, n)
                    if (line.lstrip("\t") if strip_tabs else line) == delim:
                        break
                    out.append((line, False))
            del pending[:]
            continue
        buf.append(c)
        i += 1
    if buf:
        flush()
    if len(stack) != 1:
        raise ShellScanError("unterminated %s" % {"sq": "single quote", "dq": "double quote",
                                                   "ansi": "$'...' string", "bt": "backtick",
                                                   "sub": "$( ) substitution",
                                                   "arith": "$(( )) expression"}[stack[-1][0]])
    if pending:
        raise ShellScanError("unterminated here-document <<%s" % pending[0][0])
    return out


def code_lines(text):
    """Canonical (text, strippable) lines with blanks and comments gone and code lines trimmed."""
    result = []
    for line, strippable in canonical_lines(text):
        if strippable:
            line = line.strip()
            if not line:
                continue
        result.append((line, strippable))
    return result


def case_entries(lines, header, body):
    """Entries of the one `case` whose header line is exactly `header`.

    Returns (entries, entry_line_indexes), or None when the header does not occur exactly once.
    Raises ShellScanError when the case never closes. Only arms at the case's own nesting depth count,
    and only those whose whole body is `body`.
    """
    starts = [k for k, (s, st) in enumerate(lines) if st and s == header]
    if len(starts) != 1:
        return None
    entries, indexes, depth = {}, set(), 1
    for k in range(starts[0] + 1, len(lines)):
        s, st = lines[k]
        if not st:
            continue
        if CASE_OPEN_RE.match(s):
            depth += 1
        elif ESAC_RE.match(s):
            depth -= 1
            if depth == 0:
                return entries, indexes
        elif depth == 1:
            m = ENTRY_RE.match(s)
            if m and " ".join(m.group(2).split()) == body:
                for pat in m.group(1).split("|"):
                    entries[pat] = pat
                indexes.add(k)
    raise ShellScanError("the case at %r never reaches its esac" % header)
