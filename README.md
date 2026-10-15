# TokenBar

**Your AI habit, priced in cafés con leche.**

TokenBar is a macOS menu bar app for MBA students who use Claude Code and Codex more than they admit in class. It reads your local usage logs, shows how close you are to your limits, and converts the damage into units that a student in Barcelona understands. Then it roasts you, case-method style.

```
 ☕ 3.4      ← Café Index: today's tokens, in cafés con leche
 🎓 0.04%    ← Tuition Meter: share of a €114,000 MBA, burned in tokens
 💧 22 L     ← Water Footprint: what your prompts drank today
```

Click the icon for the full teaching note:

```
┌──────────────────────────────────────────────┐
│  3.4 cafés con leche today                   │
│  €6.12 of tokens ÷ €1.80 per café con leche  │
│  12 this week                                │
│                                              │
│  Claude Code   62% of 5-hour limit           │
│                resets in 1 h 48 min          │
│  Codex         18% of weekly limit           │
│                                              │
│  "The protagonist has 38% of Opus left       │
│   and a 9 AM deadline. Discuss."             │
└──────────────────────────────────────────────┘
```

> **Status:** Alpha. `tokenbar@0.1.0-alpha.2` is on npm. It works on the maintainer's Mac and on a few brave classmates' Macs. Expect bugs. Report them with the feedback link in the app.

## Why this exists

Engineering teams track every token. MBA students track nothing, then hit the limit at 1 AM, the night before a group deck is due.

TokenBar has one job: **show you how much AI you use, before a limit surprises you.**

The jokes are part of the product. You forget "€6.12". You remember "3.4 cafés con leche, and it is only Tuesday".

## Install

