#!/usr/bin/env bash
# Build, notarize, staple, and package DepartureBoardSaver for release.
#
# Prerequisite: Set up notarytool
#
# Usage:
#   ./scripts/release.sh 1.0.0

set -euo pipefail

VERSION="${1:?Usage: $0 <version>  e.g. $0 1.0.0}"
SCHEME="DepartureBoardSaver"
BUILD_DIR="build/release"
DERIVED_DATA="build/deriveddata"
SAVER="$BUILD_DIR/DepartureBoardSaver.saver"
SUBMIT_ZIP="build/submit.zip"
RELEASE_ZIP="DepartureBoardSaver-v${VERSION}.zip"

# Clean previous output so we don't accidentally ship a stale build.
rm -rf "$BUILD_DIR" "$SUBMIT_ZIP" "$RELEASE_ZIP"

echo "==> Building $SCHEME (Release, v${VERSION})..."
DEVELOPER_DIR=/Applications/Xcode-27.0-beta1.app/Contents/Developer \
xcodebuild \
  -project DepartureBoardSaver.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CONFIGURATION_BUILD_DIR="$(pwd)/$BUILD_DIR" \
  build

echo "==> Zipping for notarization..."
ditto -c -k --keepParent "$SAVER" "$SUBMIT_ZIP"

echo "==> Submitting to Apple notarization service..."
xcrun notarytool submit "$SUBMIT_ZIP" \
  --keychain-profile "DepartureBoardSaver" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$SAVER"

echo "==> Verifying Gatekeeper acceptance..."
spctl -a -vvv -t install "$SAVER"

echo "==> Packaging release zip..."
ditto -c -k --keepParent "$SAVER" "$RELEASE_ZIP"
rm "$SUBMIT_ZIP"

echo ""
echo "Done! Release artifact: $RELEASE_ZIP"
echo "Upload this file to your GitHub release."
