# Forbidden unsafe blocks/functions — except for crates listed in the
# exemptions file (FFI crates, sandboxes, etc).
exempt=0
if [ -f "$EXEMPTIONS_FILE" ]; then
  while IFS= read -r crate; do
    [ -z "$crate" ] && continue
    if [[ "$FILE_PATH" == *"$crate"* ]]; then
      exempt=1
      break
    fi
  done <<< "$(read_list "$EXEMPTIONS_FILE")"
fi
if [ "$exempt" -eq 0 ]; then
  # Strip // line comments and /* */ blocks (incl. multi-line) before matching,
  # so a commented-out or doc-mentioned `unsafe {` does not false-positive. The
  # block-comment state machine mirrors count_code_lines in detect.sh. String
  # literals containing the pattern are not handled — same heuristic limit as the
  # other comment-stripping passes here. BSD awk (macOS) has no \b, so explicit
  # boundaries are used instead.
  if awk '
    { line=$0
      if (inblock) {
        idx=index(line,"*/")
        if (idx>0) { line=substr(line, idx+2); inblock=0 } else next
      }
      while ((s=index(line,"/*"))>0) {
        rest=substr(line, s+2); e=index(rest,"*/")
        if (e>0) { line=substr(line,1,s-1) substr(rest, e+2) }
        else { line=substr(line,1,s-1); inblock=1; break }
      }
      sub(/\/\/.*$/, "", line)        # // line comment
      if (line ~ /(^|[^A-Za-z0-9_])unsafe[ \t]*(\{|fn )/) { found=1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' "$FILE_PATH" 2>/dev/null; then
    add_error "Forbidden unsafe code in $FILE_PATH — refactor to safe alternative. Add crate to settings/rust-unsafe-exemptions.txt if it legitimately needs unsafe (FFI, sandboxing)."
  fi
fi

