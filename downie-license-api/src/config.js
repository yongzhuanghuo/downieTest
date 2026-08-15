import 'dotenv/config';

/**
 * 读取环境变量配置。
 * 配置项都在 .env 里（参考 .env.example）。
 */
export function loadConfig() {
  const required = (key) => {
    const v = process.env[key];
    if (!v) throw new Error(`缺少环境变量 ${key}，请在 .env 中配置（参考 .env.example）`);
    return v;
  };

  return {
    port: Number(process.env.PORT || 3000),
    db: {
      host: process.env.DB_HOST || '127.0.0.1',
      port: Number(process.env.DB_PORT || 3306),
      user: required('DB_USER'),
      password: required('DB_PASSWORD'),
      database: required('DB_NAME'),
    },
  };
}
