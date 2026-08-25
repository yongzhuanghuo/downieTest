<template>
  <view class="page">
    <view v-if="loading" class="state-box">
      <text class="state-text">解析中…</text>
    </view>

    <view v-else-if="error" class="state-box">
      <text class="state-text error">{{ error }}</text>
      <button class="btn-primary" @tap="parse">重试</button>
    </view>

    <view v-else>
      <view class="video-card">
        <image v-if="info.cover" :src="info.cover" class="cover" mode="aspectFill" />
        <view class="video-meta">
          <text class="title">{{ info.title }}</text>
          <text class="sub">{{ info.author }}<text v-if="info.author && info.duration"> · </text>{{ fmtDuration(info.duration) }}</text>
        </view>
      </view>

      <view class="section-title">选择清晰度</view>
      <view class="format-list">
        <view
          class="format-item"
          :class="{ active: selected === f.format_id }"
          v-for="f in info.formats"
          :key="f.format_id"
          @tap="selected = f.format_id"
        >
          <text class="format-note">{{ f.note }}</text>
          <text class="format-size">{{ fmtSize(f.filesize) }}</text>
          <text v-if="selected === f.format_id" class="format-check">✓</text>
        </view>
      </view>

      <button class="btn-primary bottom" :disabled="!selected" @tap="onDownload">下载视频</button>
    </view>
  </view>
</template>

<script>
import { api } from '../../api/index.js'

export default {
  data() {
    return {
      url: '',
      loading: true,
      error: '',
      info: { title: '', cover: '', author: '', duration: 0, formats: [] },
      selected: '',
    }
  },
  onLoad(query) {
    this.url = decodeURIComponent(query.url || '')
    this.parse()
  },
  methods: {
    async parse() {
      this.loading = true
      this.error = ''
      try {
        const data = await api.parse(this.url)
        this.info = data
        // 默认选第一个（最高清晰度）
        if (data.formats.length) this.selected = data.formats[0].format_id
      } catch (e) {
        this.error = e.message
      } finally {
        this.loading = false
      }
    },
    onDownload() {
      if (!this.selected) return
      uni.navigateTo({
        // format_id 必须 encode：抖音/B站 的 format_id 是含 ?& 的完整直链，不编码会被 query 解析截断
        url: `/pages/download/download?url=${encodeURIComponent(this.url)}&format_id=${encodeURIComponent(this.selected)}&title=${encodeURIComponent(this.info.title || '')}`,
      })
    },
    fmtDuration(s) {
      if (!s) return ''
      const m = Math.floor(s / 60)
      const sec = s % 60
      return `${m}:${String(sec).padStart(2, '0')}`
    },
    fmtSize(bytes) {
      if (!bytes) return ''
      const mb = bytes / 1024 / 1024
      if (mb >= 1024) return `${(mb / 1024).toFixed(1)}G`
      return `${mb.toFixed(1)}M`
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
.state-text {
  font-size: 28rpx;
  color: #666;
  margin-bottom: 24rpx;
}
.state-text.error {
  color: #e5484d;
}
.video-card {
  background: #1e1e1e;
  border-radius: 16rpx;
  overflow: hidden;
}
.cover {
  width: 100%;
  height: 360rpx;
  background: #252525;
}
.video-meta {
  padding: 20rpx;
}
.title {
  display: block;
  font-size: 30rpx;
  font-weight: 600;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.sub {
  display: block;
  margin-top: 8rpx;
  font-size: 24rpx;
  color: #999;
}
.section-title {
  margin: 32rpx 0 16rpx;
  font-size: 30rpx;
  font-weight: 600;
}
.format-item {
  display: flex;
  align-items: center;
  background: #1e1e1e;
  border-radius: 12rpx;
  padding: 24rpx;
  margin-bottom: 16rpx;
  border: 2rpx solid transparent;
}
.format-item.active {
  border-color: #b8ff26;
}
.format-note {
  flex: 1;
  font-size: 28rpx;
}
.format-size {
  font-size: 24rpx;
  color: #999;
  margin-right: 16rpx;
}
.format-check {
  color: #b8ff26;
  font-weight: 700;
}
.btn-primary {
  background: #b8ff26;
  color: #fff;
  border-radius: 12rpx;
  font-size: 30rpx;
}
.btn-primary[disabled] {
  background: #b6cbfb;
}
.bottom {
  margin-top: 24rpx;
}
</style>
