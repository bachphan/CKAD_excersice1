import { Router } from 'express';
import { query, now } from '../db.js';
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
router.get('/meta', async (req, res) => {
  const { rows } = await query('SELECT DISTINCT brand FROM products ORDER BY LOWER(brand)');
  res.json({ ageRanges: AGE_RANGES, brands: rows.map((r) => r.brand) });
});

// GET /api/products — tìm kiếm/lọc/phân trang
router.get('/products', async (req, res) => {
  const { q, ageRange, brand } = req.query;
  const conds = [];
  const params = [];

  if (typeof q === 'string' && q.trim()) {
    params.push(`%${q.trim().toLowerCase()}%`);
    conds.push(`(LOWER(name) LIKE $${params.length} OR LOWER(brand) LIKE $${params.length})`);
  }
  if (typeof ageRange === 'string' && AGE_RANGES.includes(ageRange)) {
    params.push(ageRange);
    conds.push(`age_range = $${params.length}`);
  }
  if (typeof brand === 'string' && brand.trim()) {
    params.push(brand.trim());
    conds.push(`brand = $${params.length}`);
  }
  const minPrice = intParam(req.query.minPrice, null, 0, 100_000_000);
  const maxPrice = intParam(req.query.maxPrice, null, 0, 100_000_000);
  if (minPrice !== null) { params.push(minPrice); conds.push(`price >= $${params.length}`); }
  if (maxPrice !== null) { params.push(maxPrice); conds.push(`price <= $${params.length}`); }

  const where = conds.length ? `WHERE ${conds.join(' AND ')}` : '';
  const orderBy = SORTS[req.query.sort] || SORTS.newest;
  const limit = intParam(req.query.limit, 12, 1, 100);
  const page = intParam(req.query.page, 1, 1, 100000);

  const totalResult = await query(`SELECT COUNT(*) AS total FROM products ${where}`, params);
  const total = Number(totalResult.rows[0].total);

  const dataParams = [...params, limit, (page - 1) * limit];
  const { rows } = await query(
    `SELECT * FROM products ${where} ORDER BY ${orderBy} LIMIT $${dataParams.length - 1} OFFSET $${dataParams.length}`,
    dataParams
  );

  res.json({ items: rows.map(toApi), total, page, limit, totalPages: Math.max(1, Math.ceil(total / limit)) });
});

// GET /api/products/:id
router.get('/products/:id', async (req, res) => {
  const id = Number(req.params.id);
  const row = Number.isInteger(id) ? (await query('SELECT * FROM products WHERE id = $1', [id])).rows[0] : null;
  if (!row) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  res.json(toApi(row));
});

// ----- Admin CRUD -----

router.post('/products', requireAuth, requireAdmin, async (req, res) => {
  const d = validateBody(req.body, productRules);
  const ts = now();
  const { rows } = await query(
    `INSERT INTO products (name, brand, age_range, price, stock, origin, description, ingredients, image_url, created_at, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING *`,
    [d.name, d.brand, d.ageRange, d.price, d.stock, d.origin, d.description, d.ingredients, d.imageUrl, ts, ts]
  );
  res.status(201).json(toApi(rows[0]));
});

router.put('/products/:id', requireAuth, requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  const existing = Number.isInteger(id) ? (await query('SELECT * FROM products WHERE id = $1', [id])).rows[0] : null;
  if (!existing) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  const d = validateBody(req.body, productRules);
  const { rows } = await query(
    `UPDATE products SET name = $1, brand = $2, age_range = $3, price = $4, stock = $5, origin = $6,
     description = $7, ingredients = $8, image_url = $9, updated_at = $10 WHERE id = $11 RETURNING *`,
    [d.name, d.brand, d.ageRange, d.price, d.stock, d.origin, d.description, d.ingredients, d.imageUrl, now(), id]
  );
  res.json(toApi(rows[0]));
});

router.patch('/products/:id/stock', requireAuth, requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  const existing = Number.isInteger(id) ? (await query('SELECT * FROM products WHERE id = $1', [id])).rows[0] : null;
  if (!existing) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  const { stock } = validateBody(req.body, { stock: { type: 'int', required: true, min: 0, max: 1_000_000 } });
  const { rows } = await query('UPDATE products SET stock = $1, updated_at = $2 WHERE id = $3 RETURNING *', [stock, now(), id]);
  res.json(toApi(rows[0]));
});

router.delete('/products/:id', requireAuth, requireAdmin, async (req, res) => {
  const id = Number(req.params.id);
  const result = Number.isInteger(id) ? await query('DELETE FROM products WHERE id = $1', [id]) : { rowCount: 0 };
  if (result.rowCount === 0) throw new ApiError(404, 'Không tìm thấy sản phẩm');
  res.status(204).end();
});

export default router;
