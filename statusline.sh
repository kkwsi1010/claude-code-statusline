#!/usr/bin/env bash
# cc-statusbar - Claude Code Status Bar
# https://github.com/DreamingStrawberry/cc-statusbar
#
# Line 1: Model | Path@Branch | Context | 5h limit | 7d limit | Cost | /commands
# Line 2: DevLauncher services (auto-detected, optional)

input=$(cat)

# Debug log (enable by: touch /tmp/cc-statusbar-debug)
if [ -f /tmp/cc-statusbar-debug ]; then
    echo "[$(date '+%H:%M:%S')] called from $(ps -o ppid= -p $$ | tr -d ' ' | xargs ps -o comm= -p 2>/dev/null || echo unknown)" >> /tmp/cc-statusbar-debug.log
    echo "input_len=${#input}" >> /tmp/cc-statusbar-debug.log
fi
NOW=$(date +%s)

# ===================================================
# Config (override via ~/.claude/statusline.conf)
# ===================================================
SHOW_MODEL=true
SHOW_PATH=true
SHOW_GIT_BRANCH=true
SHOW_CONTEXT=true
SHOW_5H_LIMIT=true
SHOW_7D_LIMIT=true
SHOW_COST=false
SHOW_COMMANDS=true
SHOW_VERSION=true
SHOW_EFFORT=true
SHOW_FAST=true
LANGUAGE=en
BAR_STYLE=blocks
BAR_WIDTH=10
BAR_FILL="▓"
BAR_EMPTY="░"

