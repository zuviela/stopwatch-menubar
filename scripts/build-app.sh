#!/usr/bin/env bash
set -euo pipefail

# Build a Stopwatch.app bundle without Xcode.

cd "$(dirname "$0")/.."

APP_NAME="Stopwatch"
APP_DIR="${APP_NAME}.app"
BIN_NAME="${APP_NAME}"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Build product not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${BIN_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

chmod +x "${APP_DIR}/Contents/MacOS/${BIN_NAME}"

echo "==> Built ${APP_DIR}"
echo "    Run with: open ${APP_DIR}"
