# AI Code Usage Widget

Desktop widget for **Cursor**, **CommandCode**, **DeepSeek**, **OpenAI**, **Sarvam AI**, and **OpenCode** usage. Place it next to Clock and Stocks. A background host keeps the numbers fresh — it does not appear in the Dock.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-WidgetKit-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Add the desktop widget

1. Install and open the app once (gauge icon in the menu bar).
2. Enable **Launch at Login** from that menu so usage keeps updating after reboot.
3. Right-click an empty area of the **desktop**.
4. Choose **Edit Widgets**.
5. Search for **AI Usage**.
6. Pick a size (**Small**, **Medium**, or **Large**) and drag it onto the desktop.

macOS snaps it to the same grid as Clock, Stocks, and other system widgets. Drag it like any other desktop widget.

If **AI Usage** is missing from the gallery, open the app once, then:

```bash
pluginkit -a ~/Applications/CodeUsageWidget.app/Contents/PlugIns/CodeUsageWidgetExtension.appex
killall chronod NotificationCenter 2>/dev/null || true
```

## Widget-only (hide the app)

The host never shows in the Dock. You can hide the menu bar icon too and keep only the desktop widget:

1. Add the **AI Usage** widget (steps above).
2. Menu bar gauge → **Launch at Login** (on).
3. Menu bar gauge → **Hide Menu Bar Icon**.

The background process keeps fetching every 30 seconds. Nothing else is visible except the widget.

**Bring the menu bar back:** click the desktop widget, or open **AI Usage Widget** from Spotlight / `~/Applications`.

## Install from source

Requires **full Xcode** (not only Command Line Tools) to build the WidgetKit extension.

```bash
git clone https://github.com/s0m3OnE47/code-usage-widget.git
cd code-usage-widget
chmod +x build.sh install.sh
./install.sh
```

`install.sh` copies the app to `~/Applications`, creates `~/.config/code-usage-widget/config.json`, and registers the widget extension.

Release zip: [Releases](https://github.com/s0m3OnE47/code-usage-widget/releases).

## How it works

| Piece | What you see | What it does |
|-------|----------------|--------------|
| **Desktop widget** | AI Usage on the desktop | Displays cached usage (Small / Medium / Large) |
| **Host app** | Optional menu bar icon, never Dock | Reads cookies/tokens, polls APIs, writes the snapshot |

The widget cannot read Chrome cookies or Cursor’s local DB. The host must stay running (**Launch at Login**).

Menu bar (when visible): Refresh · Launch at Login · Show Floating Panel · Hide Menu Bar Icon · Open Config · Quit.

## Configuration

`~/.config/code-usage-widget/config.json` — see `config.example.json`.

```json
{
  "poll_interval_seconds": 30,
  "browser": "chrome",
  "firefox_profile": "auto",
  "providers": {
    "deepseek": { "api_key_env": "DEEPSEEK_API_KEY", "budget_usd": 50 },
    "openai": { "session_key": "", "budget_usd": 5 },
    "sarvam": { "api_key_env": "SARVAM_API_KEY", "credits_remaining_inr": 75 },
    "opencode": { "api_key_env": "OPENCODE_API_KEY" },
    "commandcode": { "session_token": "" }
  }
}
```

| Key | Description |
|-----|-------------|
| `poll_interval_seconds` | Host refresh interval (minimum 10) |
| `browser` | `auto`, `firefox`, or `chrome` |
| `firefox_profile` | `"auto"` or a full profile path |
| `api_key` | Inline key (Launch at Login does not inherit shell env) |
| `budget_usd` | Progress ceiling when a provider has no quota API |

## Provider setup

| Provider | Setup |
|----------|-------|
| **Cursor** | Auto from the local Cursor install |
| **CommandCode** | Chrome: paste `session_token` (below). Firefox: log in and set `"browser": "firefox"` |
| **DeepSeek** | `api_key` or `DEEPSEEK_API_KEY` |
| **OpenAI** | `session_key` (`sess-…` from platform.openai.com Network), or `session_token_0` + `_1`, or `balance_usd` |
| **Sarvam AI** | `api_key` plus optional `credits_remaining_inr` from [indus.sarvam.ai](https://indus.sarvam.ai) |
| **OpenCode** | `api_key` plus `session_token` from opencode.ai DevTools |

### CommandCode (Chrome)

Chrome cookies cannot be decrypted automatically.

1. Log in at [commandcode.ai](https://commandcode.ai)
2. DevTools → **Application** → **Cookies** → `https://commandcode.ai`
3. Copy `__Secure-commandcode_prod_.session_token`
4. Paste into `providers.commandcode.session_token`

### OpenAI

Project keys (`sk-proj-…`) cannot read billing.

**A — session key:** platform.openai.com → Billing → Network → `credit_grants` → `Authorization: Bearer sess-…`

```json
"openai": { "session_key": "sess-..." }
```

**B — cookies:** from chatgpt.com copy `.0` and `.1` separately (do not merge):

```json
"openai": {
  "session_token_0": "paste .0 value",
  "session_token_1": "paste .1 value"
}
```

**C — manual:** `"balance_usd": 4.50, "budget_usd": 5`

## Uninstall

```bash
rm -rf ~/Applications/CodeUsageWidget.app
```

Turn off **Launch at Login** first if you enabled it (menu bar, or System Settings → General → Login Items).

## Build

```bash
./build.sh
```

Host is compiled with `swiftc`. The WidgetKit extension is an Xcode app-extension target (`WidgetExtension/`). Optional: `brew install xcodegen` to regenerate that project from `project.yml`.

## Versioning

**`app.feature.patch`** (current: see [`VERSION`](VERSION)). Tags use a `v` prefix (`v0.2.0`).

| Part | When to bump |
|------|----------------|
| **app** | Breaking config or major rewrite |
| **feature** | New providers or capabilities |
| **patch** | Fixes |

## Notes

Unofficial integrations. Provider APIs can change without notice.

## License

MIT
