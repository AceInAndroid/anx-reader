import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openDatabase } from '../src/database.js';
import { createApp } from '../src/app.js';
import { hashPassword } from '../src/password.js';

let root;
let database;
let server;
let baseUrl;
let passwordHash;
let token;
let clock;

test.before(async () => {
  root = await mkdtemp(join(tmpdir(), 'anx-progress-sync-'));
  passwordHash = await hashPassword('correct horse battery staple');
  clock = 1700000000000;
  database = openDatabase(join(root, 'progress.sqlite'), { retentionDays: 90 });
  server = createApp({ database, username: 'reader', passwordHash, sessionTtlDays: 30, now: () => clock });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise((resolve) => server.close(resolve));
  database.close();
  await rm(root, { recursive: true, force: true });
});

test('health and authentication lifecycle', async () => {
  const health = await request('/health');
  assert.equal(health.status, 200);
  assert.equal(health.body.protocolVersion, 1);

  const bad = await request('/v1/auth/login', { method: 'POST', body: { username: 'reader', password: 'wrong password' } });
  assert.equal(bad.status, 401);
  const login = await request('/v1/auth/login', { method: 'POST', body: { username: 'reader', password: 'correct horse battery staple' } });
  assert.equal(login.status, 200);
  token = login.body.accessToken;
  assert.ok(token);
  const logout = await request('/v1/auth/logout', { method: 'POST', token });
  assert.equal(logout.status, 204);
  const rejected = await request('/v1/changes', { token });
  assert.equal(rejected.status, 401);
  const relogin = await request('/v1/auth/login', { method: 'POST', body: { username: 'reader', password: 'correct horse battery staple' } });
  token = relogin.body.accessToken;
});

test('position upload is idempotent and stale updates do not overwrite', async () => {
  const first = await putProgress('md5:book', 'phone', 0.4, 1000);
  assert.equal(first.status, 200);
  assert.equal(first.body.accepted, true);
  const stale = await putProgress('md5:book', 'phone', 0.2, 999);
  assert.equal(stale.body.accepted, false);
  const book = await request('/v1/books/md5%3Abook/progress', { token });
  assert.equal(book.body.positions.length, 1);
  assert.equal(book.body.positions[0].progress, 0.4);
  assert.equal(book.body.farthestProgress, 0.4);
});

test('multiple devices and incremental changes are isolated', async () => {
  await putProgress('md5:book', 'tablet', 0.8, 2000);
  const all = await request('/v1/changes', { token });
  assert.equal(all.status, 200);
  assert.equal(all.body.changes.length, 2);
  const cursor = all.body.nextCursor;
  await putProgress('md5:book', 'phone', 0.5, 3000);
  const delta = await request(`/v1/changes?cursor=${cursor}`, { token });
  assert.equal(delta.body.changes.length, 1);
  assert.equal(delta.body.changes[0].deviceId, 'phone');
  assert.equal(delta.body.changes[0].progress, 0.5);
});

test('validation, auth, and body limits are enforced', async () => {
  assert.equal((await request('/v1/changes')).status, 401);
  const invalid = await putProgress('md5:book', 'phone', 2, 4000);
  assert.equal(invalid.status, 400);
  assert.equal(invalid.body.error.code, 'invalid_progress');
  const unsupported = await request('/v1/books/md5%3Abook/devices/phone/progress', {
    method: 'PUT', token,
    body: { schemaVersion: 9, bookKey: 'md5:book', deviceId: 'phone', locator: { type: 'x', value: 'x' }, progress: 0, updatedAt: 1 },
  });
  assert.equal(unsupported.body.error.code, 'unsupported_schema');
  const oversized = await request('/v1/books/md5%3Abook/devices/phone/progress', {
    method: 'PUT', token, rawBody: JSON.stringify({ schemaVersion: 1, bookKey: 'md5:book', deviceId: 'phone', locator: { type: 'x', value: 'x'.repeat(70000) }, progress: 0, updatedAt: 1 }),
  });
  assert.equal(oversized.status, 413);
  assert.equal((await request('/v1/changes?cursor=nope', { token })).status, 400);
});

