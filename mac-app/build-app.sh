#!/bin/zsh
set -euo pipefail

APP_DIR="${0:A:h}"
REPO_DIR="${APP_DIR:h}"
OUTPUT_DIR="$APP_DIR/dist/Oversight Island.app"
BUILD_DIR="$APP_DIR/.build"
mkdir -p "$BUILD_DIR/clang-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"

if [[ ! -d "$REPO_DIR/node_modules" ]]; then
  echo "Installing Node dependencies…"
  (cd "$REPO_DIR" && npm ci)
fi

echo "Building macOS app…"
(cd "$APP_DIR" && swift build --disable-sandbox --scratch-path "$BUILD_DIR" -c release)

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/Contents/MacOS" "$OUTPUT_DIR/Contents/Resources/bridge"
cp "$BUILD_DIR/release/OversightIsland" "$OUTPUT_DIR/Contents/MacOS/OversightIsland"
cp -R "$REPO_DIR/src" "$OUTPUT_DIR/Contents/Resources/bridge/src"
cp -R "$REPO_DIR/node_modules" "$OUTPUT_DIR/Contents/Resources/bridge/node_modules"
cp "$REPO_DIR/package.json" "$OUTPUT_DIR/Contents/Resources/bridge/package.json"

cat > "$OUTPUT_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.oversight.island</string>
  <key>CFBundleName</key><string>Oversight Island</string>
  <key>CFBundleExecutable</key><string>OversightIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$OUTPUT_DIR"

echo "Built: $OUTPUT_DIR"
