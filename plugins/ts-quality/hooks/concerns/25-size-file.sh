# Resolve the limit AND where it came from in one pass (avoids running the
# override/native lookups twice). Contract: ts_max_file_lines_resolved prints
# exactly "<int> <source>" where <source> is ONE token (override|native|default)
# — the two-field `read` below relies on it; a multi-word source would spill
# into TS_MAX_SRC and break the case arms.
TS_MAX_FILE=""; TS_MAX_SRC="default"
if command -v ts_max_file_lines_resolved >/dev/null 2>&1; then
  read -r TS_MAX_FILE TS_MAX_SRC <<<"$(ts_max_file_lines_resolved)"
else
  TS_MAX_FILE=$(ts_max_file_lines)
fi
[ -n "$TS_MAX_FILE" ] || TS_MAX_FILE="${DEFAULT_TS_MAX_FILE_LINES:-300}"
[ -n "$TS_MAX_SRC" ] || TS_MAX_SRC="default"   # empty read -> case must still pick a branch
TS_LINE_COUNT=$(count_code_lines "$FILE_PATH")
if [[ "$TS_LINE_COUNT" -gt "$TS_MAX_FILE" ]]; then
  _split_hint="split into smaller modules"
  _linter="$(detect_ts_linter)"
  if [ -n "$_linter" ]; then
    # Only claim the linter owns the limit when the limit truly came from its
    # config; if a linter is present but its config isn't machine-readable
    # (e.g. .eslintrc.cjs / eslint.config.js), say so instead of contradicting.
    case "$TS_MAX_SRC" in
      native)  _split_hint="$_split_hint ($_linter enforces this max-lines limit)" ;;
      default)
        # Biome has no max-lines rule at all, so "unparsed config form" would be
        # misleading for it — say so plainly. ESLint/oxc do have max-lines, so
        # there the limit genuinely could have come from an unreadable config.
        if [ "$_linter" = "biome" ]; then
          _split_hint="$_split_hint (biome has no max-lines equivalent — gate uses the ${TS_MAX_FILE}-line default)"
        else
          _split_hint="$_split_hint ($_linter is present but the gate's limit didn't come from its config (unparsed config form or a per-glob override) — gate uses the ${TS_MAX_FILE}-line default; align them)"
        fi
        ;;
    esac
  fi
  _approx=""
  has_unterminated_block "$FILE_PATH" && _approx=" (size approximated — an unterminated /* or a string containing /* may be affecting the count)"
  add_error "TS file exceeds ${TS_MAX_FILE}-line limit: $FILE_PATH ($TS_LINE_COUNT code lines, blanks/comments excluded)${_approx} — $_split_hint"
fi

