#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="ONEsa"
CONFIGURATION="release"

cd "${PROJECT_DIR}"

./Scripts/build-app-bundle.sh "${CONFIGURATION}"

APP_BUNDLE="${PROJECT_DIR}/.build/app/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "error: app bundle not found at ${APP_BUNDLE}" >&2
  exit 66
fi

GIT_DESCRIBE="$(git describe --tags --always --dirty 2>/dev/null || true)"
if [[ -z "${GIT_DESCRIBE}" ]]; then
  GIT_DESCRIBE="nogit"
fi
STAMP="$(date +"%Y%m%d-%H%M%S")"

DIST_DIR="${PROJECT_DIR}/.build/dist"
OUT_DIR="${DIST_DIR}/${APP_NAME}-${GIT_DESCRIBE}-${STAMP}"
mkdir -p "${OUT_DIR}"

TMP_DIR="$(mktemp -d "${OUT_DIR}/staging.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

cp -R "${APP_BUNDLE}" "${TMP_DIR}/${APP_NAME}.app"

ZIP_PATH="${OUT_DIR}/${APP_NAME}.zip"
ditto -c -k --sequesterRsrc --keepParent "${TMP_DIR}/${APP_NAME}.app" "${ZIP_PATH}"

SHA256="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
SIZE_BYTES="$(stat -f%z "${ZIP_PATH}")"

INSTALL_PATH="${OUT_DIR}/INSTALL.txt"
cat > "${INSTALL_PATH}" <<EOF
ONEsa (${APP_NAME})
Build: ${GIT_DESCRIBE}
Archive: ${APP_NAME}.zip
SHA-256: ${SHA256}
Size: ${SIZE_BYTES} bytes

安装步骤（未签名小范围分发）：
1. 解压 ${APP_NAME}.zip
2. 将 ${APP_NAME}.app 拖到 /Applications
3. 首次打开：
   - Finder 中右键 ${APP_NAME}.app -> 打开 -> 再确认一次
   - 或 系统设置 -> 隐私与安全性 -> 仍要打开
4. 打开后在设置页填写 app_id / app_secret / redirect_uri / chat_id / sender filter，并点击开始授权

提示：
- 若设备有公司/学校管控策略，可能无法运行未签名应用。
- 这是独立安装包，不会携带其他人的配置或 Keychain 数据。
EOF

echo "OK"
echo "Output: ${OUT_DIR}"
echo "Zip:    ${ZIP_PATH}"
echo "Install:${INSTALL_PATH}"
