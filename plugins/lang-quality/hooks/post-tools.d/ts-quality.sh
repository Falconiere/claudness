#!/usr/bin/env bash
# Post-tool check: TypeScript / TSX quality rules
# Lightweight file-level checks (fast, no external tool invocations).
# Project-agnostic: no-op outside TS projects; package-manager driven.
#
# Inputs (from parent dispatcher post-tools/mod.sh, via `export`):
#   $tool_name     - name of the tool being invoked
#   $input         - raw JSON payload on stdin
#   $PROJECT_ROOT  - repository root

: "${tool_name:=}"
: "${input:=}"
: "${PROJECT_ROOT:=$(pwd)}"

# Core lib comes from the claudness dispatcher via CLAUDNESS_LIB_DIR (set by
# plugins/claudness/hooks/post-tools/mod.sh before registry dispatch). Outside
# that pipeline there is no relative path to it — fail SOFT: a quality check
# must never break a tool call by erroring.
[ -n "${CLAUDNESS_LIB_DIR:-}" ] && [ -f "$CLAUDNESS_LIB_DIR/detect.sh" ] || exit 0
# shellcheck source=../../../claudness/hooks/lib/detect.sh
. "$CLAUDNESS_LIB_DIR/detect.sh"
# Threshold resolver (defaults + project/native overrides). Soft if absent.
# shellcheck source=../../../claudness/hooks/lib/quality-config.sh
[ -f "$CLAUDNESS_LIB_DIR/quality-config.sh" ] && . "$CLAUDNESS_LIB_DIR/quality-config.sh"
# Multi-slot gate writer (entries keyed by file — one hook's failure no longer
# clobbers another's). Soft if absent: fallbacks below keep the legacy
# single-slot behavior when the claudness lib predates gate-file.sh.
# shellcheck source=../../../claudness/hooks/lib/gate-file.sh
[ -f "$CLAUDNESS_LIB_DIR/gate-file.sh" ] && . "$CLAUDNESS_LIB_DIR/gate-file.sh"
command -v gate_record_failure >/dev/null 2>&1 || gate_record_failure() {
  jq -n --arg reason "$4" --arg source "$3" --arg file "$2" --arg violations "$5" \
    --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{status: "failing", reason: $reason, source: $source, file: $file,
      violations: $violations, updatedAt: $updatedAt}' > "$1"
}
command -v gate_clear_file >/dev/null 2>&1 || gate_clear_file() {
  [ -f "$1" ] || return 0
  local _src _file
  _src=$(jq -r '.source // ""' "$1" 2>/dev/null || echo "")
  _file=$(jq -r '.file // ""' "$1" 2>/dev/null || echo "")
  if [ "$_src" = "$3" ] && [ "$_file" = "$2" ]; then
    jq -n --arg source "$3" --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{status: "passing", source: $source, updatedAt: $updatedAt}' > "$1"
  fi
}
command -v ts_max_file_lines        >/dev/null 2>&1 || ts_max_file_lines()        { echo "${DEFAULT_TS_MAX_FILE_LINES:-300}"; }
command -v ts_max_fn_lines          >/dev/null 2>&1 || ts_max_fn_lines()          { echo "${DEFAULT_TS_MAX_FN_LINES:-60}"; }
command -v ts_max_file_lines_source >/dev/null 2>&1 || ts_max_file_lines_source() { printf 'default'; }
# count_code_lines comes from detect.sh (sourced above) — no fallback needed.

# Load the merged config ONCE in this shell so CLAUDNESS_CFG_LOADED sticks for
# the threshold lookups below — each runs in a $(...) subshell that inherits it
# and skips re-merging (otherwise every wrapper re-spawns the jq merge).
command -v claudness_load_config >/dev/null 2>&1 && claudness_load_config 2>/dev/null || true

# Exit early if this isn't a TypeScript project.
[ "$(detect_ts)" = "ts" ] || exit 0

# Exit if no package manager is detected — we cannot recommend a typecheck command.
pm="$(detect_node_pm)"
[ -n "$pm" ] || exit 0
command -v "$pm" >/dev/null 2>&1 || exit 0

# Resolve the project's typecheck command per package manager.
typecheck_cmd() {
  case "$1" in
    bun)  echo "bun run typecheck" ;;
    pnpm) echo "pnpm -w typecheck" ;;
    yarn) echo "yarn typecheck" ;;
    npm)  echo "npm run typecheck" ;;
    *)    echo "$1 run typecheck" ;;
  esac
}
TYPECHECK_CMD="$(typecheck_cmd "$pm")"

