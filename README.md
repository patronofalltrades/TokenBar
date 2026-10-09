# TokenBar

TokenBar is a macOS menu bar app. It shows how much AI you use, and it makes fun of you for it.

TokenBar shows your Claude Code and Codex usage in the menu bar, next to the camera notch. It does not show only euros. It shows the cost in units that an MBA student in Barcelona understands: cafés con leche, menús del día and a share of the MBA tuition fee.

```
 ☕ 3.4      ← Café Index: this is all you see in the menu bar
 🏛 0.04     ← Tuition Meter: your spend since install, as a % of MBA tuition
 💧 22 L     ← Water Footprint: the water your AI drank today (a high estimate)
```

Click the icon to see the full report:

```
┌───────────────────────────────────────────┐
│  Claude Code      62% of 5-hour limit     │
│                   resets in 1 h 48 min    │
│                   as of 14:02             │
│  Codex            18% of weekly limit     │
│                                           │
│  Today ≈ €6.10        Week ≈ €21.80       │
│  ☕ Today = 3.4 cafés con leche            │
│  🎓 0.04% of your MBA tuition, in tokens   │
│                                           │
│  "The protagonist has 38% of Opus left    │
│   and a 9 AM case deadline. Discuss."     │
└───────────────────────────────────────────┘
```

> **Status:** Pre-alpha. The specification is in progress. There is no build yet. The first alpha is planned for early November 2026.

## Why TokenBar exists

Engineering teams track the token and credit usage of each LLM provider. Most students do not. They find out about a limit when they hit it, usually the night before a deadline.

TokenBar has one job: **show you how much AI you have used, so that a limit or a bill does not surprise you.**

The humor is part of the product, not decoration. A number that makes you laugh is a number you remember.

## Features (v1)

| Feature | Description |
|---|---|
| Menu bar usage | Shows one usage number next to the notch. |
| Claude Code usage | Reads local Claude Code session logs. You do not need an API key. An optional status line setup adds the 5-hour and weekly limits. Click **Connect** in Settings. TokenBar edits `~/.claude/settings.json` with a backup, and your current status line keeps working. Without it, TokenBar shows tokens and cost only. |
| Codex usage | Reads local Codex CLI session logs, including limits. You do not need an API key. |
| MBA cost conversions | Shows your cost in euros, then converts it into Barcelona units, for example cafés con leche. |
| Case-method roasts | Shows short jokes in the style of a business school case. |
| Limit alerts | Sends a macOS notification when you approach a limit. |

### What TokenBar cannot see

TokenBar cannot see usage in the ChatGPT, Claude.ai or Grok web and desktop chat apps. These apps do not supply a public usage source. TokenBar does not read browser cookies to get this data.

### How TokenBar calculates cost

Subscription usage (Claude Pro or Max, ChatGPT Plus or Pro) has no per-token bill. Thus TokenBar calculates an **API-equivalent cost**: tokens × the provider's public API price. This number tells you the value that you get from your subscription.

Providers publish prices in USD. TokenBar converts them to EUR with one fixed rate from its price file. The rate is a community estimate with a date. Thus TokenBar shows costs as estimates, for example `≈ €3.40`.

### The café index

The conversion units are in a plain data file. Anyone can add a unit or correct a price with a pull request. Prices are community estimates, not official prices.

You pick one index. TokenBar shows only that index:

- **Café Index**: today's cost in cafés con leche and other campus food.
- **Tuition Meter**: the share of MBA tuition that your tokens have cost since you installed TokenBar.
- **Water Footprint**: the water for today's output tokens. TokenBar uses a high published estimate: 45 mL for a 400-token response (Mistral AI, 2025). The source is in `water.json`.

## Privacy

- TokenBar reads data only on your Mac.
- TokenBar does not send usage data to any server. There is no telemetry.
- TokenBar v1 reads only local files. It has no API keys.
- TokenBar makes no network request unless you turn on the update check. The update check is off by default.
- TokenBar does not read the content of your prompts. It reads only token counts, model names, timestamps, limit percentages and limit reset times.

