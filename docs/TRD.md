# TokenBar Technical Requirements Document (TRD)

| Field | Value |
|---|---|
| Status | Draft 1 |
| Scope | v0.1 alpha to v1.0 |
| Date | 2026-10-08 |
| Related | [PRD](PRD.md), [DRD](DRD.md), [AGENTS.md](../AGENTS.md) |

**Writing standard.** This document uses ASD-STE100. Code identifiers, paths and JSON keys are verbatim. A claim marked **UNVERIFIED** has no confirmation from a primary source or from a file on a test Mac.

**Design rule.** This TRD follows the `ponytail` skill. Use the Swift standard library and Apple frameworks first. Do not add an abstraction until a second user of it exists. Each section names what it skips and when to add it.

## 1. Overview

TokenBar is a macOS menu bar app for Apple silicon. In v1, it reads LLM usage from local log files only. Admin API providers are Later (Sections 5.3 and 5.4). It calculates an API-equivalent cost in EUR. It converts the cost into café units and shows a roast.

Technical goals:

1. Read only token counts, model names, timestamps and limit percentages. Never keep prompt or response content.
2. Make no network request unless the user turns on the update check.
3. Show new usage in 60 seconds or less (PRD AC5).
4. Use less than 1% average CPU when idle (PRD NFR-04).
5. Keep the provider layer clean: one `UsageProvider` protocol and one adapter for each source.

## 2. Architecture

```
            ┌──────────────────────── TokenBar.app (one process) ────────────────────────┐
 ~/.claude/projects/**/*.jsonl ─┐                                                       │
 claude-limits.json ────────────┼─► ClaudeCodeProvider ─┐  UsageProvider                │
 ~/.codex/sessions/**/*.jsonl ──┴─► CodexProvider ──────┘  .fetch() async               │
                                              │                                         │
                                              ▼                                         │
                         UsageStore (@MainActor, @Observable, refresh loop)             │
                           │        │              │                                   │
                           ▼        ▼              ▼                                   │
                     CostEngine  CafeIndex     Roasts      ◄── prices.json, cafe-units.json,
                     (EUR cost)  (EUR units)   (selector)       roasts.json (bundle resources)
                           │        │              │                                   │
                           ▼        ▼              ▼                                   │
                  MenuBarLabel   PopoverView   LimitAlerts (UserNotifications)          │
            └────────────────────────────────────────────────────────────────────────────┘
 UpdateCheck.swift ──► HTTP.swift ──► api.github.com only (opt-in, v1.0)
 Later: AnthropicAdminProvider, OpenAIAdminProvider, Keychain.swift (Sections 5.3, 5.4)
```

Rules:

1. Providers return data only. Providers do not import SwiftUI or AppKit. They do not format text.
2. `UsageStore` owns the refresh loop and the provider list. Views read only from `UsageStore`.
3. Humor (café index and roasts) is data. Code selects and fills the strings. Code does not contain jokes.

**Why a protocol.** `ponytail` forbids an interface with one implementation. v0.2 has two local providers: Claude Code and Codex. Thus `UsageProvider` has two implementations. The protocol is justified. The Later API providers add more.

## 3. Repository layout

```
Package.swift                         one executableTarget "TokenBar", one testTarget
Sources/TokenBar/
  App/TokenBarApp.swift               @main App, MenuBarExtra, provider registration
  App/main.swift                      (v0.2, replaces @main) branches to --statusline mode
  App/StatuslineBridge.swift          (v0.2) writes Claude limit snapshot
  Core/Models.swift                   value types (Section 4)
  Core/UsageProvider.swift            protocol
  Core/UsageStore.swift               refresh loop, aggregation
  Core/JSONLTailReader.swift          incremental line reader
  Core/CostEngine.swift               tokens × price
  Core/HTTP.swift                     (v1.0) URLSession call, allowlist api.github.com only
  Core/UpdateCheck.swift              (v1.0) opt-in GitHub release check
  Core/Keychain.swift                 (Later) SecItem wrapper
  Providers/ClaudeCodeProvider.swift
  Providers/ClaudeCodeLimits.swift    (v0.2) reads the status line limit file
  Providers/CodexProvider.swift       (v0.2)
  Providers/AnthropicAdminProvider.swift   (Later)
  Providers/OpenAIAdminProvider.swift      (Later)
  Humor/CafeIndex.swift
  Humor/Roasts.swift
  Alerts/LimitAlerts.swift            (v0.2)
  UI/MenuBarLabel.swift
  UI/PopoverView.swift
  UI/SettingsView.swift               (v0.2)
  UI/ShareCard.swift                  (v0.2) share card image and text
  UI/APIKeysView.swift                (Later)
  Resources/prices.json
  Resources/cafe-units.json
  Resources/roasts.json
  Resources/water.json                (D41) water per output token, with source
Tests/TokenBarTests/
  *Tests.swift                        one file for each source file with logic
  Fixtures/claude/*.jsonl             synthetic data only
  Fixtures/codex/*.jsonl              synthetic data only
  Fixtures/api/*.json                 (Later) synthetic API responses
npm/package.json                      npm package "tokenbar" (TRD-T26)
npm/bin/tokenbar.js                   install and uninstall command, Node built-ins only
npm/test/*.test.js                    node --test
scripts/build-app.sh                  assembles TokenBar.app from the SwiftPM binary
scripts/make-dmg.sh                   (decide after the alpha, TRD-T11) hdiutil wrapper
.github/workflows/ci.yml              build and test on each pull request
.github/workflows/release.yml         arm64 build, app zip, GitHub Release, npm publish on tag
```

Skipped: a separate library target. Add `TokenBarCore` when the MCP server (Section 13) needs the providers in a second executable. The provider files have no UI imports, so the change is a file move.

## 4. Data model

Signatures only. Agents can add fields that an issue needs. Agents must not rename these types.

```swift
enum ProviderID: String, Codable, Sendable, CaseIterable { case claudeCode, codex }   // Later: anthropicAPI, openAIAPI

struct TokenCounts: Equatable, Sendable {           // all values are token counts
    var input = 0          // uncached input
    var output = 0         // includes reasoning or thinking tokens
    var cacheRead = 0
    var cacheWrite5m = 0
    var cacheWrite1h = 0
}

struct UsageRecord: Sendable {                       // one API response, or one API bucket
    let provider: ProviderID
    let model: String
    let timestamp: Date
    let tokens: TokenCounts
    // Later: reportedCostUSD: Decimal?, for admin API providers (Section 6, rule 1)
}

struct LimitWindow: Sendable {
    let name: String                                 // "5-hour", "weekly"
    let usedPercent: Double                          // 0...100
    let resetsAt: Date?
    let observedAt: Date                             // shown as "as of 14:02" (DRD 3.2)
}

struct ProviderSnapshot: Sendable {
    let provider: ProviderID
    let records: [UsageRecord]                       // window: last 35 days
    let limits: [LimitWindow]
    let updatedAt: Date
}

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(now: Date) async throws -> ProviderSnapshot
}
```

Providers keep their parse state (file offsets, deduplication keys) inside an `actor`. A thrown error goes to `UsageStore`, which keeps the last good snapshot and shows the error in the popover.

## 5. Provider specifications

### 5.1 Claude Code (local logs)

