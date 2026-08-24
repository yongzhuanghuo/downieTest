// 后端接口封装
// H5 环境：自动用当前访问的 host（手机访问局域网 IP 时，API 指向同 IP 的后端 8000 端口）
// 小程序 / App 环境：改成后端实际地址（局域网 IP 或部署域名）
const BASE_URL = (() => {
  // #ifdef H5
  const host = location.hostname
  if (host && host !== 'localhost' && host !== '127.0.0.1') {
    return `http://${host}:8000`
  }
  // #endif
  return 'http://127.0.0.1:8000'
})()

export function fullUrl(path) {
  if (path && path.startsWith('http')) return path
  return BASE_URL + path
}

export function request(url, method = 'GET', data = {}) {
  return new Promise((resolve, reject) => {
    uni.request({
      url: fullUrl(url),
      method,
      data,
      timeout: 60000,
      success: (res) => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(res.data)
        } else {
          const msg = (res.data && res.data.detail) || `请求失败(${res.statusCode})`
          reject(new Error(msg))
        }
      },
      fail: (err) => reject(new Error(err.errMsg || '网络错误')),
    })
  })
}

export const api = {
  parse: (url) => request('/api/parse', 'POST', { url }),
  download: (url, format_id) => request('/api/download', 'POST', { url, format_id }),
  task: (task_id) => request(`/api/task/${task_id}`),
  delogoPreview: (filePath) =>
    new Promise((resolve, reject) => {
      uni.uploadFile({
        url: fullUrl('/api/delogo/preview'),
        filePath,
        name: 'file',
        success: (res) => {
          try {
            resolve(JSON.parse(res.data))
          } catch (e) {
            reject(new Error('上传响应解析失败'))
          }
        },
        fail: (err) => reject(new Error(err.errMsg || '上传失败')),
      })
    }),
  delogoFrame: (video_id, timestamp) => request('/api/delogo/frame', 'POST', { video_id, timestamp }),
  delogoProcess: (video_id, segments) => request('/api/delogo/process', 'POST', { video_id, segments }),
  uploadImage: (filePath) =>
    new Promise((resolve, reject) => {
      uni.uploadFile({
        url: fullUrl('/api/upload/image'),
        filePath,
        name: 'file',
        success: (res) => {
          try {
            resolve(JSON.parse(res.data))
          } catch (e) {
            reject(new Error('上传图片失败'))
          }
        },
        fail: (err) => reject(new Error(err.errMsg || '上传失败')),
      })
    }),
  watermarkProcess: (params) => request('/api/watermark/process', 'POST', params),
  md5Process: (video_id) => request('/api/md5/process', 'POST', { video_id }),
  gifProcess: (params) => request('/api/gif/process', 'POST', params),
  fonts: () => request('/api/fonts'),
}

export default api
