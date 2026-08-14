/**
 * Downie 许可证后端 API (v1.0.0)
 * 运行在 Cloudflare Workers + D1 (SQLite)
 *
 * 纯 Web 标准实现，零依赖，直接粘到 Cloudflare 在线编辑器即可运行
 *
 * 端到端流程:
 * 1. 客户端输入激活码 → 先本地 HMAC-SHA256 验签
 * 2. 验签通过后 → 请求本服务绑定设备
 * 3. 服务端检查设备数 < max_devices → 写入绑定 → 返回成功
 * 4. 超过上限 → 返回已绑设备列表 → 客户端弹出解绑选择框
 *
 * 绑定: env.DB (D1)
 */

// HMAC 密钥（和 Flutter 客户端 license.dart _secret 保持一致）
const HMAC_SECRET = 'DownloPRO_HMAC_v2_x9K2pQ7mFz4L8cN3sR5t';

// ======================== CORS 辅助 ========================
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

function corsResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

function errorResponse(message, status, extra) {
  return corsResponse({ ok: false, error: message, ...extra }, status);
}

// ======================== HMAC-SHA256 验签 ========================
// 和 Flutter 客户端 license.dart 保持完全一致的算法
async function verifyLicenseCode(code, secret) {
  const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // 预处理：去掉非字母数字 + 大写 + 易混字符映射（和 Dart _clean 一致）
  // 0,O → 8；  1,I → L
  const clean = code
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .replace(/O/g, '8')
    .replace(/0/g, '8')
    .replace(/1/g, 'L')
    .replace(/I/g, 'L');

  if (clean.length !== 20) {
    throw new Error('INVALID_LENGTH');
  }

  // Base32 解码（和 Dart _decodeBase32 完全一致）
  // 20 chars × 5 bit = 100 bit，有效数据 96 bit（12 bytes），最后一个字符只取 1 bit
  const TOTAL_BYTES = 12;
  const expectedBits = TOTAL_BYTES * 8; // 96
  let buffer = 0;
  let bitsLeft = 0;
  let consumedBits = 0;
  const bytes = [];

  for (const ch of clean) {
    const idx = ALPHABET.indexOf(ch);
    if (idx < 0) continue;

    const remaining = expectedBits - consumedBits;
    // 剩下不足 5 位时，只取 LSB 侧的剩余位数
    const take = remaining < 5 ? remaining : 5;
    const mask = (1 << take) - 1;
    const val = idx & mask;

    buffer = (buffer << take) | val;
    bitsLeft += take;
    consumedBits += take;

    while (bitsLeft >= 8) {
      bitsLeft -= 8;
      bytes.push((buffer >> bitsLeft) & 0xff);
    }

    if (consumedBits >= expectedBits) break;
  }

  // 兜底对齐 12 字节
  while (bytes.length < TOTAL_BYTES) bytes.unshift(0);

  if (bytes.length < TOTAL_BYTES) throw new Error('DECODE_FAILED');

  // 拆分: 前 4 字节 = HMAC 签名截断, 后 8 字节 = payload
  const providedHmac = bytes.slice(0, 4);
  const payloadBytes = bytes.slice(4, 12);

  // 从 payload 反推字段（和 Dart LicensePayload.fromBytes 完全一致）
  // byte 0: bit4 = type flag (1=perpetual), bits 0-3 = maxDevices
  const b0 = payloadBytes[0];
  const isPerpetual = (b0 & 0x10) !== 0;
  const maxDevices = b0 & 0x0f;

  // bytes 1-4: expire timestamp (big-endian 32-bit, 0 = null)
  const expireRaw =
    (payloadBytes[1] << 24) |
    (payloadBytes[2] << 16) |
    (payloadBytes[3] << 8) |
    payloadBytes[4];
  const expireAt = expireRaw === 0 ? null : expireRaw;

  // bytes 5-7: nonce (big-endian 24-bit)
  const nonce =
    (payloadBytes[5] << 16) |
    (payloadBytes[6] << 8) |
    payloadBytes[7];

  // 重新计算 HMAC-SHA256，取前 4 字节对比
  const enc = new TextEncoder();
  const keyData = enc.encode(secret);
  const payloadData = new Uint8Array(payloadBytes);

  const cryptoKey = await crypto.subtle.importKey(
    'raw', keyData, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const signature = await crypto.subtle.sign('HMAC', cryptoKey, payloadData);
  const sigBytes = new Uint8Array(signature);

  for (let i = 0; i < 4; i++) {
    if (sigBytes[i] !== providedHmac[i]) {
      throw new Error('HMAC_MISMATCH');
    }
  }

  return {
    type: isPerpetual ? 'perpetual' : 'free',
    max_devices: maxDevices,
    nonce,
    expire_at: expireAt,
  };
}

// ======================== 路由分发 ========================
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // OPTIONS 预检
    if (request.method === 'OPTIONS') {
      return new Response('', { status: 204, headers: CORS_HEADERS });
    }

    // 健康检查
    if (request.method === 'GET' && url.pathname === '/') {
      return corsResponse({
        service: 'Downie License API',
        version: '1.0.0',
        status: 'ok',
      });
    }

    // POST /api/license/activate
    if (request.method === 'POST' && url.pathname === '/api/license/activate') {
      return handleActivate(request, env);
    }

    // POST /api/license/unbind
    if (request.method === 'POST' && url.pathname === '/api/license/unbind') {
      return handleUnbind(request, env);
    }

    // GET /api/license/status
    if (request.method === 'GET' && url.pathname === '/api/license/status') {
      return handleStatus(url, env);
    }

    // POST /api/license/heartbeat
    if (request.method === 'POST' && url.pathname === '/api/license/heartbeat') {
      return handleHeartbeat(request, env);
    }

    // POST /api/license/verify
    if (request.method === 'POST' && url.pathname === '/api/license/verify') {
      return handleVerify(request, env);
    }

    // 404
    return errorResponse('NOT_FOUND', 404);
  },
};

