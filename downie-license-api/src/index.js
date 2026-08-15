import express from 'express';
import cors from 'cors';
import { loadConfig } from './config.js';
import { createPool } from './db.js';
import { registerLicenseRoutes } from './routes/license.js';

const config = loadConfig();
const pool = await createPool();

const app = express();
app.use(cors());          // 桌面应用无浏览器同源限制，开放 CORS 无妨
app.use(express.json());  // 解析 JSON 请求体

registerLicenseRoutes(app, pool);

// 统一错误处理：兜底任何未捕获的同步/异步错误
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error('[license-api] 未处理错误:', err);
  res.status(500).json({ ok: false, error: 'INTERNAL_ERROR', message: '服务器内部错误' });
});

app.listen(config.port, () => {
  console.log(`[license-api] listening on http://0.0.0.0:${config.port}`);
});
