import { Router } from 'express';
import { db, now } from '../db.js';
import { requireAuth } from '../lib/auth.js';
import { validateBody } from '../lib/validate.js';
import { ApiError } from '../lib/errors.js';
import { toApi } from './auth.js';

const router = Router();

// GET /api/users/me
router.get('/me', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!row) throw new ApiError(404, 'Tài khoản không còn tồn tại');
  res.json(toApi(row));
});

// PUT /api/users/me — cập nhật hồ sơ (không đổi email/role qua đây)
router.put('/me', requireAuth, (req, res) => {
  const row = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);
  if (!row) throw new ApiError(404, 'Tài khoản không còn tồn tại');
  const d = validateBody(req.body, {
    fullName: { type: 'string', required: true, maxLen: 100 },
    phone: { type: 'string', maxLen: 20, pattern: /^[0-9+ .()-]*$/ },
    address: { type: 'string', maxLen: 300 },
  });
  db.prepare('UPDATE users SET full_name = ?, phone = ?, address = ? WHERE id = ?')
    .run(d.fullName, d.phone ?? row.phone, d.address ?? row.address, req.user.id);
  res.json(toApi(db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id)));
});

export default router;
