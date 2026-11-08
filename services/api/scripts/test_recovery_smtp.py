#!/usr/bin/env python3
"""许可证找回链路自测：本地 SMTP 接收 + FastAPI TestClient。

用法（在 services/api 下）：
    uv pip install -r requirements-dev.txt
    python scripts/test_recovery_smtp.py

用假 DB session 模拟许可证记录，验证：
- 命中邮箱 → 邮件里带格式化卡密
- 未命中 → found=false，不发信
- 60 秒内重发 → 429
- SMTP 未配置 → 503
不会连 MySQL、不发外网。
"""
import email
import os
import socket
import sys
from email.header import decode_header, make_header
from pathlib import Path

SERVICE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SERVICE_DIR))

# 必须在 import app 前设置，Settings 在导入时实例化
sock = socket.socket()
sock.bind(("127.0.0.1", 0))
SMTP_PORT = sock.getsockname()[1]
sock.close()

os.environ.update({
    "SMTP_HOST": "127.0.0.1",
    "SMTP_PORT": str(SMTP_PORT),
    "SMTP_SSL": "false",
    "SMTP_STARTTLS": "false",
    "SMTP_USER": "",
    "SMTP_PASSWORD": "",
    "SMTP_FROM": "bot@local.test",
    "SUPPORT_EMAIL_TO": "support@local.test",
    "MODULES": "license",
    "JWT_SECRET": "test-secret",
    "DB_HOST": "127.0.0.1",
    "DB_USER": "test",
    "DB_PASSWORD": "test",
    "DB_NAME": "test",
})

from aiosmtpd.controller import Controller  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import get_session  # noqa: E402
from app.main import app  # noqa: E402
from app.modules.license import router as license_router  # noqa: E402
from app.modules.license.models import License, Product  # noqa: E402


class ScalarRows:
    def __init__(self, rows):
        self._rows = rows

    def all(self):
        return self._rows


class FakeSession:
    def __init__(self):
        self.product = Product(
            id=1, code="downie6", name="Downie6", trial_days=14, default_max_devices=4, status=1
        )
        self.rows = [
            License(
                code="ABCDEFGHJKLMNPQRSTUV",
                product_id=1,
                type="perpetual",
                max_devices=4,
                email="buyer@example.com",
                status="activated",
            )
        ]

    async def scalar(self, _query):
        return self.product

    async def scalars(self, _query):
        return ScalarRows(self.rows)


class Sink:
    def __init__(self):
        self.messages: list[bytes] = []

    async def handle_DATA(self, server, session, envelope):
        self.messages.append(envelope.content)
        return "250 Message accepted for delivery"


def main() -> int:
    session = FakeSession()

    async def _session_override():
        yield session

    app.dependency_overrides[get_session] = _session_override

    sink = Sink()
    controller = Controller(sink, hostname="127.0.0.1", port=SMTP_PORT, ready_timeout=10)
    controller.start()
    print(f"本地 SMTP 已启动: 127.0.0.1:{SMTP_PORT}")

    try:
        with TestClient(app) as client:
            # 1. 命中：发信
            resp = client.post("/api/license/recover", json={"email": "buyer@example.com"})
            assert resp.status_code == 200, (resp.status_code, resp.text)
            body = resp.json()
            assert body["ok"] is True and body["found"] is True, body
            assert len(sink.messages) == 1, f"应收到 1 封邮件，实际 {len(sink.messages)}"

            msg = email.message_from_bytes(sink.messages[0])
            subject = str(make_header(decode_header(msg["Subject"])))
            assert "Downie6" in subject, subject
            assert msg["To"] == "buyer@example.com", msg["To"]
            assert msg["From"] == "Downie6 <bot@local.test>", msg["From"]
            text = msg.get_payload(decode=True).decode("utf-8")
            assert "ABCDE-FGHJK-LMNPQ-RSTUV" in text, text
            assert "永久授权" in text, text
            print("命中路径 + 邮件内容检查通过")

            # 2. 60 秒内重发同一邮箱：限流
            resp = client.post("/api/license/recover", json={"email": "buyer@example.com"})
            assert resp.status_code == 429, (resp.status_code, resp.text)
            assert resp.json()["detail"]["error"] == "RATE_LIMITED", resp.text
            print("重发冷却检查通过")

            # 3. 未命中：found=false，不发信
            session.rows = []
            resp = client.post("/api/license/recover", json={"email": "nobody@example.com"})
            assert resp.status_code == 200, (resp.status_code, resp.text)
            body = resp.json()
            assert body["ok"] is True and body["found"] is False, body
            assert len(sink.messages) == 1, "未命中不应发信"
            print("未命中路径检查通过")

            # 4. SMTP 未配置：明确失败，客户端可回退到邮件支持
            session.rows = []
            old_host = license_router.service.settings.smtp_host
            license_router.service.settings.smtp_host = ""
            try:
                resp = client.post("/api/license/recover", json={"email": "other@example.com"})
                assert resp.status_code == 503, (resp.status_code, resp.text)
                assert resp.json()["detail"]["error"] == "MAIL_NOT_CONFIGURED", resp.text
                print("未配置 SMTP 的失败路径通过")
            finally:
                license_router.service.settings.smtp_host = old_host
    finally:
        app.dependency_overrides.clear()
        controller.stop()

    print("✅ 许可证找回链路自测通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
