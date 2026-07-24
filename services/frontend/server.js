// Static file server + API gateway — Node thuần, KHÔNG dependency nào.
// Trình duyệt chỉ nói chuyện với origin này; /api/* được proxy sang đúng backend
// (giống vai trò Ingress trên K8s sau này), nên không cần CORS.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');
const PORT = Number(process.env.PORT || 4000);
const TIMEOUT_MS = Number(process.env.UPSTREAM_TIMEOUT_MS || 10000);

const PRODUCT = (process.env.PRODUCT_SERVICE_URL || 'http://localhost:4001').replace(/\/+$/, '');
const USER = (process.env.USER_SERVICE_URL || 'http://localhost:4002').replace(/\/+$/, '');
const ORDER = (process.env.ORDER_SERVICE_URL || 'http://localhost:4003').replace(/\/+$/, '');

// Prefix dài hơn phải đứng trước nếu trùng nhau — ở đây các prefix không giao nhau.
const UPSTREAMS = [
  ['/api/products', PRODUCT],
  ['/api/meta', PRODUCT],
  ['/api/auth', USER],
  ['/api/users', USER],
  ['/api/orders', ORDER],
];

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

function sendJson(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

async function proxy(req, res, target) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = Buffer.concat(chunks);

  const headers = {};
  if (req.headers['content-type']) headers['content-type'] = req.headers['content-type'];
  if (req.headers.authorization) headers.authorization = req.headers.authorization;

  try {
    const upstream = await fetch(target + req.url, {
      method: req.method,
      headers,
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : body,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const buf = Buffer.from(await upstream.arrayBuffer());
    res.writeHead(upstream.status, {
      'content-type': upstream.headers.get('content-type') || 'application/json',
    });
    res.end(buf);
  } catch (e) {
    console.error(`[proxy] ${req.method} ${req.url} -> ${target} failed:`, e.name || e.message);
    sendJson(res, 502, { error: { message: 'Không kết nối được dịch vụ phía sau, vui lòng thử lại' } });
  }
}

function serveStatic(req, res, pathname) {
  if (req.method !== 'GET' && req.method !== 'HEAD') return sendJson(res, 405, { error: { message: 'Method not allowed' } });
  // Chuẩn hóa + ghim vào PUBLIC_DIR để chặn path traversal (../..)
  let filePath = path.normalize(path.join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname));
  if (!filePath.startsWith(PUBLIC_DIR)) return sendJson(res, 403, { error: { message: 'Forbidden' } });
  // Route không có đuôi file (SPA) -> trả index.html
  if (!path.extname(filePath)) filePath = path.join(PUBLIC_DIR, 'index.html');

  fs.readFile(filePath, (err, data) => {
    if (err) return sendJson(res, 404, { error: { message: 'Not found' } });
    res.writeHead(200, { 'content-type': MIME[path.extname(filePath)] || 'application/octet-stream' });
    res.end(data);
  });
}

const server = http.createServer((req, res) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    return sendJson(res, 400, { error: { message: 'Bad request' } });
  }
  if (pathname === '/healthz') return sendJson(res, 200, { status: 'ok', service: 'frontend' });

  const upstream = UPSTREAMS.find(([prefix]) => pathname === prefix || pathname.startsWith(prefix + '/'));
  if (upstream) return proxy(req, res, upstream[1]);
  serveStatic(req, res, pathname);
});

server.listen(PORT, () => console.log(`frontend (static + gateway) listening on http://localhost:${PORT}`));

// Graceful shutdown (12-factor #9 - Disposability): ngừng nhận request mới, chờ request
// đang xử lý xong rồi mới thoát — tránh cắt ngang response dở khi K8s gửi SIGTERM.
function shutdown(signal) {
  console.log(`${signal} received, shutting down gracefully...`);
  server.close(() => {
    console.log('server closed, exiting');
    process.exit(0);
  });
  setTimeout(() => {
    console.error('graceful shutdown timed out, forcing exit');
    process.exit(1);
  }, 10_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
