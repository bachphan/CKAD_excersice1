import express from 'express';
import { pool } from './db.js'; // mở DB + chạy migration ngay khi start
import { seedIfEmpty } from './seed.js';
import productsRouter from './routes/products.js';
import internalRouter from './routes/internal.js';
import { errorHandler, notFound } from './lib/errors.js';

for (const key of ['JWT_SECRET', 'INTERNAL_API_KEY']) {
  if (!process.env[key]) {
    console.error(`[fatal] missing env ${key} (copy .env.example -> .env)`);
    process.exit(1);
  }
}

if (process.env.SEED_ON_START !== 'false') await seedIfEmpty();

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '100kb' }));

// /healthz = liveness THUẦN TUÝ (process sống trả lời được là đủ). /readyz = readiness THẬT — ping
// Postgres, tách khỏi /healthz để dependency chết chỉ làm kubelet gỡ pod khỏi Service Endpoints,
// KHÔNG restart container (liveness vẫn pass — đúng bản chất khác nhau của 2 loại probe).
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'product-service', version: '2.1' }));
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (e) {
    res.status(503).json({ status: 'not-ready', reason: e.message });
  }
});
app.use('/api', productsRouter);
app.use('/internal', internalRouter);

app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 4001);
const server = app.listen(port, () => console.log(`product-service listening on http://localhost:${port}`));

// Graceful shutdown (12-factor #9 - Disposability): ngừng nhận request mới, chờ request
// đang xử lý xong, đóng connection pool, rồi mới thoát — tránh cắt ngang transaction dở
// hoặc bỏ sót request khi K8s gửi SIGTERM lúc rolling update/scale down.
function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully...`);
  server.close(() => {
    pool.end(() => {
      console.log('server + db pool closed, exiting');
      process.exit(0);
    });
  });
  // Không để treo vô hạn nếu có request/connection cứng đầu không đóng được.
  setTimeout(() => {
    console.error('graceful shutdown timed out, forcing exit');
    process.exit(1);
  }, 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
