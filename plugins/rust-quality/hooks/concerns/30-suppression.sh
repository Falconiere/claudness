
# Forbidden lint suppression: #[allow(...)] / #![allow(...)] / #[expect(...)]
# and the #[cfg_attr(..., allow(...))] / cfg_attr(..., expect(...)) back door.
# Known limitation: grep is line-based, so an attribute split across multiple
# lines (e.g. `#[cfg_attr(\n  test,\n  allow(...))]`) escapes detection. Rare;
# multi-line attribute parsing isn't worth a full tokenizer here.
if grep -qE '^[[:space:]]*#!?\[(allow|expect)\(|^[[:space:]]*#!?\[cfg_attr\([^]]*\b(allow|expect)\b' "$FILE_PATH" 2>/dev/null; then
  add_error "Forbidden lint suppression (#[allow]/#[expect]/cfg_attr allow) in $FILE_PATH — remove it and fix the underlying warning in code. For unsafe_code, override in Cargo.toml [lints.rust]."
fi

