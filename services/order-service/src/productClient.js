import { ApiError } from './lib/errors.js';

// Client REST gọi sang product-service, có timeout — service kia chết/treo thì
// trả 503 cho người dùng thay vì treo request hoặc crash.
const BASE = (process.env.PRODUCT_SERVICE_URL || 'http://localhost:4001').replace(/\/+$/, '');
const TIMEOUT_MS = Number(process.env.PRODUCT_SERVICE_TIMEOUT_MS || 5000);

async function call(method, path, body) {
  let res;
  try {
    res = await fetch(BASE + path, {
      method,
      headers: {
        'content-type': 'application/json',
        'x-internal-key': process.env.INTERNAL_API_KEY || '',
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    // Timeout, connection refused, DNS... — mọi lỗi network đều thành 503.
    console.error(`[productClient] ${method} ${path} failed:`, e.name || e.message);
    throw new ApiError(503, 'Hệ thống sản phẩm đang bận, vui lòng thử lại sau');
  }

  const data = await res.json().catch(() => null);
  if (!res.ok) {
    // 409 = không đủ tồn kho — chuyển nguyên thông báo cho người dùng.
    const message = data?.error?.message || `Product service error (${res.status})`;
    throw new ApiError(res.status === 409 ? 409 : 502, message, data?.error);
  }
  return data;
}

// Kiểm tra + trừ tồn kho nguyên tử; trả về [{productId, name, unitPrice, quantity}]
export async function checkoutStock(items) {
  const data = await call('POST', '/internal/checkout', { items });
  return data.items;
}

// Hoàn kho — best effort (dùng khi hủy đơn hoặc bù trừ lỗi), không throw.
export async function restock(items) {
  try {
    await call('POST', '/internal/restock', { items });
    return true;
  } catch (e) {
    console.error('[productClient] restock failed (manual fix may be needed):', e.message);
    return false;
  }
}