**Location.** `~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl` and `~/.claude/projects/<encoded-cwd>/<session-uuid>/subagents/agent-*.jsonl`. Scan `**/*.jsonl` under `~/.claude/projects`. If `CLAUDE_CONFIG_DIR` is set, use `$CLAUDE_CONFIG_DIR/projects` (CodexBar `docs/claude.md`; UNVERIFIED on this Mac). Ignore `*/vercel-plugin/*.jsonl` and other files without assistant lines; the parser skips them anyway.

**Format.** JSON Lines. One JSON object for each line. Verified on 2026-10-08 with Claude Code 2.1.284 to 2.1.290 (229 files, 380 MB). Top-level `type` values include `assistant`, `user`, `attachment`, `system`, `ai-title`, `last-prompt` and `file-history-snapshot`. Only `type == "assistant"` lines carry token usage. The `user`, `ai-title` and `last-prompt` lines hold prompt content. Never decode them.

| Field (JSON path) | Type | Use |
|---|---|---|
| `type` | string | Keep only `"assistant"`. |
| `timestamp` | string, ISO 8601 UTC with milliseconds | Record time. |
| `message.model` | string | Model ID, for example `claude-opus-5-5`. Skip `"<synthetic>"`. |
| `message.id` | string | Deduplication key, part 1. |
| `requestId` | string, sometimes absent | Deduplication key, part 2. |
| `message.usage.input_tokens` | int | Uncached input → `input`. |
| `message.usage.output_tokens` | int | → `output`. Includes thinking tokens. |
| `message.usage.cache_read_input_tokens` | int | → `cacheRead`. |
| `message.usage.cache_creation.ephemeral_5m_input_tokens` | int | → `cacheWrite5m`. |
| `message.usage.cache_creation.ephemeral_1h_input_tokens` | int | → `cacheWrite1h`. |
| `message.usage.cache_creation_input_tokens` | int | Sum of both cache writes. Use as `cacheWrite5m` only if `cache_creation` is absent. |
| `isApiErrorMessage` | bool, optional | Skip the line if `true`. |
| `isSidechain` | bool | Subagent line. Count it. Subagent usage is real usage. |

Other `message.usage` keys exist (`service_tier`, `speed`, `inference_geo`, `server_tool_use`, `iterations`, `output_tokens_details.thinking_tokens`). v0.1 ignores them. `message.content` holds prompt and response content. **Never decode `message.content`.** Decode into a `Decodable` struct that declares only the fields in the table. `JSONDecoder` then drops all other keys.

**Deduplication.** Claude Code writes one line for each content block of a response. Thus one response appears on many lines with the same `message.id` and `requestId`. On this Mac, 5,591 unique responses produced 11,827 assistant lines. In 50 cases the repeated lines had different usage values (streaming snapshots). Rule: key = `message.id + ":" + requestId` (or `message.id` alone if `requestId` is absent). The last line for a key replaces earlier lines. Keep keys across files, because resumed sessions can copy old lines (CodexBar `docs/claude.md`; UNVERIFIED here).

**Limits (5-hour and weekly).** The logs do not contain limit percentages. A `rateLimits` key appears only in `system` error lines, and its value was `null` in all samples. Do not estimate a percentage from tokens. Anthropic does not publish limits as token counts. A token-based estimate would be wrong and would break PRD-US-11 AC2.

Use the documented Claude Code status line input. The status line command receives JSON on stdin. For Pro and Max subscribers, it includes `rate_limits.five_hour.used_percentage`, `rate_limits.five_hour.resets_at`, `rate_limits.seven_day.used_percentage` and `rate_limits.seven_day.resets_at` (epoch seconds). Source: <https://code.claude.com/docs/en/statusline> ("Rate limit usage"). The object is present only after the first API response.

Bridge design (v0.2, issue TRD-T13). The bridge is an opt-in setup (PRD Q2). Without it, the Claude Code row shows tokens and cost only.

1. The user clicks **Connect** in Settings > General (D39). TokenBar reads `~/.claude/settings.json`. A missing file is an empty object. If the file is not a JSON object, TokenBar shows an error and changes nothing. Before the first change, TokenBar copies the file to `settings.json.tokenbar-backup`. It does not replace an existing backup. If a status line exists and it is not TokenBar's, TokenBar saves the full object to `~/Library/Application Support/TokenBar/statusline-previous.json`. TokenBar then sets `"statusLine": {"type": "command", "command": "'<path of the running binary>' --statusline"}`. It keeps the old `padding` and all other keys. It writes the file atomically. A status line is TokenBar's if its command contains `TokenBar` and `--statusline`. **Disconnect** puts back the saved status line, or removes the key if no status line was saved. Settings also shows the manual snippet (`~/Applications/TokenBar.app/Contents/MacOS/TokenBar --statusline`) with a **Copy** button.
2. In `--statusline` mode, the binary reads stdin. It decodes only `rate_limits`. It writes `{"five_hour":…,"seven_day":…,"observed_at":…}` atomically to `~/Library/Application Support/TokenBar/claude-limits.json`. It prints one short line, for example `TokenBar · 5h 62% · wk 24%`, and exits with code 0. It does not start the UI. Input without `rate_limits` writes nothing. Claude Code drops a window after its `resets_at` time, so the bridge keeps the old window from the file. The bridge ignores `rate_limits.spend_limit` (Claude apps gateway only).
3. Do not use `cat > file`. The full input contains `session_name`, an AI-generated title from the prompt, and paths. TokenBar must not store these.
4. Chaining. After the write, if `statusline-previous.json` has a `command`, the bridge runs it with `/bin/sh -c` and the same stdin. If the command exits with code 0 within 2 s and prints text, the bridge prints that text. Else the bridge prints its own line. Thus the user keeps a custom status line.
5. Settings > General shows the status: "Not connected", "Connected. Waiting for the next Claude Code reply." or "Connected · updated 3 min ago" (from `observed_at`). Open Claude Code sessions must restart to read the new setting.

Reliability: **high accuracy, possibly old.** The values come from Claude Code itself. They update only while Claude Code runs. If `now > resets_at`, show the window as reset (0%). Else show the last value with its age from `observed_at`, for example "as of 14:02" (DRD 3.8). TokenBar has no Stale state. Only an unreadable file is an error.

Rejected alternative: `GET https://api.anthropic.com/api/oauth/usage` with the OAuth token from the `Claude Code-credentials` Keychain item. CodexBar uses this path (`docs/claude.md`). The endpoint is not public. Reading the token of a different app causes Keychain prompts and ACL problems. CodexBar documents many failure modes for it. Revisit only if Anthropic documents the endpoint.

**Failure modes.** Directory absent → provider shows "Claude Code not found". Malformed line → skip the line, count it, continue. Partial last line (file in write) → keep the bytes until the next newline. File truncated or replaced (size < offset, or inode changed) → reparse that file. Unknown model → count tokens, cost is unknown (Section 6).

**Verification status.** Log fields: verified on this Mac. Status line `rate_limits`: verified in official docs on 2026-10-09 (TRD-T13). The bridge binary was tested with synthetic input, not yet with a live Claude Code session.

### 5.2 Codex CLI (local logs)

**Location.** `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl` and `~/.codex/archived_sessions/rollout-*.jsonl`. If `CODEX_HOME` is set, use `$CODEX_HOME` instead of `~/.codex` (CodexBar `docs/codex.md`; UNVERIFIED here). Verified on 2026-10-08: 315 files, 1.3 GB, 4 files larger than 50 MB.

**Format.** JSON Lines. Each line has `timestamp` (ISO 8601 UTC with milliseconds), `ordinal`, `type` and `payload`. Relevant lines:

