# Notibel

Self-hosted notifications for AI coding workflows.

`Codex` and `Claude Code` publish completion events to your own server. `notibeld` stores a short event history, fans out to registered devices, and sends native iPhone push notifications through your own APNs key.

## What Is In This Repo

- `cmd/notibeld`: Go server
- `ios/Notibel.xcodeproj`: SwiftUI iPhone app
- `notify.sh`, `codex-notify.sh`: macOS Claude/Codex publishers
- `notify.ps1`, `claude-notify.ps1`, `codex-notify.ps1`: Windows publishers
- `scripts/install-hooks-macos.py`: installs the macOS Claude/Codex hooks
- `scripts/install-hooks-windows.ps1`: installs the Windows Claude/Codex hooks
- `scripts/install-systemd.sh`: generic Linux systemd deploy
- `scripts/install-systemd-from-bitwarden.sh`: deploy using Bitwarden Secrets Manager
- `deploy/notibel.service`: systemd unit

## Why Notibel Instead Of Plain ntfy?

The mental model is the same as `ntfy`: simple topics, a tiny server, and lightweight publishers.

The difference is iPhone delivery. If you want your own branded app, you need your own APNs connection. Notibel owns that APNs path directly instead of depending on `ntfy.sh`.

## Architecture

1. A desktop hook publishes `POST /v1/publish/{topic}`.
2. `notibeld` stores the event in a local JSON store.
3. `notibeld` finds registered iPhone installations subscribed to that topic.
4. `notibeld` sends APNs alerts using your app bundle ID and APNs auth key.
5. The iPhone app reads the same event history and manages topic subscriptions.

## Prerequisites

For a full setup you need:

- Go 1.24+ to build the server
- Xcode to build and sign the iPhone app
- `jq`, `curl`, `ssh`, and `scp`
- Bitwarden Secrets Manager plus the `bws` CLI
- A Bitwarden machine access token stored locally
  - macOS: Keychain service `codex.bitwarden.secrets-manager`, account `default`
  - Windows: Credential Manager target `codex.bitwarden.secrets-manager`
- A Linux ARM64 host reachable over SSH with `sudo`
- An Apple Developer account with APNs access

## Bitwarden Secrets Layout

Create a Bitwarden Secrets Manager project for Notibel and store these keys:

- `NOTIBEL_PUBLISH_TOKEN`
- `NOTIBEL_APP_TOKEN`
- `NOTIBEL_APNS_KEY_P8`
- `NOTIBEL_APNS_KEY_ID`
- `NOTIBEL_APNS_TEAM_ID`
- `NOTIBEL_APNS_BUNDLE_ID`
- `NOTIBEL_APNS_ENV`

Notes:

- `NOTIBEL_APNS_KEY_P8` must contain the full `.p8` file contents, including the `BEGIN` and `END` lines.
- `NOTIBEL_APNS_ENV` should be `development` for a dev-signed build and `production` for TestFlight/App Store builds.
- `NOTIBEL_PUBLISH_TOKEN` protects the publish API used by desktop hooks.
- `NOTIBEL_APP_TOKEN` protects the iPhone app APIs for history and device registration.

## Apple / APNs Setup

1. Create or choose an iOS App ID in the Apple Developer portal.
2. Enable Push Notifications for that App ID.
3. Create an APNs auth key in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/authkeys/list).
4. Download the `.p8` file once.
5. Record the APNs `Key ID`, your Apple `Team ID`, and the app `Bundle ID`.
6. Store those values in Bitwarden under the `NOTIBEL_APNS_*` keys listed above.

The bundle ID in Bitwarden must match the iPhone app you actually sign and install.

## Build The Server

Build the Linux ARM64 binary that the deployment script pushes to your host:

```bash
./scripts/build-linux-arm64.sh
```

This writes:

- `dist/notibeld-linux-arm64`

## Deploy The Server

### Reproducible deploy from Bitwarden

If your publish/app/APNs secrets live in Bitwarden, deploy with:

```bash
NOTIBEL_BWS_PROJECT_ID="<bitwarden-project-id>" \
bash ./scripts/install-systemd-from-bitwarden.sh <ssh-host>
```

Example:

```bash
NOTIBEL_BWS_PROJECT_ID="<bitwarden-project-id>" \
bash ./scripts/install-systemd-from-bitwarden.sh <ssh-host>
```

What this does:

- copies `dist/notibeld-linux-arm64` to the remote host
- installs `deploy/notibel.service`
- writes `/etc/notibel/notibel.env`
- writes the APNs `.p8` key to `/etc/notibel/AuthKey_<KEY_ID>.p8`
- enables and restarts `notibel.service`

### Deploy without Bitwarden

If you do not want to inject secrets from Bitwarden, export them yourself and run:

```bash
NOTIBEL_PUBLISH_TOKEN="..." \
NOTIBEL_APP_TOKEN="..." \
NOTIBEL_APNS_KEY_P8="$(cat /path/to/AuthKey_XXXX.p8)" \
NOTIBEL_APNS_KEY_ID="XXXX" \
NOTIBEL_APNS_TEAM_ID="TEAMID" \
NOTIBEL_APNS_BUNDLE_ID="com.example.notibel" \
NOTIBEL_APNS_ENV="development" \
bash ./scripts/install-systemd.sh <ssh-host>
```

