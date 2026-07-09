import { Router } from 'express';
import { query, now } from '../db.js';
import { hashPassword, verifyPassword } from '../lib/password.js';
import { signToken } from '../lib/auth.js';
import { validateBody } from '../lib/validate.js';
import { ApiError } from '../lib/errors.js';

const router = Router();

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function toApi(row) {
  return {
    id: row.id,
    email: row.email,
    fullName: row.full_name,
    phone: row.phone,
    address: row.address,
    role: row.role,
    createdAt: row.created_at,
  };
}

// POST /api/auth/register
router.post('/register', async (req, res) => {
  const d = validateBody(req.body, {
    email: { type: 'string', required: true, maxLen: 200, pattern: EMAIL_PATTERN },
    password: { type: 'string', required: true, minLen: 8, maxLen: 100, noTrim: true },
    fullName: { type: 'string', required: true, maxLen: 100 },
  });
  const email = d.email.toLowerCase();
  const existing = await query('SELECT id FROM users WHERE email = $1', [email]);
  if (existing.rows[0]) {
    throw new ApiError(409, 'Email này đã được đăng ký');
  }
  const passwordHash = await hashPassword(d.password);
  const { rows } = await query(
    "INSERT INTO users (email, password_hash, full_name, role, created_at) VALUES ($1, $2, $3, 'customer', $4) RETURNING *",
    [email, passwordHash, d.fullName, now()]
  );
  const user = rows[0];
  res.status(201).json({ token: signToken(user), user: toApi(user) });
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const d = validateBody(req.body, {
    email: { type: 'string', required: true, maxLen: 200 },
    password: { type: 'string', required: true, maxLen: 100, noTrim: true },
  });
  const { rows } = await query('SELECT * FROM users WHERE email = $1', [d.email.toLowerCase()]);
  const user = rows[0];
  // Cùng một thông báo cho "sai email" và "sai mật khẩu" — không lộ email nào đã tồn tại.
  if (!user || !(await verifyPassword(d.password, user.password_hash))) {
    throw new ApiError(401, 'Email hoặc mật khẩu không đúng');
  }
  res.json({ token: signToken(user), user: toApi(user) });
});

export default router;
export { toApi };
