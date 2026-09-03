# AI Code Usage Widget

A native macOS floating widget that shows real-time usage limits for **Cursor**, **CommandCode AI**, **DeepSeek**, **OpenAI**, **Sarvam AI**, and **OpenCode** — with animated progress bars and per-provider icons.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Draggable glass-morphism floating panel (320×780)
- Animated progress bars with color shifts at 70% / 90% usage
- Per-AI icons with pulse animations
- Auto-refreshes every 30 seconds (reloads config on each refresh)
- Refresh via ↻ button, **⌘R**, or right-click menu
- Auto-starts on login via **Launch at Login** (right-click menu)
- Right-click menu: Refresh · Open Config · Quit

## Requirements

- macOS 26+ (Apple Silicon)
- Xcode Command Line Tools (`xcode-select --install`)
- Firefox or Chrome (for cookie-based providers)

## Quick Start

```bash
git clone https://github.com/s0m3OnE47/code-usage-widget.git
cd code-usage-widget
chmod +x build.sh install.sh
./install.sh
```

Or build only:

```bash
./build.sh
open .build/CodeUsageWidget.app
```

`install.sh` copies the app to `~/Applications`, creates `~/.config/code-usage-widget/config.json` from the example, and registers a LaunchAgent for login auto-start.

## Configuration

Config lives at `~/.config/code-usage-widget/config.json`. See `config.example.json` for the full schema.

```json
{
  "poll_interval_seconds": 30,
  "browser": "chrome",
  "firefox_profile": "auto",
  "providers": {
    "deepseek": { "api_key_env": "DEEPSEEK_API_KEY", "budget_usd": 50 },
    "openai": { "session_key": "", "budget_usd": 50 },
    "sarvam": { "api_key_env": "SARVAM_API_KEY", "credits_remaining_inr": 75 },
    "opencode": { "api_key_env": "OPENCODE_API_KEY" },
    "commandcode": { "session_token": "" }
  }
}
```

| Key | Description |
|-----|-------------|
| `poll_interval_seconds` | How often to refresh (minimum 10) |
| `browser` | `auto`, `firefox`, or `chrome` for cookie-based auth |
| `firefox_profile` | `"auto"` or full path to a Firefox profile |
| `api_key` | Inline API key (useful for LaunchAgent, which doesn't inherit shell env) |
| `api_key_env` | Environment variable name for the API key |
| `budget_usd` | Progress bar ceiling for providers without a quota API |

## Provider Setup

| Provider | Setup |
|----------|-------|
| **Cursor** | Auto-detected from local Cursor install — no config needed |
| **CommandCode** | Paste `session_token` in config (see below) or log in via Firefox |
| **DeepSeek** | Set `DEEPSEEK_API_KEY` or inline `api_key` + optional `budget_usd` |
| **OpenAI** | `session_key` from platform.openai.com Network tab, chunked cookies, or manual `balance_usd` |
| **Sarvam AI** | `api_key` + optional `credits_remaining_inr` from [indus.sarvam.ai](https://indus.sarvam.ai) billing |
| **OpenCode** | `api_key` + `session_token` from opencode.ai (see DevTools while logged in) |

### CommandCode with Google Chrome

Chrome encrypts cookies so the widget cannot read them automatically. After logging in at [commandcode.ai](https://commandcode.ai):

1. Open Chrome DevTools (`Cmd+Option+I`)
2. Go to **Application** → **Cookies** → `https://commandcode.ai`
3. Copy the value of `__Secure-commandcode_prod_.session_token`
4. Paste it in config under `providers.commandcode.session_token`
5. Click ↻ or press **⌘R** to refresh

Alternatively, log into CommandCode in **Firefox** and set `"browser": "firefox"` — no manual token needed.

### OpenAI

Project-scoped API keys (`sk-proj-...`) cannot read billing. Use one of these instead:

#### Option A — session key (recommended)

1. Log into [platform.openai.com](https://platform.openai.com) and open **Billing**
2. Open DevTools → **Network**, filter for `api.openai.com`
3. Click a request like `credit_grants` and copy the **Authorization** bearer value — it starts with `sess-`
4. Add to config:

```json
"openai": {
  "session_key": "sess-..."
}
```

This token expires every few days; copy a fresh one when the widget stops updating.

#### Option B — chunked login cookies

NextAuth splits large cookies into two parts. Copy **both** separately from `https://chatgpt.com` cookies:

- `__Secure-next-auth.session-token.0`
- `__Secure-next-auth.session-token.1`

```json
"openai": {
  "session_token_0": "paste .0 value",
  "session_token_1": "paste .1 value"
}
```

Do **not** combine them into one string.

#### Option C — manual balance

If API auth is unavailable, set the balance you see on the billing page:

```json
"openai": {
  "balance_usd": 4.50,
  "budget_usd": 5
}
```

### Sarvam AI

Sarvam billing is at [indus.sarvam.ai](https://indus.sarvam.ai). If the API doesn't expose credits, set `credits_remaining_inr` manually in config (same pattern as OpenAI Option C).

### OpenCode

Set your API key and paste the `auth` session cookie from opencode.ai DevTools while logged in.

## Auto-start

Right-click the widget and enable **Launch at Login**. macOS may show a one-time permission prompt — allow it, and the alerts should stop.

The old install method used a LaunchAgent plist, which caused repeated **“App Background Activity”** notifications. Re-run `./install.sh` or launch the updated app once to remove it automatically.

To disable auto-start: right-click → **Launch at Login** (uncheck), or go to **System Settings → General → Login Items & Extensions → Allow in Background** and turn off **AI Usage Widget**.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.anakin.code-usage-widget 2>/dev/null
rm -f ~/Library/LaunchAgents/com.anakin.code-usage-widget.plist
rm -rf ~/Applications/CodeUsageWidget.app
```

## Build

No Xcode project required — a single `swiftc` invocation compiles everything:

```bash
./build.sh
```

Output: `.build/CodeUsageWidget.app`

## Versioning

Version format: **`app.feature.patch`** (e.g. `0.1.0`)

| Part | When to bump |
|------|----------------|
| **app** | Major rewrites or breaking config/API changes |
| **feature** | New providers, UI features, or notable capabilities |
| **patch** | Bug fixes and small improvements |

The canonical version lives in [`VERSION`](VERSION). `build.sh` injects it into the app bundle. Git tags use a `v` prefix (`v0.1.0`).

## Notes

These are unofficial integrations. Provider APIs may change without notice.

DeepSeek shows remaining balance against a configurable budget ceiling (not a monthly plan limit).

## License

MIT
