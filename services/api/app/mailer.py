"""通用 SMTP 发信。

与 support 模块共用一套 SMTP_* 配置；support 只发给固定支持邮箱，
这里用于给用户发许可证找回邮件。
"""
import asyncio
import smtplib
from email.message import EmailMessage
from email.utils import formataddr, formatdate

from .config import settings

SMTP_TIMEOUT = 20


def _send_sync(to: str, subject: str, body: str, from_name: str) -> None:
    if not settings.smtp_host:
        raise RuntimeError("SMTP_HOST 未配置")
    sender = settings.smtp_from or settings.smtp_user
    if not sender:
        raise RuntimeError("SMTP_FROM/SMTP_USER 未配置")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((from_name or "4KDownle", sender))
    msg["To"] = to
    msg["Date"] = formatdate(localtime=True)
    msg.set_content(body)

    if settings.smtp_ssl:
        server = smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=SMTP_TIMEOUT)
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=SMTP_TIMEOUT)
        if settings.smtp_starttls:
            server.starttls()
    try:
        if settings.smtp_user:
            server.login(settings.smtp_user, settings.smtp_password)
        server.send_message(msg)
    finally:
        try:
            server.quit()
        except Exception:  # noqa: BLE001
            pass


async def send_text(to: str, subject: str, body: str, from_name: str = "4KDownle") -> None:
    """异步发一封纯文本邮件。失败抛异常，由调用方转成业务错误。"""
    # 兜底总超时：smtplib 的 timeout 是单次 socket 操作，连接+登录+发送可能叠加。
    await asyncio.wait_for(
        asyncio.to_thread(_send_sync, to, subject, body, from_name),
        timeout=30,
    )
