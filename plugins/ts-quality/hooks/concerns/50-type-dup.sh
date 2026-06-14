NEW_TYPES=$(grep -oE '^export (interface|type) [A-Z][a-zA-Z]+' "$FILE_PATH" 2>/dev/null | awk '{print $NF}')
if [[ -n "$NEW_TYPES" ]]; then
  # git grep instead of grep -r: uses the index, skips .gitignore'd trees
  # (node_modules, dist) — the recursive walk was a per-edit hot-path cost on
  # large monorepos. --untracked keeps brand-new files visible.
  _ts_rel_fp="${FILE_PATH#"$PROJECT_ROOT"/}"
  for TYPE_NAME in $NEW_TYPES; do
    DUPE_FILE=$(git -C "$PROJECT_ROOT" grep -l --untracked -E \
      "^export (interface|type) ${TYPE_NAME}[ <{]" -- 'packages/*.ts' 'packages/*.tsx' 'apps/*.ts' 'apps/*.tsx' 2>/dev/null \
      | grep -vFx "$_ts_rel_fp" | head -1)
    if [[ -n "$DUPE_FILE" ]]; then
      add_error "Type '$TYPE_NAME' in $FILE_PATH already defined in $DUPE_FILE — import instead of redefining"
    fi
  done
fi

