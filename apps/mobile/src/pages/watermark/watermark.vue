<template>
  <view class="page">
    <!-- 上传 -->
    <view v-if="!videoId" class="state-box">
      <button class="btn-primary" @tap="chooseVideo">上传视频</button>
      <text class="hint">给视频加文字或图片水印，可叠加多个，拖动/缩放/旋转</text>
    </view>

    <!-- 编辑 -->
    <view v-else-if="phase === 'editing'" class="edit-box">
      <view class="top-bar">
        <text class="top-title">水印编辑</text>
        <button class="btn-primary export-btn" @tap="process">导出</button>
      </view>
      <text class="gesture-tip">单指拖动 · 双指缩放旋转</text>

      <!-- 视频 + 水印元素 -->
      <view class="player">
        <video :src="videoUrl" class="video" :controls="false" object-fit="fill" :show-center-play-btn="false" :show-play-btn="false" />
        <view
          v-for="(el, i) in elements"
          :key="el.id"
          class="wm-element"
          :class="{ selected: i === selectedIndex }"
          :style="elStyle(el)"
          @touchstart="startGesture(i, $event)"
          @touchmove="onGesture($event)"
          @touchend="endGesture"
          @tap.stop="selectedIndex = i"
        >
          <text v-if="el.type === 'text'" class="wm-text" :style="elTextStyle(el)">{{ el.text }}</text>
          <image v-else :src="el.imageUrl" class="wm-image" :style="{ opacity: el.opacity, width: el.imageScale * 300 + 'rpx' }" />
          <view v-if="i === selectedIndex" class="wm-delete" @tap.stop="removeElement(i)">✕</view>
        </view>
      </view>

      <!-- 添加按钮 -->
      <view class="add-row">
        <button class="btn-plain add-btn" @tap="addText">＋ 文字</button>
        <button class="btn-plain add-btn" @tap="addImage">＋ 图片</button>
        <text class="add-tip">单指拖动 · 双指缩放旋转</text>
      </view>

      <!-- 选中元素参数 -->
      <template v-if="currentEl">
        <!-- 文字参数 -->
        <template v-if="currentEl.type === 'text'">
          <input v-model="currentEl.text" class="text-input" placeholder="输入水印文字" placeholder-class="ph" />
          <view class="row">
            <text class="label">字号</text>
            <slider class="slider" :value="currentEl.size" :min="12" :max="96" :step="1" activeColor="#b8ff26" @changing="(e) => (currentEl.size = e.detail.value)" />
            <text class="val">{{ currentEl.size }}</text>
          </view>
          <view class="row">
            <text class="label">颜色</text>
            <view class="colors">
              <view v-for="c in presetColors" :key="c" :class="['color-dot', { active: currentEl.color === c && !showPicker }]" :style="{ background: c }" @tap="pickColor(c)" />
              <view class="color-dot custom" :style="{ background: showPicker ? currentEl.color : '#1e1e1e' }" @tap="togglePicker">＋</view>
            </view>
          </view>
          <!-- 颜色选择器 -->
          <view v-if="showPicker" class="picker-panel">
            <view class="sv-board" :style="svBoardStyle" @touchstart="pickSv" @touchmove="pickSv">
              <view class="sv-thumb" :style="{ left: sat * 100 + '%', top: (1 - light) * 100 + '%' }" />
            </view>
            <view class="hue-bar" @touchstart="pickHue" @touchmove="pickHue">
              <view class="hue-thumb" :style="{ left: (hue / 360) * 100 + '%' }" />
            </view>
            <view class="picker-preview">
              <view class="preview-color" :style="{ background: currentEl.color }" />
              <text class="preview-hex">{{ currentEl.color }}</text>
            </view>
          </view>
          <view class="row">
            <text class="label">样式</text>
            <view class="styles">
              <view v-for="s in styles" :key="s.key" :class="['style-opt', { active: currentEl[s.key] }]" @tap="toggleStyle(s.key)">{{ s.label }}</view>
            </view>
          </view>
          <view class="row">
            <text class="label">字体</text>
            <picker :range="fontNames" :value="currentEl.fontId" @change="(e) => (currentEl.fontId = Number(e.detail.value))">
              <view class="picker-box">{{ fontNames[currentEl.fontId] || '选择字体' }}</view>
            </picker>
          </view>
        </template>

        <!-- 图片参数 -->
        <template v-else>
          <view class="row">
            <button class="btn-plain img-btn" @tap="rechooseImage">{{ currentEl.imageId ? '重新选图' : '上传图片' }}</button>
          </view>
          <view class="row">
            <text class="label">缩放</text>
            <slider class="slider" :value="currentEl.imageScale * 100" :min="10" :max="300" :step="5" activeColor="#b8ff26" @changing="(e) => (currentEl.imageScale = e.detail.value / 100)" />
            <text class="val">{{ Math.round(currentEl.imageScale * 100) }}%</text>
          </view>
        </template>

        <!-- 通用：旋转 + 透明度 -->
        <view class="row">
          <text class="label">旋转</text>
          <slider class="slider" :value="currentEl.angle + 180" :min="0" :max="360" :step="1" activeColor="#b8ff26" @changing="(e) => (currentEl.angle = e.detail.value - 180)" />
          <text class="val">{{ Math.round(currentEl.angle) }}°</text>
        </view>
        <view class="row">
          <text class="label">透明度</text>
          <slider class="slider" :value="currentEl.opacity * 100" :min="10" :max="100" :step="5" activeColor="#b8ff26" @changing="(e) => (currentEl.opacity = e.detail.value / 100)" />
          <text class="val">{{ Math.round(currentEl.opacity * 100) }}%</text>
        </view>
      </template>
    </view>

    <!-- 处理中 -->
    <view v-else-if="phase === 'processing'" class="state-box">
      <view class="progress-ring" :style="{ background: 'conic-gradient(#b8ff26 ' + progress * 3.6 + 'deg, #252525 0deg)' }">
        <view class="progress-inner"><text class="progress-num">{{ progress }}%</text></view>
      </view>
      <text class="hint">正在加水印，请稍候…</text>
      <button class="btn-plain cancel-btn" @tap="cancelProcess">取消</button>
    </view>

    <!-- 预览 -->
    <view v-else class="done-box">
      <text class="done-title">✅ 完成</text>
      <view class="preview-box">
        <video :src="resultFullUrl" class="preview-video" controls />
      </view>
      <button class="btn-primary save-btn" @tap="saveToAlbum">保存到相册</button>
    </view>
  </view>
