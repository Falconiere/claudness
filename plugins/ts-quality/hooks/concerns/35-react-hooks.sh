if [[ "$FILE_PATH" =~ use-.*\.ts$ || "$FILE_PATH" =~ use[A-Z].*\.ts$ ]]; then
  HOOK_COUNT=$(grep -cE '^[[:space:]]*(const \[|useRef\(|useEffect\()' "$FILE_PATH" 2>/dev/null || true)
  if [[ "$HOOK_COUNT" -gt 3 ]]; then
    add_error "Hook does too many things in $FILE_PATH ($HOOK_COUNT useState/useRef/useEffect) — split into focused hooks"
  fi
fi

