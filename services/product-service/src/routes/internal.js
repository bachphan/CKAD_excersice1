import { Router } from 'express';
import { db, now } from '../db.js';
import { requireInternalKey } from '../lib/auth.js';
import { ApiError } from '../lib/errors.js';

const router = Router();
router.use(requireInternalKey);

class StockError extends Error {
  constructor(message, productId, available) {
    super(message);
    this.productId = productId;
    this.available = available;
  }
}

// Chuẩn hoá items từ order-service: gộp trùng productId, chặn số lượng vô lý.
function parseItems(body) {
  const items = body?.items;
  if (!Array.isArray(items) || items.length === 0 || items.length > 50) {
    throw new ApiError(400, 'items must be a non-empty array (max 50)');
  }
  const merged = new Map();
  for (const it of items) {
    const id = it?.productId;
    const qty = it?.quantity;
    if (!Number.isInteger(id) || id <= 0) throw new ApiError(400, 'each item needs a positive integer productId');
    if (!Number.isInteger(qty) || qty <= 0 || qty > 100) throw new ApiError(400, 'each item quantity must be 1-100');
    merged.set(id, (merged.get(id) || 0) + qty);
  }
  return [...merged].map(([productId, quantity]) => ({ productId, quantity }));
}

const getById = db.prepare('SELECT * FROM products WHERE id = ?');
// Điều kiện stock >= ? lặp lại trong UPDATE để chống race (dù better-sqlite3 tx đã serialize).
const decStock = db.prepare('UPDATE products SET stock = stock - ?, updated_at = ? WHERE id = ? AND stock >= ?');
const incStock = db.prepare('UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?');

// Kiểm tra + trừ tồn kho NGUYÊN TỬ cho cả đơn hàng: hoặc trừ hết, hoặc không trừ gì.
// Trả về snapshot giá/tên tại thời điểm checkout để order-service lưu vào đơn
// (không tin giá do client gửi lên).
const checkoutTx = db.transaction((items) => {
  const lines = [];
  for (const { productId, quantity } of items) {
    const p = getById.get(productId);
    if (!p) throw new StockError(`Sản phẩm #${productId} không tồn tại`, productId, 0);
    if (p.stock < quantity) {
      throw new StockError(`"${p.name}" chỉ còn ${p.stock} sản phẩm trong kho`, productId, p.stock);
    }
    decStock.run(quantity, now(), productId, quantity);
    lines.push({ productId: p.id, name: p.name, unitPrice: p.price, quantity });
  }
  return lines;
});

// POST /internal/checkout  { items: [{productId, quantity}] }
router.post('/checkout', (req, res) => {
  const items = parseItems(req.body);
  try {
    res.json({ items: checkoutTx(items) });
  } catch (e) {
    if (e instanceof StockError) {
      return res.status(409).json({ error: { message: e.message, productId: e.productId, available: e.available } });
    }
    throw e;
  }
});

// POST /internal/restock — hoàn kho (đơn bị hủy, hoặc bù trừ khi tạo đơn thất bại)
router.post('/restock', (req, res) => {
  const items = parseItems(req.body);
  db.transaction(() => {
    for (const { productId, quantity } of items) incStock.run(quantity, now(), productId);
  })();
  res.json({ ok: true });
});

export default router;
