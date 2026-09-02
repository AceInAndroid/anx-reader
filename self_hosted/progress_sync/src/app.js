import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { verifyPassword } from './password.js';

const BODY_LIMIT = 64 * 1024;
const PROTOCOL_VERSION = 1;

export function createApp({ database, username, passwordHash, sessionTtlDays = 30, now = Date.now }) {
  if (!username || !passwordHash) throw new Error('SYNC_USERNAME and SYNC_PASSWORD_HASH are required');

  return createServer(async (request, response) => {
    setCommonHeaders(response);
    try {
      const url = new URL(request.url, 'http://localhost');
      if (request.method === 'GET' && url.pathname === '/health') {
        return json(response, 200, {
          ok: true,
          service: 'anx-progress-sync',
          protocolVersion: PROTOCOL_VERSION,
        });
      }
      if (request.method === 'POST' && url.pathname === '/v1/auth/login') {
        const body = await readJson(request);
        const credentials = body && typeof body === 'object' && !Array.isArray(body)
          ? body
          : {};
        const usernameMatches = safeStringEqual(credentials.username, username);
        // Always run password verification to reduce username probing signals.
        const passwordMatches = await verifyPassword(credentials.password, passwordHash);
        if (!usernameMatches || !passwordMatches) {
          return error(response, 401, 'invalid_credentials', 'Invalid username or password');
        }
        const token = randomBytes(32).toString('base64url');
        const currentTime = now();
        const expiresAt = currentTime + sessionTtlDays * 24 * 60 * 60 * 1000;
        database.createSession(tokenHash(token), expiresAt, currentTime);
        return json(response, 200, {
          accessToken: token,
          expiresAt: new Date(expiresAt).toISOString(),
        });
      }

      const authHash = authenticate(request, database, now());
      if (!authHash) return error(response, 401, 'unauthorized', 'A valid bearer token is required');

      if (request.method === 'POST' && url.pathname === '/v1/auth/logout') {
        database.deleteSession(authHash);
        response.writeHead(204);
        return response.end();
      }

      if (request.method === 'GET' && url.pathname === '/v1/changes') {
        const rawCursor = url.searchParams.get('cursor');
        const cursor = parseCursor(rawCursor);
        if (cursor === undefined) return error(response, 400, 'invalid_cursor', 'cursor must be a non-negative integer');
        const result = database.getChanges(cursor);
        if (result.expired) {
          return json(response, 409, {
            error: { code: 'cursor_expired', message: 'The cursor is outside the retention window' },
            minimumCursor: result.minimumCursor,
          });
        }
        return json(response, 200, result);
      }

      const match = url.pathname.match(/^\/v1\/books\/([^/]+)\/devices\/([^/]+)\/progress$/);
      if (match) {
        const bookKey = decodePathPart(match[1]);
        const deviceId = decodePathPart(match[2]);
        if (bookKey === null || deviceId === null) {
          return error(response, 400, 'invalid_path', 'Invalid URL encoding');
        }
        if (request.method === 'PUT') {
          const body = await readJson(request);
          const position = validatePosition(body, bookKey, deviceId);
          const result = database.putPosition(position, now());
          return json(response, 200, { ...result, serverTime: now() });
        }
        if (request.method === 'DELETE') {
          const result = database.removePosition(bookKey, deviceId, now());
          return json(response, 200, { ...result, serverTime: now() });
        }
      }

      const bookMatch = url.pathname.match(/^\/v1\/books\/([^/]+)\/progress$/);
      if (request.method === 'GET' && bookMatch) {
        const bookKey = decodePathPart(bookMatch[1]);
        if (bookKey === null || !validString(bookKey, 1, 256)) {
          return error(response, 400, 'invalid_book_key', 'bookKey is invalid');
        }
        const positions = database.listBook(bookKey);
        return json(response, 200, {
          bookKey,
          positions,
          farthestProgress: positions.reduce((max, item) => Math.max(max, item.progress), 0),
        });
      }

      return error(response, 404, 'not_found', 'Route not found');
    } catch (caught) {
      if (caught instanceof ApiError) return error(response, caught.status, caught.code, caught.message);
      // Avoid logging request bodies, credentials, locators, or Authorization.
      console.error('Request failed', caught instanceof Error ? caught.message : 'unknown error');
      return error(response, 500, 'internal_error', 'Internal server error');
    }
  });
}

