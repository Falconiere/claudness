# Check: code duplication (jscpd, scoped to package directory)
# Advisory only — warns but does NOT block (pre-existing duplication is not the editor's fault).
DUPLICATION_WARNING=""
if [[ -z "$MESSAGES" && ! "$FILE_PATH" =~ \.(test|spec)\. ]]; then
  _pkg_rel="${FILE_PATH#"$PROJECT_ROOT"/}"
  _pkg_dir=""
  if [[ "$_pkg_rel" == apps/* || "$_pkg_rel" == packages/* ]]; then
    _pkg_dir="$PROJECT_ROOT/$(echo "$_pkg_rel" | cut -d/ -f1-2)"
  fi
  # jscpd runner — use whatever package manager runner is available.
  jscpd_runner=""
  case "$pm" in
    bun)  command -v bunx >/dev/null 2>&1 && jscpd_runner="bunx jscpd" ;;
    pnpm) command -v pnpm >/dev/null 2>&1 && jscpd_runner="pnpm dlx jscpd" ;;
    yarn) command -v yarn >/dev/null 2>&1 && jscpd_runner="yarn dlx jscpd" ;;
    npm)  command -v npx  >/dev/null 2>&1 && jscpd_runner="npx jscpd" ;;
  esac
  if [[ -n "$_pkg_dir" && -d "$_pkg_dir" && -f "$PROJECT_ROOT/.jscpd.json" && -n "$jscpd_runner" ]]; then
    # shellcheck disable=SC2086  # $jscpd_runner is a multi-word command (e.g. "pnpm dlx jscpd") — intentional word split
    _jscpd_out=$(timeout 10 $jscpd_runner "$_pkg_dir" \
      --config "$PROJECT_ROOT/.jscpd.json" \
      2>&1 || true)
    _file_base=$(basename "$FILE_PATH")
    if echo "$_jscpd_out" | grep -qi "found.*clone\|duplicat" && \
       echo "$_jscpd_out" | grep -q "$_file_base"; then
      DUPLICATION_WARNING="Code duplication detected involving $FILE_PATH — deduplicate or run '$TYPECHECK_CMD' before commit"
    fi
  fi
fi

