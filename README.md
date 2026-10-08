# TokenBar

TokenBar is a macOS menu bar app. It shows how much AI you use, and it makes fun of you for it.

TokenBar shows your Claude Code, Codex and LLM API usage in the menu bar, next to the camera notch. It does not show only dollars. It shows the cost in units that an IESE MBA student understands: cafés con leche, case packets and Barcelona rent.

```
 ◐ 62% · 3.4 ☕          ← this is all you see in the menu bar
```

Click the icon to see the full report:

```
┌───────────────────────────────────────────┐
│  Claude Code      62% of 5-hour limit     │
│                   resets in 1 h 48 min    │
│  Codex            18% of weekly limit     │
│  OpenAI API       $4.12 today             │
│                                           │
│  Today = 3.4 cafés con leche              │
│        = 0.6 Bar Tomàs patatas bravas     │
│                                           │
│  "The protagonist has 38% of Opus left    │
│   and a 9 AM case deadline. Discuss."     │
└───────────────────────────────────────────┘
```

> **Status:** Pre-alpha. The specification is in progress. There is no build yet.

## Why TokenBar exists

Engineering teams track the token and credit usage of each LLM provider. Most students do not. They find out about a limit when they hit it, usually the night before a deadline.

TokenBar has one job: **show you how much AI you have used, so that a limit or a bill does not surprise you.**

The humor is part of the product, not decoration. A number that makes you laugh is a number you remember.

## Features (v1)

| Feature | Description |
|---|---|
| Menu bar usage | Shows the most important usage number next to the notch. |
| Claude Code usage | Reads local Claude Code session logs. You do not need an API key. A one-time status line setup adds the 5-hour and weekly limits. |
| Codex usage | Reads local Codex CLI session logs, including limits. You do not need an API key. |
| API usage (optional) | Reads OpenAI and Anthropic usage APIs with an admin key that you supply. The Anthropic Admin API needs an organization account. |
| IESE cost conversions | Converts your spend into IESE units, for example cafés con leche. |
| Case-method roasts | Shows short jokes in the style of an IESE case. |
| Limit alerts | Sends a macOS notification when you approach a limit. |

### What TokenBar cannot see

TokenBar cannot see usage in the ChatGPT, Claude.ai or Grok web and desktop chat apps. These apps do not supply a public usage source. TokenBar does not read browser cookies to get this data.

### How TokenBar calculates cost

API usage comes with a real cost from the provider. Subscription usage (Claude Pro or Max, ChatGPT Plus or Pro) has no per-token bill. For subscriptions, TokenBar calculates an **API-equivalent cost**: tokens × the provider's public API price. This number tells you the value that you get from your subscription.

### The café index

The conversion units are in a plain data file. Anyone can add a unit or correct a price with a pull request. Prices are community estimates, not official prices.

## Privacy

- TokenBar reads data only on your Mac.
- TokenBar does not send usage data to any server. There is no telemetry.
- TokenBar keeps API keys in the macOS Keychain.
- TokenBar does not read the content of your prompts. It reads only token counts, model names, timestamps, limit percentages and limit reset times.

## Requirements

- macOS 14 (Sonoma) or later
- Apple silicon or Intel Mac

## Install

> Not available yet. The first alpha release will be on GitHub Releases.

Planned methods:

```sh
brew install --cask patronofalltrades/tap/tokenbar
```

You can also download the DMG from [Releases](https://github.com/patronofalltrades/TokenBar/releases).

**Alpha builds are not signed.** macOS will block the first launch. To open the app:

1. Open **System Settings > Privacy & Security**.
2. Find the TokenBar message.
3. Click **Open Anyway**.

The class launch build will be signed and notarized by Apple. Then this step will not be necessary.

## Roadmap

| Stage | Scope |
|---|---|
| v0.1 alpha | Claude Code logs, menu bar number, popover, café index. |
| v0.2 alpha | Codex logs, case-method roasts, limit alerts. |
| v0.3 beta | Optional API keys (OpenAI, Anthropic). Signed and notarized build. |
| v1.0 | Class launch to IESE MBA 2027 and 2028. |
| Later | MCP server, so that an AI assistant can query your usage. |
| Later | Opt-in class leaderboard ("Top Token Burner, Section B"). |
| Later | xAI (Grok) usage, when xAI supplies a usage source. |

## Documentation

| Document | Content |
|---|---|
| [Product Requirements](docs/PRD.md) | Users, problems, scope and success metrics. |
| [Technical Requirements](docs/TRD.md) | Architecture, data sources and release pipeline. |
| [Design Requirements](docs/DRD.md) | Menu bar, popover, humor voice and the café index. |
| [AGENTS.md](AGENTS.md) | Rules for AI coding agents that work on this repository. |

## Contributing

Contributions are welcome, especially new café-index units and better roasts. Read [AGENTS.md](AGENTS.md) before you open a pull request. The same rules apply to people and to AI agents.

## Prior art

[CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger is a macOS menu bar app that shows Codex and Claude Code usage. TokenBar is a separate implementation. We studied CodexBar to learn where usage data is kept. TokenBar adds the humor layer and the IESE community focus.

## License

[MIT](LICENSE)

TokenBar is not affiliated with IESE Business School, Anthropic, OpenAI or xAI.
