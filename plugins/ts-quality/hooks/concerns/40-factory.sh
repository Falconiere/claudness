FACTORY_COUNT=$(grep -cE '^export (async )?function create' "$FILE_PATH" 2>/dev/null || true)
if [[ "$FACTORY_COUNT" -gt 2 ]]; then
  add_error "Too many factory functions in $FILE_PATH ($FACTORY_COUNT) — simplify construction"
fi

