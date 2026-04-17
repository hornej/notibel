#!/bin/bash
# Claude Code notification hook for Notibel.

set -u

NOTIBEL_CONFIG_FILE="${NOTIBEL_CONFIG_FILE:-$HOME/.config/notibel/config.env}"
if [ -f "$NOTIBEL_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$NOTIBEL_CONFIG_FILE"
fi

NOTIBEL_TOPIC="${NOTIBEL_TOPIC:-claude}"
NOTIBEL_URL="${NOTIBEL_URL:-http://127.0.0.1:8787}"
NOTIBEL_PUBLISH_TOKEN="${NOTIBEL_PUBLISH_TOKEN:-}"
NOTIBEL_BWS_PROJECT_ID="${NOTIBEL_BWS_PROJECT_ID:-}"
NOTIBEL_BWS_SERVICE="${NOTIBEL_BWS_SERVICE:-codex.bitwarden.secrets-manager}"
NOTIBEL_BWS_ACCOUNT="${NOTIBEL_BWS_ACCOUNT:-default}"
PLAY_SOUND="${PLAY_SOUND:-true}"

HOOK_INPUT=""
if [ ! -t 0 ]; then
    HOOK_INPUT=$(cat)
fi

TITLE="${1:-Claude Code}"
MESSAGE="${2:-Response complete}"
SOURCE="claude-code"
HOST_NAME=""

extract_text_content() {
    jq -r '
        if type == "string" then
            .
        elif type == "array" then
            [ .[] | select(.type == "text") | .text ] | join("\n")
        else
            empty
        end
    ' 2>/dev/null
}

extract_last_msg_from_inline_transcript() {
    local payload="$1"
    echo "$payload" | jq -c '
        .transcript // []
        | map(select(.message.role? == "assistant"))
        | last
        | .message.content // empty
    ' 2>/dev/null | extract_text_content
}

extract_last_msg_from_transcript_path() {
    local transcript_path="$1"
    [ -n "$transcript_path" ] || return 0
    [ -f "$transcript_path" ] || return 0

    tail -n 200 "$transcript_path" | jq -s -c '
        map(select(.type == "assistant" and .message.role? == "assistant"))
        | last
        | .message.content // empty
    ' 2>/dev/null | extract_text_content
}

if [ -n "$HOOK_INPUT" ]; then
    CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null)
    STOP_REASON=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_reason // empty' 2>/dev/null)
    TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
    LAST_MSG=$(extract_last_msg_from_transcript_path "$TRANSCRIPT_PATH")

    if [ -z "$LAST_MSG" ]; then
        LAST_MSG=$(extract_last_msg_from_inline_transcript "$HOOK_INPUT")
    fi

    if [ -n "$PROJECT_NAME" ]; then
        TITLE="Claude Code · $PROJECT_NAME"
    fi

    if [ -n "$LAST_MSG" ]; then
        MESSAGE="$LAST_MSG"
    elif [ -n "$STOP_REASON" ]; then
        MESSAGE="$STOP_REASON"
    fi
fi

if command -v scutil >/dev/null 2>&1; then
    HOST_NAME=$(scutil --get ComputerName 2>/dev/null || true)
fi
if [ -z "$HOST_NAME" ]; then
    HOST_NAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
fi
HOST_NAME=$(echo "$HOST_NAME" | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
if [ -n "$HOST_NAME" ]; then
    SOURCE="claude-code on $HOST_NAME"
fi

load_publish_token_from_bitwarden() {
    [ -n "$NOTIBEL_PUBLISH_TOKEN" ] && return 0
    [ -n "$NOTIBEL_BWS_PROJECT_ID" ] || return 0

    command -v security >/dev/null 2>&1 || return 0
    command -v bws >/dev/null 2>&1 || return 0

    local access_token
    access_token=$(security find-generic-password -w -s "$NOTIBEL_BWS_SERVICE" -a "$NOTIBEL_BWS_ACCOUNT" 2>/dev/null) || return 0

    local secret_id
    secret_id=$(BWS_ACCESS_TOKEN="$access_token" \
        bws secret list "$NOTIBEL_BWS_PROJECT_ID" 2>/dev/null | \
        jq -r '.[] | select(.key == "NOTIBEL_PUBLISH_TOKEN") | .id' | \
        head -n 1) || return 0
    [ -n "$secret_id" ] || return 0

    NOTIBEL_PUBLISH_TOKEN=$(BWS_ACCESS_TOKEN="$access_token" \
        bws secret get "$secret_id" 2>/dev/null | jq -r '.value // empty') || return 0
}

publish_notibel() {
    [ -n "$NOTIBEL_TOPIC" ] || return 0
    load_publish_token_from_bitwarden

    local base_url="${NOTIBEL_URL%/}"
    local payload
    payload=$(jq -n \
        --arg title "$TITLE" \
        --arg message "$MESSAGE" \
        --arg source "$SOURCE" \
        '{title: $title, message: $message, source: $source}')

    if [ -n "$NOTIBEL_PUBLISH_TOKEN" ]; then
        curl -fsS -o /dev/null --max-time 5 \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $NOTIBEL_PUBLISH_TOKEN" \
            -d "$payload" \
            "$base_url/v1/publish/$NOTIBEL_TOPIC"
    else
        curl -fsS -o /dev/null --max-time 5 \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$base_url/v1/publish/$NOTIBEL_TOPIC"
    fi
}

play_sound() {
    if [ "$PLAY_SOUND" = "true" ] && [ "$(uname)" = "Darwin" ]; then
        afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
    fi
}

publish_notibel
play_sound

exit 0
