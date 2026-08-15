# =============================================================================
#  AI STAR CUBE · macOS · shared zsh library (sourced by init.sh / explorer.sh)
#  Provides: ANSI palette, width helpers, box primitives, agent registry
#  parsing, agent launch, shell spawn.
#  Caller must define before sourcing:
#    WZ_DIR  WZ_LIB(optional override)  WEZ  ROOTS_FILE  AGENT_FILE
#  launch_agent plays $WZ_DIR/splash.sh (walking-cat) before the agent boots.
# =============================================================================

# ---- ANSI palette (D-013: bright yellow = input affordance only) ----
typeset Y=$'\e[33;1m'    # bright yellow — chips + prompt prefixes ONLY
typeset C=$'\e[36m'      # cyan — LIST / FILES zone border
typeset M=$'\e[35;1m'    # magenta — AGENT zone border
typeset V=$'\e[32m'      # green — LOCATION zone border / success
typeset D=$'\e[90m'      # dark gray — frames, static notes, inactive text
typeset W=$'\e[97m'      # white — primary text / active names
typeset G=$'\e[37m'      # gray — table row text
typeset R=$'\e[31;1m'    # red — errors / out-of-tree warnings
typeset E=$'\e[32;1m'    # green — success / (default) tag
typeset X=$'\e[0m'

# =============================================================================
# H2 crash guard — an uncaught error must never leave a silent dead pane.
# Panels call `panel_guard <name>` once at startup and `clean_exit [code]`
# for every intentional exit. Any other exit path (set -u violation, syntax
# error, unhandled failure) trips TRAPEXIT with the flag unset -> visible
# red stop + wait for Enter instead of a vanishing pane.
# =============================================================================
typeset WZ_PANEL_NAME=""
typeset WZ_CLEAN_EXIT=0

# TRAPEXIT MUST live at top level (source context): zsh treats an EXIT trap
# defined INSIDE a function as function-scoped — it would fire the moment
# panel_guard() returns and its `read` would eat the panel's stdin.
TRAPEXIT() {
  local code=$?
  # main shell only — $(...) substitution subshells exit constantly and must
  # never trip the guard (their output would corrupt rendered frames)
  if (( ZSH_SUBSHELL == 0 )) && [[ -n "$WZ_PANEL_NAME" ]] && (( WZ_CLEAN_EXIT == 0 )); then
    print ""
    print -r $'\e[31m'"  ! ${WZ_PANEL_NAME} crashed (exit ${code}) — pane kept open for reading"$'\e[0m'
    print -rn $'\e[33m'"  press Enter to close "$'\e[0m'
    read -r 2>/dev/null
  fi
}

panel_guard() {  # activate the crash guard for this panel
  WZ_PANEL_NAME="${1:-panel}"
}

clean_exit() {  # intentional panel exit — bypasses the crash trap
  WZ_CLEAN_EXIT=1
  exit "${1:-0}"
}

# fatal <msg> — visible red stop for known-fatal conditions
fatal() {
  print ""
  print -r $'\e[31m'"  ! ${WZ_PANEL_NAME:-panel}: $1"$'\e[0m'
  print -rn $'\e[33m'"  press Enter to close "$'\e[0m'
  read -r 2>/dev/null
  clean_exit 1
}

# ---- terminal size ----
# refresh_size re-reads the live terminal width on every repaint so panels
# adapt to window resizes (static-screen contract: repaint on state change).
# WZ_COLS env override exists for the regression harness (pipes have no stty).
typeset COLS=80
typeset INNER=74
typeset TOT=78
refresh_size() {
  local cols=80
  local sz minc="${WZ_MIN_COLS:-54}"
  if [[ -n "${WZ_COLS:-}" && "${WZ_COLS}" =~ '^[0-9]+$' ]]; then
    cols=$WZ_COLS
  else
    sz=$(stty size 2>/dev/null)
    if [[ -n "$sz" ]]; then
      cols=${sz##* }
    fi
  fi
  (( cols < minc )) && cols=$minc
  typeset -g COLS=$cols
  typeset -g INNER=$(( cols - 6 ))
  typeset -g TOT=$(( INNER + 4 ))   # every box line = INNER+4 display cells
}
refresh_size

# =============================================================================
# width helpers (display cells, CJK = 2 — same wcwidth semantics WezTerm uses)
# =============================================================================
dwidth() {
  local s="$1" w=0
  # P3 fast path: pure-ASCII strings (the overwhelming majority of file
  # names) need no per-char wcwidth walk — zsh ${#s} is already the answer.
  if [[ "$s" != *[^$'\x01'-$'\x7f']* ]]; then
    print -n ${#s}
    return
  fi
  local c
  for c in ${(s::)s}; do
    case "$c" in
      [$'\u1100'-$'\u115f']|[$'\u2e80'-$'\ua4cf']|[$'\uac00'-$'\ud7a3']|[$'\uf900'-$'\ufaff']|[$'\ufe30'-$'\ufe4f']|[$'\uff00'-$'\uff60']|[$'\uffe0'-$'\uffe6'])
        w=$(( w + 2 )) ;;
      *)
        w=$(( w + 1 )) ;;
    esac
  done
  print -n $w
}

