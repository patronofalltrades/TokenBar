// Class leaderboard server logic (TRD Section 17, D62). No Cloudflare code: a test can run it with an in-memory store.
// The store has these async methods: getMember, createMember, updateMember, countMembers, listMembers, deleteMember, deleteStale.
const CODE = /^[a-z0-9-]{8,40}$/;
const HANDLE = /^[A-Za-z0-9_-]{2,20}$/;
const TOKEN = /^[A-Za-z0-9_-]{43}$/;  // 32 bytes in base64url
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const BODY_KEYS = ['asOf', 'spendSinceInstallEUR', 'v', 'weekCostEUR', 'weekOutputTokens'];

const MAX_BODY_BYTES = 1024;
const MAX_MEMBERS = 500;
const MIN_WRITE_GAP_MS = 10 * 60 * 1000;
const RETENTION_MS = 30 * 24 * 3600 * 1000;

const json = (status, body, headers = {}) => ({
  status,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store', ...headers },
  body: JSON.stringify(body),
});
const empty = (status) => ({ status, headers: { 'cache-control': 'no-store' }, body: null });
const fail = (status, error, headers) => json(status, { error }, headers);

async function hashToken(token) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Both strings have the same length (a SHA-256 in hex). No early exit.
function sameHash(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function bearer(request) {
  const match = /^Bearer (\S+)$/.exec(request.headers.get('authorization') || '');
  return match && TOKEN.test(match[1]) ? match[1] : null;
}

// Returns the numbers, or a string with the reason.
function parseBody(text) {
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) return 'body too large';
  let body;
  try { body = JSON.parse(text); } catch { return 'body is not JSON'; }
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return 'body is not an object';
  if (Object.keys(body).sort().join() !== BODY_KEYS.join()) return 'body has missing or unknown fields';
  if (body.v !== 1) return 'unknown version';
  if (typeof body.asOf !== 'string' || !DATE.test(body.asOf) || Number.isNaN(Date.parse(body.asOf))) return 'asOf is not a date';
  const num = (value, max, whole) =>
    typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= max && (!whole || Number.isInteger(value));
  if (!num(body.weekCostEUR, 100_000)) return 'weekCostEUR is out of range';
  if (!num(body.weekOutputTokens, 10_000_000_000_000, true)) return 'weekOutputTokens is out of range';
  if (!num(body.spendSinceInstallEUR, 10_000_000)) return 'spendSinceInstallEUR is out of range';
  return { asOf: body.asOf, weekCostEUR: body.weekCostEUR, weekOutputTokens: body.weekOutputTokens, spendSinceInstallEUR: body.spendSinceInstallEUR };
}

async function put(request, store, code, handle, now) {
  if (!HANDLE.test(handle)) return fail(422, 'handle is not valid');
  const token = bearer(request);
  if (!token) return fail(401, 'missing or malformed token');
  const parsed = parseBody(await request.text());
  if (typeof parsed === 'string') return fail(422, parsed);

  const key = handle.toLowerCase();
  const hash = await hashToken(token);
  await store.deleteStale(code, now - RETENTION_MS);

  const existing = await store.getMember(code, key);
  if (existing) {
    if (!sameHash(existing.token_hash, hash)) return fail(409, 'handle belongs to another member');
    const wait = existing.updated_at + MIN_WRITE_GAP_MS - now;
    if (wait > 0) return fail(429, 'too soon', { 'retry-after': String(Math.ceil(wait / 1000)) });
    await store.updateMember(code, key, { ...parsed, updated_at: now });
    return empty(204);
  }
  if ((await store.countMembers(code)) >= MAX_MEMBERS) return fail(403, 'class is full');
  const created = await store.createMember({ class_code: code, handle_key: key, handle, token_hash: hash, ...parsed, updated_at: now });
  // A second request made the same handle first.
  return created ? empty(204) : fail(409, 'handle belongs to another member');
}

async function board(store, code, now) {
  await store.deleteStale(code, now - RETENTION_MS);
  const rows = await store.listMembers(code);
  if (rows.length === 0) return fail(404, 'class not found');
  const members = rows
    .map((r) => ({ handle: r.handle, asOf: r.as_of, weekCostEUR: r.week_cost_eur, weekOutputTokens: r.week_output_tokens, spendSinceInstallEUR: r.spend_since_install_eur }))
    .sort((a, b) => (a.handle.toLowerCase() < b.handle.toLowerCase() ? -1 : 1));
  return json(200, { v: 1, members });
}

async function remove(request, store, code, handle) {
  if (!HANDLE.test(handle)) return fail(422, 'handle is not valid');
  const token = bearer(request);
  if (!token) return fail(401, 'missing or malformed token');
  const key = handle.toLowerCase();
  const existing = await store.getMember(code, key);
  if (!existing) return fail(404, 'member not found');
  if (!sameHash(existing.token_hash, await hashToken(token))) return fail(401, 'token does not match');
  await store.deleteMember(code, key);
  return empty(204);
}

// request: a standard Request. Returns { status, headers, body }.
async function handle(request, store, now = Date.now()) {
  const url = new URL(request.url);
  const match = /^\/v1\/classes\/([^/]+)\/(?:(board)|members\/([^/]+))$/.exec(url.pathname);
  if (!match) return fail(404, 'not found');
  const [, code, isBoard, handleName] = match;
  if (!CODE.test(code)) return fail(422, 'class code is not valid');

  if (isBoard) return request.method === 'GET' ? board(store, code, now) : fail(405, 'method not allowed', { allow: 'GET' });
  if (request.method === 'PUT') return put(request, store, code, handleName, now);
  if (request.method === 'DELETE') return remove(request, store, code, handleName);
  return fail(405, 'method not allowed', { allow: 'PUT, DELETE' });
}

export { handle, hashToken, parseBody, MAX_MEMBERS, MIN_WRITE_GAP_MS, RETENTION_MS };
