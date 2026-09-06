#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT/macos/Nightwire"
DEST="${1:-$HOME/Desktop/Nightwire.app}"

cd "$APP_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

echo "Generating Xcode project..."
xcodegen generate

echo "Building Nightwire.app..."
xcodebuild \
  -scheme Nightwire \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES

APP_SRC="$APP_DIR/build/Build/Products/Release/Nightwire.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "Build succeeded but app bundle was not found at $APP_SRC" >&2
  exit 1
fi

echo "Installing $DEST"
rm -rf "$DEST"
rm -rf "$HOME/Desktop/PingSlut.app"
mkdir -p "$(dirname "$DEST")"
cp -R "$APP_SRC" "$DEST"

echo "Build complete: $DEST"