function validatePosition(body, pathBookKey, pathDeviceId) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw invalid('invalid_body', 'Body must be a JSON object');
  if (body.schemaVersion !== PROTOCOL_VERSION) throw invalid('unsupported_schema', 'Only schemaVersion 1 is supported');
  if (body.bookKey !== pathBookKey || body.deviceId !== pathDeviceId) throw invalid('path_mismatch', 'bookKey and deviceId must match the URL');
  if (!validString(body.bookKey, 1, 256)) throw invalid('invalid_book_key', 'bookKey is invalid');
  if (!validString(body.deviceId, 1, 128)) throw invalid('invalid_device_id', 'deviceId is invalid');
  if (!body.locator || typeof body.locator !== 'object' || Array.isArray(body.locator)) throw invalid('invalid_locator', 'locator is invalid');
  if (!validString(body.locator.type, 1, 32) || !validString(body.locator.value, 1, 8192)) throw invalid('invalid_locator', 'locator is invalid');
  if (typeof body.progress !== 'number' || !Number.isFinite(body.progress) || body.progress < 0 || body.progress > 1) throw invalid('invalid_progress', 'progress must be between 0 and 1');
  if (!Number.isSafeInteger(body.updatedAt) || body.updatedAt < 0) throw invalid('invalid_updated_at', 'updatedAt must be a non-negative integer');
  if (!optionalString(body.chapterHref, 2048) || !optionalString(body.chapterTitle, 512)) throw invalid('invalid_chapter', 'chapter fields are invalid');
  return {
    bookKey: body.bookKey,
    deviceId: body.deviceId,
    locator: { type: body.locator.type, value: body.locator.value },
    progress: body.progress,
    chapterHref: body.chapterHref ?? null,
    chapterTitle: body.chapterTitle ?? null,
    updatedAt: body.updatedAt,
  };
}

async function readJson(request) {
  const declared = Number.parseInt(request.headers['content-length'] ?? '0', 10);
  if (Number.isFinite(declared) && declared > BODY_LIMIT) throw new ApiError(413, 'body_too_large', 'Request body exceeds 64 KiB');
  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > BODY_LIMIT) throw new ApiError(413, 'body_too_large', 'Request body exceeds 64 KiB');
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new ApiError(400, 'invalid_json', 'Request body must be valid JSON');
  }
}

function authenticate(request, database, currentTime) {
  const authorization = request.headers.authorization;
  if (typeof authorization !== 'string' || !authorization.startsWith('Bearer ')) return null;
  const token = authorization.slice(7);
  if (!token || token.length > 256) return null;
  const hash = tokenHash(token);
  return database.isSessionValid(hash, currentTime) ? hash : null;
}

function tokenHash(token) {
  return createHash('sha256').update(token).digest('hex');
}

function parseCursor(value) {
  if (value === null || value === '') return null;
  if (!/^\d+$/.test(value)) return undefined;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : undefined;
}

function decodePathPart(value) {
  try { return decodeURIComponent(value); } catch { return null; }
}

function validString(value, min, max) {
  return typeof value === 'string' && value.length >= min && value.length <= max && !value.includes('\0');
}

function optionalString(value, max) {
  return value === undefined || value === null || validString(value, 0, max);
}

function safeStringEqual(left, right) {
  const leftHash = createHash('sha256').update(typeof left === 'string' ? left : '').digest();
  const rightHash = createHash('sha256').update(right).digest();
  return timingSafeEqual(leftHash, rightHash);
}

function setCommonHeaders(response) {
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('Cache-Control', 'no-store');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.setHeader('X-Robots-Tag', 'noindex, nofollow');
}

function json(response, status, body) {
  response.writeHead(status);
  response.end(JSON.stringify(body));
}

function error(response, status, code, message) {
  return json(response, status, { error: { code, message } });
}

function invalid(code, message) {
  return new ApiError(400, code, message);
}

class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