command -v jq >/dev/null 2>&1 || exit 0

fp_from_input=""
if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" || "$tool_name" == "MultiEdit" ]]; then
  fp_from_input=$(echo "$input" | jq -r '.tool_input.path // .tool_input.file_path // .tool_input.target_file // empty' 2>/dev/null || echo "")
fi
FILE_PATH="${CLAUDE_FILE_PATHS:-$fp_from_input}"

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ ! "$FILE_PATH" =~ \.(ts|tsx)$ ]] && exit 0

# Skip files inside git linked worktrees — quality state is for the main checkout only.
# One git call, one dirname: --git-dir + --git-common-dir come back on two lines.
_file_dir="$(dirname "$FILE_PATH")"
_file_git_dir=""; _file_common_dir=""
{ IFS= read -r _file_git_dir; IFS= read -r _file_common_dir; } < <(
  git -C "$_file_dir" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null
)
_file_git_dir="${_file_git_dir%/}"
_file_common_dir="${_file_common_dir%/}"
if [[ -n "$_file_git_dir" && -n "$_file_common_dir" && "$_file_git_dir" != "$_file_common_dir" ]]; then
  exit 0
fi

MESSAGES=""
add_error() {
  MESSAGES="${MESSAGES}${1}\n"
}

# --- Existing checks ---

if grep -q 'from ["'"'"']\.\./' "$FILE_PATH" 2>/dev/null; then
  add_error "Forbidden ../ import in $FILE_PATH — use @/ alias"
fi

AS_LINES=$(grep -nE '\)[[:space:]]+as[[:space:]]+[a-zA-Z]|\bas[[:space:]]+any\b|\bas[[:space:]]+unknown\b|[a-zA-Z>][[:space:]]+as[[:space:]]+[A-Z]|[a-zA-Z>][[:space:]]+as[[:space:]]+(string|number|boolean|object|symbol|bigint|never|undefined|null|void)\b' "$FILE_PATH" 2>/dev/null \
  | grep -vE '^[0-9]+:[[:space:]]*//' \
  | grep -vE '\bas[[:space:]]+const\b' \
  | grep -vE '\bimport\b|^[0-9]+:[[:space:]]*export[[:space:]]*(type[[:space:]]+)?\{' \
  | head -5)
if [[ -n "$AS_LINES" ]]; then
  add_error "Forbidden 'as' type assertion in $FILE_PATH — use type guards or Zod\n${AS_LINES}"
fi

if [[ "$FILE_PATH" =~ \.(test|spec)\.(ts|tsx)$ ]]; then
  if [[ "$FILE_PATH" != */__tests__/* ]]; then
    add_error "Test file outside __tests__/: $FILE_PATH — move to sibling __tests__/ directory"
  else
    _after_tests="${FILE_PATH##*__tests__/}"
    if [[ "$_after_tests" == */* ]]; then
      _subdir="${_after_tests%%/*}"
      if [[ "$_subdir" != "fixtures" && "$_subdir" != "helpers" && "$_subdir" != "mocks" && "$_subdir" != "utils" ]]; then
        add_error "Test nested in __tests__/ subdirectory: $FILE_PATH — keep __tests__/ flat (only fixtures/helpers/mocks/utils subdirs allowed)"
      fi
    fi
    _tests_dir="${FILE_PATH%%__tests__/*}__tests__"
    _parent_dir=$(dirname "$_tests_dir")
    if ! find "$_parent_dir" -maxdepth 1 -type f \( -name "*.ts" -o -name "*.tsx" \) \
        ! -name "*.test.*" ! -name "*.spec.*" ! -name "*.d.ts" 2>/dev/null | grep -q . \
       && ! find "$_parent_dir" -maxdepth 1 -type d ! -name "__tests__" ! -name "." 2>/dev/null | grep -q .; then
      add_error "Test not co-located with source: $FILE_PATH — __tests__/ must be at the same level as the code it tests"
    fi
  fi
fi

# Resolve the limit AND where it came from in one pass (avoids running the
# override/native lookups twice). Contract: ts_max_file_lines_resolved prints
# exactly "<int> <source>" where <source> is ONE token (override|native|default)
# — the two-field `read` below relies on it; a multi-word source would spill
# into TS_MAX_SRC and break the case arms.
TS_MAX_FILE=""; TS_MAX_SRC="default"
if command -v ts_max_file_lines_resolved >/dev/null 2>&1; then
  read -r TS_MAX_FILE TS_MAX_SRC <<<"$(ts_max_file_lines_resolved)"