test('cursor expiry is explicit after retention cleanup', async () => {
  const shortDb = openDatabase(join(root, 'short.sqlite'), { retentionDays: 1 });
  const shortServer = createApp({ database: shortDb, username: 'reader', passwordHash, now: () => clock });
  await new Promise((resolve) => shortServer.listen(0, '127.0.0.1', resolve));
  const shortBase = `http://127.0.0.1:${shortServer.address().port}`;
  const login = await requestTo(shortBase, '/v1/auth/login', { method: 'POST', body: { username: 'reader', password: 'correct horse battery staple' } });
  const shortToken = login.body.accessToken;
  const put = await requestTo(shortBase, '/v1/books/b/devices/d/progress', { method: 'PUT', token: shortToken, body: { schemaVersion: 1, bookKey: 'b', deviceId: 'd', locator: { type: 'x', value: 'y' }, progress: 0.1, updatedAt: 1 } });
  assert.equal(put.status, 200);
  const initial = await requestTo(shortBase, '/v1/changes', { token: shortToken });
  clock += 2 * 24 * 60 * 60 * 1000;
  // A new write invokes maintenance and expires the previous change.
  await requestTo(shortBase, '/v1/books/b/devices/d2/progress', { method: 'PUT', token: shortToken, body: { schemaVersion: 1, bookKey: 'b', deviceId: 'd2', locator: { type: 'x', value: 'y' }, progress: 0.2, updatedAt: 2 } });
  const expired = await requestTo(shortBase, `/v1/changes?cursor=${initial.body.nextCursor - 1}`, { token: shortToken });
  assert.equal(expired.status, 409);
  await new Promise((resolve) => shortServer.close(resolve));
  shortDb.close();
});

test('deletions propagate and SQLite data survives reopening', async () => {
  const deletion = await request('/v1/books/md5%3Abook/devices/tablet/progress', {
    method: 'DELETE', token,
  });
  assert.equal(deletion.status, 200);
  assert.equal(deletion.body.accepted, true);
  const changes = await request(`/v1/changes?cursor=${deletion.body.revision - 1}`, { token });
  assert.deepEqual(changes.body.changes, [{
    bookKey: 'md5:book',
    deviceId: 'tablet',
    updatedAt: clock,
    revision: deletion.body.revision,
    deleted: true,
  }]);

  const persistentPath = join(root, 'persistent.sqlite');
  let persistent = openDatabase(persistentPath);
  persistent.putPosition({
    bookKey: 'persistent-book', deviceId: 'device',
    locator: { type: 'page', value: '42' }, progress: 0.42,
    chapterHref: null, chapterTitle: null, updatedAt: 42,
  }, clock);
  persistent.close();
  persistent = openDatabase(persistentPath);
  assert.equal(persistent.listBook('persistent-book')[0].locator.value, '42');
  persistent.close();
});

test('expired sessions are rejected', async () => {
  clock += 31 * 24 * 60 * 60 * 1000;
  const response = await request('/v1/changes', { token });
  assert.equal(response.status, 401);
});

test('concurrent device writes remain consistent', async () => {
  const login = await request('/v1/auth/login', {
    method: 'POST',
    body: {
      username: 'reader',
      password: 'correct horse battery staple',
    },
  });
  const concurrentToken = login.body.accessToken;
  const writes = await Promise.all(
    Array.from({ length: 20 }, (_, index) =>
      request(`/v1/books/concurrent/devices/device-${index}/progress`, {
        method: 'PUT',
        token: concurrentToken,
        body: {
          schemaVersion: 1,
          bookKey: 'concurrent',
          deviceId: `device-${index}`,
          locator: { type: 'page', value: String(index + 1) },
          progress: index / 20,
          updatedAt: 10_000 + index,
        },
      }),
    ),
  );
  assert.ok(writes.every((write) => write.status === 200));
  const positions = await request('/v1/books/concurrent/progress', {
    token: concurrentToken,
  });
  assert.equal(positions.body.positions.length, 20);
  assert.equal(new Set(positions.body.positions.map((item) => item.deviceId)).size, 20);
});

async function putProgress(bookKey, deviceId, progress, updatedAt) {
  return request(`/v1/books/${encodeURIComponent(bookKey)}/devices/${encodeURIComponent(deviceId)}/progress`, {
    method: 'PUT', token, body: { schemaVersion: 1, bookKey, deviceId, locator: { type: 'epub-cfi', value: `cfi-${progress}` }, progress, updatedAt },
  });
}

async function request(path, options = {}) { return requestTo(baseUrl, path, options); }
async function requestTo(origin, path, { method = 'GET', body, rawBody, token: bearer } = {}) {
  const response = await fetch(`${origin}${path}`, {
    method,
    headers: {
      ...(body || rawBody ? { 'content-type': 'application/json' } : {}),
      ...(bearer ? { authorization: `Bearer ${bearer}` } : {}),
    },
    body: rawBody ?? (body ? JSON.stringify(body) : undefined),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}
