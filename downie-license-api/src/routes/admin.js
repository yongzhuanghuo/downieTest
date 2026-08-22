import jwt from 'jsonwebtoken';
import { generateCode, formatCode } from '../license.js';
import { loadConfig } from '../config.js';

/**
 * 激活码管理后台路由（/admin/api/*）。
 * 所有接口除 login 外都经过 JWT 认证中间件。
 */
export function registerAdminRoutes(app, pool) {
  const config = loadConfig();

  // JWT 认证中间件
  const auth = (req, res, next) => {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
      return res.status(401).json({ ok: false, error: 'UNAUTHORIZED' });
    }
    try {
      jwt.verify(token, config.admin.jwtSecret);
      next();
    } catch (_e) {
      return res.status(401).json({ ok: false, error: 'UNAUTHORIZED' });
    }
  };

  // 撞码重试插入
  async function insertOne({ type, maxDevices, expireAt }) {
    for (let attempt = 0; attempt < 3; attempt++) {
      const raw = generateCode();
      try {
        await pool.execute(
          'INSERT INTO licenses (code, type, max_devices, expire_at) VALUES (?, ?, ?, ?)',
          [raw, type, maxDevices, expireAt],
        );
        return raw;
      } catch (e) {
        if (e.code === 'ER_DUP_ENTRY') continue;
        throw e;
      }
    }
    throw new Error('生成失败：多次撞码，请重试');
  }

  // 登录
  app.post('/admin/api/login', (req, res) => {
    const { username, password } = req.body || {};
    if (username !== config.admin.username || password !== config.admin.password) {
      return res.status(401).json({ ok: false, error: 'INVALID_CREDENTIALS', message: '用户名或密码错误' });
    }
    const token = jwt.sign({ role: 'admin' }, config.admin.jwtSecret, { expiresIn: '24h' });
    res.json({ ok: true, token });
  });

  // 统计
  app.get('/admin/api/stats', auth, async (_req, res, next) => {
    try {
      const [rows] = await pool.execute(`
        SELECT
          COUNT(*) AS total,
          SUM(status = 'unused') AS unused,
          SUM(status = 'activated') AS activated,
          SUM(status = 'revoked') AS revoked,
          SUM(type = 'free') AS free,
          SUM(type = 'perpetual') AS perpetual
        FROM licenses
      `);
      const [dev] = await pool.execute(
        "SELECT COUNT(*) AS c FROM device_bindings WHERE status = 'active'",
      );
      const s = rows[0] || {};
      res.json({
        ok: true,
        stats: {
          total: s.total || 0,
          unused: s.unused || 0,
          activated: s.activated || 0,
          revoked: s.revoked || 0,
          free: s.free || 0,
          perpetual: s.perpetual || 0,
          bound_devices: dev[0]?.c || 0,
        },
      });
    } catch (e) {
      next(e);
    }
  });

  // 卡密列表（分页 + 搜索 + 筛选）
  app.get('/admin/api/licenses', auth, async (req, res, next) => {
    try {
      const page = Math.max(1, parseInt(req.query.page, 10) || 1);
      const pageSize = Math.min(100, Math.max(1, parseInt(req.query.page_size, 10) || 20));
      const search = (req.query.search || '').trim().toUpperCase();
      const status = req.query.status;
      const type = req.query.type;

      const where = [];
      const params = [];
      if (search) {
        where.push('l.code LIKE ?');
        params.push(`%${search}%`);
      }
      if (status && ['unused', 'activated', 'revoked'].includes(status)) {
        where.push('l.status = ?');
        params.push(status);
      }
      if (type && ['free', 'perpetual'].includes(type)) {
        where.push('l.type = ?');
        params.push(type);
      }
      const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : '';

      const [countRows] = await pool.execute(
        `SELECT COUNT(*) AS c FROM licenses l ${whereClause}`,
        params,
      );
      const total = countRows[0]?.c || 0;

      const [rows] = await pool.execute(
        `SELECT l.*,
                (SELECT COUNT(*) FROM device_bindings d WHERE d.code = l.code AND d.status = 'active') AS bound_count
         FROM licenses l ${whereClause}
         ORDER BY l.created_at DESC
         LIMIT ? OFFSET ?`,
        [...params, pageSize, (page - 1) * pageSize],
      );

      res.json({
        ok: true,
        total,
        page,
        page_size: pageSize,
        licenses: rows.map((r) => ({
          ...r,
          formatted: formatCode(r.code),
        })),
      });
    } catch (e) {
      next(e);
    }
  });

  // 生成卡密
  app.post('/admin/api/licenses/generate', auth, async (req, res, next) => {
    try {
      const { type, count, devices, expire_days } = req.body || {};
      const t = type === 'free' ? 'free' : 'perpetual';
      const maxDevices = devices ? parseInt(devices, 10) : (t === 'perpetual' ? 4 : 1);
      const expireDays = parseInt(expire_days, 10) || 0;
      const expireAt = expireDays <= 0 ? null : Date.now() + expireDays * 86400 * 1000;
      const n = Math.min(1000, Math.max(1, parseInt(count, 10) || 1));

      const raws = [];
      for (let i = 0; i < n; i++) {
        raws.push(await insertOne({ type: t, maxDevices, expireAt }));
      }
      res.json({
        ok: true,
        count: raws.length,
        type: t,
        max_devices: maxDevices,
        expire_days: expireDays,
        codes: raws.map(formatCode),
      });
    } catch (e) {
      next(e);
    }
  });

  // 导出 CSV（按筛选）
  app.get('/admin/api/licenses/export', auth, async (req, res, next) => {
    try {
      const search = (req.query.search || '').trim().toUpperCase();
      const status = req.query.status;
      const type = req.query.type;
      const where = [];
      const params = [];
      if (search) {
        where.push('code LIKE ?');
        params.push(`%${search}%`);
      }
      if (status && ['unused', 'activated', 'revoked'].includes(status)) {
        where.push('status = ?');
        params.push(status);
      }
      if (type && ['free', 'perpetual'].includes(type)) {
        where.push('type = ?');
        params.push(type);
      }
      const whereClause = where.length ? `WHERE ${where.join(' AND ')}` : '';

      const [rows] = await pool.execute(
        `SELECT * FROM licenses ${whereClause} ORDER BY created_at DESC`,
        params,
      );
      const lines = ['activation_code,type,max_devices,status,expire_at,created_at'];
      for (const r of rows) {
        lines.push(`${formatCode(r.code)},${r.type},${r.max_devices},${r.status},${r.expire_at ?? 0},${r.created_at}`);
      }
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', 'attachment; filename=licenses.csv');
      // BOM 让 Excel 正确识别 UTF-8
      res.send('﻿' + lines.join('\n') + '\n');
    } catch (e) {
      next(e);
    }
  });

  // 卡密详情（含绑定设备）
  app.get('/admin/api/licenses/:code', auth, async (req, res, next) => {
    try {
      const [licRows] = await pool.execute('SELECT * FROM licenses WHERE code = ?', [req.params.code]);
      const license = licRows[0];
      if (!license) {
        return res.status(404).json({ ok: false, error: 'NOT_FOUND' });
      }
      const [devices] = await pool.execute(
        'SELECT * FROM device_bindings WHERE code = ? ORDER BY bound_at DESC',
        [req.params.code],
      );
      res.json({ ok: true, license: { ...license, formatted: formatCode(license.code) }, devices });
    } catch (e) {
      next(e);
    }
  });

  // 吊销
  app.post('/admin/api/licenses/:code/revoke', auth, async (req, res, next) => {
    try {
      const [r] = await pool.execute("UPDATE licenses SET status = 'revoked' WHERE code = ?", [req.params.code]);
      if (r.affectedRows === 0) {
        return res.status(404).json({ ok: false, error: 'NOT_FOUND' });
      }
      res.json({ ok: true });
    } catch (e) {
      next(e);
    }
  });

  // 恢复
  app.post('/admin/api/licenses/:code/restore', auth, async (req, res, next) => {
    try {
      const [r] = await pool.execute(
        "UPDATE licenses SET status = 'unused' WHERE code = ? AND status = 'revoked'",
        [req.params.code],
      );
      if (r.affectedRows === 0) {
        return res.status(404).json({ ok: false, error: 'NOT_FOUND' });
      }
      res.json({ ok: true });
    } catch (e) {
      next(e);
    }
  });
}
