-- Schema PostgreSQL (đã chuyển từ SQLite: INTEGER PRIMARY KEY -> SERIAL PRIMARY KEY).
-- order_items lưu SNAPSHOT tên + đơn giá tại thời điểm mua: sản phẩm bị sửa/xoá
-- sau này không làm sai lệch lịch sử đơn hàng.
CREATE TABLE IF NOT EXISTS orders (
  id               SERIAL PRIMARY KEY,
  user_id          INTEGER NOT NULL,
  status           TEXT NOT NULL DEFAULT 'confirmed'
                   CHECK (status IN ('confirmed', 'shipping', 'completed', 'cancelled')),
  total            INTEGER NOT NULL CHECK (total >= 0),
  payment_method   TEXT NOT NULL,
  shipping_name    TEXT NOT NULL,
  shipping_phone   TEXT NOT NULL,
  shipping_address TEXT NOT NULL,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);

CREATE TABLE IF NOT EXISTS order_items (
  id           SERIAL PRIMARY KEY,
  order_id     INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id   INTEGER NOT NULL,
  product_name TEXT NOT NULL,
  unit_price   INTEGER NOT NULL CHECK (unit_price >= 0),
  quantity     INTEGER NOT NULL CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
