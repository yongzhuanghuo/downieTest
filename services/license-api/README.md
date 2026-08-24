# license-api — 授权服务（Node.js + Express + MySQL）

激活码 / 设备绑定 / 管理后台。**多端共享服务**，不属于任何单一客户端。

- 目前接入方：`apps/desktop`（Flutter 桌面端，见 [license_client.dart](../../apps/desktop/lib/core/license/license_client.dart)）
- 尚未接入：`apps/mobile`、`apps/harmony-pc`

部署步骤见 [docs/deploy.md](../../docs/deploy.md)。

---

## 目录结构

```
services/license-api/
├── src/
│   ├── index.js                  # Express 入口 + 启动（监听 3000 端口）
│   ├── config.js                 # 读 .env（端口 + MySQL + admin 账号）
│   ├── db.js                     # mysql2 连接池 + 启动 ping 验证
│   ├── license.js                # 激活码工具（随机码生成/规范化/格式化）
│   └── routes/
│       ├── license.js            # 5 个接口：激活/解绑/状态/心跳/验证
│       │                          #   - activate: 查码→设备数检查(事务+FOR UPDATE)→绑定
│       │                          #   - unbind: 解绑→记日志
│       │                          #   - status: 设备列表 + 剩余名额
│       │                          #   - heartbeat: 更新 last_seen
│       │                          #   - verify: 离线降级验证
│       └── admin.js              # 管理后台 API（JWT 认证）：登录/统计/列表/生成/详情/吊销/恢复/导出
├── admin/
│   └── index.html                # 卡密管理后台单页（原生 HTML/CSS/JS，无构建）
├── sql/
│   └── schema.sql                # MySQL 建表语句（licenses/device_bindings/unbind_log）
├── scripts/
│   ├── init-db.js                # 建表脚本（幂等，CREATE TABLE IF NOT EXISTS）
│   └── generate-licenses.js      # 生成激活码（写库 + 导出 CSV）
├── .env.example                  # 环境变量模板（DB + PORT + ADMIN_* + JWT_SECRET）
├── ecosystem.config.cjs          # pm2 启动配置
├── nginx.conf.example            # 后续 HTTPS 反向代理参考
└── package.json                  # 依赖：express / mysql2 / dotenv / cors / jsonwebtoken
```

## 常用命令

全部在本目录（`services/license-api/`）下执行：

```bash
npm install                                          # 装依赖
npm run init-db                                      # 建表（幂等，可重复跑）
npm run generate -- -c 10 -t perpetual -o pro.csv    # 生成 10 个永久激活码
npm run dev                                          # 本地调试
pm2 start ecosystem.config.cjs                       # 生产启动
```

**pm2 进程名是 `downie-license-api`**（来自 `ecosystem.config.cjs` 的 `name` 字段），不随目录改名而变，服务器上的 `pm2 restart downie-license-api` 等命令保持原样。

## 非显而易见的注意点

- **所有配置走 `.env`，无默认值**：`src/config.js` 用 `required()` 强制校验，缺任一项直接启动失败。`.env` 不进库，参照 `.env.example`。
- **防超绑靠数据库事务**：`activate` 用 `SELECT ... FOR UPDATE` 锁行后再检查设备数，不是应用层判断，并发激活不会超出名额。
- **客户端不验签**：客户端只把 `code + device_fp` 发过来，完全信任服务端返回的负载，本地无密钥、无签名校验。安全边界在服务端。
- **管理后台与 API 同进程**：`src/index.js` 用 `express.static` 托管 `admin/index.html`，访问 `http://<服务器IP>:3000/admin/`，不需要单独跑前端服务。
- **生成的 CSV 含真实激活码**，已在 `.gitignore` 里忽略（`services/license-api/*.csv`），别手动 `git add -f`。
