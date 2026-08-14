#!/bin/bash
# AI STAR CUBE · macOS · install script
# Deploys wezterm/ -> ~/.config/wezterm/ with backup; creates desk-roots if absent.
# Usage: ./install.sh        (install)
#        ./install.sh doctor (diagnose only, no writes)

set -u

SRC_DIR="$(cd "$(dirname "$0")/wezterm" && pwd)"
TARGET="$HOME/.config/wezterm"
WORKBENCH_DIR="$TARGET/workbench"
ROOTS_FILE="$WORKBENCH_DIR/desk-roots.tsv"
STAMP="$(date +%Y%m%d-%H%M%S)"

say() { printf '%s\n' "$*"; }
ok()  { printf '  \033[32mOK\033[0m  %s\n' "$*"; }
bad() { printf '  \033[31mBAD\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33mWARN\033[0m %s\n' "$*"; }

doctor() {
  say "== Doctor =="
  if command -v wezterm >/dev/null 2>&1; then
    ok "wezterm: $(wezterm --version 2>/dev/null || echo unknown)"
  else
    bad "wezterm not on PATH"
  fi
  local found=0
  for a in codex deepseek kimi grok; do
    if command -v "$a" >/dev/null 2>&1; then
      ok "agent $a: $(command -v "$a")"
      found=$((found + 1))
    fi
  done
  if [ "$found" -ge 1 ]; then
    ok "agents installed: $found (>=1 passes)"
  else
    warn "no agent CLI found — install still allowed, Init will offer shell-only"
  fi
  if [ -f "$TARGET/wezterm.lua" ]; then
    ok "deployed config present at $TARGET"
    if wezterm --config-file "$TARGET/wezterm.lua" show-keys --lua >/dev/null 2>/tmp/wz-mac-doctor.err; then
      ok "config parses (show-keys)"
    else
      bad "config parse failed:"
      sed 's/^/    /' /tmp/wz-mac-doctor.err | head -n 10
    fi
  else
    warn "no deployed config yet (run install)"
  fi
}

install() {
  say "== Install =="
  if [ ! -f "$SRC_DIR/wezterm.lua" ]; then
    bad "source not found: $SRC_DIR/wezterm.lua"
    exit 1
  fi
  if [ -d "$TARGET" ]; then
    local bak="$HOME/.config/wezterm.bak-$STAMP"
    mv "$TARGET" "$bak"
    ok "backed up existing config -> $bak"
  fi
  mkdir -p "$TARGET"
  cp -R "$SRC_DIR"/. "$TARGET"/
  ok "deployed config -> $TARGET"
  mkdir -p "$WORKBENCH_DIR"
  if [ ! -f "$ROOTS_FILE" ]; then
    printf '# AI STAR CUBE desk roots — name<TAB>path<TAB>agent\n' > "$ROOTS_FILE"
    ok "created empty desk-roots"
  else
    ok "kept existing desk-roots (not overwritten)"
  fi
  say ""
  doctor
}

case "${1:-}" in
  doctor) doctor ;;
  *) install ;;
esac
