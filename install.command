#!/bin/bash
set -euo pipefail

# Require only Xcode Command Line Tools — full Xcode is NOT needed.
# Install them with: xcode-select --install
if ! command -v swift >/dev/null 2>&1; then
  echo "Error: 'swift' not found."
  echo "Install Xcode Command Line Tools (no full Xcode needed):"
  echo "  xcode-select --install"
  exit 1
fi

# Ensure the active developer directory is set (CLT or Xcode either works).
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Error: No active developer directory found."
  echo "Run: xcode-select --install"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="OpenZeus"
DERIVED="$ROOT/.build"
BINARY="$DERIVED/release/$APP_NAME"
ICON_PNG="$ROOT/Sources/OpenZeus/Resources/icon.png"
ICONSET_DIR="$DERIVED/AppIcon.iconset"
ICON_ICNS="$DERIVED/AppIcon.icns"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/$APP_NAME.app"

create_icns_from_png() {
  if [ ! -f "$ICON_PNG" ]; then
    echo "No icon source found at $ICON_PNG. Skipping icon conversion."
    return 0
  fi

  if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "Warning: sips/iconutil not available. Skipping icon conversion."
    return 0
  fi

  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  echo "Generating AppIcon.icns from icon.png..."
  sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
}

build_app_bundle() {
  local bundle="$1"
  local binary="$2"
  local macos_dir="$bundle/Contents/MacOS"
  local resources_dir="$bundle/Contents/Resources"

  rm -rf "$bundle"
  mkdir -p "$macos_dir" "$resources_dir"

  cp "$binary" "$macos_dir/$APP_NAME"
  chmod +x "$macos_dir/$APP_NAME"

  cat > "$bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.zeus.$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>Open Zeus</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  if [ -f "$ICON_ICNS" ]; then
    cp "$ICON_ICNS" "$resources_dir/AppIcon.icns"
  fi
}

create_icns_from_png

echo "Building $APP_NAME (Release)..."
swift build -c release

if [ ! -f "$BINARY" ]; then
  echo "Error: Build succeeded but binary not found at: $BINARY"
  exit 1
fi

echo "Creating app bundle..."
mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
build_app_bundle "$DEST_APP" "$BINARY"

echo "Installing to ${DEST_APP}..."
echo "Done."
open "$DEST_APP"
