#!/usr/bin/env bash
# Shared module dispatcher for the pre-tools / post-tools hook entrypoints.
# Source via:   . "${BASH_SOURCE%/*}/../lib/dispatch.sh"
#
# Public API:
#   claudness_dispatch_modules MODULES_DIR EVENT_NAME
#     Runs every MODULES_DIR/*.sh in lexical order, feeding each the exported
#     `input` variable (raw hook JSON) on stdin. EVENT_NAME is "PreToolUse"
#     or "PostToolUse" and selects the decision semantics.
#
# Output discipline:
#   - PreToolUse: a module emitting `hookSpecificOutput.permissionDecision ==
#     "deny"` is authoritative — its output is emitted immediately and
#     dispatch stops (security wins; a deny must not be suppressed by an
#     advisory).
#   - PostToolUse: a module emitting top-level `decision == "block"` is
#     authoritative — its output is emitted immediately and dispatch stops.
#     (PostToolUse has no permissionDecision; that is PreToolUse-only.)
#   - Otherwise every module's advisory `hookSpecificOutput.additionalContext`
#     (and top-level `systemMessage`) is collected and merged into ONE final
#     JSON object emitted at the end.
#
# Module exit-code semantics (deliberate — the old `echo "$input" | bash`
# pipeline masked these entirely):
#   - 0: stdout handled per the discipline above; stderr discarded.
#   - 2: the Claude Code "block via exit code" convention — the module's
#     stderr is forwarded and the dispatcher returns 2, so the entrypoint
#     exits 2 and Claude Code sees the block plus the stderr feedback.
#     Remaining modules are skipped.
#   - any other non-zero: treated as a module failure — one warning line on
#     stderr (visible in claude --debug), the module's possibly-partial
#     stdout is DISCARDED, and dispatch continues with the next module.

claudness_dispatch_modules() {
  local modules_dir="$1" event="$2"
  local script result rc err_file decision ctx msg c
  local contexts=() messages=()

  err_file=$(mktemp "${TMPDIR:-/tmp}/claudness-dispatch.XXXXXX") || return 0

  for script in "$modules_dir"/*.sh; do
    [[ ! -f "$script" ]] && continue

    rc=0
    # Modules are always executed with `bash` regardless of their shebang. This
    # is fine today because only *.sh files are globbed above; a future non-bash
    # module would require this invocation to honor the script's interpreter.
    # shellcheck disable=SC2154 # $input is exported by the sourcing entrypoint.
    result=$(bash "$script" <<<"$input" 2>"$err_file") || rc=$?

    if [[ $rc -eq 2 ]]; then
      # Deliberate hard block: propagate stderr + exit code 2.
      cat "$err_file" >&2
      rm -f "$err_file"
      return 2
    fi
    if [[ $rc -ne 0 ]]; then
      # Module failure: make it visible, drop its partial output, keep going.
      printf 'claudness-dispatch: module %s exited %d; output skipped\n' \
        "$(basename "$script")" "$rc" >&2
      continue
    fi
    [[ -z "$result" ]] && continue

    case "$event" in
      PreToolUse)
        decision=$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$result" 2>/dev/null)
        if [[ "$decision" == "deny" ]]; then
          printf '%s\n' "$result"
          rm -f "$err_file"
          return 0
        fi
        ;;
      PostToolUse)
        decision=$(jq -r '.decision // empty' <<<"$result" 2>/dev/null)
        if [[ "$decision" == "block" ]]; then
          printf '%s\n' "$result"
          rm -f "$err_file"
          return 0
        fi
        ;;
    esac

    ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$result" 2>/dev/null)
    [[ -n "$ctx" ]] && contexts+=("$ctx")
    msg=$(jq -r '.systemMessage // empty' <<<"$result" 2>/dev/null)
    [[ -n "$msg" ]] && messages+=("$msg")
  done
  rm -f "$err_file"

  local merged_ctx="" merged_msg=""
  if [[ ${#contexts[@]} -gt 0 ]]; then
    for c in "${contexts[@]}"; do
      if [[ -z "$merged_ctx" ]]; then
        merged_ctx="$c"
      else
        merged_ctx="${merged_ctx}"$'\n\n'"${c}"
      fi
    done
  fi
  if [[ ${#messages[@]} -gt 0 ]]; then
    for c in "${messages[@]}"; do
      if [[ -z "$merged_msg" ]]; then
        merged_msg="$c"
      else
        merged_msg="${merged_msg}"$'\n\n'"${c}"
      fi
    done
  fi

  if [[ -n "$merged_ctx" || -n "$merged_msg" ]]; then
    jq -n --arg ctx "$merged_ctx" --arg msg "$merged_msg" --arg ev "$event" '
      {}
      | (if $ctx != "" then .hookSpecificOutput = { hookEventName: $ev, additionalContext: $ctx } else . end)
      | (if $msg != "" then .systemMessage = $msg else . end)
    '
  fi

  return 0
}
