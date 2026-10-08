# TokenBar: Product Requirements Document

| Field | Value |
|---|---|
| Status | Draft 1, for review by the maintainer |
| Owner | Hanif Ramadhan (maintainer) |
| Date | 2026-10-08 |
| Related | [README.md](../README.md), [AGENTS.md](../AGENTS.md), [TRD.md](TRD.md), [DRD.md](DRD.md) |

This document tells what TokenBar must do and why. [TRD.md](TRD.md) tells how. [DRD.md](DRD.md) tells how it looks and sounds. If this document and README.md or AGENTS.md do not agree, stop and ask the maintainer.

## 1. Glossary

Use these terms with these meanings in all TokenBar documents.

| Term | Meaning |
|---|---|
| Usage source | A place where TokenBar reads usage data. Examples: Claude Code logs, Codex logs, the OpenAI usage API. |
| Provider | The code that reads one usage source (`UsageProvider` in AGENTS.md). |
| Usage record | One unit of usage: timestamp, model name, input tokens, output tokens. It contains no prompt or response text. |
| API cost | The real cost that a provider usage API reports. |
| API-equivalent cost | Tokens × the public API price of the model. TokenBar uses it for subscription usage. |
| Price table | The data file with the public API price of each model, its source URL and its date. |
| Limit | A cap on usage in a time window, for example a 5-hour or weekly window. |
| Limit source | A usage source that reports a limit and its reset time. |
| Café index | The conversion of a cost into café units. |
| Café unit | One entry in the café-index data file, for example "café con leche". Each entry has a name, a price in EUR and a source note. |
| Roast | A short joke in the style of an IESE case. Roasts are in a data file. |
| Menu bar item | The icon and text that TokenBar shows in the macOS menu bar. |
| Popover | The panel that opens when the user clicks the menu bar item. |
| Plan mode | A manual mode. The user enters a subscription plan and its monthly price. TokenBar uses no usage source. |
| Alpha tester | A person who installs an alpha build before the class launch. |
| Class launch | The v1.0 release to the IESE MBA classes of 2027 and 2028. |

## 2. Problem

Students at IESE use AI every day for cases, recruiting and assignments. Most use consumer subscriptions. A minority use coding tools such as Claude Code and Codex. Some pay for API usage.

These users have three problems:

1. They do not know how much they use until they hit a limit. This often occurs the night before a deadline.
2. They do not know the value of their subscription. A monthly fee does not show how much usage it buys.
3. API users find out about their bill after they spend the money.

Engineering teams solve this problem with internal dashboards. For example, the Grab engineering team tracks token and credit usage across LLM providers. Individual students have no equivalent tool. A dashboard is also not enough: a number that nobody looks at does not prevent a surprise.

## 3. Job to be done

> "Show me how much AI I have used, so that a limit or a bill does not surprise me."

Supporting jobs:

- "Tell me when I am near a limit, before I hit it."
- "Make the number easy to remember." TokenBar does this with humor: the café index and roasts.

## 4. Users and personas

The audience is the IESE MBA classes of 2027 and 2028. The README assumes approximately 350 students in each class. Most use a Mac. Most are not engineers.

The personas below are assumptions. Validate them with the alpha survey (Section 9).

| | P1: Marta, the web-chat user | P2: Arjun, the power user | P3: Lucía, the side-project builder |
|---|---|---|---|
| Background | Ex-consultant. Targets strategy roles. | Ex-software engineer or PM. Targets tech roles. | Ex-founder. Builds a startup idea during the MBA. |
| AI tools | ChatGPT Plus in the browser and the desktop app. Sometimes claude.ai. | Claude Pro or Max with Claude Code. Codex CLI. | OpenAI or Anthropic API with her own organization. Claude Code. |
| Main question | "Is my subscription worth the money?" | "How close am I to my 5-hour limit?" | "How much did my prototype cost today?" |
| What TokenBar v1 can measure | Nothing automatically. Plan mode only. | Claude Code and Codex usage. | Claude Code usage and API cost with an admin key. |
| Share of audience | Large majority (assumption) | Minority (assumption) | Small minority (assumption) |
| Role in launch | Spreads the jokes. Low data value. | Primary v1 user. Gives the best feedback. | Validates the API feature. |

