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
| Usage source | A place where TokenBar reads usage data. In v1, only local files: Claude Code logs and Codex logs. |
| Provider | The code that reads one usage source (`UsageProvider` in AGENTS.md). |
| Usage record | One unit of usage: timestamp, model name, input tokens, output tokens. It contains no prompt or response text. |
| API cost | The real cost that a provider usage API reports. Only API-key providers (Later) report it. |
| API-equivalent cost | Tokens × the public API price of the model. TokenBar uses it for subscription usage. TokenBar shows it in EUR. |
| Price table | The data file with the public API price of each model, its source URL and its date. It also holds the fixed USD to EUR rate. |
| Today | The period from local midnight to now. |
| Week | The rolling last 7 days, not a calendar week (decided 2026-10-08). |
| Limit | A cap on usage in a time window, for example a 5-hour or weekly window. |
| Limit source | A usage source that reports a limit and its reset time. |
| Café index | The conversion of a cost into café units. |
| Café unit | One entry in the café-index data file, for example "café con leche". Each entry has a name, a price in EUR and a source note. |
| Roast | A short joke in the style of an IESE case. Roasts are in a data file. |
| Menu bar item | The icon and text that TokenBar shows in the macOS menu bar. |
| Popover | The panel that opens when the user clicks the menu bar item. |
| Index | The user choice for the menu bar item: Café Index, Tuition Meter or Water Footprint (DRD 2.5, D41). |
| Tuition benchmark | The spend since first launch as a percentage of IESE MBA tuition (DRD 7.6). It is not a café unit. |
| Share card | An image of today's café index that the user copies to the clipboard (DRD 7.7). |
| Alpha tester | A person who installs an alpha build before the class launch. |
| Class launch | The v1.0 release to the launch audience. The class WhatsApp poll selects the audience (Section 10, step 0). |

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

**v1 is for people who use AI coding tools or LLM APIs** (Section 6). The launch audience is not final. Before the launch, the maintainer runs a one-question poll in the class WhatsApp: "Do you use Claude Code or Codex?" The answer selects the launch audience: the whole class, or AI builders (for example, the IESE AI Club). See Section 10, step 0. The result is not known yet.

The personas below are assumptions. Validate them with the alpha survey (Section 9).

| | P1: Marta, the web-chat user | P2: Arjun, the power user | P3: Lucía, the side-project builder |
|---|---|---|---|
| Background | Ex-consultant. Targets strategy roles. | Ex-software engineer or PM. Targets tech roles. | Ex-founder. Builds a startup idea during the MBA. |
| AI tools | ChatGPT Plus in the browser and the desktop app. Sometimes claude.ai. | Claude Pro or Max with Claude Code. Codex CLI. | OpenAI or Anthropic API with her own organization. Claude Code. |
| Main question | "Is my subscription worth the money?" | "How close am I to my 5-hour limit?" | "How much did my prototype cost today?" |
| What TokenBar v1 can measure | Nothing. Not a v1 user. | Claude Code and Codex usage. | Claude Code usage only. API cost needs API keys (Later). |
| Share of audience | Large majority (assumption) | Minority (assumption) | Small minority (assumption) |
| Role in launch | Spreads the jokes. Low data value. | Primary v1 user. Gives the best feedback. | Secondary v1 user. Tells if API keys are worth the work (Later). |

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
| API-key providers (OpenAI Admin API, Anthropic Admin API) | Roadmap "Later" (Section 7.5). v1 reads only local files. |
| Languages other than English | Spanish comes after the launch. |
| Windows, Linux, iOS, Intel Macs | macOS 14 or later on Apple silicon only (README). |
| Team or company billing features | TokenBar is for individuals. |
| Budget enforcement (block usage) | TokenBar informs. It does not control the tools. |

## 6. Key decision: users who use only web chat

**Fact.** ChatGPT web, claude.ai web and Grok have no public usage API for consumer accounts. The provider admin usage APIs cover API usage only. Thus v1 cannot see web-chat usage.

**Consequence.** P1 is the largest group at IESE (assumption). TokenBar v1 cannot answer the main job for P1.

**Options.**

