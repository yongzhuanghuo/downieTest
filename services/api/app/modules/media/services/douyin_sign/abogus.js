const fs = require('fs');
const path = require('path');

// 屏蔽算法内部的调试日志（utils.js 里 programVersion=G_DEBUG 会打印大量 digest/rc4）
console.log = () => {};
console.debug = () => {};

// 补浏览器环境（utils.js 里 EnvTestTurnOn=false，环境检测已关闭）
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
global.window = global;
Object.assign(global.window, {
  innerWidth: 2048,
  innerHeight: 960,
  outerWidth: 2554,
  outerHeight: 1386,
});
global.window.screen = { width: 2560, height: 1440, availWidth: 2560, availHeight: 1392 };
global.navigator = { platform: "Win32", userAgent: UA, vendorSubs: {} };
global.performance = { now: () => Date.now() };

// 合并加载三个 JS 文件（一次 eval，避免 vm_decode.js 顶层 var U hoisting 遮蔽）
const dir = __dirname;
const code = ['utils.js', 'sm3.js', 'vm_decode.js']
  .map((f) => fs.readFileSync(path.join(dir, f), 'utf8'))
  .join('\n');
eval(code);

// 从命令行参数读 uri（query 字符串），输出 a_bogus
const uri = process.argv[2] || '';
if (!uri) {
  console.error('usage: node abogus.js <uri>');
  process.exit(1);
}
const ab = makeABogus(uri, 0);
process.stdout.write(ab);
