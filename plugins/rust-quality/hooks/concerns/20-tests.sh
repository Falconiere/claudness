_has_inline_cfg_test=0
# Match bare `#[cfg(test)]` and `test` as the FIRST predicate of an all()/any()
# combinator (`#[cfg(all(test, feature = "x"))]`, `#[cfg(any(test, ...))]`).
# Deliberately NOT a loose `cfg(.*\btest\b`: that would false-positive on
# `#[cfg(not(test))]` (the opposite gate) and `#[cfg(feature = "test-utils")]`
# (test inside a string). A non-leading `test` predicate (`all(feature, test)`)
# is the rare miss we accept to keep zero false positives.
if [[ "$FILE_PATH" == */src/* ]] \
   && grep -qE '^[[:space:]]*#\[cfg\((test\)|all\(test\b|any\(test\b)' "$FILE_PATH" 2>/dev/null; then
  add_error "Inline #[cfg(test)] in $FILE_PATH — tests must live in tests/ directory"
  _has_inline_cfg_test=1
fi

# Test placement: a test-bearing .rs file must live under a tests/ dir, kept
# flat (only fixtures/helpers/common subdirs allowed — common/mod.rs is the
# cargo idiom for shared test helpers). Skip when the inline-#[cfg(test)] rule
# already fired: that's the canonical `src/lib.rs` with `#[cfg(test)] mod tests`
# pattern, where "move the file to tests/" is wrong (it would orphan the pub
# items) — the cfg(test) message already says to extract the tests.
_is_rust_test=0
case "$(basename "$FILE_PATH")" in
  *_test.rs|*_tests.rs) _is_rust_test=1 ;;
esac
# #[bench] and #[wasm_bindgen_test] are deliberately NOT in the alternation:
# benches belong in benches/ (cargo convention) and wasm-bindgen tests have no
# single canonical home — "move to tests/" would be a false positive for both.
# Generalized over `#[<any::path>::test]` rather than a hardcoded runtime list,
# so test_log::test, trace_test::test, actix_web::test, etc. all trip the rule;
# `test_case` (the test_case crate's generator) is added explicitly. `#[rstest]`
# is its own alternation (the macro name is not `test`). `#[cfg(test)]` is NOT
# matched here — no `test`/`test_case` token follows `#[` — and stays owned by
# the inline-cfg(test) rule above.
if [[ "$_is_rust_test" -eq 0 ]] \
   && grep -qE '^[[:space:]]*#\[([A-Za-z_][A-Za-z0-9_]*::)*(test|test_case)\b|^[[:space:]]*#\[rstest\b' "$FILE_PATH" 2>/dev/null; then
  _is_rust_test=1
fi
if [[ "$_is_rust_test" -eq 1 && "$_has_inline_cfg_test" -eq 0 ]]; then
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
