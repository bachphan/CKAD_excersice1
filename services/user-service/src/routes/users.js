import { Router } from 'express';
import { query } from '../db.js';
import { requireAuth } from '../lib/auth.js';
import { validateBody } from '../lib/validate.js';
import { ApiError } from '../lib/errors.js';
import { toApi } from './auth.js';

const router = Router();

// GET /api/users/me
router.get('/me', requireAuth, async (req, res) => {
  const { rows } = await query('SELECT * FROM users WHERE id = $1', [req.user.id]);
  if (!rows[0]) throw new ApiError(404, 'Tài khoản không còn tồn tại');
  res.json(toApi(rows[0]));
});

// PUT /api/users/me — cập nhật hồ sơ (không đổi email/role qua đây)
router.put('/me', requireAuth, async (req, res) => {
  const existing = await query('SELECT * FROM users WHERE id = $1', [req.user.id]);
  const row = existing.rows[0];
  if (!row) throw new ApiError(404, 'Tài khoản không còn tồn tại');
  const d = validateBody(req.body, {
    fullName: { type: 'string', required: true, maxLen: 100 },
    phone: { type: 'string', maxLen: 20, pattern: /^[0-9+ .()-]*$/ },
    address: { type: 'string', maxLen: 300 },
  });
  const { rows } = await query(
    'UPDATE users SET full_name = $1, phone = $2, address = $3 WHERE id = $4 RETURNING *',
    [d.fullName, d.phone ?? row.phone, d.address ?? row.address, req.user.id]
  );
  res.json(toApi(rows[0]));
});

export default router;
