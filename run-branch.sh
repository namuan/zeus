#!/bin/bash
# run-branch.sh — build and launch an isolated OpenZeus instance for the
# current git branch, with its own config and database in Application Support.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR"

# --- Prerequisite checks ---
if ! command -v swift >/dev/null 2>&1; then
  echo "Error: 'swift' not found. Install Xcode Command Line Tools:" >&2
  echo "  xcode-select --install" >&2
  exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Error: No active developer directory. Run: xcode-select --install" >&2
  exit 1
fi
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $ROOT is not inside a git repository." >&2
  exit 1
fi

# --- Derive branch name ---
RAW_BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
if [ "$RAW_BRANCH" = "HEAD" ]; then
  SHORT_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
  SANITIZED_BRANCH="detached-${SHORT_SHA}"
else
  SANITIZED_BRANCH="$(printf '%s' "$RAW_BRANCH" | tr '/:\ ()[]<>|&;*?~\\\"' '-')"
  SANITIZED_BRANCH="$(printf '%s' "$SANITIZED_BRANCH" | sed 's/--*/-/g; s/^-//; s/-$//')"
fi

APP_DIR_NAME="OpenZeus-${SANITIZED_BRANCH}"
BUNDLE_ID="com.zeus.OpenZeus.${SANITIZED_BRANCH}"

# --- Paths ---
APP_SUPPORT="$HOME/Library/Application Support"
BRANCH_DIR="${APP_SUPPORT}/${APP_DIR_NAME}"
CONFIG_FILE="${BRANCH_DIR}/config.json"
RUN_BRANCH_BUILD_ROOT="$ROOT/.run-branch-build"
SCRATCH_DIR="${RUN_BRANCH_BUILD_ROOT}/${APP_DIR_NAME}-scratch"
BINARY_SRC="${SCRATCH_DIR}/debug/OpenZeus"
BUNDLE="${RUN_BRANCH_BUILD_ROOT}/${APP_DIR_NAME}.app"

echo "Branch  : $RAW_BRANCH"
echo "App dir : $APP_DIR_NAME"
echo "Bundle  : $BUNDLE"
echo ""

# --- Create isolated config (once) ---
mkdir -p "$BRANCH_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Creating isolated config at: $CONFIG_FILE"
  cat > "$CONFIG_FILE" <<CONFIG_JSON
{
  "storage": {
    "appSupportFolderName": "${APP_DIR_NAME}",
    "databaseFileName": "app.db"
  },
  "terminal": {
    "tmuxSessionPrefix": "zeus-${SANITIZED_BRANCH}-"
  }
}
CONFIG_JSON
fi

# --- Build ---
echo "Building OpenZeus (debug, fresh scratch build)..."
cd "$ROOT"
rm -rf "$SCRATCH_DIR"
mkdir -p "$RUN_BRANCH_BUILD_ROOT"
swift build --scratch-path "$SCRATCH_DIR"

if [ ! -f "$BINARY_SRC" ]; then
  echo "Error: binary not found at: $BINARY_SRC" >&2
  exit 1
fi

# --- Create app bundle ---
# Rebuild the bundle each run so the binary is always up to date.
echo "Creating app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

cp "$BINARY_SRC" "$BUNDLE/Contents/MacOS/OpenZeus"
chmod +x "$BUNDLE/Contents/MacOS/OpenZeus"

# Copy icon if available
ICON_ICNS="${SCRATCH_DIR}/AppIcon.icns"
if [ -f "$ICON_ICNS" ]; then
  cp "$ICON_ICNS" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

# LSEnvironment injects ZEUS_APP_DIR into the process without needing a
# shell wrapper — the only macOS-native way to pass env vars to .app bundles.
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>OpenZeus</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>OpenZeus</string>
  <key>CFBundleDisplayName</key>
  <string>Open Zeus [${RAW_BRANCH}]</string>
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
  <key>LSEnvironment</key>
  <dict>
    <key>ZEUS_APP_DIR</key>
    <string>${APP_DIR_NAME}</string>
  </dict>
</dict>
</plist>
PLIST

# --- Launch ---
echo "Launching isolated instance..."
open "$BUNDLE"

echo ""
echo "Started OpenZeus (branch: ${RAW_BRANCH})"
echo "  Config  : $CONFIG_FILE"
echo "  Database: ${BRANCH_DIR}/app.db"
echo "  Bundle  : $BUNDLE"
echo ""
echo "To find the PID:  pgrep -n OpenZeus"
echo "To stop:          pkill -n OpenZeus"
