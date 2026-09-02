import { randomBytes, scrypt as scryptCallback, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(scryptCallback);
const KEY_LENGTH = 64;
const SCRYPT_OPTIONS = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

export async function hashPassword(password) {
  if (typeof password !== 'string' || password.length < 12) {
    throw new Error('Password must contain at least 12 characters');
  }
  const salt = randomBytes(16);
  const derived = await scrypt(password, salt, KEY_LENGTH, SCRYPT_OPTIONS);
  return `scrypt$${SCRYPT_OPTIONS.N}$${SCRYPT_OPTIONS.r}$${SCRYPT_OPTIONS.p}$${salt.toString('base64')}$${derived.toString('base64')}`;
}

export async function verifyPassword(password, encodedHash) {
  try {
    const [algorithm, n, r, p, saltBase64, hashBase64, extra] = encodedHash.split('$');
    if (algorithm !== 'scrypt' || extra !== undefined) return false;
    const options = {
      N: Number.parseInt(n, 10),
      r: Number.parseInt(r, 10),
      p: Number.parseInt(p, 10),
      maxmem: 64 * 1024 * 1024,
    };
    if (options.N !== 16384 || options.r !== 8 || options.p !== 1) return false;
    const salt = Buffer.from(saltBase64, 'base64');
    const expected = Buffer.from(hashBase64, 'base64');
    if (salt.length !== 16 || expected.length !== KEY_LENGTH) return false;
    const actual = await scrypt(password, salt, expected.length, options);
    return timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}
