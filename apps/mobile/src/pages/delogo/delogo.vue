<template>
  <view class="page">
    <!-- ============ 状态 1：上传视频 ============ -->
    <view v-if="!videoId" class="state-box">
      <button class="btn-primary" @tap="chooseVideo">上传视频</button>
      <text class="hint">在视频画面上框选内容，可拖拽缩放、多框、分段删除</text>
    </view>

    <!-- ============ 状态 2：框选编辑 ============ -->
    <view v-else-if="phase === 'editing'">
      <text class="hint-line">在视频画面上框选内容，可拖拽缩放、多框、分段删除</text>
      <!-- 视频画面 + 框选层 -->
      <view class="player">
        <video
          id="delogoVideo"
          :src="videoUrl"
          class="video"
          :controls="false"
          object-fit="fill"
          :show-center-play-btn="false"
          :show-play-btn="false"
          @timeupdate="onTimeUpdate"
          @loadedmetadata="onLoadedMeta"
          @play="playing = true"
          @pause="playing = false"
        />
        <view class="overlay" @touchmove="onTouchMove" @touchend="onTouchEnd" @touchcancel="onTouchEnd">
          <template v-for="(b, i) in boxes" :key="i">
            <view
              v-if="currentTime < b.endTime"
              class="box"
              :class="{ 'box-selected': i === selected }"
              :style="{ left: b.x + 'px', top: b.y + 'px', width: b.w + 'px', height: b.h + 'px' }"
            >
              <view class="box-body" @touchstart.stop="startMove(i, $event)" @tap.stop="selectBox(i)">
                <text class="box-label">{{ i + 1 }}</text>
              </view>
              <view v-if="i === selected" class="box-delete" @tap.stop="deleteBox(i)">✕</view>
              <view class="handle tl" @touchstart.stop="startResize(i, 'tl', $event)" />
              <view class="handle tr" @touchstart.stop="startResize(i, 'tr', $event)" />
              <view class="handle bl" @touchstart.stop="startResize(i, 'bl', $event)" />
              <view class="handle br" @touchstart.stop="startResize(i, 'br', $event)" />
            </view>
          </template>
        </view>
      </view>

      <!-- 时间轴 + 播放暂停 -->
      <view class="timeline">
        <view class="play-row">
          <slider
            class="timeline-slider"
            :value="currentTime"
            :max="videoDuration || 1"
            :step="0.1"
            activeColor="#b8ff26"
            @changing="onSeeking"
            @change="onSeekEnd"
          />
          <view class="play-btn" @tap="togglePlay">
            <text class="play-icon">{{ playing ? '⏸' : '▶' }}</text>
          </view>
        </view>
        <view class="time-row">
          <text class="time-text">{{ fmtTime(currentTime) }}</text>
          <text class="time-text">{{ fmtTime(videoDuration) }}</text>
        </view>
      </view>

      <!-- 添加框 -->
      <view class="add-row">
        <button class="btn-plain add-btn" @tap="addBox">＋ 添加框</button>
        <text class="add-tip">请用手指框选要擦拭的区域</text>
      </view>

      <button class="btn-primary submit" :disabled="!boxes.length || submitting" @tap="submit">
        开始去水印
      </button>
    </view>

    <!-- ============ 状态 3：处理中（圆圈进度，不锁屏） ============ -->
    <view v-else-if="phase === 'processing'" class="state-box">
      <view class="progress-ring" :style="{ background: 'conic-gradient(#b8ff26 ' + progress * 3.6 + 'deg, #252525 0deg)' }">
        <view class="progress-inner">
          <text class="progress-num">{{ progress }}%</text>
        </view>
      </view>
      <text class="progress-tip">正在去水印，请稍候…</text>
      <button class="btn-plain preview-btn" @tap="cancelProcess">取消</button>
    </view>

    <!-- ============ 状态 4：完成预览 + 保存 ============ -->
    <view v-else-if="phase === 'done'" class="done-box">
      <text class="done-title">✅ 去水印完成</text>
      <view class="preview-box">
        <video :src="resultFullUrl" class="preview-video" controls />
      </view>
      <button class="btn-primary save-btn" @tap="saveToAlbum">保存到相册</button>
    </view>
  </view>
