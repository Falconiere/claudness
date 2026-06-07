#!/usr/bin/env bash
# Pre-tool check: Bash/Shell command validation
# Data-driven: loads allow/deny rules from $SETTINGS_DIR/bash-{allow,deny}list.txt.
# Argv-aware: tokenizes the command and matches "<bin> <flag>" deny rules so
# substring evasion is harder (e.g. `node -e "evil"` is rejected even if `node`
# alone is allowed).
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

[[ "$tool_name" != "Bash" && "$tool_name" != "Shell" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

SETTINGS_DIR=$(detect_settings_dir)

read_list() {
  [ -f "$1" ] || return 0
  grep -vE '^\s*(#|$)' "$1"
}

# bash_tokenize <command>
# Tokenize a shell command into argv tokens, respecting single and double quotes.
# Echoes one token per line.
bash_tokenize() {
  local cmd="$1"
  python3 - "$cmd" <<'PY' 2>/dev/null || printf '%s\n' "$cmd"
import shlex, sys
try:
    for tok in shlex.split(sys.argv[1], posix=True):
        print(tok)
except ValueError:
    # Unparseable (unbalanced quote etc) — print whole string so substring rules still fire.
    print(sys.argv[1])
PY
}

# matches_deny <command> <denylist>
# Returns 0 (match) if any deny rule fires against the command, else 1.
matches_deny() {
  local cmd="$1"
  local denylist="$2"
  local rule first rest tokens
  # Pre-tokenize once for argv-aware rules.
  mapfile -t tokens < <(bash_tokenize "$cmd")
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if [[ "$rule" == *" "* ]]; then
      # Multi-token rule: first token must be the first argv token AND each
      # subsequent rule-token must appear later in the argv list.
      first="${rule%% *}"
      rest="${rule#* }"
      if [ "${tokens[0]:-}" = "$first" ]; then
        local ok=1 want
        for want in $rest; do
          local found=0 i
          for ((i=1; i<${#tokens[@]}; i++)); do
            if [ "${tokens[$i]}" = "$want" ]; then
              found=1
              break
            fi
          done
          if [ "$found" -eq 0 ]; then
            ok=0
            break
          fi
        done
        if [ "$ok" = 1 ]; then
          echo "$rule"
          return 0
        fi
      fi
      # Also do a substring fallback for compound tokens like "cargo test"
      # so e.g. `xargs -I_ cargo test` is still caught.
      if [[ "$cmd" == *"$rule"* ]]; then
        echo "$rule"
        return 0
      fi
    else
      # Single-token rule: substring match against the command.
      if [[ "$cmd" == *"$rule"* ]]; then
        echo "$rule"
        return 0
      fi
    fi
  done <<< "$denylist"
  return 1
}

# matches_allow <command> <allowlist>
# Returns 0 if any allow rule matches as a substring, else 1.
matches_allow() {
  local cmd="$1"
  local allowlist="$2"
  local rule
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if [[ "$cmd" == *"$rule"* ]]; then
      return 0
    fi
  done <<< "$allowlist"
  return 1
}

# Public entry — invokable when the script is sourced (used by tests).
bash_commands_decide() {
  local cmd="$1"
  local allowlist denylist hit
  allowlist=$(read_list "$SETTINGS_DIR/bash-allowlist.txt")
  denylist=$(read_list "$SETTINGS_DIR/bash-denylist.txt")

  # Strip heredoc bodies so we only check actual commands, not prose in commit messages.
  cmd=$(echo "$cmd" | sed '/<<['"'"'"]*EOF['"'"'"]*$/,/^EOF$/d')

  if matches_allow "$cmd" "$allowlist"; then
    echo "allow"
    return 0
  fi

  if hit=$(matches_deny "$cmd" "$denylist"); then
    echo "deny:$hit"
    return 0
  fi

  echo "allow"
  return 0
}

# When sourced (tests), return early.
(return 0 2>/dev/null) && return 0

command=$(echo "$input" | jq -r '.tool_input.command // ""')
decision=$(bash_commands_decide "$command")

case "$decision" in
  deny:*)
    rule="${decision#deny:}"
    jq -n --arg rule "$rule" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("Command blocked by deny rule: " + $rule)
      }
    }'
    ;;
esac

exit 0
