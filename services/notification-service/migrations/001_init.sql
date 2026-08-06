-- Lưu lại mọi notification đã "gửi" (mock — log + record, không SMTP thật) khi tiêu thụ event
-- order.completed từ Redis Pub/Sub. payload lưu JSON thô của event gốc để audit/debug.
CREATE TABLE IF NOT EXISTS notifications (
  id           SERIAL PRIMARY KEY,
  channel      TEXT NOT NULL,
  order_id     INTEGER,
  user_id      INTEGER,
  message      TEXT NOT NULL,
  payload      JSONB NOT NULL,
  created_at   TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_notifications_order ON notifications(order_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
