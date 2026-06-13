#!/usr/bin/env bash
# Statusliner statusline.
# Reads the Claude Code statusline JSON on stdin and prints a single status line:
#   model | effort | ctx | <gate> | folder | branch | <caveman>
# The signature segment is the quality-gate marker: when this project's
# PostToolUse gate is failing, it shows a loud red marker so you can't miss it.
# (Lights up only when a gate writer — e.g. lang-quality/claudness — is present.)
#
# Wire it up (settings.json) after the SessionStart hook has symlinked it to a
# stable path:
#   "statusLine": { "type": "command",
#                   "command": "bash ~/.claude/statusliner/statusline.sh" }
#
# Every field is read defensively — the schema marks effort/used_percentage/etc.
# as absent before the first API call, after /compact, or on models that lack
# them. Missing jq degrades to a minimal line rather than erroring.

input=$(cat 2>/dev/null || echo '{}')

# --- Colors (ANSI) ---
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'; BLUE=$'\033[34m'; RED=$'\033[31m'
DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

# Without jq we cannot parse the payload — emit nothing rather than garbage.
command -v jq >/dev/null 2>&1 || { printf 'claudness'; exit 0; }

# One jq pass extracts every field — a statusline renders on every prompt, so
# six separate jq spawns would be wasteful. One value per line (not @tsv: tab is
# IFS-whitespace, so `read` would collapse empty fields and shift everything);
# the per-field `read` preserves empty lines. bash-3.2-safe (no mapfile).
{
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r cwd
  IFS= read -r ctx_size
  IFS= read -r ctx_used
  IFS= read -r ctx_pct
} < <(printf '%s' "$input" | jq -r '
  (.model.display_name // "Claude"),
  (.effort.level // ""),
  (.workspace.current_dir // .cwd // ""),
  (.context_window.context_window_size // 0),
  (.context_window.total_input_tokens // 0),
  (.context_window.used_percentage // "")' 2>/dev/null)
[ -n "$model" ] || model="Claude"
[ -n "$ctx_size" ] || ctx_size=0
[ -n "$ctx_used" ] || ctx_used=0

format_tokens() {
  local n="$1"
  # Guard non-numeric input (a future schema change could emit a string) so the
  # arithmetic and printf below stay safe on the per-render hot path.
  [[ "$n" =~ ^[0-9]+$ ]] || { printf '0'; return; }
  if [ "$n" -ge 1000 ]; then printf '%dk' "$(( n / 1000 ))"; else printf '%d' "$n"; fi
}
ctx_used_fmt=$(format_tokens "$ctx_used")
ctx_size_fmt=$(format_tokens "$ctx_size")
if [[ "$ctx_pct" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  tokens_seg="${ctx_used_fmt}/${ctx_size_fmt} ($(printf '%.0f%%' "$ctx_pct"))"
else
  tokens_seg="${ctx_used_fmt}/${ctx_size_fmt}"
fi

# --- Quality gate (claudness): red marker only when failing ---
# Resolve the gate file at the git root (where the lang-quality hooks write it
# via $PROJECT_ROOT), not at $cwd — a subdir-launched session or worktree has
# cwd != project root, which would silently miss the marker.
gate_seg=""
if [ -n "$cwd" ]; then
  _gate_root=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
  gate_file="${_gate_root:-$cwd}/.claude/tmp/quality-gate-status.json"
  if [ -f "$gate_file" ]; then
    gate_status=$(jq -r '.status // ""' "$gate_file" 2>/dev/null)
    [ "$gate_status" = "failing" ] && gate_seg="${BOLD}${RED}✗ gate:failing${RESET}"
  fi
fi

# --- Git branch + folder ---
branch=""; folder=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  folder=$(basename "$cwd")
fi

# --- Caveman mode (lights up when the caveman plugin is installed) ---
# Read the flag file written by caveman-activate; refuse symlinks, cap the read,
# strip to a safe charset, whitelist known modes.
caveman_seg=""
caveman_flag="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [ -f "$caveman_flag" ] && [ ! -L "$caveman_flag" ]; then
  caveman_mode=$(head -c 64 "$caveman_flag" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  case "$caveman_mode" in
    off) ;;
    "") caveman_seg="${BOLD}${GREEN}[CAVEMAN]${RESET}" ;;
    full|lite|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
      caveman_seg="${BOLD}${GREEN}[CAVEMAN:$(printf '%s' "$caveman_mode" | tr '[:lower:]' '[:upper:]')]${RESET}" ;;
  esac
fi

# --- Assemble ---
sep="${DIM} | ${RESET}"
line="${CYAN}${model}${RESET}"
[ -n "$effort" ] && [ "$effort" != "null" ] && line="${line}${sep}${YELLOW}effort:${effort}${RESET}"
line="${line}${sep}${MAGENTA}ctx:${tokens_seg}${RESET}"
[ -n "$gate_seg" ] && line="${line}${sep}${gate_seg}"
[ -n "$folder" ] && line="${line}${sep}${BOLD}${folder}${RESET}"
[ -n "$branch" ] && line="${line}${sep}${BLUE}${branch}${RESET}"
[ -n "$caveman_seg" ] && line="${line}${sep}${caveman_seg}"

printf '%s' "$line"