| Option | Description | Assessment |
|---|---|---|
| A | Read browser cookies or local app data to get web-chat usage. | Rejected. It conflicts with G4. It can break the provider terms of service. It breaks when the web app changes. |
| B | Do not support P1. Tell P1 that TokenBar is not for them. | **Selected 2026-10-08.** Honest. It can lose part of the class launch audience. The poll in Section 10, step 0 measures this loss. |
| C | Plan mode. P1 enters the plan and its monthly price. TokenBar shows the monthly fee in café units, a daily share, and roasts. | Rejected 2026-10-08. It gives humor value, but no usage measurement. |
| D | Manual usage log. P1 records each session. | Rejected. Nobody will do this every day. |

**Decision (2026-10-08): Option B, with honest onboarding.**

1. v1 is for people who use AI coding tools or LLM APIs. P1 is not a v1 user.
2. Make P2 the primary v1 user. Measure success on P2 first (Section 9).
3. In onboarding and on the README, state: "TokenBar cannot see web-chat usage." Do not imply otherwise.
4. Add a web-chat source later only if it is reliable and obeys G4.

**Note for the maintainer.** The README first paragraph now names the v1 sources (Section 13, item 1).

## 7. Scope: user stories

Format: "As a <persona>, I want <capability>, so that <benefit>." Each acceptance criterion (AC) must be testable. Priority: **Must** blocks the stage release. **Should** does not.

### 7.1 v0.1 alpha: Claude Code logs, menu bar, popover, café index, roasts

**PRD-US-01 Install the alpha build** (Must)
As an alpha tester, I want to install TokenBar from npm, so that I can test it.
- AC1: Each GitHub release has `TokenBar.zip` and `SHA256SUMS`. The alpha has no DMG and no Homebrew formula.
- AC2: `npm install -g tokenbar`, then `tokenbar install`, installs the version of the release.
- AC3: If the installed app has a quarantine flag, `tokenbar install` shows the **Open Anyway** steps.
- AC4: The app runs on macOS 14 or later, on Apple silicon only. On an Intel Mac, `tokenbar install` stops with a clear message.

**PRD-US-02 See Claude Code usage without a key** (Must)
As P2, I want TokenBar to read my local Claude Code logs, so that I see my usage with no API key.
- AC1: TokenBar finds the Claude Code log location with no user configuration. The TRD defines the location.
- AC2: TokenBar shows tokens by model for today and for the last 7 days.
- AC3: The totals match a manual count of a test log set. The test set is in the repository.
- AC4: The parser reads only timestamp, model name and token counts. A unit test proves that prompt text is not stored.
- AC5: New usage shows in the app in 60 seconds or less (target).

**PRD-US-03 See the API-equivalent cost** (Must)
As P2, I want a cost in EUR for my subscription usage, so that I know its value.
- AC1: TokenBar calculates API-equivalent cost as tokens × price from the price table.
- AC2: Each price table entry has a model name, a price, a source URL and a "last checked" date.
- AC3: The popover labels the number "API-equivalent", not "spent". (Changed by D42: the UI shows no EUR. The cost goes only into the index.)
- AC4: If a model has no price, TokenBar shows the tokens and the text "price unknown". It does not guess.
- AC5: TokenBar converts USD prices to EUR with one fixed rate from the price table. The rate has a date and the note "community estimate".
- AC6: TokenBar shows each cost with an approximate sign, for example `≈ €3.40`. No currency setting exists. (Changed by D42: the UI shows no EUR.)

**PRD-US-04 See one number in the menu bar** (Must)
As any user, I want one short value next to the notch, so that I see my usage with no click.
- AC1: The menu bar item shows one value. The index choice selects the value (DRD 2.5). Examples: `☕ 3.4` (Café Index), `🎓 0.04%` (Tuition Meter), `💧 22 L` (Water Footprint).
- AC2: The primary metric is always Auto: the closest limit, else today's cost (DRD 2.1). No setting exists.
- AC3: The text does not exceed the width that the DRD specifies (52 pt).
- AC4: The user selects one index: Café Index, Tuition Meter or Water Footprint (DRD 2.5). No default exists. The user can change the index later.
- AC5: In the Warning and Limit hit states, all indexes show the limit value (DRD 2.5, rule 1).

