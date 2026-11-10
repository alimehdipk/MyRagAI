#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
./scripts/build-app.sh
PREVIEW_PATH="$PROJECT_ROOT/dist/MyRagAI Preview.app"
mkdir -p "$PREVIEW_PATH/Contents/MacOS" "$PREVIEW_PATH/Contents/Resources"
cp dist/MyRagAI.app/Contents/MacOS/MyRagAI "$PREVIEW_PATH/Contents/MacOS/MyRagAI"
cp dist/MyRagAI.app/Contents/Resources/AppIcon.png "$PREVIEW_PATH/Contents/Resources/AppIcon.png"
cp dist/MyRagAI.app/Contents/Resources/AppIcon.icns "$PREVIEW_PATH/Contents/Resources/AppIcon.icns"
cp dist/MyRagAI.app/Contents/Info.plist "$PREVIEW_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.myragai.documentation-preview' "$PREVIEW_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName MyRagAI Preview' "$PREVIEW_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :MyRagAIScreenshotMode bool true' "$PREVIEW_PATH/Contents/Info.plist"
codesign --force --sign - "$PREVIEW_PATH"
printf '\nPreview app: %s\n' "$PREVIEW_PATH"
