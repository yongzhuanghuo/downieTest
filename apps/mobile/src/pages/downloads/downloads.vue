<template>
  <view class="page">
    <view v-if="!history.length" class="empty">
      <text class="empty-icon">📂</text>
      <text class="empty-text">暂无下载记录</text>
      <text class="empty-hint">去首页粘贴链接开始下载吧</text>
    </view>

    <view v-else class="list">
      <view class="item" v-for="h in history" :key="h.taskId || h.time">
        <view class="item-main">
          <text class="item-title">{{ h.title }}</text>
          <!-- 进行中：进度条 -->
          <view v-if="h.status === 'downloading'" class="progress-box">
            <view class="progress-bar">
              <view class="progress-inner" :style="{ width: (h.progress || 0) + '%' }" />
            </view>
            <text class="progress-text">下载中 {{ h.progress || 0 }}%</text>
          </view>
          <text v-else-if="h.status === 'error'" class="item-error">下载失败{{ h.error ? '：' + h.error : '' }}</text>
          <text v-else class="item-time">{{ fmtTime(h.time) }}</text>
        </view>
        <view v-if="h.status === 'done'" class="item-actions">
          <text class="action" @tap="save(h)">存相册</text>
          <text class="action" @tap="copy(h)">复制链接</text>
        </view>
      </view>
    </view>
  </view>
</template>

<script>
import { api, fullUrl } from '../../api/index.js'

export default {
  data() {
    return {
      history: [],
    }
  },
  onShow() {
    this.history = uni.getStorageSync('download_history') || []
    this.resumePolling()
  },
  methods: {
    // 对「下载中」的记录，切回来后继续轮询后端更新状态
    resumePolling() {
      this.history
        .filter((h) => h.status === 'downloading' && h.taskId)
        .forEach((h) => this.pollTask(h.taskId))
    },
    async pollTask(taskId) {
      try {
        const t = await api.task(taskId)
        const list = uni.getStorageSync('download_history') || []
        const idx = list.findIndex((h) => h.taskId === taskId)
        if (idx < 0) return
        if (t.status === 'done') {
          list[idx].status = 'done'
          list[idx].resultUrl = t.result_url
          list[idx].progress = 100
        } else if (t.status === 'error') {
          list[idx].status = 'error'
          list[idx].error = t.error || '下载失败'
        } else {
          // running/pending：更新进度后继续轮询
          list[idx].progress = t.progress || 0
          uni.setStorageSync('download_history', list)
          this.history = list
          setTimeout(() => this.pollTask(taskId), 2000)
          return
        }
        uni.setStorageSync('download_history', list)
        this.history = list
      } catch (e) {
        // 网络异常，稍后重试
        setTimeout(() => this.pollTask(taskId), 3000)
      }
    },
    fmtTime(ts) {
      const d = new Date(ts)
      const pad = (n) => String(n).padStart(2, '0')
      return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
    },
    save(h) {
      const u = fullUrl(h.resultUrl)
      // #ifdef H5
      window.open(u)
      // #endif
      // #ifndef H5
      uni.downloadFile({
        url: u,
        success: (res) => {
          uni.saveVideoToPhotosAlbum({
            filePath: res.tempFilePath,
            success: () => uni.showToast({ title: '已保存到相册' }),
            fail: (e) => uni.showToast({ title: '保存失败：' + e.errMsg, icon: 'none' }),
          })
        },
      })
      // #endif
    },
    copy(h) {
      uni.setClipboardData({
        data: fullUrl(h.resultUrl),
        success: () => uni.showToast({ title: '链接已复制' }),
      })
    },
  },
}
</script>

<style scoped>
.page {
  padding: 24rpx;
  min-height: 100vh;
}
.empty {
  padding: 200rpx 0;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.empty-icon {
  font-size: 96rpx;
}
.empty-text {
  margin-top: 24rpx;
  color: #999;
  font-size: 30rpx;
}
.empty-hint {
  margin-top: 12rpx;
  color: #555;
  font-size: 24rpx;
}
.item {
  background: #1e1e1e;
  border-radius: 24rpx;
  padding: 24rpx;
  margin-bottom: 20rpx;
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.item-main {
  flex: 1;
  margin-right: 20rpx;
  overflow: hidden;
}
.item-title {
  display: block;
  color: #fff;
  font-size: 28rpx;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.progress-box {
  margin-top: 12rpx;
}
.progress-bar {
  height: 12rpx;
  background: #252525;
  border-radius: 6rpx;
  overflow: hidden;
}
.progress-inner {
  height: 100%;
  background: #b8ff26;
  border-radius: 6rpx;
  transition: width 0.3s;
}
.progress-text {
  display: block;
  margin-top: 6rpx;
  color: #666;
  font-size: 22rpx;
}
.item-error {
  display: block;
  margin-top: 8rpx;
  color: #e5484d;
  font-size: 22rpx;
}
.item-time {
  display: block;
  margin-top: 8rpx;
  color: #666;
  font-size: 22rpx;
}
.item-actions {
  display: flex;
  gap: 24rpx;
}
.action {
  color: #b8ff26;
  font-size: 26rpx;
}
</style>
