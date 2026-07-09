import { Router } from 'express';
import { db, now } from '../db.js';
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

const getOrder = db.prepare('SELECT * FROM orders WHERE id = ?');
const getItems = db.prepare('SELECT * FROM order_items WHERE order_id = ? ORDER BY id');

function loadOrder(id) {
  const order = Number.isInteger(id) ? getOrder.get(id) : null;
  return order ? toApi(order, getItems.all(order.id)) : null;
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

const insertOrder = db.prepare(`INSERT INTO orders (user_id, status, total, payment_method, shipping_name, shipping_phone, shipping_address, created_at, updated_at)
                                VALUES (?, 'confirmed', ?, ?, ?, ?, ?, ?, ?)`);
const insertItem = db.prepare(`INSERT INTO order_items (order_id, product_id, product_name, unit_price, quantity)
                               VALUES (?, ?, ?, ?, ?)`);

const createOrderTx = db.transaction((userId, shipping, paymentMethod, lines) => {
  const total = lines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0);
  const ts = now();
  const info = insertOrder.run(userId, total, paymentMethod, shipping.fullName, shipping.phone, shipping.address, ts, ts);
  for (const l of lines) insertItem.run(info.lastInsertRowid, l.productId, l.name, l.unitPrice, l.quantity);
  return Number(info.lastInsertRowid);
});

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
    orderId = createOrderTx(req.user.id, shipping, shipping.paymentMethod, lines);
  } catch (e) {
    restock(items);
    throw e;
  }
  res.status(201).json(loadOrder(orderId));
});

// GET /api/orders/mine — lịch sử đơn của user đang đăng nhập
router.get('/mine', requireAuth, (req, res) => {
  const limit = intParam(req.query.limit, 10, 1, 50);
  const page = intParam(req.query.page, 1, 1, 100000);
  const { total } = db.prepare('SELECT COUNT(*) AS total FROM orders WHERE user_id = ?').get(req.user.id);
  const orders = db
    .prepare('SELECT * FROM orders WHERE user_id = ? ORDER BY id DESC LIMIT ? OFFSET ?')
    .all(req.user.id, limit, (page - 1) * limit);
  res.json({
    items: orders.map((o) => toApi(o, getItems.all(o.id))),
    total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)),
  });
});

// GET /api/orders — admin xem tất cả đơn
router.get('/', requireAuth, requireAdmin, (req, res) => {
  const limit = intParam(req.query.limit, 20, 1, 100);
  const page = intParam(req.query.page, 1, 1, 100000);
  const { total } = db.prepare('SELECT COUNT(*) AS total FROM orders').get();
  const orders = db.prepare('SELECT * FROM orders ORDER BY id DESC LIMIT ? OFFSET ?').all(limit, (page - 1) * limit);
  res.json({
    items: orders.map((o) => toApi(o, getItems.all(o.id))),
    total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)),
  });
});

// GET /api/orders/:id — chủ đơn hoặc admin
router.get('/:id', requireAuth, (req, res) => {
  const order = loadOrder(Number(req.params.id));
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
  const order = Number.isInteger(id) ? getOrder.get(id) : null;
  if (!order) throw new ApiError(404, 'Không tìm thấy đơn hàng');
  // Đơn đã hủy là trạng thái cuối — cấm đổi tiếp để không hoàn kho 2 lần.
  if (order.status === 'cancelled') throw new ApiError(409, 'Đơn đã hủy, không thể đổi trạng thái');

  if (status === 'cancelled') {
    const items = getItems.all(id).map((i) => ({ productId: i.product_id, quantity: i.quantity }));
    // Hoàn kho best effort — nếu product-service đang chết, vẫn hủy đơn và ghi log để xử lý tay.
    await restock(items);
  }
  db.prepare('UPDATE orders SET status = ?, updated_at = ? WHERE id = ?').run(status, now(), id);
  res.json(loadOrder(id));
});

export default router;
