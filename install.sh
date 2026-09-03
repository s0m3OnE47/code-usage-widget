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

echo "Removing legacy LaunchAgent (if any)..."
launchctl bootout "gui/$(id -u)/com.anakin.code-usage-widget" 2>/dev/null || true
rm -f "$LAUNCH_AGENT"

echo ""
echo "Installed!"
echo "Launch now: open \"$INSTALL_DIR/$APP_NAME\""
echo "Enable auto-start: right-click widget → Launch at Login"
