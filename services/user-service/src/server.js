import express from 'express';
import { pool } from './db.js';
import { seedAdmin } from './seed.js';
import authRouter from './routes/auth.js';
import usersRouter from './routes/users.js';
import { errorHandler, notFound } from './lib/errors.js';

if (!process.env.JWT_SECRET) {
  console.error('[fatal] missing env JWT_SECRET (copy .env.example -> .env)');
  process.exit(1);
}

await seedAdmin();

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '50kb' }));

app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'user-service' }));
app.use('/api/auth', authRouter);
app.use('/api/users', usersRouter);

app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 4002);
const server = app.listen(port, () => console.log(`user-service listening on http://localhost:${port}`));

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
