import Database from 'better-sqlite3';

const ACCOUNT_ID = 'default';
const DAY_MS = 24 * 60 * 60 * 1000;

export function openDatabase(path, { retentionDays = 90, maxChanges = 100000 } = {}) {
  const db = new Database(path);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('busy_timeout = 5000');
  db.exec(`
    CREATE TABLE IF NOT EXISTS sync_sessions (
      token_hash TEXT PRIMARY KEY,
      expires_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS reading_positions (
      account_id TEXT NOT NULL,
      book_key TEXT NOT NULL,
      device_id TEXT NOT NULL,
      locator_type TEXT NOT NULL,
      locator_value TEXT NOT NULL,
      progress REAL NOT NULL CHECK (progress >= 0 AND progress <= 1),
      chapter_href TEXT,
      chapter_title TEXT,
      updated_at INTEGER NOT NULL,
      revision INTEGER NOT NULL,
      PRIMARY KEY (account_id, book_key, device_id)
    );
    CREATE TABLE IF NOT EXISTS sync_changes (
      revision INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id TEXT NOT NULL,
      book_key TEXT NOT NULL,
      device_id TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      operation TEXT NOT NULL DEFAULT 'upsert'
        CHECK (operation IN ('upsert', 'delete'))
    );
    CREATE INDEX IF NOT EXISTS idx_positions_account_book
      ON reading_positions(account_id, book_key);
    CREATE INDEX IF NOT EXISTS idx_changes_account_revision
      ON sync_changes(account_id, revision);
  `);

  const statements = {
    insertSession: db.prepare(
      'INSERT INTO sync_sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)',
    ),
    getSession: db.prepare(
      'SELECT expires_at FROM sync_sessions WHERE token_hash = ?',
    ),
    deleteSession: db.prepare('DELETE FROM sync_sessions WHERE token_hash = ?'),
    purgeSessions: db.prepare('DELETE FROM sync_sessions WHERE expires_at <= ?'),
    getPosition: db.prepare(`
      SELECT * FROM reading_positions
      WHERE account_id = ? AND book_key = ? AND device_id = ?
    `),
    insertChange: db.prepare(`
      INSERT INTO sync_changes(account_id, book_key, device_id, updated_at, operation)
      VALUES (?, ?, ?, ?, ?)
    `),
    upsertPosition: db.prepare(`
      INSERT INTO reading_positions(
        account_id, book_key, device_id, locator_type, locator_value,
        progress, chapter_href, chapter_title, updated_at, revision
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, book_key, device_id) DO UPDATE SET
        locator_type = excluded.locator_type,
        locator_value = excluded.locator_value,
        progress = excluded.progress,
        chapter_href = excluded.chapter_href,
        chapter_title = excluded.chapter_title,
        updated_at = excluded.updated_at,
        revision = excluded.revision
    `),
    listBook: db.prepare(`
      SELECT * FROM reading_positions
      WHERE account_id = ? AND book_key = ?
      ORDER BY updated_at DESC, device_id ASC
    `),
    listAll: db.prepare(`
      SELECT * FROM reading_positions WHERE account_id = ?
      ORDER BY revision ASC
    `),
    deletePosition: db.prepare(`
      DELETE FROM reading_positions
      WHERE account_id = ? AND book_key = ? AND device_id = ?
    `),
    maxRevision: db.prepare(`
      SELECT MAX(value) AS value FROM (
        SELECT COALESCE(MAX(revision), 0) AS value
          FROM sync_changes WHERE account_id = ?
        UNION ALL
        SELECT COALESCE((SELECT seq FROM sqlite_sequence WHERE name = 'sync_changes'), 0)
      )
    `),
    minRevision: db.prepare(
      'SELECT MIN(revision) AS value FROM sync_changes WHERE account_id = ?',
    ),
    changesAfter: db.prepare(`
      SELECT c.revision, c.book_key, c.device_id, c.updated_at, c.operation,
             p.locator_type, p.locator_value, p.progress,
             p.chapter_href, p.chapter_title, p.revision AS position_revision
      FROM sync_changes c
      LEFT JOIN reading_positions p
        ON p.account_id = c.account_id
       AND p.book_key = c.book_key
       AND p.device_id = c.device_id
      WHERE c.account_id = ? AND c.revision > ?
      ORDER BY c.revision ASC
    `),
    purgeByAge: db.prepare('DELETE FROM sync_changes WHERE updated_at < ?'),
    purgeByCount: db.prepare(`
      DELETE FROM sync_changes
      WHERE revision IN (
        SELECT revision FROM sync_changes
        ORDER BY revision DESC
        LIMIT -1 OFFSET ?
      )
    `),
  };

  const maintain = db.transaction((now) => {
    statements.purgeSessions.run(now);
    statements.purgeByAge.run(now - retentionDays * DAY_MS);
    statements.purgeByCount.run(maxChanges);
  });

  const putPosition = db.transaction((position, now) => {
    const current = statements.getPosition.get(ACCOUNT_ID, position.bookKey, position.deviceId);
    if (current && current.updated_at >= position.updatedAt) {
      return { accepted: false, revision: current.revision };
    }
    const change = statements.insertChange.run(
      ACCOUNT_ID,
      position.bookKey,
      position.deviceId,
      now,
      'upsert',
    );
    const revision = Number(change.lastInsertRowid);
    statements.upsertPosition.run(
      ACCOUNT_ID,
      position.bookKey,
      position.deviceId,
      position.locator.type,
      position.locator.value,
      position.progress,
      position.chapterHref,
      position.chapterTitle,
      position.updatedAt,
      revision,
    );
    maintain(now);
    return { accepted: true, revision };
  });

  const removePosition = db.transaction((bookKey, deviceId, now) => {
    const result = statements.deletePosition.run(ACCOUNT_ID, bookKey, deviceId);
    if (result.changes === 0) return { accepted: false, revision: null };
    const change = statements.insertChange.run(
      ACCOUNT_ID,
      bookKey,
      deviceId,
      now,
      'delete',
    );
    maintain(now);
    return { accepted: true, revision: Number(change.lastInsertRowid) };
  });

  maintain(Date.now());

  return {
    close: () => db.close(),
    createSession(tokenHash, expiresAt, now) {
      statements.insertSession.run(tokenHash, expiresAt, now);
    },
    isSessionValid(tokenHash, now) {
      const session = statements.getSession.get(tokenHash);
      if (!session || session.expires_at <= now) {
        if (session) statements.deleteSession.run(tokenHash);
        return false;
      }
      return true;
    },
    deleteSession(tokenHash) {
      statements.deleteSession.run(tokenHash);
    },
    putPosition,
    removePosition,
    listBook(bookKey) {
      return statements.listBook.all(ACCOUNT_ID, bookKey).map(toPosition);
    },
    getChanges(cursor) {
      const maxRevision = Number(statements.maxRevision.get(ACCOUNT_ID).value);
      if (cursor === null) {
        return {
          nextCursor: String(maxRevision),
          changes: statements.listAll.all(ACCOUNT_ID).map(toPosition),
        };
      }
      const min = statements.minRevision.get(ACCOUNT_ID).value;
      if (min !== null && cursor < Number(min) - 1) {
        return { expired: true, minimumCursor: String(Number(min) - 1) };
      }
      if (min === null && cursor < maxRevision) {
        return { expired: true, minimumCursor: String(maxRevision) };
      }
      const rows = statements.changesAfter.all(ACCOUNT_ID, cursor);
      // Return only the last event for each position key. Its revision remains
      // sufficient because nextCursor advances past all events in this batch.
      const latest = new Map();
      for (const row of rows) latest.set(`${row.book_key}\0${row.device_id}`, row);
      return {
        nextCursor: String(maxRevision),
        changes: [...latest.values()].sort((a, b) => a.revision - b.revision).map((row) => {
          if (row.operation === 'delete' || row.position_revision === null) {
            return {
              bookKey: row.book_key,
              deviceId: row.device_id,
              updatedAt: row.updated_at,
              revision: row.revision,
              deleted: true,
            };
          }
          return toPosition({ ...row, revision: row.position_revision });
        }),
      };
    },
  };
}

function toPosition(row) {
  return {
    bookKey: row.book_key,
    deviceId: row.device_id,
    locator: { type: row.locator_type, value: row.locator_value },
    progress: row.progress,
    chapterHref: row.chapter_href,
    chapterTitle: row.chapter_title,
    updatedAt: row.updated_at,
    revision: row.revision,
  };
}
