# TokenBar class leaderboard server

A small Cloudflare Worker with a D1 table. It stores one row for each member of a class. The protocol, the limits and the privacy rules are in [docs/TRD.md](../docs/TRD.md) Section 17.

The server has no dependency. `wrangler` is the Cloudflare tool that deploys it. Run it with `npx`. Do not add it to the repository.

## Test the logic

The logic has no Cloudflare code. Run the tests with Node.js 20 or later:

```sh
node --test server/test/*.test.mjs
```

## Deploy

The maintainer does these steps one time, with a Cloudflare account. The free plan is enough for a class: a Worker has 100,000 requests each day. One member makes about 340 requests each day, so the free plan fits about 290 members.

1. Make the database. Copy the `database_id` from the output into `wrangler.toml`.

   ```sh
   cd server
   npx wrangler d1 create tokenbar-leaderboard
   ```

2. Make the table.

   ```sh
   npx wrangler d1 execute tokenbar-leaderboard --remote --file=schema.sql
   ```

3. Deploy. The output shows the Worker address, for example `https://tokenbar-leaderboard.<account>.workers.dev`.

   ```sh
   npx wrangler deploy
   ```

4. Check the server. This must print `404` and `{"error":"class not found"}`:

   ```sh
   curl -s -w ' %{http_code}\n' https://<your-address>/v1/classes/test-class-0001/board
   ```

5. Put the address in `Sources/TokenBar/Resources/leaderboard.json` (`endpoint`). This is the approval of the new network host (AGENTS 9, D62). The app sends nothing until the address is set.

## Delete the data

A member deletes the own row in TokenBar (Settings, **Leave class and delete my data**). To delete a whole class, run:

```sh
npx wrangler d1 execute tokenbar-leaderboard --remote --command "DELETE FROM members WHERE class_code = 'the-class-code'"
```
