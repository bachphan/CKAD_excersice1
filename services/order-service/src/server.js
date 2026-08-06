import express from 'express';
import { pool } from './db.js';
import ordersRouter from './routes/orders.js';
import { errorHandler, notFound } from './lib/errors.js';
import { closePublisher } from './eventPublisher.js';

for (const key of ['JWT_SECRET', 'INTERNAL_API_KEY']) {
  if (!process.env[key]) {
    console.error(`[fatal] missing env ${key} (copy .env.example -> .env)`);
    process.exit(1);
  }
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '100kb' }));

// /healthz = liveness THUẦN TUÝ. /readyz = readiness THẬT (ping Postgres) — xem giải thích ở
// product-service/src/server.js. CHỦ Ý không check Redis ở đây: publish event là best-effort/
// fire-and-forget (xem eventPublisher.js) — Redis chết KHÔNG được làm order-service mất readiness,
// nếu không sẽ làm hỏng chính mục đích tách rời đồng bộ/bất đồng bộ.
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'order-service' }));
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ready' });
  } catch (e) {
    res.status(503).json({ status: 'not-ready', reason: e.message });
  }
});
app.use('/api/orders', ordersRouter);

app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 4003);
const server = app.listen(port, () => console.log(`order-service listening on http://localhost:${port}`));

// Graceful shutdown (12-factor #9 - Disposability)
function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully...`);
  server.close(async () => {
    await closePublisher();
    pool.end(() => {
      console.log('server + db pool closed, exiting');
      process.exit(0);
    });
  });
  setTimeout(() => {
    console.error('graceful shutdown timed out, forcing exit');
    process.exit(1);
  }, 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
