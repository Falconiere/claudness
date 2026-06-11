#!/usr/bin/env bash
# Shared runtime registry for hook modules contributed by other plugins.
# Modules placed under <root>/<event>.d/<plugin-spec>.<name>.sh are executed by
# the core dispatcher after its built-in modules, gated on the owning plugin
# being installed. The registry holds GENERATED state (synced each session by
# each plugin's register.sh); the source of truth for a module is its own plugin.

# claudness_registry_root -> prints the registry root dir (not created).
claudness_registry_root() {
  printf '%s/claudness' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# claudness_registry_event_dir EVENT -> prints "<root>/<event-slug>.d".
# Known events map to the repo's existing naming; others are CamelCase->kebab.
claudness_registry_event_dir() {
  local event="$1" slug
  case "$event" in
    PreToolUse)  slug="pre-tools" ;;
    PostToolUse) slug="post-tools" ;;
    *)
      slug=$(printf '%s' "$event" \
        | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' \
        | tr '[:upper:]' '[:lower:]')
      ;;
  esac
  printf '%s/%s.d' "$(claudness_registry_root)" "$slug"
}
