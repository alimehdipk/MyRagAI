#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP_VERSION="${APP_VERSION:-0.1.4}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "APP_VERSION must be a numeric version such as 0.1.4" >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
swift build -c release --disable-sandbox --scratch-path "$PROJECT_ROOT/.build" --cache-path "$PROJECT_ROOT/.build/cache"
BINARY_PATH="$(swift build -c release --disable-sandbox --scratch-path "$PROJECT_ROOT/.build" --cache-path "$PROJECT_ROOT/.build/cache" --show-bin-path)"
APP_PATH="$PROJECT_ROOT/dist/MyRagAI.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_PATH/MyRagAI" "$APP_PATH/Contents/MacOS/MyRagAI"
cp "$PROJECT_ROOT/Assets/AppIcon.png" "$APP_PATH/Contents/Resources/AppIcon.png"
ICONSET_PATH="$PROJECT_ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET_PATH"
for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" "$PROJECT_ROOT/Assets/AppIcon.png" --out "$ICONSET_PATH/icon_${icon_size}x${icon_size}.png" >/dev/null
    retina_size=$((icon_size * 2))
    sips -z "$retina_size" "$retina_size" "$PROJECT_ROOT/Assets/AppIcon.png" --out "$ICONSET_PATH/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
python3 "$PROJECT_ROOT/scripts/make-icns.py" "$ICONSET_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"
cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MyRagAI</string>
<key>CFBundleDisplayName</key><string>MyRagAI</string>
<key>CFBundleIdentifier</key><string>com.myragai.desktop</string>
<key>CFBundleExecutable</key><string>MyRagAI</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# Preserve SwiftPM resources for Bundle.module in installed builds.
for resource_bundle in "$BINARY_PATH"/*.bundle; do
    if [[ -d "$resource_bundle" ]]; then
        ditto "$resource_bundle" "$APP_PATH/Contents/Resources/$(basename "$resource_bundle")"
    fi
done
codesign --force --sign - "$APP_PATH"
printf '\nBuilt: %s\nOpen with: open "%s"\n' "$APP_PATH" "$APP_PATH"
