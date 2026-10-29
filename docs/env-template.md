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
# 仅首次建 admin 账号的初始密码（跑 init_db.py 时用）；建完后登录走数据库，改密码在后台
ADMIN_PASSWORD=改成初始密码
# JWT 签名密钥：一段长随机字符串，泄露了 token 可被伪造（登录/刷新 token 都用它）
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
# 开通步骤见 docs/aliyun-oss.md；OSS_ENDPOINT 必须与 bucket 实际区域一致
# （本仓库 bucket 4kdownlebucket 在上海区：oss-cn-shanghai.aliyuncs.com，填错会静默降级本地存储）
OSS_ENDPOINT=
OSS_ACCESS_KEY_ID=
OSS_ACCESS_KEY_SECRET=
OSS_BUCKET=
OSS_PUBLIC_BASE_URL=

# ============ 联系支持（客户端提交，服务端 SMTP 转发）============
# 客户端「联系支持」发到 /api/support/report，由服务端转发；不依赖用户邮件客户端。
# 以 QQ 邮箱为例：SMTP_HOST=smtp.qq.com SMTP_PORT=465 SMTP_SSL=true，
# SMTP_USER=支持邮箱，SMTP_PASSWORD=邮箱授权码（不是登录密码）。
# 不配置时接口返回 503，客户端自动回退到「复制报告 / 邮件客户端」。
SUPPORT_EMAIL_TO=huoyongzhuang@qq.com
SMTP_HOST=
SMTP_PORT=465
SMTP_USER=
SMTP_PASSWORD=
# 留空则用 SMTP_USER
SMTP_FROM=
# 465 用隐式 SSL；587 改成 SMTP_SSL=false + SMTP_STARTTLS=true
SMTP_SSL=true
SMTP_STARTTLS=false

# ============ App 版本推送（桌面端启动查 /api/version/latest）============
# 发新版：CI 打 tag 自动把固定名安装包覆盖传 OSS（.github/workflows/build.yml），
# 这里改 LATEST_VERSION / LATEST_BUILD / CHANGELOG 后 pm2 restart api 即生效；
# DOWNLOAD_URL_* 指向 OSS 固定地址，配一次不用再动
LATEST_VERSION=2.0.0
LATEST_BUILD=1
DOWNLOAD_URL_MACOS=https://4kdownlebucket.oss-cn-shanghai.aliyuncs.com/releases/4KDownle-macos.dmg
DOWNLOAD_URL_WINDOWS=https://4kdownlebucket.oss-cn-shanghai.aliyuncs.com/releases/4KDownle-Windows-Setup.exe
CHANGELOG=
FORCE_UPDATE=false
```

## 必填 vs 可选

| 键 | 必填 | 说明 |
|---|---|---|
| `DB_USER` / `DB_PASSWORD` / `DB_NAME` | 是 | 连不上库建表/启动都失败 |
| `JWT_SECRET` | 是 | 缺了登录 token 能被伪造 |
| `ADMIN_PASSWORD` | 建议 | 首次建 admin 账号的初始密码，缺了退回 `admin123` |
| `REDIS_*` | 否 | 默认 `127.0.0.1:6379` 无密码 |
| `OSS_*` | 否 | 不配则上传/产物走本地，不转存 OSS |
| `LATEST_*` / `DOWNLOAD_URL_*` | 否 | 不配则客户端检查更新永远视为已最新 |
| 其余媒体项 | 否 | 都有默认值 |

> 账号本身固定 `admin`（seed 写死），没有 `ADMIN_USERNAME` 这个配置了。
