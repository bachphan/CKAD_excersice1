import Redis from 'ioredis';
import { query, now } from './db.js';

// Subscriber Redis Pub/Sub thật — KHÔNG mock. order-service PUBLISH sự kiện "order.completed"
// ngay sau khi checkout xong (fire-and-forget, không chặn response của order-service), service
// này SUBSCRIBE, nhận event bất đồng bộ rồi "gửi" thông báo (ở đây: ghi record + log, không SMTP
// thật — đủ để chứng minh pattern event-driven mà không cần hạ tầng mail thật).
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = Number(process.env.REDIS_PORT || 6379);
const CHANNEL = process.env.REDIS_CHANNEL || 'order.completed';

// 1 connection riêng cho subscribe (theo đúng yêu cầu của Redis: connection ở chế độ subscribe
// không dùng chung được với connection thực thi lệnh thường), 1 connection riêng để healthcheck/readyz.
export const subscriberClient = new Redis({ host: REDIS_HOST, port: REDIS_PORT, lazyConnect: true, retryStrategy: (times) => Math.min(times * 200, 5000) });
export const pingClient = new Redis({ host: REDIS_HOST, port: REDIS_PORT, lazyConnect: true, retryStrategy: (times) => Math.min(times * 200, 5000) });

async function handleMessage(channel, raw) {
  let event;
  try {
    event = JSON.parse(raw);
  } catch {
    console.error('[redisSubscriber] bỏ qua message không phải JSON hợp lệ:', raw);
    return;
  }
  const message = `Đã gửi email xác nhận đơn hàng #${event.orderId} (tổng ${event.total?.toLocaleString?.('vi-VN') ?? event.total}đ) tới người dùng #${event.userId}`;
  try {
    await query(
      'INSERT INTO notifications (channel, order_id, user_id, message, payload, created_at) VALUES ($1, $2, $3, $4, $5, $6)',
      [channel, event.orderId ?? null, event.userId ?? null, message, JSON.stringify(event), now()]
    );
    console.log(`[notification] ${message}`);
  } catch (e) {
    console.error('[redisSubscriber] lưu notification thất bại:', e.message);
  }
}

export async function startSubscriber() {
  subscriberClient.on('error', (e) => console.error('[redis:subscriber] connection error:', e.message));
  await subscriberClient.connect();
  await subscriberClient.subscribe(CHANNEL);
  subscriberClient.on('message', handleMessage);
  console.log(`[redisSubscriber] đang lắng nghe channel "${CHANNEL}"`);
}

export async function stopSubscriber() {
  await Promise.allSettled([subscriberClient.quit(), pingClient.quit()]);
}
