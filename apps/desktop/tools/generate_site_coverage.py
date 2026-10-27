#!/usr/bin/env python3
"""生成 Downie 站点覆盖矩阵（文档 + 应用内 JSON）。

输入（已入库，不依赖 ~/re）：
  docs/data/downie-site-matrix.csv   REA 从 DownieCore 提取的 786 个下载器
  docs/data/yt-dlp-extractors.txt    当前内置 yt-dlp 的提取器名

输出：
  docs/site-coverage.csv             全量机器可读表
  docs/site-coverage.md              按状态分组的全量 Markdown 表
  apps/desktop/assets/site_coverage.json   偏好设置 → 支持站点

状态定义：
  native          我们自己的原生插件（已实现）
  native_partial  原生插件部分支持（如 B 站番剧单集）
  ytdlp           由 yt-dlp 负责（功能可用，但代码不是 Downie 原生复刻）
  generic         仅能用通用 HTML/WebView 资源检测尝试（未逐站验证）
  drm             DRM 内容，Downie 自身也拒绝下载
"""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MATRIX = ROOT / "docs/data/downie-site-matrix.csv"
EXTRACTORS = ROOT / "docs/data/yt-dlp-extractors.txt"
OUT_CSV = ROOT / "docs/site-coverage.csv"
OUT_MD = ROOT / "docs/site-coverage.md"
OUT_JSON = ROOT / "apps/desktop/assets/site_coverage.json"
VERIFICATION = ROOT / "docs/site-verification.csv"

NATIVE = {
    "DouyinDownloader",
    "IesdouyinDownloader",
    "BilibiliDownloader",
    "BilibiliEmbedDownloader",
    "TikTokDownloader",
    "KuaishouDownloader",
    "WeiboDownloader",
    "WeiboHTML5Downloader",
    "BilibiliBangumiDownloader",
}
NATIVE_PARTIAL: set[str] = set()

# Downie 类名与 yt-dlp 提取器名不同、但确认由 yt-dlp 覆盖的站点。
EXTRACTOR_ALIASES = {
    "OdyseeDownloader": "lbry",
}
VERIFIED_NATIVE = {
    "DouyinDownloader",
    "IesdouyinDownloader",
    "BilibiliDownloader",
}

# CSV 里只标了 Disney/Apple；这些服务即使被 yt-dlp 识别，正片仍是 DRM。
DRM_PREFIXES = (
    "disney",
    "watchdisney",
    "netflix",
    "primevideo",
    "amazonprimevideo",
    "hulu",
    "hbomax",
    "peacock",
    "paramountplus",
    "appletv",
)
DRM_EXACT = {"apple", "max"}

CLASS_SUFFIXES = (
    "downloader",
    "base",
    "new",
    "live",
    "clip",
    "clips",
    "embed",
    "embedded",
    "configuration",
    "audio",
    "music",
    "movie",
    "bangumi",
    "international",
    "cool",
    "html5",
    "show",
    "shows",
    "sports",
    "coop",
    "alt",
    "video",
    "videos",
)

STATUS_ORDER = ["native", "native_partial", "ytdlp", "generic", "drm"]
STATUS_LABEL = {
    "native": "原生插件",
    "native_partial": "原生插件（部分）",
    "ytdlp": "yt-dlp（待验证）",
    "generic": "通用资源检测（未复刻）",
    "drm": "DRM（不支持）",
}


def norm(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (value or "").lower())


def load_verification() -> tuple[set[str], list[dict[str, str]]]:
    if not VERIFICATION.exists():
        return set(), []
    with VERIFICATION.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    passed = {
        r.get("site", "")
        for r in rows
        if r.get("ok") == "yes" and r.get("site")
    }
    return passed, rows


def load_extractors() -> list[str]:
    return [
        line.strip()
        for line in EXTRACTORS.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("CURRENTLY BROKEN")
    ]


def strip_suffix(value: str) -> str:
    value = norm(value)
    for suffix in CLASS_SUFFIXES:
        if len(value) > len(suffix) and value.endswith(suffix):
            value = value[: -len(suffix)]
    return value


def extractor_matches(row: dict[str, str], extractors: list[str]) -> list[str]:
    """严格匹配：只认归一化后的完全相等，避免 BBC→Bandcamp 这类子串误报。"""
    by_name: dict[str, list[str]] = {}
    for full in extractors:
        base = full.split(":")[0]
        key = norm(base)
        if len(key) >= 3:
            by_name.setdefault(key, []).append(full)

    tokens: set[str] = set()
    for value in (row.get("site", ""), row.get("class", "")):
        if not value:
            continue
        raw = norm(value)
        if len(raw) >= 3:
            tokens.add(raw)
        stripped = strip_suffix(value)
        if len(stripped) >= 3:
            tokens.add(stripped)


    candidates: list[str] = []
    for token in tokens:
        candidates.extend(by_name.get(token, []))
    return sorted(set(candidates))[:8]


