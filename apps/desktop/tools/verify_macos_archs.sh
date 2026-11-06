#!/usr/bin/env bash
# 校验 macOS Release 包是否同时支持 Intel (x86_64) 和 Apple Silicon (arm64)。
# 用法：tools/verify_macos_archs.sh build/macos/Build/Products/Release/4KDownle.app
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "usage: $0 <path-to-.app>" >&2
  exit 2
fi

fail=0

check() {
  local label="$1"
  local path="$2"
  local want="$3" # both | arm64 | x86_64
  if [[ ! -f "$path" ]]; then
    echo "FAIL $label: missing $path" >&2
    fail=1
    return
  fi
  local archs
  archs="$(lipo -archs "$path" 2>/dev/null || true)"
  if [[ -z "$archs" ]]; then
    echo "FAIL $label: not a Mach-O binary ($path)" >&2
    fail=1
    return
  fi
  if [[ "$want" == "both" ]]; then
    for a in arm64 x86_64; do
      if [[ " $archs " != *" $a "* ]]; then
        echo "FAIL $label: missing $a (got: $archs)" >&2
        fail=1
        return
      fi
    done
  elif [[ " $archs " != *" $want "* ]]; then
    echo "FAIL $label: missing $want (got: $archs)" >&2
    fail=1
    return
  fi
  echo "OK   $label: $archs"
}

EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")"
check "main executable" "$APP/Contents/MacOS/$EXECUTABLE" both

# 所有内嵌 framework（FlutterMacOS / App / 插件）都必须是双架构
for fw in "$APP"/Contents/Frameworks/*.framework; do
  [[ -d "$fw" ]] || continue
  name="$(basename "$fw" .framework)"
  bin="$fw/Versions/A/$name"
  [[ -f "$bin" ]] || bin="$fw/$name"
  [[ -f "$bin" ]] && check "framework:$name" "$bin" both
done

ASSETS="$APP/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/assets/bin/macos"
check "ffmpeg" "$ASSETS/ffmpeg" both
check "yt-dlp (universal fallback)" "$ASSETS/yt-dlp" both
check "yt-dlp_arm64" "$ASSETS/yt-dlp_arm64" arm64
check "yt-dlp_x86_64" "$ASSETS/yt-dlp_x86_64" x86_64
check "node_arm64" "$ASSETS/node_arm64" arm64
check "node_x86_64" "$ASSETS/node_x86_64" x86_64

if [[ "$fail" -ne 0 ]]; then
  echo "macOS universal check FAILED" >&2
  exit 1
fi
echo "macOS universal check OK"
