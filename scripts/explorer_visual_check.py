#!/usr/bin/env python3
"""Character-grid visual regression for the Explorer static panel.

Renders wezterm/explorer.sh in a deterministic 80-col pipe against a temp
DESK tree, strips ANSI, then asserts the upstream Show-Listing contract:
  - all box lines flush-right at INNER+4 cells
  - HEADER / 1 LOCATION / 2 FILES / 3 COMMAND zones render
  - VIEW starts inside DESK (no out-of-tree warning on entry)
  - numbered entries appear; favorite toggle adds the ★ row on repaint
  - explorer> line prompt present

Exit 0 = all green.
"""
import os
import re
import subprocess
import sys
import tempfile
import unicodedata

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXPLORER = os.path.join(REPO, "wezterm", "explorer.sh")
WZLIB = os.path.join(REPO, "wezterm", "wzlib.zsh")
COLS = 80
INNER = COLS - 6
TOT = INNER + 4

ANSI = re.compile(r"\x1b\[[0-9;]*m")
failures = []


def disp(s: str) -> int:
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def check(cond: bool, msg: str):
    status = "PASS" if cond else "FAIL"
    print(f"  {status}  {msg}")
    if not cond:
        failures.append(msg)


def render() -> str:
    with tempfile.TemporaryDirectory() as td:
        desk = os.path.join(td, "Desk")
        os.makedirs(os.path.join(desk, "src"))
        os.makedirs(os.path.join(desk, "docs"))
        os.makedirs(os.path.join(desk, ".git"))
        with open(os.path.join(desk, "README.md"), "w") as f:
            f.write("# readme\n")
        fav = os.path.join(td, "favorites.tsv")
        roots = os.path.join(td, "roots.tsv")
        with open(roots, "w") as f:
            f.write(f"Desk\t{desk}\tcodex\n")
        agentsf = os.path.join(td, "agents.tsv")
        with open(agentsf, "w") as f:
            f.write("codex\tOpenAI Codex CLI\tcodex\tflag\t-C\t0\n")
        env = dict(os.environ)
        env["WZ_LIB"] = WZLIB
        env["WZ_ROOTS_FILE"] = roots
        env["WZ_AGENTS_FILE"] = agentsf
        env["WZ_FAV_FILE"] = fav
        # 1 = descend into .git; b = bind refused; s = back to DESK; f = favorite; q = quit
        feed = "1\nb\ns\nf\nq\n"
        p = subprocess.run(
            ["zsh", EXPLORER, desk],
            input=feed, capture_output=True, text=True, env=env,
        )
        if p.returncode != 0:
            print("  FAIL  explorer.sh exited non-zero: " + str(p.returncode))
            print(p.stderr[:800])
            sys.exit(1)
        with open(roots) as f:
            roots_content = f.read()
        return ANSI.sub("", p.stdout), desk, roots_content


def main():
    text, desk, roots_content = render()
    lines = text.split("\n")

    frame_lines = [l for l in lines if l.startswith("  +")]
    check(all(disp(l.rstrip()) == TOT for l in frame_lines),
          f"all box frames {TOT} cells wide ({len(frame_lines)} lines)")

    interior = [l for l in lines if l.startswith("  |")]
    check(all(l.rstrip().endswith("|") and disp(l.rstrip()) == TOT for l in interior),
          f"all interior lines flush-right at {TOT} cells ({len(interior)} lines)")

    check("EXPLORER" in text and "Desk" in text, "HEADER zone with workspace name")
    check("1 LOCATION" in text, "1 LOCATION zone renders")
    check("VIEW" in text and desk in text, "VIEW row shows desk path")
    check("2 FILES" in text, "2 FILES zone renders")
    check("3 COMMAND" in text, "3 COMMAND zone renders")

    # out-of-tree warning must NOT appear (VIEW starts at DESK)
    check("left DESK tree" not in text, "no out-of-tree warning at entry")

    # numbered entries render (src dir + docs dir + README)
    check("[1]" in text and "[2]" in text and "[3]" in text,
          "numbered entries [1..3] render")
    check("src/" in text and "docs/" in text, "dirs listed with trailing slash")
    check("README.md" in text, "files listed")

    # favorite toggle: after f, the repaint must show the ★ row
    check("★ favorites" in text or "★ Desk" in text, "favorite row appears after f toggle")

    # b on a hidden dir is refused; desk-roots stays unpolluted
    check("hidden dir refused" in text, "b refuses hidden dir (.git)")
    check(".git" not in roots_content, "desk-roots unpolluted by hidden-dir bind")

    check("explorer>" in text, "explorer> prompt present")

    print("")
    if failures:
        print("RESULT: FAIL")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
