#!/bin/bash
# Codex Notification Script
# Receives JSON as first argument when Codex completes a task

# Configuration
NTFY_TOPIC="${NTFY_TOPIC:-ai-code-notifications-$(whoami)}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
PLAY_SOUND="${PLAY_SOUND:-true}"
MAX_MSG_LENGTH="${MAX_MSG_LENGTH:-500}"

# Parse JSON argument
JSON_INPUT="${1:-{}}"

# Extract notification type
NOTIFICATION_TYPE=$(echo "$JSON_INPUT" | jq -r '.type // empty' 2>/dev/null)

# Only notify on agent-turn-complete
if [ "$NOTIFICATION_TYPE" != "agent-turn-complete" ]; then
    exit 0
fi

# Extract context from Codex JSON
# last-assistant-message contains the final response preview
LAST_MSG=$(echo "$JSON_INPUT" | jq -r '.["last-assistant-message"] // empty' 2>/dev/null | head -c $MAX_MSG_LENGTH)

# Build title
TITLE="Codex"

# Build message with context
if [ -n "$LAST_MSG" ]; then
    MESSAGE="$LAST_MSG"
    [ ${#LAST_MSG} -ge $MAX_MSG_LENGTH ] && MESSAGE="${MESSAGE}..."
else
    MESSAGE="Task completed"
fi

if [ -n "$NTFY_TOPIC" ]; then
    curl -s -o /dev/null --max-time 5 \
        -H "Title: $TITLE" \
        -H "Priority: default" \
        -H "Tags: robot,white_check_mark" \
        -d "$MESSAGE" \
        "$NTFY_SERVER/$NTFY_TOPIC"
fi

# Play sound on macOS
if [ "$PLAY_SOUND" = "true" ] && [ "$(uname)" = "Darwin" ]; then
    afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
fi

exit 0