| Line | Field (JSON path) | Use |
|---|---|---|
| `type == "turn_context"` | `payload.model` | Current model for later usage lines in the file. |
| `type == "token_usage_record"` | `payload.response_id` | Deduplication key. |
| same | `payload.usage.input_tokens`, `.cached_input_tokens`, `.cache_write_input_tokens`, `.output_tokens`, `.reasoning_output_tokens` | Tokens for one response. |
| `type == "event_msg"`, `payload.type == "token_count"` | `payload.info.last_token_usage.*` (same keys) | Tokens for one response, older files only. |
| same | `payload.rate_limits.primary` and `.secondary` → `used_percent`, `window_minutes`, `resets_at` (epoch s) | Limit windows. |
| same | `payload.rate_limits.plan_type`, `.limit_id` | Display only. |

Mapping: `input = input_tokens − cached_input_tokens`. `cacheRead = cached_input_tokens`. `cacheWrite5m = 0`: `cache_write_input_tokens` is 0 on every real line (verified 2026-10-08, 47,313 lines). `output = output_tokens`. `cached_input_tokens` is part of `input_tokens` and `reasoning_output_tokens` is part of `output_tokens` (verified on 47,313 real lines, 2026-10-08). Never decode `response_item` lines, `payload.base_instructions` or `payload.collaboration_mode.settings.developer_instructions`. They hold content.

Double count rule: if a file has any `token_usage_record` line, use only those lines for tokens. Else use `token_count` lines. Do not use `total_token_usage`. It is cumulative.

**Limits.** Codex writes its limits into the log. On this Mac every `token_count` line had `primary.window_minutes == 10080` (weekly), `secondary == null`, and `plan_type == "prolite"`. Name the window from `window_minutes`: 300 → "5-hour", 10080 → "weekly", other → "<n>-minute". Use the newest `token_count` line across all files. Reliability: **high accuracy, possibly old**, same rules as Section 5.1. `observedAt` is the `timestamp` of that line.

**Failure modes.** Same as Section 5.1. A file can grow by many MB during one session. The tail reader (Section 7) handles this.

**Verification status.** Verified on this Mac (Codex CLI with `codex-auto-review` and `gpt-6-sol` models). The format changes often. Keep fixtures for both the old (`token_count` only) and new (`token_usage_record`) shapes.

### 5.3 Anthropic Admin API (Later)

v1 reads only local files (PRD 7.4). Sections 5.3 and 5.4 stay as reference for the Later stage. Do not build them in v1. Their hosts are not in the v1 allowlist (Section 10).

| Item | Value |
|---|---|
| Usage | `GET https://api.anthropic.com/v1/organizations/usage_report/messages` |
| Cost | `GET https://api.anthropic.com/v1/organizations/cost_report` |
| Headers | `x-api-key: <admin key>`, `anthropic-version: 2023-06-01`, `User-Agent: TokenBar/<version>` |
| Key | Admin API key, prefix `sk-ant-admin01-`. Workspace API keys do not work. |
| Query | `starting_at`, `ending_at` (RFC 3339), `bucket_width` (`1d`, `1h`, `1m`; cost: `1d` only), `group_by[]=model` (usage), `group_by[]=description` (cost), `limit`, `page` |
| Usage fields | `data[].starting_at`, `data[].results[].model`, `.uncached_input_tokens`, `.cache_read_input_tokens`, `.cache_creation.ephemeral_5m_input_tokens`, `.cache_creation.ephemeral_1h_input_tokens`, `.output_tokens`; `has_more`, `next_page` |
| Cost fields | `data[].results[].amount` (decimal string in cents: `"123.45"` = $1.2345), `.currency` (`"USD"`), `.model`, `.token_type` |
| Freshness | Data appears in about 5 minutes. Poll a maximum of once a minute. |

Sources: <https://platform.claude.com/docs/en/manage-claude/usage-cost-api>, <https://platform.claude.com/docs/en/api/beta/organization/usage_report/retrieve_messages>, <https://platform.claude.com/docs/en/api/beta/organization/cost_report/retrieve>. Verified 2026-10-08.

**Important limit.** "The Admin API is unavailable for individual accounts." Only an organization in the Claude Console has admin keys. Most students do not have one. The PRD and the onboarding text must say this.

Refresh every 15 minutes, because data is about 5 minutes late. Request today and the current month only. Map one result to one `UsageRecord` with `timestamp = starting_at` and `reportedCostUSD` from the cost report.

Failure modes: 401/403 → "Key rejected. Use an admin key." 429 → wait for the next cycle. No network → keep the last snapshot and show its age.

### 5.4 OpenAI Admin API (Later)

| Item | Value |
|---|---|
| Usage | `GET https://api.openai.com/v1/organization/usage/completions` |
| Cost | `GET https://api.openai.com/v1/organization/costs` |
| Headers | `Authorization: Bearer <admin key>` |
| Key | Organization admin key from <https://platform.openai.com/settings/organization/admin-keys>. Project keys do not work. |
| Query | `start_time` (Unix s, required), `end_time`, `bucket_width` (`1m`, `1h`, `1d`; costs: `1d` only), `group_by` (for example `model`), `limit`, `page` |
| Usage fields | `input_tokens`, `input_cached_tokens`, `output_tokens`, `num_model_requests`, `model`; pagination cursor `next_page` |
| Cost fields | `amount.value`, `amount.currency`, `line_item`, `project_id` |

Source: <https://developers.openai.com/cookbook/examples/completions_usage_api>. The API reference page returned HTTP 403 to the verification fetch. Thus the response envelope keys (`data[].results[]`, `has_more`) are **UNVERIFIED**. Confirm them with a real admin key before TRD-T20 is done. Mapping: `input = input_tokens − input_cached_tokens` (UNVERIFIED that cached is a subset).

### 5.5 xAI (later)

Known: CodexBar reads a prepaid balance and daily spend from `https://management-api.x.ai/v1/billing/teams/{team_id}/prepaid/balance` and `POST …/billing/teams/{team_id}/usage` with a Management API key and team ID (CodexBar `docs/xai.md`). This is **UNVERIFIED** against xAI docs. It covers the developer platform only, not Grok consumer plans. No local Grok log source is known. Do not build an xAI provider until the maintainer approves the new host (AGENTS.md Section 9).

## 6. Cost engine

API-equivalent cost = Σ over token classes (tokens × price for that model and class) ÷ 1,000,000.

1. (Later) Use `reportedCostUSD` if an admin API provider supplies it. Do not calculate a second value. v1 has no such provider.
2. Else look up the model in `prices.json`. Try an exact `id` match first. Then try an `id` followed by a date suffix only, for example `claude-haiku-4-5-20251001` or `gpt-5.5-2026-04-23`. A different suffix is not a match. Thus `gpt-5.5-pro` does not get the `gpt-5.5` price.
3. If no match exists, the cost for that record is `nil`. The popover shows "price unknown" and the token count. Do not guess.
4. Use `Decimal` for money. Do not use `Double`.
5. A class with no price in the file costs 0. For example, OpenAI has no cache-write price.
6. Convert the USD result to EUR with `usd_to_eur` from `prices.json`. The UI does not show the EUR cost. It shows only the index that comes from it (D42).
7. A model can have a `long_context` price set with `above_tokens`. The prompt size is the sum of `input`, `cacheRead`, `cacheWrite5m` and `cacheWrite1h`. If the prompt size is more than `above_tokens`, all token classes of that record use the `long_context` prices. Examples: OpenAI above 272K input tokens, Claude Haiku 5.5 above 100K.

