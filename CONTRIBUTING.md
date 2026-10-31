# Contributing

Thanks for your interest in Video Compressor! Bug reports, ideas and pull requests are welcome.

## Getting started

Requirements: macOS 14+, Xcode 16+ (Swift 5.10+). `brew install ffmpeg` is needed for the
tests and for the WebM / MKV / GIF / AV1 / VP9 code paths.

```bash
git clone https://github.com/ardasnturk/video-compressor.git
cd video-compressor
swift build
swift test
./scripts/build-app.sh --install   # ad-hoc signed app in /Applications
```

To work on the UI without the menu bar popover, open the same view in a regular window:

```bash
open --env VC_DEBUG_WINDOW=1 --env VC_DEBUG_FILES=/path/to/video.mov "build/Video Compressor.app"
```

## Pull requests

- Keep changes focused; one topic per PR.
- Match the existing style (SwiftUI + `@Observable`, small views, comments only where the *why* isn't obvious).
- Run `swift test` before opening the PR. Add a test to `Tests/VideoCompressorTests` when you
  change encoding behaviour.
- Write user-facing strings in English inside `Text("…")`, `Button("…")` or `String(localized: "…")`, then run
  `./scripts/update-strings.sh` and add the translations (see below).
- Add a line to the `Unreleased` section of `CHANGELOG.md`.

## Adding or improving a language

All UI text is in [`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings), a String Catalog with English
as the source language. It is compiled into `<lang>.lproj` folders when the app is bundled.

1. Open `Resources/Localizable.xcstrings` in Xcode (or edit the JSON) and add your language.
   Translate every string and keep format specifiers such as `%@` and `%lld`. For several arguments, use
   positional ones (`%1$@`, `%2$@`) when the word order changes.
2. Add the language code to `LocalizationTests.languages` in `Tests/VideoCompressorTests/LocalizationTests.swift`.
3. Run `swift test`. The localization test fails on any missing translation or mismatched specifier.
4. Check the UI with your language. Labels are short on purpose, because the popover is only 392 pt wide:
   ```bash
   ./scripts/build-app.sh
   open -n --env VC_DEBUG_WINDOW=1 "build/Video Compressor.app" --args -AppleLanguages "(de)"
   ```

## Releasing (maintainers)

1. Bump `VERSION` and move the changelog entries under the new version.
2. Commit, then run `./scripts/release.sh --publish`.

The script signs with Developer ID, notarizes the app and the DMG, writes the Sparkle
`appcast.xml` and creates the GitHub release. See the header of `scripts/release.sh` for the
one-time keychain setup.
