#!/bin/bash
set -euo pipefail

APP_NAME="PortsMonitor"
APP_BUNDLE_ID="com.example.PortsMonitor"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
SOURCE_DIR="Sources/PortsMonitor"
MODULE_CACHE="$(pwd)/.build/ModuleCache"
INFO_PLIST="${CONTENTS_DIR}/Info.plist"

echo "Preparing app bundle..."
mkdir -p "${MACOS_DIR}" "${MODULE_CACHE}"
cp "${SOURCE_DIR}/Info.plist" "${INFO_PLIST}"

# Replace Xcode-only placeholders so Finder can launch the manually built app bundle.
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_ID}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_NAME}" "${INFO_PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "${INFO_PLIST}"

echo "Building ${APP_NAME}..."
CLANG_MODULE_CACHE_PATH="${MODULE_CACHE}" swiftc \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  -parse-as-library \
  -o "${MACOS_DIR}/${APP_NAME}" \
  "${SOURCE_DIR}/Main.swift" \
  "${SOURCE_DIR}/AppDelegate.swift" \
  "${SOURCE_DIR}/ViewController.swift"

chmod +x "${MACOS_DIR}/${APP_NAME}"
echo "Build successful: ${APP_DIR}"

if [[ "${NO_OPEN:-0}" == "1" ]]; then
  echo "NO_OPEN=1 set, skip launch."
else
  if [[ "${USE_OPEN:-0}" == "1" ]]; then
    echo "Launching ${APP_NAME} via open..."
    open "${APP_DIR}"
  else
    echo "Launching ${APP_NAME} executable..."
    "${MACOS_DIR}/${APP_NAME}" &
  fi
fi
