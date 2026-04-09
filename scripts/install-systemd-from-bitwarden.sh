#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
remote_host="${1:-${NOTIBEL_REMOTE_HOST:-}}"
project_id="${NOTIBEL_BWS_PROJECT_ID:-}"
service_name="${NOTIBEL_BWS_SERVICE:-codex.bitwarden.secrets-manager}"
account_name="${NOTIBEL_BWS_ACCOUNT:-default}"

if [[ -z "${project_id}" ]]; then
  echo "set NOTIBEL_BWS_PROJECT_ID to the Bitwarden Secrets Manager project that contains NOTIBEL_* secrets" >&2
  exit 1
fi

if [[ -z "${remote_host}" ]]; then
  echo "usage: ./scripts/install-systemd-from-bitwarden.sh <ssh-host>" >&2
  exit 1
fi

command -v bws >/dev/null 2>&1 || {
  echo "bws must be installed to deploy from Bitwarden" >&2
  exit 1
}

access_token="${BWS_ACCESS_TOKEN:-}"
if [[ -z "${access_token}" ]] && command -v security >/dev/null 2>&1; then
  access_token="$(security find-generic-password -w -s "${service_name}" -a "${account_name}" 2>/dev/null || true)"
fi

if [[ -z "${access_token}" ]]; then
  echo "missing Bitwarden access token; export BWS_ACCESS_TOKEN or store it in macOS Keychain (${account_name}@${service_name})" >&2
  exit 1
fi

export BWS_ACCESS_TOKEN="${access_token}"
exec bws run --project-id "${project_id}" -- bash "${repo_root}/scripts/install-systemd.sh" "${remote_host}"
