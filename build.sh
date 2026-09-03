#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BIN="$ROOT/.build/CodeUsageWidget"
APP="$ROOT/.build/CodeUsageWidget.app"
CONTENTS="$APP/Contents"

echo "Building Code Usage Widget..."
mkdir -p "$ROOT/.build"

swiftc -sdk "$SDK" \
  -target arm64-apple-macos26.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework Foundation \
  -framework ServiceManagement \
  -O \
  -o "$BIN" \
  "$ROOT/Sources/Models/UsageModels.swift" \
  "$ROOT/Sources/Services/ConfigLoader.swift" \
  "$ROOT/Sources/Services/UsageAggregator.swift" \
  "$ROOT/Sources/Auth/CursorTokenReader.swift" \
  "$ROOT/Sources/Auth/BrowserCookieReader.swift" \
  "$ROOT/Sources/Fetchers/HTTPClient.swift" \
  "$ROOT/Sources/Fetchers/CursorFetcher.swift" \
  "$ROOT/Sources/Fetchers/DeepSeekFetcher.swift" \
  "$ROOT/Sources/Fetchers/OpenAIFetcher.swift" \
  "$ROOT/Sources/Fetchers/CommandCodeFetcher.swift" \
  "$ROOT/Sources/Fetchers/SarvamFetcher.swift" \
  "$ROOT/Sources/Fetchers/OpenCodeFetcher.swift" \
  "$ROOT/Sources/UI/AnimatedProgressBar.swift" \
  "$ROOT/Sources/UI/ProviderIconView.swift" \
  "$ROOT/Sources/UI/ProviderRowView.swift" \
  "$ROOT/Sources/UI/WidgetLayout.swift" \
  "$ROOT/Sources/UI/WidgetView.swift" \
  "$ROOT/Sources/UI/WindowDragHandle.swift" \
  "$ROOT/Sources/App.swift"

echo "Packaging .app bundle..."
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/CodeUsageWidget"
cp "$ROOT/config.example.json" "$CONTENTS/Resources/config.example.json"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CodeUsageWidget</string>
  <key>CFBundleDisplayName</key><string>AI Usage Widget</string>
  <key>CFBundleIdentifier</key><string>com.anakin.code-usage-widget</string>
  <key>CFBundleExecutable</key><string>CodeUsageWidget</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS/PkgInfo"

echo "Done. Launch with: open \"$APP\""
