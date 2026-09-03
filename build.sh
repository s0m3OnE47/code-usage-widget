#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BIN="$ROOT/.build/CodeUsageWidget"
APP="$ROOT/.build/CodeUsageWidget.app"
CONTENTS="$APP/Contents"

echo "Building Code Usage Widget..."
mkdir -p "$ROOT/.build"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be app.feature.patch (e.g. 0.1.0), got: $VERSION" >&2
  exit 1
fi

swiftc -sdk "$SDK" \
  -target arm64-apple-macos26.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework Foundation \
  -framework ServiceManagement \
  -framework WidgetKit \
  -O \
  -o "$BIN" \
  "$ROOT/Sources/Shared/UsageSnapshot.swift" \
  "$ROOT/Sources/Shared/UsageCache.swift" \
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
  "$ROOT/Sources/UI/WindowPositioning.swift" \
  "$ROOT/Sources/UI/WidgetView.swift" \
  "$ROOT/Sources/App.swift"

echo "Packaging .app bundle..."
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/CodeUsageWidget"
cp "$ROOT/config.example.json" "$CONTENTS/Resources/config.example.json"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CodeUsageWidget</string>
  <key>CFBundleDisplayName</key><string>AI Usage Widget</string>
  <key>CFBundleIdentifier</key><string>com.anakin.code-usage-widget</string>
  <key>CFBundleExecutable</key><string>CodeUsageWidget</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS/PkgInfo"

echo "Building WidgetKit extension (Xcode app-extension target)..."
EXT_NAME="CodeUsageWidgetExtension"
APPEX="$CONTENTS/PlugIns/${EXT_NAME}.appex"
DERIVED="$ROOT/.build/DerivedData"
XCODE_DEV="/Applications/Xcode.app/Contents/Developer"

if [[ ! -d "$XCODE_DEV" ]]; then
  echo "Full Xcode.app is required to build the WidgetKit extension (swiftc-wrapped appex is rejected by chronod)." >&2
  exit 1
fi
export DEVELOPER_DIR="$XCODE_DEV"

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$ROOT/WidgetExtension" && xcodegen generate)
fi

xcodebuild \
  -project "$ROOT/WidgetExtension/CodeUsageWidgetExtension.xcodeproj" \
  -scheme "$EXT_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM="" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  ONLY_ACTIVE_ARCH=YES \
  build

BUILT_APPEX="$DERIVED/Build/Products/Release/${EXT_NAME}.appex"
if [[ ! -d "$BUILT_APPEX" ]]; then
  echo "Widget extension build missing at $BUILT_APPEX" >&2
  exit 1
fi

rm -rf "$CONTENTS/PlugIns" "$CONTENTS/Extensions"
mkdir -p "$CONTENTS/PlugIns"
cp -R "$BUILT_APPEX" "$APPEX"

echo "Signing with entitlements..."
codesign --force --sign - --identifier com.anakin.code-usage-widget.widget \
  --entitlements "$ROOT/WidgetExtension/CodeUsageWidgetExtension.entitlements" \
  "$APPEX"
codesign --force --sign - --identifier com.anakin.code-usage-widget \
  --entitlements "$ROOT/CodeUsageWidget.entitlements" \
  "$APP"

echo "Done. Launch with: open \"$APP\""
echo "Add desktop widget: right-click desktop → Edit Widgets → AI Usage"
