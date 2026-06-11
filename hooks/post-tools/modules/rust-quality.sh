#!/usr/bin/env bash
# Post-tool check: Rust quality rules.
# Project-agnostic: no-op outside Rust projects or when cargo is missing.
# Unsafe-block exemptions for FFI crates come from
# $SETTINGS_DIR/rust-unsafe-exemptions.txt.
#
# Inputs (from parent dispatcher post-tools/mod.sh, via `export`):
#   $tool_name     - name of the tool being invoked
#   $input         - raw JSON payload on stdin
#   $PROJECT_ROOT  - repository root

: "${tool_name:=}"
: "${input:=}"
: "${PROJECT_ROOT:=$(pwd)}"

_claudness_lib="${CLAUDNESS_LIB_DIR:-${BASH_SOURCE%/*}/../../lib}"
# shellcheck source=../../lib/detect.sh
. "$_claudness_lib/detect.sh"

[ "$(detect_rust)" = "rust" ] || exit 0
command -v cargo >/dev/null 2>&1 || exit 0
command -v jq    >/dev/null 2>&1 || exit 0

SETTINGS_DIR=$(detect_settings_dir)
EXEMPTIONS_FILE="$SETTINGS_DIR/rust-unsafe-exemptions.txt"

# read_list is sourced from lib/detect.sh.

fp_from_input=""
if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" || "$tool_name" == "MultiEdit" ]]; then
  fp_from_input=$(echo "$input" | jq -r '.tool_input.path // .tool_input.file_path // .tool_input.target_file // empty' 2>/dev/null || echo "")
fi
FILE_PATH="${CLAUDE_FILE_PATHS:-$fp_from_input}"

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ ! "$FILE_PATH" =~ \.rs$ ]] && exit 0

MESSAGES=""
add_error() {
  MESSAGES="${MESSAGES}${1}\n"
}

LINE_COUNT=$(wc -l < "$FILE_PATH" | tr -d ' ')
if [[ "$LINE_COUNT" -gt 500 ]]; then
  add_error "File exceeds 500-line limit: $FILE_PATH ($LINE_COUNT lines) — split into submodules"
fi