`Resources/prices.json` (values below are **EXAMPLE values, not real prices**):

```json
{
  "last_verified": "2026-10-08",
  "unit": "USD per 1M tokens",
  "usd_to_eur": 0.90,
  "fx_updated": "2026-10-08",
  "fx_note": "community estimate — verify",
  "models": [
    { "id": "claude-example-model", "input": 1.00, "output": 5.00,
      "cache_read": 0.10, "cache_write_5m": 1.25, "cache_write_1h": 2.00,
      "source": "https://platform.claude.com/docs/en/about-claude/pricing" }
  ]
}
```

Rules for contributors: update `last_verified` and `source` with each price change. A test fails if `last_verified` is missing or if a model has no `source`. The popover footer shows "Prices verified <date>".

Currency (PRD Q3): EUR everywhere. Providers publish prices in USD. `prices.json` has one fixed `usd_to_eur` rate, its `fx_updated` date and `fx_note`. The rate is a community estimate. A test fails if the rate is missing, ≤ 0, or has no date. No currency setting exists. The café index and the tuition benchmark use EUR prices directly. Skipped: a live exchange-rate source. It needs a new host.

## 7. Refresh and performance

**Decision: polling, not file events.** A timer runs every 60 seconds (decided 2026-10-08). No refresh setting exists. Low Power Mode does not change the interval. Each tick does a `stat` of each candidate file and reads only new bytes. The popover Refresh button runs a tick at once.

Reasons:

1. 60 seconds meets the 60-second target (PRD-US-02 AC5) for most updates. The timer tolerance can add up to 10 seconds.
2. FSEvents on `~/.claude` fires for many files that TokenBar does not use (history, cache, file-history). It adds a C API wrapper and a second code path.
3. One `stat` for each of about 550 files every 60 seconds costs almost nothing.

Skipped: FSEvents (`FSEventStreamCreate`). Add it if measured CPU or latency fails the targets.

Energy rules:

1. Use a tolerant timer: `Task.sleep` with a tolerance in one loop, or a `Timer` with `tolerance = 10 s`. macOS can then coalesce wakeups.
2. Run parsing off the main actor. Send only the new `ProviderSnapshot` to the main actor.

**Incremental parsing (`JSONLTailReader`).** Keep a state for each file: device and inode, size, byte offset, and a buffer for a partial line.

1. If inode or device changed, or size < offset: reset the offset to 0. Drop that file's records.
2. If size == offset: skip the file.
3. Else read from the offset to the end with `FileHandle`. Split on `\n`. Keep the bytes after the last `\n` as the partial line.
4. Before decoding, test the raw line for a marker (`"type":"assistant"` for Claude; `token_usage_record`, `token_count` or `turn_context` for Codex). Skip all other lines without decoding. This skips most bytes.

**Startup window.** On launch, scan only files whose modification date is in the last 35 days. This covers "this month" and the weekly window. Keep records in memory only. Skipped: an on-disk cache. Add it if a cold scan takes more than 3 seconds on a 1.5 GB log set. Measure this in TRD-T05 and TRD-T12.

**Day boundaries.** "Today" starts at local midnight in `Calendar.current`. "Week" is the rolling last 7 days: `now − 7 × 24 h` to `now` (PRD Section 1).

## 8. Menu bar and the notch

Problem: on a Mac with a notch, macOS hides status items that do not fit to the right of the notch. macOS does not tell the user (DRD 2.3).

Mitigation:

1. Use one display mode: Compact, max 52 pt, on all displays (DRD 2.2). TokenBar does not detect the notch. Do not use `NSScreen.auxiliaryTopLeftArea`.
2. Fix the label width. Use `.monospacedDigit()`. Reserve space for the longest value, for example `100%`. The width must not change on each update. A width change makes macOS move other items.
3. Draw one template icon and the value in one fixed-width template `NSImage` (`MenuBarLabel`). The icon is an SF Symbol or a custom index icon (DRD 8.3).
4. In first run and in Settings, tell the user: hold Command and drag the TokenBar icon to the right, next to the clock. Items near the clock are hidden last.

Skipped: detection of the hidden state. `MenuBarExtra` does not expose its `NSStatusItem`. A check of the status item window frame against the notch area is possible but fragile (UNVERIFIED). Add it if alpha users report a hidden icon.

## 9. Humor data files

All humor files are JSON in `Sources/TokenBar/Resources/`. SwiftPM processes them with `resources: [.process("Resources")]`. Load them with `Bundle.tokenBar` (`Core/ResourceBundle.swift`), not `Bundle.module` (D34). The DRD owns the fields and the voice. The TRD owns the file format and path. The custom index icons are SVG files in `Resources/Icons` (DRD 8.3, D43). SwiftPM copies them to the root of the resource bundle, so load them without a subdirectory.

| File | Top-level keys | Item fields |
|---|---|---|
| `cafe-units.json` | `units`, `tuition` | Units, DRD 7.6: `id`, `singular`, `plural`, `emoji`, `price_eur`, `price_note`, `source`, `updated`. `tuition` is one object, not a unit: `id` (`iese_mba_tuition`), `label`, `price_eur`, `source`, `updated`. The UI shows `label`. Code has no hardcoded school name. |
| `roasts.json` | `roasts` | DRD 7.2: `id`, `text`, `category`, `min_percent`, `max_percent`, `hours`, `weekdays`, `provider`, `locale` |
| `water.json` | `ml_per_output_token`, `basis`, `source`, `source_note`, `last_verified`, `units` | DRD 7.8. Units: `id`, `singular`, `plural`, `ml`. A test fails if the factor or a unit size is ≤ 0. |

Load rules:

1. Decode with `Codable`. Reject the whole file if decoding fails. A unit test decodes the shipped files, so a bad pull request fails CI.
2. A test checks that each `id` is unique and that each `price_eur` is > 0.
3. A test checks that each roast placeholder is in the DRD list (`{percent}`, `{remaining}`, `{model}`, `{provider}`, `{reset}`, `{time}`, `{cost}`, `{unit_value}`, `{unit_plural}`, `{tuition_percent}`, `{tuition_years}`).
4. Store the roast rotation history (DRD 7.4) in `UserDefaults` as a list of the last 10 IDs. Keep the time of the last roast change in memory.
5. Store the tuition running total in `UserDefaults`: `tuitionFirstLaunch` (date), `tuitionSpendEUR` (`Decimal` as a string) and `tuitionCountedThrough` (date). These values are not secrets.
6. On each refresh, add the cost of each complete day after `tuitionCountedThrough` and before today. Then set `tuitionCountedThrough` to yesterday.
7. Spend since first launch = `tuitionSpendEUR` + the cost of today. Do not store the cost of today. A day older than the 35-day window is not counted.

Skipped: loading user-supplied data files from disk. Add it if contributors ask to test units without a build.

## 10. Security and privacy

| Requirement | Implementation | Check |
|---|---|---|
| Local only | No server. No analytics SDK. No crash reporter. | Code review. `grep` in CI for `URLSession` outside `Core/HTTP.swift`. |
| No prompt content | Decodable structs declare only the fields in Section 5. | Fixture test: content contains `SECRET-MARKER`; assert no record, log or file contains it. |
| Keys in Keychain (Later) | v1 has no API keys. When they come back: `SecItemAdd`/`SecItemCopyMatching`, `kSecClassGenericPassword`, service = bundle ID, account = `ProviderID.rawValue`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. | Unit test with a test-only service name. |
| No keys in files (Later) | Never write a key to `UserDefaults`, a file or a log. Do not print a key in an error. | Code review. |
| Host allowlist | `HTTP.swift` has one function. In v1, it rejects any host that is not `api.github.com`. | Unit test. |
| Read-only on other apps' files | Open `~/.claude` and `~/.codex` files read-only. Never write there. | Code review. |
| Logs | Use `os.Logger` with `privacy: .private` for paths and model names. Log counts, not values. | Code review. |

