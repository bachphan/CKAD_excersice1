-- Chỉ dùng SQL ANSI để sau này chuyển sang PostgreSQL không phải sửa schema:
--   INTEGER PRIMARY KEY -> SERIAL/IDENTITY, TEXT -> TEXT/VARCHAR, timestamp lưu ISO-8601 TEXT.
CREATE TABLE IF NOT EXISTS products (
  id          INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL,
  brand       TEXT    NOT NULL,
  age_range   TEXT    NOT NULL,
  price       INTEGER NOT NULL CHECK (price >= 0),   -- VND, số nguyên (tránh sai số float)
  stock       INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  origin      TEXT    NOT NULL DEFAULT '',
  description TEXT    NOT NULL DEFAULT '',
  ingredients TEXT    NOT NULL DEFAULT '',
  image_url   TEXT,
  created_at  TEXT    NOT NULL,
  updated_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_products_brand     ON products(brand);
CREATE INDEX IF NOT EXISTS idx_products_age_range ON products(age_range);
CREATE INDEX IF NOT EXISTS idx_products_price     ON products(price);
