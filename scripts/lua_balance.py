#!/usr/bin/env python3
"""Minimal Lua delimiter balance check (defense line, no external deps)."""
import sys
from pathlib import Path

PAIRS = {"(": ")", "{": "}", "[": "]"}
CLOSERS = set(PAIRS.values())


def check(text: str, path: str) -> list:
    errors = []
    stack = []
    i = 0
    in_str = None  # None | "'" | '"' | '[[' long
    line = 1
    n = len(text)
    while i < n:
        c = text[i]
        if in_str == "[[":
            if c == "]" and i + 1 < n and text[i + 1] == "]":
                in_str = None
                i += 2
                continue
        elif in_str:
            if c == "\\" and in_str != "[[":
                i += 2
                continue
            if c == in_str:
                in_str = None
        else:
            if c == "-" and i + 1 < n and text[i + 1] == "-":
                j = text.find("\n", i)
                if text.startswith("[[", i + 2):
                    in_str = "[["
                    i += 4
                    continue
                i = n if j == -1 else j
                continue
            if c == '"' or c == "'":
                in_str = c
            elif c in PAIRS:
                stack.append((c, line))
            elif c in CLOSERS:
                if not stack:
                    errors.append(f"{path}:{line}: unmatched closer {c}")
                else:
                    opener, oline = stack.pop()
                    if PAIRS[opener] != c:
                        errors.append(f"{path}:{line}: mismatch {opener}@{oline} vs {c}")
        if c == "\n":
            line += 1
        i += 1
    if in_str:
        errors.append(f"{path}: unclosed string")
    for opener, oline in stack:
        errors.append(f"{path}:{oline}: unclosed {opener}")
    return errors


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("wezterm")
    files = sorted(root.rglob("*.lua")) if root.is_dir() else [root]
    total = 0
    failed = False
    for f in files:
        errs = check(f.read_text(encoding="utf-8", errors="replace"), str(f))
        total += len(errs)
        if errs:
            failed = True
            for e in errs:
                print(e)
        else:
            print(f"OK  {f}")
    print(f"\n{'FAIL' if failed else 'PASS'} — {len(files)} files, {total} issues")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