**Primary v1 persona: P2.** TokenBar v1 measures real usage only for P2 and P3. Section 6 explains the decision for P1.

## 5. Goals and non-goals

### 5.1 Goals

| ID | Goal |
|---|---|
| G1 | Show current AI usage and cost in the menu bar, with no API key, for Claude Code and Codex users. |
| G2 | Warn the user before a limit, when a limit source exists. |
| G3 | Make usage memorable with the café index and roasts. |
| G4 | Keep all data on the Mac. Send no telemetry. Read no prompt content. |
| G5 | Get real users at IESE and collect evidence of adoption without telemetry. |
| G6 | Make the project easy to contribute to: café units and roasts by pull request. |

### 5.2 Non-goals for v1

| Non-goal | Reason |
|---|---|
| Measure ChatGPT web, claude.ai web or Grok usage | No public usage API exists for these consumer products (Section 6). |
| Read browser cookies or scrape web sessions | This conflicts with G4. It is also fragile. |
| Class leaderboard | Roadmap "Later". It needs a server and consent design. |
| MCP server | Roadmap "Later". |
| xAI (Grok) usage | Roadmap "Later", when xAI supplies a usage source. |
| Windows, Linux, iOS | macOS 14 or later only (README). |
| Team or company billing features | TokenBar is for individuals. |
| Budget enforcement (block usage) | TokenBar informs. It does not control the tools. |

## 6. Key decision: users who use only web chat

**Fact.** ChatGPT web, claude.ai web and Grok have no public usage API for consumer accounts. The provider admin usage APIs cover API usage only. Thus v1 cannot see web-chat usage.

**Consequence.** P1 is the largest group at IESE (assumption). TokenBar v1 cannot answer the main job for P1.

**Options.**

| Option | Description | Assessment |
|---|---|---|
| A | Read browser cookies or local app data to get web-chat usage. | Rejected. It conflicts with G4. It can break the provider terms of service. It breaks when the web app changes. |
| B | Do not support P1. Tell P1 that TokenBar is not for them. | Honest, but it loses most of the class launch audience. |
| C | Plan mode. P1 enters the plan and its monthly price. TokenBar shows the monthly fee in café units, a daily share, and roasts. | Honest and cheap to build. It gives humor value, but no usage measurement. |
| D | Manual usage log. P1 records each session. | Rejected. Nobody will do this every day. |

**Recommendation: Option C, and say clearly what TokenBar cannot do.**

1. Make P2 the primary v1 user. Measure success on P2 first (Section 9).
2. Add plan mode in v0.3 so that P1 can install TokenBar and get the humor layer.
3. In onboarding and on the README, state: "TokenBar cannot see web-chat usage." Do not imply otherwise.
4. Keep the open question (Q1) to look for a reliable web-chat source. Add a source only if it obeys G4.

**Note for the maintainer.** The README first paragraph says that TokenBar shows "Claude, ChatGPT and Grok usage". This is not true for v1. Section 13 proposes a change.

## 7. Scope: user stories

Format: "As a <persona>, I want <capability>, so that <benefit>." Each acceptance criterion (AC) must be testable. Priority: **Must** blocks the stage release. **Should** does not.

### 7.1 v0.1 alpha: Claude Code logs, menu bar, popover, café index

**PRD-US-01 Install the alpha build** (Must)
As an alpha tester, I want to install TokenBar from GitHub Releases or Homebrew, so that I can test it.
- AC1: A DMG is attached to each GitHub release.
- AC2: `brew install --cask patronofalltrades/tap/tokenbar` installs the same version.
- AC3: The README tells how to open an unsigned build with **Open Anyway**.
- AC4: The app runs on macOS 14 or later, on Apple silicon and Intel.

