if grep -qE 'function is[A-Z].*\): .* is [A-Z]' "$FILE_PATH" 2>/dev/null; then
  if [[ -f "$PROJECT_ROOT/package.json" ]] && grep -q '"zod"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    add_error "Manual type guard in $FILE_PATH — use Zod schema instead"
  fi
fi

