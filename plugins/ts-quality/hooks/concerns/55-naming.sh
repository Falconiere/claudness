# Check: forbidden sub-component file names (must match the exported function)
_basename="$(basename "$FILE_PATH" .tsx)"
_basename="${_basename%.ts}"
if [[ "$FILE_PATH" =~ \.(tsx)$ ]]; then
  if echo "$_basename" | grep -qE '^(parts|components|helpers|items|sections|elements)$|-(parts|sections|items|elements)$'; then
    add_error "Forbidden component filename '$_basename.tsx' in $FILE_PATH — name file after its exported function (e.g. api-key-create-button.tsx)"
  fi
fi

# --- New checks ---