**PRD-US-05 See the full report in the popover** (Must)
As any user, I want details when I click, so that I understand the number.
- AC1: The popover shows each usage source with its usage, cost and time of last update.
- AC2: The popover shows the café index for today.
- AC3: The popover has links to Settings and Quit.
- AC4: The popover shows the Today and Week totals side by side. It has no Today/Week control.
- AC5: Only a source that TokenBar cannot read is an error. If a log has no new lines, TokenBar shows the last value. Each limit value shows its age, for example "as of 14:02".

**PRD-US-06 Convert cost into café units** (Must)
As any user, I want my cost in IESE units, so that I remember it.
- AC1: Café units are in one data file. Adding a unit needs no code change.
- AC2: Each unit has a name, a price in EUR and a source note. The README states that prices are community estimates.
- AC3: The popover shows one café-index line with one unit that TokenBar selects automatically (DRD 7.6). No unit setting exists.
- AC4: A contributor can add a unit with one pull request that changes only the data file.
- AC5: A test fails if a unit has a missing field or a price of zero or less.
- AC6: With the Tuition Meter, the popover shows the tuition benchmark: the share of IESE tuition that the spend since first launch has cost (DRD 7.6).
- AC7: The data file has one tuition entry, `iese_mba_tuition`. TokenBar shows the years-to-tuition value only with 7 or more days of data.

**PRD-US-07 Trust the privacy promise** (Must)
As any user, I want proof that my data stays on my Mac, so that I can install TokenBar safely.
- AC1: v0.1 makes no network requests. A test with a network monitor confirms this before each release.
- AC2: The README privacy section matches the behavior of the build.
- AC3: TokenBar has no analytics or crash-report SDK.

**PRD-US-08 Understand an empty state** (Must)
As P1, I want a clear message when TokenBar finds no usage source, so that I do not think the app is broken.
- AC1: If no usage source exists, the popover tells which sources TokenBar supports.
- AC2: The message states that TokenBar cannot see web-chat usage.

**PRD-US-10 Read a case-method roast** (Must)
As any user, I want a short joke about my usage, so that the app is fun to open.
- AC1: Roasts are in a data file. Adding a roast needs no code change.
- AC2: A roast can use placeholders for live values, for example the limit percentage.
- AC3: TokenBar selects a roast that matches the current state (low, medium or high usage).
- AC4: The user can turn off roasts with the Roasts toggle in Settings (DRD 2.5, D41).
- AC5: Roasts follow the DRD voice rules. Roasts do not mention a real classmate, professor or section by name.

Example roast (humor string, not STE): *"The protagonist has 38% of Opus left and a 9 AM case deadline. Discuss."*

### 7.2 v0.2 alpha: Codex logs, limit alerts, share card

**PRD-US-09 See Codex usage without a key** (Must)
As P2, I want TokenBar to read my local Codex CLI logs, so that I see Codex usage too.
- AC1: AC1 to AC5 of PRD-US-02 apply to Codex logs.
- AC2: The popover shows Claude Code and Codex as separate usage sources.

**PRD-US-11 See my limit and its reset time** (Must, when a limit source exists)
As P2, I want to see the percentage of my limit and the reset time, so that I can plan my work.
- AC1: For each limit source, the popover shows the percentage used and the time to reset.
- AC2: If no limit source exists for a tool, TokenBar shows usage only. It does not estimate a limit.
- AC3: The TRD documents each limit source and its reliability.
- AC4: Claude Code limits come from an opt-in status line setup (Q2). Settings has a **Connect** button (D39) and the manual snippet with a Copy button.
- AC5: **Connect** keeps an existing custom Claude Code status line. TokenBar runs it and shows its output (D39).
- AC6: Without the setup, TokenBar shows Claude Code tokens and cost only.

**PRD-US-12 Get a limit alert** (Must, when a limit source exists)
As P2, I want a macOS notification before I hit a limit, so that a limit does not surprise me.
- AC1: TokenBar sends two notifications: at 95% of a limit and at limit hit (DRD 6.1). It sends no 80% notification and no reset notification. The menu bar shows the Warning state from 80%.
- AC2: The user can turn off each of the two alerts.
- AC3: TokenBar sends each alert a maximum of one time in each limit window.
- AC4: When Roasts is on, the notification can include a roast. When Roasts is off, it has no roast.
- AC5: TokenBar has no quiet hours. macOS Focus controls the delivery.

