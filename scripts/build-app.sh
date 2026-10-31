#!/bin/zsh
# Builds a release "Video Compressor.app" into ./build and optionally installs it.
#   ./scripts/build-app.sh            → build/Video Compressor.app
#   ./scripts/build-app.sh --install  → also copies it to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Video Compressor"
BUNDLE_ID="com.jastech.videocompressor"
VERSION="1.0.0"
APP="build/$APP_NAME.app"

echo "▸ Compiling (release, arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64 >/dev/null
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/VideoCompressor"

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VideoCompressor"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.video</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>tr</string>
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

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1

echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x VideoCompressor 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✓ /Applications/$APP_NAME.app yüklendi ve açıldı"
fi
