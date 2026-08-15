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
  exit 0
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
