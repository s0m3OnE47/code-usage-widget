# Changelog

All notable changes to this project are documented in this file.

Versioning follows **`app.feature.patch`**. See [`VERSION`](VERSION).

## [0.4.4] — 2026-09-03

### Changed (desktop widget)

- Two-column grid on Medium (6 cells) and Large (all 12 providers, no more "+N more"); Small shows 3
- Beautified rows: provider icon tile, card background, slimmer gradient bars, worst-status dot in the header, "now" for fresh data

## [0.4.3] — 2026-09-03

### Fixed

- Cursor header vs bar desync (6% vs 7%): `Int()` truncation replaced with rounding everywhere, matching the `%.0f` bar labels
- Keychain prompt storms: denied/missing items are now cached per-launch (previously a deny re-prompted every 30s poll); Chrome Safe Storage likewise; new **Reload Secrets** menu item re-reads after out-of-band changes
- Panel clicks falling to Finder: window sits one level above Finder desktop; hosting layer has a hit-testable underlay

### Added

- **Providers** menu-bar submenu with per-provider show/hide checkmarks (persisted to `disabled_providers`)

## [0.4.2] — 2026-09-03

### Fixed

- Scroll unreliable in the floating panel: header now has **chevron up/down buttons** that page deterministically via `ScrollViewReader` (works even when wheel/drag gestures never reach the desktop-level window)
- Keychain prompt storm: `KeychainStore` and Chrome Safe Storage reads are cached in memory, so each item prompts at most once per launch instead of every 30s poll; README documents Always Allow + `use_keychain: false` escape hatch

## [0.4.1] — 2026-09-03

### Fixed

- Cursor "sign in" error: `SQLiteReader` opens copies with `immutable=1`, fixing `SQLITE_CANTOPEN` on WAL-mode DBs (regression from 0.2.3)
- Refresh button dead: drag monitor swallowed `mouseUp` for plain clicks — clicks without movement now pass through, so Refresh/buttons/billing links fire
- Scrolling broken / lower rows cut off: window drags now start only in the header strip; content drags belong to the `ScrollView` (drag-to-scroll, scroller knob)

## [0.4.0] — 2026-09-03

### Added

- Keychain-backed secrets (`use_keychain`, service `com.anakin.code-usage-widget`): resolution order Keychain → inline → env; menu bar **Migrate Secrets to Keychain** moves inline keys/tokens and redacts `config.json`
- Usage history: append-only `history.jsonl` (5000-line cap) plus 24h sparklines in the host panel
- New providers: **Anthropic**, **Gemini**, **xAI** (key check + manual `balance_usd`), **Copilot** (GitHub token auth check), **Ollama** (local `/api/tags` model count), **OpenRouter** (live `/api/v1/credits`)

## [0.3.0] — 2026-09-03

### Added (features)

- `disabled_providers` to hide providers; `privacy_mode` masks amounts (`•••`); `notifications_enabled` with 80%/100% alerts
- Billing deep-links: host rows and widget rows link to each provider's billing page
- Chrome multi-profile: Default, Profile 1/2, Brave Default

### Changed (improvements)

- Config validation with warnings (clamped `poll_interval_seconds` 10–3600, unknown provider ids)
- Poll timer rebuilds when interval changes; widget timeline fallback 15m → 5m
- `HTTPClient` uses ephemeral session (no shared cookies), status-preserving errors, cached POSIX formatters

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
