#!/bin/bash
# Build a universal, ad-hoc signed app and package distributable macOS downloads.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' NixMind/Info.plist)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Invalid app version: $VERSION" >&2
  exit 1
fi
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$VERSION" ]]; then
  echo "Release tag $RELEASE_TAG does not match app version v$VERSION" >&2
  exit 1
fi

xcodebuild -project NixMind.xcodeproj -scheme NixMind \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/release \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build

APP='build/release/Build/Products/Release/Nix Mind.app'
BINARY="$APP/Contents/MacOS/Nix Mind"
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$BUNDLE_VERSION" == "$VERSION" ]]
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$BUILD_VERSION" == "$VERSION" ]]
lipo "$BINARY" -verify_arch arm64 x86_64
test -f "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
# Xcode removes framework headers when embedding; refresh that resource seal.
# Keep Sparkle's nested helper signatures and entitlements intact.
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/Sparkle.framework"
codesign --verify --deep --strict "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

mkdir -p dist
# A locally generated feed from an older build must not accompany a new archive.
rm -f dist/appcast.xml
ZIP="Nix-Mind-$VERSION-macos-universal.zip"
DMG="Nix-Mind-$VERSION-macos-universal.dmg"
# Delete only the generated ZIP before reusing its exact output path.
rm -f "dist/$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ZIP"

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/nix-mind-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Nix Mind.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Nix Mind $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "dist/$DMG"
hdiutil verify "dist/$DMG"
(
  cd dist
  shasum -a 256 "$ZIP" "$DMG" > SHA256SUMS.txt
)
printf 'Release %s packaged in dist/\n' "$VERSION"
