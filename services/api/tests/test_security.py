"""安全相关回归测试（不连数据库）：

- 进程内限流窗口
- 管理端 JWT + admin 角色校验
- 客户端授权过期校验
- 设备列表必须由已绑定设备发起
- 心跳/verify 对被吊销授权码的拒绝
"""
import asyncio
import time

import jwt
import pytest
from fastapi import HTTPException

from app.config import settings
from app.modules.admin.models import SysRole, SysUser
from app.modules.license.models import DeviceBinding, License
from app.modules.license import service
from app.ratelimit import InMemoryRateLimiter
import app.security as security


class _Cred:
    def __init__(self, token: str):
        self.credentials = token


class _ScalarResult:
    def __init__(self, items):
        self.items = items

    def all(self):
        return self.items


class _FakeSession:
    """按调用顺序返回 scalar/scalars 结果，并记录 execute 的 rowcount。"""

    def __init__(self, scalar_values=None, rowcount: int = 1):
        self.scalar_values = list(scalar_values or [])
        self.rowcount = rowcount

    async def scalar(self, _query):
        return self.scalar_values.pop(0)

    async def scalars(self, _query):
        return _ScalarResult(self.scalar_values.pop(0))

    async def execute(self, _statement):
        rowcount = self.rowcount

        class _Result:
            pass

        result = _Result()
        result.rowcount = rowcount
        return result

    async def commit(self):
        return None


def _token(**extra) -> str:
    payload = {"user_id": 1, "username": "admin", "type": "access", "exp": int(time.time()) + 60}
    payload.update(extra)
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def _license(**extra) -> License:
    values = {
        "code": "ABCDEABCDEABCDEABCDE",
        "type": "perpetual",
        "max_devices": 4,
        "expire_at": None,
        "status": "activated",
    }
    values.update(extra)
    return License(**values)


def _admin_user() -> SysUser:
    return SysUser(id=1, username="admin", password_hash="x", status=1)


def test_rate_limiter_window_and_reset():
    limiter = InMemoryRateLimiter()
    assert limiter.allow("k", limit=2, window_seconds=60)
    assert limiter.allow("k", limit=2, window_seconds=60)
    assert not limiter.allow("k", limit=2, window_seconds=60)
    limiter.reset("k")
    assert limiter.allow("k", limit=2, window_seconds=60)


def test_require_admin_allows_admin_role():
    admin_role = SysRole(id=1, name="超级管理员", code="admin", status=1)
    session = _FakeSession([_admin_user(), [1], [admin_role]])

    result = asyncio.run(
        security.require_admin(_Cred(_token()), session)
    )

    assert result["username"] == "admin"


def test_require_admin_rejects_non_admin_role():
    user_role = SysRole(id=2, name="普通用户", code="user", status=1)
    session = _FakeSession([_admin_user(), [2], [user_role]])

    with pytest.raises(HTTPException) as exc:
        asyncio.run(security.require_admin(_Cred(_token()), session))

    assert exc.value.status_code == 403


def test_require_license_rejects_expired():
    expired = _license(expire_at=int(time.time() * 1000) - 1000)

    with pytest.raises(HTTPException) as exc:
        asyncio.run(
            security.require_license("ABCDEABCDEABCDEABCDE", "fp", _FakeSession([expired]))
        )

    assert exc.value.status_code == 403
    assert exc.value.detail["error"] == "LICENSE_EXPIRED"


def test_status_requires_bound_device():
    session = _FakeSession([_license(), None])

    with pytest.raises(service.LicenseError) as exc:
        asyncio.run(service.status(session, "ABCDEABCDEABCDEABCDE", "fp"))

    assert exc.value.status == 403
    assert exc.value.error == "DEVICE_NOT_BOUND"


def test_heartbeat_rejects_revoked_license():
    session = _FakeSession([_license(status="revoked")])

    with pytest.raises(service.LicenseError) as exc:
        asyncio.run(service.heartbeat(session, "ABCDEABCDEABCDEABCDE", "fp", "dev"))

    assert exc.value.status == 403
    assert exc.value.error == "LICENSE_REVOKED"


def test_verify_revoked_is_not_pro():
    binding = DeviceBinding(
        id="x",
        code="ABCDEABCDEABCDEABCDE",
        device_fp="fp",
        device_name="dev",
        status="active",
    )
    session = _FakeSession([_license(status="revoked"), binding])

    result = asyncio.run(service.verify(session, "ABCDEABCDEABCDEABCDE", "fp"))

    assert result["valid"] is False
    assert result["is_pro"] is False
    assert result["reason"] == "LICENSE_REVOKED"