**PRD-US-02 See Claude Code usage without a key** (Must)
As P2, I want TokenBar to read my local Claude Code logs, so that I see my usage with no API key.
- AC1: TokenBar finds the Claude Code log location with no user configuration. The TRD defines the location.
- AC2: TokenBar shows tokens by model for today and for the last 7 days.
- AC3: The totals match a manual count of a test log set. The test set is in the repository.
- AC4: The parser reads only timestamp, model name and token counts. A unit test proves that prompt text is not stored.
- AC5: New usage shows in the app in 60 seconds or less (target).

**PRD-US-03 See the API-equivalent cost** (Must)
As P2, I want a cost in EUR or USD for my subscription usage, so that I know its value.
- AC1: TokenBar calculates API-equivalent cost as tokens × price from the price table.
- AC2: Each price table entry has a model name, a price, a source URL and a "last checked" date.
- AC3: The popover labels the number "API-equivalent", not "spent".
- AC4: If a model has no price, TokenBar shows the tokens and the text "price unknown". It does not guess.

**PRD-US-04 See one number in the menu bar** (Must)
As any user, I want one short value next to the notch, so that I see my usage with no click.
- AC1: The menu bar item shows one primary value and one café-unit value. Example format: `◐ 62% · 3.4 ☕`.
- AC2: The user can select the primary value: limit percentage, cost today, or tokens today.
- AC3: The text does not exceed the width that the DRD specifies.

**PRD-US-05 See the full report in the popover** (Must)
As any user, I want details when I click, so that I understand the number.
- AC1: The popover shows each usage source with its usage, cost and time of last update.
- AC2: The popover shows the café index for today.
- AC3: The popover has links to Settings and Quit.

**PRD-US-06 Convert cost into café units** (Must)
As any user, I want my cost in IESE units, so that I remember it.
- AC1: Café units are in one data file. Adding a unit needs no code change.
- AC2: Each unit has a name, a price in EUR and a source note. The README states that prices are community estimates.
- AC3: The popover shows a minimum of two café units for the current cost.
- AC4: A contributor can add a unit with one pull request that changes only the data file.
- AC5: A test fails if a unit has a missing field or a price of zero or less.

**PRD-US-07 Trust the privacy promise** (Must)
As any user, I want proof that my data stays on my Mac, so that I can install TokenBar safely.
- AC1: v0.1 makes no network requests. A test with a network monitor confirms this before each release.
- AC2: The README privacy section matches the behavior of the build.
- AC3: TokenBar has no analytics or crash-report SDK.

**PRD-US-08 Understand an empty state** (Must)
As P1, I want a clear message when TokenBar finds no usage source, so that I do not think the app is broken.
- AC1: If no usage source exists, the popover tells which sources TokenBar supports.
- AC2: The message states that TokenBar cannot see web-chat usage.

### 7.2 v0.2 alpha: Codex logs, roasts, limit alerts

**PRD-US-09 See Codex usage without a key** (Must)
As P2, I want TokenBar to read my local Codex CLI logs, so that I see Codex usage too.
- AC1: AC1 to AC5 of PRD-US-02 apply to Codex logs.
- AC2: The popover shows Claude Code and Codex as separate usage sources.

**PRD-US-10 Read a case-method roast** (Must)
As any user, I want a short joke about my usage, so that the app is fun to open.
- AC1: Roasts are in a data file. Adding a roast needs no code change.
- AC2: A roast can use placeholders for live values, for example the limit percentage.
- AC3: TokenBar selects a roast that matches the current state (low, medium or high usage).
- AC4: The user can turn off roasts in Settings.
- AC5: Roasts follow the DRD voice rules. Roasts do not mention a real classmate, professor or section by name.

Example roast (humor string, not STE): *"The protagonist has 38% of Opus left and a 9 AM case deadline. Discuss."*

**PRD-US-11 See my limit and its reset time** (Must, when a limit source exists)
As P2, I want to see the percentage of my limit and the reset time, so that I can plan my work.
- AC1: For each limit source, the popover shows the percentage used and the time to reset.
- AC2: If no limit source exists for a tool, TokenBar shows usage only. It does not estimate a limit.
- AC3: The TRD documents each limit source and its reliability.

