import express from 'express';
import { pool } from './db.js';
import ordersRouter from './routes/orders.js';
import { errorHandler, notFound } from './lib/errors.js';

for (const key of ['JWT_SECRET', 'INTERNAL_API_KEY']) {
  if (!process.env[key]) {
    console.error(`[fatal] missing env ${key} (copy .env.example -> .env)`);
    process.exit(1);
  }
}

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '100kb' }));

app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'order-service' }));
app.use('/api/orders', ordersRouter);

app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 4003);
const server = app.listen(port, () => console.log(`order-service listening on http://localhost:${port}`));

// Graceful shutdown (12-factor #9 - Disposability)
function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully...`);
  server.close(() => {
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
