import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import cors from 'cors';
import { loadConfig } from './config.js';
import { createPool } from './db.js';
import { registerLicenseRoutes } from './routes/license.js';
import { registerAdminRoutes } from './routes/admin.js';

const config = loadConfig();

// 启动时连不上数据库要给出清晰提示并退出，避免 pm2 反复拉起产生一堆 unhandledRejection
let pool;
try {
  pool = await createPool();
} catch (e) {
  console.error('[license-api] 数据库连接失败，请检查：');
  console.error('  1. MySQL 是否已启动：systemctl status mysql');
  console.error('  2. 数据库/用户是否已创建（见 DEPLOY.md 第一步）：');
  console.error('     CREATE DATABASE downie_license ...  /  CREATE USER downie ...');
  console.error('  3. .env 的 DB_NAME / DB_USER / DB_PASSWORD 是否与上面一致');
  console.error('原始错误:', e.message || e);
  process.exit(1);
}

const app = express();
app.use(cors());          // 桌面应用无浏览器同源限制，开放 CORS 无妨
app.use(express.json());  // 解析 JSON 请求体

registerLicenseRoutes(app, pool);

// 激活码管理后台：接口 + 静态页面托管（同一个进程，无需额外前端服务）
registerAdminRoutes(app, pool);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
app.use('/admin', express.static(path.join(__dirname, '..', 'admin')));

// 统一错误处理：兜底任何未捕获的同步/异步错误
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('[license-api] 未处理错误:', err);
  res.status(500).json({ ok: false, error: 'INTERNAL_ERROR', message: '服务器内部错误' });
});

app.listen(config.port, () => {
  console.log(`[license-api] listening on http://0.0.0.0:${config.port}`);
});
