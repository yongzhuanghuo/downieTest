import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPool } from '../src/db.js';

/**
 * 建表脚本：读 sql/schema.sql 并逐条执行。
 * 用法：node scripts/init-db.js
 * 前提：数据库和用户已创建（见 DEPLOY.md），.env 已配置。
 */
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const schemaPath = path.join(__dirname, '..', 'sql', 'schema.sql');
const schema = fs.readFileSync(schemaPath, 'utf8');

// 按分号拆成单条语句（本 schema 无存储过程，不会误拆）
const statements = schema
  .split(';')
  .map((s) => s.trim())
  .filter((s) => s.length > 0);

const pool = await createPool();
try {
  for (const stmt of statements) {
    await pool.query(stmt);
  }
  console.log('✅ 数据表已创建/更新');
} finally {
  await pool.end();
}
