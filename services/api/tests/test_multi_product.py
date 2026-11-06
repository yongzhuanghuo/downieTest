"""多产品授权回归测试（不连数据库）。

验证 trials 按 (product_id, device_fp) 记录，且试用天数来自 products 表。
"""
import asyncio
from datetime import datetime

from app.modules.license import service
from app.modules.license.models import Product


class _Begin:
    async def __aenter__(self):
        return None

    async def __aexit__(self, exc_type, exc, tb):
        return False


class _TrialSession:
    def __init__(self, scalar_values):
        self.scalar_values = list(scalar_values)
        self.added = []

    def begin(self):
        return _Begin()

    async def scalar(self, _query):
        return self.scalar_values.pop(0)

    def add(self, obj):
        self.added.append(obj)


def _product(**extra) -> Product:
    values = {
        "id": 1,
        "code": "downie6",
        "name": "Downie6",
        "trial_days": 14,
        "default_max_devices": 4,
        "status": 1,
    }
    values.update(extra)
    return Product(**values)


def test_trial_uses_product_trial_days():
    product = _product(id=2, code="launch", name="launch", trial_days=14, default_max_devices=1)
    session = _TrialSession([product, None])

    result = asyncio.run(
        service.start_trial(
            session,
            "device-fp",
            device_name="Mac",
            platform="macos",
            product_code="launch",
        )
    )

    assert result["ok"] is True
    assert result["product"] == "launch"
    assert result["trial"]["status"] == "active"
    assert result["trial"]["days_remaining"] == 14
    assert len(session.added) == 1
    row = session.added[0]
    assert row.product_id == 2
    assert row.device_fp == "device-fp"
    assert row.trial_end > datetime.utcnow()


def test_trial_defaults_to_downie6():
    product = _product()
    session = _TrialSession([product, None])

    result = asyncio.run(service.start_trial(session, "device-fp"))

    assert result["product"] == "downie6"
    assert session.added[0].product_id == 1
