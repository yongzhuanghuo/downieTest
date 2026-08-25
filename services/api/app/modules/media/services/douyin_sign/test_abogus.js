const fs = require('fs');
const path = require('path');

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
global.navigator = { platform: "Win32", userAgent: UA };
global.performance = { now: () => Date.now() };

// 加载三个 JS 文件（合并成一次 eval，避免 vm_decode.js 顶层 var U hoisting 遮蔽）
const dir = __dirname;
const code = ['utils.js', 'sm3.js', 'vm_decode.js']
  .map((f) => fs.readFileSync(path.join(dir, f), 'utf8'))
  .join('\n');
eval(code);

const uri = "device_platform=webapp&aid=6383&channel=channel_pc_web&aweme_id=7676713464924018859";
try {
  const ab = makeABogus(uri, 0);
  console.log("✅ a_bogus:", ab);
  console.log("length:", ab.length);
} catch (e) {
  console.log("❌ 报错:", e.message);
  console.log(e.stack);
}
