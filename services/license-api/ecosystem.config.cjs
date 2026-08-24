// pm2 启动配置：pm2 start ecosystem.config.cjs
module.exports = {
  apps: [
    {
      name: 'downie-license-api',
      script: 'src/index.js',
      cwd: __dirname,
      instances: 1,
      autorestart: true,
      max_memory_restart: '200M',
      env: { NODE_ENV: 'production' },
    },
  ],
};
