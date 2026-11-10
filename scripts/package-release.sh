#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export APP_VERSION="${1:-0.1.4}"
bash scripts/build-app.sh
APP_PATH="$PROJECT_ROOT/dist/MyRagAI.app"
ARCH="$(uname -m)"
case "$ARCH" in
    arm64) LABEL="AppleSilicon" ;;
    x86_64) LABEL="Intel" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/MyRagAI" -verify_arch "$ARCH"
ARCHIVE="MyRagAI-${APP_VERSION}-macOS-${LABEL}.zip"
mkdir -p dist/releases
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "dist/releases/$ARCHIVE"
(cd dist/releases && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
echo "Release archive: dist/releases/$ARCHIVE"
