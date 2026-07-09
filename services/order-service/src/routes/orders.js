import { Router } from 'express';
import { pool, query, now } from '../db.js';
import { requireAuth, requireAdmin } from '../lib/auth.js';
import { validateBody, intParam } from '../lib/validate.js';
import { ApiError } from '../lib/errors.js';
import { checkoutStock, restock } from '../productClient.js';

const router = Router();

const STATUSES = ['confirmed', 'shipping', 'completed', 'cancelled'];
const PAYMENT_METHODS = ['cod', 'bank_transfer'];

function toApi(order, items) {
  return {
    id: order.id,
    userId: order.user_id,
    status: order.status,
    total: order.total,
    paymentMethod: order.payment_method,
    shipping: { fullName: order.shipping_name, phone: order.shipping_phone, address: order.shipping_address },
    items: items.map((i) => ({
      productId: i.product_id,
      productName: i.product_name,
      unitPrice: i.unit_price,
      quantity: i.quantity,
    })),
    createdAt: order.created_at,
    updatedAt: order.updated_at,
  };
}

async function getItemsFor(orderId) {
  const { rows } = await query('SELECT * FROM order_items WHERE order_id = $1 ORDER BY id', [orderId]);
  return rows;
}

async function loadOrder(id) {
  if (!Number.isInteger(id)) return null;
  const { rows } = await query('SELECT * FROM orders WHERE id = $1', [id]);
  const order = rows[0];
  return order ? toApi(order, await getItemsFor(order.id)) : null;
}

// Gộp item trùng productId, validate số lượng — cùng giới hạn với product-service.
function parseItems(body) {
  const items = body?.items;
  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw new ApiError(400, 'Giỏ hàng trống hoặc quá nhiều mặt hàng (tối đa 50)');
  }
  const merged = new Map();
  for (const it of items) {
    const id = it?.productId;
    const qty = it?.quantity;
    if (!Number.isInteger(id) || id <= 0) throw new ApiError(400, 'productId không hợp lệ');
    if (!Number.isInteger(qty) || qty <= 0 || qty > 100) throw new ApiError(400, 'Số lượng mỗi mặt hàng phải từ 1 đến 100');
    merged.set(id, (merged.get(id) || 0) + qty);
  }
  return [...merged].map(([productId, quantity]) => ({ productId, quantity }));
}

async function createOrderTx(userId, shipping, paymentMethod, lines) {
  const total = lines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0);
  const ts = now();
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query(
      `INSERT INTO orders (user_id, status, total, payment_method, shipping_name, shipping_phone, shipping_address, created_at, updated_at)
       VALUES ($1, 'confirmed', $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
      [userId, total, paymentMethod, shipping.fullName, shipping.phone, shipping.address, ts, ts]
    );
    const orderId = rows[0].id;
    for (const l of lines) {
      await client.query(
        'INSERT INTO order_items (order_id, product_id, product_name, unit_price, quantity) VALUES ($1, $2, $3, $4, $5)',
        [orderId, l.productId, l.name, l.unitPrice, l.quantity]
      );
    }
    await client.query('COMMIT');
    return orderId;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

// POST /api/orders — checkout (thanh toán giả lập: đơn được xác nhận ngay)
router.post('/', requireAuth, async (req, res) => {
  const shipping = validateBody(req.body, {
    fullName: { type: 'string', required: true, maxLen: 100 },
    phone: { type: 'string', required: true, minLen: 8, maxLen: 20, pattern: /^[0-9+ .()-]+$/ },
    address: { type: 'string', required: true, maxLen: 300 },
    paymentMethod: { type: 'string', required: true, enum: PAYMENT_METHODS },
  });
  const items = parseItems(req.body);

  // Bước 1: trừ kho nguyên tử bên product-service — giá/tên lấy từ đó, KHÔNG tin client.
  const lines = await checkoutStock(items);

  // Bước 2: ghi đơn hàng local. Nếu ghi lỗi (rất hiếm) thì hoàn kho lại (best effort).
  let orderId;
  try {
    orderId = await createOrderTx(req.user.id, shipping, shipping.paymentMethod, lines);
  } catch (e) {
    await restock(items);
    throw e;
  }
  res.status(201).json(await loadOrder(orderId));
});

// GET /api/orders/mine — lịch sử đơn của user đang đăng nhập
router.get('/mine', requireAuth, async (req, res) => {
  const limit = intParam(req.query.limit, 10, 1, 50);
  const page = intParam(req.query.page, 1, 1, 100000);
  const totalResult = await query('SELECT COUNT(*) AS total FROM orders WHERE user_id = $1', [req.user.id]);
  const total = Number(totalResult.rows[0].total);
  const { rows: orders } = await query(
    'SELECT * FROM orders WHERE user_id = $1 ORDER BY id DESC LIMIT $2 OFFSET $3',
    [req.user.id, limit, (page - 1) * limit]
  );
  const items = await Promise.all(orders.map(async (o) => toApi(o, await getItemsFor(o.id))));
  res.json({ items, total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)) });
});

// GET /api/orders — admin xem tất cả đơn
router.get('/', requireAuth, requireAdmin, async (req, res) => {
  const limit = intParam(req.query.limit, 20, 1, 100);
  const page = intParam(req.query.page, 1, 1, 100000);
  const totalResult = await query('SELECT COUNT(*) AS total FROM orders');
  const total = Number(totalResult.rows[0].total);
  const { rows: orders } = await query('SELECT * FROM orders ORDER BY id DESC LIMIT $1 OFFSET $2', [limit, (page - 1) * limit]);
  const items = await Promise.all(orders.map(async (o) => toApi(o, await getItemsFor(o.id))));
  res.json({ items, total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)) });
});

// GET /api/orders/:id — chủ đơn hoặc admin
router.get('/:id', requireAuth, async (req, res) => {
  const order = await loadOrder(Number(req.params.id));
  // Trả 404 (không phải 403) khi xem đơn của người khác — không lộ ID đơn tồn tại.
  if (!order || (order.userId !== req.user.id && req.user.role !== 'admin')) {
    throw new ApiError(404, 'Không tìm thấy đơn hàng');
  }
  res.json(order);
});

// PATCH /api/orders/:id/status — admin cập nhật trạng thái; hủy đơn thì hoàn kho
router.patch('/:id/status', requireAuth, requireAdmin, async (req, res) => {
  const { status } = validateBody(req.body, { status: { type: 'string', required: true, enum: STATUSES } });
  const id = Number(req.params.id);
  const existing = Number.isInteger(id) ? await query('SELECT * FROM orders WHERE id = $1', [id]) : { rows: [] };
  const order = existing.rows[0];
  if (!order) throw new ApiError(404, 'Không tìm thấy đơn hàng');
  // Đơn đã hủy là trạng thái cuối — cấm đổi tiếp để không hoàn kho 2 lần.
  if (order.status === 'cancelled') throw new ApiError(409, 'Đơn đã hủy, không thể đổi trạng thái');

  if (status === 'cancelled') {
    const orderItems = await getItemsFor(id);
    const items = orderItems.map((i) => ({ productId: i.product_id, quantity: i.quantity }));
    // Hoàn kho best effort — nếu product-service đang chết, vẫn hủy đơn và ghi log để xử lý tay.
    await restock(items);
  }
  await query('UPDATE orders SET status = $1, updated_at = $2 WHERE id = $3', [status, now(), id]);
  res.json(await loadOrder(id));
});

export default router;
