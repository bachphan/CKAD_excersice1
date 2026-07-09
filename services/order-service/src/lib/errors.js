export class ApiError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

export function notFound(req, res) {
  res.status(404).json({ error: { message: 'Not found' } });
}

export function errorHandler(err, req, res, _next) {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { message: 'Invalid JSON body' } });
  }
  // ApiError là lỗi chủ động (kể cả 503) -> giữ nguyên message cho client;
  // lỗi bất ngờ -> che message, chỉ log server-side.
  const expected = err instanceof ApiError;
  const status = (expected && err.status) || 500;
  if (!expected) console.error('[error]', err);
  else if (status >= 500) console.error('[error]', err.message);
  res.status(status).json({
    error: {
      message: expected ? err.message : 'Internal server error',
      ...(expected && err.details ? { details: err.details } : {}),
    },
  });
}
