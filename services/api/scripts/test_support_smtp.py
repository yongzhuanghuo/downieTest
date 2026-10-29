#!/usr/bin/env python3
"""联系支持链路自测：本地 SMTP 接收 + FastAPI TestClient。

用法（在 services/api 下）：
    uv pip install -r requirements-dev.txt
    python scripts/test_support_smtp.py

会启动一个只监听 127.0.0.1 的临时 SMTP 服务器，向 /api/support/report
发一份带中文的报告，然后检查邮件头/正文。不会连真实邮箱、不发外网。
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
    "MODULES": "support",  # 不挂 license/admin/media，避免本地连 MySQL
})

from aiosmtpd.controller import Controller  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402
from app.modules.support import router as support_router  # noqa: E402


class Sink:
    def __init__(self):
        self.messages: list[bytes] = []

    async def handle_DATA(self, server, session, envelope):
        self.messages.append(envelope.content)
        return "250 Message accepted for delivery"


def main() -> int:
    sink = Sink()
    controller = Controller(
        sink,
        hostname="127.0.0.1",
        port=SMTP_PORT,
        ready_timeout=10,
    )
    controller.start()
    print(f"本地 SMTP 已启动: 127.0.0.1:{SMTP_PORT}")

    try:
        with TestClient(app) as client:
            payload = {
                "email": "buyer@example.com",
                "url": "https://youtu.be/PHkxkeeoLyw",
                "account": "YouTube",
                "message": "无效的配置，视频无法解析",
                "diagnostics": "版本：2.0.33\n系统：macos",
                "platform": "macos",
            }
            resp = client.post("/api/support/report", json=payload)
            assert resp.status_code == 200, (resp.status_code, resp.text)
            body = resp.json()
            assert body.get("ok") is True, body
            print("接口返回:", body)

            assert len(sink.messages) == 1, f"应收到 1 封邮件，实际 {len(sink.messages)}"
            raw = sink.messages[0]
            msg = email.message_from_bytes(raw)
            subject = str(make_header(decode_header(msg["Subject"])))
            assert "PHkxkeeoLyw" not in subject  # 主题只放邮箱和类型
            assert "buyer@example.com" in subject, subject
            assert msg["To"] == "support@local.test", msg["To"]
            assert msg["Reply-To"] == "buyer@example.com", msg["Reply-To"]
            assert msg["From"] == "4KDownle <bot@local.test>", msg["From"]

            text = msg.get_payload(decode=True).decode("utf-8")
            for needle in (
                "buyer@example.com",
                "https://youtu.be/PHkxkeeoLyw",
                "YouTube",
                "无效的配置，视频无法解析",
                "版本：2.0.33",
            ):
                assert needle in text, f"邮件正文缺少: {needle}"
            print("邮件头/正文检查通过")

            # SMTP 未配置时必须是明确失败，不能假装成功
            old_host = support_router.settings.smtp_host
            support_router.settings.smtp_host = ""
            try:
                resp = client.post(
                    "/api/support/report",
                    json={**payload, "email": "other@example.com"},
                )
                assert resp.status_code == 503, (resp.status_code, resp.text)
                assert resp.json().get("error") == "MAIL_NOT_CONFIGURED"
                print("未配置 SMTP 的失败路径通过")
            finally:
                support_router.settings.smtp_host = old_host
    finally:
        controller.stop()

    print("✅ 联系支持链路自测通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
