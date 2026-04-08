#!/bin/bash
# AI Code Assistant Notification Script
# Sends push notifications via ntfy.sh and optionally plays a sound

# Configuration
NTFY_TOPIC="${NTFY_TOPIC:-ai-code-notifications-$(whoami)}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
PLAY_SOUND="${PLAY_SOUND:-true}"
MAX_MSG_LENGTH=200  # Truncate long messages

# Read hook input from stdin (Claude Code passes JSON via stdin)
HOOK_INPUT=""
if [ ! -t 0 ]; then
    HOOK_INPUT=$(cat)
fi

# Parse arguments (used as fallback)
TITLE="${1:-AI Assistant}"
MESSAGE="${2:-Task completed}"

# Try to extract info from Claude Code hook input
if [ -n "$HOOK_INPUT" ]; then
    # Extract project/cwd for context
    CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null)
    
    # Extract the stop reason
    STOP_REASON=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_reason // empty' 2>/dev/null)
    
    # Extract transcript for last message preview
    LAST_MSG=$(echo "$HOOK_INPUT" | jq -r '.transcript[-1].message.content // empty' 2>/dev/null | head -c $MAX_MSG_LENGTH)
    
    # Build title with project name
    if [ -n "$PROJECT_NAME" ]; then
        TITLE="Claude Code · $PROJECT_NAME"
    else
        TITLE="Claude Code"
    fi
    
    # Build message with context
    if [ -n "$LAST_MSG" ]; then
        MESSAGE="$LAST_MSG"
        [ ${#LAST_MSG} -ge $MAX_MSG_LENGTH ] && MESSAGE="${MESSAGE}..."
    elif [ -n "$STOP_REASON" ]; then
        MESSAGE="$STOP_REASON"
    else
        MESSAGE="Response complete"
    fi
fi

# Send notification via ntfy
send_ntfy() {
    [ -n "$NTFY_TOPIC" ] || return 0

    curl -s -o /dev/null --max-time 5 \
        -H "Title: $TITLE" \
        -H "Priority: default" \
        -H "Tags: robot,sparkles" \
        -d "$MESSAGE" \
        "$NTFY_SERVER/$NTFY_TOPIC"
}

# Play sound on macOS
play_sound() {
    if [ "$PLAY_SOUND" = "true" ] && [ "$(uname)" = "Darwin" ]; then
        afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
    fi
}

# Main
send_ntfy
play_sound

exit 0
