#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/outputs/SmoothKeys.app}"
[[ -d "$APP" ]] || { echo "Build SmoothKeys.app first with scripts/build_app.sh" >&2; exit 1; }
APP="$(cd "$APP" && pwd)"
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/SmoothKeys" | tr ' ' '-')
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid app version" >&2; exit 1; }
DEST="$ROOT/outputs/releases/v$VERSION"
mkdir -p "$DEST"
WORK=$(mktemp -d "$DEST/.dmg-XXXXXX")
MOUNT="$WORK/mount"
cleanup() {
  if mount | grep -Fq " on $MOUNT ("; then
    hdiutil detach "$MOUNT" >/dev/null || return
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/content" "$MOUNT"
ditto --norsrc --noextattr --noacl "$APP" "$WORK/content/SmoothKeys.app"
codesign --force --deep --options runtime --sign - --timestamp=none "$WORK/content/SmoothKeys.app"
codesign --verify --deep --strict "$WORK/content/SmoothKeys.app"
if LC_ALL=C grep -aRq '/Users/' "$WORK/content/SmoothKeys.app"; then
  echo "App contains local build paths; rebuild with scripts/build_app.sh" >&2
  exit 1
fi
ln -s /Applications "$WORK/content/Applications"

hdiutil create -quiet -volname SmoothKeys -srcfolder "$WORK/content" -fs HFS+ -format UDRW "$WORK/layout.dmg"
hdiutil attach -quiet -nobrowse -readwrite -mountpoint "$MOUNT" "$WORK/layout.dmg"

osascript - "$MOUNT" <<'APPLESCRIPT'
on run arguments
    tell application "Finder"
        set installerFolder to POSIX file (item 1 of arguments) as alias
        set installerDisk to disk of installerFolder
        tell installerDisk
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 180, 780, 540}
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 96
            set text size of viewOptions to 13
            set position of item "SmoothKeys.app" of container window to {145, 150}
            set position of item "Applications" of container window to {435, 150}
            close container window
        end tell
        update installerDisk without registering applications
    end tell
    delay 2
end run
APPLESCRIPT

hdiutil detach -quiet "$MOUNT"
NAME="SmoothKeys-$VERSION-macOS-$ARCH.dmg"
hdiutil convert -quiet "$WORK/layout.dmg" -format UDZO -o "$WORK/$NAME"
hdiutil verify "$WORK/$NAME"
mv -f "$WORK/$NAME" "$DEST/$NAME"
(cd "$DEST" && shasum -a 256 "$NAME" > SHA256SUMS)
echo "$DEST/$NAME"
