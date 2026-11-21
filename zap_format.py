"""
zap_format.py - token-safe Lua/Luau formatter used by the ZapHub build.

The first formatter run over this payload ate the space in `c and(` and emitted
`cand(` - a real bug, because `cand` then reads as a global. This formatter
never rewrites a token: it only inserts line breaks and keeps the original
inter-word whitespace as a single space, so the token stream is provably
unchanged. Callers can assert that with `tokens()`.
"""

from __future__ import annotations

import re

NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUM_RE = re.compile(r"0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?[uUlL]*"
                    r"|(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?[uUlL]*")
OPS = ["...", "..=", "..", "==", "~=", "!=", "<=", ">=", "::", "->", "//=", "//",
       "+=", "-=", "*=", "/=", "%=", "^=", "..", "+", "-", "*", "/", "%", "^", "#",
       "&", "~", "|", "<", ">", "=", "(", ")", "{", "}", "[", "]", ";", ":", ",", ".", "?", "!"]


def _long_bracket(src: str, i: int):
    """Return end index of a long bracket starting at src[i]=='[', or None."""
    j = i + 1
    eq = 0
    while j < len(src) and src[j] == "=":
        eq += 1
        j += 1
    if j < len(src) and src[j] == "[":
        close = "]" + "=" * eq + "]"
        end = src.find(close, j + 1)
        return (end + len(close)) if end != -1 else len(src)
    return None


def tokenize(src: str):
    """[(text, had_space_before, kind)] with kind in name/num/str/comment/op."""
    out = []
    i = 0
    n = len(src)
    had_space = False
    while i < n:
        ch = src[i]
        if ch in " \t\r\n":
            had_space = True
            i += 1
            continue
        if src.startswith("--", i):
            j = i + 2
            if j < n and src[j] == "[":
                end = _long_bracket(src, j)
                if end is not None:
                    out.append((src[i:end], had_space, "comment"))
                    i = end
                    had_space = False
                    continue
            end = src.find("\n", i)
            end = n if end == -1 else end
            out.append((src[i:end], had_space, "comment"))
            i = end
            had_space = False
            continue
        if ch in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == ch:
                    j += 1
                    break
                if src[j] == "\n":
                    break
                j += 1
            out.append((src[i:j], had_space, "str"))
            i = j
            had_space = False
            continue
        if ch == "[":
            end = _long_bracket(src, i)
            if end is not None:
                out.append((src[i:end], had_space, "str"))
                i = end
                had_space = False
                continue
        m = NAME_RE.match(src, i)
        if m:
            out.append((m.group(0), had_space, "name"))
            i = m.end()
            had_space = False
            continue
        m = NUM_RE.match(src, i)
        if m and m.end() > i:
            out.append((m.group(0), had_space, "num"))
            i = m.end()
            had_space = False
            continue
        for op in OPS:
            if src.startswith(op, i):
                out.append((op, had_space, "op"))
                i += len(op)
                had_space = False
                break
        else:
            out.append((ch, had_space, "op"))
            i += 1
            had_space = False
    return out


OPEN_AFTER = {"then", "do", "repeat", "else"}
DEDENT_BEFORE = {"end", "until", "else", "elseif"}
NEWLINE_AFTER = {";", "end", "until", "then", "do", "repeat", "else"}
# A line may only end AFTER one of these, never before. Breaking before `(` or
# `{` produces "looks like an argument list" ambiguity; `f\n(x)` parses as
# f(x) in one reading and a syntax error in the other.
BREAK_AFTER = {",", ";", "and", "or", "..", "+", "-", "*", "/", "==", "~=", "=", "<", ">"}
WIDTH = 108
INDENT = "    "


def format_lua(src: str) -> str:
    toks = tokenize(src)
    lines = []
    cur = []
    col = 0
    depth = 0
    prev = None
    at_line_start = True

    def flush():
        nonlocal cur, col, at_line_start
        if cur:
            lines.append("".join(cur).rstrip())
        cur = []
        col = 0
        at_line_start = True

    def emit(tok_text, text, space):
        nonlocal cur, col, at_line_start
        if at_line_start:
            pad = INDENT * max(depth, 0)
            cur.append(pad)
            col = len(pad)
            at_line_start = False
        if space and col > 0:
            cur.append(" ")
            col += 1
        cur.append(text)
        col += len(text)

    for text, had_space, kind in toks:
        if kind == "comment":
            flush()
            emit(None, text, False)
            flush()
            prev = None
            continue

        # block depth bookkeeping
        if kind == "name" and text in DEDENT_BEFORE:
            depth = max(0, depth - 1)

        if kind == "name" and text in DEDENT_BEFORE:
            flush()
        elif prev in (";",) or (prev is not None and prev in NEWLINE_AFTER):
            flush()

        emit(None, text, had_space)
        prev = text

        # wrap only at points where a newline cannot change the parse
        if col > WIDTH and text in BREAK_AFTER:
            flush()

        if kind == "name" and text in OPEN_AFTER:
            depth += 1
        elif kind == "name" and text in ("function",):
            depth += 1

        if (kind == "name" and text in NEWLINE_AFTER) or (kind == "op" and text in (";",)):
            flush()

    flush()
    return "\n".join(lines) + "\n"


def tokens(src: str):
    return [(t, k) for t, _s, k in tokenize(src)]