**PRD-US-21 Share today's café index** (Must)
As any user, I want to copy an image of today's café index, so that I can post the joke in a class chat.
- AC1: The popover footer has a **Share** button. **Share** copies an image and a text to the clipboard (DRD 7.7).
- AC2: The card contains today's café-index value, the tuition benchmark (if available), the current roast and the repository link.
- AC3: The card contains no user name, file paths, project names or prompt content. A test proves this.
- AC4: The card shows a model name only if the roast uses `{model}`.
- AC5: TokenBar renders the image with SwiftUI `ImageRenderer`. The feature adds no dependency.
- AC6: The card shows the selected index only. Before the user selects an index, the card shows numbers only.
- AC7: After the copy, the popover shows a one-line confirmation.
- AC8: **Share** makes no network request. The user decides where to paste the card.

### 7.3 v1.0: class launch

**PRD-US-15 Open the app with no security warning** (Must)
As any user, I want an install method with no security step, so that macOS opens the app with no warning.
- AC1: After an install with npm (`tokenbar install`), a first launch on a clean Mac shows no **Open Anyway** step.
- AC2: If the maintainer ships a DMG after the alpha, the README tells DMG users how to use **Open Anyway**.
- AC3: TokenBar needs no Developer ID and no notarization for this story (Q4).

**PRD-US-17 Give feedback** (Should)
As an alpha tester, I want a feedback link in the app, so that I can report a problem quickly.
- AC1: Settings has a "Send feedback" item. The error state has a "Report a problem" item. Both open the feedback Tally form (URL set at alpha) in the browser, not GitHub.
- AC2: The app sends no data itself. The user decides what to submit.

**PRD-US-18 Complete onboarding in two minutes** (Must)
As P2 or P3, I want a short first-run setup, so that I see a value quickly.
- AC1: The first run detects the available usage sources and shows them.
- AC2: The first run states what TokenBar can see and what it cannot see.
- AC3: Test with 5 people from the target audience (AI-coding-tool users). A minimum of 2 are not software engineers by background. 4 or more reach a value in the menu bar in 2 minutes or less (target).
- AC4: After detection, the first run asks the user to select one index: Café Index, Tuition Meter or Water Footprint. It shows a live preview of each index (DRD 4.5). No default exists.

**PRD-US-19 Start at login** (Must)
As any user, I want TokenBar to start when I log in, so that I do not need to open it.
- AC1: Settings has a "Launch at login" option. The default is on after onboarding.

**PRD-US-20 Get updates** (Should)
As any user, I want to know when a new version exists, so that I get fixes.
- AC1: npm users get updates with `npm update -g tokenbar`, then `tokenbar install`.
- AC2: The update check is opt-in and off by default. It goes only to GitHub. The TRD lists the host.

### 7.4 Later: API keys

v1 reads only local files. The API-key stories move to Later (decided 2026-10-08). They keep their IDs. Start them only after v1.0, with maintainer approval.

**PRD-US-13 Add an OpenAI admin key** (Later)
As P3, I want to add my OpenAI admin key, so that I see my real API cost.
- AC1: TokenBar stores the key only in the macOS Keychain.
- AC2: TokenBar shows API cost for today and for the current month.
- AC3: TokenBar connects only to the OpenAI API host that the TRD lists.
- AC4: An invalid key shows a clear error. The error does not show the key.
- AC5: The user can delete the key. TokenBar removes it from the Keychain.

**PRD-US-14 Add an Anthropic admin key** (Later)
As P3, I want to add my Anthropic admin key, so that I see my real API cost.
- AC1: AC1 to AC5 of PRD-US-13 apply, with the Anthropic API host.

### 7.5 Story map

| Stage | Target date | Stories |
|---|---|---|
| v0.1 alpha | Early November 2026 | US-01 to US-08, US-10 |
| v0.2 alpha | Mid-December 2026 | US-09, US-11, US-12, US-21 |
| v1.0 | January 2027 | US-15, US-17 to US-20, and fixes from alpha feedback |
| Later | — | US-13, US-14 (API keys), Spanish, MCP server, opt-in class leaderboard, xAI usage |

