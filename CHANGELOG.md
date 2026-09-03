# Changelog

All notable changes to this project are documented in this file.

Versioning follows **`app.feature.patch`**. See [`VERSION`](VERSION).

## [0.2.3] — 2026-09-03

### Fixed (security)

- `config.json` and config dir now forced to `0600` / `0700`; existing installs hardened on load; `install.sh` creates them locked down
- Firefox/Cursor DB copies use UUID `0600` temp files via `SecureTempFile` instead of predictable `/tmp/cuw_*_PID`
- Chrome cookies: Python only extracts `encrypted_value` (base64, `mkstemp`, parameterized SQL); AES-128-CBC decrypt moved to Swift `CommonCrypto` so the derived key never appears in `ps` (`openssl -K <hex>` removed); Safe Storage password via Keychain API instead of `security` CLI
- Firefox/Cursor SQLite via bound parameters (`SQLiteReader` + `-lsqlite3`); cookie names/hosts allow-listed, LIKE wildcards escaped, Firefox profile traversal rejected
- `.gitignore` now ignores `config.json`, `*.sqlite`, `*.vscdb`; ad-hoc codesign uses `--options runtime`

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