**PRD-US-12 Get a limit alert** (Must, when a limit source exists)
As P2, I want a macOS notification before I hit a limit, so that a limit does not surprise me.
- AC1: TokenBar sends a notification at 80% and at 95% of a limit (default thresholds).
- AC2: The user can change or turn off each threshold.
- AC3: TokenBar sends each alert a maximum of one time in each limit window.
- AC4: The notification can include a roast. The user can turn this off.

### 7.3 v0.3 beta: API keys, signed build, plan mode

**PRD-US-13 Add an OpenAI admin key** (Must)
As P3, I want to add my OpenAI admin key, so that I see my real API cost.
- AC1: TokenBar stores the key only in the macOS Keychain.
- AC2: TokenBar shows API cost for today and for the current month.
- AC3: TokenBar connects only to the OpenAI API host that the TRD lists.
- AC4: An invalid key shows a clear error. The error does not show the key.
- AC5: The user can delete the key. TokenBar removes it from the Keychain.

**PRD-US-14 Add an Anthropic admin key** (Must)
As P3, I want to add my Anthropic admin key, so that I see my real API cost.
- AC1: AC1 to AC5 of PRD-US-13 apply, with the Anthropic API host.

**PRD-US-15 Open the app with no security warning** (Must)
As any user, I want a signed and notarized build, so that macOS opens the app with no warning.
- AC1: The beta build is signed with a Developer ID and notarized by Apple.
- AC2: A first launch on a clean Mac shows no **Open Anyway** step.

**PRD-US-16 Use plan mode** (Must)
As P1, I want to enter my plan and its price, so that I get value from TokenBar with no usage source.
- AC1: The user can add one or more plans with a name and a monthly price that the user types.
- AC2: TokenBar does not ship subscription prices. The user enters the price.
- AC3: TokenBar shows the monthly fee and the daily share in café units.
- AC4: The popover labels plan mode values "plan cost", not "usage".
- AC5: Roasts in plan mode do not claim to know the user's usage.

**PRD-US-17 Give feedback** (Should)
As an alpha tester, I want a feedback link in the app, so that I can report a problem quickly.
- AC1: Settings has a "Send feedback" item. It opens the survey or GitHub Issues in the browser.
- AC2: The app sends no data itself. The user decides what to submit.

### 7.4 v1.0: class launch

**PRD-US-18 Complete onboarding in two minutes** (Must)
As P1 or P2, I want a short first-run setup, so that I see a value quickly.
- AC1: The first run detects the available usage sources and shows them.
- AC2: The first run states what TokenBar can see and what it cannot see.
- AC3: In a test with 5 non-engineers, 4 or more reach a value in the menu bar in 2 minutes or less (target).

**PRD-US-19 Start at login** (Must)
As any user, I want TokenBar to start when I log in, so that I do not need to open it.
- AC1: Settings has a "Launch at login" option. The default is on after onboarding.

**PRD-US-20 Get updates** (Should)
As any user, I want to know when a new version exists, so that I get fixes.
- AC1: Homebrew users get updates with `brew upgrade`.
- AC2: Any update check is opt-in and goes only to GitHub. The TRD lists the host.

### 7.5 Story map

| Stage | Stories |
|---|---|
| v0.1 alpha | US-01 to US-08 |
| v0.2 alpha | US-09 to US-12 |
| v0.3 beta | US-13 to US-17 |
| v1.0 | US-18 to US-20, and fixes from beta feedback |
| Later | MCP server, opt-in class leaderboard, xAI usage |

Create one Linear issue for each story. Use the story ID in the issue title.

## 8. Requirements that apply to all stories

| ID | Requirement |
|---|---|
| NFR-01 | TokenBar reads no prompt or response content (AGENTS.md 5.4). |
| NFR-02 | TokenBar sends no usage data off the Mac and has no telemetry (AGENTS.md 5.5). |
| NFR-03 | TokenBar keeps API keys only in the Keychain (AGENTS.md 5.6). |
| NFR-04 | TokenBar uses less than 1% average CPU when idle (target, to verify in TRD). |
| NFR-05 | TokenBar works offline. Only API-key providers and the optional update check need the network. |
| NFR-06 | All user-facing numbers show their unit and their type: API cost, API-equivalent cost or plan cost. |
| NFR-07 | The README credits CodexBar as prior art. TokenBar copies no CodexBar code. |

