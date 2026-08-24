<script>
export default {
  onLaunch() {
    console.log('4KDownle Launch')
  },
}
</script>

<style lang="scss">
@import 'uview-plus/index.scss';

/* 全局暗黑样式 */
page {
  background-color: #121212;
  color: #ffffff;
  font-size: 28rpx;
  line-height: 1.5;
}

/* 公共主按钮：亮绿 */
.btn-primary {
  background: #b8ff26 !important;
  color: #0a0a0a !important;
  border-radius: 24rpx;
  font-size: 30rpx;
  font-weight: 600;
}
.btn-primary[disabled] {
  background: #3a4020 !important;
  color: #777 !important;
}

/* 公共次级按钮 */
.btn-plain {
  background: #1e1e1e !important;
  color: #b8ff26 !important;
  border: 2rpx solid #b8ff26 !important;
  border-radius: 24rpx;
  font-size: 30rpx;
}

/* H5 端 tabBar 文字大小兜底（App/小程序端用 pages.json 的 fontSize） */
.uni-tabbar__label {
  font-size: 14px !important;
}
</style>
