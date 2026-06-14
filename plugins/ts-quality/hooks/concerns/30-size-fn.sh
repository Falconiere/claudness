TS_MAX_FN=$(ts_max_fn_lines)
# Brace-depth fn-length counter — mirrors rust-quality.sh so TS and Rust measure
# the same way. The end of a function is found by counting brace depth from the
# fn's own line (single-line "..."/'...'/`...` string and quote char-literal
# contents stripped first), so a method inside a class/object is measured to ITS
# own indented close, an inner if/for/switch close can't end the range early, and
# a column-0 `}` inside a template literal no longer cuts the range short — the
# bugs the old `^}` col-0 marker had. Three start forms: `function` declarations,
# `const NAME = (…) =>` / `= function` expressions (params may span lines), and
# class/object methods `name(…) {` (control-flow keywords excluded so their
# blocks aren't mistaken for methods). Known limitation (same as Rust): a brace
# inside a MULTI-LINE template/string still leaks into the count — an unbalanced
# one leaves the fn unmeasured (fail-open), never falsely flagged short.
LONG_FUNCS=$(awk -v max="$TS_MAX_FN" -v q="'" '
  function strip(l) {
    gsub(/\\"/, "", l)            # escaped double quotes
    gsub(/"[^"]*"/, "", l)        # double-quoted string contents
    gsub(q "[^" q "]*" q, "", l)  # single-quoted string / char-literal contents
    gsub(/`[^`]*`/, "", l)        # single-line template-literal contents
    return l
  }
  function fnstart() { infn=1; start=NR; name=$0; depth=0; opened=0 }
  !infn {
    s=strip($0)
    if (s ~ /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?function[ \t*]/) { fnstart() }
    else if (s ~ /^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?const[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*(async[[:space:]]+)?(\(|function[ \t(*])/) { fnstart() }
    else if (s ~ /^[[:space:]]+(public[[:space:]]+|private[[:space:]]+|protected[[:space:]]+|static[[:space:]]+|async[[:space:]]+|override[[:space:]]+|readonly[[:space:]]+|get[[:space:]]+|set[[:space:]]+|\*[[:space:]]*)*[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(<[^(){}]*>)?[[:space:]]*\(/ \
         && s !~ /^[[:space:]]*(if|for|while|switch|catch|return|do|else|function|await|with|yield|throw|new|typeof|delete|void|in|of|case)[^A-Za-z0-9_$]/ \
         && s !~ /=>/ \
         && s !~ /;[[:space:]]*$/ \
         && s ~ /\)([[:space:]]*:[^={]*)?[[:space:]]*\{[[:space:]]*$/) { fnstart() }
  }
  infn {
    line=strip($0)
    no=gsub(/\{/, "{", line); nc=gsub(/\}/, "}", line)
    depth += no - nc
    if (no > 0) opened=1
    if (opened && depth <= 0) {
      len=NR-start
      if (len > max) printf "%s:%d (%d lines)\n", name, start, len
      infn=0
    }
    # Release a brace-less single-line form (an expression-bodied arrow like
    # `const sq = (x) => x * x;` or a parenthesized `const x = (a, b);`) on its
    # terminating `;`. Mirrors rust-quality.sh: without this the start sticks and
    # the NEXT real function is misattributed to this line — a bogus over-length.
    if (!opened && $0 ~ /;[[:space:]]*$/) infn=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_FUNCS" ]]; then
  add_error "Function too long in $FILE_PATH (>${TS_MAX_FN} lines) — simplify or split"
fi