Create one Linear issue for each story. Use the story ID in the issue title. US-16 is cancelled (2026-10-08, Section 6). Do not reuse the ID.

## 8. Requirements that apply to all stories

| ID | Requirement |
|---|---|
| NFR-01 | TokenBar reads no prompt or response content (AGENTS.md 5.4). |
| NFR-02 | TokenBar sends no usage data off the Mac and has no telemetry (AGENTS.md 5.5). |
| NFR-03 | v1 has no API keys. When API keys come back (Later), TokenBar keeps them only in the Keychain (AGENTS.md 5.6). |
| NFR-04 | TokenBar uses less than 1% average CPU when idle (target, to verify in TRD). |
| NFR-05 | TokenBar works offline. In v1, only the opt-in update check needs the network. |
| NFR-06 | All user-facing numbers show their unit. The UI shows no EUR cost (D42). |
| NFR-08 | The README and all user-facing UI text outside the data files do not use the name "IESE". Section 13 has the rule. |
| NFR-07 | The README credits CodexBar as prior art. TokenBar copies no CodexBar code. |

## 9. Success metrics

TokenBar has no telemetry. Thus every metric below comes from a public count or from a person who chooses to answer. All numbers are targets or assumptions, not facts.

### 9.1 Measurement methods

| Method | What it measures | Notes |
|---|---|---|
| npm download counts API (`https://api.npmjs.org/downloads/point/<period>/tokenbar`) | Downloads of the npm package (primary channel) | Public, no key. `npm update` and `npx` also count, and mirrors and CI can add downloads. Thus the count is an upper bound for people. |
| GitHub Releases API, `download_count` of each release asset | Downloads of `TokenBar.zip`, and of the DMG if it ships after the alpha | A Homebrew formula (if it ships) builds from the source tarball. The source tarball has no `download_count`. Thus this count does not include Homebrew installs. One person can download more than one time. |
| Homebrew analytics | Not available | Homebrew public analytics cover official taps only (to verify). Do not depend on them for a personal tap. |
| GitHub stars, issues, pull requests | Interest and contribution | Count only people who are not the maintainer. |
| Opt-in survey (Tally) | Active use, value, persona, NPS-style score | Linked from US-17 and from class channels. Send at day 7 and day 30 after launch. |
| Class WhatsApp poll | Installs and weekly use in each section | One question: "Do you have TokenBar installed and open this week?" |
| User interviews | Qualitative evidence | 30-minute calls. Record notes in a public case study with consent. |
| Shared screenshots and share cards | Word of mouth | Count posts in class channels and LinkedIn that users choose to share (PRD-US-21). |

### 9.2 Targets

The base is approximately 700 students in two classes (assumption from README audience). P2 is a minority, so targets are modest.

| ID | Metric | Target | Source | Stage |
|---|---|---|---|---|
| M1 | Alpha testers who install and use for 7 days | 8 | Direct contact | v0.2 |
| M2 | Alpha bug reports or suggestions | 15 | Survey, GitHub Issues | v0.2 |
| M3 | npm downloads plus GitHub Release asset downloads in 30 days after class launch | 150 | npm download counts API, GitHub Releases API | v1.0 |
| M4 | Self-reported weekly active users at day 30 | 50 | WhatsApp poll, survey | v1.0 |
| M5 | Survey answers at day 30 | 30 | Survey | v1.0 |
| M6 | Survey users who say TokenBar prevented a limit or bill surprise | 40% of P2 answers | Survey | v1.0 |
| M7 | Café-unit or roast pull requests from other people | 5 | GitHub | v1.0 + 60 days |
| M8 | GitHub stars (secondary) | 100 | GitHub | v1.0 + 60 days |
| M9 | User interviews done | 8, with a minimum of 3 from P2 | Interview notes | v1.0 + 30 days |

**Primary metric: M4.** It is the closest proxy for real use without telemetry.

### 9.3 Portfolio evidence (FDE goal)

The maintainer uses TokenBar to show Forward Deployed Engineer skills. The deliverables below are committed scope, not optional extras (decided 2026-10-08).