// ======================== Handler 实现 ========================

/**
 * POST /api/license/activate - 激活（绑定设备）
 */
async function handleActivate(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('INVALID_JSON', 400);
  }

  const { code, device_fp, device_name } = body;
  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 1. 本地验签
  let payload;
  try {
    payload = await verifyLicenseCode(code, HMAC_SECRET);
  } catch (e) {
    return errorResponse('INVALID_CODE', 400, { detail: e.message });
  }

  // 2. 查激活码
  let license;
  try {
    license = await env.DB.prepare(
      'SELECT * FROM licenses WHERE code = ? AND status != ?'
    ).bind(code, 'revoked').first();
  } catch (e) {
    return errorResponse('DB_ERROR', 500, { detail: 'SELECT licenses: ' + e.message });
  }

  if (!license) {
    // 首次激活自动录入
    try {
      await env.DB.prepare(
        'INSERT OR IGNORE INTO licenses (code, type, max_devices, nonce) VALUES (?, ?, ?, ?)'
      ).bind(code, payload.type, payload.max_devices, payload.nonce).run();
    } catch (e) {
      return errorResponse('DB_ERROR', 500, { detail: 'INSERT licenses: ' + e.message });
    }
  }

  // 3. 查已绑设备
  let boundResult;
  try {
    boundResult = await env.DB.prepare(
      'SELECT * FROM device_bindings WHERE code = ? AND status = ?'
    ).bind(code, 'active').all();
  } catch (e) {
    return errorResponse('DB_ERROR', 500, { detail: 'SELECT bindings: ' + e.message });
  }
  const bound = boundResult.results;

  // 4. 幂等：当前设备已绑定直接返回
  const existing = bound.find(d => d.device_fp === device_fp);
  if (existing) {
    return corsResponse({
      ok: true,
      license: payload,
      device: existing,
      bound_count: bound.length,
      remaining_slots: Math.max(0, payload.max_devices - bound.length),
    });
  }

  // 5. 设备数检查
  if (bound.length >= payload.max_devices) {
    return corsResponse({
      ok: false,
      error: 'DEVICE_LIMIT_REACHED',
      message: `已绑定 ${bound.length}/${payload.max_devices} 台设备，请先解绑旧设备`,
      bound_devices: bound,
    }, 403);
  }

  // 6. 写入绑定（如果已存在则忽略，幂等）
  const id = crypto.randomUUID();
  try {
    await env.DB.prepare(
      'INSERT OR IGNORE INTO device_bindings (id, code, device_fp, device_name) VALUES (?, ?, ?, ?)'
    ).bind(id, code, device_fp, device_name || 'Unknown').run();
  } catch (e) {
    return errorResponse('DB_ERROR', 500, { detail: 'INSERT binding: ' + e.message });
  }

  // 7. 更新码状态
  try {
    await env.DB.prepare(
      'UPDATE licenses SET status = ? WHERE code = ? AND status = ?'
    ).bind('activated', code, 'unused').run();
  } catch (e) {
    return errorResponse('DB_ERROR', 500, { detail: 'UPDATE license: ' + e.message });
  }

  return corsResponse({
    ok: true,
    license: payload,
    device: {
      id,
      device_fp: device_fp,
      device_name: device_name || 'Unknown',
      bound_at: new Date().toISOString(),
    },
    bound_count: bound.length + 1,
    remaining_slots: payload.max_devices - bound.length - 1,
  });
}

