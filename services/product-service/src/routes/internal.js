import { Router } from 'express';
import { pool, now } from '../db.js';
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

// Kiểm tra + trừ tồn kho NGUYÊN TỬ cho cả đơn hàng: hoặc trừ hết, hoặc không trừ gì
// (1 transaction Postgres thật, dùng client riêng từ pool + BEGIN/COMMIT/ROLLBACK).
// Trả về snapshot giá/tên tại thời điểm checkout để order-service lưu vào đơn
// (không tin giá do client gửi lên).
async function checkoutTx(items) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const lines = [];
    for (const { productId, quantity } of items) {
      // FOR UPDATE khoá dòng đang đọc — chống race condition khi 2 request checkout cùng lúc
      // trên cùng 1 sản phẩm (tương đương vai trò serialize của better-sqlite3 transaction trước đây).
      const { rows } = await client.query('SELECT * FROM products WHERE id = $1 FOR UPDATE', [productId]);
      const p = rows[0];
      if (!p) throw new StockError(`Sản phẩm #${productId} không tồn tại`, productId, 0);
      if (p.stock < quantity) {
        throw new StockError(`"${p.name}" chỉ còn ${p.stock} sản phẩm trong kho`, productId, p.stock);
      }
      await client.query('UPDATE products SET stock = stock - $1, updated_at = $2 WHERE id = $3', [quantity, now(), productId]);
      lines.push({ productId: p.id, name: p.name, unitPrice: p.price, quantity });
    }
    await client.query('COMMIT');
    return lines;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

async function restockTx(items) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const { productId, quantity } of items) {
      await client.query('UPDATE products SET stock = stock + $1, updated_at = $2 WHERE id = $3', [quantity, now(), productId]);
    }
    await client.query('COMMIT');
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

// POST /internal/checkout  { items: [{productId, quantity}] }
router.post('/checkout', async (req, res) => {
  const items = parseItems(req.body);
  try {
    res.json({ items: await checkoutTx(items) });
  } catch (e) {
    if (e instanceof StockError) {
      return res.status(409).json({ error: { message: e.message, productId: e.productId, available: e.available } });
    }
    throw e;
  }
});

// POST /internal/restock — hoàn kho (đơn bị hủy, hoặc bù trừ khi tạo đơn thất bại)
router.post('/restock', async (req, res) => {
  const items = parseItems(req.body);
  await restockTx(items);
  res.json({ ok: true });
});

export default router;
