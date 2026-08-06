import Redis from 'ioredis';

// Publisher Redis Pub/Sub thật — fire-and-forget: publish KHÔNG BAO GIỜ làm fail hay làm chậm
// response checkout. notification-service subscribe channel này để "gửi" thông báo bất đồng bộ,
// tách khỏi luồng đồng bộ tạo đơn (đúng lý do dùng async: người dùng không cần chờ gửi mail xong
// mới thấy đơn được tạo).
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const CHANNEL = process.env.REDIS_CHANNEL || 'order.completed';

const publisher = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  lazyConnect: true,
  retryStrategy: (times) => Math.min(times * 200, 5000),
  maxRetriesPerRequest: 1,
});
publisher.on('error', (e) => console.error('[redis:publisher] connection error:', e.message));

let connecting = null;
async function ensureConnected() {
  if (publisher.status === 'ready') return;
  connecting ??= publisher.connect().catch((e) => {
    connecting = null;
    throw e;
  });
  await connecting;
}

// Best-effort — lỗi publish CHỈ log, không throw (order đã tạo thành công rồi, không được rollback
// vì lý do phụ trợ như thông báo gửi thất bại).
export async function publishOrderCompleted(order) {
  try {
    await ensureConnected();
    const event = {
      orderId: order.id,
      userId: order.userId,
      total: order.total,
      itemCount: order.items.length,
      at: new Date().toISOString(),
    };
    await publisher.publish(CHANNEL, JSON.stringify(event));
  } catch (e) {
    console.error('[eventPublisher] publish order.completed thất bại (best-effort, bỏ qua):', e.message);
  }
}

export async function closePublisher() {
  await publisher.quit().catch(() => {});
}