</template>

<script>
import { api, fullUrl } from '../../api/index.js'

function hslToHex(h, s, l) {
  h /= 360
  const hue2rgb = (p, q, t) => {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  let r, g, b
  if (s === 0) {
    r = g = b = l
  } else {
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s
    const p = 2 * l - q
    r = hue2rgb(p, q, h + 1 / 3)
    g = hue2rgb(p, q, h)
    b = hue2rgb(p, q, h - 1 / 3)
  }
  const toHex = (x) => Math.round(x * 255).toString(16).padStart(2, '0')
  return '#' + toHex(r) + toHex(g) + toHex(b)
}

let _id = 1

export default {
  data() {
    return {
      videoId: '',
      videoUrl: '',
      playerW: 0,
      playerH: 0,
      playerLeft: 0,
      playerTop: 0,
      elements: [],
      selectedIndex: 0,
      fonts: [],
      fontNames: [],
      presetColors: ['#ffffff', '#000000', '#ff0000', '#ffff00', '#00ff00', '#0000ff', '#ff8800', '#8800ff', '#ff00ff'],
      styles: [
        { key: 'bold', label: '粗体' },
        { key: 'italic', label: '斜体' },
        { key: 'shadow', label: '阴影' },
        { key: 'outline', label: '描边' },
        { key: 'tile', label: '平铺' },
      ],
      showPicker: false,
      hue: 0,
      sat: 1.0,
      light: 0.6,
      svRect: null,
      hueRect: null,
      gesture: null,
      phase: 'editing',
      progress: 0,
      resultUrl: '',
      taskId: '',
      timer: null,
    }
  },
  computed: {
    resultFullUrl() {
      return this.resultUrl ? fullUrl(this.resultUrl) : ''
    },
    currentEl() {
      return this.elements[this.selectedIndex] || null
    },
    svBoardStyle() {
      const hueColor = hslToHex(this.hue, 1, 0.5)
      return {
        background: `linear-gradient(to top, #000, rgba(0,0,0,0)), linear-gradient(to right, #fff, ${hueColor})`,
      }
    },
  },
  onLoad() {
    this.loadFonts()
    try {
      const info = uni.getSystemInfoSync()
      this.playerW = (info && info.windowWidth) || 375
      this.playerH = Math.round((420 / 750) * ((info && info.windowWidth) || 375))
    } catch (e) {
      this.playerW = 375
      this.playerH = 210
    }
  },
  onReady() {
    // 页面渲染后实测 player 尺寸，覆盖 onLoad 的估算值
    setTimeout(() => {
      uni.createSelectorQuery()
        .select('.player')
        .boundingClientRect((rect) => {
          if (rect && rect.width) {
            this.playerW = rect.width
            this.playerH = rect.height
          }
        })
        .exec()
    }, 300)
  },
  onUnload() {
    if (this.timer) clearInterval(this.timer)
  },
  methods: {
    async loadFonts() {
      try {
        const data = await api.fonts()
        this.fonts = data.fonts || []
        this.fontNames = this.fonts.map((f) => f.name)
      } catch (e) {
        // 忽略
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
            this.elements = [this.newTextElement()]
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
              this.playerLeft = rect.left
              this.playerTop = rect.top
            }
          })
          .exec()
      }, 300)
    },
    newTextElement() {
      return {
        id: _id++,
        type: 'text',
        text: '水印文字',
        size: 36,
        color: '#ffffff',
        fontId: 0,
        bold: false,
        italic: false,
        shadow: false,
        outline: false,
        tile: false,
        imageId: '',
        imageUrl: '',
        imageScale: 1.0,
        opacity: 1.0,
        x: 0.5,
        y: 0.5,
        angle: 0,
      }
    },
    addText() {
      this.elements.push(this.newTextElement())
      this.selectedIndex = this.elements.length - 1
    },
    addImage() {
      uni.chooseImage({
        count: 1,
        success: async (res) => {
          uni.showLoading({ title: '上传中…' })
          try {
            const data = await api.uploadImage(res.tempFilePaths[0])
            this.elements.push({
              id: _id++,
              type: 'image',
              text: '',
              size: 0,
              color: '#ffffff',
              fontId: 0,
              bold: false,
              italic: false,
              shadow: false,
              outline: false,
              tile: false,
              imageId: data.image_id,
              imageUrl: fullUrl(data.url),
              imageScale: 0.3,
              opacity: 1.0,
              x: 0.5,
              y: 0.5,
              angle: 0,
            })
            this.selectedIndex = this.elements.length - 1
          } catch (e) {
            uni.showToast({ title: e.message, icon: 'none' })
          } finally {
            uni.hideLoading()
          }
        },
      })
    },
    rechooseImage() {
      uni.chooseImage({
        count: 1,
        success: async (res) => {
          uni.showLoading({ title: '上传中…' })
          try {
            const data = await api.uploadImage(res.tempFilePaths[0])
            this.currentEl.imageId = data.image_id
            this.currentEl.imageUrl = fullUrl(data.url)
          } catch (e) {
            uni.showToast({ title: e.message, icon: 'none' })
          } finally {
            uni.hideLoading()
          }
        },
      })
    },
    removeElement(i) {
      this.elements.splice(i, 1)
      this.selectedIndex = Math.max(0, Math.min(this.selectedIndex, this.elements.length - 1))
    },
    elStyle(el) {
      const scale = el.type === 'text' ? el.size / 36 : 1
      return {
        left: el.x * this.playerW + 'px',
        top: el.y * this.playerH + 'px',
        transform: `translate(-50%, -50%) scale(${scale}) rotate(${el.angle}deg)`,
      }
    },
    elTextStyle(el) {
      const s = { color: el.color, opacity: el.opacity }
      s.fontWeight = el.bold ? 'bold' : 'normal'
      s.fontStyle = el.italic ? 'italic' : 'normal'
      if (el.shadow) s.textShadow = '2px 2px 4px rgba(0,0,0,0.6)'
      if (el.outline) s.webkitTextStroke = '1px #000'
      return s
    },
    // 手势：单指拖动 + 双指缩放旋转
    startGesture(i, e) {
      this.selectedIndex = i
      const el = this.elements[i]
      if (e.touches.length === 1) {
        const t = e.touches[0]
        this.gesture = { mode: 'move', startX: t.clientX, startY: t.clientY, el: { x: el.x, y: el.y } }
      } else if (e.touches.length === 2) {
        const t1 = e.touches[0]
        const t2 = e.touches[1]
        this.gesture = {
          mode: 'pinch',
          startDist: Math.hypot(t2.clientX - t1.clientX, t2.clientY - t1.clientY),
          startAngle: Math.atan2(t2.clientY - t1.clientY, t2.clientX - t1.clientX),
          el: { size: el.size, imageScale: el.imageScale, angle: el.angle },
        }
      }
    },
    onGesture(e) {
      const el = this.currentEl
      if (!this.gesture || !el) return
      if (this.gesture.mode === 'move' && e.touches.length === 1) {
        const t = e.touches[0]
        const dx = t.clientX - this.gesture.startX
        const dy = t.clientY - this.gesture.startY
        el.x = this.clamp(this.gesture.el.x + dx / this.playerW, 0, 1)
        el.y = this.clamp(this.gesture.el.y + dy / this.playerH, 0, 1)
      } else if (this.gesture.mode === 'pinch' && e.touches.length === 2) {
        const t1 = e.touches[0]
        const t2 = e.touches[1]
        const dist = Math.hypot(t2.clientX - t1.clientX, t2.clientY - t1.clientY)
        const ang = Math.atan2(t2.clientY - t1.clientY, t2.clientX - t1.clientX)
        const ratio = this.gesture.startDist > 0 ? dist / this.gesture.startDist : 1
        if (el.type === 'text') {
          el.size = this.clamp(Math.round(this.gesture.el.size * ratio), 12, 96)
        } else {
          el.imageScale = this.clamp(this.gesture.el.imageScale * ratio, 0.1, 3)
        }
        let dAngle = ((ang - this.gesture.startAngle) * 180) / Math.PI
        if (dAngle > 180) dAngle -= 360
        if (dAngle < -180) dAngle += 360
        el.angle = this.gesture.el.angle + dAngle
      }
    },
    endGesture() {
      this.gesture = null
    },
    clamp(v, min, max) {
      return Math.max(min, Math.min(max, v))
    },
    pickColor(c) {
      if (this.currentEl) this.currentEl.color = c
      this.showPicker = false
    },
    toggleStyle(key) {
      if (this.currentEl) this.currentEl[key] = !this.currentEl[key]
    },
    // 颜色选择器
    togglePicker() {
      this.showPicker = !this.showPicker
      if (this.showPicker) {
        this.$nextTick(() => this.measurePicker())
      }
    },
    measurePicker() {
      uni.createSelectorQuery().select('.sv-board').boundingClientRect((r) => { if (r) this.svRect = r }).exec()
      uni.createSelectorQuery().select('.hue-bar').boundingClientRect((r) => { if (r) this.hueRect = r }).exec()
    },
    pickHue(e) {
      if (!this.hueRect) return
      const t = e.touches[0]
      const x = (t.clientX - this.hueRect.left) / this.hueRect.width
      this.hue = this.clamp(x, 0, 1) * 360
      this.applyPickerColor()
    },
    pickSv(e) {
      if (!this.svRect) return
      const t = e.touches[0]
      const x = (t.clientX - this.svRect.left) / this.svRect.width
      const y = (t.clientY - this.svRect.top) / this.svRect.height
      this.sat = this.clamp(x, 0, 1)
      this.light = this.clamp(1 - y, 0, 1)
      this.applyPickerColor()
    },
    applyPickerColor() {
      if (this.currentEl) this.currentEl.color = hslToHex(this.hue, this.sat, this.light)
    },
    async process() {
      const valid = this.elements.filter((el) => {
        if (el.type === 'text') return el.text && el.text.trim()
        return el.imageId
      })
      if (!valid.length) {
        uni.showToast({ title: '请先添加水印', icon: 'none' })
        return
      }
      this.phase = 'processing'
      this.progress = 8
      const elements = this.elements.map((el) => ({
        type: el.type,
        text: el.text,
        size: el.size,
        color: el.color,
        opacity: el.opacity,
        font_id: el.fontId,
        bold: el.bold,
        italic: el.italic,
        shadow: el.shadow,
        outline: el.outline,
        tile: el.tile,
        x: el.x,
        y: el.y,
        angle: el.angle,
        image_id: el.imageId,
        image_scale: el.imageScale,
      }))
      try {
        const { task_id } = await api.watermarkProcess({ video_id: this.videoId, elements })
        this.taskId = task_id
        uni.setNavigationBarTitle({ title: '预览' })
        this.poll()
      } catch (e) {
        uni.showToast({ title: e.message, icon: 'none' })
        this.phase = 'editing'
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
            uni.showToast({ title: t.error || '处理失败', icon: 'none' })
            this.phase = 'editing'
            uni.setNavigationBarTitle({ title: '加水印' })
          } else {
            const real = Math.round(t.progress || 0)
            if (real > this.progress) this.progress = real
            else this.progress = Math.min(this.progress + Math.ceil(Math.random() * 7), 90)
          }
        } catch (e) {
          this.clearTimer()
          this.phase = 'editing'
        }
      }, 1500)
    },
    clearTimer() {
      if (this.timer) {
        clearInterval(this.timer)
        this.timer = null
      }
    },
    cancelProcess() {
      this.clearTimer()
      this.phase = 'editing'
      this.progress = 0
      uni.setNavigationBarTitle({ title: '加水印' })
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
.edit-box {
  display: flex;
  flex-direction: column;
}
.top-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16rpx;
}
.top-title {
  font-size: 32rpx;
  font-weight: 700;
}
.gesture-tip {
  display: block;
  font-size: 22rpx;
  color: #999;
  margin-bottom: 12rpx;
}
.export-btn {
  width: 140rpx;
  height: 64rpx;
  line-height: 64rpx;
  padding: 0;
  font-size: 28rpx;
}
.player {
  position: relative;
  width: 100%;
  height: 420rpx;
  background: #000;
  border-radius: 16rpx;
  overflow: hidden;
}
.video {
  width: 100%;
  height: 100%;
}
.wm-element {
  position: absolute;
  z-index: 5;
}
.wm-element.selected {
  outline: 2rpx dashed #b8ff26;
}
.wm-text {
  font-size: 36px;
  white-space: nowrap;
}
.wm-image {
  height: auto;
}
.wm-delete {
  position: absolute;
  right: -14px;
  top: -14px;
  width: 26px;
  height: 26px;
  border-radius: 50%;
  background: #ff4d4f;
  color: #fff;
  font-size: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.add-row {
  display: flex;
  align-items: center;
  gap: 16rpx;
  margin-top: 20rpx;
}
.add-btn {
  font-size: 26rpx;
  padding: 0 28rpx;
  height: 64rpx;
  line-height: 64rpx;
}
.add-tip {
  font-size: 22rpx;
  color: #999;
  margin-left: auto;
}
.row {
  display: flex;
  align-items: center;
  margin-top: 20rpx;
}
.text-input {
  margin-top: 20rpx;
  background: #1e1e1e;
  border-radius: 12rpx;
  height: 80rpx;
  padding: 0 20rpx;
  color: #fff;
  font-size: 28rpx;
}
.ph {
  color: #666;
}
.label {
  width: 90rpx;
  font-size: 26rpx;
  color: #999;
  flex-shrink: 0;
}
.slider {
  flex: 1;
  margin: 0 16rpx;
}
.val {
  width: 90rpx;
  font-size: 24rpx;
  color: #b8ff26;
  text-align: right;
}
.colors {
  display: flex;
  flex-wrap: wrap;
  gap: 14rpx;
}
.color-dot {
  width: 52rpx;
  height: 52rpx;
  border-radius: 50%;
  border: 3rpx solid transparent;
}
.color-dot.active {
  border-color: #b8ff26;
}
.color-dot.custom {
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28rpx;
  border: 3rpx dashed #666;
}
.picker-panel {
  margin-top: 16rpx;
  background: #1e1e1e;
  border-radius: 12rpx;
  padding: 20rpx;
}
.sv-board {
  position: relative;
  width: 100%;
  height: 320rpx;
  border-radius: 8rpx;
  background: linear-gradient(to top, #000, rgba(0, 0, 0, 0)), linear-gradient(to right, #fff, hsl(0, 0%, 100%));
  background-color: hsl(0, 100%, 50%);
}
.sv-thumb {
  position: absolute;
  width: 20rpx;
  height: 20rpx;
  border-radius: 50%;
  border: 3rpx solid #fff;
  transform: translate(-50%, -50%);
}
.hue-bar {
  position: relative;
  width: 100%;
  height: 40rpx;
  border-radius: 8rpx;
  margin-top: 20rpx;
  background: linear-gradient(to right, #f00, #ff0, #0f0, #0ff, #00f, #f0f, #f00);
}
.hue-thumb {
  position: absolute;
  top: 50%;
  width: 20rpx;
  height: 40rpx;
  border: 3rpx solid #fff;
  transform: translate(-50%, -50%);
}
.picker-preview {
  display: flex;
  align-items: center;
  margin-top: 20rpx;
}
.preview-color {
  width: 60rpx;
  height: 60rpx;
  border-radius: 8rpx;
  border: 2rpx solid #fff;
}
.preview-hex {
  margin-left: 16rpx;
  font-size: 26rpx;
  color: #fff;
}
.styles {
  display: flex;
  flex-wrap: wrap;
  gap: 12rpx;
}
.style-opt {
  padding: 8rpx 24rpx;
  border-radius: 20rpx;
  background: #1e1e1e;
  border: 2rpx solid #444;
  font-size: 24rpx;
  color: #999;
}
.style-opt.active {
  border-color: #b8ff26;
  color: #b8ff26;
}
.picker-box {
  background: #1e1e1e;
  border-radius: 12rpx;
  padding: 14rpx 24rpx;
  font-size: 26rpx;
  color: #fff;
}
.img-btn {
  font-size: 26rpx;
  padding: 0 24rpx;
  height: 64rpx;
  line-height: 64rpx;
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
.cancel-btn {
  margin-top: 32rpx;
  width: 300rpx;
}
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
.btn-primary {
  background: #b8ff26;
  color: #0a0a0a;
  border-radius: 12rpx;
  font-size: 30rpx;
}
.btn-plain {
  background: #1e1e1e;
  color: #b8ff26;
  border: 2rpx solid #b8ff26;
  border-radius: 12rpx;
}
</style>
