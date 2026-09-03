# Changelog

All notable changes to this project are documented in this file.

Versioning follows **`app.feature.patch`**. See [`VERSION`](VERSION).

## [0.2.2] — 2026-09-03

### Changed

- Renamed the app bundle to **AIUsageWidget** (display name: AI Usage Widget)
- Added a tesseract app icon

## [0.2.1] — 2026-09-03

### Added

- **Hide Menu Bar Icon** so only the desktop widget stays visible while the host keeps polling
- Clicking the desktop widget (or opening the app) restores the menu bar
- Enabling hide also turns on **Launch at Login** so data keeps updating after reboot
- Changelog for all releases

### Changed

- README rewritten around adding the WidgetKit widget and widget-only mode

## [0.2.0] — 2026-09-03

### Added

- Native **AI Usage** WidgetKit desktop widget (Small / Medium / Large)
- Menu-bar host with no Dock icon; optional floating panel
- Xcode-built WidgetKit app-extension (required for the macOS widget gallery)
- Shared usage snapshot (Application Support, App Group, widget container)

### Changed

- Replaced LaunchAgent auto-start with **Launch at Login** (`SMAppService`)

## [0.1.0] — 2026-09-03

### Added

- First public release: floating macOS widget for Cursor, CommandCode, DeepSeek, OpenAI, Sarvam AI, and OpenCode
- Config at `~/.config/code-usage-widget/config.json`
- 30s polling, animated progress bars, `app.feature.patch` versioning
