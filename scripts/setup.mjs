// One-shot setup: copy .env.example -> .env (if missing) and npm install for every package.
// Zero-dependency, cross-platform (Windows/macOS/Linux).
import { existsSync, copyFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const services = ['product-service', 'user-service', 'order-service', 'frontend'];

for (const svc of services) {
  const dir = path.join(root, 'services', svc);
  const example = path.join(dir, '.env.example');
  const env = path.join(dir, '.env');
  if (existsSync(example) && !existsSync(env)) {
    copyFileSync(example, env);
    console.log(`[setup] created ${svc}/.env from .env.example`);
  }
}

for (const dir of [root, ...services.map((s) => path.join(root, 'services', s))]) {
  console.log(`\n[setup] npm install in ${dir}`);
  const r = spawnSync('npm', ['install', '--no-audit', '--no-fund'], {
    cwd: dir,
    stdio: 'inherit',
    shell: true, // needed on Windows to resolve npm.cmd
  });
  if (r.status !== 0) {
    console.error(`[setup] npm install failed in ${dir}`);
    process.exit(r.status ?? 1);
  }
}

console.log('\n[setup] done. Run: npm run dev');
