#!/bin/bash
set -e

# DJView Standalone DMG Creator Script
# Compiles Rust djvu-bridge static library, builds Swift DJView executable, packages DJView.app, and creates DJView.dmg installer.

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="DJView"
APP_BUNDLE="$PROJECT_DIR/DJView.app"
GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-${GIT_TAG:-0.1.0}}"
DMG_NAME="DJView.dmg"
VERSIONED_DMG_NAME="DJView-v${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
VERSIONED_DMG_PATH="$PROJECT_DIR/$VERSIONED_DMG_NAME"
STAGING_DIR="$PROJECT_DIR/target/dmg_staging"

echo "=== 1. Building Executable and App Bundle ==="
"$PROJECT_DIR/scripts/build.sh"

echo "=== 2. Preparing Standalone DMG Staging Directory ==="
rm -rf "$STAGING_DIR" "$DMG_PATH" "$VERSIONED_DMG_PATH"
mkdir -p "$STAGING_DIR"

# Copy DJView.app bundle to staging
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# Create symlink to /Applications for standard macOS drag-and-drop installation
ln -s /Applications "$STAGING_DIR/Applications"

echo "=== 3. Generating Standalone macOS $DMG_NAME (v${VERSION}) ==="
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING_DIR" \
               -ov -format UDZO \
               "$DMG_PATH"

cp "$DMG_PATH" "$VERSIONED_DMG_PATH"

echo "=== Standalone DMG Successfully Created! ==="
echo "Primary DMG Path: $DMG_PATH"
echo "Versioned DMG Path: $VERSIONED_DMG_PATH"
