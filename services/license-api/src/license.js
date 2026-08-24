import crypto from 'node:crypto';

/**
 * 激活码工具（数据库随机码方案）。
 *
 * 激活码是服务端生成的一串随机字符，直接存进 licenses 表；
 * 激活时按规范化后的码查库，命中且未吊销/未超设备数才算成功。
 * 客户端不持有任何密钥、不参与签名，因此无法离线伪造激活码。
 */

// 32 字符字母表（去掉易混字符 0/1/O/I）
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/**
 * 生成一个随机激活码（默认 20 位，约 100 bit 熵）。
 * 256 % 32 === 0，所以 `b % 32` 无取模偏差。
 */
export function generateCode(length = 20) {
  const bytes = crypto.randomBytes(length);
  let out = '';
  for (const b of bytes) out += ALPHABET[b % ALPHABET.length];
  return out;
}

/**
 * 规范化用户输入的激活码：去分隔符 + 统一大写。
 * 数据库里存的是无分隔符的大写原始串。
 */
export function normalizeCode(input) {
  return String(input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
}

/**
 * 把原始 20 位串格式化成 XXXX-XXXX-XXXX-XXXX（仅用于展示/导出）。
 */
export function formatCode(raw) {
  return raw.replace(/(.{5})/g, '$1-').replace(/-$/, '');
}
