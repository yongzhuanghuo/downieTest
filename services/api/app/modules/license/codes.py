"""激活码工具（数据库随机码方案）。

与 Node 版 `src/license.js` 完全等价：
- 32 字符字母表（去掉易混字符 0/1/O/I）
- 默认 20 位，约 100 bit 熵；256 % 32 == 0 所以 `b % 32` 无取模偏差
- 规范化：去分隔符 + 统一大写
- 格式化：XXXXX-XXXXX-XXXXX-XXXXX（仅展示/导出用）
"""
import re
import secrets

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def generate_code(length: int = 20) -> str:
    bytes_ = secrets.token_bytes(length)
    return "".join(ALPHABET[b % len(ALPHABET)] for b in bytes_)


def normalize_code(code: str | None) -> str:
    return re.sub(r"[^A-Z0-9]", "", (code or "").upper())


def format_code(raw: str) -> str:
    return "-".join(raw[i : i + 5] for i in range(0, len(raw), 5))
