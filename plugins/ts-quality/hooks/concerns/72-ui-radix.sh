# Check: raw radix AlertDialog/Dialog imports. Drop leading-`//` comment lines
# first (same filter as the AS_LINES check above) so a commented-out import does
# not false-positive. Like AS_LINES, only whole-line `//` comments are dropped —
# a radix path inside a trailing comment after real code still matches (rare:
# imports are standalone). Kept consistent with the sibling rules on purpose.
if grep -nE "from ['\"]@radix-ui/react-(alert-dialog|dialog)['\"]" "$FILE_PATH" 2>/dev/null \
     | grep -qvE '^[0-9]+:[[:space:]]*//'; then
  if [[ "$FILE_PATH" != */packages/ui/* ]]; then
    add_error "Raw radix import in $FILE_PATH — use shared components from @/components/ui/"
  fi
fi

