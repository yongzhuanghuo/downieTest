# services/media-api — 视频解析 / 下载 / 去水印服务（FastAPI）

视频解析 / 下载 / 去水印服务。手机端跑不了 ffmpeg/yt-dlp，所有视频处理都在这里完成。

## 前置依赖

- Python 3.10+
- **ffmpeg**（系统级，B站音视频合并、去水印、抽帧都用它）
- 可选：Playwright（视频号等强反爬站点兜底，V1 暂不需要）

```bash
# macOS 装 ffmpeg
brew install ffmpeg
```

## 安装运行

```bash
cd services/media-api
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

启动后：
- 接口文档：http://127.0.0.1:8000/docs
- 健康检查：http://127.0.0.1:8000/health

## API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/parse` | `{url}` → 标题/封面/作者/时长/清晰度列表 |
| POST | `/api/download` | `{url, format_id}` → `{task_id}` |
| GET | `/api/task/{id}` | 轮询进度 `{status, progress, result_url}` |
| POST | `/api/delogo/preview` | 上传视频(multipart `file`) → `{video_id, video_url}` |
| POST | `/api/delogo/frame` | `{video_id, timestamp}` → `{frame_url}` |
| POST | `/api/delogo/process` | `{video_id, segments}` → `{task_id}` |

下载结果通过 `/files/*` 静态访问，临时文件（上传视频、抽帧图）通过 `/tmp/*` 访问。

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `DOWNLOAD_DIR` | `backend/downloads` | 下载结果目录 |
| `TEMP_DIR` | `backend/tmp` | 临时文件目录 |
| `PUBLIC_BASE_URL` | `http://127.0.0.1:8000` | 对外 base url（部署时改成域名） |

## 已知限制（V1）

- 任务状态存内存，进程重启丢失（后续换 Celery + Redis）。
- 抖音/B站专用解析器（A-Bogus 签名 / WBI 参数）尚未实现，当前统一走 yt-dlp 通用解析；强反爬站点可能失败。
- 去水印 `blur` 仅支持单框、`crop` 裁边未实现，默认用 `delogo`。
- 视频号不支持（yt-dlp 支持弱，需登录态，已排除在 V1 外）。
