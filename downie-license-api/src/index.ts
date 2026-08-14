/**
 * Downie 许可证后端 API
 * 运行在 Cloudflare Workers + D1 (SQLite)
 *
 * 端到端流程:
 * 1. 客户端输入激活码 → 先本地 HMAC-SHA256 验签
 * 2. 验签通过后 → 请求本服务绑定设备
 * 3. 服务端检查设备数 < max_devices → 写入绑定 → 返回成功
 * 4. 超过上限 → 返回已绑设备列表 → 客户端弹出解绑选择框
 */

import { Hono } from 'hono';
import { cors } from 'hono/cors';

// ======================== 类型定义 ========================
type Bindings = {
  DB: D1Database;
  HMAC_SECRET: string;
};

type LicensePayload = {
  type: string;            // 'perpetual' | 'free'
  max_devices: number;
  nonce: number;
  expire_at: number | null;
};

// ======================== HMAC-SHA256 验签 ========================
// 和 Flutter 客户端保持完全一致的签名算法
async function verifyLicenseCode(
  code: string,
  secret: string,
): Promise<LicensePayload> {
  // Base32 解码（自定义字母表，和客户端一致）
  const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // 移除横线
  const clean = code.replace(/-/g, '').toUpperCase();

  // 检查长度: 20 位 = 12.5 字节，去掉最后 4 bit 填充 = 12 字节
  if (clean.length !== 20) {
    throw new Error('INVALID_LENGTH');
  }

  // Base32 解码
  const bits: number[] = [];
  for (const ch of clean) {
    const idx = ALPHABET.indexOf(ch);
    if (idx === -1) throw new Error('INVALID_CHAR');
    for (let i = 4; i >= 0; i--) {
      bits.push((idx >> i) & 1);
    }
  }

  // 12 字节 = 96 bit（前 32 bit = HMAC 截断，后 64 bit = payload）
  // 但为了对齐 base32 编码，最后 4 bit 是补零，去掉
  // 所以有效数据是 (20 * 5 - 4) / 8 = 96 / 8 = 12 字节
  const bytes: number[] = [];
  for (let i = 0; i < bits.length; i += 8) {
    if (i + 8 > bits.length) break;
    let byte = 0;
    for (let j = 0; j < 8; j++) {
      byte = (byte << 1) | bits[i + j];
    }
    bytes.push(byte);
  }

  if (bytes.length < 12) throw new Error('DECODE_FAILED');

  // 拆分: 前 4 字节 = HMAC 前缀, 后 8 字节 = payload
  const providedHmac = bytes.slice(0, 4);
  const payloadBytes = bytes.slice(4, 12);

  // 从 payload 反推字段
  // 第 0 字节: type | max_devices
  const b0 = payloadBytes[0];
  const type = b0 & 0x7f;      // 低 7 bit
  const maxDevices = (b0 >> 7) & 0x01; // 最高 bit（0=1, 1=4）
  // 第 1 字节: nonce 高 8 bit
  // 第 2 字节: nonce 中 8 bit
  // 第 3 字节: nonce 低 8 bit
  // 第 4 字节: expire 标记 + 高 4 bit
  // 第 5 字节: expire 中 8 bit
  // 第 6 字节: expire 低 8 bit
  // 第 7 字节: expire 最低 4 bit

  const nonce =
    (payloadBytes[1] << 16) |
    (payloadBytes[2] << 8) |
    payloadBytes[3];

  const expireFlag = (payloadBytes[4] >> 4) & 0x01;
  let expireAt: number | null = null;
  if (expireFlag) {
    expireAt =
      ((payloadBytes[4] & 0x0f) << 24) |
      (payloadBytes[5] << 16) |
      (payloadBytes[6] << 8) |
      payloadBytes[7];
    // 如果值为 0，设为永久
    if (expireAt === 0) expireAt = null;
  }

  // 重新计算 HMAC-SHA256，取前 4 字节，对比
  const enc = new TextEncoder();
  const keyData = enc.encode(secret);
  const payloadData = new Uint8Array(payloadBytes);

  // HMAC-SHA256 计算
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    keyData,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, payloadData);
  const sigBytes = new Uint8Array(signature);

  // 取前 4 字节对比
  for (let i = 0; i < 4; i++) {
    if (sigBytes[i] !== providedHmac[i]) {
      throw new Error('HMAC_MISMATCH');
    }
  }

  const typeStr = type === 1 ? 'perpetual' : 'free';
  const devices = maxDevices ? 4 : 1;

  return {
    type: typeStr,
    max_devices: devices,
    nonce,
    expire_at: expireAt,
  };
}

