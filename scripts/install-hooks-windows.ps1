param(
    [Parameter(Mandatory = $true)]
    [string]$ServerUrl,
    [Parameter(Mandatory = $true)]
    [string]$BitwardenProjectId,
    [string]$RepoRoot = "",
    [string]$ClaudeSettings = (Join-Path $HOME ".claude\settings.json"),
    [string]$CodexConfig = (Join-Path $HOME ".codex\config.toml"),
    [string]$ConfigFile = (Join-Path $HOME ".config\notibel\config.env")
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Update-ClaudeSettings {
    param(
        [string]$Path,
        [string]$Command
    )

    function Test-IsLegacyClaudeCommand {
        param([string]$Current)

        return (
            $Current -eq $Command -or
            $Current -like "*ai-notifications*notify*" -or
            $Current -like "*notibel*notify.sh*" -or
            $Current -like "*notibel*notify.ps1*" -or
            $Current -like "*notibel*claude-notify*" -or
            $Current -like "*notibel*claude-notify.cmd*" -or
            $Current -like "*notibel*claude-notify.ps1*"
        )
    }

    function Set-ClaudeCommandHook {
        param(
            [psobject]$HooksObject,
            [string]$EventName
        )

        $entries = @()
        $property = $HooksObject.PSObject.Properties[$EventName]
        if ($null -ne $property) {
            $entries = @($property.Value)
        } else {
            $HooksObject | Add-Member -NotePropertyName $EventName -NotePropertyValue @()
        }

        $updatedEntries = @()
        $hasDesired = $false

        foreach ($entry in $entries) {
            if ($null -eq $entry.hooks) {
                $updatedEntries += $entry
                continue
            }

            $newHooks = @()
            foreach ($hook in @($entry.hooks)) {
                if ($hook.type -ne "command") {
                    $newHooks += $hook
                    continue
                }

                $current = [string]$hook.command
                if (Test-IsLegacyClaudeCommand -Current $current) {
                    if (-not $hasDesired) {
                        $hook.command = $Command
                        $hasDesired = $true
                        $newHooks += $hook
                    }
                } else {
                    $newHooks += $hook
                }
            }

            if ($newHooks.Count -gt 0) {
                $entry.hooks = $newHooks
                $updatedEntries += $entry
            }
        }

        if (-not $hasDesired) {
            $updatedEntries += [pscustomobject]@{
                matcher = ""
                hooks = @(
                    [pscustomobject]@{
                        type = "command"
                        command = $Command
                    }
                )
            }
        }

        $HooksObject.$EventName = @($updatedEntries)
    }

    if (Test-Path -LiteralPath $Path) {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } else {
        $data = [pscustomobject]@{}
    }

    if ($null -eq $data.hooks) {
        $data | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    Set-ClaudeCommandHook -HooksObject $data.hooks -EventName "Stop"
    Set-ClaudeCommandHook -HooksObject $data.hooks -EventName "StopFailure"

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $data | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $Path -Value ($json + "`n")
}

function Update-CodexConfig {
    param(
        [string]$Path,
        [string]$CommandPath
    )

    $notifyParts = @(
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $CommandPath
    )
    $quotedNotifyParts = @(
        foreach ($part in $notifyParts) {
            "'" + ($part -replace "'", "''") + "'"
        }
    )
    $notifyLine = "notify = [" + ($quotedNotifyParts -join ", ") + "]"
    $content = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw } else { "" }

    if ($content -match '(?m)^notify\s*=.*$') {
        $content = [regex]::Replace($content, '(?m)^notify\s*=.*$', $notifyLine, 1)
    } elseif ($content) {
        $match = [regex]::Match($content, '(?m)^model_reasoning_effort\s*=.*$')
        if (-not $match.Success) {
            $match = [regex]::Match($content, '(?m)^model\s*=.*$')
        }

        if ($match.Success) {
            $insertAt = $match.Index + $match.Length
            $content = $content.Insert($insertAt, "`n$notifyLine")
        } else {
            $content = "$notifyLine`n$content"
        }
    } else {
        $content = "$notifyLine`n"
    }

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $content
}

function Update-NotibelConfig {
    param(
        [string]$Path,
        [string]$ServerUrlValue,
        [string]$ProjectId
    )

    $map = [ordered]@{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) {
                continue
            }
            $parts = $trimmed -split "=", 2
            $map[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    $map["NOTIBEL_URL"] = $ServerUrlValue.TrimEnd("/")
    $map["NOTIBEL_BWS_PROJECT_ID"] = $ProjectId
    if (-not $map.Contains("NOTIBEL_BWS_TARGET")) {
        $map["NOTIBEL_BWS_TARGET"] = "codex.bitwarden.secrets-manager"
    }

    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $lines = foreach ($key in $map.Keys | Sort-Object) {
        "$key=$($map[$key])"
    }
    Set-Content -LiteralPath $Path -Value ($lines -join "`n")
}

$claudeCommand = (Join-Path $RepoRoot "claude-notify.cmd")
$codexCommand = (Join-Path $RepoRoot "codex-notify.ps1")

Update-ClaudeSettings -Path $ClaudeSettings -Command $claudeCommand
Update-CodexConfig -Path $CodexConfig -CommandPath $codexCommand
Update-NotibelConfig -Path $ConfigFile -ServerUrlValue $ServerUrl -ProjectId $BitwardenProjectId

Write-Host "Updated Claude settings: $ClaudeSettings"
Write-Host "Updated Codex config: $CodexConfig"
Write-Host "Wrote Notibel config: $ConfigFile"
