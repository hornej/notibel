#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="${repo_root}/dist"

mkdir -p "${dist_dir}"

GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -trimpath -ldflags="-s -w" \
  -o "${dist_dir}/notibeld-linux-arm64" \
  ./cmd/notibeld

file "${dist_dir}/notibeld-linux-arm64"
