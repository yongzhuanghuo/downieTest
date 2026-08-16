#!/usr/bin/env bash
#
# 下载 yt-dlp 和 ffmpeg 的发布用二进制，放到 assets/bin/{macos,windows}/
#
# 用法:
#   ./scripts/download-binaries.sh
#   GH_PROXY=https://ghproxy.com/ ./scripts/download-binaries.sh   # GitHub 走加速代理
#
# 说明:
#   - macOS: 官方独立二进制 yt-dlp_macos + evermeet.cx 静态版 ffmpeg
#   - Windows: yt-dlp.exe + gyan.dev 的 ffmpeg.exe
#   - 这些文件较大，已被 .gitignore 忽略，只在本地/CI 管理，不进 git
#   - 不能用 brew 的 yt-dlp/ffmpeg 代替：brew 的 yt-dlp 是 Python 脚本、ffmpeg 依赖动态库，
#     用户机器上没有这些依赖，发布必须用官方独立/静态二进制。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_DIR="$ROOT/assets/bin/macos"
WINDOWS_DIR="$ROOT/assets/bin/windows"

# GitHub 加速代理前缀（可选）。国内直连慢/失败时，设成镜像地址，如 https://ghproxy.com/
GH_PROXY="${GH_PROXY:-}"

YTDLP_MACOS_URL="${GH_PROXY}https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
YTDLP_WINDOWS_URL="${GH_PROXY}https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
FFMPEG_MACOS_URL="https://evermeet.cx/ffmpeg/getrelease/zip"
FFMPEG_WINDOWS_URL="https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

mkdir -p "$MACOS_DIR" "$WINDOWS_DIR"

download() {
  local url="$1" out="$2"
  echo "⬇️  下载 $out"
  # --http1.1 避免 GFW 干扰 HTTP/2 导致的 PROTOCOL_ERROR；--retry-all-errors 让它遇到协议错误也重试
  curl -fL --http1.1 --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 -o "$out" "$url"
}

# 从 zip 里提取指定文件名的二进制（zip 内部常带版本号目录）
extract_bin() {
  local zip="$1" name="$2" dest="$3"
  local tmp_dir found
  tmp_dir="$(mktemp -d)"
  unzip -q -o "$zip" -d "$tmp_dir"
  found="$(find "$tmp_dir" -name "$name" -type f | head -1)"
  if [ -z "$found" ]; then
    echo "❌ 在 $zip 里没找到 $name"
    rm -rf "$tmp_dir"
    return 1
  fi
  cp "$found" "$dest"
  rm -rf "$tmp_dir"
  echo "✅ $dest"
}

echo "=== 1/4 yt-dlp (macOS) ==="
download "$YTDLP_MACOS_URL" "$MACOS_DIR/yt-dlp"
chmod +x "$MACOS_DIR/yt-dlp"

echo "=== 2/4 yt-dlp (Windows) ==="
download "$YTDLP_WINDOWS_URL" "$WINDOWS_DIR/yt-dlp.exe"

echo "=== 3/4 ffmpeg (macOS 静态版) ==="
ffmpeg_macos_zip="$(mktemp -d)/ffmpeg.zip"
download "$FFMPEG_MACOS_URL" "$ffmpeg_macos_zip"
extract_bin "$ffmpeg_macos_zip" "ffmpeg" "$MACOS_DIR/ffmpeg"
chmod +x "$MACOS_DIR/ffmpeg"

echo "=== 4/4 ffmpeg (Windows) ==="
ffmpeg_win_zip="$(mktemp -d)/ffmpeg_win.zip"
download "$FFMPEG_WINDOWS_URL" "$ffmpeg_win_zip"
extract_bin "$ffmpeg_win_zip" "ffmpeg.exe" "$WINDOWS_DIR/ffmpeg.exe"

echo ""
echo "✅ 全部完成："
ls -lh "$MACOS_DIR" "$WINDOWS_DIR"
echo ""
echo "验证版本："
"$MACOS_DIR/yt-dlp" --version
"$MACOS_DIR/ffmpeg" -version 2>/dev/null | head -1
