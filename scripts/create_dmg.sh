#!/bin/bash
set -e

# DJView Standalone DMG Creator Script
# Compiles Rust djvu-bridge static library, builds Swift DJView executable, packages DJView.app, and creates DJView.dmg installer.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DJView"
APP_BUNDLE="$PROJECT_DIR/DJView.app"
DMG_NAME="DJView.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
STAGING_DIR="$PROJECT_DIR/target/dmg_staging"

echo "=== 1. Building Executable and App Bundle ==="
"$PROJECT_DIR/scripts/build.sh"

echo "=== 2. Preparing Standalone DMG Staging Directory ==="
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

# Copy DJView.app bundle to staging
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# Create symlink to /Applications for standard macOS drag-and-drop installation
ln -s /Applications "$STAGING_DIR/Applications"

echo "=== 3. Generating Standalone macOS $DMG_NAME ==="
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING_DIR" \
               -ov -format UDZO \
               "$DMG_PATH"

echo "=== Standalone DMG Successfully Created! ==="
echo "DMG Path: $DMG_PATH"
