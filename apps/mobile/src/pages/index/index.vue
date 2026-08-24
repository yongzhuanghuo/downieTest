<template>
  <view class="page">
    <!-- 顶部导航栏 -->
    <view class="navbar" :style="{ paddingTop: statusBarHeight + 'px' }">
      <view class="navbar-inner">
        <view class="logo">4K</view>
        <text class="app-name">4KDownle</text>
        <view class="navbar-right">
          <view class="nav-btn" @tap="toast('暂无通知')">
            <text class="nav-emoji">🔔</text>
          </view>
          <view class="nav-btn avatar" @tap="goMine">
            <text class="nav-emoji">👤</text>
          </view>
        </view>
      </view>
    </view>

    <!-- Banner -->
    <view class="banner">
      <text class="banner-title">全能视频下载工具</text>
      <text class="banner-sub">支持1000+网站视频下载</text>
      <view class="banner-tag">多平台支持 iOS · Android · 小程序 · H5</view>
      <view class="banner-icons">
        <view class="icon-badge" v-for="(e, i) in bannerIcons" :key="i" :style="e.badgeStyle">
          <image :src="e.src" class="icon-img" />
        </view>
      </view>
    </view>

    <!-- 链接下载视频 -->
    <text class="section-title">链接下载视频</text>
    <view class="input-row">
      <input
        v-model="url"
        class="input"
        placeholder="粘贴视频链接（支持抖音/微信/YouTube等）"
        placeholder-class="ph"
        @confirm="onParse"
      />
      <view class="paste-btn" @tap="paste">📋</view>
    </view>
    <button class="btn-primary download-btn" :disabled="!url.trim()" @tap="onParse">
      ⬇ 立即下载
    </button>

    <!-- 视频工具 -->
    <view class="section-head">
      <text class="section-title">视频工具</text>
      <text class="view-all" @tap="viewAll">查看全部</text>
    </view>
    <view class="tool-grid">
      <view class="tool-card" v-for="t in tools" :key="t.name" @tap="onTool(t)">
        <view class="tool-icon-wrap" :style="{ background: t.bg }">
          <text class="tool-icon">{{ t.icon }}</text>
        </view>
        <text class="tool-name">{{ t.name }}</text>
        <text class="tool-desc">{{ t.desc }}</text>
      </view>
    </view>
  </view>
</template>

<script>
const URL_RE = /(https?:\/\/[^\s]+)/

export default {
  data() {
    return {
      statusBarHeight: 20,
      url: '',
      bannerIcons: [
        { src: '/static/icons/youtube.svg', badgeStyle: { top: '16rpx', right: '40rpx', background: '#FF0000' } },
        { src: '/static/icons/bilibili.svg', badgeStyle: { top: '66rpx', right: '120rpx', background: '#00A1D6' } },
        { src: '/static/icons/tiktok.svg', badgeStyle: { top: '26rpx', right: '210rpx', background: '#25F4EE' } },
        { src: '/static/icons/kuaishou.svg', badgeStyle: { top: '106rpx', right: '16rpx', background: '#FF4906' } },
        { src: '/static/icons/xiaohongshu.svg', badgeStyle: { top: '120rpx', right: '180rpx', background: '#FF2442' } },
        { src: '/static/icons/instagram.svg', badgeStyle: { top: '160rpx', right: '70rpx', background: '#E4405F' } },
      ],
      tools: [
        { name: '去水印', desc: '框选擦拭水印', icon: '💧', bg: 'rgba(255,122,26,0.15)', path: '/pages/delogo/delogo' },
        { name: '加水印', desc: '文字/图片水印', icon: '🖊️', bg: 'rgba(74,144,217,0.15)', path: '/pages/watermark/watermark' },
        { name: 'MD5修改', desc: '一键修改视频MD5', icon: '#️⃣', bg: 'rgba(7,193,96,0.15)', path: '/pages/md5/md5' },
        { name: '转GIF', desc: '视频片段转动图', icon: '🖼️', bg: 'rgba(255,122,26,0.15)', path: '/pages/gif/gif' },
      ],
    }
  },
  onLoad() {
    const info = uni.getSystemInfoSync()
    this.statusBarHeight = info.statusBarHeight || 20
  },
  onShow() {
    this.readClipboard()
  },
  methods: {
    readClipboard() {
      if (this.url.trim()) return
      uni.getClipboardData({
        success: (res) => {
          const m = (res.data || '').match(URL_RE)
          if (m) {
            this.url = m[1]
            uni.showToast({ title: '已粘贴链接，点击立即下载', icon: 'none' })
          }
        },
      })
    },
    paste() {
      uni.getClipboardData({
        success: (res) => {
          if (res.data) this.url = res.data
        },
      })
    },
    onParse() {
      const u = this.url.trim()
      if (!u) return
      uni.navigateTo({ url: `/pages/parse/parse?url=${encodeURIComponent(u)}` })
    },
    onTool(t) {
      if (t.path) uni.navigateTo({ url: t.path })
    },
    viewAll() {
      uni.showToast({ title: '功能开发中', icon: 'none' })
    },
    goMine() {
      uni.switchTab({ url: '/pages/mine/mine' })
    },
    toast(msg) {
      uni.showToast({ title: msg, icon: 'none' })
    },
  },
}
</script>

