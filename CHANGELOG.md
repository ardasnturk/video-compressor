# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.1] - 2026-11-01

First public release.

### Added
- Menu bar app with drag & drop, file picker (⌘O), folder support and Finder "Open With".
- Export to MP4, MOV, M4V, WebM, MKV and GIF.
- H.264 and HEVC through AVFoundation / VideoToolbox (hardware accelerated, no dependencies).
- AV1 and VP9, plus inputs AVFoundation can't read, through a local ffmpeg installation.
- Quality mode (5 levels) and target-size mode with an automatic second pass.
- Presets: Discord, WhatsApp, E-mail, Web, Archive, GIF.
- Resolution and frame-rate limits, audio removal.
- Job queue with estimated size, ETA, savings and live progress in the menu bar.
- Preferences: output folder, file suffix, notifications, sound, launch at login, concurrency.
- Automatic updates via Sparkle.
- Signed with Developer ID and notarized DMG.