### Verify the server

```bash
curl http://<server-ip>:8787/healthz
```

Healthy APNs-enabled output looks like:

```json
{"apnsConfigured":true,"ok":true}
```

## Build And Install The iPhone App

Open `ios/Notibel.xcodeproj` in Xcode.

Then:

1. Set your Apple team.
2. Confirm the bundle ID matches `NOTIBEL_APNS_BUNDLE_ID`.
3. Keep the Push Notifications entitlement enabled.
4. Install on a physical iPhone.

You can also do a simulator-only compile check with:

```bash
xcodebuild -project ios/Notibel.xcodeproj -scheme Notibel -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Configure The iPhone App

In the app:

1. Set the server URL to `http://<server-ip>:8787`.
2. Enter `NOTIBEL_APP_TOKEN`.
3. Add the topics you care about, for example `codex` and `claude`.
4. Request notification permission.
5. Sync device registration.

Expected result:

- `Authorization` becomes `Authorized`
- a device token appears
- sync status becomes `Synced`

## Install Desktop Hooks On macOS

First, make sure:

- `bws` is installed
- the Bitwarden machine access token is stored in macOS Keychain under service `codex.bitwarden.secrets-manager` and account `default`

Then run:

```bash
python3 ./scripts/install-hooks-macos.py \
  --server-url "http://<server-ip>:8787" \
  --bitwarden-project-id "<bitwarden-project-id>"
```

This updates:

- `~/.claude/settings.json`
- `~/.codex/config.toml`
- `~/.codex/hooks.json`
- `~/.config/notibel/config.env`

The generated config file stores:

- `NOTIBEL_URL`
- `NOTIBEL_BWS_PROJECT_ID`
- `NOTIBEL_BWS_SERVICE`
- `NOTIBEL_BWS_ACCOUNT`

After that:

- Claude Code stop hooks call `notify.sh`
- Codex `Stop` hooks call `codex-notify.sh`
- both scripts fetch `NOTIBEL_PUBLISH_TOKEN` from Bitwarden automatically if it is not already exported
- the macOS installer enables `features.codex_hooks = true` and removes the legacy `notify = [...]` entry so Codex only notifies once per completed turn

## Install Desktop Hooks On Windows

First, make sure:

- `bws` is installed
- the Bitwarden machine access token is stored in Windows Credential Manager under `codex.bitwarden.secrets-manager`

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks-windows.ps1 `
  -ServerUrl "http://<server-ip>:8787" `
  -BitwardenProjectId "<bitwarden-project-id>"
```

This updates:

- `%USERPROFILE%\.claude\settings.json`
- `%USERPROFILE%\.codex\config.toml`
- `%USERPROFILE%\.config\notibel\config.env`

The Windows wrappers are:

- `claude-notify.cmd`

Because Codex hooks are currently disabled on Windows, the Windows installer still uses Codex's legacy `notify = [...]` integration.
On Windows that legacy Codex config points directly to `powershell.exe ... codex-notify.ps1` so the JSON payload survives intact.

## Manual Publisher Tests

macOS Claude-shaped test:

```bash
printf '{"cwd":"/tmp/demo","transcript":[{"message":{"content":"Claude test"}}]}' | ./notify.sh
```

macOS Claude Stop-hook test:

```bash
printf '{"cwd":"/tmp/demo","transcript_path":"%s"}' "$HOME/.claude/projects/example/session.jsonl" | ./notify.sh
```

macOS Codex-shaped test:

```bash
./codex-notify.sh '{"type":"agent-turn-complete","cwd":"/tmp/demo","thread_title":"Demo thread","last-assistant-message":"Codex test"}'
```

macOS Codex Stop-hook test:

```bash
./codex-notify.sh '{"hook_event_name":"Stop","cwd":"/tmp/demo","thread_title":"Demo thread","last_assistant_message":"Codex test"}'
```

Windows test:

```powershell
.\notify.ps1 -Title "Codex" -Message "Task completed" -Source "codex" -Topic "codex"
```

## Troubleshooting

`401` from `notify.sh` or `codex-notify.sh`

- The machine cannot read `NOTIBEL_PUBLISH_TOKEN` from Bitwarden.
- Check the Bitwarden project ID in `~/.config/notibel/config.env`.
- Check that the local machine access token is stored in Keychain or Credential Manager.

`apnsConfigured:false`

- One or more `NOTIBEL_APNS_*` values are missing on the server.
- Re-run the deploy script after fixing Bitwarden or exported env vars.

The iPhone app shows `unauthorized`

- `NOTIBEL_APP_TOKEN` in the app does not match the server.

No push alert arrives but the notifications screen works

- APNs is configured, but the app may not be signed for the same environment.
- Development-signed builds need `NOTIBEL_APNS_ENV=development`.

The app cannot reach the server off your LAN

- Put Notibel behind TLS and a reachable hostname before using it outside your home network.

## Repo References

- `cmd/notibeld/main.go`
- `internal/httpapi/server.go`
- `internal/notifier/service.go`
- `internal/apns/client.go`
- `internal/store/store.go`
- `docs/architecture.md`
- `docs/apns-setup.md`
