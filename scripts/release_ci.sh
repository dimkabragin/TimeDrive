#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "[ERROR] GITHUB_TOKEN is required in CI mode." >&2
  exit 1
fi

export PUBLISH=1
export NON_INTERACTIVE=1

"${ROOT_DIR}/scripts/release_local.sh" "$@"
