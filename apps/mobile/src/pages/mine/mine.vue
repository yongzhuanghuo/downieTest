<template>
  <view class="page">
    <view class="notice-card">
      <text class="notice-title">使用须知</text>
      <text class="notice-text">本工具仅供个人学习、备份已授权内容使用。请勿下载或传播侵犯他人版权的视频，用户需对自身使用行为负责。</text>
    </view>

    <view class="list">
      <view class="list-item" @tap="toast('开发中')">
        <text class="list-icon">📁</text>
        <text class="list-label">下载历史</text>
      </view>
      <view class="list-item" @tap="toast('开发中')">
        <text class="list-icon">🎞️</text>
        <text class="list-label">去水印历史</text>
      </view>
      <view class="list-item" @tap="toast('开发中')">
        <text class="list-icon">⭐</text>
        <text class="list-label">收藏</text>
      </view>
      <view class="list-item" @tap="toast('开发中')">
        <text class="list-icon">⚙️</text>
        <text class="list-label">设置</text>
      </view>
      <view class="list-item" @tap="toast('开发中')">
        <text class="list-icon">📮</text>
        <text class="list-label">反馈 / 关于</text>
      </view>
    </view>

    <view class="version">v0.1.0</view>
  </view>
</template>

<script>
export default {
  methods: {
    toast(msg) {
      uni.showToast({ title: msg, icon: 'none' })
    },
  },
}
</script>

<style scoped>
.page {
  padding: 24rpx;
}
.notice-card {
  background: #241a0e;
  border-radius: 16rpx;
  padding: 24rpx;
}
.notice-title {
  display: block;
  font-size: 28rpx;
  font-weight: 600;
  color: #ffa94d;
  margin-bottom: 12rpx;
}
.notice-text {
  display: block;
  font-size: 24rpx;
  color: #b08968;
  line-height: 1.6;
}
.list {
  margin-top: 24rpx;
  background: #1e1e1e;
  border-radius: 16rpx;
  overflow: hidden;
}
.list-item {
  display: flex;
  align-items: center;
  padding: 28rpx 24rpx;
  border-bottom: 1rpx solid #2a2a2a;
}
.list-icon {
  font-size: 36rpx;
  margin-right: 20rpx;
}
.list-label {
  font-size: 28rpx;
}
.version {
  margin-top: 48rpx;
  text-align: center;
  font-size: 24rpx;
  color: #555;
}
</style>
