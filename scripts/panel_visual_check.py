#!/usr/bin/env python3
"""Character-grid visual regression for the Init static panel.

Renders wezterm/init.sh in a deterministic 80-col pipe (stty unavailable in a
pipe, so init.sh falls back to COLS=80), strips ANSI, then asserts:
  - every line inside a box has exactly INNER+4 display cells (right border flush)
  - LIST header columns align with data-row columns (display-width aware)
  - chip indent parity between LIST and AGENT zones
  - two-step flow texts appear (step2 title, agent prompt, cancel hint, wz>)

This is the defense line that catches the misalignment class the upstream
InputSelector-era review missed. Exit 0 = all green.
"""
import os
import re
import subprocess
import sys
import tempfile
import unicodedata

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT = os.path.join(REPO, "wezterm", "init.sh")
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


def pos_of(line: str, token: str):
    i = line.find(token)
    return None if i < 0 else disp(line[:i])


def render() -> str:
    with tempfile.TemporaryDirectory() as td:
        proj = os.path.join(td, "Alpha")
        os.makedirs(proj)
        roots = os.path.join(td, "roots.tsv")
        with open(roots, "w") as f:
            f.write(f"Alpha\t{proj}\tcodex\n")
        env = dict(os.environ)
        env["WZ_ROOTS_FILE"] = roots
        # n1 -> step2 render; q -> cancel back to step1; q -> exit (no spawns)
        feed = "n1\nq\nq\n"
        p = subprocess.run(
            ["zsh", INIT], input=feed, capture_output=True, text=True, env=env
        )
        if p.returncode != 0:
            print("  FAIL  init.sh exited non-zero: " + str(p.returncode))
            sys.exit(1)
        return ANSI.sub("", p.stdout)


def main():
    text = render()
    lines = text.split("\n")

    box_lines = [l for l in lines if l.startswith("  +") or l.startswith("  |") or l.startswith("  -")]
    frame_lines = [l for l in lines if l.startswith("  +")]

    # 1) every frame line (box top/bottom) is exactly TOT wide
    check(all(disp(l.rstrip()) == TOT for l in frame_lines),
          f"all box frames {TOT} cells wide ({len(frame_lines)} lines)")

    # 2) every box-interior line has a flush right border at TOT
    interior = [l for l in lines if l.startswith("  |")]
    bad = [disp(l.rstrip()) for l in interior if not l.rstrip().endswith("|")]
    check(all(l.rstrip().endswith("|") and disp(l.rstrip()) == TOT for l in interior),
          f"all interior lines flush-right at {TOT} cells ({len(interior)} lines)")

    # 3) header vs data column alignment (first step1 render)
    hdr = next((l for l in lines if "[#]" in l), None)
    row = next((l for l in lines if "[1]" in l and "Alpha" in l), None)
    if hdr is None or row is None:
        check(False, "LIST header/data rows found")
        print("\nRESULT: FAIL")
        sys.exit(1)

    for htoken, rtoken in (
        ("DateTime", "08-"),
        ("Tag", "[任务]"),
        ("Project", "Alpha"),
        ("Path", "/"),
        ("Agent", "Codex"),
    ):
        hp, rp = pos_of(hdr, htoken), pos_of(row, rtoken)
        if rtoken == "/":
            rp = pos_of(row, "/")  # row path starts with '/'
        check(hp is not None and rp is not None and hp == rp,
              f"column '{htoken}' aligned (header@{hp} row@{rp})")

    # 4) chip indent parity: LIST [1] and AGENT [1] start at the same column
    list_chip = pos_of(row, "[1]")
    agt_row = next((l for l in lines if "[1]" in l and "Codex" in l and "Alpha" not in l), None)
    agt_chip = pos_of(agt_row, "[1]") if agt_row else None
    check(list_chip == 4 and agt_chip == 4, f"chip indent parity (list@{list_chip} agent@{agt_chip})")

    # 5) two-step flow texts
    check("2 AGENT  << step 2 · pick agent for Alpha" in text, "step2 title switches with pending task")
    check("agent 1-" in text and "(Enter = default, q = cancel)" in text, "step2 agent line-input prompt")
    check("! launch cancelled" in text, "cancel hint repaint after q")
    check("wz>" in text, "step1 wz> prompt present")

    print("")
    if failures:
        print("RESULT: FAIL")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
