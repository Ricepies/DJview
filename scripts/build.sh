#!/usr/bin/env bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "=== 1. Building Rust djvu-bridge Static Library ==="
cd "$PROJECT_ROOT/djvu-bridge"
cargo build --release

echo "=== 2. Building Swift DJView Executable ==="
cd "$PROJECT_ROOT/DJView"
swift build -c release

GIT_TAG="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-${GIT_TAG:-0.1.0}}"
BUILD_NUM="${BUILD_NUM:-$(git rev-list --count HEAD 2>/dev/null || echo "1")}"

echo "=== 3. Packaging macOS Deja.app Bundle (v${VERSION} build ${BUILD_NUM}) ==="
APP_BUNDLE="$PROJECT_ROOT/Deja.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$PROJECT_ROOT/DJView/.build/release/Deja" "$MACOS_DIR/Deja"
chmod +x "$MACOS_DIR/Deja"

if [ -f "$PROJECT_ROOT/ccc.icns" ]; then
    cp "$PROJECT_ROOT/ccc.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "$PROJECT_ROOT/aaa.icns" ]; then
    cp "$PROJECT_ROOT/aaa.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Deja</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>org.deja.Deja</string>
    <key>CFBundleName</key>
    <string>Deja</string>
    <key>CFBundleDisplayName</key>
    <string>Deja Reader</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>DjVu Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.lizardtech.djvu</string>
                <string>org.djvutoy.djvu</string>
                <string>public.djvu</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>djvu</string>
                <string>djv</string>
            </array>
            <key>CFBundleTypeMIMETypes</key>
            <array>
                <string>image/vnd.djvu</string>
                <string>image/x-djvu</string>
            </array>
            <key>CFBundleTypeIconFile</key>
            <string>AppIcon</string>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.lizardtech.djvu</string>
            <key>UTTypeDescription</key>
            <string>DjVu Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.content</string>
                <string>public.composite-content</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>djvu</string>
                    <string>djv</string>
                </array>
                <key>public.mime-type</key>
                <array>
                    <string>image/vnd.djvu</string>
                    <string>image/x-djvu</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "=== 4. Registering Deja.app with macOS LaunchServices ==="
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP_BUNDLE" || true

echo "=== Deja.app Successfully Built! ==="
echo "Path: $APP_BUNDLE"
