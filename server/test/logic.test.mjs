// Tests for the class leaderboard server logic (TRD Section 17). Run: node --test server/test/*.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { handle, hashToken, MAX_MEMBERS, MIN_WRITE_GAP_MS, RETENTION_MS } from '../src/logic.mjs';

// An in-memory store with the same methods as the D1 store.
function memoryStore() {
  const rows = new Map();
  const id = (code, key) => `${code}/${key}`;
  return {
    rows,
    async getMember(code, key) { return rows.get(id(code, key)) ?? null; },
    async createMember(m) {
      if (rows.has(id(m.class_code, m.handle_key))) return false;
      rows.set(id(m.class_code, m.handle_key), {
        class_code: m.class_code, handle_key: m.handle_key, handle: m.handle, token_hash: m.token_hash, as_of: m.asOf,
        week_cost_eur: m.weekCostEUR, week_output_tokens: m.weekOutputTokens, spend_since_install_eur: m.spendSinceInstallEUR, updated_at: m.updated_at,
      });
      return true;
    },
    async updateMember(code, key, f) {
      Object.assign(rows.get(id(code, key)), {
        as_of: f.asOf, week_cost_eur: f.weekCostEUR, week_output_tokens: f.weekOutputTokens, spend_since_install_eur: f.spendSinceInstallEUR, updated_at: f.updated_at,
      });
    },
    async countMembers(code) { return [...rows.values()].filter((r) => r.class_code === code).length; },
    async listMembers(code) { return [...rows.values()].filter((r) => r.class_code === code); },
    async deleteMember(code, key) { rows.delete(id(code, key)); },
    async deleteStale(code, cutoff) {
      for (const [k, r] of rows) if (r.class_code === code && r.updated_at < cutoff) rows.delete(k);
    },
  };
}

const NOW = Date.UTC(2026, 10, 25, 12, 0, 0);
const CODE = 'cafe-k3m9-x7q2';
const TOKEN_A = 'A'.repeat(43);
const TOKEN_B = 'B'.repeat(43);
const GOOD = { v: 1, asOf: '2026-11-25', weekCostEUR: 8.5, weekOutputTokens: 123456, spendSinceInstallEUR: 45.6 };

function req(method, path, { token, body } = {}) {
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  return new Request(`https://leaderboard.example${path}`, { method, headers, body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body) });
}
const member = (handle) => `/v1/classes/${CODE}/members/${handle}`;
const put = (store, handle, token, body = GOOD, now = NOW) => handle_(store, req('PUT', member(handle), { token, body }), now);
const handle_ = (store, request, now = NOW) => handle(request, store, now);

test('a first PUT makes the member and stores only a token hash', async () => {
  const store = memoryStore();
  const res = await put(store, 'Ana', TOKEN_A);
  assert.equal(res.status, 204);
  const row = [...store.rows.values()][0];
  assert.equal(row.handle, 'Ana');
  assert.equal(row.handle_key, 'ana');
  assert.equal(row.token_hash, await hashToken(TOKEN_A));
  assert.ok(!JSON.stringify(row).includes(TOKEN_A), 'the token is not stored');
  assert.deepEqual(Object.keys(row).sort(), ['as_of', 'class_code', 'handle', 'handle_key', 'spend_since_install_eur', 'token_hash', 'updated_at', 'week_cost_eur', 'week_output_tokens']);
});

test('another token cannot take a handle, even with a different case', async () => {
  const store = memoryStore();
  await put(store, 'Ana', TOKEN_A);
  assert.equal((await put(store, 'ANA', TOKEN_B)).status, 409);
  assert.equal((await put(store, 'ana', TOKEN_B)).status, 409);
  assert.equal([...store.rows.values()].length, 1);
});