if [[ "$FILE_PATH" == */src/* ]] && grep -qE '#\[cfg\(test\)\]' "$FILE_PATH" 2>/dev/null; then
  add_error "Inline #[cfg(test)] in $FILE_PATH — tests must live in tests/ directory"
fi

# Forbidden #[allow(...)] / #![allow(...)] / #[expect(...)] / #![expect(...)]
if grep -qE '#!?\[(allow|expect)\(' "$FILE_PATH" 2>/dev/null; then
  add_error "Forbidden #[allow(...)] / #[expect(...)] in $FILE_PATH — remove it and fix the underlying warning. For unsafe_code, override in Cargo.toml [lints.rust]."
fi

# Forbidden unsafe blocks/functions — except for crates listed in the
# exemptions file (FFI crates, sandboxes, etc).
exempt=0
if [ -f "$EXEMPTIONS_FILE" ]; then
  while IFS= read -r crate; do
    [ -z "$crate" ] && continue
    if [[ "$FILE_PATH" == *"$crate"* ]]; then
      exempt=1
      break
    fi
  done <<< "$(read_list "$EXEMPTIONS_FILE")"
fi
if [ "$exempt" -eq 0 ]; then
  if grep -qE '\bunsafe\b\s*(\{|fn )' "$FILE_PATH" 2>/dev/null; then
    add_error "Forbidden unsafe code in $FILE_PATH — refactor to safe alternative. Add crate to settings/rust-unsafe-exemptions.txt if it legitimately needs unsafe (FFI, sandboxing)."
  fi
fi

LONG_RS_FUNCS=$(awk '
  /^[[:space:]]*(pub )?(async )?fn / { start=NR; name=$0 }
  start && /^[[:space:]]*\}/ {
    len=NR-start
    if (len > 50) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_RS_FUNCS" ]]; then
  add_error "Function too long in $FILE_PATH (>50 lines) — extract helpers."
fi

LONG_IMPL=$(awk '
  /^impl / { start=NR; name=$0 }
  start && /^\}/ {
    len=NR-start
    if (len > 200) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_IMPL" ]]; then
  add_error "Impl block too large in $FILE_PATH (>200 lines) — split into trait impls or modules."
fi

# --- Error-handling rules (zero tolerance) ---
# src/ is production code (tests must live in tests/, enforced above), so
# any panic-on-error pattern here is a prod panic.
if [[ "$FILE_PATH" == */src/* ]] && command -v ast-grep >/dev/null 2>&1; then
  # Run ast-grep, capturing output to a variable BEFORE truncating: piping
  # straight into `head` would mask ast-grep's exit code, silently turning
  # tool failures into "no hits". ast-grep is grep-like: 0 = matches,
  # 1 = no matches (or runtime error, with stderr output), >1 = crash.
  ast_err_file="$(mktemp)"
  ast_rc_file="$(mktemp)"
  ast_grep_fail_detail=""
  # ast_scan runs in a command-substitution subshell, so it cannot set parent
  # variables. It communicates the exit code via $ast_rc_file and its stderr
  # via $ast_err_file (both shared temp files the parent can read back).
  ast_scan() {
    local out rc
    out=$(ast-grep --lang rust -p "$1" "$FILE_PATH" 2>"$ast_err_file")
    rc=$?
    printf '%s' "$rc" > "$ast_rc_file"
    if [[ "$rc" -gt 1 || ( "$rc" -eq 1 && -s "$ast_err_file" ) ]]; then
      return 1
    fi
    printf '%s\n' "$out" | head -n "$2"
  }

  # Snapshot the exit code + trimmed stderr of a failing scan into
  # ast_grep_fail_detail so the surfaced message tells the agent WHAT broke,
  # not just THAT it broke. Cap stderr at ~200 chars to avoid leaking output.
  record_ast_fail() {
    local rc stderr_first
    rc=$(cat "$ast_rc_file" 2>/dev/null)
    stderr_first=$(head -n 1 "$ast_err_file" 2>/dev/null | cut -c1-200)
    ast_grep_fail_detail="exit ${rc:-?}${stderr_first:+: $stderr_first}"
  }

  ast_grep_failed=0
  UNWRAP_HITS=$(ast_scan '$E.unwrap()' 5) || { ast_grep_failed=1; record_ast_fail; }
  if [[ -n "$UNWRAP_HITS" ]]; then
    add_error ".unwrap() in $FILE_PATH — use ? or match on Result/Option\n${UNWRAP_HITS}"
  fi
  EXPECT_HITS=$(ast_scan '$E.expect($M)' 5) || { ast_grep_failed=1; record_ast_fail; }
  if [[ -n "$EXPECT_HITS" ]]; then
    add_error ".expect() in $FILE_PATH — use ? or match on Result/Option\n${EXPECT_HITS}"
  fi

  PANIC_HITS=$(ast_scan 'panic!($$$)' 3) || { ast_grep_failed=1; record_ast_fail; }
  TODO_HITS=$(ast_scan 'todo!($$$)' 3) || { ast_grep_failed=1; record_ast_fail; }
  UNIMPL_HITS=$(ast_scan 'unimplemented!($$$)' 3) || { ast_grep_failed=1; record_ast_fail; }
  if [[ -n "$PANIC_HITS" || -n "$TODO_HITS" || -n "$UNIMPL_HITS" ]]; then
    add_error "panic!/todo!/unimplemented! in $FILE_PATH — return a Result instead\n${PANIC_HITS}${TODO_HITS}${UNIMPL_HITS}"
  fi

  rm -f "$ast_err_file" "$ast_rc_file"
  if [[ "$ast_grep_failed" -ne 0 ]]; then
    add_error "ast-grep failed while scanning $FILE_PATH (${ast_grep_fail_detail:-unknown error}) — error-handling rules could not be verified; fix the tool/file and re-edit"
  fi
fi

# --- Output ---

if [[ -n "$MESSAGES" ]]; then
  # Write violation to gate status file for pre-tool blocking (zero tolerance).
  GATE_DIR="$PROJECT_ROOT/.claude/tmp"
  GATE_FILE="$GATE_DIR/quality-gate-status.json"
  mkdir -p "$GATE_DIR"

  jq -n \
    --arg status "failing" \
    --arg reason "Post-edit Rust quality violation(s) detected" \
    --arg file "$FILE_PATH" \
    --arg violations "$MESSAGES" \
    --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      status: $status,
      reason: $reason,
      source: "rust-quality-hook",
      file: $file,
      violations: $violations,
      updatedAt: $updatedAt
    }' > "$GATE_FILE"

  jq -n --arg ctx "$MESSAGES" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("QUALITY VIOLATION — fix before proceeding:\n" + $ctx)
    }
  }'
else
  # Clear gate if this file now passes (only if this hook set it).
  GATE_DIR="$PROJECT_ROOT/.claude/tmp"
  GATE_FILE="$GATE_DIR/quality-gate-status.json"
  if [[ -f "$GATE_FILE" ]]; then
    GATE_SOURCE=$(jq -r '.source // ""' "$GATE_FILE" 2>/dev/null || echo "")
    GATE_FILE_PATH=$(jq -r '.file // ""' "$GATE_FILE" 2>/dev/null || echo "")
    if [[ "$GATE_SOURCE" == "rust-quality-hook" && "$GATE_FILE_PATH" == "$FILE_PATH" ]]; then
      jq -n \
        --arg status "passing" \
        --arg source "rust-quality-hook" \
        --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status: $status, source: $source, updatedAt: $updatedAt}' > "$GATE_FILE"
    fi
  fi
fi

exit 0
