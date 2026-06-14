# Set up the statusline

Wire the statusline into the user's Claude Code `settings.json` so the status
bar renders. The plugin's SessionStart hook already maintains the script
symlink, but Claude Code reads `statusLine` only from `settings.json` and a
plugin cannot declare it — this command adds that one key, safely and
idempotently. It never clobbers an existing custom statusLine and backs the
file up before any write.

## Steps

1. Run the setup script. Pass `--force` through **only** if the user explicitly
   asked to replace an existing custom statusLine:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" $ARGUMENTS
   ```

2. Read the first word of the output (the STATUS token) and report:
   - **WIRED** / **CREATED** — success. Tell the user to **restart the session**
     (or `/clear`) for the status bar to appear; `statusLine` loads at session
     start.
   - **ALREADY** — already wired; nothing to do.
   - **REFUSED** — a different statusLine is already set. Show the current value
     the script printed, and tell the user to re-run `/statusline:setup --force`
     to replace it (or wire it by hand).
   - **ERROR** — relay the message; do not retry blindly.

Do not hand-edit `settings.json` — the script round-trips the JSON and keeps a
`settings.json.bak` backup.
