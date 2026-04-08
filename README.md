# AI Code Assistant Notifications

Get notified on your iPhone (or Mac) when Claude Code or other AI assistants complete a task.

## Quick Setup

### 1. Install ntfy app on your iPhone

1. Download **ntfy** from the [App Store](https://apps.apple.com/us/app/ntfy/id1625396347)
2. Open the app and tap **+** to subscribe to a topic
3. Enter a unique topic name (e.g., `ai-code-notifications-yourname-random123`)
   - ⚠️ Topic names are public, so use something hard to guess!

### 2. Configure your topic

Set your topic as an environment variable:

```bash
export NTFY_TOPIC="ai-code-notifications-yourname-random123"
```

### 3. Test the notification

```bash
./notify.sh "Test" "This is a test notification"
```

You should receive a push notification on your iPhone!

## Claude Code Integration

Add this hook to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "command": "/absolute/path/to/ai-notifications/notify.sh 'Claude Code' 'Response complete'"
      }
    ]
  }
}
```

### Hook types available:
- `Stop` - When Claude finishes responding
- `Notification` - When Claude sends a notification
- `PreToolUse` / `PostToolUse` - Before/after tool execution

## OpenAI Codex Integration

Codex CLI doesn't have native hooks, but you can wrap it:

```bash
# Add to your .zshrc or .bashrc
codex_notify() {
    codex "$@"
    /absolute/path/to/ai-notifications/notify.sh "Codex" "Task completed"
}
alias codex='codex_notify'
```

## Configuration Options

| Variable | Default | Description |
|----------|---------|-------------|
| `NTFY_TOPIC` | `ai-code-notifications-$(whoami)` | Your ntfy topic name |
| `NTFY_SERVER` | `https://ntfy.sh` | ntfy server URL |
| `PLAY_SOUND` | `true` | Play sound on Mac |

## Mac-only Sound

If you only want Mac sounds (no iPhone), set:

```bash
export NTFY_TOPIC=""  # Disable ntfy
export PLAY_SOUND="true"
```

## Troubleshooting

### Notifications not appearing on iPhone?

1. Make sure you subscribed to the correct topic in the ntfy app
2. Check that notifications are enabled for ntfy in iOS Settings
3. Test with: `curl -d "test" ntfy.sh/your-topic-name`

### Sound not playing on Mac?

The script uses `/System/Library/Sounds/Glass.aiff`. You can change this to any other system sound in `/System/Library/Sounds/`.
