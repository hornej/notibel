#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Install Notibel hooks into local Claude and Codex config on macOS.")
    parser.add_argument("--server-url", required=True, help="Notibel server base URL, for example http://your-server:8787")
    parser.add_argument("--bitwarden-project-id", required=True, help="Bitwarden Secrets Manager project ID that contains NOTIBEL_PUBLISH_TOKEN")
    parser.add_argument("--repo-root", default=str(repo_root), help="Path to the Notibel repo")
    parser.add_argument("--claude-settings", default=str(Path.home() / ".claude" / "settings.json"))
    parser.add_argument("--codex-config", default=str(Path.home() / ".codex" / "config.toml"))
    parser.add_argument("--codex-hooks", default=str(Path.home() / ".codex" / "hooks.json"))
    parser.add_argument("--codex-global-state", default=str(Path.home() / ".codex" / ".codex-global-state.json"))
    parser.add_argument("--config-file", default=str(Path.home() / ".config" / "notibel" / "config.env"))
    return parser.parse_args()


def update_claude_settings(path: Path, command: str) -> None:
    if path.exists():
        data = json.loads(path.read_text())
    else:
        data = {}

    hooks = data.setdefault("hooks", {})
    stop_entries = hooks.setdefault("Stop", [])

    updated = False
    for entry in stop_entries:
        hook_list = entry.get("hooks")
        if not isinstance(hook_list, list):
            continue
        for hook in hook_list:
            if hook.get("type") != "command":
                continue
            current = str(hook.get("command", ""))
            if current == command or "ai-notifications/notify.sh" in current or "/notibel/notify.sh" in current:
                hook["command"] = command
                updated = True

    if not updated:
        stop_entries.append({"hooks": [{"type": "command", "command": command}]})

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def update_codex_config(path: Path) -> None:
    text = path.read_text() if path.exists() else ""

    text = re.sub(r"(?m)^notify\s*=.*(?:\n|$)", "", text)

    features_pattern = re.compile(r"(?ms)(^\[features\]\s*\n)(.*?)(?=^\[|\Z)")
    match = features_pattern.search(text)
    if match:
        header = match.group(1)
        body = match.group(2)
        if re.search(r"(?m)^codex_hooks\s*=.*$", body):
            body = re.sub(r"(?m)^codex_hooks\s*=.*$", "codex_hooks = true", body, count=1)
        else:
            if body and not body.endswith("\n"):
                body += "\n"
            body += "codex_hooks = true\n"
        text = text[:match.start()] + header + body + text[match.end():]
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        if text:
            text += "\n"
        text += "[features]\ncodex_hooks = true\n"

    text = re.sub(r"\n{3,}", "\n\n", text)
    text = text.lstrip("\n")
    if text and not text.endswith("\n"):
        text += "\n"

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def is_notibel_codex_hook(command: str, desired_command: str) -> bool:
    return (
        command == desired_command
        or "ai-notifications/codex-notify.sh" in command
        or "/notibel/codex-notify.sh" in command
    )


def update_codex_hooks(path: Path, command: str) -> None:
    if path.exists():
        data = json.loads(path.read_text())
    else:
        data = {}

    hooks = data.setdefault("hooks", {})
    stop_entries = hooks.setdefault("Stop", [])

    updated = False
    for entry in stop_entries:
        hook_list = entry.get("hooks")
        if not isinstance(hook_list, list):
            continue
        for hook in hook_list:
            if hook.get("type") != "command":
                continue
            current = str(hook.get("command", ""))
            if is_notibel_codex_hook(current, command):
                hook["command"] = command
                updated = True

    if not updated:
        stop_entries.append(
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": command,
                        "timeout": 30,
                    }
                ]
            }
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def update_notibel_config(path: Path, server_url: str, project_id: str) -> None:
    existing: dict[str, str] = {}
    if path.exists():
        for line in path.read_text().splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            key, value = stripped.split("=", 1)
            existing[key.strip()] = value.strip()

    existing["NOTIBEL_URL"] = server_url.rstrip("/")
    existing["NOTIBEL_BWS_PROJECT_ID"] = project_id
    existing.setdefault("NOTIBEL_BWS_SERVICE", "codex.bitwarden.secrets-manager")
    existing.setdefault("NOTIBEL_BWS_ACCOUNT", "default")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(f"{key}={value}\n" for key, value in sorted(existing.items())))


def update_codex_global_state(path: Path) -> None:
    if path.exists():
        data = json.loads(path.read_text())
    else:
        data = {}

    data["notifications-turn-mode"] = "off"

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()

    update_claude_settings(Path(args.claude_settings).expanduser(), str(repo_root / "notify.sh"))
    update_codex_config(Path(args.codex_config).expanduser())
    update_codex_hooks(Path(args.codex_hooks).expanduser(), str(repo_root / "codex-notify.sh"))
    update_codex_global_state(Path(args.codex_global_state).expanduser())
    update_notibel_config(Path(args.config_file).expanduser(), args.server_url, args.bitwarden_project_id)

    print(f"Updated Claude settings: {Path(args.claude_settings).expanduser()}")
    print(f"Updated Codex config: {Path(args.codex_config).expanduser()}")
    print(f"Updated Codex hooks: {Path(args.codex_hooks).expanduser()}")
    print(f"Updated Codex global state: {Path(args.codex_global_state).expanduser()}")
    print(f"Wrote Notibel config: {Path(args.config_file).expanduser()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
