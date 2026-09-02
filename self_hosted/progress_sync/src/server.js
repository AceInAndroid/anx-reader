import { openDatabase } from './database.js';
import { createApp } from './app.js';

const port = parseInteger(process.env.PORT ?? '8080', 'PORT', 1, 65535);
const sessionTtlDays = parseInteger(process.env.SESSION_TTL_DAYS ?? '30', 'SESSION_TTL_DAYS', 1, 365);
const retentionDays = parseInteger(process.env.CHANGE_RETENTION_DAYS ?? '90', 'CHANGE_RETENTION_DAYS', 1, 3650);
const maxChanges = parseInteger(process.env.MAX_CHANGES ?? '100000', 'MAX_CHANGES', 100, 10000000);
const database = openDatabase(process.env.DATABASE_PATH ?? '/data/progress.sqlite', {
  retentionDays,
  maxChanges,
});
const server = createApp({
  database,
  username: process.env.SYNC_USERNAME,
  passwordHash: process.env.SYNC_PASSWORD_HASH,
  sessionTtlDays,
});

server.listen(port, '0.0.0.0', () => {
  console.log(`anx-progress-sync listening on port ${port}`);
});

function shutdown() {
  server.close(() => {
    database.close();
    process.exit(0);
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

function parseInteger(value, name, min, max) {
  if (!/^\d+$/.test(value)) throw new Error(`${name} must be an integer`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`${name} must be between ${min} and ${max}`);
  }
  return parsed;
}