// ======================== 辅助函数 ========================
function errorResponse(message: string, status: number, extra?: any) {
  return Response.json(
    { ok: false, error: message, ...extra },
    { status },
  );
}

// ======================== 路由 ========================
const app = new Hono<{ Bindings: Bindings }>();
app.use('*', cors({ origin: '*' }));

/**
 * POST /api/license/activate
 * 激活（绑定设备）
 */
app.post('/api/license/activate', async (c) => {
  const { code, device_fp, device_name } = await c.req.json();

  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 1. 本地验签
  let payload: LicensePayload;
  try {
    payload = await verifyLicenseCode(code, c.env.HMAC_SECRET);
  } catch (e: any) {
    return errorResponse('INVALID_CODE', 400, { detail: e.message });
  }

  // 2. 查激活码
  const license = await c.env.DB.prepare(
    'SELECT * FROM licenses WHERE code = ? AND status != ?',
  )
    .bind(code, 'revoked')
    .first();

  if (!license) {
    // 码未录入数据库 —— 但签名合法。
    // 自动录入（首次激活时触发，简化部署流程）
    await c.env.DB.prepare(
      'INSERT OR IGNORE INTO licenses (code, type, max_devices, nonce) VALUES (?, ?, ?, ?)',
    )
      .bind(code, payload.type, payload.max_devices, payload.nonce)
      .run();
  }

  // 3. 查已绑设备
  const { results: bound } = await c.env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND status = ?',
  )
    .bind(code, 'active')
    .all();

  // 4. 幂等：当前设备已绑定直接返回
  const existing = bound.find((d: any) => d.device_fp === device_fp);
  if (existing) {
    return c.json({
      ok: true,
      license: payload,
      device: existing,
      bound_count: bound.length,
      remaining_slots: Math.max(0, payload.max_devices - bound.length),
    });
  }

  // 5. 设备数检查
  if (bound.length >= payload.max_devices) {
    return c.json(
      {
        ok: false,
        error: 'DEVICE_LIMIT_REACHED',
        message: `已绑定 ${bound.length}/${payload.max_devices} 台设备，请先解绑旧设备`,
        bound_devices: bound,
      },
      403,
    );
  }

  // 6. 写入绑定
  const id = crypto.randomUUID();
  await c.env.DB.prepare(
    `INSERT INTO device_bindings (id, code, device_fp, device_name) VALUES (?, ?, ?, ?)`,
  )
    .bind(id, code, device_fp, device_name || 'Unknown')
    .run();

  // 7. 更新码状态为 activated
  await c.env.DB.prepare(
    'UPDATE licenses SET status = ? WHERE code = ? AND status = ?',
  )
    .bind('activated', code, 'unused')
    .run();

  return c.json({
    ok: true,
    license: payload,
    device: { id, bound_at: new Date().toISOString() },
    bound_count: bound.length + 1,
    remaining_slots: payload.max_devices - bound.length - 1,
  });
});

/**
 * POST /api/license/unbind
 * 解绑设备（支持跨设备远程解绑）
 */
app.post('/api/license/unbind', async (c) => {
  const { code, device_fp } = await c.req.json();

  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 1. 验签
  try {
    await verifyLicenseCode(code, c.env.HMAC_SECRET);
  } catch {
    return errorResponse('INVALID_CODE', 400);
  }

  // 2. 查本月解绑次数（限制 2 次/月）
  const { results: monthUnbinds } = await c.env.DB.prepare(
    `SELECT * FROM unbind_log WHERE code = ? AND unbound_at >= datetime('now', '-30 days')`,
  )
    .bind(code)
    .all();

  if (monthUnbinds.length >= 2) {
    return errorResponse(
      'UNBIND_LIMIT_EXCEEDED',
      429,
      { message: '本月解绑次数已用完（2/2），下月可继续操作' },
    );
  }

  // 3. 获取设备名称
  const device = await c.env.DB.prepare(
    'SELECT device_name FROM device_bindings WHERE code = ? AND device_fp = ? AND status = ?',
  )
    .bind(code, device_fp, 'active')
    .first();

  const deviceName = device ? (device as any).device_name : 'Unknown';

  // 4. 执行解绑
  await c.env.DB.batch([
    c.env.DB.prepare(
      'UPDATE device_bindings SET status = ? WHERE code = ? AND device_fp = ? AND status = ?',
    )
      .bind('unbound', code, device_fp, 'active'),
    c.env.DB.prepare(
      'INSERT INTO unbind_log (id, code, device_fp, device_name) VALUES (?, ?, ?, ?)',
    )
      .bind(crypto.randomUUID(), code, device_fp, deviceName),
  ]);

  // 5. 查剩余名额
  const { results: remaining } = await c.env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND status = ?',
  )
    .bind(code, 'active')
    .all();

  return c.json({
    ok: true,
    message: '设备已解绑',
    remaining_slots: Math.max(0, 4 - remaining.length),
  });
});