</template>

<script>
import { api, fullUrl } from '../../api/index.js'

const MIN_SIZE = 24 // 框最小尺寸（px）

export default {
  data() {
    return {
      videoId: '',
      videoUrl: '',
      videoDuration: 0,
      currentTime: 0,
      playerW: 0,
      playerH: 0,
      boxes: [], // 擦除框 [{x, y, w, h, endTime}] 像素 + 生效结束时间
      selected: -1,
      drag: null,
      playing: false,
      phase: 'editing', // editing / processing / done
      progress: 0,
      resultUrl: '',
      taskId: '',
      timer: null,
      fakeStep: 0,
      submitting: false,
    }
  },
  computed: {
    resultFullUrl() {
      return this.resultUrl ? fullUrl(this.resultUrl) : ''
    },
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
            this.measurePlayer()
          } catch (e) {
            uni.showToast({ title: e.message, icon: 'none' })
          } finally {
            uni.hideLoading()
          }
        },
      })
    },
    measurePlayer() {
      setTimeout(() => {
        uni.createSelectorQuery()
          .select('.player')
          .boundingClientRect((rect) => {
            if (rect) {
              this.playerW = rect.width
              this.playerH = rect.height
            }
          })
          .exec()
      }, 300)
    },
    onTimeUpdate(e) {
      this.currentTime = e.detail.currentTime || 0
    },
    onLoadedMeta(e) {
      this.videoDuration = e.detail.duration || 0
    },
    togglePlay() {
      const ctx = uni.createVideoContext('delogoVideo')
      if (this.playing) ctx.pause()
      else ctx.play()
    },
    onSeeking(e) {
      const t = e.detail.value
      this.currentTime = t
      uni.createVideoContext('delogoVideo').seek(t)
    },
    onSeekEnd(e) {
      const t = e.detail.value
      this.currentTime = t
      uni.createVideoContext('delogoVideo').seek(t)
      this.selected = -1
    },
    newBox() {
      const w = Math.round(this.playerW * 0.3)
      const h = Math.round(this.playerH * 0.2)
      return {
        x: Math.round((this.playerW - w) / 2),
        y: Math.round((this.playerH - h) / 2),
        w,
        h,
        endTime: this.videoDuration || 99999, // 整段生效
      }
    },
    addBox() {
      this.boxes.push(this.newBox())
      this.selected = this.boxes.length - 1
    },
    // 点 ✕：截断到当前时间点（之前仍有框，之后无框）
    deleteBox(i) {
      if (this.currentTime < 0.5) {
        this.boxes.splice(i, 1) // 在开头删除 = 彻底移除
      } else {
        this.boxes[i].endTime = this.currentTime
      }
      this.selected = -1
    },
    selectBox(i) {
      this.selected = i
    },
    startMove(i, e) {
      this.selected = i
      const t = e.touches[0]
      this.drag = { type: 'move', index: i, startX: t.clientX, startY: t.clientY, box: { ...this.boxes[i] } }
    },
    startResize(i, handle, e) {
      this.selected = i
      const t = e.touches[0]
      this.drag = { type: 'resize', index: i, handle, startX: t.clientX, startY: t.clientY, box: { ...this.boxes[i] } }
    },
    onTouchMove(e) {
      if (!this.drag) return
      const t = e.touches[0]
      const dx = t.clientX - this.drag.startX
      const dy = t.clientY - this.drag.startY
      const b = this.boxes[this.drag.index]
      const s = this.drag.box

      if (this.drag.type === 'move') {
        b.x = this.clamp(s.x + dx, 0, this.playerW - s.w)
        b.y = this.clamp(s.y + dy, 0, this.playerH - s.h)
      } else {
        let { x, y, w, h } = s
        const hd = this.drag.handle
        if (hd.includes('l')) { x = s.x + dx; w = s.w - dx }
        if (hd.includes('r')) { w = s.w + dx }
        if (hd.includes('t')) { y = s.y + dy; h = s.h - dy }
        if (hd.includes('b')) { h = s.h + dy }
        if (hd.includes('l')) {
          if (w < MIN_SIZE) { x = s.x + s.w - MIN_SIZE; w = MIN_SIZE }
          if (x < 0) { w += x; x = 0 }
        }
        if (hd.includes('t')) {
          if (h < MIN_SIZE) { y = s.y + s.h - MIN_SIZE; h = MIN_SIZE }
          if (y < 0) { h += y; y = 0 }
        }
        if (hd.includes('r')) w = Math.min(w, this.playerW - s.x)
        if (hd.includes('b')) h = Math.min(h, this.playerH - s.y)
        b.x = x
        b.y = y
        b.w = Math.max(MIN_SIZE, w)
        b.h = Math.max(MIN_SIZE, h)
      }
    },
    onTouchEnd() {
      this.drag = null
    },
    clamp(v, min, max) {
      return Math.max(min, Math.min(max, v))
    },
    toPercent(b) {
      return {
        x: +(b.x / this.playerW).toFixed(4),
        y: +(b.y / this.playerH).toFixed(4),
        w: +(b.w / this.playerW).toFixed(4),
        h: +(b.h / this.playerH).toFixed(4),
      }
    },
    // 把框的 endTime 组合成分段 segments
    buildSegments() {
      const duration = this.videoDuration || 0
      const times = new Set([0, duration])
      this.boxes.forEach((b) => times.add(Math.min(b.endTime, duration)))
      const sorted = [...times].sort((a, b) => a - b)

      const segments = []
      for (let i = 0; i < sorted.length - 1; i++) {
        const start = sorted[i]
        const end = sorted[i + 1]
        if (end <= start) continue
        const boxes = this.boxes.filter((b) => b.endTime > start)
        if (boxes.length) {
          segments.push({ start, end, boxes: boxes.map((b) => this.toPercent(b)) })
        }
      }
      return segments
    },
    async submit() {
      const segments = this.buildSegments()
      if (!segments.length) {
        uni.showToast({ title: '请先添加框', icon: 'none' })
        return
      }
      this.submitting = true
      try {
        const { task_id } = await api.delogoProcess(this.videoId, segments)
        this.taskId = task_id
        this.phase = 'processing'
        this.progress = 8
        this.fakeStep = 0
        uni.setNavigationBarTitle({ title: '预览' })
        this.poll()
      } catch (e) {
        uni.showToast({ title: e.message, icon: 'none' })
      } finally {
        this.submitting = false
      }
    },
    poll() {
      this.clearTimer()
      this.timer = setInterval(async () => {
        try {
          const t = await api.task(this.taskId)
          if (t.status === 'done') {
            this.progress = 100
            this.resultUrl = t.result_url
            this.clearTimer()
            this.phase = 'done'
          } else if (t.status === 'error') {
            this.clearTimer()
            uni.showToast({ title: t.error || '去水印失败', icon: 'none' })
            this.phase = 'editing'
          } else {
            // 起步 8%，中间结合后端真实进度 + 随机小步，看起来更自然
            const real = Math.round(t.progress || 0)
            if (real > this.progress) {
              this.progress = real
            } else {
              this.progress = Math.min(this.progress + Math.ceil(Math.random() * 7), 90)
            }
          }
        } catch (e) {
          this.clearTimer()
          uni.showToast({ title: e.message, icon: 'none' })
          this.phase = 'editing'
        }
      }, 1500)
    },
    cancelProcess() {
      this.clearTimer()
      this.phase = 'editing'
      this.progress = 0
      uni.setNavigationBarTitle({ title: '去水印' })
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
}
.state-box {
  padding: 120rpx 0;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.hint {
  margin-top: 24rpx;
  font-size: 24rpx;
  color: #999;
  text-align: center;
  line-height: 1.6;
}
.hint-line {
  display: block;
  font-size: 24rpx;
  color: #999;
  line-height: 1.6;
  margin-bottom: 16rpx;
}
.player {
  position: relative;
  width: 100%;
  height: 480rpx;
  background: #000;
  border-radius: 16rpx;
  overflow: hidden;
}
.video {
  width: 100%;
  height: 100%;
}
.overlay {
  position: absolute;
  left: 0;
  top: 0;
  width: 100%;
  height: 100%;
}
.box {
  position: absolute;
  border: 2rpx solid rgba(255, 77, 79, 0.7);
  background: rgba(255, 77, 79, 0.1);
}
.box-selected {
  border: 3rpx solid #ff4d4f;
  background: rgba(255, 77, 79, 0.18);
}
.box-body {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}
.box-label {
  color: #ff4d4f;
  font-size: 26rpx;
  font-weight: 700;
}
.box-delete {
  position: absolute;
  right: -14px;
  top: -14px;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: #ff4d4f;
  color: #fff;
  font-size: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10;
}
.handle {
  position: absolute;
  background: #ff4d4f;
  border: 2rpx solid #fff;
  box-sizing: border-box;
}
.handle.tl { left: -8px; top: -8px; width: 16px; height: 16px; border-radius: 50%; }
.handle.tr { right: -8px; top: -8px; width: 16px; height: 16px; border-radius: 50%; }
.handle.bl { left: -8px; bottom: -8px; width: 16px; height: 16px; border-radius: 50%; }
.handle.br { right: -8px; bottom: -8px; width: 16px; height: 16px; border-radius: 50%; }
.timeline {
  margin-top: 20rpx;
  background: #1e1e1e;
  border-radius: 16rpx;
  padding: 16rpx 20rpx;
}
.play-row {
  display: flex;
  align-items: center;
}
.play-btn {
  width: 56rpx;
  height: 56rpx;
  border-radius: 50%;
  background: #b8ff26;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.play-icon {
  color: #0a0a0a;
  font-size: 28rpx;
  font-weight: 700;
}
.timeline-slider {
  flex: 1;
  margin: 0 16rpx;
}
.time-row {
  display: flex;
  justify-content: space-between;
  margin-top: 4rpx;
  padding: 0 8rpx;
}
.time-text {
  font-size: 22rpx;
  color: #999;
}
.add-row {
  margin-top: 20rpx;
  display: flex;
  align-items: center;
}
.add-btn {
  width: 220rpx;
  height: 64rpx;
  line-height: 64rpx;
  font-size: 26rpx;
  padding: 0;
  flex-shrink: 0;
}
.add-tip {
  margin-left: 20rpx;
  font-size: 24rpx;
  color: #999;
}
.submit {
  margin-top: 24rpx;
}
/* 圆圈进度 */
.progress-ring {
  width: 180rpx;
  height: 180rpx;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
}
.progress-inner {
  width: 140rpx;
  height: 140rpx;
  border-radius: 50%;
  background: #121212;
  display: flex;
  align-items: center;
  justify-content: center;
}
.progress-num {
  color: #b8ff26;
  font-size: 34rpx;
  font-weight: 700;
}
.progress-tip {
  margin-top: 24rpx;
  font-size: 26rpx;
  color: #999;
}
.preview-btn {
  margin-top: 32rpx;
  width: 400rpx;
}
/* 完成预览 */
.done-box {
  display: flex;
  flex-direction: column;
}
.done-title {
  font-size: 32rpx;
  font-weight: 700;
  margin-bottom: 20rpx;
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
.btn-primary[disabled] {
  background: #3a4020;
  color: #777;
}
.btn-plain {
  background: #1e1e1e;
  color: #b8ff26;
  border: 2rpx solid #b8ff26;
  border-radius: 12rpx;
}
</style>