Network hosts:

| Host | When | Data sent |
|---|---|---|
| `api.github.com` | Update check turned on (opt-in, off by default, PRD-US-20) | Nothing except the request itself |
| `api.anthropic.com` | Later only: Anthropic admin key added | Admin key, date range |
| `api.openai.com` | Later only: OpenAI admin key added | Admin key, date range |

v1 allows only `api.github.com`. The Later hosts need maintainer approval when API keys come back.

A new host needs maintainer approval (AGENTS.md Section 9).

## 11. Permissions and sandbox decision

**Decision: no App Sandbox. Ad-hoc signature. Distribution outside the Mac App Store: npm for the alpha. DMG and Homebrew formula: decide after the alpha. See Section 13.**

Analysis:

1. A sandboxed app cannot read `~/.claude` or `~/.codex`. A sandboxed app can read them only after the user selects the folder in an `NSOpenPanel` and the app stores a security-scoped bookmark.
2. These folders are hidden. A non-engineer cannot easily select a hidden folder. This breaks the 2-minute onboarding target (PRD-US-18).
3. The App Sandbox is required only for the Mac App Store. TokenBar ships with npm, and possibly a Homebrew formula and a DMG after the alpha.
4. A signed build is "Later, optional" (Section 13). If it starts, notarization requires Hardened Runtime, not the sandbox.
5. CodexBar ships non-sandboxed for the same reason (`docs/sparkle.md`).

Consequences:

1. No entitlements file is needed. Do not add `com.apple.security.*` entitlements without approval.
2. macOS TCC does not protect `~/.claude` or `~/.codex`. TokenBar needs no Full Disk Access. Do not ask for it.
3. Notifications need user permission. Ask on the first alert setup (v0.2), not at launch.
4. `UNUserNotificationCenter` needs a real app bundle with a bundle ID. It fails in a bare `swift run` binary (UNVERIFIED for macOS 14+; test in TRD-T15).

Revisit if the maintainer wants the Mac App Store.

## 12. Testing strategy

1. Use Swift Testing (`import Testing`, `@Test`, `#expect`). Run `swift test`.
2. **Use synthetic fixtures only.** Never copy a line from a real user log into the repository. Write fixture lines by hand. Use `"<redacted>"` or `SECRET-MARKER` in content fields.
3. Each parser test file covers these cases: a normal line, a repeated line with the same key, a changed usage for the same key, a malformed line, a partial last line, a truncated file, an unknown model.
4. `JSONLTailReader` tests write to a temporary file in steps: append, append a partial line, finish the line, truncate.
5. `CostEngine` tests use a fixture price file, not the shipped one. Check prefix matching, unknown models and `Decimal` rounding.
6. Data file tests decode the shipped `prices.json`, `cafe-units.json`, `roasts.json` and `water.json` (Section 9).
7. `HTTP.swift` and `UpdateCheck.swift` tests use `URLProtocol` stubs with fixture JSON. No test calls a real API. (Later: API provider tests use the same stubs.)
8. Inject `now: Date` into each provider and the store. Do not call `Date()` in logic.
9. UI: no snapshot tests in v0.1. Test the label text function (state → string) as a pure function.
10. Performance check (manual, TRD-T05 and TRD-T12): cold scan time on the maintainer's Mac and idle CPU in Activity Monitor. Record both in the pull request.

## 13. Build and release pipeline

**CI (`ci.yml`).** On each pull request: `macos-15` runner, select Xcode with Swift 6 (`sudo xcode-select -s /Applications/Xcode_<version>.app`; exact version UNVERIFIED on the runner image), `swift build`, `swift test`. No third-party actions except `actions/checkout`.

**Distribution decision (2026-10-08, PRD Q4).** TokenBar v0.x has no Developer ID and no notarization. TokenBar does not join the Apple Developer Program ($99 each year).

**Alpha channel and hardware (decided 2026-10-08).** The alpha ships on npm only. The maintainer decides on the DMG and the Homebrew formula after the alpha (TRD-T11, v1.0 stage). TokenBar builds for Apple silicon (arm64) only. No Intel or universal build. The minimum is macOS 14.

| Channel | Command | Stage | First launch |
|---|---|---|---|
| npm | `npm install -g tokenbar`, then `tokenbar install` | Alpha and v1.0 | No Gatekeeper prompt (facts 1 to 3) |
| Homebrew formula | `brew install patronofalltrades/tap/tokenbar` | Decide after the alpha | No Gatekeeper prompt. The formula builds from source. |
| DMG | Download from GitHub Releases | Decide after the alpha | Gatekeeper blocks the app. The user clicks **Open Anyway**. |

Facts for this decision (checked 2026-10-08):

