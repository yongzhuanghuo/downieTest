<template>
  <view class="page">
    <view class="card">
      <text class="status">{{ statusText }}</text>
      <view class="progress-bar">
        <view class="progress-inner" :style="{ width: progress + '%' }" />
      </view>
      <text class="percent">{{ progress }}%</text>
    </view>

    <view v-if="done" class="preview-box">
      <video :src="resultFullUrl" class="preview-video" controls />
    </view>

    <view v-if="done" class="actions">
      <button class="btn-primary" @tap="saveToAlbum">保存到相册</button>
      <button class="btn-plain" @tap="copyLink">复制下载链接</button>
    </view>

    <view v-if="error" class="error-box">
      <text class="error-text">{{ error }}</text>
      <button class="btn-primary" @tap="start">重试</button>
    </view>
  </view>
</template>

<script>
import { api, fullUrl } from '../../api/index.js'

export default {
  data() {
    return {
      url: '',
      title: '',
      formatId: '',
      taskId: '',
      progress: 0,
      status: 'running',
      resultUrl: '',
      error: '',
      timer: null,
    }
  },
  computed: {
    done() {
      return this.status === 'done'
    },
    statusText() {
      if (this.status === 'done') return '✅ 下载完成'
      if (this.status === 'error') return '❌ 下载失败'
      return '正在下载…'
    },
    resultFullUrl() {
      return this.resultUrl ? fullUrl(this.resultUrl) : ''
    },
  },
  onLoad(query) {
    // 模式 1：去水印等已有 task_id 的场景，直接轮询
    if (query.task_id) {
      this.taskId = query.task_id
      this.status = 'running'
      this.upsertHistory('downloading')
      this.poll()
      return
    }
    // 模式 2：下载场景，先提交下载再轮询
    this.url = decodeURIComponent(query.url || '')
    this.title = decodeURIComponent(query.title || '')
    this.formatId = query.format_id || ''
    this.start()
  },
  onUnload() {
    this.clearTimer()
  },
  methods: {
    clearTimer() {
      if (this.timer) {
        clearInterval(this.timer)
        this.timer = null
      }
    },
    async start() {
      this.error = ''
      this.status = 'running'
      this.progress = 0
      try {
        const { task_id } = await api.download(this.url, this.formatId)
        this.taskId = task_id
        this.upsertHistory('downloading')
        this.poll()
      } catch (e) {
        this.error = e.message
        this.status = 'error'
      }
    },
    poll() {
      this.clearTimer()
      this.timer = setInterval(async () => {
        try {
          const t = await api.task(this.taskId)
          this.progress = t.progress || 0
          this.status = t.status
          if (t.status === 'done') {
            this.resultUrl = t.result_url
            this.clearTimer()
            this.upsertHistory('done')
          } else if (t.status === 'error') {
            this.error = t.error || '下载失败'
            this.clearTimer()
            this.upsertHistory('error')
          }
        } catch (e) {
          this.error = e.message
          this.status = 'error'
          this.clearTimer()
        }
      }, 1500)
    },
    saveToAlbum() {
      const u = fullUrl(this.resultUrl)
      // #ifdef H5
      window.open(u)
      // #endif
      // #ifndef H5
      uni.showLoading({ title: '保存中…' })
      uni.downloadFile({
        url: u,
        success: (res) => {
          if (res.statusCode !== 200) {
            uni.hideLoading()
            uni.showToast({ title: '下载文件失败', icon: 'none' })
            return
          }
          uni.saveVideoToPhotosAlbum({
            filePath: res.tempFilePath,
            success: () => {
              uni.hideLoading()
              uni.showToast({ title: '已保存到相册' })
            },
            fail: (e) => {
              uni.hideLoading()
              uni.showToast({ title: '保存失败：' + e.errMsg, icon: 'none' })
            },
          })
        },
        fail: (e) => {
          uni.hideLoading()
          uni.showToast({ title: '下载失败：' + e.errMsg, icon: 'none' })
        },
      })
      // #endif
    },
    copyLink() {
      const u = fullUrl(this.resultUrl)
      uni.setClipboardData({
        data: u,
        success: () => uni.showToast({ title: '链接已复制' }),
      })
    },
    upsertHistory(status) {
      // 按 taskId 去重，持久化下载记录（切走页面后仍可追踪）
      const list = uni.getStorageSync('download_history') || []
      const item = {
        taskId: this.taskId,
        title: this.title || '视频文件',
        url: this.url,
        resultUrl: this.resultUrl || '',
        error: this.error || '',
        status, // downloading / done / error
        progress: this.progress || 0,
        time: Date.now(),
      }
      const idx = list.findIndex((h) => h.taskId === this.taskId)
      if (idx >= 0) {
        list[idx] = { ...item, time: list[idx].time }
      } else {
        list.unshift(item)
      }
      uni.setStorageSync('download_history', list.slice(0, 50))
    },
  },
}
</script>

<style scoped>
.page {
  padding: 24rpx;
}
.card {
  background: #1e1e1e;
  border-radius: 16rpx;
  padding: 40rpx 32rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.status {
  font-size: 32rpx;
  font-weight: 600;
  margin-bottom: 24rpx;
}
.progress-bar {
  width: 100%;
  height: 16rpx;
  background: #252525;
  border-radius: 8rpx;
  overflow: hidden;
}
.progress-inner {
  height: 100%;
  background: #b8ff26;
  border-radius: 8rpx;
  transition: width 0.3s;
}
.percent {
  margin-top: 16rpx;
  font-size: 28rpx;
  color: #999;
}
.preview-box {
  margin-top: 24rpx;
  background: #000;
  border-radius: 16rpx;
  overflow: hidden;
}
.preview-video {
  width: 100%;
  height: 400rpx;
}
.actions {
  margin-top: 32rpx;
}
.btn-primary {
  background: #b8ff26;
  color: #fff;
  border-radius: 12rpx;
  font-size: 30rpx;
}
.btn-plain {
  margin-top: 16rpx;
  background: #1e1e1e;
  color: #b8ff26;
  border: 2rpx solid #b8ff26;
  border-radius: 12rpx;
  font-size: 30rpx;
}
.error-box {
  margin-top: 32rpx;
  text-align: center;
}
.error-text {
  display: block;
  color: #e5484d;
  font-size: 26rpx;
  margin-bottom: 24rpx;
}
</style>
