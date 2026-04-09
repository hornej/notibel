#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="${NOTIBEL_BINARY_PATH:-${repo_root}/dist/notibeld-linux-arm64}"
service_path="${NOTIBEL_SERVICE_PATH:-${repo_root}/deploy/notibel.service}"
remote_host="${1:-${NOTIBEL_REMOTE_HOST:-}}"

if [[ ! -x "${binary_path}" ]]; then
  echo "missing binary at ${binary_path}; run ./scripts/build-linux-arm64.sh first" >&2
  exit 1
fi

if [[ ! -f "${service_path}" ]]; then
  echo "missing service file at ${service_path}" >&2
  exit 1
fi

if [[ -z "${remote_host}" ]]; then
  echo "usage: ./scripts/install-systemd.sh <ssh-host>" >&2
  exit 1
fi

publish_token="${NOTIBEL_PUBLISH_TOKEN:-$(openssl rand -hex 24)}"
app_token="${NOTIBEL_APP_TOKEN:-$(openssl rand -hex 24)}"
listen_addr="${NOTIBEL_LISTEN_ADDR:-0.0.0.0:8787}"
store_path="${NOTIBEL_STORE_PATH:-/var/lib/notibel/store.json}"
event_limit="${NOTIBEL_EVENT_LIMIT:-500}"
apns_key_p8="${NOTIBEL_APNS_KEY_P8:-}"
apns_key_id="${NOTIBEL_APNS_KEY_ID:-}"
apns_team_id="${NOTIBEL_APNS_TEAM_ID:-}"
apns_bundle_id="${NOTIBEL_APNS_BUNDLE_ID:-}"
apns_env="${NOTIBEL_APNS_ENV:-development}"

if [[ "${apns_env}" != "development" && "${apns_env}" != "production" ]]; then
  echo "NOTIBEL_APNS_ENV must be development or production" >&2
  exit 1
fi

apns_fields_set=0
for value in "${apns_key_p8}" "${apns_key_id}" "${apns_team_id}" "${apns_bundle_id}"; do
  if [[ -n "${value}" ]]; then
    apns_fields_set=$((apns_fields_set + 1))
  fi
done

if (( apns_fields_set > 0 && apns_fields_set < 4 )); then
  echo "APNs deployment requires NOTIBEL_APNS_KEY_P8, NOTIBEL_APNS_KEY_ID, NOTIBEL_APNS_TEAM_ID, and NOTIBEL_APNS_BUNDLE_ID together" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cat > "${tmp_dir}/notibel.env" <<EOF
NOTIBEL_LISTEN_ADDR=${listen_addr}
NOTIBEL_STORE_PATH=${store_path}
NOTIBEL_EVENT_LIMIT=${event_limit}
NOTIBEL_PUBLISH_TOKEN=${publish_token}
NOTIBEL_APP_TOKEN=${app_token}
EOF

apns_key_name=""
if (( apns_fields_set == 4 )); then
  apns_key_name="AuthKey_${apns_key_id}.p8"
  cat >> "${tmp_dir}/notibel.env" <<EOF
NOTIBEL_APNS_KEY_PATH=/etc/notibel/${apns_key_name}
NOTIBEL_APNS_KEY_ID=${apns_key_id}
NOTIBEL_APNS_TEAM_ID=${apns_team_id}
NOTIBEL_APNS_BUNDLE_ID=${apns_bundle_id}
NOTIBEL_APNS_ENV=${apns_env}
EOF
  printf '%s\n' "${apns_key_p8}" > "${tmp_dir}/${apns_key_name}"
fi

scp "${binary_path}" "${remote_host}:/tmp/notibeld"
scp "${service_path}" "${remote_host}:/tmp/notibel.service"
scp "${tmp_dir}/notibel.env" "${remote_host}:/tmp/notibel.env"

if [[ -n "${apns_key_name}" ]]; then
  scp "${tmp_dir}/${apns_key_name}" "${remote_host}:/tmp/${apns_key_name}"
fi

ssh "${remote_host}" 'sudo bash -s' <<EOF
set -euo pipefail

id -u notibel >/dev/null 2>&1 || useradd --system --home /var/lib/notibel --shell /usr/sbin/nologin notibel

install -d -o root -g root -m 0755 /opt/notibel
install -d -o root -g root -m 0755 /opt/notibel/bin
install -d -o root -g root -m 0755 /etc/notibel
install -d -o notibel -g notibel -m 0755 /var/lib/notibel

install -o root -g root -m 0755 /tmp/notibeld /opt/notibel/bin/notibeld
install -o root -g root -m 0644 /tmp/notibel.service /etc/systemd/system/notibel.service
install -o root -g notibel -m 0640 /tmp/notibel.env /etc/notibel/notibel.env

if compgen -G "/tmp/AuthKey_*.p8" >/dev/null; then
  for key_file in /tmp/AuthKey_*.p8; do
    install -o root -g notibel -m 0640 "\${key_file}" "/etc/notibel/\$(basename "\${key_file}")"
    rm -f "\${key_file}"
  done
fi

rm -f /tmp/notibeld /tmp/notibel.service /tmp/notibel.env

systemctl daemon-reload
systemctl enable notibel.service
systemctl restart notibel.service
systemctl --no-pager --full status notibel.service | sed -n '1,18p'
EOF

host_ip="$(ssh "${remote_host}" "hostname -I | awk '{print \$1}'")"
echo
echo "Installed Notibel on ${remote_host}."
echo "Health check: http://${host_ip}:8787/healthz"
