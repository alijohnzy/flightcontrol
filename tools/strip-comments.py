#!/usr/bin/env python3
"""Remove Lua comments without touching string literals.

Scans character by character rather than pattern matching, because the source
contains '--' inside strings ("set by hand -- /fcon learn ...") and long-bracket
strings holding secure snippets. A regex would mangle both.
"""
import re
import sys


def _long_bracket(src, i):
    """If a long bracket opens at i, return (level, body_start). Else None."""
    if src[i] != "[":
        return None
    j = i + 1
    level = 0
    while j < len(src) and src[j] == "=":
        level += 1
        j += 1
    if j < len(src) and src[j] == "[":
        return level, j + 1
    return None


def _close_long(src, level, start):
    """Index just past the matching close bracket, or len(src) if unterminated."""
    close = "]" + "=" * level + "]"
    end = src.find(close, start)
    return len(src) if end == -1 else end + len(close)


def strip(src):
    out = []
    i, n = 0, len(src)

    while i < n:
        c = src[i]

        # short string
        if c in "\"'":
            quote = c
            out.append(c)
            i += 1
            while i < n:
                if src[i] == "\\":
                    out.append(src[i:i + 2])
                    i += 2
                    continue
                out.append(src[i])
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            continue

        # comment: check before long strings, since --[[ starts with -
        if c == "-" and src.startswith("--", i):
            lb = _long_bracket(src, i + 2)
            if lb:
                level, body = lb
                i = _close_long(src, level, body)
            else:
                nl = src.find("\n", i)
                i = n if nl == -1 else nl
            continue

        # long string
        lb = _long_bracket(src, i)
        if lb:
            level, body = lb
            end = _close_long(src, level, body)
            out.append(src[i:end])
            i = end
            continue

        out.append(c)
        i += 1

    text = "".join(out)
    # a line that held only a comment now holds only whitespace: drop it
    text = "\n".join(l.rstrip() for l in text.split("\n"))
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip("\n") + "\n"


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as fh:
        sys.stdout.write(strip(fh.read()))
