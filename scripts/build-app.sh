#!/usr/bin/env bash
set -euo pipefail

# Build a Tally.app bundle without Xcode.

cd "$(dirname "$0")/.."

APP_NAME="Tally"
APP_DIR="${APP_NAME}.app"
BIN_NAME="${APP_NAME}"

INSTALL_DIR="/Applications"

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

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating AppIcon.icns"
    ./scripts/make-icon.swift
    iconutil -c icns -o Resources/AppIcon.icns Resources/AppIcon.iconset
fi
cp Resources/AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"

chmod +x "${APP_DIR}/Contents/MacOS/${BIN_NAME}"

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - "${APP_DIR}" >/dev/null

echo "==> Built ${APP_DIR}"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}/${APP_DIR}"
    ditto "${APP_DIR}" "${INSTALL_DIR}/${APP_DIR}"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "${INSTALL_DIR}/${APP_DIR}" >/dev/null
    mdimport "${INSTALL_DIR}/${APP_DIR}"
    echo "==> Installed to ${INSTALL_DIR}/${APP_DIR}"
    echo "    Run with: open -a ${APP_NAME}"
else
    echo "    Run with: open ${APP_DIR}"
    echo "    Install with: ./scripts/build-app.sh --install"
fi
