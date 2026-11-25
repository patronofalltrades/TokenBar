// Cloudflare Worker entry (TRD Section 17.5, D62). It connects the logic to a D1 table. The tests do not run this file.
import { handle } from './logic.mjs';

function d1Store(db) {
  const one = (sql, ...args) => db.prepare(sql).bind(...args);
  return {
    getMember: (code, key) => one('SELECT * FROM members WHERE class_code = ?1 AND handle_key = ?2', code, key).first(),
    async createMember(m) {
      const result = await one(
        `INSERT INTO members (class_code, handle_key, handle, token_hash, as_of, week_cost_eur, week_output_tokens, spend_since_install_eur, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9) ON CONFLICT (class_code, handle_key) DO NOTHING`,
        m.class_code, m.handle_key, m.handle, m.token_hash, m.asOf, m.weekCostEUR, m.weekOutputTokens, m.spendSinceInstallEUR, m.updated_at,
      ).run();
      return result.meta.changes === 1;
    },
    async updateMember(code, key, f) {
      await one(
        `UPDATE members SET as_of = ?3, week_cost_eur = ?4, week_output_tokens = ?5, spend_since_install_eur = ?6, updated_at = ?7
         WHERE class_code = ?1 AND handle_key = ?2`,
        code, key, f.asOf, f.weekCostEUR, f.weekOutputTokens, f.spendSinceInstallEUR, f.updated_at,
      ).run();
    },
    async countMembers(code) { return (await one('SELECT COUNT(*) AS n FROM members WHERE class_code = ?1', code).first()).n; },
    async listMembers(code) {
      return (await one(
        'SELECT handle, as_of, week_cost_eur, week_output_tokens, spend_since_install_eur FROM members WHERE class_code = ?1', code,
      ).all()).results;
    },
    async deleteMember(code, key) { await one('DELETE FROM members WHERE class_code = ?1 AND handle_key = ?2', code, key).run(); },
    async deleteStale(code, cutoff) { await one('DELETE FROM members WHERE class_code = ?1 AND updated_at < ?2', code, cutoff).run(); },
  };
}

export default {
  async fetch(request, env) {
    const result = await handle(request, d1Store(env.DB));
    return new Response(result.body, { status: result.status, headers: result.headers });
  },
};
