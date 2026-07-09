import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const { Pool } = pg;
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Pool đọc PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE từ env tự động (chuẩn của node-postgres).
export const pool = new Pool();

export async function query(text, params) {
  return pool.query(text, params);
}

// Migration đơn giản: chạy các file .sql theo thứ tự tên, ghi nhận vào schema_migrations.
async function runMigrations() {
  const migrationsDir = path.join(__dirname, '..', 'migrations');
  await pool.query('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL)');
  const { rows } = await pool.query('SELECT version FROM schema_migrations');
  const applied = new Set(rows.map((r) => r.version));
  for (const file of fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
    if (applied.has(file)) continue;
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (version, applied_at) VALUES ($1, $2)', [file, new Date().toISOString()]);
      await client.query('COMMIT');
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
    console.log(`[db] applied migration ${file}`);
  }
}

// Top-level await: chặn import cho tới khi DB sẵn sàng + migration xong (giữ nguyên hành vi cũ).
await runMigrations();

export function now() {
  return new Date().toISOString();
}
