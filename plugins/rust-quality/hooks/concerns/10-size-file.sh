RUST_MAX_FILE=$(rust_max_file_lines)
LINE_COUNT=$(count_code_lines "$FILE_PATH")
if [[ "$LINE_COUNT" -gt "$RUST_MAX_FILE" ]]; then
  _split_hint="split into submodules"
  [ -n "$(detect_clippy)" ] && _split_hint="$_split_hint (clippy enforces complexity here)"
  _approx=""
  has_unterminated_block "$FILE_PATH" && _approx=" (size approximated — an unterminated /* or a string containing /* may be affecting the count)"
  add_error "File exceeds ${RUST_MAX_FILE}-line limit: $FILE_PATH ($LINE_COUNT code lines, blanks/comments excluded)${_approx} — $_split_hint"
fi

