#!/usr/bin/env python3
"""Character-grid visual regression for the Init static panel.

Renders wezterm/init.sh across a WIDTH MATRIX via WZ_COLS (pipes have no
stty, so refresh_size falls back to WZ_COLS), strips ANSI, then asserts:
  - every box frame/interior line is flush-right at exactly TOT cells
  - LIST header columns align with data-row columns at EVERY width
  - adjacent columns carry a >=2-cell gap (upstream ColGap discipline)
  - Path column is SEMI-flexible with a hard cap of 34: wide hosts never
    let it swallow the row (anti-squish regression for aspect-ratio resize)
  - ultra-narrow (60) keeps frames flush (key_row hard-truncates tail)
  - chip indent parity between LIST and AGENT zones
  - agent zone renders registry rows; unresolvable rows hidden
  - two-step flow texts (step2 title, agent prompt, cancel hint, wz>)

Exit 0 = all green.
"""
import os
import re
import subprocess
import sys
import tempfile
import unicodedata

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INIT = os.path.join(REPO, "wezterm", "init.sh")
WZLIB = os.path.join(REPO, "wezterm", "wzlib.zsh")

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

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


def expected_widths(inner: int):
    """Mirror of init.sh render() column layout (must stay in sync)."""
    w_date, w_tag, w_agent, gap = 13, 6, 8, 2
    w_proj = min(22, max(12, inner * 14 // 100))
    w_path = inner - 1 - 6 - w_date - w_tag - w_agent - w_proj - 4 * gap
    if w_path > 34:
        w_path = 34
    elif w_path < 16:
        need = 16 - w_path
        if need > 0 and w_proj > 12:
            cut = min(need, w_proj - 12)
            w_proj -= cut
            need -= cut
        if need > 0 and w_date > 11:
            cut = min(need, w_date - 11)
            w_date -= cut
            need -= cut
        if need > 0 and w_tag > 5:
            cut = min(need, w_tag - 5)
            w_tag -= cut
            need -= cut
        w_path = inner - 1 - 6 - w_date - w_tag - w_agent - w_proj - 4 * gap
        w_path = max(10, w_path)
    return w_date, w_tag, w_proj, w_path, w_agent


def render(cols: int) -> str:
    with tempfile.TemporaryDirectory() as td:
        proj = os.path.join(td, "Alpha")
        os.makedirs(proj)
        roots = os.path.join(td, "roots.tsv")
        with open(roots, "w") as f:
            f.write(f"Alpha\t{proj}\tcodex\n")
        agentsf = os.path.join(td, "agents.tsv")
        with open(agentsf, "w") as f:
            f.write(
                "codex\tOpenAI Codex CLI\tcodex\tflag\t-C\t0\n"
                "kimi\tKimi Code CLI\tkimi\tcwd\t\t0\n"
                "agy\tAGY\tagy\tcwd\t\t0\n"
                "ghost\tGHOST\tno-such-exe-xyz\tcwd\t\t0\n"
            )
        env = dict(os.environ)
        env["WZ_LIB"] = WZLIB
        env["WZ_ROOTS_FILE"] = roots
        env["WZ_AGENTS_FILE"] = agentsf
        env["WZ_COLS"] = str(cols)
        # n1 -> step2 render; q -> cancel; a -> all-view; q -> exit (no spawns)
        feed = "n1\nq\na\nq\n"
        p = subprocess.run(
            ["zsh", INIT], input=feed, capture_output=True, text=True, env=env
        )
        if p.returncode != 0:
            print(f"  FAIL  init.sh exited non-zero at {cols} cols: " + str(p.returncode))
            print(p.stderr[:800])
            sys.exit(1)
        return ANSI.sub("", p.stdout)


def grid_checks(cols: int, text: str):
    """Frame flush + column alignment + gap + Path cap at one width."""
    inner = cols - 6
    tot = inner + 4
    lines = text.split("\n")

    frame_lines = [l for l in lines if l.startswith("  +")]
    check(all(disp(l.rstrip()) == tot for l in frame_lines),
          f"[{cols}] all box frames {tot} cells wide ({len(frame_lines)} lines)")

    interior = [l for l in lines if l.startswith("  |")]
    check(all(l.rstrip().endswith("|") and disp(l.rstrip()) == tot for l in interior),
          f"[{cols}] all interior lines flush-right at {tot} cells ({len(interior)} lines)")

    hdr = next((l for l in lines if "[#]" in l), None)
    row = next((l for l in lines if "[1]" in l and "Alpha" in l), None)
    if hdr is None or row is None:
        check(False, f"[{cols}] LIST header/data rows found")
        return

    w_date, w_tag, w_proj, w_path, w_agent = expected_widths(inner)
    p_date_h, p_date_r = pos_of(hdr, "DateTime"), pos_of(row, "08-")
    check(p_date_h is not None and p_date_r is not None and p_date_h == p_date_r,
          f"[{cols}] column 'DateTime' aligned (header@{p_date_h} row@{p_date_r})")
    # remaining columns: derive row positions from Date start + widths
    # (Tag may be truncated like '[任~' at narrow widths, so no text match)
    h_tag, h_proj, h_path, h_agent = (
        pos_of(hdr, "Tag"), pos_of(hdr, "Project"),
        pos_of(hdr, "Path"), pos_of(hdr, "Agent"),
    )
    r_tag = p_date_r + w_date + 2
    r_proj = r_tag + w_tag + 2
    r_path = r_proj + w_proj + 2
    r_agent = r_path + w_path + 2
    check(h_tag == r_tag, f"[{cols}] column 'Tag' aligned (header@{h_tag} row@{r_tag})")
    check(h_proj == r_proj, f"[{cols}] column 'Project' aligned (header@{h_proj} row@{r_proj})")
    check(h_path == r_path, f"[{cols}] column 'Path' aligned (header@{h_path} row@{r_path})")
    check(h_agent == r_agent, f"[{cols}] column 'Agent' aligned (header@{h_agent} row@{r_agent})")

    p_date, p_tag = p_date_h, h_tag
    p_proj, p_path, p_agent = h_proj, h_path, h_agent
    check(p_tag - (p_date + w_date) == 2, f"[{cols}] gap Date->Tag == 2 (got {p_tag - (p_date + w_date)})")
    check(p_proj - (p_tag + w_tag) == 2, f"[{cols}] gap Tag->Proj == 2 (got {p_proj - (p_tag + w_tag)})")
    check(p_path - (p_proj + w_proj) == 2, f"[{cols}] gap Proj->Path == 2 (got {p_path - (p_proj + w_proj)})")
    check(p_agent - (p_path + w_path) == 2, f"[{cols}] gap Path->Agent == 2 (got {p_agent - (p_path + w_path)})")

    actual_path_w = p_agent - p_path - 2
    check(actual_path_w <= 35, f"[{cols}] Path column capped (width {actual_path_w} <= 35)")
    check(actual_path_w == w_path, f"[{cols}] Path width matches layout ({actual_path_w} == {w_path})")

    # head-truncation contract: '~' marker sits at the Path column start and
    # the TAIL (project name) stays visible
    tilde = row.rfind("~")
    if tilde >= 0:
        check(disp(row[:tilde]) == p_path,
              f"[{cols}] path '~' marker at Path column ({disp(row[:tilde])} == {p_path})")
        path_seg = row[tilde:tilde + w_path]
        check(path_seg.rstrip().endswith("Alpha"),
              f"[{cols}] path keeps tail (project name 'Alpha' visible)")

    # fixed columns never inflate on wide hosts (anti-squish core):
    # Date/Tag start at the same absolute column at 80 and 200 cols
    if cols >= 200:
        check(p_date == 10, f"[{cols}] Date starts at fixed column 10 (got {p_date})")
        check(p_tag == 25, f"[{cols}] Tag starts at fixed column 25 (got {p_tag})")


def wizard_render() -> tuple:
    """Drive the 4-step wizard end-to-end and return output + side effects."""
    with tempfile.TemporaryDirectory() as td:
        proj = os.path.join(td, "Alpha")
        os.makedirs(proj)
        roots = os.path.join(td, "roots.tsv")
        with open(roots, "w") as f:
            f.write(f"Alpha\t{proj}\tcodex\n")
        agentsf = os.path.join(td, "agents.tsv")
        with open(agentsf, "w") as f:
            f.write(
                "codex\tOpenAI Codex CLI\tcodex\tflag\t-C\t0\n"
                "kimi\tKimi Code CLI\tkimi\tcwd\t\t0\n"
            )
        env = dict(os.environ)
        env["WZ_LIB"] = WZLIB
        env["WZ_ROOTS_FILE"] = roots
        env["WZ_AGENTS_FILE"] = agentsf
        env["WZ_COLS"] = "80"
        env["WEZ"] = "/bin/echo"   # neutralize spawn side effects in the harness
        # c -> wizard; WZTest -> name; 2 -> location RECENT(td); Enter -> default
        # agent; y -> confirm & create & launch
        feed = "c\nWZTest\n2\n\ny\n"
        p = subprocess.run(
            ["zsh", INIT], input=feed, capture_output=True, text=True, env=env
        )
        if p.returncode != 0:
            print("  FAIL  wizard run exited non-zero: " + str(p.returncode))
            print(p.stderr[:800])
            sys.exit(1)
        with open(roots) as f:
            roots_content = f.read()
        wzproj = ""
        wp = os.path.join(td, "WZTest", ".wz-project")
        if os.path.exists(wp):
            with open(wp) as f:
                wzproj = f.read()
        return ANSI.sub("", p.stdout), roots_content, wzproj, td


def main():
    text80 = render(80)

    # ---- width matrix: aspect-ratio resilience ----
    for cols in (72, 80, 120, 200):
        grid_checks(cols, text80 if cols == 80 else render(cols))

    # ultra-narrow: frames stay flush (tail truncation, no wrap chaos)
    text60 = render(60)
    tot60 = 60 - 6 + 4
    interior60 = [l for l in text60.split("\n") if l.startswith("  |")]
    check(all(l.rstrip().endswith("|") and disp(l.rstrip()) == tot60 for l in interior60),
          "[60] ultra-narrow keeps frames flush (no wrap)")

    # ---- COMMAND zone regular grid (chip slot 11 + label slot 24) ----
    l1 = next((l for l in text80.split("\n") if "one-shot launch" in l), None)
    l2 = next((l for l in text80.split("\n") if "NEW TASK wizard" in l), None)
    l3 = next((l for l in text80.split("\n") if "all view" in l), None)
    if l1 and l2 and l3:
        c1 = pos_of(l1, "[ <t><a> ]")
        c2 = pos_of(l2, "[ c ]")
        c3 = pos_of(l3, "[ a ]")
        check(c1 == 43 and c2 == 43 and c3 == 43,
              f"COMMAND chip column 2 flush at 43 (got {c1}/{c2}/{c3})")
        k1 = pos_of(l1, "[ <num> ]")
        k2 = pos_of(l2, "[ n<num> ]")
        k3 = pos_of(l3, "[ s ]")
        check(k1 == 4 and k2 == 4 and k3 == 4,
              f"COMMAND chip column 1 flush at 4 (got {k1}/{k2}/{k3})")
        v1 = pos_of(l1, " one-shot launch")
        v2 = pos_of(l2, " NEW TASK wizard")
        check(v1 == 56 and v2 == 56,
              f"COMMAND label column 2 flush at 56 (got {v1}/{v2})")

    # ---- 80-col full-content assertions ----
    lines = text80.split("\n")
    row = next((l for l in lines if "[1]" in l and "Alpha" in l), None)

    list_chip = pos_of(row, "[1]") if row else None
    agt_row = next((l for l in lines if "[1]" in l and "Codex" in l and "Alpha" not in l), None)
    agt_chip = pos_of(agt_row, "[1]") if agt_row else None
    check(list_chip == 4 and agt_chip == 4, f"chip indent parity (list@{list_chip} agent@{agt_chip})")

    check("OpenAI Codex CLI" in text80, "registry agent 'codex' rendered")
    check("Kimi Code CLI" in text80, "registry agent 'kimi' rendered")
    check("AGY" in text80, "user-registered agent 'agy' rendered")
    check("GHOST" not in text80, "unresolvable registry row hidden (equal footing)")

    check("2 AGENT  << step 2 · pick agent for Alpha" in text80, "step2 title switches with pending task")
    check("agent 1-" in text80 and "(Enter = default, q = cancel)" in text80, "step2 agent line-input prompt")
    check("! launch cancelled" in text80, "cancel hint repaint after q")
    check("ALL non-noise (combo off)" in text80, "a toggles all-view (combo off)")
    check("wz>" in text80, "step1 wz> prompt present")

    # ---- wizard 4-step flow ----
    wtext, wroots, wproj, wtd = wizard_render()
    check("Step 1/4 · project name" in wtext, "wizard step1 name renders")
    check("Step 2/4 · create location" in wtext, "wizard step2 location renders")
    check("LOCATIONS" in wtext and "RECOMMENDED" in wtext, "wizard location candidates render")
    check("Step 3/4 · default agent" in wtext, "wizard step3 agent renders")
    check("Step 4/4 · confirm" in wtext, "wizard step4 confirm renders")
    check(f"WZTest\t{os.path.join(wtd, 'WZTest')}\tcodex" in wroots,
          "wizard freezes desk-roots row (name/path/agent)")
    check(f"name=WZTest\npath={os.path.join(wtd, 'WZTest')}\n" == wproj,
          "wizard freezes .wz-project identity")
    check("wizard cancelled" not in wtext, "wizard completes without cancellation")

    print("")
    if failures:
        print("RESULT: FAIL")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
