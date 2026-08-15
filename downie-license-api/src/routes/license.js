import { randomUUID } from 'node:crypto';
import { normalizeCode } from '../license.js';

const MONTHLY_UNBIND_LIMIT = 2;

/**
 * 授权相关路由。
 * 所有接口都返回统一结构：{ ok: boolean, error?, message?, ... }
 */
export function registerLicenseRoutes(app, pool) {
  // 健康检查
  app.get('/', (_req, res) => {
    res.json({ service: 'Downie License API', version: '2.0.0', status: 'ok' });
  });

  /**
   * POST /api/license/activate 激活（绑定设备）
   * body: { code, device_fp, device_name? }
   */
  app.post('/api/license/activate', async (req, res, next) => {
    try {
      const { code, device_fp, device_name } = req.body || {};
      if (!code || !device_fp) {
        return res.status(400).json({ ok: false, error: 'MISSING_PARAMS' });
      }
      const normalized = normalizeCode(code);

      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();
        // 锁住码对应的行，串行化同一码的并发激活，避免超绑
        const [rows] = await conn.execute(
          'SELECT * FROM licenses WHERE code = ? FOR UPDATE',
          [normalized],
        );
        const license = rows[0];

        if (!license) {
          await conn.rollback();
          return res.status(400).json({ ok: false, error: 'INVALID_CODE', message: '激活码无效' });
        }
        if (license.status === 'revoked') {
          await conn.rollback();
          return res.status(403).json({ ok: false, error: 'LICENSE_REVOKED', message: '该激活码已被吊销' });
        }

        const [boundRows] = await conn.execute(
          "SELECT * FROM device_bindings WHERE code = ? AND status = 'active'",
          [normalized],
        );
        const payload = {
          type: license.type,
          max_devices: license.max_devices,
          expire_at: license.expire_at,
        };

        // 幂等：本设备已绑定，直接返回成功
        const existing = boundRows.find((d) => d.device_fp === device_fp);
        if (existing) {
          await conn.commit();
          return res.json({
            ok: true,
            license: payload,
            device: existing,
            bound_count: boundRows.length,
            remaining_slots: Math.max(0, license.max_devices - boundRows.length),
          });
        }

        // 设备数检查
        if (boundRows.length >= license.max_devices) {
          await conn.commit();
          return res.status(403).json({
            ok: false,
            error: 'DEVICE_LIMIT_REACHED',
            message: `已绑定 ${boundRows.length}/${license.max_devices} 台设备，请先解绑旧设备`,
            bound_devices: boundRows,
          });
        }

        // 写入绑定
        const id = randomUUID();
        await conn.execute(
          'INSERT INTO device_bindings (id, code, device_fp, device_name) VALUES (?, ?, ?, ?)',
          [id, normalized, device_fp, device_name || 'Unknown'],
        );
        await conn.execute(
          "UPDATE licenses SET status = 'activated' WHERE code = ? AND status = 'unused'",
          [normalized],
        );
        await conn.commit();

        return res.json({
          ok: true,
          license: payload,
          device: { id, device_fp, device_name: device_name || 'Unknown', bound_at: new Date().toISOString() },
          bound_count: boundRows.length + 1,
          remaining_slots: Math.max(0, license.max_devices - boundRows.length - 1),
        });
      } catch (e) {
        await conn.rollback().catch(() => {});
        throw e;
      } finally {
        conn.release();
      }
    } catch (e) {
      next(e);
    }
  });

  /**
   * POST /api/license/unbind 解绑设备
   * body: { code, device_fp }
   */
  app.post('/api/license/unbind', async (req, res, next) => {
    try {
      const { code, device_fp } = req.body || {};
      if (!code || !device_fp) {
        return res.status(400).json({ ok: false, error: 'MISSING_PARAMS' });
      }
      const normalized = normalizeCode(code);

      const [licRows] = await pool.execute('SELECT * FROM licenses WHERE code = ?', [normalized]);
      const license = licRows[0];
      if (!license) {
        return res.status(400).json({ ok: false, error: 'INVALID_CODE', message: '激活码无效' });
      }

      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();

        // 月限检查：近 30 天解绑次数
        const [monthUnbinds] = await conn.execute(
          'SELECT * FROM unbind_log WHERE code = ? AND unbound_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)',
          [normalized],
        );
        if (monthUnbinds.length >= MONTHLY_UNBIND_LIMIT) {
          await conn.rollback();
          return res.status(429).json({
            ok: false,
            error: 'UNBIND_LIMIT_EXCEEDED',
            message: '本月解绑次数已用完（2/2），下月可继续操作',
          });
        }

        const [devRows] = await conn.execute(
          "SELECT device_name FROM device_bindings WHERE code = ? AND device_fp = ? AND status = 'active'",
          [normalized, device_fp],
        );
        const deviceName = devRows[0]?.device_name || 'Unknown';

        await conn.execute(
          "UPDATE device_bindings SET status = 'unbound' WHERE code = ? AND device_fp = ? AND status = 'active'",
          [normalized, device_fp],
        );
        await conn.execute(
          'INSERT INTO unbind_log (id, code, device_fp, device_name) VALUES (?, ?, ?, ?)',
          [randomUUID(), normalized, device_fp, deviceName],
        );
        await conn.commit();

        const [remaining] = await pool.execute(
          "SELECT * FROM device_bindings WHERE code = ? AND status = 'active'",
          [normalized],
        );
        return res.json({
          ok: true,
          message: '设备已解绑',
          remaining_slots: Math.max(0, license.max_devices - remaining.length),
        });
      } catch (e) {
        await conn.rollback().catch(() => {});
        throw e;
      } finally {
        conn.release();
      }
    } catch (e) {
      next(e);
    }
  });

  /**
   * GET /api/license/status?code=XXX&device_fp=YYY 查询状态
   */
  app.get('/api/license/status', async (req, res, next) => {
    try {
      const code = req.query.code;
      const deviceFp = req.query.device_fp;
      if (!code) {
        return res.status(400).json({ ok: false, error: 'MISSING_CODE' });
      }
      const normalized = normalizeCode(code);

      const [licRows] = await pool.execute('SELECT * FROM licenses WHERE code = ?', [normalized]);
      const license = licRows[0];
      if (!license) {
        return res.status(404).json({ ok: false, error: 'NOT_FOUND' });
      }

      const [devices] = await pool.execute(
        "SELECT * FROM device_bindings WHERE code = ? AND status = 'active' ORDER BY bound_at",
        [normalized],
      );
      const boundDevices = devices.map((d) => ({ ...d, is_current: d.device_fp === deviceFp }));

      return res.json({
        ok: true,
        license: { type: license.type, max_devices: license.max_devices, expire_at: license.expire_at },
        bound_devices: boundDevices,
        remaining_slots: Math.max(0, license.max_devices - devices.length),
      });
    } catch (e) {
      next(e);
    }
  });

  /**
   * POST /api/license/heartbeat 心跳保活
   * body: { code, device_fp, device_name? }
   */
  app.post('/api/license/heartbeat', async (req, res, next) => {
    try {
      const { code, device_fp, device_name } = req.body || {};
      if (!code || !device_fp) {
        return res.status(400).json({ ok: false, error: 'MISSING_PARAMS' });
      }
      const normalized = normalizeCode(code);

      const [result] = await pool.execute(
        "UPDATE device_bindings SET last_seen = NOW(), device_name = ? WHERE code = ? AND device_fp = ? AND status = 'active'",
        [device_name || 'Unknown', normalized, device_fp],
      );
      if (result.affectedRows === 0) {
        return res.status(404).json({ ok: false, error: 'NOT_FOUND' });
      }
      return res.json({ ok: true, next_heartbeat_hours: 24 });
    } catch (e) {
      next(e);
    }
  });

  /**
   * POST /api/license/verify 离线降级验证（客户端暂未接入，保留接口）
   * body: { code, device_fp }
   */
  app.post('/api/license/verify', async (req, res, next) => {
    try {
      const { code, device_fp } = req.body || {};
      if (!code || !device_fp) {
        return res.status(400).json({ ok: false, error: 'MISSING_PARAMS' });
      }
      const normalized = normalizeCode(code);

      const [licRows] = await pool.execute('SELECT * FROM licenses WHERE code = ?', [normalized]);
      const license = licRows[0];
      if (!license) {
        return res.json({ ok: true, valid: false, reason: 'INVALID_CODE' });
      }

      const [bindRows] = await pool.execute(
        "SELECT * FROM device_bindings WHERE code = ? AND device_fp = ? AND status = 'active'",
        [normalized, device_fp],
      );
      if (!bindRows[0]) {
        return res.json({ ok: true, valid: false, reason: 'DEVICE_NOT_BOUND' });
      }

      return res.json({
        ok: true,
        valid: license.status !== 'revoked',
        is_pro: true,
        device_active: true,
      });
    } catch (e) {
      next(e);
    }
  });
}
