#!/usr/bin/env python3
"""用真实样本链接跑 yt-dlp，验证站点是否真的能解析。

用法：
  python3 apps/desktop/tools/verify_site_samples.py \
    --samples docs/data/site-samples.csv \
    --out docs/site-verification.csv

samples CSV 至少包含 site,url 两列；可选 note。
这是开发/回归工具，不进入 CI（避免网络波动导致构建失败）。
"""
from __future__ import annotations

import argparse
import csv
import subprocess
import time
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
COVERAGE = ROOT / "docs/site-coverage.csv"


def load_coverage() -> dict[str, dict[str, str]]:
    with COVERAGE.open(encoding="utf-8", newline="") as f:
        return {row["site"]: row for row in csv.DictReader(f)}


def run_one(
    ytdlp: Path,
    url: str,
    timeout: int,
    proxy: str,
    cookie: str,
) -> tuple[bool, str, str]:
    args = [
        str(ytdlp),
        "--simulate",
        "--no-download",
        "--no-playlist",
        "--no-warnings",
        "--socket-timeout",
        str(min(15, timeout)),
        "--retries",
        "1",
        "--print",
        "%(extractor)s\t%(title)s\t%(duration)s",
    ]
    if proxy:
        args += ["--proxy", proxy]
    if cookie:
        args += ["--cookies", cookie]
    args.append(url)
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, "", f"timeout {timeout}s"
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "").strip().splitlines()
        return False, "", (message[-1] if message else f"exit {result.returncode}")
    line = (result.stdout or "").strip().splitlines()
    return True, (line[-1] if line else "ok"), ""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", required=True)
    parser.add_argument("--out", default="docs/site-verification.csv")
    parser.add_argument(
        "--ytdlp",
        default=str(ROOT / "apps/desktop/assets/bin/macos/yt-dlp"),
    )
    parser.add_argument("--proxy", default="")
    parser.add_argument("--cookie", default="")
    parser.add_argument("--timeout", type=int, default=45)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--only-status", default="")
    args = parser.parse_args()

    ytdlp = Path(args.ytdlp)
    if not ytdlp.exists():
        raise SystemExit(f"yt-dlp not found: {ytdlp}")
    coverage = load_coverage()
    with Path(args.samples).open(encoding="utf-8", newline="") as f:
        samples = list(csv.DictReader(f))
    if args.limit > 0:
        samples = samples[: args.limit]

    out_rows: list[dict[str, str]] = []
    ok_count = 0
    for index, sample in enumerate(samples, 1):
        site = (sample.get("site") or "").strip()
        url = (sample.get("url") or "").strip()
        if not url:
            continue
        status = coverage.get(site, {}).get("status", "")
        if args.only_status and status != args.only_status:
            continue
        started = time.monotonic()
        ok, detail, error = run_one(
            ytdlp,
            url,
            args.timeout,
            args.proxy,
            args.cookie,
        )
        elapsed = round(time.monotonic() - started, 1)
        if ok:
            ok_count += 1
        out_rows.append(
            {
                "site": site,
                "coverage_status": status,
                "ok": "yes" if ok else "no",
                "detail": detail,
                "error": error,
                "seconds": str(elapsed),
                "url": url,
                "verified_at": date.today().isoformat(),
            }
        )
        print(
            f"[{index}/{len(samples)}] {site or '?'}: "
            f"{'OK' if ok else 'FAIL'} ({elapsed}s) {detail or error[:120]}"
        )

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "site",
                "coverage_status",
                "ok",
                "detail",
                "error",
                "seconds",
                "url",
                "verified_at",
            ],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(out_rows)
    print(f"wrote {out} · {ok_count}/{len(out_rows)} passed")


if __name__ == "__main__":
    main()
