import express from 'express';
import './db.js';
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
app.listen(port, () => console.log(`user-service listening on http://localhost:${port}`));