test('the owner updates after 10 minutes and gets 429 before', async () => {
  const store = memoryStore();
  await put(store, 'Ana', TOKEN_A);
  const soon = await put(store, 'Ana', TOKEN_A, { ...GOOD, weekCostEUR: 9 }, NOW + MIN_WRITE_GAP_MS - 1000);
  assert.equal(soon.status, 429);
  assert.equal(soon.headers['retry-after'], '1');
  assert.equal((await put(store, 'Ana', TOKEN_A, { ...GOOD, weekCostEUR: 9 }, NOW + MIN_WRITE_GAP_MS)).status, 204);
  assert.equal([...store.rows.values()][0].week_cost_eur, 9);
});

test('a PUT needs a well-formed token', async () => {
  const store = memoryStore();
  assert.equal((await put(store, 'Ana', undefined)).status, 401);
  assert.equal((await put(store, 'Ana', 'short')).status, 401);
  assert.equal((await put(store, 'Ana', 'A'.repeat(44))).status, 401);
  assert.equal(store.rows.size, 0);
});

test('bad bodies give 422 and store nothing', async () => {
  const store = memoryStore();
  const bad = [
    '', 'not json', '[]', 'null', '1',
    { ...GOOD, extra: 1 },
    { v: 1, asOf: GOOD.asOf, weekCostEUR: 1, weekOutputTokens: 1 },
    { ...GOOD, v: 2 },
    { ...GOOD, asOf: '2026-13-45' },
    { ...GOOD, asOf: 'yesterday' },
    { ...GOOD, weekCostEUR: -1 },
    { ...GOOD, weekCostEUR: 100_001 },
    { ...GOOD, weekCostEUR: '8.5' },
    { ...GOOD, weekOutputTokens: 1.5 },
    { ...GOOD, weekOutputTokens: 10_000_000_000_001 },
    { ...GOOD, spendSinceInstallEUR: 10_000_001 },
    '{"v":1,"asOf":"2026-11-25","weekCostEUR":1e999,"weekOutputTokens":1,"spendSinceInstallEUR":1}',
    JSON.stringify({ ...GOOD, padding: 'x'.repeat(2000) }),
  ];
  for (const body of bad) {
    const res = await put(store, 'Ana', TOKEN_A, body);
    assert.equal(res.status, 422, `body ${String(typeof body === 'string' ? body : JSON.stringify(body)).slice(0, 60)}`);
  }
  assert.equal(store.rows.size, 0);
});

test('codes and handles are validated', async () => {
  const store = memoryStore();
  for (const handle of ['a', 'x'.repeat(21), 'ana smith', 'ana%20', 'ana.b', 'ñandú']) {
    const res = await handle_(store, req('PUT', `/v1/classes/${CODE}/members/${encodeURIComponent(handle)}`, { token: TOKEN_A, body: GOOD }));
    assert.equal(res.status, 422, handle);
  }
  for (const code of ['short', 'UPPERCASE-CODE', 'has space code', 'x'.repeat(41), 'bad_underscore']) {
    const res = await handle_(store, req('PUT', `/v1/classes/${encodeURIComponent(code)}/members/ana`, { token: TOKEN_A, body: GOOD }));
    assert.equal(res.status, 422, code);
  }
  assert.equal(store.rows.size, 0);
});

test('a class holds 500 members', async () => {
  const store = memoryStore();
  for (let i = 0; i < MAX_MEMBERS; i++) {
    await store.createMember({ class_code: CODE, handle_key: `m${i}`, handle: `m${i}`, token_hash: 'x', asOf: '2026-11-25', weekCostEUR: 1, weekOutputTokens: 1, spendSinceInstallEUR: 1, updated_at: NOW });
  }
  assert.equal((await put(store, 'Late', TOKEN_A)).status, 403);
  // Another class is not full.
  await store.createMember({ class_code: 'other-class-1', handle_key: 'ana', handle: 'Ana', token_hash: 'x', asOf: '2026-11-25', weekCostEUR: 1, weekOutputTokens: 1, spendSinceInstallEUR: 1, updated_at: NOW });
  assert.equal((await handle_(store, req('PUT', '/v1/classes/other-class-1/members/Bob', { token: TOKEN_A, body: GOOD }))).status, 204);
});

