#!/usr/bin/env bash
# parse-verdict.sh — turn the CI review bot's issue comment (stdin) into a
# deterministic JSON verdict the babysit loop acts on. Keeps the parsing OUT of
# the LLM prompt so behaviour is testable (scripts/__tests__/parse-verdict.bats
# against a captured real comment) and stable.
#
# stdin : raw comment body (markdown)
# stdout: { is_review_comment, state, complete, verdict, verdict_label, findings[] }
#   state: in_progress | complete | unknown
#     - unknown  → no checkbox checklist found (cannot judge completeness; the
#                  caller degrades to GitHub check-conclusion behaviour)
#     - in_progress → ≥1 unchecked `- [ ]` (review still running; do not act)
#     - complete → ≥1 checkbox AND none unchecked
#   findings[]: { path, line|null, severity, text, key }  (key = path:line:sha1(text)[:8])
#
# Identification is by MARKER, robust to both header states the bot uses
# ("PR Review in Progress" → "Code Review —"): a CI job link, a "Code Review"
# header, or an "agent-merge" verdict label. No marker → is_review_comment:false.
set -o pipefail

command -v jq >/dev/null 2>&1 || { echo "parse-verdict.sh: jq required" >&2; exit 2; }

input=$(cat 2>/dev/null || true)

_empty() { jq -nc '{is_review_comment:false, state:"unknown", complete:false, verdict:"none", verdict_label:"", findings:[]}'; }

# Empty / unreadable stdin → not a review comment.
[ -n "${input//[[:space:]]/}" ] || { _empty; exit 0; }

# --- Identify: marker-based, both states ---
is_review=false
if printf '%s' "$input" | grep -qE 'actions/runs/[0-9]+|Code Review|agent-merge'; then
  is_review=true
fi
if [ "$is_review" != true ]; then _empty; exit 0; fi

# --- Completeness: checkbox state only ---
unchecked=$(printf '%s\n' "$input" | grep -cE '^[[:space:]]*-[[:space:]]\[[[:space:]]\]' || true)
checked=$(printf '%s\n'   "$input" | grep -cE '^[[:space:]]*-[[:space:]]\[[xX]\]'        || true)
boxes=$((unchecked + checked))
if   [ "$boxes" -eq 0 ];     then state="unknown"
elif [ "$unchecked" -gt 0 ]; then state="in_progress"
else                              state="complete"
fi
complete=false; [ "$state" = complete ] && complete=true

# --- Verdict ---
verdict_label=$(printf '%s' "$input" | grep -oE 'agent-merge-[a-z-]+' | head -1 || true)
if printf '%s' "$input" | grep -qE '\*\*Approved\*\*' || [[ "$verdict_label" == *approved* ]]; then
  verdict="approved"
elif printf '%s' "$input" | grep -qiE '\*\*Changes requested\*\*|changes-requested|agent-merge-blocked' || [[ "$verdict_label" == *changes* || "$verdict_label" == *blocked* ]]; then
  verdict="changes"
else
  verdict="none"
fi

# --- Findings: only the `### Findings` … next `### ` block, lines of the form
#     `path[:line]`: severity: text
_sha1() { (sha1sum 2>/dev/null || shasum 2>/dev/null || echo nohash) | cut -c1-8; }
findings_block=$(printf '%s\n' "$input" | awk '/^### Findings[[:space:]]*$/{f=1;next} /^### /{f=0} f')
findings_json="[]"
while IFS= read -r line; do
  [[ "$line" =~ ^\`([^\`]+)\`:\ (blocker|high|medium|low|nit):\ (.*)$ ]] || continue
  raw_path="${BASH_REMATCH[1]}"; sev="${BASH_REMATCH[2]}"; text="${BASH_REMATCH[3]}"
  if [[ "$raw_path" =~ ^(.+):([0-9]+)$ ]]; then path="${BASH_REMATCH[1]}"; ln="${BASH_REMATCH[2]}"; else path="$raw_path"; ln=""; fi
  h=$(printf '%s' "$text" | _sha1)
  key="${path}:${ln}:${h}"
  obj=$(jq -nc --arg path "$path" --arg line "$ln" --arg severity "$sev" --arg text "$text" --arg key "$key" \
    '{path:$path, line:(if $line=="" then null else ($line|tonumber) end), severity:$severity, text:$text, key:$key}') || continue
  findings_json=$(jq -c --argjson o "$obj" '. + [$o]' <<<"$findings_json")
done <<< "$findings_block"

jq -nc \
  --argjson is_review "$is_review" \
  --arg state "$state" \
  --argjson complete "$complete" \
  --arg verdict "$verdict" \
  --arg verdict_label "${verdict_label:-}" \
  --argjson findings "$findings_json" \
  '{is_review_comment:$is_review, state:$state, complete:$complete, verdict:$verdict, verdict_label:$verdict_label, findings:$findings}'