else
  TS_MAX_FILE=$(ts_max_file_lines)
fi
[ -n "$TS_MAX_FILE" ] || TS_MAX_FILE="${DEFAULT_TS_MAX_FILE_LINES:-300}"
[ -n "$TS_MAX_SRC" ] || TS_MAX_SRC="default"   # empty read -> case must still pick a branch
TS_LINE_COUNT=$(count_code_lines "$FILE_PATH")
if [[ "$TS_LINE_COUNT" -gt "$TS_MAX_FILE" ]]; then
  _split_hint="split into smaller modules"
  _linter="$(detect_ts_linter)"
  if [ -n "$_linter" ]; then
    # Only claim the linter owns the limit when the limit truly came from its
    # config; if a linter is present but its config isn't machine-readable
    # (e.g. .eslintrc.cjs / eslint.config.js), say so instead of contradicting.
    case "$TS_MAX_SRC" in
      native)  _split_hint="$_split_hint ($_linter enforces this max-lines limit)" ;;
      default) _split_hint="$_split_hint ($_linter is present but the gate's limit didn't come from its config (unparsed config form or a per-glob override) — gate uses the ${TS_MAX_FILE}-line default; align them)" ;;
    esac
  fi
  _approx=""
  has_unterminated_block "$FILE_PATH" && _approx=" (size approximated — an unterminated /* or a string containing /* may be affecting the count)"
  add_error "TS file exceeds ${TS_MAX_FILE}-line limit: $FILE_PATH ($TS_LINE_COUNT code lines, blanks/comments excluded)${_approx} — $_split_hint"
fi

