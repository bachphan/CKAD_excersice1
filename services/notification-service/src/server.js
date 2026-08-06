import express from 'express';
import { pool } from './db.js';
import notificationsRouter from './routes/notifications.js';
import { errorHandler, notFound } from './lib/errors.js';
import { startSubscriber, stopSubscriber, pingClient } from './redisSubscriber.js';

for (const key of ['JWT_SECRET']) {
  if (!process.env[key]) {
    console.error(`[fatal] missing env ${key} (copy .env.example -> .env)`);
    process.exit(1);
  }
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '100kb' }));

// /healthz = liveness THUẦN TUÝ — process còn sống trả lời được HTTP là đủ, KHÔNG check dependency
// (nếu check DB/Redis ở đây, dependency chết dây chuyền sẽ làm kubelet giết pod đang khoẻ mạnh).
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'notification-service' }));

// /readyz = readiness THẬT — chỉ sẵn sàng nhận traffic khi DB VÀ Redis đều kết nối được. Tách khỏi
// /healthz để kubelet gỡ pod khỏi Service Endpoints khi dependency chết, nhưng KHÔNG restart container
// (liveness vẫn pass) — đúng bản chất khác nhau giữa liveness và readiness.
app.get('/readyz', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    const pong = await pingClient.ping();
    if (pong !== 'PONG') throw new Error('redis ping không trả PONG');
    res.json({ status: 'ready' });
  } catch (e) {
    res.status(503).json({ status: 'not-ready', reason: e.message });
  }
});

app.use('/api/notifications', notificationsRouter);

app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 4004);
const server = app.listen(port, async () => {
  console.log(`notification-service listening on http://localhost:${port}`);
  try {
    await pingClient.connect();
    await startSubscriber();
  } catch (e) {
    // Không exit — Redis có thể chưa sẵn sàng lúc pod mới khởi động (thứ tự khởi động song song
    // trong K8s). /readyz sẽ trả 503 cho tới khi kết nối lại được, startupProbe cho đủ thời gian retry.
    console.error('[fatal-ish] kết nối Redis lúc khởi động thất bại, sẽ tự retry:', e.message);
  }
});

// Graceful shutdown (12-factor #9 - Disposability)
function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully...`);
  server.close(async () => {
    await stopSubscriber();
    pool.end(() => {
      console.log('server + db pool + redis closed, exiting');
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
