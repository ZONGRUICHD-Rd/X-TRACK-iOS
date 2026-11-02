#!/usr/bin/env bash
# Build an UNSIGNED X-TRACK .ipa for iOS 26 (arm64).
# Requirements: macOS + Xcode 26, XcodeGen (brew install xcodegen).
# Output: build/X-TRACK-unsigned.ipa
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD="$ROOT/build"
CONFIGURATION="${CONFIGURATION:-Release}"

rm -rf "$BUILD"
mkdir -p "$BUILD"

xcodegen generate --spec project.yml

xcodebuild \
    -project XTrack.xcodeproj \
    -scheme XTrack \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    build | tee "$BUILD/xcodebuild.log" | (command -v xcbeautify >/dev/null && xcbeautify || cat)

APP="$BUILD/DerivedData/Build/Products/${CONFIGURATION}-iphoneos/XTrack.app"
if [ ! -d "$APP" ]; then
    echo "error: $APP not found" >&2
    exit 1
fi

mkdir -p "$BUILD/Payload"
cp -R "$APP" "$BUILD/Payload/"
(cd "$BUILD" && zip -qry X-TRACK-unsigned.ipa Payload)

echo "IPA: $BUILD/X-TRACK-unsigned.ipa"
/usr/bin/plutil -p "$APP/Info.plist" | grep -E "CFBundleIdentifier|MinimumOSVersion|CFBundleShortVersionString" || true
ls -lh "$BUILD/X-TRACK-unsigned.ipa"
