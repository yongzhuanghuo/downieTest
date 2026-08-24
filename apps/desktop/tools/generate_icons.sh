#!/usr/bin/env bash
# 从源 logo（正方形图片，可能是 jpeg 却叫 .png）生成：
#   - assets/logo.png                     侧边栏图标（256x256）
#   - macos/Runner/.../AppIcon.appiconset 各尺寸 PNG
#   - windows/runner/resources/app_icon.ico
# 用法：bash tools/generate_icons.sh [源图片路径]（默认 logo.png）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC="${1:-logo.png}"
APPDIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"
ASSET="assets/logo.png"
ICO="windows/runner/resources/app_icon.ico"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 0. 源图可能实际是 JPEG 却叫 .png，先统一转成真正的 PNG
PNG_SRC="$TMP/src.png"
sips -s format png "$SRC" --out "$PNG_SRC" >/dev/null

# 1. 侧边栏图标（256x256）
sips -s format png -z 256 256 "$PNG_SRC" --out "$ASSET" >/dev/null
echo "✅ $ASSET"

# 2. macOS 图标（各尺寸）
for size in 16 32 64 128 256 512 1024; do
  sips -s format png -z "$size" "$size" "$PNG_SRC" --out "$APPDIR/app_icon_${size}.png" >/dev/null
done
echo "✅ macOS AppIcon.appiconset（16~1024）"

# 3. Windows ico（16/32/48/64/128/256，PNG 打包）
for size in 16 32 48 64 128 256; do
  sips -s format png -z "$size" "$size" "$PNG_SRC" --out "$TMP/icon_${size}.png" >/dev/null
done
python3 - "$TMP" "$ICO" <<'PY'
import sys, os, struct
tmp, ico = sys.argv[1], sys.argv[2]
sizes = [16, 32, 48, 64, 128, 256]
images = []
for s in sizes:
    with open(os.path.join(tmp, f"icon_{s}.png"), "rb") as f:
        images.append((s, f.read()))
count = len(images)
header = struct.pack("<HHH", 0, 1, count)
offset = 6 + 16 * count
entries, blob = b"", b""
for s, data in images:
    b = 0 if s >= 256 else s
    entries += struct.pack("<BBBBHHII", b, b, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
    blob += data
with open(ico, "wb") as f:
    f.write(header + entries + blob)
print(f"✅ {ico}（{count} 个尺寸）")
PY

echo "✅ 图标全部生成完毕"
