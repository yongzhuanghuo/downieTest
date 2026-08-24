import mysql from 'mysql2/promise';
import { loadConfig } from './config.js';

/**
 * 创建 MySQL 连接池，并在启动时 ping 一次验证可用。
 */
export async function createPool() {
  const { db } = loadConfig();
  const pool = mysql.createPool({
    host: db.host,
    port: db.port,
    user: db.user,
    password: db.password,
    database: db.database,
    waitForConnections: true,
    connectionLimit: 10,
    connectTimeout: 10000,     // 连接超时 10s，快速失败而非无限挂起
    enableKeepAlive: true,     // TCP keepalive，减少跨网络下的假死连接
    keepAliveInitialDelay: 0,
    charset: 'utf8mb4',
  });

  // 启动时验证连接，连不上直接抛错退出，避免带着坏连接上线
  const conn = await pool.getConnection();
  await conn.ping();
  conn.release();

  return pool;
}
