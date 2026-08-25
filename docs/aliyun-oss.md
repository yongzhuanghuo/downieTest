# 阿里云 OSS 开通与配置指南

手机端上传 / 产物走**后端中转转存**：前端 → `services/api`（multipart）→ 后端处理 → 转存 OSS → 返回直链。
你只需要开通 OSS 并把 `OSS_*` 填进 `.env`，代码已就位，未配置时后端自动降级本地。

## 1. 开通 OSS + 建 Bucket

1. 登录阿里云控制台 → 对象存储 OSS → 开通。
2. 创建 Bucket：
   - **Bucket 名称**：全局唯一，如 `4kdownle-media`
   - **地域**：选离用户近的（如 `华东1（杭州）`，对应 endpoint `oss-cn-hangzhou.aliyuncs.com`）
   - **读写权限**：选 **公共读**（因为要直链下载视频/图片；敏感文件不要放这个 bucket）
3. 记下 **Endpoint**（地域对应的公网 endpoint）。

## 2. 创建 AccessKey（强烈建议用 RAM 子账号，不要用主账号 AK）

1. 控制台 → 访问控制 RAM → 用户 → 创建用户（编程访问）。
2. 创建后保存 **AccessKeyId + AccessKeySecret**（Secret 只显示一次）。
3. 给该用户授权最小权限策略（只允许操作这一个 Bucket）：
   ```json
   {
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["oss:PutObject", "oss:GetObject", "oss:ListObjects"],
         "Resource": ["acs:oss:*:*:你的Bucket名", "acs:oss:*:*:你的Bucket名/*"]
       }
     ],
     "Version": "1"
   }
   ```

## 3. 配置 `.env`

在 `services/api/.env` 加：

```ini
OSS_ENDPOINT=oss-cn-hangzhou.aliyuncs.com
OSS_ACCESS_KEY_ID=你的AccessKeyId
OSS_ACCESS_KEY_SECRET=你的AccessKeySecret
OSS_BUCKET=4kdownle-media
OSS_PUBLIC_BASE_URL=https://4kdownle-media.oss-cn-hangzhou.aliyuncs.com
```

- `OSS_PUBLIC_BASE_URL` 是拼直链用的域名：先用 Bucket 公网域名，绑了 CDN 再换成 CDN 域名。
- 配完重启 `services/api`（`pm2 restart api`）。

## 4.（可选）绑定 CDN 加速

1. 阿里云 CDN → 添加域名 → 源站选 OSS Bucket。
2. 域名解析后，把 `OSS_PUBLIC_BASE_URL` 换成 `https://你的CDN域名`，代码不用改。
3. 若用私有 Bucket + CDN 回源鉴权，需要 OSS 私有读 + CDN 鉴权配置，属于进阶，暂不需要。

## 5. 小程序 / App 端域名白名单

- 微信小程序后台 → 开发管理 → 服务器域名，把 OSS/CDN 域名加入 **downloadFile 合法域名**（保存相册走 `uni.downloadFile`）。
- App/H5 无此限制。

## 验证

```bash
# 上传一个视频，看返回的 video_url / result_url 是否变成 https://...oss... 直链
curl -I "https://4kdownle-media.oss-cn-hangzhou.aliyuncs.com/xxx.mp4"
# 应返回 200
```

## 安全提醒

- **不要把 AccessKey 提交进 git**。`.env` 已在 `.gitignore`。
- Bucket 公共读 = 任何人拿到 URL 都能下载，适合直链分发；不要把含隐私的文件放进去。
