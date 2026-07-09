import jwt from 'jsonwebtoken';
import { ApiError } from './errors.js';

// Verify JWT do user-service phát hành (shared secret) — không cần gọi sang user-service.
export function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw new ApiError(401, 'Thiếu token xác thực');
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = { id: payload.sub, email: payload.email, role: payload.role };
  } catch {
    throw new ApiError(401, 'Token không hợp lệ hoặc đã hết hạn');
  }
  next();
}

export function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') throw new ApiError(403, 'Chỉ admin mới được thao tác này');
  next();
}

// Bảo vệ các endpoint /internal/* (chỉ order-service được gọi).
export function requireInternalKey(req, res, next) {
  if (!process.env.INTERNAL_API_KEY || req.headers['x-internal-key'] !== process.env.INTERNAL_API_KEY) {
    throw new ApiError(401, 'Invalid internal key');
  }
  next();
}
