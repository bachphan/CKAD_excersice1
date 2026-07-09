import { Router } from 'express';
import { db, now } from '../db.js';
import { AGE_RANGES } from '../constants.js';
import { requireAuth, requireAdmin } from '../lib/auth.js';
import { validateBody, intParam } from '../lib/validate.js';
import { ApiError } from '../lib/errors.js';

const router = Router();

const productRules = {
  name: { type: 'string', required: true, maxLen: 200 },
  brand: { type: 'string', required: true, maxLen: 100 },
  ageRange: { type: 'string', required: true, enum: AGE_RANGES },
  price: { type: 'int', required: true, min: 0, max: 100_000_000 },
  stock: { type: 'int', min: 0, max: 1_000_000, default: 0 },
  origin: { type: 'string', maxLen: 100, default: '' },
  description: { type: 'string', maxLen: 5000, default: '' },
  ingredients: { type: 'string', maxLen: 5000, default: '' },
  imageUrl: { type: 'string', maxLen: 500, default: null },
};

function toApi(row) {
  return {
    id: row.id,
    name: row.name,
    brand: row.brand,
    ageRange: row.age_range,
    price: row.price,
    stock: row.stock,
    origin: row.origin,
    description: row.description,
    ingredients: row.ingredients,
    imageUrl: row.image_url || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

// Whitelist cột sort — không bao giờ nối chuỗi từ input vào SQL.
const SORTS = {
  newest: 'id DESC',
  price_asc: 'price ASC',
  price_desc: 'price DESC',
  name: 'LOWER(name) ASC',
};

// GET /api/meta — dữ liệu cho bộ lọc trên frontend
router.get('/meta', (req, res) => {
  const brands = db.prepare('SELECT DISTINCT brand FROM products ORDER BY LOWER(brand)').all().map((r) => r.brand);
  res.json({ ageRanges: AGE_RANGES, brands });
});

// GET /api/products — tìm kiếm/lọc/phân trang
router.get('/products', (req, res) => {
  const { q, ageRange, brand } = req.query;
  const conds = [];
  const params = [];

  if (typeof q === 'string' && q.trim()) {
    conds.push('(LOWER(name) LIKE ? OR LOWER(brand) LIKE ?)');
    const like = `%${q.trim().toLowerCase()}%`;
    params.push(like, like);
  }
  if (typeof ageRange === 'string' && AGE_RANGES.includes(ageRange)) {
    conds.push('age_range = ?');
    params.push(ageRange);
  }
  if (typeof brand === 'string' && brand.trim()) {
    conds.push('brand = ?');
    params.push(brand.trim());
  }
  const minPrice = intParam(req.query.minPrice, null, 0, 100_000_000);
  const maxPrice = intParam(req.query.maxPrice, null, 0, 100_000_000);
  if (minPrice !== null) { conds.push('price >= ?'); params.push(minPrice); }
  if (maxPrice !== null) { conds.push('price <= ?'); params.push(maxPrice); }

  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  const orderBy = SORTS[req.query.sort] || SORTS.newest;
  const limit = intParam(req.query.limit, 12, 1, 100);
  const page = intParam(req.query.page, 1, 1, 100000);

  const { total } = db.prepare(`SELECT COUNT(*) AS total FROM products ${where}`).get(...params);
  const rows = db
    .prepare(`SELECT * FROM products ${where} ORDER BY ${orderBy} LIMIT ? OFFSET ?`)
    .all(...params, limit, (page - 1) * limit);

  res.json({ items: rows.map(toApi), total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)) });
});

// GET /api/products/:id
router.get('/products/:id', (req, res) => {
  const id = Number(req.params.id);
  const row = Number.isInteger(id) ? db.prepare('SELECT * FROM products WHERE id = ?').get(id) : null;
  if (!row) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  res.json(toApi(row));
});

// ----- Admin CRUD -----

router.post('/products', requireAuth, requireAdmin, (req, res) => {
  const d = validateBody(req.body, productRules);
  const ts = now();
  const info = db
    .prepare(`INSERT INTO products (name, brand, age_range, price, stock, origin, description, ingredients, image_url, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(d.name, d.brand, d.ageRange, d.price, d.stock, d.origin, d.description, d.ingredients, d.imageUrl, ts, ts);
  const row = db.prepare('SELECT * FROM products WHERE id = ?').get(info.lastInsertRowid);
  res.status(201).json(toApi(row));
});

router.put('/products/:id', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  const existing = Number.isInteger(id) ? db.prepare('SELECT * FROM products WHERE id = ?').get(id) : null;
  if (!existing) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  const d = validateBody(req.body, productRules);
  db.prepare(`UPDATE products SET name = ?, brand = ?, age_range = ?, price = ?, stock = ?, origin = ?,
              description = ?, ingredients = ?, image_url = ?, updated_at = ? WHERE id = ?`)
    .run(d.name, d.brand, d.ageRange, d.price, d.stock, d.origin, d.description, d.ingredients, d.imageUrl, now(), id);
  res.json(toApi(db.prepare('SELECT * FROM products WHERE id = ?').get(id)));
});

router.patch('/products/:id/stock', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  const existing = Number.isInteger(id) ? db.prepare('SELECT * FROM products WHERE id = ?').get(id) : null;
  if (!existing) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  const { stock } = validateBody(req.body, { stock: { type: 'int', required: true, min: 0, max: 1_000_000 } });
  db.prepare('UPDATE products SET stock = ?, updated_at = ? WHERE id = ?').run(stock, now(), id);
  res.json(toApi(db.prepare('SELECT * FROM products WHERE id = ?').get(id)));
});

router.delete('/products/:id', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  const info = Number.isInteger(id) ? db.prepare('DELETE FROM products WHERE id = ?').run(id) : { changes: 0 };
  if (info.changes === 0) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  res.status(204).end();
});

export default router;
