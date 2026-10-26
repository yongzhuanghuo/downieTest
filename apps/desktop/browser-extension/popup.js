const tokenInput = document.getElementById('token');
const sendButton = document.getElementById('send');
const status = document.getElementById('status');
const pageUrl = document.getElementById('page-url');

let currentUrl = '';

function setStatus(text, kind) {
  status.textContent = text;
  status.className = kind || '';
}

chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
  const tab = tabs && tabs[0];
  currentUrl = tab && tab.url ? tab.url : '';
  pageUrl.textContent = currentUrl || '无法读取当前页面地址';
  if (!currentUrl || !/^https?:\/\//.test(currentUrl)) {
    setStatus('当前页面不是普通网页，无法发送', 'error');
    sendButton.disabled = true;
  }
});

chrome.storage.local.get({ token: '' }, (values) => {
  tokenInput.value = values.token || '';
});

tokenInput.addEventListener('input', () => {
  chrome.storage.local.set({ token: tokenInput.value.trim() });
});

sendButton.addEventListener('click', async () => {
  const token = tokenInput.value.trim();
  if (!token) {
    setStatus('请先填写 token', 'error');
    return;
  }
  if (!currentUrl) {
    setStatus('没有可发送的页面', 'error');
    return;
  }

  sendButton.disabled = true;
  setStatus('正在发送…');
  try {
    const endpoint =
      'http://127.0.0.1:8765/add?url=' +
      encodeURIComponent(currentUrl) +
      '&token=' +
      encodeURIComponent(token);
    const response = await fetch(endpoint, { method: 'GET' });
    const text = await response.text();
    if (!response.ok) {
      setStatus(text || `发送失败（${response.status}）`, 'error');
    } else {
      setStatus(text || '已加入下载队列', 'ok');
    }
  } catch (error) {
    setStatus('无法连接 Downie6，请确认应用已启动并开启端口', 'error');
  } finally {
    sendButton.disabled = false;
  }
});
