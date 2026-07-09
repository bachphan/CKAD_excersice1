import { ApiError } from './errors.js';

// Validator khai báo tối giản — đủ dùng cho app này, khỏi thêm dependency.
// rules: { field: { type: 'string'|'int', required, minLen, maxLen, min, max, enum, pattern, noTrim, default } }
export function validateBody(body, rules) {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new ApiError(400, 'Request body must be a JSON object');
  }
  const errors = [];
  const out = {};

  for (const [field, r] of Object.entries(rules)) {
    let v = body[field];
    if (v === undefined || v === null) {
      if (r.required) errors.push(`${field} is required`);
      else if ('default' in r) out[field] = r.default;
      continue;
    }
    if (r.type === 'string') {
      if (typeof v !== 'string') { errors.push(`${field} must be a string`); continue; }
      if (!r.noTrim) v = v.trim();
      if (v.length === 0) {
        if (r.required) errors.push(`${field} must not be empty`);
        else if ('default' in r) out[field] = r.default;
        continue;
      }
      if (r.minLen !== undefined && v.length < r.minLen) errors.push(`${field} must be at least ${r.minLen} characters`);
      if (r.maxLen !== undefined && v.length > r.maxLen) errors.push(`${field} must be at most ${r.maxLen} characters`);
      if (r.enum && !r.enum.includes(v)) errors.push(`${field} must be one of: ${r.enum.join(', ')}`);
      if (r.pattern && !r.pattern.test(v)) errors.push(`${field} has invalid format`);
    } else if (r.type === 'int') {
      if (typeof v === 'string' && /^-?\d+$/.test(v)) v = Number(v);
      if (!Number.isInteger(v)) { errors.push(`${field} must be an integer`); continue; }
      if (r.min !== undefined && v < r.min) errors.push(`${field} must be >= ${r.min}`);
      if (r.max !== undefined && v > r.max) errors.push(`${field} must be <= ${r.max}`);
    }
    out[field] = v;
  }

  if (errors.length) throw new ApiError(400, 'Dữ liệu không hợp lệ', errors);
  return out;
}

// Parse query param số nguyên, kẹp trong [min, max]; trả về def nếu không hợp lệ.
export function intParam(value, def, min, max) {
  const n = Number(value);
  if (!Number.isInteger(n)) return def;
  return Math.min(max, Math.max(min, n));
}
