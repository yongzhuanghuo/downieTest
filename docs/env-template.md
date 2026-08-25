# services/api/.env 完整模板

复制下面全部内容到 `services/api/.env`，把「改成xxx」的占位符替换成真实值。

```ini
# ============ 服务 ============
PORT=3000
# 挂载模块：license,admin,media（逗号分隔，默认全开；境外媒体节点可 MODULES=media）
MODULES=license,admin,media

# ============ MySQL（授权）============
# 在阿里云服务器上跑时，DB_HOST 保持 127.0.0.1（指向本机 Docker MySQL）
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=改成你的数据库用户
DB_PASSWORD=改成你的数据库密码
DB_NAME=改成你的数据库名

# ============ Redis（任务队列 / 频控）============
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# ============ 管理后台 ============
ADMIN_USERNAME=admin
ADMIN_PASSWORD=改成你的后台登录密码
# JWT 签名密钥：一段长随机字符串，泄露了 token 可被伪造
JWT_SECRET=改成一段长随机字符串

# ============ 媒体 ============
# 对外 base url（部署时改成真实域名，用于拼接直链）
PUBLIC_BASE_URL=http://127.0.0.1:8000
# 单个视频上传大小上限（字节，默认 2GB）
MAX_UPLOAD_SIZE=2147483648
# CORS 白名单，逗号分隔；默认 * 全放开
ALLOWED_ORIGINS=*
# /files /tmp 是否强制签名 URL：0 关（本地开发）1 开（公网部署）
SIGNED_URLS=0
# 并发媒体任务数（默认按 CPU 核数 / 2）
MEDIA_CONCURRENCY=2
# yt-dlp 全局代理（境内部署抓 YouTube 用，如 http://127.0.0.1:7890，空 = 不走代理）
YTDLP_PROXY=
# 下载/临时目录（默认 services/api/downloads、tmp，一般不用改）
# DOWNLOAD_DIR=
# TEMP_DIR=

# ============ 阿里云 OSS（可选，不配则本地降级）============
# 开通步骤见 docs/aliyun-oss.md
OSS_ENDPOINT=
OSS_ACCESS_KEY_ID=
OSS_ACCESS_KEY_SECRET=
OSS_BUCKET=
OSS_PUBLIC_BASE_URL=
```

## 必填 vs 可选

| 键 | 必填 | 说明 |
|---|---|---|
| `DB_USER` / `DB_PASSWORD` / `DB_NAME` | 是 | 连不上库建表/启动都失败 |
| `JWT_SECRET` | 是 | 缺了登录 token 能被伪造 |
| `ADMIN_PASSWORD` | 建议 | 缺了默认账号密码退回 `admin123` |
| `ADMIN_USERNAME` | 否 | 默认 `admin` |
| `REDIS_*` | 否 | 默认 `127.0.0.1:6379` 无密码 |
| `OSS_*` | 否 | 不配则上传/产物走本地，不转存 OSS |
| 其余媒体项 | 否 | 都有默认值 |