You need an Apple silicon Mac, macOS 14 or later, and [Node.js](https://nodejs.org) 18 or later.

```sh
npx tokenbar install
```

That's it. TokenBar copies itself to `~/Applications`, opens, and walks you through a short setup. It is faster than a coffee chat and less awkward.

### Let your AI install it

You already use Claude Code or Codex. Make it do the work. Paste this into your agent:

```text
Install TokenBar for me: https://github.com/patronofalltrades/TokenBar
Follow the "For AI agents" section of the README.
```

### Update and remove

- **Update:** run `npx tokenbar@latest install` again.
- **Remove:** run `npx tokenbar uninstall`. It also removes the TokenBar status line from Claude Code and puts back your old one. No hard feelings.

## What you get

| Feature | What it does |
|---|---|
| One number in the menu bar | Pick one index: Café Index, Tuition Meter or Water Footprint. The number sits next to the notch and judges you quietly. |
| Claude Code and Codex usage | Reads the local logs on your Mac. No API key, no login. |
| Real limits | Codex limits come from its logs. For Claude Code limits, click **Connect** in setup. TokenBar adds a status line to `~/.claude/settings.json` with a backup, and your old status line keeps working. |
| The receipt | A line under the headline shows the math, for example "€45.60 of tokens since install ÷ €114,000 MBA tuition". Trust, but verify. |
| Case-method roasts | About 40 short jokes about cold calls, cover letters, decks and coffee chats. |
| Limit alerts | A macOS notification at 95% and at the limit, so you can save your work before the model leaves you. |
| Share card | Copy a card and paste it in your Section chat. Bragging rights, or a cry for help. |
| Serious mode | A plain bar style for days when you cannot take a joke. |

### Three indexes

- **Café Index.** Today's spend in cafés con leche (€1.80), menús del día (€10) and other campus prices. The prices are community estimates in a plain JSON file. Your pull request is welcome.
- **Tuition Meter.** Your spend since install, as a share of a €114,000 MBA. It also tells you the year in which your tokens finish the tuition. When you reach 100%: "Tuition fully burned. The tokens graduated before you did."
- **Water Footprint.** The water for today's output tokens, from a high published estimate (Mistral AI, 2025: 45 mL for a 400-token response). The number is dramatic on purpose. The source is in `water.json`.

### A few roasts

> "Limit reached. You must now read the case yourself."

> "You used AI to write a cover letter about your passion for the firm. The firm used AI to read it."

> "Your finance professor would call this a sunk cost. Your AI calls it a Tuesday."

> "The model gave you three frameworks and a 2x2. You are now ready for consulting."

## How the cost is calculated

Claude Pro, Claude Max, ChatGPT Plus and ChatGPT Pro have no per-token bill. TokenBar calculates an **API-equivalent cost**: your tokens × the provider's public API price, converted to EUR at one fixed rate. This number tells you how much value you get from your subscription. It is not money that you paid. Each price has a source URL and a "last verified" date in `prices.json`.

## What TokenBar cannot see

ChatGPT, Claude.ai and Grok in the browser or in their desktop apps. These apps have no public usage source, and TokenBar does not read your browser cookies. Your 3 AM ChatGPT therapy sessions stay between you and OpenAI.

## Privacy

- Everything stays on your Mac. TokenBar makes no network requests.
- No telemetry. No analytics. No account.
- TokenBar never reads your prompts or responses. It reads only token counts, model names, timestamps and limits. Your terrible first drafts are safe.

## For AI agents

If a user asked you to install TokenBar, do these steps. Do not clone or build the repository.

1. Check the Mac. Stop and tell the user if a check fails.
   - `uname -m` must print `arm64`. TokenBar does not run on Intel Macs.
   - `sw_vers -productVersion` must be 14.0 or later.
   - `node --version` must be v18 or later. If Node.js is not installed, tell the user to install it from https://nodejs.org. Do not install it without permission.
2. Run `npx --yes tokenbar install`. The command checks the app signature, copies `TokenBar.app` to `~/Applications` and opens it.
3. Tell the user that a TokenBar setup window is open, possibly behind other windows. The user must finish the setup.
4. Do not edit `~/.claude/settings.json` yourself. The **Connect** button in the setup window does this with a backup.

To remove TokenBar, run `npx --yes tokenbar uninstall`.

The package is `tokenbar` on npm. It is built and published only by the GitHub Actions release workflow of this repository, with a provenance statement.

## Verify a download

Each [GitHub release](https://github.com/patronofalltrades/TokenBar/releases) lists the SHA-256 of `TokenBar.zip`. The npm package contains the same file and has a provenance statement that links it to the GitHub Actions build. The maintainer approves each npm release with 2FA.

## Roadmap

| Stage | Scope |
|---|---|
| Alpha (now) | Everything above. Tested with a small group of classmates. |
| v1.0 (January 2027) | Class launch at the start of the winter term, after the alpha feedback. |
| Later | Spanish. A class leaderboard ("Top Token Burner, Section B"), opt-in only. An MCP server, so your AI can ask how much AI you use. Grok usage, when xAI gives a usage source. |

## Contributing

Pull requests are welcome, especially new café units and better roasts. A good roast is about MBA life (cold calls, LinkedIn, case interviews, decks), not about generic AI. The maintainer approves each roast. Read [AGENTS.md](AGENTS.md) first. The same rules apply to people and to AI agents.

| Document | Content |
|---|---|
| [Product Requirements](docs/PRD.md) | Users, problems, scope and success metrics. |
| [Technical Requirements](docs/TRD.md) | Architecture, data sources and release pipeline. |
| [Design Requirements](docs/DRD.md) | Menu bar, popover, humor voice and the café index. |
| [Decision log](docs/DECISIONS.md) | Each decision, with its date and reason. |
| [Workflow](docs/WORKFLOW.md) | How work moves from a Linear issue to a merged pull request. |

## Prior art

[CodexBar](https://github.com/steipete/CodexBar) by Peter Steinberger is a macOS menu bar app that shows Codex and Claude Code usage. TokenBar is a separate implementation. We studied CodexBar to learn where usage data is kept. TokenBar adds the humor and the MBA focus.

## License

[MIT](LICENSE). Free, like the coffee at a corporate presentation.

TokenBar is not affiliated with any business school, Anthropic, OpenAI or xAI. No business school approved these jokes.
