#!/usr/bin/env bash
# /statusline:setup — idempotently wire the statusline into settings.json.
#
# Claude Code reads `statusLine` only from settings.json, and a plugin may not
# declare it in its manifest. So installing the plugin maintains the symlink
# but cannot turn the status bar on by itself. This script adds the one key,
# safely:
#   - never clobbers an existing custom statusLine (pass --force to override)
#   - backs settings.json up to settings.json.bak before any write
#   - idempotent: re-running once wired is a no-op
#
# Requires python3 for the JSON edit (a half-written settings.json would brick
# the session — worth the one dependency to round-trip it correctly). Prints a
# leading STATUS token (WIRED/CREATED/ALREADY/REFUSED/ERROR) the command reads.

set -euo pipefail

force=0
for arg in "$@"; do
  case "$arg" in
    --force | -f) force=1 ;;
    *) ;;
  esac
done

cfg_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$cfg_dir/settings.json"

# Point at the stable symlink the SessionStart hook maintains. Mirror the path
# style the README documents: a literal ~ for the default dir (Claude Code runs
# the statusLine command through a shell, so ~ expands), else the explicit dir.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  desired_cmd="bash \"$CLAUDE_CONFIG_DIR/statusline/statusline.sh\""
else
  desired_cmd="bash ~/.claude/statusline/statusline.sh"
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR python3 not found — add this to $settings manually:"
  echo "  \"statusLine\": { \"type\": \"command\", \"command\": \"$desired_cmd\" }"
  exit 1
fi

python3 - "$settings" "$desired_cmd" "$force" <<'PY'
import json, os, shutil, sys

settings, desired_cmd, force = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
marker = "statusline/statusline.sh"
block = {"type": "command", "command": desired_cmd}

created = False
if os.path.exists(settings) and os.path.getsize(settings) > 0:
    try:
        with open(settings) as f:
            data = json.load(f)
    except (ValueError, OSError) as e:
        print(f"ERROR could not parse {settings}: {e} — not touching it")
        sys.exit(1)
    if not isinstance(data, dict):
        print(f"ERROR {settings} is not a JSON object — not touching it")
        sys.exit(1)
else:
    data, created = {}, True

cur = data.get("statusLine")

# Already ours (matches whether it was wired via ~ or an explicit config dir).
if isinstance(cur, dict) and marker in str(cur.get("command", "")):
    print("ALREADY statusLine already points at the statusline plugin — nothing to do.")
    sys.exit(0)

# A different statusLine is present: refuse rather than overwrite, unless forced.
if cur is not None and not force:
    print("REFUSED a different statusLine is already set in settings.json.")
    print("  current: " + json.dumps(cur))
    print("  re-run with --force to replace it, or set it manually:")
    print('    "statusLine": ' + json.dumps(block))
    sys.exit(3)

os.makedirs(os.path.dirname(settings) or ".", exist_ok=True)
if os.path.exists(settings):
    shutil.copy2(settings, settings + ".bak")

data["statusLine"] = block
with open(settings, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

if created:
    print(f"CREATED wrote {settings} with the statusLine wired. Restart the session to see it.")
else:
    print(f"WIRED added statusLine to {settings} (backup: settings.json.bak). Restart the session to see it.")
PY
