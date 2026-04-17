param(
    [string]$JsonInput = ""
)

if (-not $JsonInput -and [Console]::IsInputRedirected) {
    $JsonInput = [Console]::In.ReadToEnd()
}

if (-not $JsonInput) {
    exit 0
}

try {
    $payload = $JsonInput | ConvertFrom-Json -ErrorAction Stop
} catch {
    exit 0
}

$rootPayload = $payload
$stopHook = [string]$payload.hook_event_name -eq "Stop"
if ([string]$payload.type -eq "event_msg" -and $null -ne $payload.payload) {
    $payload = $payload.payload
}

$payloadType = $payload.PSObject.Properties["type"]
if (-not $stopHook -and $null -eq $payloadType) {
    exit 0
}

$eventType = [string]$payload.type
if (-not $stopHook -and $eventType -ne "agent-turn-complete" -and $eventType -ne "task_complete") {
    exit 0
}

$title = "Codex"
$message = if ($payload.last_assistant_message) {
    [string]$payload.last_assistant_message
} elseif ($payload.'last-assistant-message') {
    [string]$payload.'last-assistant-message'
} elseif ($payload.last_agent_message) {
    [string]$payload.last_agent_message
} else {
    "Task completed"
}

$projectPath = if ($rootPayload.cwd) {
    [string]$rootPayload.cwd
} elseif ($payload.cwd) {
    [string]$payload.cwd
} elseif ($rootPayload.workspace -and $rootPayload.workspace.cwd) {
    [string]$rootPayload.workspace.cwd
} elseif ($payload.workspace -and $payload.workspace.cwd) {
    [string]$payload.workspace.cwd
} elseif ($rootPayload.workspace_dir) {
    [string]$rootPayload.workspace_dir
} elseif ($payload.workspace_dir) {
    [string]$payload.workspace_dir
} else {
    [string](Get-Location)
}

$project = ""
if ($projectPath) {
    $project = Split-Path -Leaf $projectPath
}

$threadTitle = if ($rootPayload.thread_title) {
    [string]$rootPayload.thread_title
} elseif ($payload.thread_title) {
    [string]$payload.thread_title
} elseif ($rootPayload.threadTitle) {
    [string]$rootPayload.threadTitle
} elseif ($payload.threadTitle) {
    [string]$payload.threadTitle
} elseif ($rootPayload.conversation_title) {
    [string]$rootPayload.conversation_title
} elseif ($payload.conversation_title) {
    [string]$payload.conversation_title
} elseif ($rootPayload.conversationTitle) {
    [string]$rootPayload.conversationTitle
} elseif ($payload.conversationTitle) {
    [string]$payload.conversationTitle
} elseif ($rootPayload.session_title) {
    [string]$rootPayload.session_title
} elseif ($payload.session_title) {
    [string]$payload.session_title
} elseif ($rootPayload.sessionTitle) {
    [string]$rootPayload.sessionTitle
} elseif ($payload.sessionTitle) {
    [string]$payload.sessionTitle
} elseif ($rootPayload.thread -and $rootPayload.thread.title) {
    [string]$rootPayload.thread.title
} elseif ($payload.thread -and $payload.thread.title) {
    [string]$payload.thread.title
} elseif ($rootPayload.conversation -and $rootPayload.conversation.title) {
    [string]$rootPayload.conversation.title
} elseif ($payload.conversation -and $payload.conversation.title) {
    [string]$payload.conversation.title
} elseif ($rootPayload.session -and $rootPayload.session.title) {
    [string]$rootPayload.session.title
} elseif ($payload.session -and $payload.session.title) {
    [string]$payload.session.title
} else {
    ""
}

$computerName = if ($env:COMPUTERNAME) { [string]$env:COMPUTERNAME } else { "windows" }
$source = "codex on $computerName"

$publishScript = Join-Path $PSScriptRoot "notify.ps1"
& $publishScript -Title $title -Message $message -Source $source -Project $project -ThreadTitle $threadTitle -Topic "codex"
exit $LASTEXITCODE
