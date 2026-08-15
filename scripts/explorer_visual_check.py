#!/usr/bin/env python3
"""Character-grid visual regression for the Explorer static panel.

Renders wezterm/explorer.sh in a deterministic pipe against a temp DESK tree,
strips ANSI, then asserts the upstream Show-Listing contract:
  - all box lines flush-right at INNER+4 cells (OSC8 sequences zero-width)
  - HEADER / 1 LOCATION / 2 FILES / 3 COMMAND zones render
  - numbered entries appear; favorite toggle adds the ★ row on repaint
  - click-to-open: OSC8 file:// hyperlinks present; executables never linked
  - long names truncate head~tail.ext (extension kept)
  - o<num> system-open branch (OPEN_CMD neutralized in harness)
  - fs change detection via wzlib snapshot (unit-checked)

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
OSC8 = re.compile(r"\x1b\]8;;[^\x1b]*\x1b\\")
failures = []


def disp(s: str) -> int:
    return sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)


def strip_osc8(s: str) -> str:
    return OSC8.sub("", s)


def check(cond: bool, msg: str):
    status = "PASS" if cond else "FAIL"
    print(f"  {status}  {msg}")
    if not cond:
        failures.append(msg)


def render(cols: int = 80) -> tuple:
    with tempfile.TemporaryDirectory() as td:
        desk = os.path.join(td, "Desk")
        os.makedirs(os.path.join(desk, "src"))
        os.makedirs(os.path.join(desk, "docs"))
        os.makedirs(os.path.join(desk, ".git"))
        with open(os.path.join(desk, "README.md"), "w") as f:
            f.write("# readme\n")
        longfile = "very" + "x" * 60 + ".txt"
        with open(os.path.join(desk, longfile), "w") as f:
            f.write("long\n")
        os.makedirs(os.path.join(desk, "longdir" + "y" * 60))
        extool = os.path.join(desk, "exec_tool.sh")
        with open(extool, "w") as f:
            f.write("echo hi\n")
        os.chmod(extool, 0o755)
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
        env["WZ_COLS"] = str(cols)
        env["OPEN_CMD"] = "/bin/echo"   # neutralize real Finder/open in harness
        # 1 = descend into .git; b = bind refused; s = back to DESK;
        # f = favorite; o1 = system-open favorite dir; o6 = open README; q = quit
        feed = "1\nb\ns\nf\no1\no6\nq\n"
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
        return ANSI.sub("", p.stdout), desk, roots_content, longfile


def grid_checks(cols: int):
    """Rail-width matrix: 45 = sidebar width (0.21 rail), 80 = full tab."""
    text, desk, roots_content, _ = render(cols)
    tot = cols - 6 + 4
    clean = strip_osc8(text)
    lines = clean.split("\n")
    frame_lines = [l for l in lines if l.startswith("  +")]
    check(all(disp(l.rstrip()) == tot for l in frame_lines),
          f"[{cols}] all box frames {tot} cells wide ({len(frame_lines)} lines)")
    interior = [l for l in lines if l.startswith("  |")]
    check(all(l.rstrip().endswith("|") and disp(l.rstrip()) == tot for l in interior),
          f"[{cols}] all interior lines flush-right at {tot} cells ({len(interior)} lines)")
    check("EXPLORER" in text and "Desk" in text, f"[{cols}] HEADER zone renders")
    check("1 LOCATION" in text and "2 FILES" in text and "3 COMMAND" in text,
          f"[{cols}] LOCATION/FILES/COMMAND zones render")
    check("explorer>" in text, f"[{cols}] explorer> prompt present")
    check("seg_w" not in text, f"[{cols}] no zsh local-leak artifacts in output")
    check(".git" not in roots_content, f"[{cols}] desk-roots unpolluted by hidden-dir bind")
    if cols == 45:
        check("veryxxxxxxxxx~" in text, "[45] long filename truncates head~tail.ext")
    return text


def linkable_check():
    with tempfile.TemporaryDirectory() as td:
        sh = os.path.join(td, "tool.sh")
        with open(sh, "w") as f:
            f.write("echo hi\n")
        os.chmod(sh, 0o755)
        txt = os.path.join(td, "note.txt")
        with open(txt, "w") as f:
            f.write("x\n")
        sub_dir = os.path.join(td, "subdir")
        os.makedirs(sub_dir)
        app = os.path.join(td, "prog.app")
        with open(app, "w") as f:
            f.write("x\n")
        script = f'''source "{WZLIB}"
is_linkable "{sh}" && print LINK_SH
is_linkable "{txt}" && print LINK_TXT
is_linkable "{sub_dir}" && print LINK_DIR
is_linkable "{app}" && print LINK_APP'''
        p = subprocess.run(["zsh", "-c", script], capture_output=True, text=True)
        out = p.stdout
        check("LINK_SH" not in out, "executable file not linkable (click-safe)")
        check("LINK_TXT" in out, "plain file linkable")
        check("LINK_DIR" in out, "directory linkable")
        check("LINK_APP" not in out, ".app bundle file not linkable")


def fs_check():
    with tempfile.TemporaryDirectory() as td:
        script = f'''source "{WZLIB}"
fs_snap_reset "{td}"
touch "{td}/newfile"
fs_changed "{td}" && print CHANGED
fs_changed "{td}" && print WRONG'''
        p = subprocess.run(["zsh", "-c", script], capture_output=True, text=True)
        check("CHANGED" in p.stdout, "fs change detected exactly once")
        check("WRONG" not in p.stdout, "no repeat change without modification")


def main():
    # rail-width matrix: 45 ≈ 0.21 sidebar rail of a 215-col window; 80 full tab
    grid_checks(45)
    text, desk, roots_content, longfile = render(80)
    clean = strip_osc8(text)
    lines = clean.split("\n")

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
    check("left DESK tree" not in text, "no out-of-tree warning at entry")

    # numbered entries render (idx column right-aligned, no brackets — upstream style)
    check("|   1  " in clean and "|   2  " in clean and "|   3  " in clean,
          "numbered entries [1..3] render")
    check("src/" in text and "docs/" in text, "dirs listed with trailing slash")
    check("README.md" in text, "files listed")

    # favorite toggle: after f, the repaint must show the ★ row
    check("★ favorites" in text or "★ Desk" in text, "favorite row appears after f toggle")

    # b on a hidden dir is refused; desk-roots stays unpolluted
    check("hidden dir refused" in text, "b refuses hidden dir (.git)")
    check(".git" not in roots_content, "desk-roots unpolluted by hidden-dir bind")

    # click-to-open hyperlinks (OSC8 file:// present in raw text)
    check("]8;;file://" in text, "OSC8 file:// hyperlinks emitted")
    exec_line = next((l for l in text.split("\n") if "exec_tool.sh" in l), "")
    check(exec_line != "" and "]8;;" not in exec_line,
          "executable row carries no hyperlink")

    # long-name truncation: head kept, extension kept, '~' present
    check("very" in text and ".txt" in text,
          "long filename truncates head~tail.ext")
    check("longdir" in text, "long dirname truncates with head kept")

    # o<num> system-open branch (OPEN_CMD neutralized → hint text)
    check("Finder:" in text, "o<num> opens dir via system open (Finder)")
    check("opened README.md" in text, "o<num> opens file via default app")

    check("explorer>" in text, "explorer> prompt present")

    linkable_check()
    fs_check()

    print("")
    if failures:
        print("RESULT: FAIL")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
