import { query, now } from './db.js';
import { hashPassword } from './lib/password.js';

// Tạo tài khoản admin lần đầu khởi động (idempotent). Trên K8s: set qua Secret.
export async function seedAdmin() {
  const email = (process.env.ADMIN_EMAIL || '').toLowerCase();
  const password = process.env.ADMIN_PASSWORD;
  if (!email || !password) return;
  const { rows } = await query('SELECT id FROM users WHERE email = $1', [email]);
  if (rows[0]) return;
  const passwordHash = await hashPassword(password);
  await query(
    "INSERT INTO users (email, password_hash, full_name, role, created_at) VALUES ($1, $2, 'Quản trị viên', 'admin', $3)",
    [email, passwordHash, now()]
  );
  console.log(`[seed] created admin account ${email}`);
}
