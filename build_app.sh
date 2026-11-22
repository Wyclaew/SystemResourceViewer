#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

APP_NAME="Resource Monitor"
DMG_NAME="${APP_NAME}.dmg"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
DMG_STAGE=".tmp/dmg_stage"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist 2>/dev/null || echo "1.1.0")
echo "=== Packaging Resource Monitor v${VERSION} ==="

echo "=== 1. Checking Application Icon ==="
if [ ! -f "AppIcon.icns" ]; then
    echo "Generating AppIcon.icns..."
    mkdir -p .tmp/clang-cache
    swift -module-cache-path .tmp/clang-cache generate_icon.swift
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
else
    echo "AppIcon.icns found."
fi

echo "=== 2. Building Production Release Binary (Strict Concurrency) ==="
mkdir -p .tmp/clang-cache
TMPDIR="$PWD/.tmp" swift build -c release --disable-sandbox \
    -Xbuild-tools-swiftc -module-cache-path -Xbuild-tools-swiftc "$PWD/.tmp/clang-cache" \
    -Xswiftc -module-cache-path -Xswiftc "$PWD/.tmp/clang-cache" \
    -Xswiftc -strict-concurrency=complete

echo "=== 3. Assembling macOS .app Bundle ==="
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp ".build/release/SystemResourceViewer" "${MACOS_DIR}/SystemResourceViewer"
chmod +x "${MACOS_DIR}/SystemResourceViewer"
cp "Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

echo "Applying Hardened Runtime code signature with entitlements..."
codesign --force --deep \
    --options runtime \
    --entitlements "SystemResourceViewer.entitlements" \
    --sign - "${BUNDLE_DIR}"

echo "Verifying bundle code signature..."
codesign --verify --deep --strict --verbose=2 "${BUNDLE_DIR}"

# Maintain legacy alias for backwards compatibility
rm -rf "System Resource Viewer.app"
ln -s "${BUNDLE_DIR}" "System Resource Viewer.app"

echo "Bundle successfully created: ${BUNDLE_DIR}"

echo "=== 4. Staging DMG Package ==="
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${BUNDLE_DIR}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

echo "=== 5. Generating Compressed Disk Image (.dmg) ==="
rm -f "${DMG_NAME}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGE}" -ov -format UDZO "${DMG_NAME}"

echo "Cleaning up staging directory..."
rm -rf "${DMG_STAGE}"

echo "=== 6. Verifying DMG Integrity and Contents ==="
hdiutil verify "${DMG_NAME}"

MOUNT_DIR=$(mktemp -d /tmp/resmon_verify.XXXXXX)
hdiutil attach "${DMG_NAME}" -mountpoint "${MOUNT_DIR}" -nobrowse -quiet

if [ ! -d "${MOUNT_DIR}/${APP_NAME}.app" ]; then
    echo "Verification error: ${APP_NAME}.app missing from mounted DMG!"
    hdiutil detach "${MOUNT_DIR}" -quiet || true
    rm -rf "${MOUNT_DIR}"
    exit 1
fi

if [ ! -L "${MOUNT_DIR}/Applications" ]; then
    echo "Verification error: /Applications symlink missing from mounted DMG!"
    hdiutil detach "${MOUNT_DIR}" -quiet || true
    rm -rf "${MOUNT_DIR}"
    exit 1
fi

hdiutil detach "${MOUNT_DIR}" -force -quiet || true
rm -rf "${MOUNT_DIR}"

echo "=================================================="
echo " Packaging completed successfully!"
echo " Artifact: ${DMG_NAME} ($(du -sh "${DMG_NAME}" | cut -f1))"
echo " Bundle:   ${BUNDLE_DIR}"
echo "=================================================="
