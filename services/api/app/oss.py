"""阿里云 OSS 后端中转转存。

上传链路：前端 → 后端（multipart）→ 后端处理（ffmpeg 需本地文件）→ 转存 OSS → 返回直链。
未配置 OSS（.env 缺 OSS_*）时 `is_enabled()` 返回 False，调用方降级返回本地相对路径。
"""
import asyncio
from pathlib import Path

from .config import settings


def is_enabled() -> bool:
    return all(
        (
            settings.oss_endpoint,
            settings.oss_access_key_id,
            settings.oss_access_key_secret,
            settings.oss_bucket,
            settings.oss_public_base_url,
        )
    )


def _bucket():
    import oss2

    auth = oss2.Auth(settings.oss_access_key_id, settings.oss_access_key_secret)
    return oss2.Bucket(auth, settings.oss_endpoint, settings.oss_bucket)


async def upload_file(local_path: Path, key: str) -> str | None:
    """上传本地文件到 OSS，返回完整 URL；未启用或失败返回 None。"""
    if not is_enabled() or not local_path.exists():
        return None

    def _upload():
        _bucket().put_object_from_file(key, str(local_path))

    try:
        await asyncio.to_thread(_upload)
    except Exception:  # noqa: BLE001 OSS 失败降级本地
        return None
    return f"{settings.oss_public_base_url.rstrip('/')}/{key}"