def is_drm(row: dict[str, str]) -> bool:
    if row.get("drm") == "yes":
        return True
    site = norm(row.get("site", ""))
    cls = strip_suffix(row.get("class", ""))
    for value in (site, cls):
        if value in DRM_EXACT or value.startswith(DRM_PREFIXES):
            return True
    return False


def classify(
    row: dict[str, str],
    extractors: list[str],
    verified_sites: set[str],
) -> dict[str, object]:
    cls = row.get("class", "")
    site = row.get("site", "")
    matches = extractor_matches(row, extractors)
    alias = EXTRACTOR_ALIASES.get(cls)
    if alias:
        alias_base = norm(alias)
        matches = sorted({
            full
            for full in extractors
            if norm(full.split(":")[0]) == alias_base
        })

    if cls in NATIVE:
        status = "native"
    elif cls in NATIVE_PARTIAL:
        status = "native_partial"
    elif is_drm(row):
        status = "drm"
    elif row.get("ytdlp") == "yes" or alias:
        status = "ytdlp"
    else:
        status = "generic"

    notes = (row.get("notes") or "").strip()
    sample_verified = site in verified_sites
    if sample_verified:
        notes = (notes + "；2026-10-27 样本解析通过" if notes else "2026-10-27 样本解析通过")
    if status == "drm" and "drm" not in notes.lower():
        notes = (notes + "；DRM 正片不支持" if notes else "DRM 正片不支持")
    if status == "generic":
        notes = (
            notes
            + "；未原生复刻，需通用资源检测/自定义集成验证"
            if notes
            else "未原生复刻，需通用资源检测/自定义集成验证"
        )

    return {
        "site": site,
        "className": cls,
        "domains": [
            d.strip()
            for d in (row.get("domains") or "").split(";")
            if d.strip()
        ],
        "status": status,
        "statusLabel": STATUS_LABEL[status],
        "verified": (status == "native" and cls in VERIFIED_NATIVE)
        or sample_verified,
        "priority": row.get("priority") or "P1",
        "ytdlpExtractors": matches,
        "notes": notes,
    }


