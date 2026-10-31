#!/bin/zsh
# Builds, signs, notarizes and publishes a release.
#
#   ./scripts/release.sh            build + notarize → build/release/<version>/
#   ./scripts/release.sh --publish  also tags v<version> and creates the GitHub release
#
# One-time setup:
#   • A "Developer ID Application" certificate in the login keychain
#   • xcrun notarytool store-credentials "video-compressor-notary" …
#   • Sparkle EdDSA key in the keychain (generate_keys --account video-compressor)
#
# Environment overrides: SIGN_IDENTITY, NOTARY_PROFILE, SPARKLE_ACCOUNT, GITHUB_REPO
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Video Compressor"
VERSION="$(cat VERSION)"
TAG="v$VERSION"
GITHUB_REPO="${GITHUB_REPO:-ardasnturk/video-compressor}"
NOTARY_PROFILE="${NOTARY_PROFILE:-video-compressor-notary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-video-compressor}"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
OUT="build/release/$VERSION"
DMG="$OUT/VideoCompressor-$VERSION.dmg"
APP="build/$APP_NAME.app"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -m1 -o '"Developer ID Application: .*"' | tr -d '"')" || true
fi
[[ -n "$SIGN_IDENTITY" ]] || { echo "✗ No Developer ID Application certificate found"; exit 1; }
export SIGN_IDENTITY

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "✗ Notary profile '$NOTARY_PROFILE' not found. Run: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" …"
    exit 1
}

if [[ "${1:-}" == "--publish" ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "✗ Working tree is not clean"; exit 1; }
    ! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "✗ Tag $TAG already exists"; exit 1; }
fi

rm -rf "$OUT"; mkdir -p "$OUT"

# 1. Build + sign the app.
./scripts/build-app.sh

# 2. Notarize and staple the app so it also works offline once copied out of the DMG.
echo "▸ Notarizing app…"
ditto -c -k --keepParent "$APP" "$OUT/app.zip"
xcrun notarytool submit "$OUT/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm "$OUT/app.zip"

# 3. DMG with an Applications shortcut for drag-to-install.
echo "▸ Creating DMG…"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# 4. Sparkle appcast (one item; served from releases/latest/download/appcast.xml).
echo "▸ Writing appcast…"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$DMG")"
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$(basename "$DMG")"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>$APP_NAME</title>
    <link>https://github.com/$GITHUB_REPO</link>
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$GITHUB_REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="$DOWNLOAD_URL" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

shasum -a 256 "$DMG" | tee "$OUT/SHA256SUMS.txt"
echo "✓ $OUT"

# 5. Publish.
if [[ "${1:-}" == "--publish" ]]; then
    echo "▸ Publishing $TAG…"
    NOTES="$(awk -v v="$VERSION" '$0 ~ "^## \\[?"v {f=1; next} /^## / && f {exit} f' CHANGELOG.md)"
    git tag -a "$TAG" -m "$APP_NAME $VERSION"
    git push origin "$TAG"
    gh release create "$TAG" "$DMG" "$OUT/appcast.xml" "$OUT/SHA256SUMS.txt" \
        --repo "$GITHUB_REPO" --title "$APP_NAME $VERSION" --notes "$NOTES"
    echo "✓ https://github.com/$GITHUB_REPO/releases/tag/$TAG"
fi
