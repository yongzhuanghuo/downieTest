<template>
  <view class="launch">
    <view class="content">
      <view class="title-wrap">
        <text class="title">强大的</text>
        <text class="title title-red">视频搬运工具</text>
      </view>
      <text class="subtitle">支持海量国内外各大常用视频平台</text>

      <view class="icons">
        <view
          class="icon-item"
          v-for="(p, i) in platforms"
          :key="i"
          :style="{ top: p.top, left: p.left, background: p.bg }"
        >
          <text class="icon-emoji">{{ p.emoji }}</text>
        </view>
      </view>
    </view>

    <view class="download" @tap="onEnter">
      <text class="download-icon">⬇</text>
      <text class="download-text">立即进入</text>
    </view>
  </view>
</template>

<script>
export default {
  data() {
    return {
      platforms: [
        { emoji: '⚡', bg: '#ff7a1a', top: '18%', left: '10%' },
        { emoji: '▶️', bg: '#ff0000', top: '8%', left: '42%' },
        { emoji: '📷', bg: '#c13584', top: '20%', left: '72%' },
        { emoji: '💬', bg: '#07c160', top: '40%', left: '6%' },
        { emoji: '🐦', bg: '#1da1f2', top: '34%', left: '84%' },
        { emoji: '🎵', bg: '#161823', top: '58%', left: '16%' },
        { emoji: '📕', bg: '#ff2442', top: '62%', left: '70%' },
        { emoji: '🔵', bg: '#e6162d', top: '72%', left: '38%' },
        { emoji: '📰', bg: '#ff4d4f', top: '48%', left: '50%' },
      ],
    }
  },
  onLoad() {
    // 仅首次启动显示，之后直接进首页
    if (uni.getStorageSync('has_launched')) {
      uni.switchTab({ url: '/pages/index/index' })
    }
  },
  methods: {
    onEnter() {
      uni.setStorageSync('has_launched', true)
      uni.switchTab({ url: '/pages/index/index' })
    },
  },
}
</script>

<style scoped>
.launch {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background: linear-gradient(135deg, #1a0b2e, #6c5ce7, #4a90d9, #121212);
  background-size: 300% 300%;
  animation: flow 12s ease infinite;
}
@keyframes flow {
  0% { background-position: 0% 50%; }
  50% { background-position: 100% 50%; }
  100% { background-position: 0% 50%; }
}
.content {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding-top: 160rpx;
}
.title-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
}
.title {
  color: #ffffff;
  font-size: 60rpx;
  font-weight: 800;
  line-height: 1.4;
}
.title-red {
  color: #ff3b30;
}
.subtitle {
  margin-top: 24rpx;
  color: rgba(255, 255, 255, 0.7);
  font-size: 28rpx;
}
.icons {
  position: relative;
  width: 600rpx;
  height: 560rpx;
  margin-top: 40rpx;
}
.icon-item {
  position: absolute;
  width: 96rpx;
  height: 96rpx;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8rpx 24rpx rgba(0, 0, 0, 0.3);
}
.icon-emoji {
  font-size: 48rpx;
}
.download {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding-bottom: 100rpx;
}
.download-icon {
  width: 120rpx;
  height: 120rpx;
  border-radius: 50%;
  background: #b8ff26;
  color: #0a0a0a;
  font-size: 56rpx;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8rpx 32rpx rgba(184, 255, 38, 0.5);
}
.download-text {
  margin-top: 16rpx;
  color: rgba(255, 255, 255, 0.8);
  font-size: 26rpx;
}
</style>
