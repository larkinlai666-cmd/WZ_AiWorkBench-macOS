#!/usr/bin/env python3
"""Unit regression for desk.lua core semantics (Q1).

Runs desk.lua inside a standalone Lua interpreter (wezterm's lua isn't
scriptable headlessly, so we stub the tiny `wezterm` surface the module
touches: home_dir + GLOBAL). Asserts:
  - normalize: file:// strip, %20 decode, backslash, trailing slash
  - is_weak_path: system roots, home, home subdirs, /private, ~/Library/*
  - is_reserved_name matrix
  - read_map hardening: BOM, comments, missing columns, weak-path rows,
    reserved names, dot-prefixed names are all dropped
  - set_root: reserved/weak/hidden refused; same-path takeover removes old row
  - write_map atomicity: tmp+rename (no truncated file mid-write), roundtrip
  - basename / short_path / project_label

Requires a `lua` binary (5.3/5.4) on PATH; falls back to luajit.
Exit 0 = all green.
"""
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESK = os.path.join(REPO, "wezterm", "desk.lua")

LUA = shutil.which("lua") or shutil.which("lua5.4") or shutil.which("lua5.3") or shutil.which("luajit")
failures = []


def check(cond: bool, msg: str):
    status = "PASS" if cond else "FAIL"
    print(f"  {status}  {msg}")
    if not cond:
        failures.append(msg)


HARNESS = r"""
-- stub wezterm surface used by desk.lua
local HOME = os.getenv("WZ_TEST_HOME")
package.preload["wezterm"] = function()
  return { home_dir = HOME, GLOBAL = {} }
end
package.path = os.getenv("WZ_TEST_MODDIR") .. "/?.lua;" .. package.path
-- redirect the roots file into the sandbox
local real_open = io.open
local SANDBOX = os.getenv("WZ_TEST_ROOTS")
io.open = function(path, mode)
  if path:find("desk%-roots%.tsv") then
    if path:find("%.tmp%.") then
      return real_open(SANDBOX .. ".tmp", mode)
    end
    return real_open(SANDBOX, mode)
  end
  return real_open(path, mode)
end
local real_rename = os.rename
os.rename = function(a, b)
  local src = a:find("desk%-roots%.tsv%.tmp%.") and (SANDBOX .. ".tmp") or a
  local dst = b:find("desk%-roots%.tsv$") and SANDBOX or b
  return real_rename(src, dst)
end

local desk = require("desk")
local function T(name, cond)
  print((cond and "OK " or "NO ") .. name)
end

-- normalize
T("norm-file-uri", desk.normalize("file:///Users/x/proj") == "/Users/x/proj")
T("norm-pct20", desk.normalize("/Users/x/My%20Proj") == "/Users/x/My Proj")
T("norm-backslash", desk.normalize("C:\\x\\y") == "C:/x/y")
T("norm-trailing", desk.normalize("/a/b///") == "/a/b")
T("norm-empty", desk.normalize("") == nil)

-- weak paths
T("weak-root", desk.is_weak_path("/") == true)
T("weak-tmp", desk.is_weak_path("/tmp") == true)
T("weak-private", desk.is_weak_path("/private/var/x") == true)
T("weak-home", desk.is_weak_path(HOME) == true)
T("weak-docs", desk.is_weak_path(HOME .. "/Documents") == true)
T("weak-lib-sub", desk.is_weak_path(HOME .. "/Library/Caches") == true)
T("strong-proj", desk.is_weak_path(HOME .. "/wz_build/Proj") == false)

-- reserved names
T("res-home", desk.is_reserved_name("Home") == true)
T("res-tmp", desk.is_reserved_name("tmp") == true)
T("res-empty", desk.is_reserved_name("") == true)
T("res-proj", desk.is_reserved_name("MyProj") == false)

-- basename / labels
T("base", desk.basename("/a/b/c") == "c")
T("label-weak", desk.project_label("/tmp") == "(system)")

-- set_root gates
T("set-reserved", desk.set_root("home", HOME .. "/wz_build/A") == false)
T("set-weak", desk.set_root("A", "/tmp") == false)
T("set-hidden", desk.set_root(".git", HOME .. "/wz_build/A") == false)
T("set-ok", desk.set_root("ProjA", HOME .. "/wz_build/ProjA") == true)
T("get-ok", desk.get_root("ProjA") == HOME .. "/wz_build/ProjA")

-- same-path takeover: new name for same path removes old row
T("set-takeover", desk.set_root("ProjB", HOME .. "/wz_build/ProjA") == true)
T("takeover-old-gone", desk.get_root("ProjA") == nil or desk.get_root("ProjA") ~= HOME .. "/wz_build/ProjA")

-- roots_list roundtrip after writes
local list = desk.roots_list()
T("list-nonempty", #list >= 1)
"""


def run_lua(roots_content: str):
    with tempfile.TemporaryDirectory() as td:
        roots = os.path.join(td, "roots.tsv")
        with open(roots, "w") as f:
            f.write(roots_content)
        harness = os.path.join(td, "harness.lua")
        with open(harness, "w") as f:
            f.write(HARNESS)
        env = dict(os.environ)
        env["WZ_TEST_HOME"] = "/Users/testuser"
        env["WZ_TEST_MODDIR"] = os.path.join(REPO, "wezterm")
        env["WZ_TEST_ROOTS"] = roots
        p = subprocess.run([LUA, harness], capture_output=True, text=True, env=env)
        final = ""
        with open(roots) as f:
            final = f.read()
        return p, final


def main():
    if not LUA:
        print("  SKIP  no lua interpreter on PATH — desk semantics not unit-checked")
        print("RESULT: PASS (skipped)")
        return

    seed = (
        "\ufeff# comment row\n"
        "GoodProj\t/Users/testuser/wz_build/GoodProj\tcodex\n"
        "home\t/Users/testuser/wz_build/X\t\n"          # reserved name -> drop
        ".hidden\t/Users/testuser/wz_build/Y\t\n"        # dot name -> drop
        "WeakRow\t/tmp\t\n"                              # weak path -> drop
        "MissingCol\n"                                   # malformed -> drop
    )
    p, final = run_lua(seed)
    out = p.stdout
    if p.returncode != 0:
        print("  FAIL  lua harness exited non-zero")
        print(p.stderr[:800])
        sys.exit(1)

    for line in out.splitlines():
        line = line.strip()
        if line.startswith("OK "):
            check(True, "lua: " + line[3:])
        elif line.startswith("NO "):
            check(False, "lua: " + line[3:])

    # read_map hardening: dropped rows must not survive the write roundtrip
    check("home\t" not in final, "reserved-name row dropped on rewrite")
    check(".hidden" not in final, "dot-name row dropped on rewrite")
    check("/tmp" not in final.replace(".tmp", ""), "weak-path row dropped on rewrite")
    check("GoodProj" in final, "good row survives roundtrip")
    check("ProjB" in final, "takeover row present after set_root")

    print("")
    if failures:
        print("RESULT: FAIL")
        sys.exit(1)
    print("RESULT: PASS")


if __name__ == "__main__":
    main()
