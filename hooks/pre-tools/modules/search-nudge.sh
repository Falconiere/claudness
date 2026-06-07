#!/bin/bash
# Pre-tool check: Enforce search hierarchy
#   1. ast-grep (structural / AST patterns) — first on code files
#   2. Grep    (exact literals on non-code files, or after ast-grep returned nothing)
#
# Grep on code files is nudged toward ast-grep when patterns look structural.
# Bash grep/rg is always nudged toward proper tools.
#
# Inputs (from parent dispatcher pre-tools/mod.sh, via `export`):
#   $tool_name - name of the tool being invoked
#   $input     - raw JSON payload on stdin

: "${tool_name:=}"
: "${input:=}"

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

HAS_ASTGREP="$(detect_ast_grep)"

# ── Structural pattern keywords (shared) ────────────────────────────────────
STRUCT_RE='(^|\s)(fn |impl |async fn|async |class |function |struct |trait |interface |type |pub (fn|struct|enum|trait|mod|type|async)|export (function|class|interface|type|const|default)|enum |mod |const fn|#\[derive|#\[cfg|#\[test|@Component|@Injectable|@Module|=>|-> Result|-> impl|dyn |Box<|Arc<|Vec<|Option<|where |for .*in )'

# ── Non-code file globs (Grep is sole tool for these) ──────────────────────
NON_CODE_GLOB_RE='\*\.(toml|md|markdown|json|jsonc|yaml|yml|txt|env|sql|sh|bash|zsh|fish|lock|cfg|ini|conf|csv|xml|html|svg|css|graphql|gql|proto|makefile|dockerfile)'
NON_CODE_TYPE_RE='^(toml|json|yaml|md|markdown|html|css|sql|sh|bash|make|docker|config|xml|csv|graphql|proto)$'

# ── Non-code path segments (hooks, docs, config dirs) ──────────────────────
NON_CODE_PATH_RE='(\.claude/|docs/|\.github/|infra/|scripts/|\.config|Makefile|Dockerfile|Cargo\.toml|package\.json|tsconfig)'

# ── Grep tool ───────────────────────────────────────────────────────────────
if [[ "$tool_name" == "Grep" ]]; then
  pattern=$(echo "$input" | jq -r '.tool_input.pattern // ""')
  glob_filter=$(echo "$input" | jq -r '.tool_input.glob // ""')
  type_filter=$(echo "$input" | jq -r '.tool_input.type // ""')
  path_filter=$(echo "$input" | jq -r '.tool_input.path // ""')

  # ── ALLOW: Non-code file types (Grep is sole tool — ast-grep can't do these)
  if [[ -n "$glob_filter" ]] && echo "$glob_filter" | grep -qiE "$NON_CODE_GLOB_RE"; then
    exit 0
  fi
  if [[ -n "$type_filter" ]] && echo "$type_filter" | grep -qiE "$NON_CODE_TYPE_RE"; then
    exit 0
  fi
  if [[ -n "$path_filter" ]] && echo "$path_filter" | grep -qiE "$NON_CODE_PATH_RE"; then
    exit 0
  fi

  # ── STOP: Structural code pattern → ast-grep (only when installed)
  if echo "$pattern" | grep -qE "$STRUCT_RE"; then
    if [ "$HAS_ASTGREP" = "ast-grep" ]; then
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": "STOP: Structural code pattern detected. Use ast-grep: `ast-grep run --pattern \"your pattern\" --lang rust/typescript .` AST-aware matching is far more accurate. Grep is for exact literals on non-code files, or after ast-grep returned nothing."
        }
      }'
    else
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": "WARN: structural code pattern detected but ast-grep is not installed. Falling back to Grep — expect false positives. Install ast-grep (`cargo install ast-grep` or `brew install ast-grep`) for AST-aware matching."
        }
      }'
    fi
    exit 0
  fi

  exit 0
fi

# ── Bash tool: catch grep/rg being used for code search ────────────────────
if [[ "$tool_name" == "Bash" || "$tool_name" == "Shell" ]]; then
  command=$(echo "$input" | jq -r '.tool_input.command // ""')

  # Strip heredoc bodies
  cmd_only=$(printf '%s\n' "$command" | strip_heredocs)

  # Catch grep/rg invocations
  if echo "$cmd_only" | grep -qE '(^|\s|&&|\|\||;)(grep|rg|ripgrep)\s'; then
    # Structural patterns → ast-grep (only when installed)
    if echo "$cmd_only" | grep -qE "$STRUCT_RE"; then
      if [ "$HAS_ASTGREP" = "ast-grep" ]; then
        jq -n '{
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": "STOP: grep/rg for structural code search. Use ast-grep: `ast-grep run --pattern \"your pattern\" --lang rust/typescript .` grep/rg is for piping command output or non-code files."
          }
        }'
      else
        jq -n '{
          "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": "WARN: structural grep/rg detected but ast-grep is not installed. Proceeding with grep/rg — expect false positives. Install ast-grep (`cargo install ast-grep` or `brew install ast-grep`) for AST-aware matching."
          }
        }'
      fi
      exit 0
    fi

    # All other grep/rg → nudge to proper tools (gated on ast-grep availability)
    if [ "$HAS_ASTGREP" = "ast-grep" ]; then
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": "grep/rg in Bash detected. Use ast-grep for structural patterns on code files, Grep tool for exact literals on non-code files. Bash grep/rg only for piping command output."
        }
      }'
    else
      jq -n '{
        "hookSpecificOutput": {
          "hookEventName": "PreToolUse",
          "additionalContext": "grep/rg in Bash detected. Use Grep tool for exact literals on non-code files. Bash grep/rg only for piping command output. (ast-grep not installed — structural matching unavailable.)"
        }
      }'
    fi
    exit 0
  fi

  exit 0
fi

exit 0
