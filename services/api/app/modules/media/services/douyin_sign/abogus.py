"""a_bogus 生成封装：node 子进程执行 abogus.js（抖音 web 签名算法）。

算法源自开源 douyin_sign（utils.js + sm3.js + vm_decode.js），
node 执行 JS 生成 a_bogus（对应抖音版本 V 1.0.1.19-fix.01）。
"""
import logging
import subprocess
from pathlib import Path

logger = logging.getLogger("app.douyin.abogus")

_DIR = Path(__file__).parent


def generate(uri: str) -> str:
    """生成 a_bogus。uri 为 query 字符串（含 device_platform/aid/aweme_id/msToken 等）。"""
    try:
        result = subprocess.run(
            ["node", str(_DIR / "abogus.js"), uri],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("a_bogus 生成超时")

    if result.returncode != 0:
        raise RuntimeError(f"a_bogus 生成失败: {result.stderr.strip()[:200]}")

    ab = result.stdout.strip()
    if not ab:
        raise RuntimeError("a_bogus 生成结果为空")
    return ab
