#!/bin/zsh
# Re-extracts every user-facing string from the Swift sources into Resources/Localizable.xcstrings.
# Existing translations are kept; new keys appear untranslated, removed keys are marked stale.
# Translate the new keys (Xcode can open .xcstrings, or edit the JSON) and run `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)"
find Sources -name "*.swift" -exec touch {} +
swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata "$OUT"/*.stringsdata
rm -rf "$OUT"
echo "✓ Resources/Localizable.xcstrings updated"
