#!/usr/bin/env python3
"""构建带 YouTube SABR 支持的 yt-dlp 独立二进制。

背景：yt-dlp 正式版尚不支持 YouTube SABR（issue #12482，PR #13515 未合并），
而 Downie 4.12.7+ 自己实现了 SABR，所以同一个视频 Downie 能下 1080p、
正式版 yt-dlp 只能拿到 360p 或直接报 bot check。

用法（CI 里由 GitHub Actions 调用）：
    python tools/build_sabr_ytdlp.py --output assets/bin/macos/yt-dlp_arm64

    # 本地已有源码/依赖时，跳过下载和 pip install：
    python tools/build_sabr_ytdlp.py \
      --source-dir /tmp/yt-dlp-sabr --no-install \
      --python /tmp/yt-build/bin/python \
      --output /tmp/yt-dlp-sabr

说明：
- 固定 commit，避免分支漂移；升级时改 SABR_SHA 并回归测试。
- PyInstaller 打包的 yt-dlp 按上游声明是 GPLv3+；项目原本就分发 yt-dlp
  官方二进制，这里不改变许可证类别，但分发时仍应保留 THIRD_PARTY_LICENSES。
- 该脚本只负责构建，不修改仓库里的其他文件。
"""
from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

SABR_REPO = "coletdjnz/yt-dlp-dev"
SABR_SHA = "b7685f01f1c9b61c9b1293bf86ac4400d3748f0f"
TARBALL_URL = f"https://codeload.github.com/{SABR_REPO}/tar.gz/{SABR_SHA}"


def _download(url: str, target: Path, retries: int = 3) -> None:
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            print(f"[sabr] 下载 {url}（第 {attempt} 次）", flush=True)
            with urllib.request.urlopen(url, timeout=120) as response:
                target.write_bytes(response.read())
            if target.stat().st_size < 1024:
                raise RuntimeError(f"下载内容过小：{target.stat().st_size} 字节")
            return
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            print(f"[sabr] 下载失败：{exc}", flush=True)
    raise RuntimeError(f"下载失败：{url}") from last_error


def _extract(tarball: Path, dest: Path) -> Path:
    with tarfile.open(tarball, "r:gz") as archive:
        try:
            archive.extractall(dest, filter="data")
        except TypeError:
            archive.extractall(dest)
    roots = [p for p in dest.iterdir() if p.is_dir()]
    if len(roots) != 1:
        raise RuntimeError(f"压缩包目录结构异常：{[p.name for p in roots]}")
    return roots[0]


def _pip_install(python: str, source_dir: Path) -> None:
    print("[sabr] 安装 PyInstaller / protobug / yt-dlp 源码", flush=True)
    subprocess.run(
        [python, "-m", "pip", "install", "--quiet", "--upgrade", "pip"],
        check=True,
    )
    subprocess.run(
        [
            python,
            "-m",
            "pip",
            "install",
            "--quiet",
            "pyinstaller>=6.0",
            "protobug>=1.0.0",
            str(source_dir),
        ],
        check=True,
    )


def _build(python: str, source_dir: Path) -> Path:
    print("[sabr] 运行 PyInstaller", flush=True)
    subprocess.run(
        [python, "-m", "bundle.pyinstaller", "--onefile"],
        cwd=source_dir,
        check=True,
    )
    dist = source_dir / "dist"
    candidates = [
        p for p in dist.iterdir()
        if p.is_file() and p.name.startswith("yt-dlp") and p.suffix != ".spec"
    ]
    if not candidates:
        raise RuntimeError(f"PyInstaller 未生成 yt-dlp：{dist}")
    # 多架构/多后缀时取最大的可执行文件
    return max(candidates, key=lambda p: p.stat().st_size)


def _default_output() -> Path:
    ext = ".exe" if platform.system() == "Windows" else ""
    return Path("assets") / "bin" / (
        "windows" if platform.system() == "Windows" else "macos"
    ) / f"yt-dlp{ext}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=_default_output())
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--source-dir", type=Path, default=None,
                        help="已下载的 SABR 源码目录；省略则按固定 commit 下载")
    parser.add_argument("--no-install", action="store_true",
                        help="跳过 pip install（依赖已就绪时）")
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args()

    workdir: tempfile.TemporaryDirectory[str] | None = None
    try:
        if args.source_dir:
            source_dir = args.source_dir.resolve()
        else:
            workdir = tempfile.TemporaryDirectory(prefix="yt-sabr-")
            root = Path(workdir.name)
            tarball = root / "sabr.tar.gz"
            _download(TARBALL_URL, tarball)
            source_dir = _extract(tarball, root)

        if not args.no_install:
            _pip_install(args.python, source_dir)

        built = _build(args.python, source_dir)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(built, args.output)
        if platform.system() != "Windows":
            os.chmod(args.output, 0o755)
        print(f"[sabr] 输出：{args.output} ({args.output.stat().st_size} bytes)")
        print(f"[sabr] commit：{SABR_SHA}")
        return 0
    finally:
        if workdir is not None and not args.keep_workdir:
            workdir.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
