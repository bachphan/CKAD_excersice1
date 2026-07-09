import express from 'express';
import './db.js'; // mở DB + chạy migration ngay khi start
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

app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'product-service' }));
app.use('/api', productsRouter);
app.use('/internal', internalRouter);

app.use(notFound);
app.use(errorHandler);

const port = Number(process.env.PORT || 4001);
app.listen(port, () => console.log(`product-service listening on http://localhost:${port}`));
