param(
    [string]$Title = "AI Assistant",
    [string]$Message = "Task completed",
    [string]$Source = "powershell",
    [string]$Project = "",
    [string]$ThreadTitle = "",
    [string]$Topic = ""
)

$NotibelIsWindows = $env:OS -eq "Windows_NT"

function Import-NotibelConfig {
    $configPath = if ($env:NOTIBEL_CONFIG_FILE) {
        $env:NOTIBEL_CONFIG_FILE
    } else {
        Join-Path $HOME ".config/notibel/config.env"
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        return
    }

    foreach ($line in Get-Content -LiteralPath $configPath) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (-not $name) {
            continue
        }
        if (-not (Test-Path "Env:$name")) {
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

$signature = @"
using System;
using System.Runtime.InteropServices;

public static class NotibelCredMan {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public UInt32 Flags;
        public UInt32 Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, uint type, uint reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern void CredFree([In] IntPtr cred);
}
"@

if ($NotibelIsWindows -and -not ("NotibelCredMan" -as [type])) {
    Add-Type -TypeDefinition $signature
}

function Get-BwsAccessToken {
    param([string]$Target = "codex.bitwarden.secrets-manager")

    if (-not $NotibelIsWindows) {
        return $null
    }

    $credPtr = [IntPtr]::Zero
    if (-not [NotibelCredMan]::CredRead($Target, 1, 0, [ref]$credPtr)) {
        return $null
    }

    try {
        $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($credPtr, [type][NotibelCredMan+CREDENTIAL])
        if ($cred.CredentialBlobSize -eq 0 -or $cred.CredentialBlob -eq [IntPtr]::Zero) {
            return ""
        }
        $bytes = New-Object byte[] $cred.CredentialBlobSize
        [System.Runtime.InteropServices.Marshal]::Copy($cred.CredentialBlob, $bytes, 0, $cred.CredentialBlobSize)
        return [System.Text.Encoding]::Unicode.GetString($bytes).TrimEnd([char]0)
    } finally {
        if ($credPtr -ne [IntPtr]::Zero) {
            [NotibelCredMan]::CredFree($credPtr)
        }
    }
}

function Resolve-NotibelPublishToken {
    if ($env:NOTIBEL_PUBLISH_TOKEN) {
        return $env:NOTIBEL_PUBLISH_TOKEN
    }

    $projectId = if ($env:NOTIBEL_BWS_PROJECT_ID) { $env:NOTIBEL_BWS_PROJECT_ID } else { "" }
    if (-not $projectId) {
        return ""
    }

    $bws = Get-Command bws -ErrorAction SilentlyContinue
    if (-not $bws) {
        return ""
    }

    $target = if ($env:NOTIBEL_BWS_TARGET) { $env:NOTIBEL_BWS_TARGET } else { "codex.bitwarden.secrets-manager" }
    $accessToken = Get-BwsAccessToken -Target $target
    if ($null -eq $accessToken) {
        return ""
    }

    $oldToken = $env:BWS_ACCESS_TOKEN
    $env:BWS_ACCESS_TOKEN = $accessToken
    try {
        $secretListJson = & $bws.Source secret list $projectId 2>$null
        if (-not $secretListJson) {
            return ""
        }

        $secretList = $secretListJson | ConvertFrom-Json
        $secretId = ($secretList | Where-Object { $_.key -eq "NOTIBEL_PUBLISH_TOKEN" } | Select-Object -First 1 -ExpandProperty id)
        if (-not $secretId) {
            return ""
        }

        $secretJson = & $bws.Source secret get $secretId 2>$null
        if (-not $secretJson) {
            return ""
        }

        $secret = $secretJson | ConvertFrom-Json
        return [string]$secret.value
    } finally {
        if ($null -eq $oldToken) {
            Remove-Item Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue
        } else {
            $env:BWS_ACCESS_TOKEN = $oldToken
        }
    }
}

Import-NotibelConfig

$NotibelTopic = if ($Topic) { $Topic } elseif ($env:NOTIBEL_TOPIC) { $env:NOTIBEL_TOPIC } else { "codex" }
$NotibelUrl = if ($env:NOTIBEL_URL) { $env:NOTIBEL_URL.TrimEnd("/") } else { "http://127.0.0.1:8787" }
$PublishToken = Resolve-NotibelPublishToken

$Headers = @{
    "Content-Type" = "application/json"
}

if ($PublishToken) {
    $Headers["Authorization"] = "Bearer $PublishToken"
}

$Payload = @{
    title = $Title
    message = $Message
    source = $Source
    project = $Project
    threadTitle = $ThreadTitle
} | ConvertTo-Json -Compress

try {
    Invoke-RestMethod `
        -Method Post `
        -Uri "$NotibelUrl/v1/publish/$NotibelTopic" `
        -Headers $Headers `
        -Body $Payload | Out-Null
} catch {
    [Console]::Error.WriteLine("Notibel publish failed: $($_.Exception.Message)")
}
