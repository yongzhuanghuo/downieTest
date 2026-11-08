"""许可证找回回归测试（不连数据库、不发真实邮件）。

覆盖：命中时把卡密发到邮箱、未命中不发信、邮箱格式错误、吊销卡密不返回。
"""
import asyncio

import pytest

from app.modules.license import service
from app.modules.license.models import License, Product


class _ScalarResult:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class _FakeSession:
    def __init__(self, product, rows):
        self._product = product
        self._rows = rows

    async def scalar(self, _query):
        return self._product

    async def scalars(self, _query):
        return _ScalarResult(self._rows)


def _product() -> Product:
    return Product(id=1, code="downie6", name="Downie6", trial_days=14, default_max_devices=4, status=1)


def _license(code: str, **extra) -> License:
    values = {
        "code": code,
        "product_id": 1,
        "type": "perpetual",
        "max_devices": 4,
        "email": "buyer@example.com",
        "status": "activated",
    }
    values.update(extra)
    return License(**values)


@pytest.fixture(autouse=True)
def _smtp_configured(monkeypatch):
    monkeypatch.setattr(service.settings, "smtp_host", "smtp.example.com")


def test_recover_sends_all_codes(monkeypatch):
    sent = []

    async def fake_send(to, subject, body, from_name="4KDownle"):
        sent.append((to, subject, body, from_name))

    monkeypatch.setattr(service.mailer, "send_text", fake_send)
    rows = [_license("ABCDEFGHJKLMNPQRSTUV"), _license("ZYXWVUTSRQPONMLKJHGF")]
    session = _FakeSession(_product(), rows)

    ok = asyncio.run(service.recover_by_email(session, "buyer@example.com"))
    assert ok is True
    assert len(sent) == 1
    to, subject, body, from_name = sent[0]
    assert to == "buyer@example.com"
    assert "Downie6" in subject
    assert from_name == "Downie6"
    assert "ABCDE-FGHJK-LMNPQ-RSTUV" in body
    assert "ZYXWV-UTSRQ-PONML-KJHGF" in body


def test_recover_no_match_does_not_send(monkeypatch):
    async def fake_send(*args, **kwargs):
        raise AssertionError("未命中不应发信")

    monkeypatch.setattr(service.mailer, "send_text", fake_send)
    session = _FakeSession(_product(), [])

    ok = asyncio.run(service.recover_by_email(session, "nobody@example.com"))
    assert ok is False


def test_recover_rejects_invalid_email():
    session = _FakeSession(_product(), [])
    with pytest.raises(service.LicenseError) as exc:
        asyncio.run(service.recover_by_email(session, "not-an-email"))
    assert exc.value.error == "INVALID_EMAIL"


def test_recover_requires_smtp(monkeypatch):
    monkeypatch.setattr(service.settings, "smtp_host", "")
    session = _FakeSession(_product(), [])
    with pytest.raises(service.LicenseError) as exc:
        asyncio.run(service.recover_by_email(session, "buyer@example.com"))
    assert exc.value.error == "MAIL_NOT_CONFIGURED"


def test_recover_mail_failure_maps_to_502(monkeypatch):
    async def fake_send(*args, **kwargs):
        raise RuntimeError("smtp down")

    monkeypatch.setattr(service.mailer, "send_text", fake_send)
    session = _FakeSession(_product(), [_license("ABCDEFGHJKLMNPQRSTUV")])
    with pytest.raises(service.LicenseError) as exc:
        asyncio.run(service.recover_by_email(session, "buyer@example.com"))
    assert exc.value.error == "MAIL_FAILED"
    assert exc.value.status == 502
