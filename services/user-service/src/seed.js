import { db, now } from './db.js';
import { hashPassword } from './lib/password.js';

// Tạo tài khoản admin lần đầu khởi động (idempotent). Trên K8s: set qua Secret.
export async function seedAdmin() {
  const email = (process.env.ADMIN_EMAIL || '').toLowerCase();
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password) return;
  if (db.prepare('SELECT id FROM users WHERE email = ?').get(email)) return;
  const passwordHash = await hashPassword(password);
  db.prepare("INSERT INTO users (email, password_hash, full_name, role, created_at) VALUES (?, ?, 'Quản trị viên', 'admin', ?)")
    .run(email, passwordHash, now());
  console.log(`[seed] created admin account ${email}`);
}