/**
 * POST /api/license/unbind - 解绑设备
 */
async function handleUnbind(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('INVALID_JSON', 400);
  }

  const { code, device_fp } = body;
  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 1. 验签
  try {
    await verifyLicenseCode(code, HMAC_SECRET);
  } catch {
    return errorResponse('INVALID_CODE', 400);
  }

  // 2. 获取设备名称
  const device = await env.DB.prepare(
    'SELECT device_name FROM device_bindings WHERE code = ? AND device_fp = ? AND status = ?'
  ).bind(code, device_fp, 'active').first();

  const deviceName = device ? device.device_name : 'Unknown';

  // 3. 执行解绑 (batch)
  await env.DB.batch([
    env.DB.prepare(
      'UPDATE device_bindings SET status = ? WHERE code = ? AND device_fp = ? AND status = ?'
    ).bind('unbound', code, device_fp, 'active'),
    env.DB.prepare(
      'INSERT INTO unbind_log (id, code, device_fp, device_name) VALUES (?, ?, ?, ?)'
    ).bind(crypto.randomUUID(), code, device_fp, deviceName),
  ]);

  // 4. 查剩余名额
  const { results: remaining } = await env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND status = ?'
  ).bind(code, 'active').all();

  return corsResponse({
    ok: true,
    message: '设备已解绑',
    remaining_slots: Math.max(0, 4 - remaining.length),
  });
}

/**
 * GET /api/license/status - 查询状态
 */
async function handleStatus(url, env) {
  const code = url.searchParams.get('code');
  const device_fp = url.searchParams.get('device_fp');

  if (!code) {
    return errorResponse('MISSING_CODE', 400);
  }

  // 1. 查激活码
  const license = await env.DB.prepare(
    'SELECT * FROM licenses WHERE code = ?'
  ).bind(code).first();

  if (!license) {
    return errorResponse('NOT_FOUND', 404);
  }

  // 2. 查已绑设备
  const { results: devices } = await env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND status = ? ORDER BY bound_at'
  ).bind(code, 'active').all();

  const maxDevices = license.max_devices || 4;

  // 标记当前设备
  const devicesWithFlag = devices.map(d => ({
    ...d,
    is_current: d.device_fp === device_fp,
  }));

  return corsResponse({
    ok: true,
    license: {
      type: license.type,
      max_devices: maxDevices,
      expire_at: license.expire_at,
    },
    bound_devices: devicesWithFlag,
    remaining_slots: Math.max(0, maxDevices - devices.length),
  });
}

/**
 * POST /api/license/heartbeat - 心跳保活
 */
async function handleHeartbeat(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('INVALID_JSON', 400);
  }

  const { code, device_fp, device_name } = body;
  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  const result = await env.DB.prepare(
    `UPDATE device_bindings SET last_seen = datetime('now'), device_name = ? 
     WHERE code = ? AND device_fp = ? AND status = ?`
  ).bind(device_name || 'Unknown', code, device_fp, 'active').run();

  if (result.changes === 0) {
    return errorResponse('NOT_FOUND', 404);
  }

  return corsResponse({ ok: true, next_heartbeat_hours: 24 });
}

/**
 * POST /api/license/verify - 离线降级验证
 */
async function handleVerify(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('INVALID_JSON', 400);
  }

  const { code, device_fp } = body;
  if (!code || !device_fp) {
    return errorResponse('MISSING_PARAMS', 400);
  }

  // 1. 本地验签
  try {
    await verifyLicenseCode(code, HMAC_SECRET);
  } catch {
    return corsResponse({ ok: true, valid: false, reason: 'SIGNATURE_INVALID' });
  }

  // 2. 查绑定
  const binding = await env.DB.prepare(
    'SELECT * FROM device_bindings WHERE code = ? AND device_fp = ? AND status = ?'
  ).bind(code, device_fp, 'active').first();

  if (!binding) {
    return corsResponse({ ok: true, valid: false, reason: 'DEVICE_NOT_BOUND' });
  }

  // 3. 查码状态
  const license = await env.DB.prepare(
    'SELECT status FROM licenses WHERE code = ?'
  ).bind(code).first();

  const status = license ? license.status : 'unknown';

  return corsResponse({
    ok: true,
    valid: status !== 'revoked',
    is_pro: true,
    device_active: true,
  });
}
