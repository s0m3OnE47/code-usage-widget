#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CodeUsageWidget.app"
INSTALL_DIR="$HOME/Applications"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.anakin.code-usage-widget.plist"
CONFIG_DIR="$HOME/.config/code-usage-widget"
WIDGET_ID="com.anakin.code-usage-widget.widget"
APPEX="$INSTALL_DIR/$APP_NAME/Contents/PlugIns/CodeUsageWidgetExtension.appex"

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

echo "Registering WidgetKit extension..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME" || true
if [ -d "$APPEX" ]; then
  pluginkit -a "$APPEX" || true
  pluginkit -e use -p com.apple.widgetkit-extension -i "$WIDGET_ID" || true
else
  echo "Warning: widget extension missing at $APPEX" >&2
fi

echo ""
echo "Installed!"
echo "Launch now: open \"$INSTALL_DIR/$APP_NAME\""
echo "Menu bar icon → Launch at Login"
echo "Add desktop widget: right-click desktop → Edit Widgets → AI Usage"
