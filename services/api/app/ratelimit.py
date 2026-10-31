"""进程内速率限制。

单进程部署（uvicorn 单 worker）够用；多 worker 时各进程独立计数，
只能作为第一道防线，真正的全局限流应在 Nginx / Redis 层做。

用法：
    limiter = InMemoryRateLimiter()
    if not limiter.allow(f"login:{ip}", limit=10, window_seconds=600):
        ...
"""
from __future__ import annotations

import time
from typing import Dict, List

from fastapi import Request


class InMemoryRateLimiter:
    def __init__(self) -> None:
        self._hits: Dict[str, List[float]] = {}

    def allow(self, key: str, *, limit: int, window_seconds: float) -> bool:
        """记录一次请求；超过窗口内限额返回 False。"""
        now = time.time()
        recent = [t for t in self._hits.get(key, []) if now - t < window_seconds]
        if len(recent) >= limit:
            self._hits[key] = recent
            return False
        recent.append(now)
        self._hits[key] = recent
        # 防止被大量随机 key 撑爆内存
        if len(self._hits) > 5000:
            self._hits = {
                k: ts for k, ts in self._hits.items() if any(now - t < window_seconds for t in ts)
            }
        return True

    def reset(self, key: str) -> None:
        self._hits.pop(key, None)


def client_ip(request: Request) -> str:
    """优先取反代写入的 X-Forwarded-For 第一个地址。"""
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        return forwarded.split(",")[0].strip() or "unknown"
    return request.client.host if request.client else "unknown"
