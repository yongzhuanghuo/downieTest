<template>
  <view class="page">
    <view v-if="!videoId" class="state-box">
      <button class="btn-primary" @tap="chooseVideo">上传视频</button>
      <text class="hint">重新封装视频文件以修改 MD5，无损、不影响播放</text>
    </view>

    <view v-else-if="phase === 'editing'" class="state-box">
      <text class="hint">视频已就绪，点击下方按钮修改 MD5</text>
      <button class="btn-primary" @tap="process">修改 MD5</button>
    </view>

    <view v-else-if="phase === 'processing'" class="state-box">
      <text class="hint">处理中…</text>
    </view>

    <view v-else class="done-box">
      <text class="done-title">✅ 完成</text>
      <view class="md5-row">
        <text class="md5-text">原 MD5：{{ beforeMd5 }}</text>
        <text class="md5-text">新 MD5：{{ afterMd5 }}</text>
      </view>
      <view class="preview-box">
        <video :src="resultFullUrl" class="preview-video" controls />
      </view>
      <button class="btn-primary save-btn" @tap="saveToAlbum">保存到相册</button>
    </view>
  </view>
</template>

<script>
import { api, fullUrl } from '../../api/index.js'

export default {
  data() {
    return {
      videoId: '',
      phase: 'editing',
      beforeMd5: '',
      afterMd5: '',
      resultUrl: '',
      timer: null,
    }
  },
  computed: {
    resultFullUrl() {
      return this.resultUrl ? fullUrl(this.resultUrl) : ''
    },
  },
  onUnload() {
    if (this.timer) clearInterval(this.timer)
  },
  methods: {
    chooseVideo() {
      uni.chooseVideo({
        sourceType: ['album', 'camera'],
        maxDuration: 300,
        success: async (res) => {
          uni.showLoading({ title: '上传中…' })
          try {
            const data = await api.delogoPreview(res.tempFilePath)
            this.videoId = data.video_id
          } catch (e) {
            uni.showToast({ title: e.message, icon: 'none' })
          } finally {
            uni.hideLoading()
          }
        },
      })
    },
    async process() {
      this.phase = 'processing'
      try {
        const { task_id } = await api.md5Process(this.videoId)
        this.poll(task_id)
      } catch (e) {
        uni.showToast({ title: e.message, icon: 'none' })
        this.phase = 'editing'
      }
    },
    poll(taskId) {
      this.timer = setInterval(async () => {
        try {
          const t = await api.task(taskId)
          if (t.status === 'done') {
            this.resultUrl = t.result_url
            this.beforeMd5 = (t.data && t.data.before_md5) || ''
            this.afterMd5 = (t.data && t.data.after_md5) || ''
            clearInterval(this.timer)
            this.phase = 'done'
          } else if (t.status === 'error') {
            clearInterval(this.timer)
            uni.showToast({ title: t.error || '处理失败', icon: 'none' })
            this.phase = 'editing'
          }
        } catch (e) {
          clearInterval(this.timer)
          uni.showToast({ title: e.message, icon: 'none' })
          this.phase = 'editing'
        }
      }, 1000)
    },
    saveToAlbum() {
      const u = fullUrl(this.resultUrl)
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
  },
}
</script>

<style scoped>
.page {
  padding: 24rpx;
  min-height: 100vh;
}
.state-box {
  padding: 160rpx 0;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.hint {
  margin-top: 24rpx;
  font-size: 24rpx;
  color: #999;
  text-align: center;
}
.done-box {
  display: flex;
  flex-direction: column;
}
.done-title {
  font-size: 32rpx;
  font-weight: 700;
  margin-bottom: 20rpx;
}
.md5-row {
  background: #1e1e1e;
  border-radius: 12rpx;
  padding: 20rpx;
  margin-bottom: 20rpx;
}
.md5-text {
  display: block;
  font-size: 24rpx;
  color: #999;
  margin-bottom: 8rpx;
  word-break: break-all;
}
.preview-box {
  background: #000;
  border-radius: 16rpx;
  overflow: hidden;
}
.preview-video {
  width: 100%;
  height: 400rpx;
}
.save-btn {
  margin-top: 24rpx;
}
.btn-primary {
  background: #b8ff26;
  color: #0a0a0a;
  border-radius: 12rpx;
  font-size: 30rpx;
}
</style>
