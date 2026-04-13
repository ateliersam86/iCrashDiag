#!/bin/bash
# Build iCrashDiag.app — packages the SwiftPM binary into a proper macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONFIG="${1:-debug}"
APP_NAME="iCrashDiag"
BUNDLE="${SCRIPT_DIR}/${APP_NAME}.app"
BINARY_PATH="${SCRIPT_DIR}/.build/arm64-apple-macosx/${BUILD_CONFIG}/${APP_NAME}"

echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
if [ "$BUILD_CONFIG" = "release" ]; then
    swift build -c release 2>&1
else
    swift build 2>&1
fi

echo "==> Creating .app bundle..."
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

# Copy binary
cp "${BINARY_PATH}" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "${SCRIPT_DIR}/iCrashDiag/Resources/Info.plist" "${BUNDLE}/Contents/Info.plist"

# Copy icon
cp "${SCRIPT_DIR}/iCrashDiag/Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"

# Copy SwiftPM resource bundle — TWO locations required:
#
# 1. Contents/Resources/  — standard macOS location (used when app is in /Applications)
# 2. App root (.app/)     — where SwiftPM's generated Bundle.module accessor looks:
#      mainPath = Bundle.main.bundleURL.appendingPathComponent("iCrashDiag_iCrashDiag.bundle")
#    Without this copy, Bundle.module falls back to a hardcoded .build/ path on the
#    developer's Desktop, triggering a macOS TCC privacy prompt before the window opens.
KNOWLEDGE_BUNDLE="${SCRIPT_DIR}/.build/arm64-apple-macosx/${BUILD_CONFIG}/iCrashDiag_iCrashDiag.bundle"
if [ -d "${KNOWLEDGE_BUNDLE}" ]; then
    cp -R "${KNOWLEDGE_BUNDLE}" "${BUNDLE}/Contents/Resources/"
    cp -R "${KNOWLEDGE_BUNDLE}" "${BUNDLE}/"   # <-- fixes TCC prompt
fi

# Copy localization files to Contents/Resources/ for Bundle.main lookup
for lproj in "${SCRIPT_DIR}/iCrashDiag/Resources/"*.lproj; do
    if [ -d "${lproj}" ]; then
        cp -R "${lproj}" "${BUNDLE}/Contents/Resources/"
    fi
done

echo "==> Signing ad-hoc..."
codesign --force --deep --sign - "${BUNDLE}" 2>&1 || true

echo ""
echo "Done! ${BUNDLE}"
echo "Run: open ${BUNDLE}"
