param(
    [Parameter(Mandatory = $true)]
    [string]$ServerUrl,
    [Parameter(Mandatory = $true)]
    [string]$BitwardenProjectId,
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$ClaudeSettings = (Join-Path $HOME ".claude\settings.json"),
    [string]$CodexConfig = (Join-Path $HOME ".codex\config.toml"),
    [string]$ConfigFile = (Join-Path $HOME ".config\notibel\config.env")
)

$ErrorActionPreference = "Stop"

function Update-ClaudeSettings {
    param(
        [string]$Path,
        [string]$Command
    )

    if (Test-Path -LiteralPath $Path) {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } else {
        $data = [pscustomobject]@{}
    }

    if ($null -eq $data.hooks) {
        $data | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
    }
    if ($null -eq $data.hooks.Stop) {
        $data.hooks | Add-Member -NotePropertyName Stop -NotePropertyValue @()
    }

    $updated = $false
    foreach ($entry in $data.hooks.Stop) {
        if ($null -eq $entry.hooks) {
            continue
        }
        foreach ($hook in $entry.hooks) {
            if ($hook.type -ne "command") {
                continue
            }
            $current = [string]$hook.command
            if ($current -eq $Command -or $current -like "*ai-notifications*notify*" -or $current -like "*notibel*claude-notify*") {
                $hook.command = $Command
                $updated = $true
            }
        }
    }

    if (-not $updated) {
        $data.hooks.Stop += [pscustomobject]@{
            hooks = @(
                [pscustomobject]@{
                    type = "command"
                    command = $Command
                }
            )
        }
    }

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

    $notifyLine = "notify = [`"$CommandPath`"]"
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
$codexCommand = (Join-Path $RepoRoot "codex-notify.cmd")

Update-ClaudeSettings -Path $ClaudeSettings -Command $claudeCommand
Update-CodexConfig -Path $CodexConfig -CommandPath $codexCommand
Update-NotibelConfig -Path $ConfigFile -ServerUrlValue $ServerUrl -ProjectId $BitwardenProjectId

Write-Host "Updated Claude settings: $ClaudeSettings"
Write-Host "Updated Codex config: $CodexConfig"
Write-Host "Wrote Notibel config: $ConfigFile"
