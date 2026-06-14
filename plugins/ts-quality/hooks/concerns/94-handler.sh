# Handler-presence advisory (non-blocking): the file awaits but has no try/catch
# and no .catch anywhere — rejections may be unhandled. Advisory, not a block,
# because the handler can legitimately live in every caller.
ERR_ADVISORY=""
# Comment-only lines are stripped first: a commented-out `await` must not raise
# the advisory, and a `try`/`.catch` that only appears in a comment must not
# suppress it. (`*`-prefixed lines are JSDoc/block-comment continuations; a
# CODE line starting with `*` — a multiplication continuation holding the only
# await — is stripped too, accepted: advisory-only, fails open.)
_ts_noncomment=$(grep -vE '^[[:space:]]*(//|/\*|\*)' "$FILE_PATH" 2>/dev/null)
if printf '%s\n' "$_ts_noncomment" | grep -qE '\bawait[[:space:]]' \
   && ! printf '%s\n' "$_ts_noncomment" | grep -qE '\btry\b|\.catch\('; then
  ERR_ADVISORY="Async code in $FILE_PATH uses await with no try/catch or .catch in the file — ensure rejections are handled here or by every caller."
fi