<style scoped>
.page {
  min-height: 100vh;
  padding: 0 24rpx 40rpx;
}
.navbar {
  padding-bottom: 16rpx;
}
.navbar-inner {
  display: flex;
  align-items: center;
  height: 88rpx;
}
.logo {
  width: 64rpx;
  height: 64rpx;
  border-radius: 16rpx;
  background: linear-gradient(135deg, #b8ff26, #6c5ce7);
  color: #0a0a0a;
  font-size: 30rpx;
  font-weight: 800;
  display: flex;
  align-items: center;
  justify-content: center;
}
.app-name {
  margin-left: 16rpx;
  color: #fff;
  font-size: 34rpx;
  font-weight: 700;
}
.navbar-right {
  margin-left: auto;
  display: flex;
  gap: 20rpx;
}
.nav-btn {
  width: 64rpx;
  height: 64rpx;
  border-radius: 50%;
  background: #1e1e1e;
  display: flex;
  align-items: center;
  justify-content: center;
}
.nav-emoji {
  font-size: 32rpx;
}
.banner {
  position: relative;
  margin-top: 8rpx;
  border-radius: 24rpx;
  padding: 32rpx;
  background: linear-gradient(135deg, #6c5ce7, #4a90d9);
  overflow: hidden;
}
.banner-title {
  display: block;
  color: #fff;
  font-size: 44rpx;
  font-weight: 800;
}
.banner-sub {
  display: block;
  margin-top: 12rpx;
  color: rgba(255, 255, 255, 0.8);
  font-size: 26rpx;
}
.banner-tag {
  display: inline-block;
  margin-top: 24rpx;
  padding: 8rpx 20rpx;
  border-radius: 24rpx;
  background: #b8ff26;
  color: #0a0a0a;
  font-size: 22rpx;
  font-weight: 600;
}
.banner-icons {
  position: absolute;
  top: 0;
  right: 0;
  width: 320rpx;
  height: 100%;
}
.icon-badge {
  position: absolute;
  width: 64rpx;
  height: 64rpx;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4rpx 12rpx rgba(0, 0, 0, 0.3);
}
.icon-img {
  width: 40rpx;
  height: 40rpx;
}
.section-title {
  display: block;
  margin: 36rpx 0 20rpx;
  color: #fff;
  font-size: 32rpx;
  font-weight: 700;
}
.input-row {
  display: flex;
  align-items: center;
  background: #1e1e1e;
  border-radius: 24rpx;
  padding: 0 24rpx;
}
.input {
  flex: 1;
  height: 96rpx;
  color: #fff;
  font-size: 28rpx;
}
.ph {
  color: #666;
}
.paste-btn {
  padding: 12rpx;
  font-size: 36rpx;
}
.download-btn {
  margin-top: 24rpx;
}
.section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 36rpx;
}
.view-all {
  color: #4a90d9;
  font-size: 24rpx;
}
.tool-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 20rpx;
}
.tool-card {
  width: calc(50% - 10rpx);
  background: #1e1e1e;
  border-radius: 24rpx;
  padding: 28rpx;
  box-sizing: border-box;
}
.tool-icon-wrap {
  width: 80rpx;
  height: 80rpx;
  border-radius: 20rpx;
  display: flex;
  align-items: center;
  justify-content: center;
}
.tool-icon {
  font-size: 44rpx;
}
.tool-name {
  display: block;
  margin-top: 20rpx;
  color: #fff;
  font-size: 30rpx;
  font-weight: 600;
}
.tool-desc {
  display: block;
  margin-top: 8rpx;
  color: #777;
  font-size: 22rpx;
}
</style>
