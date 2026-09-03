#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CodeUsageWidget.app"
INSTALL_DIR="$HOME/Applications"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.anakin.code-usage-widget.plist"
CONFIG_DIR="$HOME/.config/code-usage-widget"

echo "Building..."
"$ROOT/build.sh"

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$ROOT/.build/$APP_NAME" "$INSTALL_DIR/$APP_NAME"

echo "Setting up config..."
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config.json" ]; then
  cp "$ROOT/config.example.json" "$CONFIG_DIR/config.json"
  echo "Created $CONFIG_DIR/config.json"
fi

echo "Registering LaunchAgent..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$LAUNCH_AGENT" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.anakin.code-usage-widget</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/$APP_NAME/Contents/MacOS/CodeUsageWidget</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/com.anakin.code-usage-widget" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"

echo ""
echo "Installed! The widget will auto-start on login."
echo "Launch now: open \"$INSTALL_DIR/$APP_NAME\""
