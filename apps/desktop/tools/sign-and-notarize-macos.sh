#!/usr/bin/env bash
# 给 4KDownle.app 做 Developer ID 签名 + 公证（可选，发布正式包时用）。
#
# 用法：
#   DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="4kdownle-notary" \
#   tools/sign-and-notarize-macos.sh <4KDownle.app> [Downie6.dmg]
#
# 如果不用 keychain profile，也可以提供：
#   APPLE_ID / APPLE_TEAM_ID / APP_SPECIFIC_PASSWORD
set -euo pipefail

APP_PATH="${1:-}"
DMG_PATH="${2:-}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "usage: $0 <4KDownle.app> [Downie6.dmg]" >&2
  exit 2
fi
if [[ -z "$IDENTITY" ]]; then
  echo "error: DEVELOPER_ID_APPLICATION is required" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT_DIR/macos/Runner/Release.entitlements"

sign() {
  /usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
}

echo "Signing embedded binaries..."
BIN_DIR="$APP_PATH/Contents/Resources/flutter_assets/assets/bin/macos"
for name in ffmpeg yt-dlp yt-dlp_arm64 yt-dlp_x86_64 node node_arm64 node_x86_64; do
  file="$BIN_DIR/$name"
  if [[ -f "$file" ]]; then
    sign "$file"
  fi
done

echo "Signing frameworks..."
find "$APP_PATH/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" -print0 |
  while IFS= read -r -d '' framework; do
    name="$(basename "$framework" .framework)"
    bin="$framework/Versions/A/$name"
    [[ -f "$bin" ]] || bin="$framework/$name"
    if [[ -f "$bin" ]]; then
      sign "$bin"
    fi
    sign "$framework"
  done

echo "Signing nested dylibs..."
find "$APP_PATH/Contents" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 |
  while IFS= read -r -d '' lib; do
    sign "$lib"
  done

echo "Signing app..."
/usr/bin/codesign --force --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" "$APP_PATH"

echo "Verifying signature..."
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/spctl --assess --type execute --verbose=4 "$APP_PATH" || true

if [[ -n "$DMG_PATH" ]]; then
  if [[ ! -f "$DMG_PATH" ]]; then
    echo "error: DMG not found: $DMG_PATH" >&2
    exit 1
  fi
  echo "Signing DMG..."
  sign "$DMG_PATH"
  hdiutil verify "$DMG_PATH"

  echo "Submitting DMG for notarization..."
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APP_SPECIFIC_PASSWORD" \
      --wait
  else
    echo "warning: no notary credentials; DMG signed but not notarized" >&2
    exit 0
  fi

  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  echo "Notarized and stapled: $DMG_PATH"
fi

echo "Done."
