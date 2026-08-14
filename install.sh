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
  # Preserve user data (desk-roots, agent registry) across reinstalls:
  # the whole TARGET dir is moved away below, so snapshot workbench first.
  local data_bak=""
  if [ -d "$WORKBENCH_DIR" ]; then
    data_bak="${TMPDIR:-/tmp}/wz-workbench-$STAMP"
    mkdir -p "$data_bak"
    cp -R "$WORKBENCH_DIR"/. "$data_bak"/ 2>/dev/null
    ok "snapshotted user data -> $data_bak"
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
  if [ -n "$data_bak" ] && [ -d "$data_bak" ]; then
    cp -R "$data_bak"/. "$WORKBENCH_DIR"/ 2>/dev/null
    ok "restored user data (desk-roots, agent registry)"
  fi
  if [ ! -f "$ROOTS_FILE" ]; then
    printf '# AI STAR CUBE desk roots — name<TAB>path<TAB>agent\n' > "$ROOTS_FILE"
    ok "created empty desk-roots"
  else
    ok "kept existing desk-roots (not overwritten)"
  fi
  if [ -f "$SRC_DIR/agents.tsv.default" ] && [ ! -f "$WORKBENCH_DIR/agents.tsv" ]; then
    cp "$SRC_DIR/agents.tsv.default" "$WORKBENCH_DIR/agents.tsv"
    ok "created agent registry from template"
  else
    ok "kept existing agent registry (not overwritten)"
  fi
  say ""
  doctor
  say ""
  if [ -x "$(dirname "$0")/scripts/check.sh" ]; then
    "$(dirname "$0")/scripts/check.sh"
  fi
}

case "${1:-}" in
  doctor) doctor ;;
  *) install ;;
esac
