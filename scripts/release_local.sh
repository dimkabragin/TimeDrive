#!/usr/bin/env bash

set -euo pipefail

on_error() {
  local exit_code=$?
  local line_no=${1:-unknown}
  echo "[ERROR] release_local.sh failed at line ${line_no} with exit code ${exit_code}" >&2
  exit "${exit_code}"
}

trap 'on_error $LINENO' ERR

PROJECT="TimeDrive.xcodeproj"
SCHEME="${SCHEME:-TimeDrive}"
CONFIGURATION="${CONFIGURATION:-Release}"
PUBLISH="${PUBLISH:-0}"
FORCE="${FORCE:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
VERSION="${VERSION:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/.build-release"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
BUILD_PRODUCTS_DIR="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}"
APP_NAME="TimeDrive.app"
APP_PATH_BUILT="${BUILD_PRODUCTS_DIR}/${APP_NAME}"
APP_PATH_DIST="${DIST_DIR}/${APP_NAME}"
ZIP_PATH="${DIST_DIR}/TimeDrive.zip"
DMG_PATH="${DIST_DIR}/TimeDrive.dmg"
SHA_PATH="${DIST_DIR}/SHA256SUMS.txt"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required tool is missing: ${cmd}" >&2
    exit 1
  fi
}

resolve_version() {
  if [[ -n "${VERSION}" ]]; then
    return
  fi

  VERSION="$(git -C "${ROOT_DIR}" tag --points-at HEAD | head -n 1 || true)"
  if [[ -z "${VERSION}" ]]; then
    VERSION="$(git -C "${ROOT_DIR}" describe --tags --abbrev=0 2>/dev/null || true)"
  fi

  if [[ -z "${VERSION}" ]]; then
    echo "[ERROR] VERSION is not set and no git tag was found. Pass VERSION=vX.Y.Z." >&2
    exit 1
  fi
}

preflight() {
  echo "[INFO] Running preflight checks..."
  require_cmd xcodebuild
  require_cmd ditto
  require_cmd hdiutil
  require_cmd shasum

  if [[ "${PUBLISH}" == "1" ]]; then
    require_cmd gh
  fi

  if [[ ! -f "${ROOT_DIR}/${PROJECT}" ]]; then
    echo "[ERROR] Project file not found: ${PROJECT}" >&2
    exit 1
  fi
}

validate_scheme() {
  local schemes
  schemes="$(xcodebuild -list -project "${ROOT_DIR}/${PROJECT}" 2>/dev/null || true)"
  if ! grep -q "^[[:space:]]*${SCHEME}$" <<<"${schemes}"; then
    echo "[ERROR] Scheme '${SCHEME}' not found in ${PROJECT}." >&2
    exit 1
  fi
}

build_app() {
  echo "[INFO] Building ${SCHEME} (${CONFIGURATION})..."
  rm -rf "${BUILD_DIR}" "${DIST_DIR}"
  mkdir -p "${DIST_DIR}"

  xcodebuild \
    -project "${ROOT_DIR}/${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -destination 'platform=macOS' \
    build >/dev/null

  if [[ ! -d "${APP_PATH_BUILT}" ]]; then
    echo "[ERROR] Built app not found at ${APP_PATH_BUILT}" >&2
    exit 1
  fi

  ditto "${APP_PATH_BUILT}" "${APP_PATH_DIST}"
}

read_app_version() {
  local info_plist
  info_plist="${APP_PATH_DIST}/Contents/Info.plist"
  if [[ ! -f "${info_plist}" ]]; then
    echo "[ERROR] Info.plist not found in built app." >&2
    exit 1
  fi
  defaults read "${info_plist}" CFBundleShortVersionString
}

version_guardrails() {
  local app_version expected_version
  app_version="$(read_app_version)"
  expected_version="${VERSION#v}"

  if [[ "${expected_version}" != "${app_version}" ]]; then
    if [[ "${FORCE}" != "1" ]]; then
      echo "[ERROR] Version mismatch: VERSION=${VERSION}, app CFBundleShortVersionString=${app_version}." >&2
      echo "[ERROR] Set FORCE=1 to continue anyway." >&2
      exit 1
    fi
    echo "[WARN] Version mismatch ignored due to FORCE=1: VERSION=${VERSION}, app=${app_version}"
  fi
}

package_artifacts() {
  echo "[INFO] Packaging artifacts..."

  rm -f "${ZIP_PATH}" "${DMG_PATH}" "${SHA_PATH}"

  ditto -c -k --sequesterRsrc --keepParent "${APP_PATH_DIST}" "${ZIP_PATH}"

  local dmg_src
  dmg_src="${BUILD_DIR}/dmg-src"
  rm -rf "${dmg_src}"
  mkdir -p "${dmg_src}"
  ditto "${APP_PATH_DIST}" "${dmg_src}/${APP_NAME}"

  hdiutil create \
    -volname "TimeDrive ${VERSION}" \
    -srcfolder "${dmg_src}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

  (
    cd "${DIST_DIR}"
    shasum -a 256 "$(basename "${ZIP_PATH}")" "$(basename "${DMG_PATH}")" >"$(basename "${SHA_PATH}")"
  )

  [[ -d "${APP_PATH_DIST}" ]] || { echo "[ERROR] Missing artifact: ${APP_PATH_DIST}" >&2; exit 1; }
  [[ -f "${ZIP_PATH}" ]] || { echo "[ERROR] Missing artifact: ${ZIP_PATH}" >&2; exit 1; }
  [[ -f "${DMG_PATH}" ]] || { echo "[ERROR] Missing artifact: ${DMG_PATH}" >&2; exit 1; }
  [[ -f "${SHA_PATH}" ]] || { echo "[ERROR] Missing artifact: ${SHA_PATH}" >&2; exit 1; }
}

print_summary() {
  local app_version
  app_version="$(read_app_version)"
  echo
  echo "========== Release summary =========="
  echo "Version:         ${VERSION}"
  echo "App version:     ${app_version}"
  echo "Scheme:          ${SCHEME}"
  echo "Configuration:   ${CONFIGURATION}"
  echo "Publish:         ${PUBLISH}"
  echo "Force mismatch:  ${FORCE}"
  echo "Dist directory:  ${DIST_DIR}"
  echo "Artifacts:"
  ls -lh "${APP_PATH_DIST}" "${ZIP_PATH}" "${DMG_PATH}" "${SHA_PATH}"
  echo "====================================="
  echo
}

publish_release() {
  if [[ "${PUBLISH}" != "1" ]]; then
    return
  fi

  if [[ "${NON_INTERACTIVE}" != "1" ]]; then
    read -r -p "Publish release ${VERSION} to GitHub? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      echo "[INFO] Publish cancelled by user."
      return
    fi
  fi

  echo "[INFO] Publishing release ${VERSION} with gh..."

  if gh release view "${VERSION}" >/dev/null 2>&1; then
    gh release upload "${VERSION}" \
      "${ZIP_PATH}" \
      "${DMG_PATH}" \
      "${SHA_PATH}" \
      --clobber
  else
    gh release create "${VERSION}" \
      "${ZIP_PATH}" \
      "${DMG_PATH}" \
      "${SHA_PATH}" \
      --title "${VERSION}" \
      --notes "Install TimeDrive from the attached artifacts. Verify downloads with SHA256SUMS.txt."
  fi

  echo "[INFO] GitHub release ${VERSION} is published/updated."
}

main() {
  resolve_version
  preflight
  validate_scheme
  build_app
  version_guardrails
  package_artifacts
  print_summary
  publish_release
  echo "[INFO] Release pipeline completed successfully."
}

main "$@"
