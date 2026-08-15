import fs from 'node:fs';
import { createPool } from '../src/db.js';
import { generateCode, formatCode } from '../src/license.js';

/**
 * 生成激活码并写入数据库，输出 CSV。
 *
 * 用法：
 *   node scripts/generate-licenses.js -c 10 -t perpetual
 *   node scripts/generate-licenses.js -c 5 -t free -e 30 -o trial.csv
 *
 * 选项：
 *   -t, --type     free | perpetual     (默认 perpetual)
 *   -d, --devices  最大设备数            (默认 free=1 perpetual=4)
 *   -e, --expire   过期天数              (默认 0=永不过期)
 *   -c, --count    生成数量              (默认 1)
 *   -o, --output   CSV 输出文件          (默认 stdout)
 */

function parseArgs(argv) {
  const opts = { count: 1, type: 'perpetual', devices: null, expireDays: 0, output: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '-t':
      case '--type':
        opts.type = argv[++i];
        break;
      case '-d':
      case '--devices':
        opts.devices = parseInt(argv[++i], 10);
        break;
      case '-e':
      case '--expire':
        opts.expireDays = parseInt(argv[++i], 10);
        break;
      case '-c':
      case '--count':
        opts.count = parseInt(argv[++i], 10);
        break;
      case '-o':
      case '--output':
        opts.output = argv[++i];
        break;
      default:
        console.error(`未知参数: ${a}`);
        printHelp();
        process.exit(1);
    }
  }
  return opts;
}

function printHelp() {
  console.log(`
用法: node scripts/generate-licenses.js [options]

  -t, --type       free | perpetual   (默认 perpetual)
  -d, --devices    最大设备数          (默认 free=1 perpetual=4)
  -e, --expire     过期天数            (默认 0=永不过期)
  -c, --count      生成数量            (默认 1)
  -o, --output     CSV 输出文件        (默认 stdout)

示例:
  node scripts/generate-licenses.js -c 5 -t perpetual -o pro.csv
  node scripts/generate-licenses.js -c 10 -t free -e 30 -o trial.csv
`);
}

// 生成单个码并入库；极小概率撞码时重试
async function insertOne(pool, { type, maxDevices, expireAt }) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const raw = generateCode();
    try {
      await pool.execute(
        'INSERT INTO licenses (code, type, max_devices, expire_at) VALUES (?, ?, ?, ?)',
        [raw, type, maxDevices, expireAt],
      );
      return raw;
    } catch (e) {
      if (e.code === 'ER_DUP_ENTRY') continue; // 撞码，重试
      throw e;
    }
  }
  throw new Error('生成失败：多次撞码，请重试');
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const type = opts.type === 'free' ? 'free' : 'perpetual';
  const maxDevices = opts.devices ?? (type === 'perpetual' ? 4 : 1);
  const expireAt = opts.expireDays <= 0 ? null : Date.now() + opts.expireDays * 86400 * 1000;

  const pool = await createPool();
  const raws = [];
  try {
    for (let i = 0; i < opts.count; i++) {
      raws.push(await insertOne(pool, { type, maxDevices, expireAt }));
    }
  } finally {
    await pool.end();
  }

  const rows = ['activation_code,type,max_devices,expire_at_ts,expire_days'];
  for (const raw of raws) {
    rows.push(`${formatCode(raw)},${type},${maxDevices},${expireAt ?? 0},${opts.expireDays}`);
  }
  const out = rows.join('\n') + '\n';

  if (opts.output) {
    fs.writeFileSync(opts.output, out);
    console.log(`✅ 已生成 ${raws.length} 个激活码 -> ${opts.output}`);
  } else {
    process.stdout.write(out);
  }
}

main().catch((e) => {
  console.error('生成失败:', e.message);
  process.exit(1);
});
