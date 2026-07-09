import { scrypt, randomBytes, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scryptAsync = promisify(scrypt);

// Dùng scrypt built-in của Node (khuyến nghị OWASP) — khỏi cần dependency bcrypt.
// Định dạng lưu: "<salt-hex>:<hash-hex>"
export async function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const buf = await scryptAsync(password, salt, 64);
  return `${salt}:${buf.toString('hex')}`;
}

export async function verifyPassword(password, stored) {
  const [salt, hashHex] = String(stored).split(':');
  if (!salt || !hashHex) return false;
  const buf = await scryptAsync(password, salt, 64);
  const expected = Buffer.from(hashHex, 'hex');
  return expected.length === buf.length && timingSafeEqual(buf, expected);
}
