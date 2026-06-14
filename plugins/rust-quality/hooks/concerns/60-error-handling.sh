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
  # Keep the FIRST failing probe's detail — later probes don't overwrite it, so
  # the surfaced diagnostic is deterministic instead of naming only the last.
  record_ast_fail() {
    [ -n "$ast_grep_fail_detail" ] && return 0
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
  UNREACH_HITS=$(ast_scan 'unreachable!($$$)' 3) || { ast_grep_failed=1; record_ast_fail; }
  if [[ -n "$PANIC_HITS" || -n "$TODO_HITS" || -n "$UNIMPL_HITS" || -n "$UNREACH_HITS" ]]; then
    add_error "panic!/todo!/unimplemented!/unreachable! in $FILE_PATH — return a Result instead\n${PANIC_HITS}${TODO_HITS}${UNIMPL_HITS}${UNREACH_HITS}"
  fi

  rm -f "$ast_err_file" "$ast_rc_file"
  if [[ "$ast_grep_failed" -ne 0 ]]; then
    add_error "ast-grep failed while scanning $FILE_PATH (${ast_grep_fail_detail:-unknown error}) — error-handling rules could not be verified; fix the tool/file and re-edit"
  fi
fi

