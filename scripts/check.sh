#!/bin/bash
# AI STAR CUBE · macOS · defense-line check (one-shot regression)
# Runs: lua balance -> show-keys parse -> mirror md5 (repo vs deployed config)
# Exit 0 = all green.

set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"
FAIL=0

say() { printf '%s\n' "$*"; }
ok()  { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
bad() { printf '  \033[31mBAD\033[0m %s\n' "$*"; }

WEZ="${WEZTERM_BIN:-}"
if [ -z "$WEZ" ]; then
  WEZ="$(command -v wezterm || true)"
fi
if [ -z "$WEZ" ] && [ -x "$HOME/.local/bin/wezterm" ]; then
  WEZ="$HOME/.local/bin/wezterm"
fi

say "== lua balance =="
if python3 scripts/lua_balance.py wezterm >/tmp/wz-check-balance.log 2>&1; then
  ok "lua balance PASS"
else
  bad "lua balance FAIL"
  tail -n 10 /tmp/wz-check-balance.log
  FAIL=1
fi

say "== panel visual grid =="
if python3 scripts/panel_visual_check.py >/tmp/wz-check-visual.log 2>&1; then
  ok "panel visual grid PASS"
else
  bad "panel visual grid FAIL"
  tail -n 15 /tmp/wz-check-visual.log
  FAIL=1
fi

say "== show-keys parse =="
if [ -n "$WEZ" ]; then
  if "$WEZ" --config-file "$DIR/wezterm/wezterm.lua" show-keys --lua >/dev/null 2>/tmp/wz-check-keys.err; then
    ok "config parses (show-keys) via $WEZ"
  else
    bad "config parse FAIL"
    head -n 10 /tmp/wz-check-keys.err
    FAIL=1
  fi
else
  bad "wezterm binary not found — skipping parse check"
  FAIL=1
fi

say "== mirror md5 (repo vs ~/.config/wezterm) =="
if [ -f "$HOME/.config/wezterm/wezterm.lua" ]; then
  MIRROR_FAIL=0
  while IFS= read -r f; do
    rel="${f#./}"
    if [ -f "$HOME/.config/wezterm/$rel" ]; then
      if ! cmp -s "wezterm/$rel" "$HOME/.config/wezterm/$rel"; then
        bad "drift: $rel"
        MIRROR_FAIL=1
      fi
    else
      bad "missing deployed file: $rel"
      MIRROR_FAIL=1
    fi
  done < <(cd wezterm && find . -type f | sort)
  if [ "$MIRROR_FAIL" -eq 0 ]; then
    ok "mirror md5 PASS (all wezterm/ files identical)"
  else
    FAIL=1
  fi
else
  warn_msg="no deployed config (~/.config/wezterm missing) — run ./install.sh"
  printf '  \033[33mWARN\033[0m %s\n' "$warn_msg"
fi

say ""
if [ "$FAIL" -eq 0 ]; then
  ok "ALL GREEN"
else
  bad "REGRESSION FAILED"
fi
exit "$FAIL"