test('the board lists the members and hides the token hash', async () => {
  const store = memoryStore();
  await put(store, 'Zoe', TOKEN_B);
  await put(store, 'ana', TOKEN_A);
  const res = await handle_(store, req('GET', `/v1/classes/${CODE}/board`));
  assert.equal(res.status, 200);
  const body = JSON.parse(res.body);
  assert.equal(body.v, 1);
  assert.deepEqual(body.members.map((m) => m.handle), ['ana', 'Zoe']);
  assert.deepEqual(Object.keys(body.members[0]).sort(), ['asOf', 'handle', 'spendSinceInstallEUR', 'weekCostEUR', 'weekOutputTokens']);
  assert.ok(!res.body.includes('token'));
});

test('an unknown class gives 404 and the board needs no token', async () => {
  const store = memoryStore();
  assert.equal((await handle_(store, req('GET', `/v1/classes/${CODE}/board`))).status, 404);
});

test('a member that is 30 days old is deleted on the next write or read', async () => {
  const store = memoryStore();
  await put(store, 'Old', TOKEN_A);
  const later = NOW + RETENTION_MS + 1000;
  await put(store, 'New', TOKEN_B, GOOD, later);
  assert.deepEqual([...store.rows.values()].map((r) => r.handle), ['New']);
  const board = JSON.parse((await handle_(store, req('GET', `/v1/classes/${CODE}/board`), later + RETENTION_MS + 1000)).body ?? '{}');
  assert.equal(board.error, 'class not found');
});

test('DELETE needs the right token', async () => {
  const store = memoryStore();
  await put(store, 'Ana', TOKEN_A);
  assert.equal((await handle_(store, req('DELETE', member('Ana')))).status, 401);
  assert.equal((await handle_(store, req('DELETE', member('Ana'), { token: TOKEN_B }))).status, 401);
  assert.equal(store.rows.size, 1);
  assert.equal((await handle_(store, req('DELETE', member('ana'), { token: TOKEN_A }))).status, 204);
  assert.equal(store.rows.size, 0);
  assert.equal((await handle_(store, req('DELETE', member('ana'), { token: TOKEN_A }))).status, 404);
});

test('a deleted handle can be taken by someone else', async () => {
  const store = memoryStore();
  await put(store, 'Ana', TOKEN_A);
  await handle_(store, req('DELETE', member('Ana'), { token: TOKEN_A }));
  assert.equal((await put(store, 'Ana', TOKEN_B)).status, 204);
});

test('other paths and methods are refused', async () => {
  const store = memoryStore();
  assert.equal((await handle_(store, req('GET', '/'))).status, 404);
  assert.equal((await handle_(store, req('GET', '/v1/classes'))).status, 404);
  assert.equal((await handle_(store, req('GET', `/v1/classes/${CODE}/members/ana`))).status, 405);
  assert.equal((await handle_(store, req('POST', `/v1/classes/${CODE}/board`))).status, 405);
  assert.equal((await handle_(store, req('PATCH', member('ana'), { token: TOKEN_A }))).status, 405);
  assert.equal((await handle_(store, req('GET', `/v1/classes/${CODE}/members/ana/extra`))).status, 404);
});

test('replies are never cached', async () => {
  const store = memoryStore();
  for (const res of [await put(store, 'Ana', TOKEN_A), await handle_(store, req('GET', `/v1/classes/${CODE}/board`)), await handle_(store, req('GET', '/x'))]) {
    assert.equal(res.headers['cache-control'], 'no-store');
  }
});

test('two requests that make the same handle at the same time give one member', async () => {
  const store = memoryStore();
  const results = await Promise.all([put(store, 'Race', TOKEN_A), put(store, 'Race', TOKEN_B)]);
  assert.deepEqual(results.map((r) => r.status).sort(), [204, 409]);
  assert.equal(store.rows.size, 1);
});
