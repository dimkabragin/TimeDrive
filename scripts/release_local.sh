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
APPCAST_GENERATE="${APPCAST_GENERATE:-1}"
APPCAST_URL="${APPCAST_URL:-}"
SPARKLE_APPCAST_URL="${SPARKLE_APPCAST_URL:-${APPCAST_URL:-}}"
APPCAST_BASE_DOWNLOAD_URL="${APPCAST_BASE_DOWNLOAD_URL:-}"
APPCAST_CHANNEL="${APPCAST_CHANNEL:-stable}"
RELEASE_NOTES_URL="${RELEASE_NOTES_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-0}"
SPARKLE_EDDSA_SIGNATURE="${SPARKLE_EDDSA_SIGNATURE:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_PRIVATE_KEY_B64="${SPARKLE_PRIVATE_KEY_B64:-}"
SPARKLE_PRIVATE_KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-}"
SPARKLE_SIGN_UPDATE_TOOL="${SPARKLE_SIGN_UPDATE_TOOL:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/.build-release"
DERIVED_DATA_DIR="${BUILD_DIR}/DerivedData"
BUILD_PRODUCTS_DIR="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}"
APP_NAME="TimeDrive.app"
APP_PATH_BUILT="${BUILD_PRODUCTS_DIR}/${APP_NAME}"
APP_PATH_DIST="${DIST_DIR}/${APP_NAME}"
XCODEBUILD_LOG="${BUILD_DIR}/xcodebuild.log"
ZIP_PATH="${DIST_DIR}/TimeDrive.zip"
DMG_PATH="${DIST_DIR}/TimeDrive.dmg"
SHA_PATH="${DIST_DIR}/SHA256SUMS.txt"
APPCAST_PATH="${DIST_DIR}/appcast.xml"
UPDATE_METADATA_PATH="${DIST_DIR}/update-metadata.json"
TEMP_SPARKLE_KEY_FILE=""

cleanup() {
  if [[ -n "${TEMP_SPARKLE_KEY_FILE}" && -f "${TEMP_SPARKLE_KEY_FILE}" ]]; then
    rm -f "${TEMP_SPARKLE_KEY_FILE}" || true
  fi
}

trap cleanup EXIT

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required tool is missing: ${cmd}" >&2
    exit 1
  fi
}

is_production_release() {
  [[ "${PUBLISH}" == "1" || "${RELEASE_ENV:-}" == "production" ]]
}

