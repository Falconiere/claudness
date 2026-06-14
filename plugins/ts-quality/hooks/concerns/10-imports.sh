# --- Existing checks ---

if grep -q 'from ["'"'"']\.\./' "$FILE_PATH" 2>/dev/null; then
  add_error "Forbidden ../ import in $FILE_PATH — use @/ alias"
fi

