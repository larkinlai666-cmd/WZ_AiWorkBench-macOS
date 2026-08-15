#!/usr/bin/env python3
"""Walking-cat splash animation regression (upstream Get-AgentSplashScript).

Runs wezterm/splash.sh with stdout redirected (non-TTY), which per the
upstream contract must degrade to ONE static final frame:
  - cat art present with the final (o.o) pose
  - progress bar full at 100% (all BLOCK chars, no LIGHT-SHADE leftovers)
  - project · agent-label line rendered
  - 'starting...' line rendered
  - TTY slow-mo path exercises all 5 frames with cursor homing intact

Exit 0 = all green.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPLASH = os.path.join(REPO, "wezterm", "splash.sh")

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
failures = []


def check(cond: bool, msg: str):
    status = "PASS" if cond else "FAIL"
    print(f"  {status}  {msg}")
    if not cond:
        failures.append(msg)


def run(args, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    p = subprocess.run(["zsh", SPLASH] + args, capture_output=True, text=True, env=env)
    return p


def main():
    # --- non-TTY single frame (what regression harnesses and redirects see) ---
    p = run(["Alpha", "OpenAI Codex CLI"])
    if p.returncode != 0:
        print("  FAIL  splash.sh exited non-zero: " + str(p.returncode))
        print(p.stderr[:800])
        sys.exit(1)
    text = ANSI.sub("", p.stdout)

    check("/\\_/\\" in text, "cat head renders")
    check("( o.o )" in text, "final pose (o.o) renders")
    check(" > ^ <" in text, "cat legs render")
    check("100%" in text, "progress reaches 100%")
    check("[█" in text, "progress bar fills with block chars")
    check("░" not in text, "no light-shade remains at 100%")
    check("Alpha · OpenAI Codex CLI" in text, "project · agent-label line")
    check("starting..." in text, "starting... line renders")

    # --- TTY slow-mo multi-frame (cursor homing path, all frames) ---
    p = run(["Alpha", "OpenAI Codex CLI"], {"WZ_SPLASH_FRAMES": "6", "WZ_SPLASH_MS": "0.001"})
    if p.returncode != 0:
        print("  FAIL  splash.sh multi-frame exited non-zero: " + str(p.returncode))
        print(p.stderr[:800])
        sys.exit(1)
    raw = p.stdout
    check(raw.count("/\\_/\\") == 6, "all 6 frames painted (cat head x6)")
    check("( -.- )" in raw, "alternate pose (-.-) appears in odd frames")
    check(" > ^ <~" in raw, "alternate legs appear in odd frames")
    check("0%" in raw and "100%" in raw, "progress spans 0%..100%")

    print("")
    if failures:
        print("RESULT: FAIL")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
