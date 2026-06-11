#!/usr/bin/env bash
# SessionStart registry sync for the lang-quality plugin.
#
# Mirrors hooks/post-tools.d/*.sh into the claudness runtime registry
# (${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudness/post-tools.d/) under the
# namespaced filename lang-quality@falconiere__<name>.sh, prunes entries
# bearing OUR prefix whose source module is gone, and clears our own crashed
# tmp residue. Other plugins' entries are never touched. The core claudness
# dispatcher executes the synced copies, gated on this plugin being installed.
#
# Silent on success (SessionStart stdout becomes context); errors are
# non-fatal — a failed sync means the registry copy is stale, not broken.

SPEC="lang-quality@falconiere"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SELF_DIR/post-tools.d"
REG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudness/post-tools.d"

# Consume stdin so Claude Code's hook IPC never stalls.
cat > /dev/null 2>&1 || true

[ -d "$SRC_DIR" ] || exit 0
mkdir -p "$REG_DIR" 2>/dev/null || exit 0

# Clear OUR orphaned atomic-write residue from prior crashed runs. Age-gated
# so a concurrent SessionStart's in-flight tmp (seconds old) is never clobbered.
find "$REG_DIR" -maxdepth 1 -name "${SPEC}__*.sh.tmp.*" -mmin +1 -delete 2>/dev/null

# Sync: copy each source module if missing or changed (atomic tmp+mv).
for src in "$SRC_DIR"/*.sh; do
  [ -f "$src" ] || continue
  name=$(basename "$src")
  dst="$REG_DIR/${SPEC}__${name}"
  if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
    tmp="${dst}.tmp.$$"
    if cp "$src" "$tmp" 2>/dev/null; then
      mv "$tmp" "$dst" 2>/dev/null || rm -f "$tmp"
    else
      rm -f "$tmp" 2>/dev/null
    fi
  fi
done

# Prune: remove OUR entries whose source module is gone. Never glob outside
# our own spec prefix.
for dst in "$REG_DIR/${SPEC}__"*.sh; do
  [ -f "$dst" ] || continue
  name=$(basename "$dst")
  src="$SRC_DIR/${name#"${SPEC}"__}"
  [ -f "$src" ] || rm -f "$dst"
done

exit 0
