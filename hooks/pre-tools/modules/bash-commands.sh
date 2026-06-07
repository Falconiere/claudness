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

# tokens_contain_rule <rule> <token...>
# Returns 0 if `tokens[0]` matches the first rule token AND every subsequent
# rule token appears as a distinct later argv token. Substring matching is
# never used here — that was the source of false-positives on commit messages
# like `git commit -m "fix cargo test failure"`.
tokens_contain_rule() {
  local rule="$1"; shift
  local -a tokens=("$@")
  local -a rule_tokens
  # shellcheck disable=SC2206  # intentional word-split on whitespace
  rule_tokens=($rule)
  [ ${#rule_tokens[@]} -eq 0 ] && return 1
  [ "${tokens[0]:-}" = "${rule_tokens[0]}" ] || return 1
  local i j want found
  for ((i=1; i<${#rule_tokens[@]}; i++)); do
    want="${rule_tokens[$i]}"
    found=0
    for ((j=1; j<${#tokens[@]}; j++)); do
      if [ "${tokens[$j]}" = "$want" ]; then
        found=1
        break
      fi
    done
    [ "$found" -eq 0 ] && return 1
  done
  return 0
}

# matches_deny <command> <denylist>
# Returns 0 (match) if any deny rule fires against the command, else 1.
# Multi-token rules use argv-aware matching only (no substring fallback);
# single-token rules require exact argv equality with `tokens[0]` OR substring
# anywhere on the command (kept for back-compat with bare-name rules).
matches_deny() {
  local cmd="$1"
  local denylist="$2"
  local rule tokens
  mapfile -t tokens < <(bash_tokenize "$cmd")
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if [[ "$rule" == *" "* ]]; then
      if tokens_contain_rule "$rule" "${tokens[@]}"; then
        echo "$rule"
        return 0
      fi
    else
      # Single-token rule: substring match against the command. Most bare-name
      # rules (`biome`, `cargo test` style) are matched here.
      if [[ "$cmd" == *"$rule"* ]]; then
        echo "$rule"
        return 0
      fi
    fi
  done <<< "$denylist"
  return 1
}

# matches_allow <command> <allowlist>
# Returns 0 if any allow rule matches. Multi-token rules are argv-aware
# (same shape as deny); single-token rules substring-match.
matches_allow() {
  local cmd="$1"
  local allowlist="$2"
  local rule tokens
  mapfile -t tokens < <(bash_tokenize "$cmd")
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    if [[ "$rule" == *" "* ]]; then
      if tokens_contain_rule "$rule" "${tokens[@]}"; then
        return 0
      fi
    else
      if [[ "$cmd" == *"$rule"* ]]; then
        return 0
      fi
    fi
  done <<< "$allowlist"
  return 1
}

# Public entry — invokable when the script is sourced (used by tests).
#
# Order matters: deny is consulted FIRST. The old order (allow then deny)
# meant an allowlist entry of `node` would bypass the `node -e` security
# deny — substring evasion. Allowlist is now an explicit override on top of
# deny, intended for project-specific exemptions.
bash_commands_decide() {
  local cmd="$1"
  local allowlist denylist hit
  allowlist=$(read_list "$SETTINGS_DIR/bash-allowlist.txt")
  denylist=$(read_list "$SETTINGS_DIR/bash-denylist.txt")

  # Strip heredoc bodies so we only check actual commands, not prose in commit messages.
  cmd=$(echo "$cmd" | sed '/<<['"'"'"]*EOF['"'"'"]*$/,/^EOF$/d')

  if hit=$(matches_deny "$cmd" "$denylist"); then
    echo "deny:$hit"
    return 0
  fi

  if matches_allow "$cmd" "$allowlist"; then
    echo "allow"
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
