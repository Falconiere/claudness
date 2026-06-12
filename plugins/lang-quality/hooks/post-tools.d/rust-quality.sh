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

# Core lib comes from the claudness dispatcher via CLAUDNESS_LIB_DIR (set by
# plugins/claudness/hooks/post-tools/mod.sh before registry dispatch). Outside
# that pipeline there is no relative path to it — fail SOFT: a quality check
# must never break a tool call by erroring.
[ -n "${CLAUDNESS_LIB_DIR:-}" ] && [ -f "$CLAUDNESS_LIB_DIR/detect.sh" ] || exit 0
# shellcheck source=../../../claudness/hooks/lib/detect.sh
. "$CLAUDNESS_LIB_DIR/detect.sh"
# Threshold resolver (defaults + project/native overrides). Soft if absent.
# shellcheck source=../../../claudness/hooks/lib/quality-config.sh
[ -f "$CLAUDNESS_LIB_DIR/quality-config.sh" ] && . "$CLAUDNESS_LIB_DIR/quality-config.sh"
command -v rust_max_file_lines >/dev/null 2>&1 || rust_max_file_lines() { echo "${DEFAULT_RUST_MAX_FILE_LINES:-500}"; }
command -v rust_max_fn_lines   >/dev/null 2>&1 || rust_max_fn_lines()   { echo "${DEFAULT_RUST_MAX_FN_LINES:-50}"; }
command -v rust_max_impl_lines >/dev/null 2>&1 || rust_max_impl_lines() { echo "${DEFAULT_RUST_MAX_IMPL_LINES:-200}"; }
command -v count_code_lines    >/dev/null 2>&1 || count_code_lines()    { wc -l < "$1" | tr -d ' '; }

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

RUST_MAX_FILE=$(rust_max_file_lines)
LINE_COUNT=$(count_code_lines "$FILE_PATH")
if [[ "$LINE_COUNT" -gt "$RUST_MAX_FILE" ]]; then
  _split_hint="split into submodules"
  [ -n "$(detect_clippy)" ] && _split_hint="$_split_hint (clippy enforces complexity here)"
  add_error "File exceeds ${RUST_MAX_FILE}-line limit: $FILE_PATH ($LINE_COUNT code lines, blanks/comments excluded) — $_split_hint"
fi

if [[ "$FILE_PATH" == */src/* ]] && grep -qE '#\[cfg\(test\)\]' "$FILE_PATH" 2>/dev/null; then
  add_error "Inline #[cfg(test)] in $FILE_PATH — tests must live in tests/ directory"
fi

# Test placement: a test-bearing .rs file must live under a tests/ dir, kept
# flat (only fixtures/helpers/common subdirs allowed — common/mod.rs is the
# cargo idiom for shared test helpers).
_is_rust_test=0
case "$(basename "$FILE_PATH")" in
  *_test.rs|*_tests.rs) _is_rust_test=1 ;;
esac
if [[ "$_is_rust_test" -eq 0 ]] \
   && grep -qE '^[[:space:]]*#\[(tokio::|async_std::|actix_rt::|rstest::)?test\b' "$FILE_PATH" 2>/dev/null; then
  _is_rust_test=1
fi
if [[ "$_is_rust_test" -eq 1 ]]; then
  if [[ "$FILE_PATH" != */tests/* ]]; then
    add_error "Rust test file outside tests/: $FILE_PATH — move to a sibling tests/ directory"
  else
    _after_tests="${FILE_PATH##*/tests/}"
    if [[ "$_after_tests" == */* ]]; then
      _subdir="${_after_tests%%/*}"
      if [[ "$_subdir" != "fixtures" && "$_subdir" != "helpers" && "$_subdir" != "common" ]]; then
        add_error "Rust test nested in tests/ subdirectory: $FILE_PATH — keep tests/ flat (only fixtures/helpers/common subdirs allowed)"
      fi
    fi
  fi
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

RUST_MAX_FN=$(rust_max_fn_lines)
LONG_RS_FUNCS=$(awk -v max="$RUST_MAX_FN" '
  /^[[:space:]]*(pub )?(async )?fn / { start=NR; name=$0 }
  start && /^[[:space:]]*\}/ {
    len=NR-start
    if (len > max) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_RS_FUNCS" ]]; then
  add_error "Function too long in $FILE_PATH (>${RUST_MAX_FN} lines) — extract helpers."
fi

RUST_MAX_IMPL=$(rust_max_impl_lines)
LONG_IMPL=$(awk -v max="$RUST_MAX_IMPL" '
  /^impl / { start=NR; name=$0 }
  start && /^\}/ {
    len=NR-start
    if (len > max) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_IMPL" ]]; then
  add_error "Impl block too large in $FILE_PATH (>${RUST_MAX_IMPL} lines) — split into trait impls or modules."
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

# --- Docs (soft advisory, never blocks) ---
# A public API item in src/ should carry a concise /// doc comment. Advisory
# only — collected separately from MESSAGES so it never sets the failing gate.
DOC_ADVISORY=""
if [[ "$FILE_PATH" == */src/* && ! "$_is_rust_test" -eq 1 ]]; then
  _undoc=$(awk '
    /^[[:space:]]*$/   { next }   # blanks do not reset the doc context
    /^[[:space:]]*#\[/ { next }   # attributes sit between doc and item
    {
      if ($0 ~ /^[[:space:]]*pub[[:space:]]+(fn|struct|enum|trait)[[:space:]]/) {
        if (prev !~ /^[[:space:]]*(\/\/\/|\/\/!)/) printf "%d: %s\n", NR, $0
      }
      prev=$0
    }
  ' "$FILE_PATH" 2>/dev/null | head -3)
  if [[ -n "$_undoc" ]]; then
    DOC_ADVISORY="Public items missing a /// doc comment in $FILE_PATH — add a concise one-line doc:\n${_undoc}"
  fi
  # Concise cap: flag doc-comment runs that have grown long.
  _verbose_doc=$(awk '
    /^[[:space:]]*\/\/[\/!]/ { if (run==0) start=NR; run++; next }
    { if (run>12) printf "%d: doc block is %d lines — trim to the essentials\n", start, run; run=0 }
    END { if (run>12) printf "%d: doc block is %d lines — trim to the essentials\n", start, run }
  ' "$FILE_PATH" 2>/dev/null | head -2)
  if [[ -n "$_verbose_doc" ]]; then
    DOC_ADVISORY="${DOC_ADVISORY:+$DOC_ADVISORY\n}Verbose doc comment in $FILE_PATH — docs must be present but concise:\n${_verbose_doc}"
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

  # Docs advisory (non-blocking — no gate write).
  if [[ -n "$DOC_ADVISORY" ]]; then
    jq -n --arg ctx "$DOC_ADVISORY" '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": $ctx
      }
    }'
  fi
fi

exit 0
