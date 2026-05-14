#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ONEsa"
CONFIGURATION="${1:-${CONFIGURATION:-debug}}"

case "${CONFIGURATION}" in
  debug|release)
    ;;
  *)
    echo "error: unsupported configuration '${CONFIGURATION}'. Use 'debug' or 'release'." >&2
    exit 64
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INFO_PLIST_SOURCE="${PROJECT_DIR}/AppResources/Info.plist"
APP_BUNDLE_DIR="${PROJECT_DIR}/.build/app/${CONFIGURATION}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

if [[ ! -f "${INFO_PLIST_SOURCE}" ]]; then
  echo "error: missing Info.plist at ${INFO_PLIST_SOURCE}" >&2
  exit 66
fi

cd "${PROJECT_DIR}"

BIN_DIR="$(swift build --disable-sandbox --configuration "${CONFIGURATION}" --show-bin-path)"
swift build --disable-sandbox --configuration "${CONFIGURATION}"

EXECUTABLE_SOURCE="${BIN_DIR}/${APP_NAME}"
if [[ ! -x "${EXECUTABLE_SOURCE}" ]]; then
  echo "error: expected executable not found at ${EXECUTABLE_SOURCE}" >&2
  exit 66
fi

rm -rf "${APP_BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_SOURCE}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"
cp "${INFO_PLIST_SOURCE}" "${CONTENTS_DIR}/Info.plist"

CF_BUNDLE_EXECUTABLE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || true)"
if [[ -z "${CF_BUNDLE_EXECUTABLE}" ]]; then
  echo "error: ${CONTENTS_DIR}/Info.plist must contain CFBundleExecutable" >&2
  exit 65
fi

if [[ "${CF_BUNDLE_EXECUTABLE}" != "${APP_NAME}" ]]; then
  echo "error: CFBundleExecutable '${CF_BUNDLE_EXECUTABLE}' does not match expected executable '${APP_NAME}'" >&2
  exit 65
fi

if [[ ! -x "${MACOS_DIR}/${CF_BUNDLE_EXECUTABLE}" ]]; then
  echo "error: CFBundleExecutable '${CF_BUNDLE_EXECUTABLE}' does not match an executable file in ${MACOS_DIR}" >&2
  exit 66
fi

LSUI_ELEMENT_VALUE="$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || true)"
if [[ "${LSUI_ELEMENT_VALUE}" != "true" && "${LSUI_ELEMENT_VALUE}" != "1" ]]; then
  echo "error: ${CONTENTS_DIR}/Info.plist must contain LSUIElement=true" >&2
  exit 65
fi

echo "Built ${APP_BUNDLE_DIR}"
echo "Verified CFBundleExecutable=${CF_BUNDLE_EXECUTABLE}"
echo "Verified LSUIElement=true"
