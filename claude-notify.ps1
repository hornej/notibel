param(
    [string]$Title = "Claude Code",
    [string]$Message = "Response complete"
)

$HookInput = ""
if ([Console]::IsInputRedirected) {
    $HookInput = [Console]::In.ReadToEnd()
}

function Get-TextContent {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Content
    )

    if ($null -eq $Content) {
        return ""
    }

    if ($Content -is [string]) {
        return $Content
    }

    if ($Content -is [System.Collections.IEnumerable]) {
        $parts = @(
            foreach ($item in $Content) {
                if ($null -ne $item -and $item.type -eq "text" -and $item.text) {
                    [string]$item.text
                }
            }
        )
        return ($parts -join "`n")
    }

    return ""
}

function Get-LastInlineTranscriptMessage {
    param($Payload)

    if ($null -eq $Payload -or $null -eq $Payload.transcript) {
        return ""
    }

    $assistantMessages = @(
        foreach ($entry in $Payload.transcript) {
            if ($null -ne $entry -and $null -ne $entry.message -and $entry.message.role -eq "assistant") {
                $entry.message.content
            }
        }
    )

    if ($assistantMessages.Count -eq 0) {
        return ""
    }

    return Get-TextContent $assistantMessages[-1]
}

function Get-LastTranscriptPathMessage {
    param([string]$TranscriptPath)

    if (-not $TranscriptPath -or -not (Test-Path $TranscriptPath)) {
        return ""
    }

    $assistantMessages = @(
        Get-Content -Path $TranscriptPath -Tail 200 | ForEach-Object {
            try {
                $entry = $_ | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $entry -and $entry.type -eq "assistant" -and $null -ne $entry.message -and $entry.message.role -eq "assistant") {
                    $entry.message.content
                }
            } catch {
            }
        }
    )

    if ($assistantMessages.Count -eq 0) {
        return ""
    }

    return Get-TextContent $assistantMessages[-1]
}

if ($HookInput) {
    try {
        $payload = $HookInput | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $payload = $null
    }

    if ($null -ne $payload) {
        $cwd = [string]$payload.cwd
        if ($cwd) {
            $projectName = Split-Path -Leaf $cwd
            if ($projectName) {
                $Title = "Claude Code · $projectName"
            }
        }

        $lastMessage = Get-LastTranscriptPathMessage ([string]$payload.transcript_path)
        if (-not $lastMessage) {
            $lastMessage = Get-LastInlineTranscriptMessage $payload
        }

        if ($lastMessage) {
            $Message = $lastMessage
        } elseif ($payload.stop_hook_reason) {
            $Message = [string]$payload.stop_hook_reason
        }
    }
}

$publishScript = Join-Path $PSScriptRoot "notify.ps1"
$source = "claude-code"
$computerName = if ($env:COMPUTERNAME) {
    [string]$env:COMPUTERNAME
} else {
    [System.Environment]::MachineName
}
$computerName = $computerName.Trim()
if ($computerName) {
    $source = "claude-code on $computerName"
}
& $publishScript -Title $Title -Message $Message -Source $source -Topic "claude"
exit $LASTEXITCODE