# Load config: Windows side first (TUI saves here), then WSL home as fallback
CONF=""
for wconf in /mnt/c/Users/*/.claude/statusline.conf; do
    [ -f "$wconf" ] && CONF="$wconf" && break
done
[ -z "$CONF" ] && CONF="$HOME/.claude/statusline.conf"
[ -f "$CONF" ] && source "$CONF"

# ===================================================
# JSON parser (no jq)
# ===================================================
# Bash regex JSON parser (no subprocess forks)
_e() {
    local v=""
    [[ "$input" =~ \"$1\"[[:space:]]*:[[:space:]]*([^,}]+) ]] && v="${BASH_REMATCH[1]}"
    v="${v//\"/}"; v="${v// /}"; echo "$v"
}
_es() {
    local v=""
    [[ "$input" =~ \"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && v="${BASH_REMATCH[1]}"
    echo "$v"
}
_ea() {
    local v=""
    [[ "$input" =~ \"$1\"[^}]*\"$2\"[[:space:]]*:[[:space:]]*([^,}]+) ]] && v="${BASH_REMATCH[1]}"
    v="${v//\"/}"; v="${v// /}"; echo "$v"
}

# ===================================================
# Data
# ===================================================
model=$(_es "display_name")
cwd=$(_es "current_dir"); [ -z "$cwd" ] && cwd=$(_es "cwd")
exceeds_200k=$(_e "exceeds_200k_tokens")
fast_mode=$(_e "fast_mode")
thinking_enabled=$(_ea "thinking" "enabled")
effort_level=$(_ea "effort" "level")
used_pct=$(_e "used_percentage")
five_h_pct=$(_ea "five_hour" "used_percentage")
five_h_reset=$(_ea "five_hour" "resets_at")
seven_d_pct=$(_ea "seven_day" "used_percentage")
seven_d_reset=$(_ea "seven_day" "resets_at")
total_cost=$(_e "total_cost_usd")

[ -z "$five_h_pct" ] && five_h_pct=0; [ -z "$seven_d_pct" ] && seven_d_pct=0
ui=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
fi=$(printf "%.0f" "$five_h_pct" 2>/dev/null || echo 0)
si=$(printf "%.0f" "$seven_d_pct" 2>/dev/null || echo 0)

# ===================================================
# Colors
# ===================================================
R='\033[0m'; B='\033[1m'; BK='\033[5m'; D='\033[2m'
CY='\033[36m'; GN='\033[32m'; YL='\033[33m'; RD='\033[31m'
GR='\033[90m'; MG='\033[35m'; BL='\033[34m'; OR='\033[38;5;208m'

_c() { local p=$1; [ "$p" -ge 80 ] 2>/dev/null && echo "$RD" && return; [ "$p" -ge 50 ] 2>/dev/null && echo "$YL" && return; echo "$GN"; }

# ===================================================
# Block bar with 1/8 precision
# ===================================================
_bar() {
    local pct=$1 w=${2:-$BAR_WIDTH}

    local fc="" ec=""
    case "$BAR_STYLE" in
        dots)      fc="●"; ec="○" ;;
        squares)   fc="■"; ec="□" ;;
        lines)     fc="━"; ec="─" ;;
        triangles) fc="▰"; ec="▱" ;;
        ascii)     fc="#"; ec="." ;;
        *)         fc="$BAR_FILL"; ec="$BAR_EMPTY" ;;
    esac

    local n=$(( pct * w / 100 ))
    [ "$n" -gt "$w" ] && n=$w
    local m=$(( w - n ))
    local bar=""
    for ((i=0;i<n;i++)); do bar+="$fc"; done
    for ((i=0;i<m;i++)); do bar+="$ec"; done
    echo "$bar"
}

_fmt_time() {
    local s=$1 fmt=$2
    [ "$s" -le 0 ] 2>/dev/null && echo "now" && return
    if [ "$fmt" = "hm" ]; then
        echo "$(( s/3600 ))h $(( s%3600/60 ))m"
    else
        echo "$(( s/86400 ))d $(( s%86400/3600 ))h $(( s%3600/60 ))m"
    fi
}

# Estimate remaining time: how long until limit is exhausted at current rate
# Uses reset timestamp to derive elapsed time within the window
_remain() {
    local reset_ts=$1 pct=$2 fmt=$3
    [ -z "$pct" ] || [ "$pct" -le 0 ] 2>/dev/null && return
    [ -z "$reset_ts" ] || [ "$reset_ts" -le 0 ] 2>/dev/null && return
    local now=$NOW  # reuse top-level
    local remain_pct=$(( 100 - pct ))
    # elapsed within window = window_size - time_until_reset
    # For 5h window: window = 18000s, for 7d: 604800s
    # But simpler: remaining = elapsed * remain% / used%
    # elapsed from reset: we don't know window start, use session duration as fallback
    local total_dur
    total_dur=$(_e "total_duration_ms")
    [ -z "$total_dur" ] || [ "$total_dur" -le 0 ] 2>/dev/null && return
    local elapsed=$(( total_dur / 1000 ))
    local remain_sec=$(( elapsed * remain_pct / pct ))
    _fmt_time "$remain_sec" "$fmt"
}


# Git
gb=""; command -v git >/dev/null 2>&1 && [ -d "$cwd" ] && gb=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
# Short path: last 2 segments (bash builtins only)
_cwd="${cwd//\\//}"
IFS='/' read -ra _pp <<< "$_cwd"
_pn=${#_pp[@]}
if [ "$_pn" -gt 2 ]; then
    sp="${_pp[$((_pn-2))]}/${_pp[$((_pn-1))]}"
else
    sp="$_cwd"
fi

# ===================================================
# Line 1
# ===================================================
# Language labels
case "$LANGUAGE" in
    ko) L_CTX="컨텍스트"; L_5H="5시간"; L_7D="7일"; L_SVC="서비스"; L_SET="설정" ;;
    ja) L_CTX="ctx"; L_5H="5h"; L_7D="7d"; L_SVC="svc"; L_SET="設定" ;;
    zh) L_CTX="上下文"; L_5H="5小时"; L_7D="7天"; L_SVC="服务"; L_SET="设置" ;;
    fr) L_CTX="ctx"; L_5H="5h"; L_7D="7j"; L_SVC="svc"; L_SET="config" ;;
    de) L_CTX="ctx"; L_5H="5h"; L_7D="7T"; L_SVC="svc"; L_SET="Einst." ;;
    ru) L_CTX="ctx"; L_5H="5ч"; L_7D="7д"; L_SVC="svc"; L_SET="настр." ;;
    *)  L_CTX="ctx"; L_5H="5h"; L_7D="7d"; L_SVC="svc"; L_SET="settings" ;;
esac

ctx_color=$(_c $ui); five_color=$(_c $fi); seven_color=$(_c $si)

sep=""
if [ "$SHOW_MODEL" = "true" ]; then
    printf "${CY}${B}%s${R}" "$model"
    ctx_size_raw=$(_e "context_window_size")
    # Prefer thinking.enabled from JSON. Fallback to ctx_size > 200k for older Claude Code versions.
    if [ "$thinking_enabled" = "true" ]; then
        printf " ${GN}thinking:on${R}"
    elif [ "$thinking_enabled" = "false" ]; then
        printf " ${GR}thinking:off${R}"
    elif [ "$exceeds_200k" = "true" ] || [ "${ctx_size_raw:-0}" -gt 200000 ] 2>/dev/null; then
        printf " ${GN}thinking:on${R}"
    else
        printf " ${GR}thinking:off${R}"
    fi
    # Effort level: low/medium/high/xhigh/max
    if [ "$SHOW_EFFORT" = "true" ] && [ -n "$effort_level" ]; then
        case "$effort_level" in
            max|xhigh) ec="$RD" ;;
            high)      ec="$YL" ;;
            *)         ec="$GN" ;;
        esac
        printf " ${ec}effort:%s${R}" "$effort_level"
    fi
    # Fast mode
    if [ "$SHOW_FAST" = "true" ] && [ "$fast_mode" = "true" ]; then
        printf " ${YL}fast:on${R}"
    fi
    sep=" ${GR}|${R} "
fi
if [ "$SHOW_PATH" = "true" ]; then
    printf "%b${BL}%s${R}" "$sep" "$sp"
    [ "$SHOW_GIT_BRANCH" = "true" ] && [ -n "$gb" ] && printf "${GR}@${R}${MG}%s${R}" "$gb"
    sep=" ${GR}|${R} "
fi
if [ "$SHOW_CONTEXT" = "true" ]; then
    ctx_size=$(_e "context_window_size")
    ctx_used=$(( ctx_size * ui / 100 ))
    # Format used tokens as k or M
    if [ "$ctx_used" -ge 1000000 ] 2>/dev/null; then
        ctx_used_fmt="$(( ctx_used / 1000000 )).$(( ctx_used % 1000000 / 100000 ))M"
    elif [ "$ctx_used" -ge 1000 ] 2>/dev/null; then
        ctx_used_fmt="$(( ctx_used / 1000 ))k"
    else
        ctx_used_fmt="$ctx_used"
    fi
    if [ "$ctx_size" -ge 1000000 ] 2>/dev/null; then
        ctx_total_fmt="$(( ctx_size / 1000000 )).$(( ctx_size % 1000000 / 100000 ))M"
    else
        ctx_total_fmt="$(( ctx_size / 1000 ))k"
    fi
    printf "%b${L_CTX} ${ctx_color}%s${R} ${ctx_color}%d%%${R} ${GR}%s/%s${R}" "$sep" "$(_bar $ui)" "$ui" "$ctx_used_fmt" "$ctx_total_fmt"
    sep=" ${GR}|${R} "
fi
# Only show rate limits when Claude Code actually sends them (resets_at present and > 0).
# Fast mode and some session states omit rate_limits entirely.
if [ "$SHOW_5H_LIMIT" = "true" ] && [ -n "$five_h_reset" ] && [ "$five_h_reset" -gt 0 ] 2>/dev/null; then
    printf "%b${L_5H} ${five_color}%s${R} ${five_color}%d%%${R}" "$sep" "$(_bar $fi)" "$fi"
    d5=$(( five_h_reset - $NOW ))
    [ "$d5" -gt 0 ] && printf " ${GR}%s${R}" "$(_fmt_time $d5 hm)" || printf " ${GR}now${R}"
    sep=" ${GR}|${R} "
fi
if [ "$SHOW_7D_LIMIT" = "true" ] && [ -n "$seven_d_reset" ] && [ "$seven_d_reset" -gt 0 ] 2>/dev/null; then
    printf "%b${L_7D} ${seven_color}%s${R} ${seven_color}%d%%${R}" "$sep" "$(_bar $si)" "$si"
    d7=$(( seven_d_reset - $NOW ))
    [ "$d7" -gt 0 ] && printf " ${GR}%s${R}" "$(_fmt_time $d7 dhm)" || printf " ${GR}now${R}"
    sep=" ${GR}|${R} "
fi
# Cost: only shown for API key users (not Claude Max subscription)
[ "$SHOW_COST" = "true" ] && [ -n "$total_cost" ] && [ "$total_cost" != "null" ] && [ "$total_cost" != "0" ] && printf "%b${GR}\$%.2f${R}" "$sep" "$total_cost" 2>/dev/null && sep=" ${GR}|${R} "
if [ "$SHOW_COMMANDS" = "true" ] || [ "$SHOW_VERSION" = "true" ]; then
    hint=""
    ver=""; cmd=""
    [ "$SHOW_VERSION" = "true" ] && ver="v1.0.30"
    [ "$SHOW_COMMANDS" = "true" ] && cmd="${L_SET}: npx cc-statusbar"
    printf "%b" "$sep"
    [ -n "$ver" ] && printf "${GR}%s${R}" "$ver"
    [ -n "$ver" ] && [ -n "$cmd" ] && printf " ${GR}|${R} "
    [ -n "$cmd" ] && printf "${D}${GR}%s${R}" "$cmd"
fi

# ===================================================
# DevLauncher (same line, fully async, cache only)
# ===================================================
CACHE="/tmp/.devlauncher-status-cache"

# Find DevLauncher
DL=""
for c in "/mnt/c/Users/$USER/DevLauncher.ps1" "/c/Users/$USER/DevLauncher.ps1" "$HOME/DevLauncher.ps1" "/mnt/c/Users/$USERNAME/DevLauncher.ps1" "/c/Users/$USERNAME/DevLauncher.ps1"; do
    [ -f "$c" ] && DL="$c" && break
done
[ -z "$DL" ] && exit 0

# Async refresh with cache (TTL 5s). Never blocks the status line:
# render always reads the cache, and a stale cache only triggers a detached
# background refresh for the NEXT render. An inline `powershell.exe status`
# costs ~4s from WSL, which makes Claude Code drop the whole status line, so
# the refresh must run detached (fds to /dev/null so it doesn't hold the pipe).
now=$NOW
need_refresh=true
[ -f "$CACHE" ] && cached_at=$(head -1 "$CACHE" 2>/dev/null) && [ $(( now - ${cached_at:-0} )) -lt 5 ] 2>/dev/null && need_refresh=false

if [ "$need_refresh" = "true" ] && [ ! -f "$CACHE.lock" ]; then
    tmp="${DL#/mnt}"; drive="${tmp:1:1}"; rest="${tmp:2}"
    ws=$(printf '%s:%s' "${drive^}" "$rest" | tr '/' '\\' 2>/dev/null)
    # Detached background refresh; lock prevents piling up powershell processes.
    ( : > "$CACHE.lock"
      r=$(timeout 5 powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ws" status 2>/dev/null | tr -d '\r')
      [ -n "$r" ] && { echo "$now"; echo "$r"; } > "$CACHE"
      rm -f "$CACHE.lock"
    ) </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null
fi

# Read from cache
raw=""
[ -f "$CACHE" ] && raw=$(tail -n +2 "$CACHE")

# Render services — extract status by keyword match (emoji-safe)
parts=""
spin=$([ $(( NOW % 2 )) -eq 0 ] && echo "●" || echo "○")
while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Extract name and :port using bash regex (emoji-safe, no subprocess)
    [[ "$line" =~ ([A-Za-z0-9_-]+)[[:space:]]+(:[0-9]+) ]] || continue
    np="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    if [[ "$line" == *Running* ]]; then
        parts="${parts:+$parts ${GR}|${R} }${GN}●${R} ${GN}${B}${np}${R}"
    elif [[ "$line" == *Starting* ]]; then
        parts="${parts:+$parts ${GR}|${R} }${YL}${spin}${R} ${YL}${B}${np}${R}"
    elif [[ "$line" == *Error* ]]; then
        parts="${parts:+$parts ${GR}|${R} }${BK}${RD}✖${R} ${RD}${B}${np}${R}"
    elif [[ "$line" == *Stopped* ]]; then
        parts="${parts:+$parts ${GR}|${R} }${GR}● ${np}${R}"
    fi
done <<< "$raw"
if [ -n "$parts" ]; then
    printf "\n${GR}${L_SVC}${R} $parts"
fi
printf "\n"

# ===================================================
# Auto-update (daily, silent, background)
# ===================================================
_CC_UPDATE_FLAG="$HOME/.claude/.cc-last-check"
_need_check=true
if [ -f "$_CC_UPDATE_FLAG" ]; then
    _last=$(cat "$_CC_UPDATE_FLAG" 2>/dev/null)
    [ $(( NOW - ${_last:-0} )) -lt 86400 ] 2>/dev/null && _need_check=false
fi
if [ "$_need_check" = "true" ] && command -v npm >/dev/null 2>&1; then
    echo "$NOW" > "$_CC_UPDATE_FLAG" 2>/dev/null
    (nohup sh -c 'npm install -g cc-statusbar@latest >/dev/null 2>&1 && cc-statusbar install >/dev/null 2>&1' >/dev/null 2>&1 </dev/null &) >/dev/null 2>&1
fi
