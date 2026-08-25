"""资源限制：并发上限 / 上传大小 / 磁盘清理。

media 模块是 CPU/磁盘重服务，公网前必须有这些约束，否则是开放下载代理。
"""
import asyncio
import os
from pathlib import Path

from .config import DOWNLOAD_DIR, MAX_UPLOAD_SIZE, TEMP_DIR


def concurrency_limit() -> int:
    """并发媒体任务上限。默认按 CPU 核数（至少 1），可用 MEDIA_CONCURRENCY 覆盖。"""
    n = int(os.getenv("MEDIA_CONCURRENCY", 0))
    if n > 0:
        return n
    return max(1, (os.cpu_count() or 2) // 2)


# 全局信号量：media 路由里 asyncio.to_thread 之前 acquire
MEDIA_SEMAPHORE = asyncio.Semaphore(concurrency_limit())


class UploadTooLarge(Exception):
    pass


async def stream_to_file(upload, dest: Path, max_size: int = MAX_UPLOAD_SIZE) -> Path:
    """流式写文件，边读边累加计数，超限抛 UploadTooLarge（转 413）。"""
    written = 0
    with open(dest, "wb") as f:
        while chunk := await upload.read(1024 * 1024):
            written += len(chunk)
            if written > max_size:
                f.close()
                dest.unlink(missing_ok=True)
                raise UploadTooLarge()
            f.write(chunk)
    return dest


async def cleanup_expired(max_age_hours: int = 24) -> int:
    """清理 downloads/ tmp 里超过 max_age_hours 的文件。返回删除数量。

    用 asyncio.to_thread 执行同步文件遍历，避免阻塞事件循环。
    """
    def _clean() -> int:
        import time

        now = time.time()
        removed = 0
        for d in (DOWNLOAD_DIR, TEMP_DIR):
            if not d.exists():
                continue
            for p in d.rglob("*"):
                try:
                    if p.is_file() and now - p.stat().st_mtime > max_age_hours * 3600:
                        p.unlink()
                        removed += 1
                except OSError:
                    continue
        return removed

    return await asyncio.to_thread(_clean)