1. Gatekeeper checks a downloaded app at first launch only if the app has the `com.apple.quarantine` extended attribute. The attribute is opt-in. An app adds it to new files only if its `Info.plist` sets `LSFileQuarantineEnabled`. Command-line tools such as `curl` do not add it. Sources: [Eclectic Light](https://eclecticlight.co/2020/10/29/quarantine-and-the-quarantine-flag/), [Red Canary](https://redcanary.com/threat-detection-report/techniques/gatekeeper-bypass/).
2. Local test on the maintainer's Mac (macOS 26, npm 11.19.1): files that `node` and `curl` wrote had no `com.apple.quarantine`. The global `node_modules` folder had no `com.apple.quarantine` on any file. Files had `com.apple.provenance`. This attribute does not start the first-launch prompt (UNVERIFIED by an Apple source; confirm in TRD-T26).
3. Exception: a process can inherit quarantine flags from a parent app that sets `LSFileQuarantineEnabled`. Then the kernel adds the attribute to each file that the process makes. Source: [nubjs/nub PR 601](https://github.com/nubjs/nub/pull/601). Thus `tokenbar install` must check for the attribute (see the npm package below).
4. Apple silicon runs only signed code. An ad-hoc signature is sufficient. The linker adds an ad-hoc signature to the executable, but this signature does not cover resources. An ad-hoc signature does not pass Gatekeeper. Source: [macOS Big Sur 11.0.1 Universal Apps Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes).
5. Homebrew casks add `com.apple.quarantine` to each download. Homebrew 5.0.0 deprecated `--no-quarantine`. Homebrew 7.0.4 has no `--no-quarantine` code. Sources: [Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/), `Library/Homebrew/cask/download.rb` in Homebrew 7.0.4. Thus a cask for an unsigned app always needs **Open Anyway**. TokenBar has no cask.

**Release (`release.yml`).** On a tag `v*`:

1. `swift build -c release --arch arm64`. The arm64 binary is in `.build/arm64-apple-macosx/release/TokenBar` (path UNVERIFIED; check `--show-bin-path`).
2. `scripts/build-app.sh` makes `TokenBar.app/Contents/{MacOS,Resources,Info.plist}`. The `Info.plist` sets `LSUIElement` to true. It copies the SwiftPM resource bundle into `Contents/Resources`. The generated `Bundle.module` does not look in `Contents/Resources`: it checks the `.app` root and the build folder only (verified 2026-10-08, Swift 6.3.3). App code must load resources with `Bundle.tokenBar` (`Core/ResourceBundle.swift`), which checks `Contents/Resources` first. Do not call `Bundle.module` directly.
3. Ad-hoc sign the bundle with `codesign --force --sign - TokenBar.app`. This signature seals `Info.plist` and the resources (fact 4). Do not use `--deep`, because the bundle has one executable.
4. Verify the signature with `codesign --verify --strict --verbose=2 TokenBar.app`.
5. `scripts/build-app.sh` makes `TokenBar.zip` in the repository root. The publish step copies it to `npm/TokenBar.zip`.
6. Write `SHA256SUMS` with `shasum -a 256` for `TokenBar.zip`.
7. Upload `TokenBar.zip` and `SHA256SUMS` to a GitHub Release with `gh release create`. Put the SHA-256 values in the release notes.
8. Publish the npm package (see "npm publish" below).
9. Only if the maintainer approves a DMG after the alpha (TRD-T11): run `scripts/make-dmg.sh` (`hdiutil create -volname TokenBar -srcfolder TokenBar.app -format UDZO TokenBar-<version>.dmg`). Add the DMG to `SHA256SUMS` and to the release.

**npm package (`npm/`, TRD-T26).**

- `npm/package.json`: `"name": "tokenbar"`, `"bin": {"tokenbar": "bin/tokenbar.js"}`, `"os": ["darwin"]`, `"cpu": ["arm64"]`, `"engines": {"node": ">=18"}`, a `files` list and a `repository` URL. The `repository` URL must match the GitHub repository exactly, with the same case. Provenance needs this match.
- The package has no dependencies. `bin/tokenbar.js` uses only Node built-in modules.
- The package has no `preinstall`, `install` or `postinstall` script. pnpm 10 does not run dependency lifecycle scripts by default, and `--ignore-scripts` stops them ([pnpm 10.0.0](https://newreleases.io/project/npm/pnpm/release/10.0.0)). npm also advises against install scripts ([npm scripts](https://docs.npmjs.com/cli/v11/using-npm/scripts)).
- Decision: the package contains the prebuilt arm64 app as `TokenBar.zip`. The command does not download the app from GitHub Releases. Reasons: no new network host, no download code, and the npm provenance covers the app bytes. A zip made with `ditto` keeps the bundle structure, file modes and signature files.
- Updates: `npm update -g tokenbar`, then `tokenbar install`.

`tokenbar install` does these steps:

1. Stop with an error if the Mac is not macOS 14 or later, or if `process.arch` is not `arm64`. The message tells the user that TokenBar needs Apple silicon.
2. Quit TokenBar if it runs.
3. Extract `TokenBar.zip` into a temporary folder with `/usr/bin/ditto -x -k`.
4. Run `codesign --verify --strict` on the extracted app. Stop if it fails.
5. Replace `~/Applications/TokenBar.app` with the extracted app. Make `~/Applications` if it does not exist.
6. Check the app for `com.apple.quarantine` with `xattr -p`. If the attribute exists, show the **Open Anyway** steps. Do not remove the attribute.
7. Open the app with `open ~/Applications/TokenBar.app`.

`tokenbar uninstall` quits TokenBar and removes `~/Applications/TokenBar.app`. It does not remove settings. It shows the user where they are.

`npx tokenbar install` must also work. It uses the same steps.

**npm publish (supply-chain controls).**

1. Turn on two-factor authentication for the npm account.
2. Publish only from `release.yml` on a GitHub-hosted runner. Never publish from a laptop.
3. Use npm trusted publishing (OIDC). It needs npm CLI 11.5.1 or later, Node 22.14.0 or later, `permissions: id-token: write` and a GitHub-hosted runner. Source: [npm trusted publishers](https://docs.npmjs.com/trusted-publishers).
4. Run `npm publish --provenance --access public`. Trusted publishing makes provenance by default, but keep the flag as an explicit check. Source: [npm provenance](https://docs.npmjs.com/generating-provenance-statements).
5. After the first trusted publish, set the package to "Require two-factor authentication and disallow tokens".
6. Do not store an npm token in GitHub secrets.

UNVERIFIED: npm can need an existing package before you add a trusted publisher. If so, ask the maintainer. Do not publish from a laptop to make the package.

**Homebrew formula (TRD-T11, decide after the alpha).** Build this only if the maintainer approves it after the alpha. Formula `Formula/tokenbar.rb` in `patronofalltrades/homebrew-tap`:

- `url`: the GitHub source tarball of the tag. Add its `sha256`.
- `depends_on arch: :arm64`, `depends_on macos: :sonoma` and `uses_from_macos "swift" => :build`. Homebrew core Swift formulae (for example `swiftformat`) use this line and need no full Xcode.
- `install`: `system "swift", "build", *std_swift_args`. Then run `scripts/build-app.sh` and `codesign --force --sign -`. Then `prefix.install "TokenBar.app"`.
- `caveats`: tell the user to copy the app with `cp -R "$(brew --prefix)/opt/tokenbar/TokenBar.app" ~/Applications/`.

Formula limits:

1. The Homebrew 7 sandbox blocks reads of the home folder ([Homebrew 7.0.0](https://brew.sh/2026/09/13/homebrew-7.0.0/)). Thus the formula cannot write to `~/Applications`. The user copies the app after each install and each `brew upgrade`.
2. Homebrew 6 and later require the user to trust a third-party tap before Homebrew runs its code ([Homebrew 6.0.0](https://brew.sh/2026/06/11/homebrew-6.0.0/)). The README must show `brew trust --tap patronofalltrades/tap` before the install command. Homebrew 7.0.4 `cmd/trust.rb` accepts this syntax.
3. The tap has no bottles. Each install builds from source and needs Command Line Tools with Swift 6.
4. A SwiftUI build with only Command Line Tools is UNVERIFIED. Test it on a Mac with no Xcode in TRD-T11.
5. Homebrew core does not accept a formula whose main output is a `.app` bundle ([Acceptable Formulae](https://docs.brew.sh/Acceptable-Formulae)). The formula stays in the personal tap.

Update the formula by hand for alpha. Skipped: automatic tap updates; they need a cross-repo token.

**Signed build (Later, optional).** Do this only if non-technical users become a target after the alpha. It needs the Apple Developer Program and maintainer approval.

1. Import the Developer ID Application certificate from GitHub secrets into a temporary keychain (`security create-keychain`, `security import`).
2. `codesign --force --options runtime --timestamp --sign "Developer ID Application: …" TokenBar.app`.
3. Sign the DMG. Then `xcrun notarytool submit TokenBar.dmg --key <p8> --key-id <id> --issuer <uuid> --wait`.
4. `xcrun stapler staple TokenBar.dmg`.
5. Store secrets only in GitHub Actions secrets. Changes to this workflow need approval (AGENTS.md Section 9).

**Auto-update decision: no Sparkle.** Sparkle needs a dependency, an EdDSA key, an appcast and a signed build. CodexBar disables Sparkle for unsigned and Homebrew builds anyway (`docs/sparkle.md`). TokenBar uses:

1. npm users: `npm update -g tokenbar`, then `tokenbar install`.
2. Homebrew users (only if the formula ships): `brew upgrade`, then copy the app again (formula limit 1).
3. Users who turn on the update check (v1.0, TRD-T23, off by default): one check each day at most. `GET https://api.github.com/repos/patronofalltrades/TokenBar/releases/latest`. Compare `tag_name` with `CFBundleShortVersionString`. If newer, show "Update available" in the popover footer with a link to the release page. No download, no install.

Add Sparkle only if users fail to update and the build is signed.

**Future seams (do not build now).**

- MCP server: a later `--mcp` mode in `App/main.swift` can reuse the providers and `CostEngine`, because they have no UI imports. It must expose totals only, never records with paths. Skipped until the roadmap item starts.
- Class leaderboard: needs a backend. This breaks "no data leaves the Mac". It needs an explicit opt-in, a pseudonym, daily totals only (no model, project or path), and a deletion path. Out of scope for v1.0.

## 14. Work breakdown

Rules: one issue = one branch = one pull request. "Owns" lists the files the issue creates. Shared edits are named. Every issue must meet AGENTS.md Section 7. Provider registration is a one-line shared edit in `App/TokenBarApp.swift`. [WORKFLOW.md](WORKFLOW.md) shows which agent owns each task.

Stages (PRD Section 10): v0.1 alpha in early November 2026, v0.2 alpha in mid-December 2026, v1.0 in January 2027. The v0.3 beta stage is removed. Its tasks moved to v1.0 or Later.

### v0.1 alpha (early November 2026)

| ID | Title | Depends on | Owns | Acceptance criteria |
|---|---|---|---|---|
| TRD-T01 | Package skeleton and menu bar shell | — | `Package.swift`, `App/TokenBarApp.swift`, `.github/workflows/ci.yml` | `swift build` and `swift test` pass in CI. App shows a `MenuBarExtra` with placeholder text. No Dock icon: the app sets the `.accessory` activation policy, because a SwiftPM binary has no `Info.plist`. T10 writes `LSUIElement` into the bundle `Info.plist`. |
| TRD-T02 | Core models and `UsageProvider` protocol | T01 | `Core/Models.swift`, `Core/UsageProvider.swift` | Types match Section 4. Compiles with Swift 6 strict concurrency. |
| TRD-T03 | Incremental JSONL tail reader | T01 | `Core/JSONLTailReader.swift`, tests | Handles append, partial line, truncation, inode change (Section 7). Tests pass. |
| TRD-T04 | Price table and cost engine | T02 | `Core/CostEngine.swift`, `Resources/prices.json`, tests | Section 6 rules 2–6. Data file test. Real prices with `source` URLs for current Claude models. `usd_to_eur` rate with `fx_updated` and `fx_note`. Costs returned in EUR. |
| TRD-T05 | Claude Code provider (tokens) | T02, T03 | `Providers/ClaudeCodeProvider.swift`, `Fixtures/claude/*`, tests | Section 5.1 fields and deduplication. `SECRET-MARKER` test passes. Cold scan time recorded. |
| TRD-T06 | Café index data and converter | T01 | `Humor/CafeIndex.swift`, `Resources/cafe-units.json`, tests | DRD 7.6 unit selection rules 1–7: one unit, no preferred unit. Units: café con leche, pa amb tomàquet, Bar Tomàs patatas bravas, menú del día. Data file test. The data file has the `iese_mba_tuition` entry with `price_eur` > 0. Calculates `{tuition_percent}` and `{tuition_years}` (DRD 7.6). No `{tuition_years}` with less than 7 days of data. Running total in `UserDefaults` (Section 9, rules 5–7), tested with a test-only suite. |
| TRD-T07 | Usage store and refresh loop | T02 | `Core/UsageStore.swift`, tests | 60 s loop with a tolerant timer. No refresh setting. No Low Power interval. Keeps the last snapshot on error. Today from local midnight, Week as the rolling last 7 days. Tested with a stub provider. |
| TRD-T08 | Menu bar label | T06, T07 | `UI/MenuBarLabel.swift`, tests | DRD 2.1–2.5. Compact mode only, max 52 pt (68 pt for the Tuition Meter, D41), fixed width. No notch detection. Primary metric always Auto. States: Normal, Warning, Limit hit, No data, Error. No Stale state. One index: Café Index, Tuition Meter or Water Footprint (D41). The first run asks for the index, with no default (DRD 4.5). All indexes show the limit value in Warning and Limit hit. Label text function tested for each index. |
| TRD-T09 | Popover view | T04, T06, T07, T14 | `UI/PopoverView.swift` | DRD Section 3 layout. Index headline for the selected index only, with one small second line (D41, D42). No EUR. Limit age "as of 14:02". Shows "Some models not counted", last update time, prices verified date, roast line. Error state **Report a problem** opens the Tally form URL. |
| TRD-T10 | App bundle and release workflow (ad-hoc signed, arm64) | T01 | `scripts/build-app.sh`, `.github/workflows/release.yml` | A tag produces an arm64 `TokenBar.zip` for npm and `SHA256SUMS` on GitHub Releases (Section 13). No DMG. The bundle has an ad-hoc signature (`codesign --force --sign -`). `codesign --verify --strict` passes. The app from the zip launches. `Bundle.module` loads resources. |
| TRD-T26 | npm package and `tokenbar install` command | T10 | `npm/package.json`, `npm/bin/tokenbar.js`, `npm/test/*.test.js` (`node --test`); shared edit: `.github/workflows/release.yml` (publish job) | Section 13 "npm package" and "npm publish". Contains the arm64 app. `"cpu": ["arm64"]`. `tokenbar install` stops on Intel and below macOS 14. No lifecycle scripts. Publish with provenance from GitHub Actions only. `npm i -g` and `npx` work. Install and uninstall tested on a clean user account. App launches with no Gatekeeper prompt. |
| TRD-T14 | Roast data and selector | T01 | `Humor/Roasts.swift`, `Resources/roasts.json`, tests | DRD 7.2–7.5. Select from the roasts that match the state. `limit` priority. No category weights. No repeat in the last 10. Maximum one change in 10 minutes. Change on state change. Placeholder test. Deterministic with injected random source. All roasts approved by the maintainer. No "IESE" in roast text. |

### v0.2 alpha (mid-December 2026)

| ID | Title | Depends on | Owns | Acceptance criteria |
|---|---|---|---|---|
| TRD-T12 | Codex provider (tokens and limits) | T02, T03 | `Providers/CodexProvider.swift`, `Fixtures/codex/*`, tests | Section 5.2. Both log shapes. No double count. Weekly limit from newest line, with `observedAt`. |
| TRD-T13 | Claude limit bridge (status line, opt-in) | T05 | `App/main.swift`, `App/StatuslineBridge.swift`, `Providers/ClaudeCodeLimits.swift`, tests; shared edit: remove `@main` in `App/TokenBarApp.swift` | Section 5.1 bridge steps 1–5. Opt-in setup. Writes only `rate_limits`. Reset rule tested. Old values show their age, no Stale state. Without the setup, Claude Code shows tokens and cost only. |
| TRD-T15 | Limit alerts | T07 | `Alerts/LimitAlerts.swift`, tests | Two events only: 95% and limit hit (DRD 6.1). No 80% and no reset notification. One alert for each event in each window (PRD-US-12). DRD 6.2 rate limits. No quiet hours. Roast in the body only when an index is selected and Roasts is on. Permission asked on first setup. |
| TRD-T16 | Settings window | T07 | `UI/SettingsView.swift` | DRD Section 5: 3 tabs (General, Alerts, About). General: Index picker (3 values), Roasts toggle, Launch at login (on after onboarding, `SMAppService`), Claude limits **Connect** and **Disconnect** with status, and the manual snippet with a Copy button (D39), Command-drag tip. Alerts: 95% and limit hit toggles. About: **Send feedback** opens the Tally form. No refresh, currency, display mode, menu bar metric, unit or quiet-hours setting. English only, String Catalog. |
| TRD-T27 | Share card | T06, T09, T14 | `UI/ShareCard.swift`, tests; shared edit: **Share** button in `UI/PopoverView.swift` footer | DRD 7.7 rules 1–7. Render with SwiftUI `ImageRenderer`. No dependency. Copy the image and the text to the clipboard. Card has no user name, paths, project names or prompt content. Model name only if the roast uses `{model}`. Selected index only. No index yet: numbers only. Card text function tested, including a `SECRET-MARKER` test. No network request. |
| TRD-T31 | One index: Café Index, Tuition Meter or Water Footprint | T08, T09, T16, T27, T28 | `Core/SettingsKey.swift`, `Humor/WaterFootprint.swift`, `Resources/water.json`, UI files, tests | D41. One picker with 3 values. Migrates `barStyle` one time: funny to café, serious to no choice. Tuition Meter as percent of tuition since install (DRD 7.6 rules 1 and 5). Water Footprint from output tokens (DRD 7.8). Width test for the longest values: 52 pt, and 68 pt for the Tuition Meter (D41). |

### v1.0 (January 2027)

| ID | Title | Depends on | Owns | Acceptance criteria |
|---|---|---|---|---|
| TRD-T18 | HTTP client with host allowlist | T01 | `Core/HTTP.swift`, tests | Allowlist has only `api.github.com`. Rejects other hosts. CI `grep` check for `URLSession` outside this file. |
| TRD-T23 | Opt-in update check | T18 | `Core/UpdateCheck.swift`, tests | Off by default. One request a day at most. Version compare tested. |
| TRD-T28 | First-run onboarding | T08, T09, T16 | `UI/OnboardingView.swift`, tests | PRD-US-18 and DRD Section 4. Detects Claude Code and Codex logs. States what TokenBar cannot see (web chat). Includes the index choice from T08 (D41). Turns on launch at login. The onboarding test with 5 target users passes (PRD-US-18 AC3). |
| TRD-T11 | DMG and Homebrew formula (decide after the alpha) | T10 | `scripts/make-dmg.sh`; `Formula/tokenbar.rb` in the tap repository | Start only if the maintainer approves after the alpha. DMG: Section 13 release step 9. Formula: Section 13 "Homebrew formula", arm64 only. `brew install patronofalltrades/tap/tokenbar` builds and installs. Build tested on a Mac with only Command Line Tools. The copied app launches with no Gatekeeper prompt. |

### Later

| ID | Title | Depends on | Owns | Acceptance criteria |
|---|---|---|---|---|
| TRD-T17 | Keychain wrapper (Later) | T01 | `Core/Keychain.swift`, tests | Save, read, delete. Section 10 attributes. |
| TRD-T19 | Anthropic Admin provider (Later) | T02, T17, T18 | `Providers/AnthropicAdminProvider.swift`, `Fixtures/api/anthropic-*.json`, tests | Section 5.3. Pagination. Cents to dollars. 15-minute interval. Needs approval to add `api.anthropic.com` to the allowlist. |
| TRD-T20 | OpenAI Admin provider (Later) | T02, T17, T18 | `Providers/OpenAIAdminProvider.swift`, `Fixtures/api/openai-*.json`, tests | Section 5.4. Envelope keys confirmed with a real key and noted in this TRD. Needs approval to add `api.openai.com` to the allowlist. |
| TRD-T21 | API key screen (Later) | T16, T17 | `UI/APIKeysView.swift` | DRD 4.3: secure field, Test button, admin-key note. Adds an API keys tab to Settings. |
| TRD-T22 | Signing and notarization (Later, optional) | T10 | shared edit: `.github/workflows/release.yml` | Start only if non-technical users become a target after the alpha (PRD Q4). Notarized, stapled DMG opens with no Gatekeeper warning. Needs approval. |
| TRD-T24 | Cask for signed build (Later, optional) | T22 | `Casks/tokenbar.rb` in the tap repository | Start only after T22. Cask points to the notarized DMG. |
| TRD-T25 | Cancelled 2026-10-08 (plan mode cut, PRD Q1) | — | — | — |

Parallel waves: Wave 1: T01. Wave 2: T02, T03, T06, T10, T14. Wave 3: T04, T05, T07, T12, T26. Wave 4: T08, T09, T13, T15, T16. Wave 5: T27. Wave 6 (v1.0): T18, then T23; T28. After the alpha, only if approved: T11. Not in a wave (Later): T17, T19, T20, T21. Later, optional: T22, then T24.

## 15. Risks

| ID | Risk | Mitigation |
|---|---|---|
| TR1 | Claude Code or Codex changes its log format. | Tolerant decoding: missing optional fields do not fail a line. Fixtures for each known shape. Count skipped lines and show "format changed?" if the share is high. |
| TR2 | Status line bridge conflicts with an existing user status line. | Opt-in setup. **Connect** writes a backup of `settings.json`, saves the old status line and runs it after TokenBar (D39). **Disconnect** puts it back. |
| TR3 | Limit data is old when the CLI is idle. | Use `resets_at`. Show each limit value with its age ("as of 14:02"). Never show an old percentage without its age. |
| TR4 | Cold scan of 1.3 GB Codex logs is slow. | 35-day window, marker prefilter, measure in T12. Add a disk cache only if needed. |
| TR5 | Prices change and the table is wrong. | `last_verified` shown in the UI. Community pull requests. |
| TR6 | Most students have no admin key. | v1 reads only local files. Admin APIs are Later. If they come back, state the admin-key need in the UI. |
| TR7 | Unsigned alpha scares non-engineers. | The npm install shows no Gatekeeper prompt (Section 13). DMG and Homebrew: decide after the alpha. README "Open Anyway" steps if a DMG ships. Signed build: Later, optional (TRD-T22). |
| TR8 | The TokenBar icon hides behind the notch. | Compact mode only, fixed width, Command-drag tip (Section 8). |
| TR9 | A parser bug stores prompt content. | Field-only `Decodable` structs and the `SECRET-MARKER` test. |

## 16. Open questions

| ID | Question | Owner |
|---|---|---|
| TQ1 | Bundle ID for the app (and the Keychain service, Later). Proposal: `com.patronofalltrades.TokenBar`. | Maintainer |
| TQ2 | Is the status line bridge acceptable as the Claude limit source? **Resolved 2026-10-08: yes, as an opt-in setup (PRD Q2, Section 5.1).** | — |
| TQ3 | Default refresh interval: 30 s (proposal) or 60 s? **Resolved 2026-10-08: 60 s, no setting (Section 7).** | — |
| TQ4 | Is the 35-day window enough for the popover views in the DRD? | DRD owner |
| TQ5 | If the formula ships after the alpha (TRD-T11): does the release workflow need a tap token for automatic formula updates? Is the `brew trust --tap` step acceptable for the launch audience? | Maintainer, after the alpha |
| TQ6 | Which Xcode version does CI pin? It must ship Swift 6 and Swift Testing. | First agent on T01 |
| TQ7 | Does TokenBar also read `~/Library/Application Support/Claude/*/.claude/projects` (Claude Desktop sessions)? CodexBar does. Not checked on this Mac. | Maintainer |
