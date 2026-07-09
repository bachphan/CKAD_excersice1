import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Database from 'better-sqlite3';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dbPath = path.resolve(process.env.DB_PATH || path.join(__dirname, '..', 'data', 'products.db'));
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

export const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// Migration đơn giản: chạy các file .sql theo thứ tự tên, ghi nhận vào schema_migrations.
// Cơ chế này giữ nguyên được khi chuyển sang Postgres (chỉ đổi driver).
const migrationsDir = path.join(__dirname, '..', 'migrations');
db.exec('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL)');
const applied = new Set(db.prepare('SELECT version FROM schema_migrations').all().map((r) => r.version));
for (const file of fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
  if (applied.has(file)) continue;
  const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
  db.transaction(() => {
    db.exec(sql);
    db.prepare('INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)').run(file, new Date().toISOString());
  })();
  console.log(`[db] applied migration ${file}`);
}

export function now() {
  return new Date().toISOString();
}