| Deliverable | Content | Stage |
|---|---|---|
| Decision log | Each product and technical decision, with date and reason: [DECISIONS.md](DECISIONS.md). | Kept current from v0.1 |
| Workflow write-up | How agents from different providers build TokenBar: [WORKFLOW.md](WORKFLOW.md). | v0.1, updated at v1.0 |
| Build-in-public posts | Three posts: kickoff, alpha learnings, launch. | Kickoff at v0.1, learnings at v0.2, launch at v1.0 |
| Demo video or GIF | A short demo for the README and the launch post. | v1.0 |
| Public case study | Problem, users, decisions, metrics M3 to M9, and lessons. | After day 30 of v1.0 |

Also collect this evidence during the launch:

1. Interview notes that show how user feedback changed the product.
2. A changelog that links each change to a user request.
3. A record of the privacy decision and how the metrics work without telemetry.

## 10. Launch plan

TokenBar launches v1.0 in January 2027, at the start of the IESE winter term (decided 2026-10-08). The v0.3 beta stage is removed. Its work moves to v1.0 or Later (Section 7.5).

| Phase | Stage | Who | Start (target) | Exit criteria |
|---|---|---|---|---|
| 1. Private alpha | v0.1 | 3 to 5 technical friends who use Claude Code | Early November 2026 | No crash for 7 days. Claude Code totals verified by a minimum of 3 testers. npm install works on a clean Mac with no **Open Anyway** step. |
| 2. Wider alpha | v0.2 | 8 to 15 testers, including Codex users and 2 non-engineers | Mid-December 2026 | M1 met. Limit alerts work for a minimum of 3 testers. 5 testers read the roasts and give feedback. The maintainer decides on the DMG and the Homebrew formula. |
| 3. Class launch | v1.0 | The audience from step 0: IESE MBA 2027 and 2028, or an AI-builders group | January 2027, start of the winter term | US-18 AC3 test done before the launch. Launch done. Day-7 and day-30 survey sent. |

Class launch actions:

0. Before you make the launch target final, run a one-question poll in the class WhatsApp: "Do you use Claude Code or Codex?" The answer decides the launch audience: the whole class, or AI builders (for example, the IESE AI Club). Record the result and the decision in this section. Result: not known yet.
1. Prepare a one-page install guide with screenshots. State what TokenBar cannot see.
2. Post in the channels of the launch audience with a short demo GIF and the npm command.
3. Ask a minimum of 5 alpha testers to share a screenshot of their café index on launch day.
4. Offer a 15-minute install session for non-engineers (to confirm with the maintainer, Q6).
5. Send the WhatsApp poll at day 7 and day 30. Send the survey at day 30.
6. Publish the case study after day 30.

## 11. Risks and mitigations

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Most of the class uses only web chat, which v1 cannot see. | High | High | Option B: v1 is for AI-coding-tool and API users (Section 6). Honest onboarding (US-18). The poll selects the launch audience (Section 10, step 0). Measure success on P2 first. |
| R2 | Claude Code or Codex changes the local log format. | Medium | High | Version-tolerant parsers. Test fixtures for each known format. Show "source not readable" and do not show wrong numbers. |
| R3 | No reliable limit source exists for a tool. | Medium | High | US-11 AC2: show usage only. Do not estimate. Document the limit source in the TRD. |
| R4 | API prices change and the price table becomes old. | High | Medium | "Last checked" date per price (US-03 AC2). Show the date in the popover. |
| R5 | A roast offends a classmate or professor. | Medium | Medium | The maintainer approves each roast (Q7). One safe set only. No real names (US-10 AC5). Option to turn off roasts. |
| R6 | Users think TokenBar sends their data. | Medium | High | No network in v0.1. Open source. Privacy section in onboarding. |
| R7 | Low adoption cannot be measured without telemetry. | High | Medium | Section 9 methods. Accept that numbers are lower bounds. |
| R8 | Apple Developer Program cost or delay blocks signing. | Medium | High | Closed by Q4: no Developer ID for v0.x. npm is the primary channel. |
| R9 | Users read API-equivalent cost as money that they spent. | Medium | Medium | Label rule NFR-06. Explain in the popover. |
| R10 | Café-unit prices are wrong or old. | Medium | Low | Source note per unit. Community pull requests. README disclaimer. |
| R11 | The maintainer has little time during the MBA. | High | Medium | Time budget: 3 to 5 hours a week (decided 2026-10-08). Plan about 2 waves a week ([WORKFLOW.md](WORKFLOW.md)). Small scope. Agents build with Linear issues (AGENTS.md 6). Cut Should stories first. |
| R12 | Users confuse TokenBar with a business school, Anthropic or OpenAI product. | Low | Medium | Neutral public name: no "IESE" in the README or UI text (NFR-08). Non-affiliation note in README and in the About window. |

