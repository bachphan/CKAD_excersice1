import { Router } from 'express';
import { query } from '../db.js';
import { requireAuth, requireAdmin } from '../lib/auth.js';
import { intParam } from '../lib/validate.js';

const router = Router();

function toApi(row) {
  return {
    id: row.id,
    channel: row.channel,
    orderId: row.order_id,
    userId: row.user_id,
    message: row.message,
    payload: row.payload,
    createdAt: row.created_at,
  };
}

// GET /api/notifications — admin xem toàn bộ notification đã "gửi" (bằng chứng consumer thật
// đã xử lý event Redis Pub/Sub, không chỉ khai báo trên giấy)
router.get('/', requireAuth, requireAdmin, async (req, res) => {
  const limit = intParam(req.query.limit, 20, 1, 100);
  const page = intParam(req.query.page, 1, 1, 100000);
  const totalResult = await query('SELECT COUNT(*) AS total FROM notifications');
  const total = Number(totalResult.rows[0].total);
  const { rows } = await query('SELECT * FROM notifications ORDER BY id DESC LIMIT $1 OFFSET $2', [limit, (page - 1) * limit]);
  res.json({ items: rows.map(toApi), total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)) });
});

export default router;