/**
 * GET /api/license/status?code=XXX&device_fp=YYY
 * 查询激活码状态、设备列表、剩余解绑次数
 */
app.get('/api/license/status', async (c) => {
  const code = c.req.query('code');
  const device_fp = c.req.query('device_fp');

  if (!code) {
    return errorResponse('MISSING_CODE', 400);
  }

  // 1. 查激活码
  const license = await c.env.DB.prepare(
    'SELECT * FROM licenses WHERE code = ?',
  )
    .bind(code)
    .first();

  if (!license) {
    return errorResponse('NOT_FOUND', 404);
  }

  // 2. 查已绑设备
  const { results: devices } = await c.env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND status = ? ORDER BY bound_at',
  )
    .bind(code, 'active')
    .all();

  // 3. 查本月解绑次数
  const { results: unbinds } = await c.env.DB.prepare(
    `SELECT * FROM unbind_log WHERE code = ? AND unbound_at >= datetime('now', '-30 days')`,
  )
    .bind(code)
    .all();

  const maxDevices = (license as any).max_devices || 4;

  // 标记当前设备
  const devicesWithFlag = devices.map((d: any) => ({
    ...d,
    is_current: d.device_fp === device_fp,
  }));

  return c.json({
    ok: true,
    license: {
      type: (license as any).type,
      max_devices: maxDevices,
      expire_at: (license as any).expire_at,
    },
    bound_devices: devicesWithFlag,
    remaining_slots: Math.max(0, maxDevices - devices.length),
    unbind_used_this_month: unbinds.length,
    unbind_monthly_limit: 2,
  });
});

/**
 * POST /api/license/heartbeat
 * 心跳保活（每 24 小时一次）
 */
app.post('/api/license/heartbeat', async (c) => {
  const { code, device_fp, device_name } = await c.req.json();

  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 更新 last_seen
  const result = await c.env.DB.prepare(
    `UPDATE device_bindings SET last_seen = datetime('now'), device_name = ? 
     WHERE code = ? AND device_fp = ? AND status = ?`,
  )
    .bind(device_name || 'Unknown', code, device_fp, 'active')
    .run();

  if (result.changes === 0) {
    return errorResponse('NOT_FOUND', 404);
  }

  return c.json({ ok: true, next_heartbeat_hours: 24 });
});

/**
 * POST /api/license/verify
 * 离线降级验证（客户端超过 7 天未联网时调用）
 */
app.post('/api/license/verify', async (c) => {
  const { code, device_fp } = await c.req.json();

  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 1. 本地验签
  try {
    await verifyLicenseCode(code, c.env.HMAC_SECRET);
  } catch {
    return c.json({ ok: true, valid: false, reason: 'SIGNATURE_INVALID' });
  }

  // 2. 查绑定
  const binding = await c.env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND device_fp = ? AND status = ?',
  )
    .bind(code, device_fp, 'active')
    .first();

  if (!binding) {
    return c.json({
      ok: true,
      valid: false,
      reason: 'DEVICE_NOT_BOUND',
    });
  }

  // 3. 查码状态
  const license = await c.env.DB.prepare(
    'SELECT status FROM licenses WHERE code = ?',
  )
    .bind(code)
    .first();

  const status = license ? (license as any).status : 'unknown';

  return c.json({
    ok: true,
    valid: status !== 'revoked',
    is_pro: true,
    device_active: true,
  });
});

// 健康检查
app.get('/', (c) => {
  return c.json({
    service: 'Downie License API',
    version: '1.0.0',
    status: 'ok',
  });
});

export default app;
