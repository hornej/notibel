#!/bin/bash
# Codex notification hook for Notibel.

set -u

NOTIBEL_CONFIG_FILE="${NOTIBEL_CONFIG_FILE:-$HOME/.config/notibel/config.env}"
if [ -f "$NOTIBEL_CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$NOTIBEL_CONFIG_FILE"
fi

NOTIBEL_TOPIC="${NOTIBEL_TOPIC:-codex}"
NOTIBEL_URL="${NOTIBEL_URL:-http://127.0.0.1:8787}"
NOTIBEL_PUBLISH_TOKEN="${NOTIBEL_PUBLISH_TOKEN:-}"
NOTIBEL_BWS_PROJECT_ID="${NOTIBEL_BWS_PROJECT_ID:-}"
NOTIBEL_BWS_SERVICE="${NOTIBEL_BWS_SERVICE:-codex.bitwarden.secrets-manager}"
NOTIBEL_BWS_ACCOUNT="${NOTIBEL_BWS_ACCOUNT:-default}"
PLAY_SOUND="${PLAY_SOUND:-true}"
JSON_INPUT="${1:-}"
if [ -z "$JSON_INPUT" ] && [ ! -t 0 ]; then
    JSON_INPUT=$(cat)
fi

[ -n "$JSON_INPUT" ] || exit 0

EVENT_PAYLOAD=$(echo "$JSON_INPUT" | jq -c '
    if .type == "event_msg" and (.payload | type == "object") then
        .payload
    elif (.payload | type? == "object") then
        .payload
    else
        .
    end
' 2>/dev/null)
[ -n "$EVENT_PAYLOAD" ] || exit 0

NOTIFICATION_TYPE=$(echo "$EVENT_PAYLOAD" | jq -r '.type // empty' 2>/dev/null)
case "$NOTIFICATION_TYPE" in
    agent-turn-complete|task_complete)
        ;;
    *)
        exit 0
        ;;
esac

LAST_MSG=$(echo "$EVENT_PAYLOAD" | jq -r '.last_agent_message // .last_assistant_message // ."last-assistant-message" // empty' 2>/dev/null)
PROJECT_CWD=$(echo "$JSON_INPUT" | jq -r '.cwd // .workspace.cwd // .workspace_dir // .workspace.path // .project.root // .project.path // empty' 2>/dev/null)
if [ -z "$PROJECT_CWD" ]; then
    PROJECT_CWD=$(echo "$EVENT_PAYLOAD" | jq -r '.cwd // .workspace.cwd // .workspace_dir // .workspace.path // .project.root // .project.path // empty' 2>/dev/null)
fi
THREAD_TITLE=$(echo "$JSON_INPUT" | jq -r '.thread_title // .threadTitle // .conversation_title // .conversationTitle // .session_title // .sessionTitle // .thread.title // .conversation.title // .session.title // empty' 2>/dev/null)
if [ -z "$THREAD_TITLE" ]; then
    THREAD_TITLE=$(echo "$EVENT_PAYLOAD" | jq -r '.thread_title // .threadTitle // .conversation_title // .conversationTitle // .session_title // .sessionTitle // .thread.title // .conversation.title // .session.title // empty' 2>/dev/null)
fi
TITLE="Codex"
MESSAGE="Task completed"
SOURCE="codex"
PROJECT=""

if [ -z "$PROJECT_CWD" ]; then
    PROJECT_CWD="${PWD:-}"
fi

if [ -n "$PROJECT_CWD" ]; then
    PROJECT=$(basename "$PROJECT_CWD" 2>/dev/null)
fi

HOST_NAME=""
if command -v scutil >/dev/null 2>&1; then
    HOST_NAME=$(scutil --get ComputerName 2>/dev/null || true)
fi
if [ -z "$HOST_NAME" ]; then
    HOST_NAME=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
fi
HOST_NAME=$(echo "$HOST_NAME" | tr '\r\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
if [ -n "$HOST_NAME" ]; then
    SOURCE="codex on $HOST_NAME"
fi

if [ -n "$LAST_MSG" ]; then
    MESSAGE="$LAST_MSG"
fi

is_internal_metadata_message() {
    local message="$1"
    [ -n "$message" ] || return 1

    printf '%s' "$message" | jq -e '
        def allowed_suggestion_item_keys:
            ["id", "title", "description", "prompt", "threadAction", "appIds", "status", "createdAtMs", "updatedAtMs", "reason"];

        def is_known_suggestion_item:
            type == "object"
            and (
                [keys_unsorted[] | select((allowed_suggestion_item_keys | index(.)) | not)]
                | length
            ) == 0;

        type == "object"
        and (
            [keys_unsorted[] | select(. != "title" and . != "suggestions" and . != "exclude" and . != "description" and . != "reason" and . != "projectRoot" and . != "generatedAtMs" and . != "currentSuggestionIds")]
            | length
        ) == 0
        and (
            (keys_unsorted == ["title"] and (.title | type == "string"))
            or
            (keys_unsorted == ["exclude"] and ((.exclude | type) == "string" or (.exclude | type) == "array" or (.exclude | type) == "object"))
            or
            (
                (.suggestions | type == "array")
                and ((.projectRoot? | type) == "string" or .projectRoot? == null)
                and ((.generatedAtMs? | type) == "number" or .generatedAtMs? == null)
                and ((.currentSuggestionIds? | type) == "array" or .currentSuggestionIds? == null)
                and (.suggestions | type == "array")
                and (
                    [.suggestions[]? | is_known_suggestion_item]
                    | all
                )
            )
        )
    ' >/dev/null 2>&1
}

if is_internal_metadata_message "$MESSAGE"; then
    exit 0
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
        --arg project "$PROJECT" \
        --arg threadTitle "$THREAD_TITLE" \
        '{title: $title, message: $message, source: $source, project: $project, threadTitle: $threadTitle}')

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
