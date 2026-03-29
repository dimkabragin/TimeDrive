#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST_PUBLISH_MODE="${APPCAST_PUBLISH_MODE:-pages}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "[ERROR] GITHUB_TOKEN is required in CI mode." >&2
  exit 1
fi

if [[ -z "${VERSION:-}" && -n "${GITHUB_REF_NAME:-}" ]]; then
  export VERSION="${GITHUB_REF_NAME}"
fi

if [[ -z "${APPCAST_BASE_DOWNLOAD_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${VERSION:-}" ]]; then
  export APPCAST_BASE_DOWNLOAD_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${VERSION}"
fi

if [[ -z "${RELEASE_NOTES_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${VERSION:-}" ]]; then
  export RELEASE_NOTES_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${VERSION}"
fi

if [[ -z "${APPCAST_URL:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  repo_name="${GITHUB_REPOSITORY#*/}"
  export APPCAST_URL="https://$(printf '%s' "${GITHUB_REPOSITORY}" | cut -d'/' -f1).github.io/${repo_name}/appcast.xml"
fi

if [[ -z "${SPARKLE_APPCAST_URL:-}" && -n "${APPCAST_URL:-}" ]]; then
  export SPARKLE_APPCAST_URL="${APPCAST_URL}"
fi

export APPCAST_GENERATE="${APPCAST_GENERATE:-1}"
export APPCAST_CHANNEL="${APPCAST_CHANNEL:-stable}"
export SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-1}"
export RELEASE_ENV="${RELEASE_ENV:-production}"

if [[ "${RELEASE_ENV}" == "production" ]]; then
  if [[ "${APPCAST_GENERATE}" != "1" ]]; then
    echo "[ERROR] Production CI release requires APPCAST_GENERATE=1." >&2
    exit 1
  fi

  if [[ "${SPARKLE_SIGN_UPDATE}" != "1" ]]; then
    echo "[ERROR] Production CI release requires SPARKLE_SIGN_UPDATE=1 (unsigned appcast is forbidden)." >&2
    exit 1
  fi

  if [[ "${APPCAST_PUBLISH_MODE}" == "artifact" ]]; then
    echo "[ERROR] Production CI release cannot use APPCAST_PUBLISH_MODE=artifact (public appcast URL would be unavailable/404)." >&2
    echo "[ERROR] Use APPCAST_PUBLISH_MODE=pages or configure external hosting with a reachable APPCAST_URL/SPARKLE_APPCAST_URL." >&2
    exit 1
  fi

  if [[ -z "${SPARKLE_APPCAST_URL:-}" ]]; then
    echo "[ERROR] Production CI release requires SPARKLE_APPCAST_URL (or APPCAST_URL fallback)." >&2
    exit 1
  fi

  if [[ -z "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    echo "[ERROR] Production CI release requires SPARKLE_PUBLIC_ED_KEY." >&2
    exit 1
  fi
fi

if [[ "${SPARKLE_SIGN_UPDATE}" == "1" ]]; then
  if [[ -z "${SPARKLE_EDDSA_SIGNATURE:-}" && -z "${SPARKLE_PRIVATE_KEY:-}" && -z "${SPARKLE_PRIVATE_KEY_B64:-}" && -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    echo "[ERROR] SPARKLE_SIGN_UPDATE=1 in CI requires signing data." >&2
    echo "[ERROR] Provide SPARKLE_PRIVATE_KEY (recommended) or SPARKLE_PRIVATE_KEY_B64/SPARKLE_PRIVATE_KEY_FILE." >&2
    echo "[ERROR] Alternative legacy mode: pass precomputed SPARKLE_EDDSA_SIGNATURE." >&2
    exit 1
  fi
fi

export PUBLISH=1
export NON_INTERACTIVE=1

"${ROOT_DIR}/scripts/release_local.sh" "$@"
