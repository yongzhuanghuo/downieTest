<template>
  <view class="page">
    <view v-if="!videoId" class="state-box">
      <button class="btn-primary" @tap="chooseVideo">上传视频</button>
      <text class="hint">选择视频片段转成 GIF 动图</text>
    </view>

    <view v-else-if="phase === 'editing'" class="edit-box">
      <video :src="videoUrl" class="video" controls @timeupdate="onTimeUpdate" @loadedmetadata="onLoadedMeta" />

      <view class="param-row">
        <text class="param-label">开始</text>
        <slider class="param-slider" :value="start" :max="videoDuration || 1" :step="0.1" activeColor="#b8ff26" @changing="(e) => (start = e.detail.value)" />
        <text class="param-val">{{ fmtTime(start) }}</text>
      </view>
      <view class="param-row">
        <text class="param-label">结束</text>
        <slider class="param-slider" :value="end" :max="videoDuration || 1" :step="0.1" activeColor="#b8ff26" @changing="(e) => (end = e.detail.value)" />
        <text class="param-val">{{ fmtTime(end) }}</text>
      </view>

      <view class="param-row">
        <text class="param-label">帧率</text>
        <view class="opt-group">
          <view v-for="f in [8, 10, 15]" :key="f" :class="['opt', { active: fps === f }]" @tap="fps = f">{{ f }}</view>
        </view>
      </view>
      <view class="param-row">
        <text class="param-label">尺寸</text>
        <view class="opt-group">
          <view v-for="w in [480, 360]" :key="w" :class="['opt', { active: width === w }]" @tap="width = w">{{ w }} 宽</view>
        </view>
      </view>

      <button class="btn-primary" :disabled="start >= end" @tap="process">转 GIF</button>
    </view>

    <view v-else-if="phase === 'processing'" class="state-box">
      <text class="hint">转换中…</text>
    </view>

    <view v-else class="done-box">
      <text class="done-title">✅ 完成</text>
      <image :src="resultFullUrl" class="gif-preview" mode="widthFix" />
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
      videoUrl: '',
      videoDuration: 0,
      start: 0,
      end: 3,
      fps: 10,
      width: 480,
      phase: 'editing',
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
            this.videoUrl = fullUrl(data.video_url)
          } catch (e) {
            uni.showToast({ title: e.message, icon: 'none' })
          } finally {
            uni.hideLoading()
          }
        },
      })
    },
    onTimeUpdate(e) {
      // 供参考，不强制
    },
    onLoadedMeta(e) {
      this.videoDuration = e.detail.duration || 0
      this.end = Math.min(3, this.videoDuration)
    },
    async process() {
      this.phase = 'processing'
      try {
        const { task_id } = await api.gifProcess({
          video_id: this.videoId,
          start: this.start,
          end: this.end,
          fps: this.fps,
          width: this.width,
        })
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
            clearInterval(this.timer)
            this.phase = 'done'
          } else if (t.status === 'error') {
            clearInterval(this.timer)
            uni.showToast({ title: t.error || '转换失败', icon: 'none' })
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
          uni.saveImageToPhotosAlbum({
            filePath: res.tempFilePath,
            success: () => uni.showToast({ title: '已保存到相册' }),
            fail: (e) => uni.showToast({ title: '保存失败：' + e.errMsg, icon: 'none' }),
          })
        },
      })
      // #endif
    },
    fmtTime(s) {
      if (!s && s !== 0) return '0:00'
      const m = Math.floor(s / 60)
      const sec = Math.floor(s % 60)
      return `${m}:${String(sec).padStart(2, '0')}`
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
.edit-box {
  display: flex;
  flex-direction: column;
}
.video {
  width: 100%;
  height: 400rpx;
  background: #000;
  border-radius: 16rpx;
}
.param-row {
  display: flex;
  align-items: center;
  margin-top: 20rpx;
}
.param-label {
  width: 90rpx;
  font-size: 26rpx;
  color: #999;
}
.param-slider {
  flex: 1;
  margin: 0 16rpx;
}
.param-val {
  width: 90rpx;
  font-size: 24rpx;
  color: #b8ff26;
  text-align: right;
}
.opt-group {
  display: flex;
  gap: 16rpx;
}
.opt {
  padding: 10rpx 28rpx;
  border-radius: 24rpx;
  background: #1e1e1e;
  border: 2rpx solid #444;
  font-size: 24rpx;
  color: #999;
}
.opt.active {
  border-color: #b8ff26;
  color: #b8ff26;
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
.gif-preview {
  width: 100%;
  border-radius: 16rpx;
  background: #1e1e1e;
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
.btn-primary[disabled] {
  background: #3a4020;
  color: #777;
}
</style>
