# 多产品授权迁移 Runbook（Downie6 + launch）

> 适用：把现有线上库升级到带 `products` / `trials` / `releases` 的版本。
> 原则：只加表/加列，不删旧表；旧 Downie6 客户端必须保持可用。

## 1. 上线前备份

```bash
# 在服务器上执行（数据库名按 .env 的 DB_NAME）
mysqldump -u<user> -p --single-transaction --routines --triggers <db_name> \
  > /home/downie_test/backup_$(date +%Y%m%d_%H%M%S).sql
```

同时备份：

- `services/api/.env`（新增 `RELEASE_TOKEN` 前）
- `services/api/static/admin/`（旧后台构建产物）
- 如果服务器上有旧版 `services/api` 代码，先打一个 tar 包。

## 2. 执行迁移

```bash
cd /home/downie_test/services/api
mysql -u<user> -p <db_name> < sql/migrations/20261106_multi_product.sql
```

迁移是幂等的，可重复执行。执行后检查：

```sql
SELECT id, code, name, trial_days, default_max_devices FROM products;
SELECT COUNT(*) FROM licenses WHERE product_id = 1;
SELECT COUNT(*) FROM trials;
SELECT COUNT(*) FROM trial_devices;
-- trials 行数应 >= trial_devices 行数（迁移把旧表归到 Downie6）
```

## 3. 部署新代码

1. 拉取包含以下改动的代码：
   - `app/modules/license/{models,service,router}.py`
   - `app/modules/admin/routers/{cards,products}.py`
   - `app/main.py`、`app/config.py`
   - `scripts/init_db.py`
2. 在 `.env` 增加：

```ini
RELEASE_TOKEN=<一段长随机字符串>
```

3. 重启：

```bash
pm2 restart api
curl http://127.0.0.1:3000/health
```

4. 如果菜单里没有“产品管理”，跑一次：

```bash
.venv/bin/python scripts/init_db.py
```

## 4. 部署管理后台

```bash
cd apps/admin-web
pnpm build
# 把 dist/ 同步到 services/api/static/admin/
```

后台菜单里应出现“产品管理”；卡密页应出现产品筛选/产品列。

## 5. 验证旧 Downie6 兼容

用旧版 v2.0.52 安装包验证：

- 启动试用：`POST /api/license/trial/start`（不带 product）成功
- 激活：邮箱 + 卡密成功
- 设备列表/解绑正常
- 更新检查：`GET /api/version/latest` 仍返回版本信息

## 6. 验证 launch

- 生成一张 `launch` 产品卡密。
- 在 launch 的授权窗口输入邮箱 + 卡密。
- 检查：

```sql
SELECT code, product_id, status, email FROM licenses ORDER BY created_at DESC LIMIT 5;
SELECT code, product_id, device_fp, status FROM device_bindings ORDER BY bound_at DESC LIMIT 5;
SELECT product_id, device_fp, trial_end FROM trials ORDER BY last_seen DESC LIMIT 5;
```

- 同一台 Mac 上 Downie6 与 launch 的 `trials` 应是两行（product_id 不同）。
- 在 Downie6 里激活 launch 卡密应返回 `INVALID_CODE`。

## 7. 配置 CI 发布

OSS Bucket 需要给以下前缀开匿名 `GetObject`（Bucket 本体保持私有）：

- `downie6/`
- `launch/`
- 旧兼容：`releases/`

如果只开了旧的 `releases/*`，新路径会 403；上传成功但客户端下载不到。

GitHub Secrets：

| Secret | 用途 |
|---|---|
| `OSS_ACCESS_KEY_ID` / `OSS_ACCESS_KEY_SECRET` | OSS 上传 |
| `RELEASE_TOKEN` | 调用 `/api/internal/releases/publish` |
| `API_BASE` | 可选，默认 `http://8.153.99.239:3000` |
| `BUILD_CERTIFICATE_BASE64` / `BUILD_CERTIFICATE_PASSWORD` / `KEYCHAIN_PASSWORD` | Downie6/launch Developer ID 证书 |
| `DEVELOPER_ID_APPLICATION` | 签名身份，如 `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` / `APPLE_TEAM_ID` / `APP_SPECIFIC_PASSWORD` | Downie6/launch 公证 |

Downie6 的 `build.yml` 发布 job 会：

1. 上传版本化 DMG/EXE 和 latest 别名到 OSS；
2. 生成 `downie6/macos/latest.json` / `downie6/windows/latest.json`；
3. 调用发布接口写 `releases` 表。

## 8. 回滚

- 代码回滚：恢复旧版 `services/api`，重启 pm2。
- 数据回滚：恢复 `mysqldump` 备份。
- 新表/新列是增量添加；旧代码不读它们，通常不需要立即删除。
- 旧 `trial_devices` 表保留未删，可用于回滚核对。

## 9. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `INVALID_PRODUCT` | `products` 未迁移/产品被停用 | 检查 `products` 表，跑迁移 |
| 旧客户端激活失败 | `product_id` 回填错误 | 检查 `licenses.product_id = 1` |
| 卡密生成 400 | 未选产品/产品停用 | 后台先选产品；检查产品状态 |
| 版本接口仍返回旧版本 | `releases` 无对应记录 | 检查发布接口调用/`releases` 表 |
| 后台菜单没有产品管理 | 菜单未刷新 | 跑 `scripts/init_db.py`，重新登录 |
