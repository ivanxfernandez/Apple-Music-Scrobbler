#!/bin/bash
# Builds "Apple Music Scrobbler.app" (and a .zip of it) into macos/build/.
#
#   macos/build-app.sh [version]       version defaults to the newest one in CHANGELOG.md
#
# Optional environment variables (the release workflow sets them):
#   LASTFM_API_KEY / LASTFM_API_SECRET  baked in so users don't need their own API key
#   GITHUB_REPO        owner/repo; turns on update checks against its releases
#   DISCORD_CLIENT_ID  defaults to the project's Discord application
#   UNIVERSAL=1        build for both Apple Silicon and Intel
#   SIGN_IDENTITY      a "Developer ID Application: ..." identity; default "-" signs ad hoc (unsigned for Gatekeeper)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-$(grep -m1 -oE '^## [0-9]+\.[0-9]+\.[0-9]+' ../CHANGELOG.md | cut -c4-)}"
VERSION="${VERSION#v}"
VERSION="${VERSION%%-*}" # CFBundleShortVersionString must be plain numbers
DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID-1556532063429988354}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"

ARCHS=()
if [ "${UNIVERSAL:-0}" = 1 ]; then ARCHS=(--arch arm64 --arch x86_64); fi

echo "Building $VERSION${COMMIT:+ ($COMMIT)}..."
swift build -c release --product AppleMusicScrobbler ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR="$(swift build -c release --show-bin-path ${ARCHS[@]+"${ARCHS[@]}"})"

APP="build/Apple Music Scrobbler.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AppleMusicScrobbler" "$APP/Contents/MacOS/AppleMusicScrobbler"

# App icon from the same 1024 px logo the Windows icon and Discord asset use.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size ../docs/logo-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) ../docs/logo-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

PLIST="$APP/Contents/Info.plist"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.ivanxfernandez.AppleMusicScrobbler</string>
    <key>CFBundleName</key><string>Apple Music Scrobbler</string>
    <key>CFBundleDisplayName</key><string>Apple Music Scrobbler</string>
    <key>CFBundleExecutable</key><string>AppleMusicScrobbler</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Apple Music Scrobbler reads how far into a song you are, so songs you play on repeat are scrobbled each time.</string>
</dict>
</plist>
PLIST
# Values that may contain anything go in through plutil, which escapes them.
set_string() { plutil -replace "$1" -string "$2" "$PLIST"; }
set_string CFBundleShortVersionString "$VERSION"
set_string CFBundleVersion "$VERSION"
set_string NSHumanReadableCopyright "MIT License. Not affiliated with Apple or Last.fm."
set_string LastFmApiKey "${LASTFM_API_KEY:-}"
set_string LastFmApiSecret "${LASTFM_API_SECRET:-}"
set_string GitHubRepo "${GITHUB_REPO:-}"
set_string DiscordClientId "$DISCORD_CLIENT_ID"
set_string GitCommit "$COMMIT"
plutil -lint "$PLIST" >/dev/null

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP"
else
    # Hardened runtime (needed for notarization) blocks Apple Events unless the entitlement allows them.
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements AppleMusicScrobbler.entitlements "$APP"
fi

ZIP="build/AppleMusicScrobbler-macOS.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $APP and $ZIP"
