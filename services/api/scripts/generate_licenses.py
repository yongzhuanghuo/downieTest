"""生成激活码并写入数据库，输出 CSV（移植自 Node scripts/generate-licenses.js）。

用法：
  python scripts/generate_licenses.py -c 10 -t perpetual
  python scripts/generate_licenses.py -c 5 -t free -e 30 -o trial.csv

选项：
  -t, --type     free | perpetual   (默认 perpetual)
  -d, --devices  最大设备数          (默认 free=1 perpetual=4)
  -e, --expire   过期天数            (默认 0=永不过期)
  -c, --count    生成数量            (默认 1)
  -o, --output   CSV 输出文件        (默认 stdout)
"""
import argparse
import asyncio
import time

from app.db import SessionLocal
from app.modules.license import codes, models  # noqa: F401 注册 ORM


async def _run(opts):
    type_ = "free" if opts.type == "free" else "perpetual"
    max_devices = opts.devices if opts.devices is not None else (4 if type_ == "perpetual" else 1)
    expire_at = None if opts.expire <= 0 else int(time.time() * 1000) + opts.expire * 86400 * 1000

    raws = []
    async with SessionLocal() as session:
        for _ in range(opts.count):
            raw = await _insert_one(session, type_, max_devices, expire_at)
            raws.append(raw)
        await session.commit()

    lines = ["activation_code,type,max_devices,expire_at_ts,expire_days"]
    for raw in raws:
        lines.append(f"{codes.format_code(raw)},{type_},{max_devices},{expire_at or 0},{opts.expire}")
    out = "\n".join(lines) + "\n"

    if opts.output:
        with open(opts.output, "w", encoding="utf-8") as f:
            f.write(out)
        print(f"✅ 已生成 {len(raws)} 个激活码 -> {opts.output}")
    else:
        print(out, end="")


async def _insert_one(session, type_, max_devices, expire_at) -> str:
    for _ in range(3):
        raw = codes.generate_code()
        try:
            session.add(models.License(code=raw, type=type_, max_devices=max_devices, expire_at=expire_at))
            await session.flush()
            return raw
        except Exception as e:  # noqa: BLE001 撞码重试
            await session.rollback()
            errno = getattr(getattr(e, "orig", None), "args", [None])[0]
            if errno == 1062:
                continue
            raise
    raise RuntimeError("生成失败：多次撞码，请重试")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--type", default="perpetual")
    parser.add_argument("-d", "--devices", type=int, default=None)
    parser.add_argument("-e", "--expire", type=int, default=0)
    parser.add_argument("-c", "--count", type=int, default=1)
    parser.add_argument("-o", "--output", default=None)
    args = parser.parse_args()
    try:
        asyncio.run(_run(args))
    except Exception as e:  # noqa: BLE001
        print(f"生成失败: {e}")
        raise SystemExit(1)