TS_MAX_FN=$(ts_max_fn_lines)
LONG_FUNCS=$(awk -v max="$TS_MAX_FN" '
  /^(export )?(async )?function / || /^(export )?const [a-zA-Z_]+ = (async )?\(/ {
    start=NR; name=$0
  }
  start && /^}/ {
    len=NR-start
    if (len > max) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_FUNCS" ]]; then
  add_error "Function too long in $FILE_PATH (>${TS_MAX_FN} lines) — simplify or split"
fi

if [[ "$FILE_PATH" =~ use-.*\.ts$ || "$FILE_PATH" =~ use[A-Z].*\.ts$ ]]; then
  HOOK_COUNT=$(grep -cE '^[[:space:]]*(const \[|useRef\(|useEffect\()' "$FILE_PATH" 2>/dev/null || true)
  if [[ "$HOOK_COUNT" -gt 3 ]]; then
    add_error "Hook does too many things in $FILE_PATH ($HOOK_COUNT useState/useRef/useEffect) — split into focused hooks"
  fi
fi

FACTORY_COUNT=$(grep -cE '^export (async )?function create' "$FILE_PATH" 2>/dev/null || true)
if [[ "$FACTORY_COUNT" -gt 2 ]]; then
  add_error "Too many factory functions in $FILE_PATH ($FACTORY_COUNT) — simplify construction"
fi

if grep -qE 'function is[A-Z].*\): .* is [A-Z]' "$FILE_PATH" 2>/dev/null; then
  if [[ -f "$PROJECT_ROOT/package.json" ]] && grep -q '"zod"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    add_error "Manual type guard in $FILE_PATH — use Zod schema instead"
  fi
fi

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

# Check: forbidden sub-component file names (must match the exported function)
_basename="$(basename "$FILE_PATH" .tsx)"
_basename="${_basename%.ts}"
if [[ "$FILE_PATH" =~ \.(tsx)$ ]]; then
  if echo "$_basename" | grep -qE '^(parts|components|helpers|items|sections|elements)$|-(parts|sections|items|elements)$'; then
    add_error "Forbidden component filename '$_basename.tsx' in $FILE_PATH — name file after its exported function (e.g. api-key-create-button.tsx)"
  fi
fi

# --- New checks ---

# Check: console.log — capture once, then test (not grep-twice).
CONSOLE_LINES=$(grep -nE '^[[:space:]]*console\.log\(' "$FILE_PATH" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -3)
if [[ -n "$CONSOLE_LINES" ]]; then
  add_error "Forbidden console.log in $FILE_PATH — use console.error/warn/info\n${CONSOLE_LINES}"
fi

# Check: suppression comments — fix the issue in code, never silence the tool.
# @ts-expect-error is exempt in test/spec files, where asserting a compile error
# is a legitimate test; banned everywhere else like the rest.
SUPPRESS_TOKENS='@ts-ignore|@ts-nocheck|eslint-disable|biome-ignore'
if [[ ! "$FILE_PATH" =~ \.(test|spec)\.(ts|tsx)$ ]]; then
  SUPPRESS_TOKENS="${SUPPRESS_TOKENS}|@ts-expect-error"
fi
DISABLE_LINES=$(grep -nE "(//|/\*+)[[:space:]]*(${SUPPRESS_TOKENS})" "$FILE_PATH" 2>/dev/null | head -3)
if [[ -n "$DISABLE_LINES" ]]; then
  add_error "Forbidden suppression comment in $FILE_PATH — fix the underlying issue in code, never silence it\n${DISABLE_LINES}"
fi

# Check: confirm()/alert() in frontend files
if [[ "$FILE_PATH" == */components/* || "$FILE_PATH" == */routes/* ]]; then
  CONFIRM_LINES=$(grep -nE '\b(confirm|alert)[[:space:]]*\(' "$FILE_PATH" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | grep -vE '(ConfirmDeleteAlert|AlertDialog|customAlert|customConfirm)' | head -3)
  if [[ -n "$CONFIRM_LINES" ]]; then
    add_error "Forbidden confirm()/alert() in $FILE_PATH — use AlertDialog component\n${CONFIRM_LINES}"
  fi
fi

# Check: raw radix AlertDialog/Dialog imports
if grep -qE "from ['\"]@radix-ui/react-(alert-dialog|dialog)['\"]" "$FILE_PATH" 2>/dev/null; then
  if [[ "$FILE_PATH" != */packages/ui/* ]]; then
    add_error "Raw radix import in $FILE_PATH — use shared components from @/components/ui/"
  fi
fi

# Check: mutable props (Props type param without Readonly)
PROPS_LINES=$(grep -nE '\((props|[a-z]+Props):[[:space:]]+[A-Z][a-zA-Z]+Props\)' "$FILE_PATH" 2>/dev/null | grep -v 'Readonly' | head -3)
if [[ -n "$PROPS_LINES" ]]; then
  add_error "Mutable props in $FILE_PATH — wrap in Readonly<Props>\n${PROPS_LINES}"
fi

# Check: manual try/catch+toast pattern in components
if [[ "$FILE_PATH" == */components/* || "$FILE_PATH" == */routes/* ]]; then
  # [[:space:]] not \s: BSD awk (macOS) has no \s and reads it as a literal `s`,
  # which silently killed this rule for the universal `catch (` spelling.
  CATCH_TOAST=$(awk '/catch[[:space:]]*\(/{found=1} found && /toast\(/{print NR": "$0; found=0}' "$FILE_PATH" 2>/dev/null | head -3)
  if [[ -n "$CATCH_TOAST" ]]; then
    add_error "Manual try/catch+toast in $FILE_PATH — use shared error handling\n${CATCH_TOAST}"
  fi
fi

# --- Error-handling rules (zero tolerance) ---

if command -v ast-grep >/dev/null 2>&1; then
  # ast-grep is grep-like: 0 = matches, 1 = no matches (or runtime error, with
  # stderr output), >1 = crash. Capturing exit + stderr (rather than
  # `2>/dev/null | head`) means a parser bug or malformed file becomes a
  # finding instead of silently no-op'ing every rule below. Mirrors the
  # ast_scan/record_ast_fail scaffolding in rust-quality.sh.
  ts_ast_err_file="$(mktemp)"
  ts_ast_rc_file="$(mktemp)"
  ts_ast_fail_detail=""
  ts_ast_scan() {
    local out rc
    out=$(ast-grep --lang ts -p "$1" "$FILE_PATH" 2>"$ts_ast_err_file")
    rc=$?
    printf '%s' "$rc" > "$ts_ast_rc_file"
    if [[ "$rc" -gt 1 || ( "$rc" -eq 1 && -s "$ts_ast_err_file" ) ]]; then
      return 1
    fi
    printf '%s\n' "$out" | head -n "$2"
  }
  ts_record_ast_fail() {
    local rc stderr_first
    rc=$(cat "$ts_ast_rc_file" 2>/dev/null)
    stderr_first=$(head -n 1 "$ts_ast_err_file" 2>/dev/null | cut -c1-200)
    ts_ast_fail_detail="exit ${rc:-?}${stderr_first:+: $stderr_first}"
  }
  ts_ast_failed=0

  # Empty catch — swallowed error
  EMPTY_CATCH=$(ts_ast_scan 'try { $$$ } catch ($_) { }' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  EMPTY_CATCH_NOARG=$(ts_ast_scan 'try { $$$ } catch { }' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$EMPTY_CATCH" || -n "$EMPTY_CATCH_NOARG" ]]; then
    add_error "Empty catch block in $FILE_PATH — handle the error or rethrow; do not swallow\n${EMPTY_CATCH}${EMPTY_CATCH_NOARG}"
  fi

  # Silent promise rejection — .catch(() => {}) / .catch(() => null)
  EMPTY_CATCH_HANDLER=$(ts_ast_scan '$_.catch(() => { })' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  NULL_CATCH_HANDLER=$(ts_ast_scan '$_.catch(() => null)' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  UNDEF_CATCH_HANDLER=$(ts_ast_scan '$_.catch(() => undefined)' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$EMPTY_CATCH_HANDLER" || -n "$NULL_CATCH_HANDLER" || -n "$UNDEF_CATCH_HANDLER" ]]; then
    add_error "Silent promise rejection in $FILE_PATH — log or rethrow the error\n${EMPTY_CATCH_HANDLER}${NULL_CATCH_HANDLER}${UNDEF_CATCH_HANDLER}"
  fi

  # Swallow via a catch that just returns a nullish value — error vanishes.
  # Skip the pattern scans entirely on files with no catch (avoids 6 ast-grep
  # spawns on the common case, since this runs on every edit).
  if grep -qE '\bcatch\b' "$FILE_PATH" 2>/dev/null; then
    SWALLOW_CATCH=""
    for _pat in \
      'try { $$$ } catch ($_) { return null }' \
      'try { $$$ } catch ($_) { return undefined }' \
      'try { $$$ } catch ($_) { return }' \
      'try { $$$ } catch { return null }' \
      'try { $$$ } catch { return undefined }' \
      'try { $$$ } catch { return }'; do
      _h=$(ts_ast_scan "$_pat" 2) || { ts_ast_failed=1; ts_record_ast_fail; }
      [[ -n "$_h" ]] && SWALLOW_CATCH="${SWALLOW_CATCH}${_h}\n"
    done
    if [[ -n "$SWALLOW_CATCH" ]]; then
      add_error "Catch swallows the error by returning a nullish value in $FILE_PATH — handle, log, or rethrow it\n${SWALLOW_CATCH}"
    fi
  fi

  # throw new Error() with no message
  THROW_EMPTY_ERROR=$(ts_ast_scan 'throw new Error()' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$THROW_EMPTY_ERROR" ]]; then
    add_error "throw new Error() with no message in $FILE_PATH — include a descriptive message\n${THROW_EMPTY_ERROR}"
  fi

  # throw of string literal — breaks instanceof Error
  THROW_STRING=$(ts_ast_scan 'throw "$S"' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  THROW_TSTR=$(ts_ast_scan 'throw `$S`' 3) || { ts_ast_failed=1; ts_record_ast_fail; }
  if [[ -n "$THROW_STRING" || -n "$THROW_TSTR" ]]; then
    add_error "throw of string literal in $FILE_PATH — throw an Error (or subclass) instead\n${THROW_STRING}${THROW_TSTR}"
  fi

  rm -f "$ts_ast_err_file" "$ts_ast_rc_file"
  if [[ "$ts_ast_failed" -ne 0 ]]; then
    add_error "ast-grep failed while scanning $FILE_PATH (${ts_ast_fail_detail:-unknown error}) — error-handling rules could not be verified; fix the tool/file and re-edit"
  fi
fi

# throw of numeric/boolean/null/undefined literal — match anywhere on line,
# strip line comments and inline /* */ blocks first so `// throw 5` style
# annotations and example code in comments don't trigger.
THROW_LITERAL=$(awk '
  {
    line = $0
    # Strip /* ... */ blocks on a single line (heuristic; multi-line not handled).
    gsub(/\/\*.*\*\//, "", line)
    # Strip // line comments (heuristic — does not preserve `//` inside a string,
    # which is rare in real code).
    sub(/\/\/.*$/, "", line)
    if (match(line, /(^|[^a-zA-Z_$])throw[ \t]+(-?[0-9]+(\.[0-9]+)?|null|undefined|true|false)([ \t]|;|}|$)/)) {
      print NR ": " $0
    }
  }
' "$FILE_PATH" 2>/dev/null | head -3)
if [[ -n "$THROW_LITERAL" ]]; then
  add_error "throw of non-Error literal in $FILE_PATH — throw an Error (or subclass) instead\n${THROW_LITERAL}"
fi

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

# --- Docs (soft advisory, never blocks) ---
# Exported API should carry a concise JSDoc. Advisory only — kept out of
# MESSAGES so it never sets the failing gate. Skips tests, barrels, declarations.
DOC_ADVISORY=""
_ts_base="$(basename "$FILE_PATH")"
if [[ ! "$FILE_PATH" =~ \.(test|spec)\.(ts|tsx)$ && ! "$FILE_PATH" =~ \.d\.ts$ \
      && "$_ts_base" != "index.ts" && "$_ts_base" != "index.tsx" ]]; then
  _undoc=$(awk '
    /^[[:space:]]*$/   { next }   # blanks do not reset the doc context
    /^[[:space:]]*\/\// { next }  # line comments / pragmas sit between doc and export
    {
      if ($0 ~ /^export (async )?function / || $0 ~ /^export (abstract )?class / \
          || $0 ~ /^export default / || $0 ~ /^export (const|interface|type|enum) [A-Z]/ \
          || $0 ~ /^export const [a-z_][A-Za-z0-9_]* = (async )?(\(|function)/) {
        if (prev !~ /\*\/[[:space:]]*$/ && prev !~ /^[[:space:]]*\/\*\*/) printf "%d: %s\n", NR, $0
      }
      prev=$0
    }
  ' "$FILE_PATH" 2>/dev/null | head -3)
  if [[ -n "$_undoc" ]]; then
    DOC_ADVISORY="Exported API missing a JSDoc in $FILE_PATH — add a concise /** */ doc:\n${_undoc}"
  fi
  _verbose_doc=$(awk '
    !inb && /\/\*\*/ { inb=1; start=NR; cnt=0 }   # !inb: a /** in prose must not reset the count mid-block
    inb { cnt++ }
    inb && /\*\// { if (cnt>12) printf "%d: JSDoc block is %d lines — trim to the essentials\n", start, cnt; inb=0 }
  ' "$FILE_PATH" 2>/dev/null | head -2)
  if [[ -n "$_verbose_doc" ]]; then
    DOC_ADVISORY="${DOC_ADVISORY:+$DOC_ADVISORY\n}Verbose JSDoc in $FILE_PATH — docs must be present but concise:\n${_verbose_doc}"
  fi
fi

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

# --- Output ---

if [[ -n "$MESSAGES" ]]; then
  # Record this file's violation in the gate status file (entry keyed by file
  # path — does not clobber failures recorded for other files or hooks).
  GATE_DIR="$PROJECT_ROOT/.claude/tmp"
  GATE_FILE="$GATE_DIR/quality-gate-status.json"
  mkdir -p "$GATE_DIR"
  gate_record_failure "$GATE_FILE" "$FILE_PATH" "ts-quality-hook" \
    "Post-edit quality violation(s) detected" "$MESSAGES"

  jq -n --arg ctx "$MESSAGES" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("QUALITY VIOLATION — fix before proceeding:\n" + $ctx)
    }
  }'
else
  # Clear this file's entry now that it passes (only if this hook set it).
  # Other files' failures stay recorded; the gate only flips to passing when
  # no entry remains.
  GATE_FILE="$PROJECT_ROOT/.claude/tmp/quality-gate-status.json"
  gate_clear_file "$GATE_FILE" "$FILE_PATH" "ts-quality-hook"

  # Advisories (non-blocking — no gate write). Duplication + docs combined into
  # a single additionalContext so the hook emits exactly one JSON object.
  ADVISORY="$DUPLICATION_WARNING"
  [[ -n "$DOC_ADVISORY" ]] && ADVISORY="${ADVISORY:+$ADVISORY\n}$DOC_ADVISORY"
  [[ -n "$ERR_ADVISORY" ]] && ADVISORY="${ADVISORY:+$ADVISORY\n}$ERR_ADVISORY"
  if [[ -n "$ADVISORY" ]]; then
    jq -n --arg ctx "$ADVISORY" '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": $ctx
      }
    }'
  fi
fi

exit 0