## 12. Open questions for the maintainer

| ID | Question | Needed by |
|---|---|---|
| Q1 | Do you accept Option C or Option B for web-chat users (Section 6)? **Resolved 2026-10-08: Option B. P1 is not a v1 user. v1 is for people who use AI coding tools or LLM APIs.** | — |
| Q2 | Is a reliable, local, privacy-safe limit source available for Claude Code and Codex? If not, do limit alerts stay in v0.2? **Resolved (decided 2026-10-08): yes. Codex limits are in its logs. For Claude Code, the status line bridge (TRD 5.1) is an opt-in setup. Settings shows the snippet with a Copy button. Settings warns that the snippet replaces an existing custom status line. Without the setup, Claude Code shows tokens and cost only. Limit alerts stay in v0.2.** | v0.2 |
| Q3 | Which currency is the default: EUR or USD? Do you allow a user setting? **Resolved (decided 2026-10-08): EUR everywhere. No currency setting. TokenBar converts USD prices with one fixed rate in `prices.json`. The rate has a date and the note "community estimate". Costs show as `≈ €3.40`. The café index and the tuition benchmark use EUR directly.** | v0.1 |
| Q4 | Do you pay for the Apple Developer Program? Who owns the Developer ID? **Decided 2026-10-08: no Developer ID for v0.x. Use npm as the primary channel.** Signing and notarization are "Later, optional": only if non-technical users become a target after the alpha. | — |
| Q5 | Which survey tool do you use (Google Forms, Tally or other)? Is a third-party form compatible with the privacy promise? **Resolved (decided 2026-10-08): Tally. The app only opens the Tally form (URL set at alpha) in the browser. The app sends no data. The user decides what to submit.** | v0.2 |
| Q6 | Do you run an install session at class launch? Do you need approval from the class representatives or IESE to post in class channels? | v1.0 |
| Q7 | Who reviews roasts before release? Do you want a "safe" default set and an opt-in "spicy" set? **Resolved (decided 2026-10-08): the maintainer alone approves each roast. One safe set only. No "spicy" mode.** | v0.2 |
| Q8 | Do you add a "copy share card" feature (an image of today's café index) to help word of mouth? **Resolved 2026-10-08: yes. The share card is a v0.2 Must (PRD-US-21, DRD 7.7).** | v0.2 |
| Q9 | Do you target students outside IESE after v1.0? This changes the café units and the voice. | After v1.0 |
| Q10 | Is the launch date fixed to a point in the academic calendar, for example the start of a term? **Resolved 2026-10-08: yes. v1.0 launches in January 2027, at the start of the IESE winter term (Section 10).** | — |
| Q11 | Is the launch audience the whole class or AI builders? **Decided 2026-10-08: the class WhatsApp poll decides (Section 10, step 0). Result not known yet.** | v1.0 |

## 13. Proposed changes to README.md

These changes need approval from the maintainer. This PRD does not make them.

1. Done. The first paragraph names the v1 sources: Claude Code and Codex. API keys are Later (Section 7.4).
2. Done. The README has a "What TokenBar cannot see" note: ChatGPT web, claude.ai web and Grok.
3. Closed 2026-10-08. Q1 selected Option B, so the README needs no change for web-chat users.
4. Closed 2026-10-08. Q2 confirmed the Claude Code limit source, so the example "62% of 5-hour limit" stays.
5. Done. Neutral public name (decided 2026-10-08). The README, the repository description and all user-facing UI text outside the data files do not use the name "IESE". Use "MBA", "business school" or "Barcelona". "IESE" can appear only in the `Resources/*.json` data files, in PRD, TRD and DRD planning text about the audience, and in internal names such as the `iese_mba_tuition` ID. The non-affiliation note is neutral.
