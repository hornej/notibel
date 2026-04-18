#!/bin/bash
# Codex turn-ended notify wrapper for Notibel on macOS.

set -u

NOTIBEL_CONFIG_FILE="${NOTIBEL_CONFIG_FILE:-$HOME/.config/notibel/config.env}"
if [ -f "$NOTIBEL_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$NOTIBEL_CONFIG_FILE"
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
JSON_INPUT="${1:-}"
if [ -z "$JSON_INPUT" ] && [ ! -t 0 ]; then
    JSON_INPUT=$(cat)
fi

[ -n "$JSON_INPUT" ] || exit 0

run_chained_notify() {
    [ -n "${NOTIBEL_CODEX_CHAIN_NOTIFY_JSON_B64:-}" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local chain_json=""
    chain_json=$(printf '%s' "$NOTIBEL_CODEX_CHAIN_NOTIFY_JSON_B64" | base64 -D 2>/dev/null) || \
        chain_json=$(printf '%s' "$NOTIBEL_CODEX_CHAIN_NOTIFY_JSON_B64" | base64 -d 2>/dev/null) || \
        return 0

    local -a chain_argv=()
    while IFS= read -r part; do
        chain_argv+=("$part")
    done < <(printf '%s' "$chain_json" | jq -r '.[]' 2>/dev/null)

    [ "${#chain_argv[@]}" -gt 0 ] || return 0
    printf '%s' "$JSON_INPUT" | "${chain_argv[@]}" >/dev/null 2>&1 || true
}

run_notibel_notify() {
    printf '%s' "$JSON_INPUT" | "$SCRIPT_DIR/codex-notify.sh" >/dev/null 2>&1 || true
}

run_chained_notify
run_notibel_notify

exit 0
