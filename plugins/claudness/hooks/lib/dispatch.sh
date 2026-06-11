#!/usr/bin/env bash
# Shared module dispatcher for the pre-tools / post-tools hook entrypoints.
# Source via:   . "${BASH_SOURCE%/*}/../lib/dispatch.sh"
#
# Public API:
#   claudness_dispatch_modules MODULES_DIR EVENT_NAME [REGISTRY_DIR...]
#     Runs every MODULES_DIR/*.sh in lexical order, then every *.sh in each
#     REGISTRY_DIR (built-in modules first), feeding each the exported `input`
#     variable (raw hook JSON) on stdin. EVENT_NAME is "PreToolUse" or
#     "PostToolUse" and selects the decision semantics.
#     Registry modules (anything outside MODULES_DIR) MUST be namespaced
#     "<plugin-spec>__<name>.sh" (specs must not contain "__"; "__" instead of
#     "." so specs like "name@git.example.com" parse unambiguously) and run
#     only when `claudness_plugin_active <plugin-spec>` succeeds. A registry
#     file that is not namespaced, or dispatched without that helper sourced,
#     is SKIPPED — fail closed, so a partial-sourcing bug degrades to "do
#     less" instead of running ungated modules. Built-in MODULES_DIR scripts
#     are never gated. The plugin-active lookup is memoized per spec within
#     one dispatch call.
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
  # With <2 args `shift 2` would not shift at all, leaving $1 to be re-globbed
  # as a registry dir and every built-in module run twice.
  [[ $# -lt 2 ]] && return 0
  local modules_dir="$1" event="$2"; shift 2
  local registry_dirs=("$@")
  local script result rc err_file decision ctx msg c base plugin
  local contexts=() messages=()
  # Per-dispatch memo of plugin-active lookups (space-delimited spec lists;
  # plain strings, not associative arrays, for bash 3.2 compatibility).
  local active_specs=" " inactive_specs=" "

  # Constant for the whole dispatch; resolved once instead of per module.
  local plugin_helper_ok=0
  declare -F claudness_plugin_active >/dev/null 2>&1 && plugin_helper_ok=1

  err_file=$(mktemp "${TMPDIR:-/tmp}/claudness-dispatch.XXXXXX") || return 0

  # Ordered module list: built-in dir first, then each registry dir.
  local scripts=()
  for script in "$modules_dir"/*.sh; do
    [[ -f "$script" ]] && scripts+=("$script")
  done
  local rdir
  for rdir in "${registry_dirs[@]}"; do
    [[ -d "$rdir" ]] || continue
    for script in "$rdir"/*.sh; do
      [[ -f "$script" ]] && scripts+=("$script")
    done
  done

  for script in "${scripts[@]}"; do
    [[ ! -f "$script" ]] && continue

    # Anything outside MODULES_DIR is a registry module and MUST satisfy the
    # gating contract; violations are skipped, never run. Built-ins are
    # globbed directly from $modules_dir, so "registry" means the script's
    # dirname is not EXACTLY $modules_dir — a prefix match would let a
    # registry dir nested under the modules tree masquerade as built-in (and
    # an empty modules_dir prefix would match every absolute path).
    base=$(basename "$script")
    if [[ -z "$modules_dir" || "${script%/*}" != "$modules_dir" ]]; then
      # The spec must be non-empty ("__foo.sh") and whitespace-free: the
      # memo lists are space-delimited, so a spec containing whitespace
      # could substring-collide with another spec's memo entry.
      plugin="${base%%__*}"
      if [[ "$base" != *__*.sh || -z "$plugin" || "$plugin" == *[[:space:]]* ]]; then
        printf 'claudness-dispatch: registry module %s lacks <plugin-spec>__<name>.sh namespace; skipped\n' \
          "$base" >&2
        continue
      fi
      if [[ $plugin_helper_ok -ne 1 ]]; then
        printf 'claudness-dispatch: claudness_plugin_active not sourced; registry module %s skipped\n' \
          "$base" >&2
        continue
      fi
      # Resolve each distinct spec at most once per dispatch (hot path: one
      # jq per plugin instead of one per module).
      if [[ "$active_specs" != *" $plugin "* ]]; then
        [[ "$inactive_specs" == *" $plugin "* ]] && continue
        if ! claudness_plugin_active "$plugin"; then
          inactive_specs="${inactive_specs}${plugin} "
          continue
        fi
        active_specs="${active_specs}${plugin} "
      fi
    fi

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