## Requirements

- macOS 14 (Sonoma) or later
- Apple silicon Mac. TokenBar does not support Intel Macs.

## Install

> Not available yet. The alpha releases will be on npm only.

TokenBar is free and open source. Builds are not signed with an Apple Developer ID. Use the npm method. With this method, macOS opens TokenBar with no security prompt.

### npm (recommended)

You need [Node.js](https://nodejs.org) 18 or later.

```sh
npm install -g tokenbar
tokenbar install
```

`tokenbar install` copies TokenBar.app to `~/Applications` and opens it. To get a new version, run `npm update -g tokenbar`, then run `tokenbar install` again.

To remove TokenBar, run `tokenbar uninstall`, then run `npm uninstall -g tokenbar`.

### Homebrew (after the alpha)

> Not decided yet. The maintainer decides after the alpha if this method ships.

This method builds TokenBar from source. You need the Xcode Command Line Tools.

```sh
brew trust --tap patronofalltrades/tap
brew install patronofalltrades/tap/tokenbar
cp -R "$(brew --prefix)/opt/tokenbar/TokenBar.app" ~/Applications/
```

After each `brew upgrade`, copy the app again.

### DMG (after the alpha)

> Not decided yet. The maintainer decides after the alpha if this method ships.

Download the DMG from [Releases](https://github.com/patronofalltrades/TokenBar/releases). macOS blocks the first launch of a DMG build. To open the app:

1. Open **System Settings > Privacy & Security**.
2. Find the TokenBar message.
3. Click **Open Anyway**.

### Check a download

Each release lists the SHA-256 checksum of each file. The npm package has a provenance statement that links it to the GitHub Actions build.

## Roadmap

| Stage | Scope |
|---|---|
| v0.1 alpha (early November 2026) | Claude Code logs, menu bar number, popover, café index, case-method roasts. npm install. |
| v0.2 alpha (mid-December 2026) | Codex logs, Claude limits (status line setup), limit alerts, Settings, share card. |
| v1.0 (January 2027) | Class launch at the start of the winter term. Onboarding, launch at login, opt-in update check, feedback form. Homebrew and DMG: decided after the alpha. |
| Later | API keys: OpenAI Admin API and Anthropic Admin API usage. |
| Later | Spanish language. |
| Later | MCP server, so that an AI assistant can query your usage. |
| Later | Opt-in class leaderboard ("Top Token Burner, Section B"). |
| Later | xAI (Grok) usage, when xAI supplies a usage source. |
| Later, optional | Signed and notarized build. Only if non-technical users become a target after the alpha. |

## Documentation

| Document | Content |
|---|---|
| [Product Requirements](docs/PRD.md) | Users, problems, scope and success metrics. |
| [Technical Requirements](docs/TRD.md) | Architecture, data sources and release pipeline. |
| [Design Requirements](docs/DRD.md) | Menu bar, popover, humor voice and the café index. |
| [Decision log](docs/DECISIONS.md) | Each decision, with its date and reason. |
| [Workflow](docs/WORKFLOW.md) | How work flows from a Linear issue to a merged pull request. |
| [AGENTS.md](AGENTS.md) | Rules for AI coding agents that work on this repository. |

## Contributing

Contributions are welcome, especially new café-index units and better roasts. Read [AGENTS.md](AGENTS.md) before you open a pull request. The same rules apply to people and to AI agents.

## Prior art

[CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger is a macOS menu bar app that shows Codex and Claude Code usage. TokenBar is a separate implementation. We studied CodexBar to learn where usage data is kept. TokenBar adds the humor layer and the MBA community focus.

## License

[MIT](LICENSE)

TokenBar is not affiliated with any business school, Anthropic, OpenAI or xAI.
