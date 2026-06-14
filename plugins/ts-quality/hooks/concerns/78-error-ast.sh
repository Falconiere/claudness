# --- Error-handling rules (zero tolerance) ---

if command -v ast-grep >/dev/null 2>&1; then
  # ast-grep is grep-like: 0 = matches, 1 = no matches (or runtime error, with
  # stderr output), >1 = crash. Capturing exit + stderr (rather than
  # `2>/dev/null | head`) means a parser bug or malformed file becomes a
  # finding instead of silently no-op'ing every rule below. Mirrors the
  # ast_scan/record_ast_fail scaffolding in rust-quality.sh.
  ts_ast_err_file="$(mktemp)"
  ts_ast_rc_file="$(mktemp)"
  ts_ast_fail_detail=""
  ts_ast_scan() {
    local out rc
    out=$(ast-grep --lang ts -p "$1" "$FILE_PATH" 2>"$ts_ast_err_file")
    rc=$?
    printf '%s' "$rc" > "$ts_ast_rc_file"
    if [[ "$rc" -gt 1 || ( "$rc" -eq 1 && -s "$ts_ast_err_file" ) ]]; then
      return 1
    fi
    printf '%s\n' "$out" | head -n "$2"
  }
  ts_record_ast_fail() {
    # Keep the FIRST failing probe's detail; later probes don't overwrite it, so
    # the surfaced diagnostic is deterministic instead of naming only whichever
    # probe happened to fail last.
    [ -n "$ts_ast_fail_detail" ] && return 0
    local rc stderr_first
    rc=$(cat "$ts_ast_rc_file" 2>/dev/null)
    stderr_first=$(head -n 1 "$ts_ast_err_file" 2>/dev/null | cut -c1-200)
    ts_ast_fail_detail="exit ${rc:-?}${stderr_first:+: $stderr_first}"
  }
  ts_ast_failed=0

  # Empty catch — swallowed error
  EMPTY_CATCH=$(ts_ast_scan 'try { $$$ } catch ($_) { }' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  EMPTY_CATCH_NOARG=$(ts_ast_scan 'try { $$$ } catch { }' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$EMPTY_CATCH" || -n "$EMPTY_CATCH_NOARG" ]]; then
    add_error "Empty catch block in $FILE_PATH — handle the error or rethrow; do not swallow\n${EMPTY_CATCH}${EMPTY_CATCH_NOARG}"
  fi

  # Silent promise rejection — .catch(() => {}) / .catch(() => null)
  EMPTY_CATCH_HANDLER=$(ts_ast_scan '$_.catch(() => { })' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  NULL_CATCH_HANDLER=$(ts_ast_scan '$_.catch(() => null)' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  UNDEF_CATCH_HANDLER=$(ts_ast_scan '$_.catch(() => undefined)' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$EMPTY_CATCH_HANDLER" || -n "$NULL_CATCH_HANDLER" || -n "$UNDEF_CATCH_HANDLER" ]]; then
    add_error "Silent promise rejection in $FILE_PATH — log or rethrow the error\n${EMPTY_CATCH_HANDLER}${NULL_CATCH_HANDLER}${UNDEF_CATCH_HANDLER}"
  fi

  # Swallow via a catch that just returns a nullish value — error vanishes.
  # Skip the pattern scans entirely on files with no catch (avoids 6 ast-grep
  # spawns on the common case, since this runs on every edit).
  if grep -qE '\bcatch\b' "$FILE_PATH" 2>/dev/null; then
    SWALLOW_CATCH=""
    for _pat in \
      'try { $$$ } catch ($_) { return null }' \
      'try { $$$ } catch ($_) { return undefined }' \
      'try { $$$ } catch ($_) { return }' \
      'try { $$$ } catch { return null }' \
      'try { $$$ } catch { return undefined }' \
      'try { $$$ } catch { return }'; do
      _h=$(ts_ast_scan "$_pat" 2) || { ts_ast_failed=1; ts_record_ast_fail; }
      [[ -n "$_h" ]] && SWALLOW_CATCH="${SWALLOW_CATCH}${_h}\n"
    done
    if [[ -n "$SWALLOW_CATCH" ]]; then
      add_error "Catch swallows the error by returning a nullish value in $FILE_PATH — handle, log, or rethrow it\n${SWALLOW_CATCH}"
    fi
  fi

  # throw new Error() with no message
  THROW_EMPTY_ERROR=$(ts_ast_scan 'throw new Error()' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$THROW_EMPTY_ERROR" ]]; then
    add_error "throw new Error() with no message in $FILE_PATH — include a descriptive message\n${THROW_EMPTY_ERROR}"
  fi

  # throw of string literal — breaks instanceof Error
  THROW_STRING=$(ts_ast_scan 'throw "$S"' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  THROW_TSTR=$(ts_ast_scan 'throw `$S`' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$THROW_STRING" || -n "$THROW_TSTR" ]]; then
    add_error "throw of string literal in $FILE_PATH — throw an Error (or subclass) instead\n${THROW_STRING}${THROW_TSTR}"
  fi

  rm -f "$ts_ast_err_file" "$ts_ast_rc_file"
  if [[ "$ts_ast_failed" -ne 0 ]]; then
    add_error "ast-grep failed while scanning $FILE_PATH (${ts_ast_fail_detail:-unknown error}) — error-handling rules could not be verified; fix the tool/file and re-edit"
  fi
fi

