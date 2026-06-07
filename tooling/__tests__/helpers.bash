#!/usr/bin/env bash
# Shared bats helpers for .tooling script tests.
#
# Each test gets a fresh sandbox: a copy of the target script under
# `<TMP>/<tool>/search.sh`, a writable `<TMP>/.env` next to it (mirroring
# the real `.tooling/.env` parent-relative layout), and a `curl` stub on
# PATH that records its argv to `<TMP>/curl.log` instead of hitting the
# network. Tests assert against `curl.log` to verify env resolution.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setup_sandbox() {
  local tool="$1"
  export SANDBOX="$(mktemp -d)"
  export CURL_LOG="$SANDBOX/curl.log"
  export TOOL_DIR="$SANDBOX/$tool"
  export ENV_FILE="$SANDBOX/.env"

  mkdir -p "$TOOL_DIR" "$SANDBOX/bin"
  cp "$REPO_ROOT/.tooling/$tool/search.sh" "$TOOL_DIR/search.sh"
  chmod +x "$TOOL_DIR/search.sh"

  cat > "$SANDBOX/bin/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$CURL_LOG"
# Emit a minimal JSON body so `jq '.'` downstream does not choke.
printf '{}\n'
CURL
  chmod +x "$SANDBOX/bin/curl"

  export PATH="$SANDBOX/bin:$PATH"
}

teardown_sandbox() {
  [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
}

write_env() {
  printf '%s\n' "$@" > "$ENV_FILE"
}
