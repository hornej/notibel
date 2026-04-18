<p align="center">
  <img src="notibel-app-icon.jpg" alt="Notibel app icon" width="128" />
</p>

# Notibel

An iOS app and self-hosted notification system for AI coding workflows.

`Codex` and `Claude Code` publish completion events to your own server. `notibeld` stores a short event history, fans out to registered devices, and sends native iPhone push notifications through your own APNs key.

## Table Of Contents

- [Quick Start](#quick-start)
- [What Is In This Repo](#what-is-in-this-repo)
- [Why Notibel Instead Of Plain ntfy?](#why-notibel-instead-of-plain-ntfy)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Config And Secret Sources](#config-and-secret-sources)
- [Bitwarden Secrets Layout (Optional)](#bitwarden-secrets-layout-optional)
- [Apple / APNs Setup](#apple--apns-setup)
- [Build The Server](#build-the-server)
- [Deploy The Server](#deploy-the-server)
- [Build And Install The iOS App](#build-and-install-the-ios-app)
- [Configure The iOS App](#configure-the-ios-app)
- [Install Desktop Hooks On macOS](#install-desktop-hooks-on-macos)
- [Install Desktop Hooks On Windows](#install-desktop-hooks-on-windows)
- [Manual Publisher Tests](#manual-publisher-tests)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Further Reading](#further-reading)

## Quick Start

Typical path: Linux host with `systemd`, manually managed secrets, and a
physical iPhone.

1. Create your Apple app ID and APNs key.
   Use [Apple / APNs Setup](#apple--apns-setup).
2. Build and deploy the server:

```bash
make build-linux-arm64

NOTIBEL_PUBLISH_TOKEN="..." \
NOTIBEL_APP_TOKEN="..." \
NOTIBEL_APNS_KEY_P8="$(cat /path/to/AuthKey_XXXX.p8)" \
NOTIBEL_APNS_KEY_ID="XXXX" \
NOTIBEL_APNS_TEAM_ID="TEAMID" \
NOTIBEL_APNS_BUNDLE_ID="com.example.notibel" \
NOTIBEL_APNS_ENV="development" \
bash ./scripts/install-systemd.sh <ssh-host>
```

3. Prepare iOS signing and run a compile check:

```bash
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
make ios-build-sim
```

Then edit `ios/Config/Local.xcconfig` and set `DEVELOPMENT_TEAM = YOUR_TEAM_ID`.

4. Install the app on a physical iPhone, then enter:
   - server URL `http://<server-ip>:8787`
   - `NOTIBEL_APP_TOKEN`
   - topics such as `codex` and `claude`
5. Optional: install desktop hooks for Claude Code and/or Codex.
   Use [Install Desktop Hooks On macOS](#install-desktop-hooks-on-macos) or [Install Desktop Hooks On Windows](#install-desktop-hooks-on-windows).

## What Is In This Repo

- `cmd/notibeld`: Go server
- `ios/Notibel.xcodeproj`: SwiftUI iPhone app
- `notify.sh`, `codex-notify.sh`: macOS Claude/Codex publishers
- `notify.ps1`, `claude-notify.ps1`, `codex-notify.ps1`: Windows PowerShell publishers
- `claude-notify.cmd`, `codex-notify.cmd`: Windows command wrappers
- `scripts/install-hooks-macos.py`: installs the macOS Claude/Codex hooks
- `scripts/install-hooks-windows.ps1`: installs the Windows Claude/Codex hooks
- `scripts/install-systemd.sh`: generic Linux systemd deploy
- `scripts/install-systemd-from-bitwarden.sh`: deploy using Bitwarden Secrets Manager
- `deploy/notibel.service`: systemd unit

## Why Notibel Instead Of Plain ntfy?

The mental model is still close to `ntfy`: simple topics, a tiny server, and lightweight publishers.

I built Notibel because I wanted the full `Codex` and `Claude Code` responses on my phone, I did not want those messages routed through a public endpoint, and I wanted better Markdown formatting than a generic relay gave me. If you also want your own branded iOS app and direct control of the APNs path, Notibel owns that connection end to end instead of depending on `ntfy.sh`.

## Architecture

1. A desktop hook publishes `POST /v1/publish/{topic}`.
2. `notibeld` stores the event in a local JSON store.
3. `notibeld` finds registered iPhone installations subscribed to that topic.
4. `notibeld` sends APNs alerts using your app bundle ID and APNs auth key.
5. The iPhone app reads the same event history and manages topic subscriptions.

## Prerequisites

Core requirements:

- Go 1.20+ if you want to build the server locally
- Xcode to build and sign the iPhone app
- An Apple Developer account with APNs access
- A server that can run a small Go binary or container and reach APNs

Optional convenience tooling in this repo:

- `make` for the convenience targets in this repo
- `jq` and `curl` for the desktop publisher scripts
- `ssh`, `scp`, and `sudo` for the provided Linux systemd deploy scripts
- Bitwarden Secrets Manager plus the `bws` CLI if you want Bitwarden-backed secret injection
  - macOS: Keychain service `codex.bitwarden.secrets-manager`, account `default`
  - Windows: Credential Manager target `codex.bitwarden.secrets-manager`

Notibel itself does not require Bitwarden. It reads standard `NOTIBEL_*`
environment variables and can get them from any secret source you prefer.

The default build and deploy helpers in this repo target Linux with `systemd`
and build `linux/arm64` by default, but `notibeld` itself is not limited to
ARM64 hosts.

## Config And Secret Sources

`notibeld` and the publisher scripts read `NOTIBEL_*` values from environment
variables.

Important defaults:

- `NOTIBEL_LISTEN_ADDR` defaults to `:8787`
- `NOTIBEL_STORE_PATH` defaults to `data/store.json` when running the binary directly; the Linux `systemd` installer sets it to `/var/lib/notibel/store.json`
- `NOTIBEL_EVENT_LIMIT` defaults to `500`

You can provide those values from:

- exported shell environment variables
- `/etc/notibel/notibel.env` on a Linux `systemd` host
- `~/.config/notibel/config.env` for the desktop hook scripts
- Bitwarden Secrets Manager via the optional helper scripts in this repo
- another secret manager that injects environment variables before launch

The repo does not automatically load a project-root `.env` file.

## Bitwarden Secrets Layout (Optional)

If you want to manage Notibel secrets in Bitwarden Secrets Manager, create a
project and store these keys:

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
6. Store those values under the corresponding `NOTIBEL_APNS_*` keys wherever you manage server secrets.

If you use Bitwarden, the bundle ID stored there must match the iPhone app you
actually sign and install.

## Build The Server

The default helper builds a Linux ARM64 binary because the included deploy
script expects that target:

```bash
make build-linux-arm64
```

This writes:

- `dist/notibeld-linux-arm64`

`notibeld` is just a Go binary, so you can build for another Linux target if
your server is not ARM64. For example:

```bash
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
go build -trimpath -ldflags="-s -w" \
  -o dist/notibeld-linux-amd64 \
  ./cmd/notibeld
```

You can also containerize it with the provided [Dockerfile](Dockerfile).

## Deploy The Server

The included deploy scripts target Linux hosts with `systemd` over SSH. If you
are using another environment, run the binary or container with your normal
process manager and provide the same `NOTIBEL_*` environment variables.

### Reproducible deploy from Bitwarden

If your publish/app/APNs secrets live in Bitwarden, deploy with:

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

With the provided Linux `systemd` deploy, event data lives at
`/var/lib/notibel/store.json` by default. The server keeps only the most recent
`NOTIBEL_EVENT_LIMIT` events total, which defaults to `500`.

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

## Build And Install The iOS App

Open `ios/Notibel.xcodeproj` in Xcode.

The current iOS deployment target is `17.0`.

Before the first device build on a machine, copy the local signing template and
set your Apple team ID:

```bash
cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig
```

Then edit `ios/Config/Local.xcconfig` and set:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

`ios/Config/Local.xcconfig` is ignored by git, so each machine can keep its own
signing team without modifying the shared Xcode project.

Before you install on a physical iPhone:

1. Set your Apple team.
2. Confirm the bundle ID matches `NOTIBEL_APNS_BUNDLE_ID`.
3. Keep the Push Notifications entitlement enabled.

For local validation:

```bash
make ci
make ios-build-sim
```

## Configure The iOS App

In the app:

1. Set the server URL to `http://<server-ip>:8787` by default, or whatever host and port you configured with `NOTIBEL_LISTEN_ADDR`.
2. Enter `NOTIBEL_APP_TOKEN`.
3. Add the topics you care about, for example `codex` and `claude`.
4. Request notification permission.
5. Sync device registration.

The iPhone app stores the app token in the device Keychain rather than in `UserDefaults`.

Topic names are case-sensitive and must match `^[A-Za-z0-9._-]{1,64}$`.
That means letters, numbers, dots, underscores, and dashes only. No spaces or
slashes.

Expected result:

- `Authorization` becomes `Authorized`
- a device token appears
- sync status becomes `Synced`

## Install Desktop Hooks On macOS

If you want to use the included Bitwarden-backed installer, first make sure:

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
- `~/.codex/.codex-global-state.json`
- `~/.config/notibel/config.env`

The generated config file stores:

- `NOTIBEL_URL`
- `NOTIBEL_BWS_PROJECT_ID`
- `NOTIBEL_BWS_SERVICE`
- `NOTIBEL_BWS_ACCOUNT`

After that:

- Claude Code stop hooks call `notify.sh` and publish to topic `claude` by default
- Codex turn-ended notifications call `codex-notify-fanout.sh`, which publishes to topic `codex`
- both scripts fetch `NOTIBEL_PUBLISH_TOKEN` from Bitwarden automatically if it is not already exported
- the macOS installer preserves any existing Codex `notify = [...]` command by chaining it through `codex-notify-fanout.sh`
- the macOS installer disables `features.codex_hooks` and removes the old Notibel `Stop` hook so Codex only notifies once per completed turn
- the macOS installer also sets Codex app completion notifications to `off` so the desktop app does not generate a second turn-finished alert alongside Notibel

If you are not using Bitwarden, you can still use the hook scripts. Set
`NOTIBEL_URL` and `NOTIBEL_PUBLISH_TOKEN` in `~/.config/notibel/config.env`
yourself, or export them in the shell that launches the hook.

## Install Desktop Hooks On Windows

If you want to use the included Bitwarden-backed installer, first make sure:

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
- `codex-notify.cmd`

Because Codex hooks are currently disabled on Windows, the Windows installer still uses Codex's legacy `notify = [...]` integration.
On Windows that legacy Codex config points directly to `powershell.exe ... codex-notify.ps1` so the JSON payload survives intact.

If you are not using Bitwarden, you can still run the PowerShell publishers by
setting `NOTIBEL_URL` and `NOTIBEL_PUBLISH_TOKEN` in
`%USERPROFILE%\.config\notibel\config.env` or in the process environment.

## Manual Publisher Tests

macOS Claude test:

```bash
printf '{"cwd":"/tmp/demo","transcript":[{"message":{"content":"Claude test"}}]}' | ./notify.sh
```

macOS Codex test:

```bash
./codex-notify.sh '{"type":"agent-turn-complete","cwd":"/tmp/demo","thread_title":"Demo thread","last-assistant-message":"Codex test"}'
```

Windows test:

```powershell
.\notify.ps1 -Title "Codex" -Message "Task completed" -Source "codex" -Topic "codex"
```

## Troubleshooting

`401` from `notify.sh` or `codex-notify.sh`

- `NOTIBEL_PUBLISH_TOKEN` is missing or wrong.
- If you use Bitwarden, check the Bitwarden project ID in `~/.config/notibel/config.env`.
- If you do not use Bitwarden, check your exported env vars or config file contents.

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

## License

Notibel is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

## Further Reading

- [docs/architecture.md](docs/architecture.md)
- [docs/apns-setup.md](docs/apns-setup.md)