## 9. Success metrics

TokenBar has no telemetry. Thus every metric below comes from a public count or from a person who chooses to answer. All numbers are targets or assumptions, not facts.

### 9.1 Measurement methods

| Method | What it measures | Notes |
|---|---|---|
| GitHub Releases API, `download_count` of each DMG asset | Downloads, including Homebrew installs | The Homebrew cask downloads the DMG from GitHub Releases. Thus this count includes cask installs. One person can download more than one time. |
| Homebrew analytics | Not available | Homebrew public analytics cover official taps only (to verify). Do not depend on them for a personal tap. |
| GitHub stars, issues, pull requests | Interest and contribution | Count only people who are not the maintainer. |
| Opt-in survey (Google Form or Tally) | Active use, value, persona, NPS-style score | Linked from US-17 and from class channels. Send at day 7 and day 30 after launch. |
| Class WhatsApp poll | Installs and weekly use in each section | One question: "Do you have TokenBar installed and open this week?" |
| User interviews | Qualitative evidence | 30-minute calls. Record notes in a public case study with consent. |
| Shared screenshots | Word of mouth | Count posts in class channels and LinkedIn that users choose to share. |

### 9.2 Targets

The base is approximately 700 students in two classes (assumption from README audience). P2 is a minority, so targets are modest.

| ID | Metric | Target | Source | Stage |
|---|---|---|---|---|
| M1 | Alpha testers who install and use for 7 days | 8 | Direct contact | v0.2 |
| M2 | Alpha bug reports or suggestions | 15 | GitHub Issues, survey | v0.3 |
| M3 | DMG downloads in 30 days after class launch | 150 | GitHub Releases API | v1.0 |
| M4 | Self-reported weekly active users at day 30 | 50 | WhatsApp poll, survey | v1.0 |
| M5 | Survey answers at day 30 | 30 | Survey | v1.0 |
| M6 | Survey users who say TokenBar prevented a limit or bill surprise | 40% of P2 answers | Survey | v1.0 |
| M7 | Café-unit or roast pull requests from other people | 5 | GitHub | v1.0 + 60 days |
| M8 | GitHub stars | 100 | GitHub | v1.0 + 60 days |
| M9 | User interviews done | 8, with a minimum of 3 from P2 | Interview notes | v1.0 + 30 days |

**Primary metric: M4.** It is the closest proxy for real use without telemetry.

### 9.3 Portfolio evidence (FDE goal)

The maintainer uses TokenBar to show Forward Deployed Engineer skills. Collect this evidence during the launch:

1. A public case study: problem, users, decisions, metrics M3 to M9, and lessons.
2. Interview notes that show how user feedback changed the product.
3. A changelog that links each change to a user request.
4. A record of the privacy decision and how the metrics work without telemetry.

## 10. Launch plan

| Phase | Stage | Who | Duration (target) | Exit criteria |
|---|---|---|---|---|
| 1. Private alpha | v0.1 | 3 to 5 technical friends who use Claude Code | 2 weeks | No crash for 7 days. Claude Code totals verified by a minimum of 3 testers. |
| 2. Wider alpha | v0.2 | 8 to 15 testers, including Codex users and 2 non-engineers | 2 to 3 weeks | M1 met. Limit alerts work for a minimum of 3 testers. Roasts reviewed by 5 testers. |
| 3. Beta | v0.3 | Same group plus 2 to 3 API-key users and 3 P1 users | 2 weeks | Signed build works on a clean Mac. Plan mode tested by 3 P1 users. US-18 AC3 test done. |
| 4. Class launch | v1.0 | IESE MBA 2027 and 2028 | 1 day launch, 30-day follow-up | Launch done. Day-7 and day-30 survey sent. |

Class launch actions:

1. Prepare a one-page install guide with screenshots. State what TokenBar cannot see.
2. Post in class WhatsApp groups with a short demo GIF and the Homebrew command.
3. Ask a minimum of 5 alpha testers to share a screenshot of their café index on launch day.
4. Offer a 15-minute install session for non-engineers (to confirm with the maintainer, Q6).
5. Send the WhatsApp poll at day 7 and day 30. Send the survey at day 30.
6. Publish the case study after day 30.

## 11. Risks and mitigations

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Most of the class uses only web chat, which v1 cannot see. | High | High | Plan mode (US-16). Honest onboarding (US-18). Measure success on P2 first. Keep Q1 open. |
| R2 | Claude Code or Codex changes the local log format. | Medium | High | Version-tolerant parsers. Test fixtures for each known format. Show "source not readable" and do not show wrong numbers. |
| R3 | No reliable limit source exists for a tool. | Medium | High | US-11 AC2: show usage only. Do not estimate. Document the limit source in the TRD. |
| R4 | API prices change and the price table becomes old. | High | Medium | "Last checked" date per price (US-03 AC2). Show the date in the popover. |
| R5 | A roast offends a classmate or professor. | Medium | Medium | Roast review by testers. No real names (US-10 AC5). Option to turn off roasts. |
| R6 | Users think TokenBar sends their data. | Medium | High | No network in v0.1. Open source. Privacy section in onboarding. |
| R7 | Low adoption cannot be measured without telemetry. | High | Medium | Section 9 methods. Accept that numbers are lower bounds. |
| R8 | Apple Developer Program cost or delay blocks signing. | Medium | High | Decide Q4 before v0.3. Keep unsigned alpha path. |
| R9 | Users read API-equivalent cost as money that they spent. | Medium | Medium | Label rule NFR-06. Explain in the popover. |
| R10 | Café-unit prices are wrong or old. | Medium | Low | Source note per unit. Community pull requests. README disclaimer. |
| R11 | The maintainer has little time during the MBA. | High | Medium | Small scope. Agents build with Linear issues (AGENTS.md 6). Cut Should stories first. |
| R12 | Users confuse TokenBar with an IESE, Anthropic or OpenAI product. | Low | Medium | Non-affiliation note in README and in the About window. |

## 12. Open questions for the maintainer

| ID | Question | Needed by |
|---|---|---|
| Q1 | Do you accept Option C (plan mode) for web-chat users? Or do you prefer Option B (say that P1 is not a v1 user)? | v0.3 |
| Q2 | Is a reliable, local, privacy-safe limit source available for Claude Code and Codex? If not, do limit alerts stay in v0.2? | v0.2 |
| Q3 | Which currency is the default: EUR or USD? Do you allow a user setting? | v0.1 |
| Q4 | Do you pay for the Apple Developer Program for v0.3? Who owns the Developer ID? | v0.3 |
| Q5 | Which survey tool do you use (Google Forms, Tally or other)? Is a third-party form compatible with the privacy promise? | v0.2 |
| Q6 | Do you run an install session at class launch? Do you need approval from the class representatives or IESE to post in class channels? | v1.0 |
| Q7 | Who reviews roasts before release? Do you want a "safe" default set and an opt-in "spicy" set? | v0.2 |
| Q8 | Do you add a "copy share card" feature (an image of today's café index) to help word of mouth? It is not in the README. | v1.0 |
| Q9 | Do you target students outside IESE after v1.0? This changes the café units and the voice. | After v1.0 |
| Q10 | Is the launch date fixed to a point in the academic calendar, for example the start of a term? | v0.3 |

## 13. Proposed changes to README.md

These changes need approval from the maintainer. This PRD does not make them.

1. The first paragraph says that TokenBar shows "Claude, ChatGPT and Grok usage". Change it to name the v1 sources: Claude Code, Codex and the optional OpenAI and Anthropic APIs.
2. Add a "What TokenBar cannot see" note: ChatGPT web, claude.ai web and Grok.
3. Add plan mode to the v1 feature table and to v0.3 in the roadmap, if Q1 is accepted.
4. The example shows "62% of 5-hour limit" for Claude Code. Keep it only if Q2 confirms a limit source.