ensure_https_url() {
  local value="$1"
  local name="$2"

  if [[ -z "${value}" ]]; then
    echo "[ERROR] ${name} must not be empty." >&2
    exit 1
  fi

  if [[ ! "${value}" =~ ^https:// ]]; then
    echo "[ERROR] ${name} must start with https:// (current: ${value})" >&2
    exit 1
  fi
}

sha256_file() {
  local file="$1"
  shasum -a 256 "${file}" | awk '{print $1}'
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "${value}"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}

resolve_download_base_url() {
  if [[ -n "${APPCAST_BASE_DOWNLOAD_URL}" ]]; then
    return
  fi

  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    APPCAST_BASE_DOWNLOAD_URL="https://github.com/${GITHUB_REPOSITORY}/releases/download/${VERSION}"
    return
  fi

  APPCAST_BASE_DOWNLOAD_URL="https://example.invalid/TimeDrive/releases/${VERSION}"
  echo "[WARN] APPCAST_BASE_DOWNLOAD_URL is not set and GITHUB_REPOSITORY is empty."
  echo "[WARN] Placeholder URL will be used: ${APPCAST_BASE_DOWNLOAD_URL}"
}

resolve_release_notes_url() {
  if [[ -n "${RELEASE_NOTES_URL}" ]]; then
    return
  fi

  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    RELEASE_NOTES_URL="https://github.com/${GITHUB_REPOSITORY}/releases/tag/${VERSION}"
    return
  fi

  RELEASE_NOTES_URL="https://example.invalid/TimeDrive/releases/tag/${VERSION}"
  echo "[WARN] RELEASE_NOTES_URL is not set and GITHUB_REPOSITORY is empty."
  echo "[WARN] Placeholder URL will be used: ${RELEASE_NOTES_URL}"
}

validate_autoupdate_configuration() {
  if [[ -z "${APPCAST_URL}" && -n "${SPARKLE_APPCAST_URL}" ]]; then
    APPCAST_URL="${SPARKLE_APPCAST_URL}"
  fi

  if [[ -z "${SPARKLE_APPCAST_URL}" && -n "${APPCAST_URL}" ]]; then
    SPARKLE_APPCAST_URL="${APPCAST_URL}"
  fi

  if is_production_release; then
    if [[ "${APPCAST_GENERATE}" != "1" ]]; then
      echo "[ERROR] Production release requires APPCAST_GENERATE=1." >&2
      exit 1
    fi

    ensure_https_url "${SPARKLE_APPCAST_URL}" "SPARKLE_APPCAST_URL"

    if [[ -z "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
      echo "[ERROR] Production release requires SPARKLE_PUBLIC_ED_KEY for SUPublicEDKey injection." >&2
      exit 1
    fi

    if [[ "${SPARKLE_SIGN_UPDATE}" != "1" ]]; then
      echo "[ERROR] Production release requires SPARKLE_SIGN_UPDATE=1 (signed appcast is mandatory)." >&2
      exit 1
    fi
  fi

  if [[ "${APPCAST_GENERATE}" != "1" && "${SPARKLE_SIGN_UPDATE}" == "1" ]]; then
    echo "[ERROR] SPARKLE_SIGN_UPDATE=1 requires APPCAST_GENERATE=1." >&2
    exit 1
  fi

  if [[ "${APPCAST_GENERATE}" != "1" ]]; then
    return
  fi

  if [[ -n "${APPCAST_URL}" ]]; then
    ensure_https_url "${APPCAST_URL}" "APPCAST_URL"
  else
    echo "[WARN] APPCAST_URL is empty. Metadata file will include empty appcast_url."
  fi

  ensure_https_url "${APPCAST_BASE_DOWNLOAD_URL}" "APPCAST_BASE_DOWNLOAD_URL"
  ensure_https_url "${RELEASE_NOTES_URL}" "RELEASE_NOTES_URL"

  if [[ "${SPARKLE_SIGN_UPDATE}" == "1" ]]; then
    if [[ -n "${SPARKLE_EDDSA_SIGNATURE}" ]]; then
      return
    fi

    if [[ -n "${SPARKLE_PRIVATE_KEY}" || -n "${SPARKLE_PRIVATE_KEY_B64}" || -n "${SPARKLE_PRIVATE_KEY_FILE}" ]]; then
      return
    fi

    echo "[ERROR] SPARKLE_SIGN_UPDATE=1 requires signature or private key material." >&2
    echo "[ERROR] Provide one of: SPARKLE_EDDSA_SIGNATURE, SPARKLE_PRIVATE_KEY, SPARKLE_PRIVATE_KEY_B64, SPARKLE_PRIVATE_KEY_FILE." >&2
    exit 1
  fi
}

decode_base64_to_file() {
  local input="$1"
  local output_file="$2"

  if printf '%s' "${input}" | base64 --decode >"${output_file}" 2>/dev/null; then
    return
  fi

  if printf '%s' "${input}" | base64 -D >"${output_file}" 2>/dev/null; then
    return
  fi

  echo "[ERROR] Failed to decode SPARKLE_PRIVATE_KEY_B64. Expected valid base64 string." >&2
  exit 1
}

resolve_sparkle_sign_update_tool() {
  if [[ -n "${SPARKLE_SIGN_UPDATE_TOOL}" ]]; then
    if [[ -x "${SPARKLE_SIGN_UPDATE_TOOL}" ]]; then
      printf '%s' "${SPARKLE_SIGN_UPDATE_TOOL}"
      return
    fi
    echo "[ERROR] SPARKLE_SIGN_UPDATE_TOOL is set but not executable: ${SPARKLE_SIGN_UPDATE_TOOL}" >&2
    exit 1
  fi

  local candidates=()
  candidates+=("$(command -v sign_update 2>/dev/null || true)")
  candidates+=("$(xcrun --find sign_update 2>/dev/null || true)")
  candidates+=("${ROOT_DIR}/.build-release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update")
  candidates+=("${ROOT_DIR}/.build-release/DerivedData/SourcePackages/checkouts/Sparkle/bin/sign_update")
  candidates+=("/opt/homebrew/bin/sign_update")
  candidates+=("/usr/local/bin/sign_update")

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "${candidate}" && -x "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return
    fi
  done

  echo "[ERROR] SPARKLE_SIGN_UPDATE=1 requires Sparkle sign_update tool, but it was not found." >&2
  echo "[ERROR] Install Sparkle tools or set SPARKLE_SIGN_UPDATE_TOOL=<absolute path to sign_update>." >&2
  exit 1
}

resolve_sparkle_private_key_file() {
  if [[ -n "${SPARKLE_PRIVATE_KEY_FILE}" ]]; then
    if [[ ! -f "${SPARKLE_PRIVATE_KEY_FILE}" ]]; then
      echo "[ERROR] SPARKLE_PRIVATE_KEY_FILE does not exist: ${SPARKLE_PRIVATE_KEY_FILE}" >&2
      exit 1
    fi
    if [[ ! -r "${SPARKLE_PRIVATE_KEY_FILE}" ]]; then
      echo "[ERROR] SPARKLE_PRIVATE_KEY_FILE is not readable: ${SPARKLE_PRIVATE_KEY_FILE}" >&2
      exit 1
    fi
    printf '%s' "${SPARKLE_PRIVATE_KEY_FILE}"
    return
  fi

  if [[ -z "${SPARKLE_PRIVATE_KEY}" && -z "${SPARKLE_PRIVATE_KEY_B64}" ]]; then
    echo "[ERROR] No Sparkle private key material was provided." >&2
    echo "[ERROR] Set SPARKLE_PRIVATE_KEY or SPARKLE_PRIVATE_KEY_B64 (or SPARKLE_PRIVATE_KEY_FILE)." >&2
    exit 1
  fi

  mkdir -p "${BUILD_DIR}"
  TEMP_SPARKLE_KEY_FILE="$(mktemp "${BUILD_DIR}/sparkle_private_key.XXXXXX")"
  chmod 600 "${TEMP_SPARKLE_KEY_FILE}"

  if [[ -n "${SPARKLE_PRIVATE_KEY}" ]]; then
    printf '%s\n' "${SPARKLE_PRIVATE_KEY}" >"${TEMP_SPARKLE_KEY_FILE}"
  else
    decode_base64_to_file "${SPARKLE_PRIVATE_KEY_B64}" "${TEMP_SPARKLE_KEY_FILE}"
  fi

  if [[ ! -s "${TEMP_SPARKLE_KEY_FILE}" ]]; then
    echo "[ERROR] Resolved Sparkle private key file is empty." >&2
    exit 1
  fi

  printf '%s' "${TEMP_SPARKLE_KEY_FILE}"
}

compute_sparkle_signature() {
  local archive_path="$1"
  local sign_tool key_file output signature

  sign_tool="$(resolve_sparkle_sign_update_tool)"
  key_file="$(resolve_sparkle_private_key_file)"

  if ! output="$(${sign_tool} "${archive_path}" "${key_file}" 2>&1)"; then
    echo "[ERROR] Sparkle signing failed for ${archive_path}." >&2
    echo "[ERROR] sign_update output:" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi

  signature="$(printf '%s\n' "${output}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "${signature}" ]]; then
    signature="$(printf '%s\n' "${output}" | sed -n 's/^edSignature="\([^"]*\)"$/\1/p' | head -n 1)"
  fi

  if [[ -z "${signature}" ]]; then
    echo "[ERROR] Unable to parse EdDSA signature from sign_update output." >&2
    echo "[ERROR] Raw output:" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi

  printf '%s' "${signature}"
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

  if [[ ! -d "${ROOT_DIR}/${PROJECT}" ]]; then
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
  mkdir -p "${DIST_DIR}" "${BUILD_DIR}"

  local -a xcodebuild_args
  xcodebuild_args=(
    -project "${ROOT_DIR}/${PROJECT}"
    -scheme "${SCHEME}"
    -configuration "${CONFIGURATION}"
    -derivedDataPath "${DERIVED_DATA_DIR}"
    -destination 'generic/platform=macOS'
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )

  if [[ -n "${SPARKLE_APPCAST_URL}" ]]; then
    xcodebuild_args+=("SPARKLE_APPCAST_URL=${SPARKLE_APPCAST_URL}")
    xcodebuild_args+=("INFOPLIST_KEY_SUFeedURL=${SPARKLE_APPCAST_URL}")
  fi

  if [[ -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
    xcodebuild_args+=("SPARKLE_PUBLIC_ED_KEY=${SPARKLE_PUBLIC_ED_KEY}")
    xcodebuild_args+=("INFOPLIST_KEY_SUPublicEDKey=${SPARKLE_PUBLIC_ED_KEY}")
  fi

  if ! xcodebuild "${xcodebuild_args[@]}" build >"${XCODEBUILD_LOG}" 2>&1; then
    echo "[ERROR] xcodebuild failed (exit 65). Log: ${XCODEBUILD_LOG}" >&2
    tail -n 200 "${XCODEBUILD_LOG}" >&2 || true
    exit 65
  fi

  if [[ ! -d "${APP_PATH_BUILT}" ]]; then
    echo "[ERROR] Built app not found at ${APP_PATH_BUILT}" >&2
    exit 1
  fi

  ditto "${APP_PATH_BUILT}" "${APP_PATH_DIST}"

  if [[ -n "${SPARKLE_APPCAST_URL}" ]]; then
    defaults write "${APP_PATH_DIST}/Contents/Info.plist" SUFeedURL -string "${SPARKLE_APPCAST_URL}"
  fi

  if [[ -n "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
    defaults write "${APP_PATH_DIST}/Contents/Info.plist" SUPublicEDKey -string "${SPARKLE_PUBLIC_ED_KEY}"
  fi
}

validate_built_app_sparkle_configuration() {
  local info_plist su_feed_url su_public_ed_key
  info_plist="${APP_PATH_DIST}/Contents/Info.plist"

  if [[ ! -f "${info_plist}" ]]; then
    echo "[ERROR] Info.plist not found for post-build Sparkle validation: ${info_plist}" >&2
    exit 1
  fi

  if ! su_feed_url="$(defaults read "${info_plist}" SUFeedURL 2>/dev/null)" || [[ -z "${su_feed_url}" ]]; then
    echo "[ERROR] Built app Info.plist is missing SUFeedURL." >&2
    exit 1
  fi

  if ! su_public_ed_key="$(defaults read "${info_plist}" SUPublicEDKey 2>/dev/null)" || [[ -z "${su_public_ed_key}" ]]; then
    echo "[ERROR] Built app Info.plist is missing SUPublicEDKey." >&2
    exit 1
  fi

  if [[ -n "${SPARKLE_APPCAST_URL}" && "${su_feed_url}" != "${SPARKLE_APPCAST_URL}" ]]; then
    echo "[ERROR] SUFeedURL mismatch in built app Info.plist." >&2
    echo "[ERROR] Expected: ${SPARKLE_APPCAST_URL}" >&2
    echo "[ERROR] Actual:   ${su_feed_url}" >&2
    exit 1
  fi

  if [[ -n "${SPARKLE_PUBLIC_ED_KEY}" && "${su_public_ed_key}" != "${SPARKLE_PUBLIC_ED_KEY}" ]]; then
    echo "[ERROR] SUPublicEDKey mismatch in built app Info.plist." >&2
    echo "[ERROR] Expected: ${SPARKLE_PUBLIC_ED_KEY}" >&2
    echo "[ERROR] Actual:   ${su_public_ed_key}" >&2
    exit 1
  fi

  echo "[INFO] Built app Info.plist validation passed (SUFeedURL, SUPublicEDKey)."
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

generate_update_files() {
  if [[ "${APPCAST_GENERATE}" != "1" ]]; then
    echo "[INFO] APPCAST_GENERATE=${APPCAST_GENERATE}. Skipping appcast generation."
    return
  fi

  echo "[INFO] Generating update metadata and appcast..."

  local app_version zip_name artifact_url zip_sha256 zip_size pub_date sparkle_signature
  app_version="$(read_app_version)"
  zip_name="$(basename "${ZIP_PATH}")"
  artifact_url="${APPCAST_BASE_DOWNLOAD_URL%/}/${zip_name}"
  zip_sha256="$(sha256_file "${ZIP_PATH}")"
  zip_size="$(stat -f "%z" "${ZIP_PATH}")"
  pub_date="$(LC_ALL=C TZ=UTC date -R)"
  sparkle_signature="${SPARKLE_EDDSA_SIGNATURE}"

  if [[ "${SPARKLE_SIGN_UPDATE}" == "1" && -z "${sparkle_signature}" ]]; then
    echo "[INFO] SPARKLE_SIGN_UPDATE=1. Computing EdDSA signature from key material..."
    sparkle_signature="$(compute_sparkle_signature "${ZIP_PATH}")"
  fi

  if [[ "${SPARKLE_SIGN_UPDATE}" == "1" && -z "${sparkle_signature}" ]]; then
    echo "[ERROR] Failed to resolve Sparkle EdDSA signature." >&2
    exit 1
  fi

  cat >"${UPDATE_METADATA_PATH}" <<EOF
{
  "version": "$(json_escape "${VERSION#v}")",
  "tag": "$(json_escape "${VERSION}")",
  "channel": "$(json_escape "${APPCAST_CHANNEL}")",
  "artifact_name": "$(json_escape "${zip_name}")",
  "artifact_url": "$(json_escape "${artifact_url}")",
  "sha256": "${zip_sha256}",
  "size": ${zip_size},
  "release_notes_url": "$(json_escape "${RELEASE_NOTES_URL}")",
  "appcast_url": "$(json_escape "${APPCAST_URL}")",
  "sparkle_signature": "$(json_escape "${sparkle_signature}")"
}
EOF

  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">'
    echo '  <channel>'
    echo '    <title>TimeDrive Updates</title>'
    echo '    <link>'"$(xml_escape "${RELEASE_NOTES_URL}")"'</link>'
    echo '    <description>TimeDrive release feed</description>'
    echo '    <language>en</language>'
    echo '    <item>'
    echo '      <title>TimeDrive '"$(xml_escape "${VERSION#v}")"'</title>'
    echo '      <pubDate>'"$(xml_escape "${pub_date}")"'</pubDate>'
    echo '      <sparkle:channel>'"$(xml_escape "${APPCAST_CHANNEL}")"'</sparkle:channel>'
    echo '      <sparkle:version>'"$(xml_escape "${VERSION#v}")"'</sparkle:version>'
    echo '      <sparkle:shortVersionString>'"$(xml_escape "${VERSION#v}")"'</sparkle:shortVersionString>'

    if [[ -n "${sparkle_signature}" ]]; then
      echo '      <enclosure url="'"$(xml_escape "${artifact_url}")"'" length="'"${zip_size}"'" type="application/octet-stream" sparkle:edSignature="'"$(xml_escape "${sparkle_signature}")"'" />'
    else
      echo '      <enclosure url="'"$(xml_escape "${artifact_url}")"'" length="'"${zip_size}"'" type="application/octet-stream" />'
      echo '      <!-- TODO: Add sparkle:edSignature for production auto-update security -->'
    fi

    echo '      <sparkle:releaseNotesLink>'"$(xml_escape "${RELEASE_NOTES_URL}")"'</sparkle:releaseNotesLink>'
    echo '      <description><![CDATA[Version '"$(xml_escape "${VERSION#v}")"' (SHA256: '"${zip_sha256}"')]]></description>'
    echo '    </item>'
    echo '  </channel>'
    echo '</rss>'
  } >"${APPCAST_PATH}"

  [[ -f "${APPCAST_PATH}" ]] || { echo "[ERROR] Missing artifact: ${APPCAST_PATH}" >&2; exit 1; }
  [[ -f "${UPDATE_METADATA_PATH}" ]] || { echo "[ERROR] Missing artifact: ${UPDATE_METADATA_PATH}" >&2; exit 1; }

  if is_production_release; then
    if ! grep -q 'sparkle:edSignature="' "${APPCAST_PATH}"; then
      echo "[ERROR] Production appcast must include sparkle:edSignature, but it is missing." >&2
      exit 1
    fi
  fi
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
  echo "Appcast generate:${APPCAST_GENERATE}"
  echo "Appcast URL:     ${APPCAST_URL:-<empty>}"
  echo "Channel:         ${APPCAST_CHANNEL}"
  echo "Sign update:     ${SPARKLE_SIGN_UPDATE}"
  echo "Artifacts:"
  if [[ "${APPCAST_GENERATE}" == "1" ]]; then
    ls -lh "${APP_PATH_DIST}" "${ZIP_PATH}" "${DMG_PATH}" "${SHA_PATH}" "${APPCAST_PATH}" "${UPDATE_METADATA_PATH}"
  else
    ls -lh "${APP_PATH_DIST}" "${ZIP_PATH}" "${DMG_PATH}" "${SHA_PATH}"
  fi
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
  resolve_download_base_url
  resolve_release_notes_url
  preflight
  validate_autoupdate_configuration
  validate_scheme
  build_app
  validate_built_app_sparkle_configuration
  version_guardrails
  package_artifacts
  generate_update_files
  print_summary
  publish_release
  echo "[INFO] Release pipeline completed successfully."
}

main "$@"
