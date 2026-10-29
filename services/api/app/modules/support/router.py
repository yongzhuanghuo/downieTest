"""联系支持：客户端提交，服务端 SMTP 转发到支持邮箱。

与 Downie 的 Support 窗口一致，用户不需要在机器上配置邮件客户端。
SMTP 未配置时返回 503，客户端回退到「复制报告 / 邮件客户端」，不会假装成功。
"""
import asyncio
import logging
import re
import smtplib
import time
from email.message import EmailMessage
from email.utils import formataddr, formatdate

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from ...config import settings

router = APIRouter()
log = logging.getLogger("app.support")

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# 简单的进程内频控：同一 IP 10 分钟最多 5 封，防被当成垃圾邮件出口。
_HITS: dict[str, list[float]] = {}
_WINDOW_SECONDS = 600.0
_LIMIT = 5


class SupportReportIn(BaseModel):
    email: str = Field(default="", max_length=255)
    url: str = Field(default="", max_length=4000)
    account: str = Field(default="", max_length=2000)
    message: str = Field(default="", max_length=20000)
    diagnostics: str = Field(default="", max_length=60000)
    platform: str = Field(default="", max_length=40)
    version: str = Field(default="", max_length=40)
    # 蜜罐字段：正常客户端不填，爬虫填了就假装成功
    website: str = Field(default="", max_length=200)


def _rate_limited(ip: str) -> bool:
    now = time.time()
    recent = [t for t in _HITS.get(ip, []) if now - t < _WINDOW_SECONDS]
    if len(recent) >= _LIMIT:
        _HITS[ip] = recent
        return True
    recent.append(now)
    _HITS[ip] = recent
    if len(_HITS) > 2000:
        _HITS.clear()
        _HITS[ip] = [now]
    return False


def _build_message(payload: SupportReportIn, email: str, ip: str) -> EmailMessage:
    sender = settings.smtp_from or settings.smtp_user
    if not sender:
        raise RuntimeError("SMTP_FROM/SMTP_USER 未配置")

    kind = "报告链接" if payload.url.strip() else "用户反馈"
    msg = EmailMessage()
    msg["Subject"] = f"[4KDownle] {kind} - {email}"
    msg["From"] = formataddr(("4KDownle", sender))
    msg["To"] = settings.support_email_to
    msg["Reply-To"] = email
    msg["Date"] = formatdate(localtime=True)

    lines = [
        "来自 4KDownle 支持表单",
        "",
        f"联系邮箱：{email}",
        f"链接：{payload.url.strip() or '（未填写）'}",
        f"需要账户：{payload.account.strip() or '（未填写）'}",
        f"客户端：{payload.platform.strip() or '未知'} {payload.version.strip()}".rstrip(),
        f"来源 IP：{ip or '未知'}",
        "",
        "问题描述：",
        payload.message.strip() or "（未填写）",
    ]
    if payload.diagnostics.strip():
        lines += ["", "--- 诊断信息 ---", payload.diagnostics.strip()]
    msg.set_content("\n".join(lines))
    return msg


def _send_mail(payload: SupportReportIn, email: str, ip: str) -> None:
    if not settings.smtp_host:
        raise RuntimeError("SMTP_HOST 未配置")
    msg = _build_message(payload, email, ip)

    if settings.smtp_ssl:
        server = smtplib.SMTP_SSL(settings.smtp_host, settings.smtp_port, timeout=25)
    else:
        server = smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=25)
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


@router.post("/api/support/report")
async def submit_report(payload: SupportReportIn, request: Request):
    # 蜜罐命中：不暴露规则，直接成功
    if payload.website.strip():
        return {"ok": True, "message": "已收到"}

    email = payload.email.strip()
    if not _EMAIL_RE.match(email):
        return JSONResponse(
            status_code=400,
            content={"ok": False, "error": "INVALID_EMAIL", "message": "邮箱格式不正确"},
        )
    if not payload.message.strip() and not payload.url.strip():
        return JSONResponse(
            status_code=400,
            content={"ok": False, "error": "EMPTY_REPORT", "message": "请填写问题描述或链接"},
        )

    ip = request.client.host if request.client else ""
    if _rate_limited(ip):
        return JSONResponse(
            status_code=429,
            content={"ok": False, "error": "RATE_LIMITED", "message": "发送过于频繁，请稍后再试"},
        )

    if not settings.smtp_host:
        log.warning("收到支持报告但未配置 SMTP，来自 %s", email)
        return JSONResponse(
            status_code=503,
            content={
                "ok": False,
                "error": "MAIL_NOT_CONFIGURED",
                "message": "服务端未配置支持邮箱，请复制报告或使用邮件客户端发送",
            },
        )

    try:
        await asyncio.to_thread(_send_mail, payload, email, ip)
    except Exception as e:  # noqa: BLE001
        log.exception("支持邮件发送失败: %s", e)
        return JSONResponse(
            status_code=502,
            content={
                "ok": False,
                "error": "MAIL_FAILED",
                "message": "邮件发送失败，请稍后重试或复制报告发送",
            },
        )

    log.info("支持报告已发送: %s -> %s", email, settings.support_email_to)
    return {"ok": True, "message": "已发送"}
