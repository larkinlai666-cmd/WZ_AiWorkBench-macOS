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

say "== explorer visual grid =="
if python3 scripts/explorer_visual_check.py >/tmp/wz-check-explorer.log 2>&1; then
  ok "explorer visual grid PASS"
else
  bad "explorer visual grid FAIL"
  tail -n 15 /tmp/wz-check-explorer.log
  FAIL=1
fi

say "== desk semantics (lua unit) =="
if python3 scripts/desk_semantics_check.py >/tmp/wz-check-desk.log 2>&1; then
  ok "desk semantics PASS"
else
  bad "desk semantics FAIL"
  tail -n 15 /tmp/wz-check-desk.log
  FAIL=1
fi

say "== splash animation =="
if python3 scripts/splash_visual_check.py >/tmp/wz-check-splash.log 2>&1; then
  ok "splash animation PASS"
else
  bad "splash animation FAIL"
  tail -n 15 /tmp/wz-check-splash.log
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

say "== effective keymap =="
if [ -n "$WEZ" ]; then
  KEYS_OUT="$("$WEZ" --config-file "$DIR/wezterm/wezterm.lua" show-keys --lua 2>/dev/null)"
  if [ -z "$KEYS_OUT" ]; then
    bad "show-keys returned empty"
    FAIL=1
  else
    km_has() {  # km_has <desc> <literal>
      if printf '%s\n' "$KEYS_OUT" | grep -qF "$2"; then
        ok "$1"
      else
        bad "$1 (missing: $2)"
        FAIL=1
      fi
    }
    km_lacks() {  # km_lacks <desc> <literal> — literal must NOT appear
      if printf '%s\n' "$KEYS_OUT" | grep -qF "$2"; then
        bad "$1 (should be absent: $2)"
        FAIL=1
      else
        ok "$1"
      fi
    }
    km_has "Cmd+T Init binding" "{ key = 't', mods = 'SUPER'"
    km_has "Cmd+F1 help binding" "{ key = 'F1', mods = 'SUPER'"
    km_has "Cmd+F3 init binding" "{ key = 'F3', mods = 'SUPER'"
    km_has "Cmd+F4 close-pane binding" "{ key = 'F4', mods = 'SUPER'"
    km_has "Cmd+F6 desk binding" "{ key = 'F6', mods = 'SUPER'"
    km_has "Cmd+F7 explorer binding" "{ key = 'F7', mods = 'SUPER'"
    km_has "Fn+F1 alias" "{ key = 'F1', mods = 'NONE'"
    km_has "Fn+F3 alias" "{ key = 'F3', mods = 'NONE'"
    km_has "Fn+F4 alias" "{ key = 'F4', mods = 'NONE'"
    km_has "Fn+F5 reload alias" "{ key = 'F5', mods = 'NONE'"
    km_has "Fn+F6 alias" "{ key = 'F6', mods = 'NONE'"
    km_has "Fn+F7 alias" "{ key = 'F7', mods = 'NONE'"
    km_has "Cmd+W default close-tab intact" "{ key = 'w', mods = 'SUPER', action = act.CloseCurrentTab"
    km_lacks "Cmd+W pane-close hijack removed" "{ key = 'W', mods = 'SUPER', action = act.CloseCurrentPane"
    km_lacks "Cmd+H not hijacked (no workbench action)" "{ key = 'H', mods = 'SUPER', action = act.EmitEvent"
    km_lacks "Cmd+D not hijacked" "{ key = 'D', mods = 'SUPER', action = act.EmitEvent"
    km_lacks "Cmd+E not hijacked" "{ key = 'E', mods = 'SUPER', action = act.EmitEvent"
  fi
else
  bad "wezterm binary not found — skipping keymap check"
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

say "== install doctor =="
if ./install.sh doctor 2>/dev/null | grep -q "DOCTOR:PASS"; then
  ok "doctor PASS"
else
  bad "doctor FAIL (run ./install.sh doctor for detail)"
  FAIL=1
fi

say ""
if [ "$FAIL" -eq 0 ]; then
  ok "ALL GREEN"
else
  bad "REGRESSION FAILED"
fi
exit "$FAIL"
