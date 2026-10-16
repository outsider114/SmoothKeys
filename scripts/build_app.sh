#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="SmoothKeys"
BUILD_DIR="$ROOT/.build/$CONFIG"
APP_DIR="$ROOT/outputs/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

cd "$ROOT"
swift "$ROOT/scripts/generate_icons.swift"
iconutil -c icns "$ROOT/Resources/SmoothKeys.iconset" -o "$ROOT/Resources/SmoothKeys.icns"
swift build -c "$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BUILD_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/SmoothKeys.icns" "$CONTENTS/Resources/SmoothKeys.icns"
cp "$ROOT/Resources/Mos-LICENSE.txt" "$CONTENTS/Resources/Mos-LICENSE.txt"
cp "$ROOT/LICENSE" "$CONTENTS/Resources/LICENSE"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"

/usr/bin/plutil -replace CFBundleExecutable -string "$APP_NAME" "$CONTENTS/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$(date +%Y%m%d%H%M)" "$CONTENTS/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  SIGN_IDENTITY="${SMOOTHKEYS_SIGN_IDENTITY:-}"
  if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
  fi

  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
    echo "Signed with: $SIGN_IDENTITY"
  else
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
    echo "Warning: no stable signing identity found; using ad-hoc signing."
  fi
fi

echo "$APP_DIR"
