# 服务器访问与发版路径（内部）

> 本文件不记录明文密码或私钥。私钥只保存在操作者本机 `~/.ssh/4kdownle_deploy`。

- **主机**：`8.153.99.239`
- **用户**：`root`
- **SSH key**：`~/.ssh/4kdownle_deploy`（本机）
- **项目路径**：`/home/downie_test`
- **API 路径**：`/home/downie_test/services/api`
- **进程管理**：`pm2 restart api`
- **版本配置**：`/home/downie_test/services/api/.env`
  - `LATEST_VERSION`
  - `LATEST_BUILD`
  - `CHANGELOG`
  - `FORCE_UPDATE`

## 发版顺序

1. 改 `apps/desktop/pubspec.yaml` 的 `version: x.y.z+N` 和 `apps/desktop/windows/installer/setup.iss` 的 `MyAppVersion`
2. 提交并推 Gitee：`git push origin main`
3. 推 GitHub tag 触发 Actions：`git push github vX.Y.Z`（国内需代理）
4. 等 macOS / Windows 两个 job 成功，OSS 上的固定文件名被覆盖
5. 登录服务器，改 `.env` 的 `LATEST_VERSION` / `LATEST_BUILD` / `CHANGELOG`
6. `pm2 restart api`
7. 验证：
   ```bash
   curl 'http://127.0.0.1:3000/api/version/latest?platform=macos'
   curl 'http://127.0.0.1:3000/api/version/latest?platform=windows'
   ```

## 安全

- 密码/私钥绝不入库。
- 如果密码曾出现在聊天、日志或命令历史中，建议轮换，并只保留 SSH key 登录。
- 服务器上的 `.env` 含数据库、OSS、JWT 等凭据，不要复制到仓库或文档。
