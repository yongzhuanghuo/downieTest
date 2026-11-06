"""产品管理（Pure-Admin 信封）。

产品是数据驱动的：新增一行后，卡密生成页即可选择该产品。
不改代码，试用/卡密/设备/邮箱逻辑全部复用。
"""
import re
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.modules.license.models import License, Product
from ..serialize import ok
from .auth import get_current_user

router = APIRouter()

_CODE_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{1,31}$")
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class ProductIn(BaseModel):
    id: Optional[int] = None
    code: str
    name: str
    trial_days: int = 14
    default_max_devices: int = 1
    purchase_url: str = ""
    support_email: str = ""
    status: int = 1


def _product_dict(p: Product, card_count: int = 0) -> dict:
    return {
        "id": p.id,
        "code": p.code,
        "name": p.name,
        "trial_days": p.trial_days,
        "default_max_devices": p.default_max_devices,
        "purchase_url": p.purchase_url or "",
        "support_email": p.support_email or "",
        "status": p.status,
        "card_count": card_count,
    }


def _clean(body: ProductIn) -> dict:
    code = body.code.strip().lower()
    name = body.name.strip()
    if not _CODE_RE.fullmatch(code):
        raise HTTPException(
            status_code=400,
            detail={"code": 400, "message": "产品编码只能是小写字母/数字/-/_，长度 2-32"},
        )
    if not name:
        raise HTTPException(status_code=400, detail={"code": 400, "message": "产品名称不能为空"})
    email = body.support_email.strip()
    if email and (len(email) > 255 or not _EMAIL_RE.fullmatch(email)):
        raise HTTPException(status_code=400, detail={"code": 400, "message": "支持邮箱格式不正确"})
    purchase_url = body.purchase_url.strip()
    if purchase_url and not (purchase_url.startswith("https://") or purchase_url.startswith("http://")):
        raise HTTPException(
            status_code=400,
            detail={"code": 400, "message": "购买链接必须以 http:// 或 https:// 开头"},
        )
    return {
        "code": code,
        "name": name,
        "trial_days": min(365, max(1, body.trial_days)),
        "default_max_devices": min(100, max(1, body.default_max_devices)),
        "purchase_url": purchase_url,
        "support_email": email,
        "status": 1 if body.status else 0,
    }


@router.post("/product/list", dependencies=[Depends(get_current_user)])
async def product_list(session: AsyncSession = Depends(get_session)):
    rows = (await session.scalars(select(Product).order_by(Product.id))).all()
    counts = {
        product_id: count
        for product_id, count in (
            await session.execute(
                select(License.product_id, func.count(License.code)).group_by(License.product_id)
            )
        ).all()
    }
    return ok({"list": [_product_dict(p, counts.get(p.id, 0)) for p in rows]})


@router.post("/product/create", dependencies=[Depends(get_current_user)])
async def product_create(body: ProductIn, session: AsyncSession = Depends(get_session)):
    values = _clean(body)
    exists = await session.scalar(select(Product).where(Product.code == values["code"]))
    if exists:
        raise HTTPException(status_code=400, detail={"code": 400, "message": "产品编码已存在"})
    p = Product(**values)
    session.add(p)
    await session.commit()
    await session.refresh(p)
    return ok(_product_dict(p))


@router.post("/product/update", dependencies=[Depends(get_current_user)])
async def product_update(body: ProductIn, session: AsyncSession = Depends(get_session)):
    if body.id is None:
        raise HTTPException(status_code=400, detail={"code": 400, "message": "缺少产品 id"})
    p = await session.get(Product, body.id)
    if p is None:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "产品不存在"})
    values = _clean(body)
    if values["code"] != p.code:
        card_count = await session.scalar(
            select(func.count(License.code)).where(License.product_id == p.id)
        )
        if card_count:
            raise HTTPException(
                status_code=400,
                detail={"code": 400, "message": "该产品已有卡密，不能修改产品编码"},
            )
    for key, value in values.items():
        setattr(p, key, value)
    await session.commit()
    return ok(_product_dict(p))
