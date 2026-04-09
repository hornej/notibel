# Notibel Architecture

## Product Intent

Notibel is a focused, self-hosted notification rail for your own tooling.

The first use case is narrow on purpose:

- Codex completes a response on macOS or Windows
- Claude Code completes a response on macOS or Windows
- your iPhone gets a native push notification from your own app

That is enough to justify the platform work without dragging in a general-purpose messaging product.

## Why Build A Custom iOS App?

The `ntfy` model is the right starting point, but its iOS self-hosting story exists because Apple does not allow arbitrary always-on background polling. The upstream project works around that by sending relay-style poll requests through an APNs-connected upstream.

For Notibel, the cleaner approach is:

- own the iOS bundle ID
- own the APNs auth key
- have your own server talk directly to APNs
- keep the client app thin

That removes the external relay dependency and gives you room to add opinionated features later.

## MVP Components

### 1. Desktop publishers

- macOS shell hooks for Claude Code and Codex
- PowerShell publisher for Windows
- simple bearer-token authenticated `POST` requests into Notibel

### 2. Notibel server

- single small Go binary
- JSON-backed event and device registry for now
- topic-based publish API
- APNs fan-out to registered device tokens
- short event history for the mobile client

### 3. iOS app

- SwiftUI
- request push permission
- register for remote notifications
- send device token plus topic subscriptions to the server
- display recent notifications by topic

## Data Flow

1. A publisher posts `{title, message, source, project, threadTitle}` to `/v1/publish/{topic}`
2. The server stores the event in the local data file
3. The server finds registered devices subscribed to that topic
4. The server sends an APNs alert payload with event metadata
5. The iOS app opens into a recent-events view and can fetch history from `/v1/topics/{topic}/events`

## Security Model For The First Cut

- `NOTIBEL_PUBLISH_TOKEN` protects publish calls from desktop tooling
- `NOTIBEL_APP_TOKEN` protects mobile registration and event history
- APNs credentials stay on the server only

This is deliberately simple and acceptable for a single-user homelab deployment. Later, replace the shared app token with real user auth if the project grows beyond personal use.

## Homelab Placement

Pick a small Linux VM or container host that already fits into your self-hosted deployment flow:

- deploy as a small Docker container or systemd service
- terminate TLS at the reverse proxy layer you already trust
- keep APNs key material on that host only

Do not run the first version directly on a hypervisor or other high-blast-radius machine unless you have a specific reason. Keep it on a normal guest so upgrades and rollbacks stay boring.

## Recommended Public Shape

- DNS: `notibel.<your-domain>`
- TLS: valid public certificate
- ingress: reverse proxy to container port `8787`
- storage: bind mount `data/` and `secrets/`

## iOS App Shape

Use a simple SwiftUI shell:

- `TabView` with `Notifications` and `Settings`
- `NavigationStack` inside each tab
- small observable app state only where reference semantics are justified
- explicit async loading states for event history and registration

Current screens:

### Notifications

- newest events across subscribed topics
- toolbar actions for topic filters and adding a topic
- tap into a detail view

### Settings

- server base URL
- app token
- device registration state
- push permission state

## Near-Term Roadmap

1. Build the SwiftUI app shell and APNs registration flow
2. Add deep links from push payloads into a topic detail screen
3. Add authentication bootstrapping so the shared app token is not typed repeatedly
4. Add optional webhooks and richer notification actions
