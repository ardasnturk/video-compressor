#!/bin/zsh
# Builds "build/Video Compressor.app".
#
#   ./scripts/build-app.sh             ad-hoc signed, for local use
#   ./scripts/build-app.sh --install   also copies it to /Applications and launches it
#
# Environment:
#   SIGN_IDENTITY   codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#                   Defaults to "-" (ad-hoc). A real identity enables the hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Video Compressor"
BUNDLE_ID="com.jastech.videocompressor"
VERSION="$(cat VERSION)"
FEED_URL="https://github.com/ardasnturk/video-compressor/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="9VyCodJb+Tp3XfejUzSLqOUDA86wqZbzpHcuAo/SBuc="
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/$APP_NAME.app"

echo "▸ Compiling $VERSION (release, arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64 >/dev/null
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "▸ Rendering icon…"
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p build
    swift scripts/make-icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
    rm -rf "$ICONSET"
fi

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/VideoCompressor" "$APP/Contents/MacOS/VideoCompressor"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>VideoCompressor</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Arda Sentürk. MIT License.</string>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Video</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.video</string>
                <string>public.mpeg-4</string>
                <string>com.apple.quicktime-movie</string>
                <string>org.matroska.mkv</string>
                <string>org.webmproject.webm</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "▸ Signing ($([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "$SIGN_IDENTITY"))…"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi
# Inside-out, as Sparkle's documentation describes. --deep is not used on purpose.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict --deep "$APP"

echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x VideoCompressor 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP" "/Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    echo "✓ /Applications/$APP_NAME.app"
fi
