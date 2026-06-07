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

# shellcheck source=../../lib/detect.sh
. "${BASH_SOURCE%/*}/../../lib/detect.sh"

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
if [[ "$tool_name" == "Write" || "$tool_name" == "Edit" ]]; then
  fp_from_input=$(echo "$input" | jq -r '.tool_input.path // .tool_input.file_path // .tool_input.target_file // empty' 2>/dev/null || echo "")
fi
FILE_PATH="${CLAUDE_FILE_PATHS:-$fp_from_input}"

[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ ! "$FILE_PATH" =~ \.(ts|tsx)$ ]] && exit 0

# Skip files inside git linked worktrees — quality state is for the main checkout only.
_file_git_dir="$(git -C "$(dirname "$FILE_PATH")" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
_file_common_dir="$(git -C "$(dirname "$FILE_PATH")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
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

AS_LINES=$(grep -nE '\)\s+as\s+[a-zA-Z]|\bas\s+any\b|\bas\s+unknown\b|[a-zA-Z>]\s+as\s+[A-Z]|[a-zA-Z>]\s+as\s+(string|number|boolean|object|symbol|bigint|never|undefined)\b' "$FILE_PATH" 2>/dev/null \
  | grep -vE '^\d+:\s*//' \
  | grep -vE '\bas\s+const\b' \
  | grep -vE '\bimport\b' \
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

TS_LINE_COUNT=$(wc -l < "$FILE_PATH" | tr -d ' ')
if [[ "$TS_LINE_COUNT" -gt 300 ]]; then
  add_error "TS file exceeds 300-line limit: $FILE_PATH ($TS_LINE_COUNT lines) — split into smaller modules"
fi

LONG_FUNCS=$(awk '
  /^(export )?(async )?function / || /^const [a-zA-Z_]+ = (async )?\(/ {
    start=NR; name=$0
  }
  start && /^}/ {
    len=NR-start
    if (len > 60) printf "%s:%d (%d lines)\n", name, start, len
    start=0
  }
' "$FILE_PATH" 2>/dev/null)
if [[ -n "$LONG_FUNCS" ]]; then
  add_error "Function too long in $FILE_PATH (>60 lines) — simplify or split"
fi

if [[ "$FILE_PATH" =~ use-.*\.ts$ || "$FILE_PATH" =~ use[A-Z].*\.ts$ ]]; then
  HOOK_COUNT=$(grep -cE '^\s*(const \[|useRef\(|useEffect\()' "$FILE_PATH" 2>/dev/null || true)
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
  for TYPE_NAME in $NEW_TYPES; do
    DUPE_COUNT=$(grep -rl "^export \(interface\|type\) ${TYPE_NAME}[ <{]" "$PROJECT_ROOT/packages" "$PROJECT_ROOT/apps" --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v "$FILE_PATH" | head -1)
    if [[ -n "$DUPE_COUNT" ]]; then
      add_error "Type '$TYPE_NAME' in $FILE_PATH already defined in $DUPE_COUNT — import instead of redefining"
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

# Check: console.log
if grep -nE '^\s*console\.log\(' "$FILE_PATH" 2>/dev/null | grep -vE '^\s*//' | head -1 | grep -q .; then
  CONSOLE_LINES=$(grep -nE '^\s*console\.log\(' "$FILE_PATH" 2>/dev/null | grep -vE '^\s*//' | head -3)
  add_error "Forbidden console.log in $FILE_PATH — use console.error/warn/info\n${CONSOLE_LINES}"
fi

# Check: disable comments (@ts-ignore, @ts-nocheck)
DISABLE_LINES=$(grep -nE '//\s*(@ts-ignore|@ts-nocheck)\b' "$FILE_PATH" 2>/dev/null | head -3)
if [[ -n "$DISABLE_LINES" ]]; then
  add_error "Forbidden disable comment in $FILE_PATH — fix the underlying violation\n${DISABLE_LINES}"
fi

# Check: confirm()/alert() in frontend files
if [[ "$FILE_PATH" == */components/* || "$FILE_PATH" == */routes/* ]]; then
  CONFIRM_LINES=$(grep -nE '\b(confirm|alert)\s*\(' "$FILE_PATH" 2>/dev/null | grep -vE '^\s*//' | grep -vE '(ConfirmDeleteAlert|AlertDialog|customAlert|customConfirm)' | head -3)
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
PROPS_LINES=$(grep -nE '\((props|[a-z]+Props):\s+[A-Z][a-zA-Z]+Props\)' "$FILE_PATH" 2>/dev/null | grep -v 'Readonly' | head -3)
if [[ -n "$PROPS_LINES" ]]; then
  add_error "Mutable props in $FILE_PATH — wrap in Readonly<Props>\n${PROPS_LINES}"
fi

# Check: manual try/catch+toast pattern in components
if [[ "$FILE_PATH" == */components/* || "$FILE_PATH" == */routes/* ]]; then
  CATCH_TOAST=$(awk '/catch\s*\(/{found=1} found && /toast\(/{print NR": "$0; found=0}' "$FILE_PATH" 2>/dev/null | head -3)
  if [[ -n "$CATCH_TOAST" ]]; then
    add_error "Manual try/catch+toast in $FILE_PATH — use shared error handling\n${CATCH_TOAST}"
  fi
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

# --- Output ---

if [[ -n "$MESSAGES" ]]; then
  # Write violation to gate status file for pre-tool blocking
  GATE_DIR="$PROJECT_ROOT/.claude/tmp"
  GATE_FILE="$GATE_DIR/quality-gate-status.json"
  mkdir -p "$GATE_DIR"

  jq -n \
    --arg status "failing" \
    --arg reason "Post-edit quality violation(s) detected" \
    --arg file "$FILE_PATH" \
    --arg violations "$MESSAGES" \
    --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      status: $status,
      reason: $reason,
      source: "ts-quality-hook",
      file: $file,
      violations: $violations,
      updatedAt: $updatedAt
    }' > "$GATE_FILE"

  jq -n --arg ctx "QUALITY VIOLATION — fix before proceeding:\n$MESSAGES" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $ctx
    }
  }'
else
  # Clear gate if this file now passes (only if this hook set it)
  GATE_DIR="$PROJECT_ROOT/.claude/tmp"
  GATE_FILE="$GATE_DIR/quality-gate-status.json"
  if [[ -f "$GATE_FILE" ]]; then
    GATE_SOURCE=$(jq -r '.source // ""' "$GATE_FILE" 2>/dev/null || echo "")
    GATE_FILE_PATH=$(jq -r '.file // ""' "$GATE_FILE" 2>/dev/null || echo "")
    if [[ "$GATE_SOURCE" == "ts-quality-hook" && "$GATE_FILE_PATH" == "$FILE_PATH" ]]; then
      jq -n \
        --arg status "passing" \
        --arg source "ts-quality-hook" \
        --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{status: $status, source: $source, updatedAt: $updatedAt}' > "$GATE_FILE"
    fi
  fi

  # Duplication advisory (non-blocking — no gate write)
  if [[ -n "$DUPLICATION_WARNING" ]]; then
    jq -n --arg ctx "$DUPLICATION_WARNING" '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": $ctx
      }
    }'
  fi
fi

exit 0
