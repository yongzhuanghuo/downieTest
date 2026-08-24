# 授权后端部署指南（MySQL + Node.js）

后端从 Cloudflare Workers 迁移到自建 Linux 服务器（2 核 2G 阿里云）。技术栈：
Node.js 20 + Express + MySQL 8.0 + mysql2，激活码为「数据库随机码」方案。

---

## 一、服务器环境安装（Ubuntu 22.04/24.04）

```bash
# 1. 系统更新
sudo apt update && sudo apt upgrade -y

# 2. 安装 Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v    # 应输出 v20.x

# 3. 安装 MySQL 8.0
sudo apt install -y mysql-server
sudo systemctl enable --now mysql
sudo mysql_secure_installation   # 按提示设置 root 密码，其余回车即可

# 4. 创建数据库和专用用户（把「你的强密码」换成真实密码）
sudo mysql -u root -p <<'SQL'
CREATE DATABASE downie_license CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'downie'@'localhost' IDENTIFIED BY '你的强密码';
GRANT ALL PRIVILEGES ON downie_license.* TO 'downie'@'localhost';
FLUSH PRIVILEGES;
SQL

# 5. 安装 pm2（进程守护）
sudo npm i -g pm2
```

**⚠️ 阿里云安全组**：登录阿里云控制台 → 云服务器 → 安全组，**放行 3000 端口**（授权 API 用）。
MySQL 的 3306 端口**不要**放行，只允许 localhost 访问最安全。

---

## 二、部署后端代码

```bash
# 1. 上传代码到服务器（用 git / scp / rz 均可），假设放到 ~/downie-license-api
cd ~/downie-license-api

# 2. 安装依赖
npm install

# 3. 创建 .env（复制模板并填真实密码）
cp .env.example .env
vim .env          # 把 DB_PASSWORD 改成第 4 步设置的密码

# 4. 建表
npm run init-db

# 5. 生成激活码（例如 10 个 PRO 永久版，输出到 pro.csv）
npm run generate -- -c 10 -t perpetual -o pro.csv
# 查看生成的码
cat pro.csv

# 6. 用 pm2 启动并设置开机自启
pm2 start ecosystem.config.cjs
pm2 save
pm2 startup    # 按提示执行它输出的那条命令
```

---

## 三、验证

```bash
# 健康检查（本机）
curl http://127.0.0.1:3000/
# → {"service":"Downie License API","version":"2.0.0","status":"ok"}

# 从外网/本机用生成的码测试激活（把 XXXX-XXXX-XXXX-XXXX 换成真实码）
curl -X POST http://127.0.0.1:3000/api/license/activate \
  -H 'Content-Type: application/json' \
  -d '{"code":"XXXXX-XXXXX-XXXXX-XXXXX","device_fp":"test-device-123"}'
# → {"ok":true,"license":{"type":"perpetual","max_devices":4,"expire_at":null},...}

# 用随机码测试应返回无效
curl -X POST http://127.0.0.1:3000/api/license/activate \
  -H 'Content-Type: application/json' \
  -d '{"code":"AAAAA-BBBBB-CCCCC-DDDDD","device_fp":"x"}'
# → {"ok":false,"error":"INVALID_CODE",...}
```

---

## 四、客户端配置

在 Flutter 项目里，把授权后端地址改成你的服务器：

1. 编辑 [lib/core/license/license_client.dart](../apps/desktop/lib/core/license/license_client.dart) 顶部，
   或构建时用 `--dart-define` 覆盖（无需改源码）：

```bash
flutter build macos --dart-define=API_BASE=http://你的服务器IP:3000
```

2. 重新打包发布。

---

## 五、后续上 HTTPS（可选）

等你有域名后（国内需 ICP 备案），用 Nginx + Let's Encrypt：

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
# 参考 nginx.conf.example 配置反向代理到 127.0.0.1:3000
sudo certbot --nginx -d your-domain.com
```

然后把客户端 `API_BASE` 改成 `https://your-domain.com` 重新发布即可。
此时后端代码无需任何改动。

---

## 附：常用运维命令

```bash
pm2 status                 # 查看进程状态
pm2 logs downie-license-api  # 查看日志
pm2 restart downie-license-api  # 重启
pm2 delete downie-license-api   # 停止并删除

# 手动生成/吊销激活码
node scripts/generate-licenses.js -c 5 -t perpetual          # 生成 5 个 PRO 码
mysql -u root -p downie_license -e "UPDATE licenses SET status='revoked' WHERE code='XXXXX...'"
```

## 附：激活码参数说明

- `-t free` 免费版（1 设备），`-t perpetual` PRO 永久版（4 设备，默认）
- `-d 8` 自定义最大设备数
- `-e 30` 过期天数（默认 0 = 永不过期）
