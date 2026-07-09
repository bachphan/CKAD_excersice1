import express from 'express';
import './db.js';
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
app.listen(port, () => console.log(`order-service listening on http://localhost:${port}`));