def md_escape(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def md_table(rows: list[dict[str, object]], include_method: bool = True) -> str:
    if include_method:
        head = "| 站点 | Downie 类 | 域名 | 状态 | 已验证 | 优先级 | 备注 |\n|---|---|---|---|---|---|---|\n"
    else:
        head = "| 站点 | Downie 类 | 状态 | 备注 |\n|---|---|---|---|\n"
    out = [head]
    for r in rows:
        domains = ", ".join(r["domains"][:3]) if r["domains"] else ""
        if include_method:
            out.append(
                "| {site} | {cls} | {domains} | {status} | {verified} | {priority} | {notes} |\n".format(
                    site=md_escape(r["site"]),
                    cls=md_escape(r["className"]),
                    domains=md_escape(domains),
                    status=md_escape(r["statusLabel"]),
                    verified="是" if r["verified"] else "否",
                    priority=md_escape(r["priority"]),
                    notes=md_escape(r["notes"]),
                )
            )
        else:
            out.append(
                "| {site} | {cls} | {status} | {notes} |\n".format(
                    site=md_escape(r["site"]),
                    cls=md_escape(r["className"]),
                    status=md_escape(r["statusLabel"]),
                    notes=md_escape(r["notes"]),
                )
            )
    return "".join(out)


def main() -> None:
    with MATRIX.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    extractors = load_extractors()
    verified_sites, verification_rows = load_verification()
    coverage = [classify(r, extractors, verified_sites) for r in rows]
    coverage.sort(
        key=lambda r: (
            STATUS_ORDER.index(r["status"]),
            r["priority"],
            r["site"].lower(),
        )
    )

    # CSV：全量机器可读
    fields = [
        "site",
        "className",
        "domains",
        "status",
        "statusLabel",
        "verified",
        "priority",
        "ytdlpExtractors",
        "notes",
    ]
    with OUT_CSV.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for r in coverage:
            writer.writerow(
                {
                    **r,
                    "domains": ";".join(r["domains"]),
                    "ytdlpExtractors": ";".join(r["ytdlpExtractors"]),
                    "verified": "yes" if r["verified"] else "no",
                }
            )

    # JSON：应用内站点列表
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(
        json.dumps(
            {
                "generatedFrom": "Downie 4 v4.13.3 + yt-dlp 2026.07.04",
                "total": len(coverage),
                "counts": {
                    s: sum(1 for r in coverage if r["status"] == s)
                    for s in STATUS_ORDER
                },
                "sites": coverage,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )

    # Markdown：摘要 + 按状态分组的全量表
    counts = {s: sum(1 for r in coverage if r["status"] == s) for s in STATUS_ORDER}
    status_by_site = {r["site"]: r["statusLabel"] for r in coverage}
    top = [r for r in coverage if r["priority"] == "P0"]
    lines = [
        "# Downie 4 站点覆盖矩阵\n\n",
        f"- 基线：Downie 4 v4.13.3；yt-dlp 2026.07.04（{len(extractors)} 个提取器）\n",
        f"- 总数：{len(coverage)} 个 Downie 下载器/站点变体\n",
        "- 生成：`python3 apps/desktop/tools/generate_site_coverage.py`\n\n",
        "## 统计\n\n",
        "| 状态 | 数量 | 含义 |\n|---|---:|---|\n",
        f"| 原生插件 | {counts['native']} | 我们自己的解析/下载实现 |\n",
        f"| 原生插件（部分） | {counts['native_partial']} | 原生实现只覆盖部分链接形态 |\n",
        f"| yt-dlp | {counts['ytdlp']} | 功能可用（由 yt-dlp 负责），但不是 Downie 代码复刻；仍需逐站验证 |\n",
        f"| 通用资源检测（未复刻） | {counts['generic']} | 没有原生/已知提取器，只能靠通用 HTML/WebView 嗅探；未逐站验证 |\n",
        f"| DRM（不支持） | {counts['drm']} | Downie 自身也拒绝的 DRM 正片 |\n\n",
        "> 重要：`yt-dlp` 不等于“原生复刻”。本表把“能下载”和“代码复刻”分开标注，避免把 yt-dlp 覆盖误报成已完成站点。\n\n",
        "## 最近样本验证\n\n",
        "来源：`docs/site-verification.csv`（`tools/verify_site_samples.py` 生成）。"
        "失败不等于站点不支持，需区分样本失效、地区限制、登录/风控和引擎缺陷。\n\n",
        "| 站点 | 覆盖状态 | 结果 | 详情/错误 | 耗时 |\n|---|---|---|---|---:|\n",
        *[
            "| {site} | {status} | {ok} | {detail} | {secs}s |\n".format(
                site=md_escape(r.get("site", "")),
                status=md_escape(
                    r.get("coverage_status")
                    or status_by_site.get(r.get("site", ""), "")
                ),
                ok="通过" if r.get("ok") == "yes" else "失败",
                detail=md_escape(
                    (r.get("detail") or r.get("error") or "").replace("|", "/")[:180]
                ),
                secs=md_escape(r.get("seconds", "")),
            )
            for r in verification_rows
        ],
        "> 说明：Douyin 行的失败是 **yt-dlp 直跑**需要 cookie，不代表原生插件；"
        "TikTok 2.0.19 已改为原生插件，下一次样本验证会更新。"
        "X 的样本被冻结、YouTube 样本私有、Twitch VOD 已删除，属于样本失效。\n\n",
        "\n## P0 站点（35 个）\n\n",
        md_table(top),
        "\n## 已原生复刻\n\n",
        md_table([r for r in coverage if r["status"] == "native"]),
        *(
            [
                "\n## 原生部分支持\n\n",
                md_table([r for r in coverage if r["status"] == "native_partial"]),
            ]
            if counts["native_partial"]
            else []
        ),
        "\n## yt-dlp 功能覆盖（代码未复刻，待逐站验证）\n\n",
        md_table([r for r in coverage if r["status"] == "ytdlp"]),
        "\n## 通用资源检测/未复刻（需逐站验证）\n\n",
        md_table([r for r in coverage if r["status"] == "generic"]),
        "\n## DRM（不支持）\n\n",
        md_table([r for r in coverage if r["status"] == "drm"]),
        "\n## 说明\n\n",
        "- 786 个类是 Downie 的下载器/变体数量，不完全等于 786 个独立站点；其中有基类、直播/音频/番剧等变体。\n",
        "- `yt-dlp` 覆盖来自 Downie 矩阵的启发式标注 + 当前 yt-dlp 提取器名/域名匹配，实际能否下载必须以样本链接测试为准。\n",
        "- 通用资源检测是兜底，不是逐站复刻；失败率需要按站点记录后再决定是否写原生插件。\n",
    ]
    OUT_MD.write_text("".join(lines), encoding="utf-8")

    print(
        f"wrote {OUT_CSV.relative_to(ROOT)} ({len(coverage)} rows), "
        f"{OUT_MD.relative_to(ROOT)}, {OUT_JSON.relative_to(ROOT)}"
    )
    print("counts:", counts)


if __name__ == "__main__":
    main()