pad() {  # pad <text> <width> — display-width aware; hard-truncate with '~'
  local t="$1" w="$2"
  local dw
  dw=$(dwidth "$t")
  if (( dw > w )); then
    local s="$t"
    while (( $(dwidth "$s") > w - 1 )) && (( ${#s} > 1 )); do
      s="${s[1,-2]}"
    done
    print -n "${s}~"
    local i pd
    pd=$(( w - $(dwidth "$s") - 1 ))
    for (( i = 0; i < pd; i++ )); do print -n " "; done
  else
    print -n "$t"
    local i
    for (( i = dw; i < w; i++ )); do print -n " "; done
  fi
}

pad_tail() {  # pad_tail <text> <width> — head-truncate with leading '~'
  local t="$1" w="$2"   # keeps the TAIL visible (paths: project name stays)
  local dw
  dw=$(dwidth "$t")
  if (( dw > w )); then
    local s="$t"
    while (( $(dwidth "$s") > w - 1 )) && (( ${#s} > 1 )); do
      s="${s[2,-1]}"
    done
    print -n "~${s}"
    local i pd
    pd=$(( w - $(dwidth "$s") - 1 ))
    for (( i = 0; i < pd; i++ )); do print -n " "; done
  else
    print -n "$t"
    local i
    for (( i = dw; i < w; i++ )); do print -n " "; done
  fi
}

# =============================================================================
# Explorer alignment primitives (upstream sidebar.ps1 distilled, 2026-08-15)
#   - click-to-open hyperlinks with safety gate (executables never linked)
#   - head~tail.ext truncation (extension kept, CJK-aware)
#   - filesystem change detection (poll-and-compare; no kernel watcher in zsh)
# =============================================================================

# is_linkable <path> [kind] — 0 = safe for click-to-open hyperlink
is_linkable() {
  local p="$1" kind="${2:-}"
  [[ -d "$p" ]] && return 0
  [[ "$kind" == "dir" ]] && return 0
  local ext
  ext="${p:e:l}"   # zsh :e = extension, :l = lowercase
  case "$ext" in
    app|command|workflow|scpt|jar|msi|exe|bat|cmd|com|scr|reg|vbs|vbe|lnk) return 1 ;;
  esac
  [[ -x "$p" ]] && return 1
  return 0
}

# file_uri <path> — minimal RFC-compliant file URI
file_uri() {
  local p="$1"
  p="${p//\%/%25}"
  p="${p// /%20}"
  p="${p//\#/%23}"
  p="${p//\?/%3F}"
  print -rn "file://$p"
}

# osc8_link <path> <label> [kind] — click-to-open row; non-linkable = plain text
osc8_link() {
  local p="$1" label="$2" kind="${3:-}"
  if ! is_linkable "$p" "$kind"; then
    print -rn "$label"
    return
  fi
  print -rn $'\e]8;;'"$(file_uri "$p")"$'\e\\'"$label"$'\e]8;;'$'\e\\'
}

# ztrunc_display <text> <maxcells> — display-width truncate + '~'
ztrunc_display() {
  local t="$1" w="$2"
  [[ -z "$t" ]] && { print -n ""; return; }
  (( w <= 0 )) && { print -n ""; return; }
  (( $(dwidth "$t") <= w )) && { print -n "$t"; return; }
  (( w <= 1 )) && { print -n "~"; return; }
  local acc="" c
  for c in ${(s::)t}; do
    if (( $(dwidth "$acc$c") > w - 1 )); then
      print -n "${acc}~"
      return
    fi
    acc="$acc$c"
  done
  print -n "${acc}~"
}

# tail_display <text> <maxcells> — take the last <maxcells> display cells
tail_display() {
  local t="$1" w="$2" rev="" i c
  local len=${#t}
  for (( i = len; i >= 1; i-- )); do
    c="${t[i,i]}"
    if (( $(dwidth "$c$rev") > w )); then break; fi
    rev="$c$rev"
  done
  print -n "$rev"
}

# format_name_fit <name> <maxcells> <isdir> — head~tail.ext, extension kept
format_name_fit() {
  local name="$1" w="$2" isdir="${3:-0}"
  local suffix=""
  (( isdir == 1 )) && suffix="/"
  local sw; sw=$(dwidth "$suffix")
  local core="$name" budget
  budget=$(( w - sw ))
  (( budget < 2 )) && budget=2
  if (( $(dwidth "$core") <= budget )); then
    print -n "${core}${suffix}"
    return
  fi
  local ext="" base="$core"
  if (( isdir == 0 )); then
    local stem="${core%.*}"
    if [[ -n "$stem" && "$core" == *.* ]]; then
      ext=".${core:e}"
      base="$stem"
    fi
  fi
  local extw; extw=$(dwidth "$ext")
  local room=$(( budget - extw - 1 ))   # 1 cell for '~'
  if (( room < 2 )); then
    print -n "$(ztrunc_display "$core" $budget)${suffix}"
    return
  fi
  local headn tailn
  headn=$(( room * 55 / 100 ))
  (( headn < 4 )) && headn=4
  tailn=$(( room - headn ))
  if (( tailn < 2 )); then
    tailn=2
    headn=$(( room - tailn ))
  fi
  local head tail
  head=$(ztrunc_display "$base" $headn)
  [[ "$head" == *\~ ]] && head="${head%?}"   # zsh: ${x%~} never matches literal ~
  if (( tailn > 0 )) && [[ -n "$base" ]]; then
    tail=$(tail_display "$base" $tailn)
  fi
  print -n "${head}~${tail}${ext}${suffix}"
}

# ---- filesystem change detection (event-style redraw; no kernel watcher) ----
# P2: zero-fork fingerprint via zsh/stat builtin — name+size+mtime of every
# entry (incl. hidden), no ls/md5 child processes on the poll loop.
# TRAP: full `zmodload zsh/stat` shadows /usr/bin/stat with an incompatible
# builtin (BSD `stat -f` breaks everywhere) — load ONLY the zstat name.
zmodload -F zsh/stat b:zstat 2>/dev/null
typeset FS_SNAP_PREV=""
fs_snapshot() {  # <dir> -> fingerprint
  local d="$1"
  if (( $+builtins[zstat] )); then
    local -a entries st
    local e out=""
    entries=("$d"/*(DN))
    for e in $entries; do
      st=()
      if zstat -A st -- "$e" 2>/dev/null; then
        # st indices: 8=size 10=mtime (full stat array)
        out+="${e:t}:${st[8]}:${st[10]};"
      fi
    done
    print -n "$out"
    return
  fi
  # fallback: external ls (should not happen on stock macOS zsh)
  ls -lTA "$d" 2>/dev/null
}
fs_snap_reset() { FS_SNAP_PREV="$(fs_snapshot "$1")"; }
fs_changed() {  # <dir> -> 0 if changed since last reset
  local s
  s=$(fs_snapshot "$1")
  if [[ "$s" != "$FS_SNAP_PREV" ]]; then
    FS_SNAP_PREV="$s"
    return 0
  fi
  return 1
}

# =============================================================================
# box primitives — every line exactly TOT cells wide
# =============================================================================
box_top() {  # box_top <title> <color>
  local title="$1"
  local colr="$2"
  local t=" $title "
  local tw
  tw=$(dwidth "$t")
  if (( tw > INNER )); then
    t=$(pad "$t" $INNER)   # truncate over-long titles (narrow rails stay flush)
    tw=$INNER
  fi
  local fill=$(( INNER - tw ))
  (( fill < 0 )) && fill=0
  local left=$(( fill / 2 ))
  local right=$(( fill - left ))
  print -n "${colr}  +"
  local i
  for (( i = 0; i < left; i++ )); do print -n -- "-"; done
  print -n "$t"
  for (( i = 0; i < right; i++ )); do print -n -- "-"; done
  print "+${X}"
}

box_rule() {  # box_rule <color>
  local colr="$1" i
  print -n "${colr}  |"
  for (( i = 0; i < INNER; i++ )); do print -n -- "-"; done
  print "|${X}"
}

box_line() {  # box_line <text> <color> — 3 + INNER + 1 = TOT
  local text="$1" colr="$2"
  print -n "${colr}  |${X}"
  pad " $text" $INNER
  print "${colr}|${X}"
}

box_bottom() {  # box_bottom <color>
  local colr="$1" i
  print -n "${colr}  +"
  for (( i = 0; i < INNER; i++ )); do print -n -- "-"; done
  print "+${X}"
}

# Multi-segment row: "tok:text" pairs; pads to TOT; right border always flush.
key_row() {  # key_row <color> "chip:Y" "label:G" [ ... ]
  local colr="$1"; shift
  local seg tok v
  local -a texts=() colors=()
  local budget used i w padc k room s seg_w
  for seg in "$@"; do
    tok="${seg%%:*}"
    v="${seg#*:}"
    texts+=("$v")
    colors+=("$tok")
  done
  budget=$(( INNER - 1 ))
  used=0
  for (( i = 1; i <= ${#texts}; i++ )); do
    w=$(dwidth "${texts[$i]}")
    used=$(( used + w ))
  done
  if (( used > budget )); then
    # squeeze from the LAST segment backward until the row fits:
    # truncate the current segment when the rest fits, else drop it entirely
    k=${#texts}
    while (( used > budget )) && (( k >= 1 )); do
      seg_w=$(dwidth "${texts[$k]}")
      room=$(( budget - (used - seg_w) ))
      if (( room >= 1 )); then
        s="${texts[$k]}"
        while (( $(dwidth "$s") > room )) && (( ${#s} > 1 )); do
          s="${s[1,-2]}"
        done
        texts[$k]="$s"
        used=$(( used - seg_w + $(dwidth "$s") ))
        break
      fi
      texts[$k]=""
      used=$(( used - seg_w ))
      k=$(( k - 1 ))
    done
  fi
  used=0
  for (( i = 1; i <= ${#texts}; i++ )); do
    w=$(dwidth "${texts[$i]}")
    used=$(( used + w ))
  done
  local padc=$(( budget - used ))
  print -n "${colr}  |${X} "
  for (( i = 1; i <= ${#texts}; i++ )); do
    case "${colors[$i]}" in
      Y) print -n "${Y}${texts[$i]}${X}" ;;
      W) print -n "${W}${texts[$i]}${X}" ;;
      G) print -n "${G}${texts[$i]}${X}" ;;
      D) print -n "${D}${texts[$i]}${X}" ;;
      V) print -n "${V}${texts[$i]}${X}" ;;
      C) print -n "${C}${texts[$i]}${X}" ;;
      E) print -n "${E}${texts[$i]}${X}" ;;
      *) print -n "${texts[$i]}" ;;
    esac
  done
  local j
  for (( j = 0; j < padc; j++ )); do print -n " "; done
  print "${colr}|${X}"
}

# =============================================================================
# agent registry (workbench/agents.tsv — same file agents.lua reads)
# =============================================================================
typeset -a A_ID A_LABEL A_EXE A_MODE A_FLAG A_CLEAR

resolve_agent_exe() {  # <name or /abs/path> -> runnable path or empty
  local exe="$1"
  if [[ "$exe" == /* ]]; then
    [[ -x "$exe" ]] && print -n "$exe"
    return
  fi
  local found c
  found=$(command -v "$exe" 2>/dev/null)
  if [[ -n "$found" && -x "$found" ]]; then
    print -n "$found"
    return
  fi
  for c in \
    "$HOME/.local/bin/$exe" "$HOME/.kimi-code/bin/$exe" "$HOME/.codex/bin/$exe" \
    "$HOME/.grok/bin/$exe" "$HOME/.deepseek-cli/bin/$exe" "$HOME/.npm-global/bin/$exe" \
    "/opt/homebrew/bin/$exe" "/usr/local/bin/$exe"; do
    [[ -x "$c" ]] && { print -n "$c"; return; }
  done
  print -n ""
}

load_agents() {
  A_ID=(); A_LABEL=(); A_EXE=(); A_MODE=(); A_FLAG=(); A_CLEAR=()
  typeset -A _seen _seen_exe
  local id label exe mode flag clear exep
  if [[ -f "$AGENT_FILE" ]]; then
    while IFS=$'\t' read -r id label exe mode flag clear; do
      [[ -z "$id" || "$id" == \#* ]] && continue
      (( ${+_seen[$id]} )) && continue   # duplicate id -> first row wins
      _seen[$id]=1
      exep=$(resolve_agent_exe "$exe")
      [[ -z "$exep" ]] && continue   # missing exe -> hidden (equal footing)
      (( ${+_seen_exe[$exep]} )) && continue   # same binary registered twice -> first row wins
      _seen_exe[$exep]=1
      A_ID+=("$id")
      A_LABEL+=("${label:-$id}")
      A_EXE+=("$exep")
      [[ "$mode" == "flag" ]] && A_MODE+=("flag") || A_MODE+=("cwd")
      A_FLAG+=("${flag:-}")
      A_CLEAR+=("${clear:-0}")
    done < "$AGENT_FILE"
  fi
  # Built-in fallback when the registry file is absent
  if (( ${#A_ID} == 0 )); then
    local n
    for n in codex grok kimi deepseek; do
      exep=$(resolve_agent_exe "$n")
      [[ -z "$exep" ]] && continue
      A_ID+=("$n")
      A_EXE+=("$exep")
      case "$n" in
        codex)    A_LABEL+=("OpenAI Codex CLI"); A_MODE+=("flag"); A_FLAG+=("-C");     A_CLEAR+=("0") ;;
        grok)     A_LABEL+=("Grok Build CLI");   A_MODE+=("flag"); A_FLAG+=("--cwd");  A_CLEAR+=("0") ;;
        kimi)     A_LABEL+=("Kimi Code CLI");    A_MODE+=("cwd");  A_FLAG+=("");       A_CLEAR+=("0") ;;
        deepseek) A_LABEL+=("DeepSeek CLI");     A_MODE+=("cwd");  A_FLAG+=("");       A_CLEAR+=("1") ;;
      esac
    done
  fi
}

agent_index_of() {  # <id> -> 1-based index or 0
  local i
  i=1
  while (( i <= ${#A_ID} )); do
    [[ "${A_ID[$i]}" == "$1" ]] && { print -n $i; return; }
    i=$(( i + 1 ))
  done
  print -n 0
}

agent_label_of() {  # <id> -> registry label, fallback id
  local idx
  idx=$(agent_index_of "$1")
  if (( idx > 0 )); then
    print -n "${A_LABEL[$idx]}"
  else
    print -n "$1"
  fi
}

# =============================================================================
# spawn helpers (D-012: panel exits -> sole-pane tab closes with it)
# =============================================================================
launch_agent() {  # launch_agent <name> <root> <agent-index>
  local name="$1" root="$2" idx="$3"
  local exe="${A_EXE[$idx]}" mode="${A_MODE[$idx]}" flag="${A_FLAG[$idx]}" clear="${A_CLEAR[$idx]}"
  local label="${A_LABEL[$idx]}"
  local safe_root="${root//\'/\'\\\'\'}"
  local safe_exe="${exe//\'/\'\\\'\'}"
  local safe_name="${name//\'/\'\\\'\'}"
  local safe_label="${label//\'/\'\\\'\'}"
  local cmd="zsh '$WZ_DIR/splash.sh' '$safe_name' '$safe_label'"
  [[ "$clear" == "1" ]] && cmd+="; clear"
  if [[ "$mode" == "flag" && -n "$flag" ]]; then
    cmd+="; exec '$safe_exe' $flag '$safe_root'"
  else
    cmd+="; exec '$safe_exe'"
  fi
  "$WEZ" cli spawn --cwd "$root" -- /bin/zsh -lc "$cmd" >/dev/null 2>&1
  clean_exit 0
}

open_shell() {
  "$WEZ" cli spawn -- /bin/zsh -l >/dev/null 2>&1
}

open_dash() {  # grok dashboard tab (skip project gate — global UI, upstream parity)
  local gexe
  gexe=$(resolve_agent_exe "grok")
  [[ -z "$gexe" ]] && return 1
  "$WEZ" cli spawn -- "$gexe" dashboard >/dev/null 2>&1
  return 0
}
