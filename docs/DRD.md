# TokenBar Design Requirements Document (DRD)

| Field | Value |
|---|---|
| Status | Draft 1 |
| Scope | v1.0 (class launch) |
| Related | [README](../README.md), [PRD](PRD.md), [TRD](TRD.md), [AGENTS.md](../AGENTS.md) |

This document specifies the user interface, the humor system and the café index. The PRD specifies scope. The TRD specifies data sources and architecture. If this document and AGENTS.md do not agree, AGENTS.md has priority.

**Writing standard.** This document uses ASD-STE100. User-facing humor strings (roasts, unit labels and notification copy) do not use ASD-STE100. These strings are in tables and code blocks. They follow the voice guide in Section 7.1.

**Terms.** This document uses these terms with one meaning only:

| Term | Meaning |
|---|---|
| Menu bar item | The TokenBar status item in the macOS menu bar. |
| Popover | The window that opens when the user clicks the menu bar item. |
| Provider | One usage source. In v1: Claude Code or Codex. OpenAI API and Anthropic API are Later (PRD 7.4). |
| Limit | A usage cap with a reset time, for example the Claude 5-hour limit. |
| Primary metric | The single number in the menu bar item. |
| Cost | API-equivalent cost in EUR, shown as an estimate: `≈ €3.40`. Real API cost comes with API keys (Later). |
| Unit | One café-index item, for example café con leche. |
| Roast | One short humor line in the style of an IESE case. |

---

## 1. Design principles

1. **Glanceable.** The user must understand the menu bar item in less than one second. Show one number.
2. **Quiet by default.** Do not animate the menu bar item. Send few notifications. Show a roast only in the popover.
3. **Funny about AI usage only.** Make jokes about tokens, limits, deadlines and MBA life. Do not make jokes about the body, gender, origin, religion, money problems or a real person.
4. **Honest numbers.** The joke never hides the real number. Show the real percentage or cost next to each café-index value. Label API-equivalent cost as an estimate.
5. **Native.** Use system fonts, semantic colors and SF Symbols. TokenBar must look like a part of macOS.
6. **Compact.** The space next to the camera notch is small. TokenBar must not push other items out of the menu bar.

---

## 2. Menu bar item

### 2.1 Primary metric

The primary metric is always Auto (decided 2026-10-08). No "Menu bar shows" setting exists.

1. Auto shows the highest limit percentage of all providers. This is the limit that is closest to a reset problem. Example: `62%`.
2. If no provider has a limit, Auto shows today's cost for all providers. Example: `€3.4`. The menu bar has no `≈` sign. The popover keeps `≈ €` (D38). TRD-T08 checks that this value fits in 52 pt.

The bar style (Section 2.5) selects if the menu bar item shows the primary metric or the café-index value.

### 2.2 Display mode and width

TokenBar has one display mode: Compact, on all displays (decided 2026-10-08). No Standard mode, no Icon only mode and no Display mode setting exist.

| Content | Maximum width |
|---|---|
| Symbol and one value. The bar style (Section 2.5) selects the value. | 52 pt |

The symbol changes with the state (Section 2.4).

Use monospaced digits. The width must not change when the number changes from `9%` to `10%`. Reserve the width for the longest value.

### 2.3 The notch constraint

On a MacBook with a camera notch, status items share the space to the right of the notch. When the space is full, macOS hides the items that do not fit. The hidden items are behind the notch. macOS does not tell the user.

Requirements:

1. Use the Compact width (Section 2.2) on all displays. TokenBar does not detect the notch.
2. TokenBar does not detect a hidden item and does not change its width automatically.
3. In first run and in Settings, show this tip: "Hold ⌘ and drag TokenBar to the right to keep it visible."
4. Do not use a text label such as "TokenBar" in the menu bar item.

### 2.4 States

| State | Condition | Menu bar item (Serious style) | Symbol candidate |
|---|---|---|---|
| Normal | Primary metric < 80%. | `◐ 62%` | `gauge.with.dots.needle.33percent` or `circle.lefthalf.filled` |
| Warning | Primary metric ≥ 80% and < 100%. | `⚠ 87%` | `exclamationmark.triangle.fill` |
| Limit hit | A limit is at 100%. | `⌛ 1h48` | `hourglass` |
| No data | First run, or no provider found. | `◌` | `circle.dashed` |
| Error | TokenBar cannot read any usage source. | `◐ !` | `exclamationmark.circle` |

Rules:

1. In the Limit hit state, show the time to reset, not the percentage. The percentage is always 100%.
2. If one provider fails and others work, use the Normal state. Show the error in the popover only.
3. Only "cannot read the source" is an error. Quiet logs are normal. If a log has no new lines, show the last value. TokenBar has no Stale state and does not dim values (decided 2026-10-08). Limit values show their age in the popover (Section 3.2).
4. Render all symbols as template images. The menu bar item has no color. The symbol shape is the state signal.
5. The `☕` in this document and in the README is the `cup.and.saucer.fill` symbol. Do not use a color emoji in the menu bar.

Verify each symbol name in the SF Symbols app for macOS 14 before implementation.

### 2.5 Bar style: Funny or Serious

The user selects the bar style in onboarding (Section 4.5). The user can change it in **Settings > General > Bar style**. There is no default. The user must select one.

| Bar style | Normal state | Warning or Limit hit state | Roasts |
|---|---|---|---|
| Funny | Café-index value: `☕ 3.4` | Limit value: `⚠ 87%` or `⌛ 1h48` | On, in the popover and in alerts |
| Serious | Primary metric: `◐ 62%` | Limit value: `⚠ 87%` or `⌛ 1h48` | Off. Alerts have no roast. |

Rules:

1. In the Warning and Limit hit states, both styles show the limit value. The joke never hides a warning (principle 4).
2. The Funny style uses the unit of Section 7.6. The `☕` is the symbol of the selected unit.
3. The Serious style sets **Roasts** and **Café index** to off. The user can turn them on again in Settings.
4. An alert includes a roast only when the bar style is Funny and **Roasts** is on. No separate alert roast setting exists (decided 2026-10-08).

---

## 3. Popover

### 3.1 Layout

- Width: 320 pt. Fixed.
- Height: content height. Maximum 560 pt. If the content is taller, the provider list scrolls.
- Padding: 16 pt on all sides. 12 pt between sections.
- Order from top to bottom: header, provider rows, totals, café-index line, roast, footer.

### 3.2 Provider row

Each enabled provider has one row.

| Element | Rule |
|---|---|
| Name | Provider name, for example "Claude Code". `.headline`. |
| Limit bar | One bar for each limit of the provider. Width 100% of the row. Height 6 pt. |
| Limit label | `62% of 5-hour limit`. Always show the number as text. |
| Reset | `resets in 1 h 48 min`. Use relative time below 24 hours. Use weekday and time above 24 hours: `resets Mon 09:00`. |
| Age | `as of 14:02`. The time when the limit source last reported the value. Show it under each limit. |
| Cost | `≈ €2.10 today`. Add `(API-equivalent)` for subscription providers. |

A provider without a limit source shows tokens and cost only. It has no bar. Example: Claude Code without the status line setup (Section 5).

### 3.3 Normal state

```
┌──────────────────────────────────────────┐
│ TokenBar                                 │
├──────────────────────────────────────────┤
│ Claude Code                              │
│ ███████████████░░░░░░░░░  62% of 5-hour  │
│ resets in 1 h 48 min · as of 14:02       │
│ ██████░░░░░░░░░░░░░░░░░░  24% of weekly  │
│ resets Mon 09:00 · as of 14:02           │
│ ≈ €3.90 today (API-equivalent)           │
│                                          │
│ Codex                                    │
│ ████░░░░░░░░░░░░░░░░░░░░  18% of weekly  │
│ resets Thu 14:00 · as of 13:55           │
│ ≈ €2.20 today (API-equivalent)           │
├──────────────────────────────────────────┤
│ Today ≈ €6.10          Week ≈ €21.80     │
│ ☕ Today = 3.4 cafés con leche            │
│ 🎓 0.04% of your MBA tuition, in tokens   │
├──────────────────────────────────────────┤
│ "The protagonist has 38% of Opus left    │
│  and a 9 AM deadline. Discuss."          │
├──────────────────────────────────────────┤
│ ⚙  ↻                Updated 2 min ago  ⏻ │
└──────────────────────────────────────────┘
```

The popover shows the Today and Week totals side by side (decided 2026-10-08). It has no Today/Week control. Today starts at local midnight. Week is the rolling last 7 days. The café-index line uses today's cost. The tuition line shows in the Funny style only (Section 7.6).

### 3.4 Warning state

```
│ Claude Code                     ⚠ 87%   │
│ ████████████████████░░░░  87% of 5-hour  │  ← bar in orange
│ resets in 42 min                         │
```

Add the `exclamationmark.triangle.fill` symbol next to the provider name. The roast comes from the High usage category (Section 7.3).

### 3.5 Limit hit state

```
│ Claude Code                  ⌛ Limit hit │
│ ████████████████████████  100% of 5-hour │  ← bar in red
│ resets in 1 h 48 min  (at 14:30)         │
│ Codex still available: 82% left this week│
```

Show the absolute reset time next to the relative time. If a different provider has capacity, show one line that names it.

### 3.6 No data state (onboarding)

Section 4 specifies this state.

### 3.7 Error state

```
│ Claude Code                     ⓘ Error │
│ TokenBar cannot read the Claude Code     │
│ logs. The log format possibly changed.   │
│ [Try again]  [Report a problem]          │
```

Rules:

1. Tell the user what failed and what to do. Do not show a stack trace.
2. **Report a problem** opens the feedback Tally form (URL set at alpha) in the browser, not GitHub (decided 2026-10-08). TokenBar sends no data. The user decides what to submit.
3. Never use a roast in an error message.

### 3.8 Data age

TokenBar has no Stale state and no stale banner (Section 2.4, rule 3).

1. If a log has no new lines, show the last value at full opacity.
2. Show the age of each limit value: `as of 14:02` (Section 3.2).
3. If `now` is after the reset time of a limit, show the limit as reset (0%).

### 3.9 Footer

| Element | Symbol | Action |
|---|---|---|
| Settings | `gearshape` | Opens the Settings window. |
| Refresh | `arrow.clockwise` | Reads all providers now. The symbol rotates while the read runs. |
| Last updated | none | `Updated 2 min ago`. Relative time. |
| Quit | `power` | Quits TokenBar. |

Keyboard: `⌘,` opens Settings. `⌘R` refreshes. `⌘Q` quits.

---

## 4. Onboarding and first run

### 4.1 Detection

At first launch, TokenBar looks for Claude Code logs and Codex logs. The TRD specifies the paths.

- If TokenBar finds a provider, show the Normal state with data. Show a one-time welcome line in place of the roast.
- If TokenBar finds no provider, show the No data state.

### 4.2 No data popover

```
┌──────────────────────────────────────────┐
│ Welcome to TokenBar                      │
│                                          │
│ TokenBar found no Claude Code or Codex   │
│ logs on this Mac.                        │
│                                          │
│ ○ I use Claude Code or Codex             │
│   → Run it one time, then click Check.   │
│ ○ I use only ChatGPT or Claude.ai        │
│   → TokenBar cannot read web chat usage  │
│     in v1. Read why.                     │
│                                          │
│ [Check again]                            │
│                                          │
│ Your data stays on this Mac.             │
├──────────────────────────────────────────┤
│ ⚙                                      ⏻ │
└──────────────────────────────────────────┘
```

Many users are not engineers. Do not use the words "CLI", "JSONL" or "endpoint" in onboarding text.

### 4.3 Add an API key (Later)

v1 has no API keys and no API key screen (PRD 7.4). Keep these rules for the Later stage:

1. The user clicks **Add API key**. The Settings window opens on an API keys tab.
2. The user selects OpenAI or Anthropic.
3. The user pastes the key into a secure text field. The field never shows the key again after save.
4. TokenBar tests the key with one usage request. Show a check mark, or show the error in plain words.
5. Tell the user that the key must be an admin key. Link to the provider page that creates admin keys.
6. Tell the user: "TokenBar keeps this key in your Mac's Keychain. It never leaves your Mac except to ask OpenAI or Anthropic for your usage."

### 4.4 Permission prompts

| Prompt | When to ask | Never ask |
|---|---|---|
| Notifications | When the user turns on an alert in Settings, or at the first 95% event with a one-time in-popover question. | At first launch. |
| Launch at login | Show a toggle in the welcome screen. Default on after onboarding (Section 5). The user can turn it off. | As a system dialog at launch. |
| Folder access | Only if the TRD requires a sandbox. Then explain the folder before the open panel shows. | Without an explanation. |

### 4.5 Bar style choice

After detection, the onboarding window asks the user to select a bar style (Section 2.5). Show the two options with a live preview of the menu bar item. The user cannot continue without a selection.

```
┌──────────────────────────────────────────┐
│ How do you want the bar?                 │
│                                          │
│  [ ☕ 3.4 ]  Funny                        │
│  Your spend in cafés con leche. Roasts.  │
│                                          │
│  [ ◐ 62% ]  Serious                      │
│  Numbers only. No jokes.                 │
│                                          │
│  Warnings always show the real number.   │
└──────────────────────────────────────────┘
```

### 4.6 Onboarding window

TokenBar has no Dock icon and no main window. Thus onboarding is a window, not the popover (TRD-T28).

1. The window opens in front of other apps at launch when no bar style is saved.
2. The window opens again at each launch until the user selects a bar style and clicks **Done**. No menu item opens it again. Settings has all the same choices.
3. TokenBar checks only that the log folders exist. It does not read a log in onboarding.

| Step | Content | Condition |
|---|---|---|
| 1. Welcome | Welcome line (Section 4.7). Claude Code and Codex: found or not found. TokenBar cannot see web chat, such as claude.ai or ChatGPT. Your data stays on this Mac. | Always |
| 2. Bar style | Section 4.5. | Always |
| 3. Claude limits | Optional **Connect** (Section 5, D39). The current status line keeps working. Errors show below the button. The user can skip. | Only if TokenBar found Claude Code |
| 4. Keep TokenBar visible | macOS hides the icons near the notch first, without a warning. An open app with many menus pushes icons out. "Hold ⌘ and drag TokenBar to the right, toward the clock." | Always. No Skip button (D40). |
| 5. Done | "Open TokenBar at login" toggle, on by default (Section 4.4). **Done** saves the bar style and turns on launch at login. A login item failure is quiet. Settings shows the real state. | Always |

Target: the user completes all steps in less than two minutes (PRD-US-18).

### 4.7 Onboarding tone

Use the voice of Section 7.1, but keep instructions literal. Humor is allowed in the welcome line only.

```
Welcome to TokenBar. Your AI spending is now a case study. You are the protagonist.
```

---

## 5. Settings window

A standard macOS Settings window with tabs. Use the SwiftUI `Settings` scene. Width 480 pt.

Settings has 3 tabs: General, Alerts and About (decided 2026-10-08). No Providers tab and no Humor tab exist. TokenBar finds Claude Code and Codex automatically.

```
┌─ TokenBar Settings ─────────────────────────────────────┐
│ [General] [Alerts] [About]                              │
├─────────────────────────────────────────────────────────┤
│ Bar style           ( ) Funny  (•) Serious              │
│ Roasts              [ ]                                 │
│ Café index          [ ]                                 │
│ Launch at login     [✓]                                 │
│                                                         │
│ Claude limits (optional)                                │
│ Not connected                               [Connect]   │
│ Your current Claude Code status line keeps working.     │
│ ▸ Show manual setup                                     │
│                                                         │
│ Tip: Hold ⌘ and drag TokenBar to the right.             │
└─────────────────────────────────────────────────────────┘
```

| Tab | Field | Type | Default |
|---|---|---|---|
| General | Bar style | Funny / Serious (Section 2.5) | Selected in onboarding |
| General | Roasts | Toggle | On (Funny), off (Serious) |
| General | Café index | Toggle | On (Funny), off (Serious) |
| General | Launch at login | Toggle | On after onboarding (decided 2026-10-08) |
| General | Claude limits | Status ("Not connected", "Connected. Waiting for the next Claude Code reply.", "Connected · updated 3 min ago"), **Connect** or **Disconnect** button, caption text, "Show manual setup" with the snippet and a **Copy** button (D39) | Not connected |
| General | Command-drag tip | Text (Section 2.3) | — |
| Alerts | 95% alert | Toggle | On |
| Alerts | Limit hit alert | Toggle | On |
| About | Version, license, GitHub link, "Add a unit or a roast" link, **Send feedback** (opens the same Tally form, URL set at alpha), disclaimer | Read-only | — |

Rules:

1. The Claude limits setup is opt-in. TokenBar edits the Claude Code settings file only when the user clicks **Connect** or **Disconnect** (D39, TRD 5.1).
2. Show the caption below the button: the current status line keeps working, open sessions must restart, and Claude Code runs the status line only in trusted folders.
3. Without the setup, the Claude Code row shows tokens and cost only (Section 3.2).
4. TokenBar refreshes every 60 seconds. No refresh setting exists. The popover **Refresh** button reads at once.
5. No currency setting exists. All costs are in EUR (Section 7.6).
6. If the Funny style is on and **Café index** is off, the menu bar item shows the primary metric.

When Roasts and Café index are off, TokenBar shows numbers only. It must work fully.

---

## 6. Notifications

### 6.1 Events

TokenBar sends two notification events only (decided 2026-10-08). It sends no 80% notification and no reset notification. The menu bar item still shows the Warning state from 80% (Section 2.4).

| Event | Condition | Interruption level |
|---|---|---|
| Warning 95% | A limit crosses 95%. | Active |
| Limit hit | A limit reaches 100%. | Active |

### 6.2 Rate limits

1. Send each event a maximum of one time for each limit window.
2. Send a maximum of 3 notifications in 60 minutes, for all providers.
3. If two events occur in 5 minutes, send only the more severe event.
4. Do not send a notification for a limit value that is older than 15 minutes. This rule applies to alerts only. The popover still shows the value with its age (Section 3.8).
5. TokenBar has no quiet hours (decided 2026-10-08). macOS Focus controls the delivery. Do not use the Time Sensitive level.

### 6.3 Copy

The title is literal. The body has the number first, then an optional roast. Add the roast only in the Funny style with **Roasts** on (Section 2.5, rule 4). Else use the body without the roast.

| Event | Title | Body |
|---|---|---|
| Warning 95% | `Claude Code: 95% of 5-hour limit` | `Resets in 38 min. Save the last 5% for the slide that matters.` |
| Limit hit | `Claude Code: limit reached` | `Resets at 14:30. Codex still has 82% left. Or, radical idea: read the case.` |

---

## 7. Humor system

### 7.1 Voice and tone guide

| Rule | Do | Do not |
|---|---|---|
| Dry | Understate. Let the number be the joke. | Use exclamation marks or "LOL". |
| MBA insider | Use case method, cold calls, Section, exhibits, teaching notes, recruiting, consulting and banking. | Explain the joke. |
| Self-aware | Make fun of the user's AI habit and of TokenBar. | Make the user feel stupid. |
| Kind | Roast the behavior. | Roast the body, gender, origin, religion, language, money problems or grades. |
| Anonymous | Use "the protagonist", "you" or a gender-neutral name: Alex, Jordan, Robin, Andrea, Sam. Use they/them. | Name a real person, professor, student or company employee. |
| Short | Maximum 140 characters (decided 2026-10-08, D32). No sentence limit. | Use multi-line jokes. |
| Safe for class | A student can show it on a projector. | Use profanity, alcohol excess or sexual content. |

The case format is the signature: a short situation, a number, and a prompt such as "Discuss." Use "Discuss." in a maximum of 1 in 4 roasts.

**Approval.** The maintainer alone approves each roast before it ships (PRD Q7). TokenBar has one safe roast set. No "spicy" set exists. Public strings do not use the name "IESE". Use "the business school", "your MBA" or "Barcelona" (PRD 13, item 5).

### 7.2 Roast data file

Roasts are data, not code. Store roasts in a data file next to the café-index units. The TRD specifies the format and the path. Each roast has these fields:

| Field | Type | Example |
|---|---|---|
| `id` | string | `high-deadline-01` |
| `text` | string with placeholders | `The protagonist has {remaining}% of {model} left...` |
| `category` | enum (Section 7.3) | `high` |
| `min_percent`, `max_percent` | number, optional | `80`, `99` |
| `hours` | range, optional, local time | `00:00-05:00` |
| `weekdays` | list, optional | `[sat, sun]` |
| `provider` | string, optional | `codex` |
| `locale` | string | `en` |

Placeholders: `{percent}`, `{remaining}`, `{model}`, `{provider}`, `{reset}`, `{time}`, `{cost}`, `{unit_value}`, `{unit_plural}`, `{tuition_percent}`, `{tuition_years}`. If a placeholder has no value, do not select the roast.

### 7.3 Categories and triggers

| Category | Trigger |
|---|---|
| `zero` | No usage today. |
| `low` | Primary limit < 20%, or cost today < €1. |
| `mid` | Primary limit 20–79%. |
| `high` | Primary limit 80–99%. |
| `limit` | A limit is at 100%. |
| `late` | Local time 00:00–05:00 and usage in the last 30 minutes. |
| `weekday` | Monday before 10:00, Friday after 18:00, or Saturday and Sunday. |
| `spend` | Cost today is above €20. |
| `career` | Any time. Recruiting, consulting and banking jokes. |
| `tuition` | 7 or more days of data. Uses the tuition benchmark (Section 7.6). |
| `provider` | A provider-specific condition, for example Codex use only. |

Selection order:

1. Make a list of all roasts that match the current state.
2. If `limit` roasts are in the list, keep only the `limit` roasts.
3. Remove roasts in the rotation history (Section 7.4).
4. Select one roast at random. Categories have no weights (decided 2026-10-08).

### 7.4 Rotation rules

1. Do not repeat a roast within the last 10 roasts shown.
2. Change the roast a maximum of one time in 10 minutes. Keep the same roast when the user opens the popover again in that time.
3. Change the roast immediately when the state changes, for example Normal to Warning.
4. If no roast is available, show no roast line. Do not show an empty quote.
5. Store the rotation history locally. Do not send it off the Mac.

### 7.5 Starter roasts

| ID | Category | Text |
|---|---|---|
| zero-01 | zero | `No tokens today. A rare case of an MBA doing the reading. Teaching note pending.` |
| low-01 | low | `{percent}% of your limit used. The board asks if AI is a strategy or a press release.` |
| low-02 | low | `Low usage. Either you finished the case yourself, or you did not open it. Discuss.` |
| mid-01 | mid | `The protagonist delegated the analysis to an LLM. The LLM delegated it to a sub-agent. A classic consulting pyramid.` |
| mid-02 | mid | `{unit_value} {unit_plural} of compute today. The campus café line is slower, but it does not hallucinate.` |
| mid-03 | mid | `You have generated more slides today than the protagonist will read this term.` |
| high-01 | high | `The protagonist has {remaining}% of {model} left and a 9 AM deadline. Discuss.` |
| high-02 | high | `{percent}% used. This is now a case about the allocation of scarce resources.` |
| high-03 | high | `At this burn rate, the startup in Exhibit 4 would also be out of runway.` |
| high-04 | high | `The cold call is coming. The tokens are not.` |
| limit-01 | limit | `Limit reached. You must now read the case yourself. Resets in {reset}.` |
| limit-02 | limit | `The protagonist is out of tokens and must face the case alone. The teaching note calls this "thinking".` |
| limit-03 | limit | `Exhibit 1: You. Exhibit 2: The limit. Exhibit 3: Reset in {reset}.` |
| late-01 | late | `It is {time}. The protagonist is still prompting. The teaching note calls this "commitment".` |
| late-02 | late | `Late night, high usage, case due tomorrow. Three data points, one pattern. Discuss.` |
| late-03 | late | `Tokens used after midnight do not appear on your transcript. Neither does sleep.` |
| weekday-01 | weekday | `Monday, 8 AM. You are opening the case for the first time. The model already read it twice.` |
| weekday-02 | weekday | `Saturday in Barcelona. Your Claude usage is up. Your beach usage is down. Discuss the trade-off.` |
| weekday-03 | weekday | `Friday evening, tokens still flowing. Either a deadline, or you are the group member who "will just finish the deck".` |
| spend-01 | spend | `Today's API-equivalent cost is {cost}. That is lunch for two at the campus menú del día. The model did not share.` |
| spend-02 | spend | `Your tokens cost more today than your coffee habit this week. Only one of them helps you stay awake in class.` |
| career-01 | career | `The protagonist asked the model to "make it more MECE". The model agreed. Nobody knows what changed.` |
| career-02 | career | `{percent}% utilization. Banking recruiters call this "a great culture fit".` |
| career-03 | career | `You used AI to write a cover letter about your passion for the firm. The firm used AI to read it.` |
| career-04 | career | `The model gave you three frameworks and a 2x2. You are now ready for consulting.` |
| provider-01 | provider | `Codex wrote 400 lines today. Your commit message was "fix".` |
| tuition-01 | tuition | `At your current burn rate, your tokens will cover your MBA tuition in {tuition_years}. The financing office is not impressed.` |
| tuition-02 | tuition | `{tuition_percent} of your MBA tuition, paid in tokens. The ROI case writes itself.` |
| tuition-03 | tuition | `You have now spent {tuition_percent} of an MBA on asking a model to explain the MBA.` |
| provider-02 | provider | `Claude and Codex both used today. Diversified portfolio. Your finance professor would approve of the risk profile, not the cost.` |

The `provider-01` line uses a fixed number as a joke. Do not present it as data. If the TRD supplies a line count, replace the number with a placeholder.

### 7.6 Café index

#### Unit schema

| Field | Type | Rule |
|---|---|---|
| `id` | string | Lowercase, snake case, unique. |
| `singular` | string | Display name for a value of exactly 1. |
| `plural` | string | Display name for all other values. |
| `symbol` | string | SF Symbol name. Used in the menu bar and the popover. |
| `emoji` | string | Used only in notifications and shared text. |
| `price_eur` | number | Community estimate. |
| `price_note` | string | Always "community estimate — verify". |
| `source` | string | Where and when a contributor saw the price. |
| `updated` | date | The date of the last price check. |

Keep Spanish and Catalan names in all locales. "Café con leche" is not translated.

#### Starter units

Café units root in two things only: the MBA tuition fee (as a benchmark) and campus food and drink (decided 2026-10-08). All prices are **community estimates — verify**. They are not official prices. Contributors must update `source` and `updated` with each change.

| id | singular | plural | symbol | emoji | price_eur | source |
|---|---|---|---|---|---|---|
| `cafe_con_leche` | café con leche | cafés con leche | `cup.and.saucer.fill` | ☕ | 1.80 | Typical Barcelona café bar. Verify. |
| `pa_amb_tomaquet` | pa amb tomàquet | pa amb tomàquets | `fork.knife` | 🍅 | 3.50 | Typical Barcelona bar. Verify. |
| `bravas_bar_tomas` | Bar Tomàs patatas bravas | Bar Tomàs patatas bravas | `flame.fill` | 🥔 | 6.00 | Bar Tomàs, Sarrià. Verify. |
| `menu_del_dia` | menú del día | menús del día | `takeoutbag.and.cup.and.straw.fill` | 🍽️ | 15.00 | Typical Barcelona lunch menu. Verify. |

With these units, the range `0.5 ≤ value ≤ 20` covers a cost from €0.90 to €300. TokenBar has no other units in v1. Contributors can add a food or drink unit by pull request. The maintainer approves it.

#### The tuition benchmark

Tuition is not a café unit. A daily cost is always a very small part of tuition, so a unit value is never in range. TokenBar uses tuition as a **benchmark** for total spend over time.

The data file has one tuition entry:

| Field | Value |
|---|---|
| `id` | `iese_mba_tuition` |
| `label` | MBA tuition. The UI shows this text. The `source` field names the school and the fee page. |
| `price_eur` | Community estimate. Use the published program fee. Verify. |
| `source`, `updated` | Same rules as café units. |

TokenBar calculates two values from it:

| Value | Formula | Example |
|---|---|---|
| `{tuition_percent}` | Spend since first launch ÷ tuition × 100 | `0.04%` |
| `{tuition_years}` | Years to reach tuition at the average daily spend of the last 30 days | `412 years` |

Rules:

1. Show the tuition benchmark in the popover under the café-index line, in the Funny style only. Format: `🎓 {tuition_percent} of your {label}, in tokens`. Example: `🎓 0.04% of your MBA tuition, in tokens`. Code takes the label from the data file. Code has no hardcoded "IESE" string.
2. Use it in roasts with the `tuition` category (Section 7.3).
3. The joke is about the tokens, not about the cost of tuition. Do not suggest that the user cannot pay tuition.
4. If there are less than 7 days of data, do not show `{tuition_years}`.

Note: the plural of `bravas_bar_tomas` is the same as the singular. This is correct.

#### Unit selection rules

The popover shows one café-index line with one unit (decided 2026-10-08). No second unit line and no "Preferred unit" setting exist.

1. Use the cost in EUR. The cost engine converts USD with the fixed rate in `prices.json` (TRD 6). The rate is a community estimate.
2. Calculate `value = cost_eur / price_eur` for each unit.
3. Keep the units with `0.5 ≤ value ≤ 20`.
4. Select the in-range unit with `value` closest to 3. Keep this unit for the full day, to prevent flicker.
5. If no unit is in range and cost is below the range, use the unit with the lowest price. Show two decimal places, for example `0.12 cafés con leche`.
6. If no unit is in range and cost is above the range, use the unit with the highest price.
7. If cost is 0, show no café-index line. Show the `zero` roast.

Format: one decimal place below 10, no decimal places at 10 and above. Use `singular` only when the displayed value is exactly `1`. Always show the real cost on the same row in the popover.

---

### 7.7 Share card (v0.2)

The share card lets the user post the joke in a class chat. It is the main word-of-mouth feature.

1. The popover footer has a **Share** button (`square.and.arrow.up`).
2. **Share** copies an image and a text to the clipboard. The user pastes them into WhatsApp or LinkedIn.
3. Render the image with SwiftUI `ImageRenderer`. Do not add a dependency.
4. The card contains: today's café-index value, the tuition benchmark (if available), the current roast and the text "TokenBar · github.com/patronofalltrades/TokenBar".
5. The card does not contain the user name, file paths, project names or prompt content. It shows model names only if the roast uses `{model}`.
6. Show a one-line confirmation in the popover: "Copied. Paste it in your Section chat."
7. In the Serious style, the card shows the numbers only.

```
┌──────────────────────────────┐
│  ☕ 3.4 cafés con leche today │
│  🎓 0.04% of MBA tuition      │
│                              │
│  "The cold call is coming.   │
│   The tokens are not."       │
│                              │
│  TokenBar · github.com/…     │
└──────────────────────────────┘
```

## 8. Visual style

### 8.1 Color

Use semantic system colors only. They adapt to light mode, dark mode and Increase Contrast.

| Use | Color |
|---|---|
| Primary text | `Color.primary` |
| Secondary text, reset times | `Color.secondary` |
| Bar track | `Color.secondary.opacity(0.2)` |
| Bar fill below 80% | `Color.accentColor` |
| Bar fill 80–99% | `Color.orange` |
| Bar fill 100% | `Color.red` |
| Roast text | `Color.secondary` |
| Menu bar item | Template image. No color. |

Do not use a brand color for a provider. Do not use green for "good". Low usage is normal, not a success.

### 8.2 Typography

| Element | Style |
|---|---|
| Menu bar text | System menu bar font. `.monospacedDigit()`. |
| Provider name | `.headline` |
| Limit label, cost | `.body`, `.monospacedDigit()` |
| Reset time | `.caption`, secondary |
| Totals | `.title3`, `.monospacedDigit()` |
| Café-index line | `.callout` |
| Roast | `.callout`, italic, in typographic quotes |
| Footer | `.caption` |

Use the system font (SF Pro) only. Do not bundle a font.

### 8.3 Iconography

1. Use SF Symbols only. Do not add custom icons in v1, except the app icon.
2. Use `.hierarchical` rendering in the popover. Use template rendering in the menu bar.
3. Use the same symbol for the same meaning everywhere. Section 2.4 and Section 3.9 list the symbols.
4. The app icon is a separate design task. It is not in this document.

### 8.4 Motion

1. Animate a limit bar width change with `.easeOut` in 0.25 s.
2. Rotate the refresh symbol while a read runs.
3. Cross-fade the roast when it changes, 0.2 s.
4. Do not animate the menu bar item.
5. When **Reduce Motion** is on, remove all animation. Change values immediately.

---

## 9. Accessibility

### 9.1 VoiceOver

| Element | Label example |
|---|---|
| Menu bar item, Normal | "TokenBar. Claude Code, 62 percent of 5-hour limit. Today, 3.4 cafés con leche." |
| Menu bar item, Limit hit | "TokenBar. Claude Code limit reached. Resets in 1 hour 48 minutes." |
| Menu bar item, No data | "TokenBar. No usage data. Click to set up." |
| Limit bar | "Claude Code 5-hour limit, 62 percent used, resets in 1 hour 48 minutes." Use `.accessibilityValue`. |
| Café-index line | "Today's cost, about 6 euros 10, equals 3.4 cafés con leche." |
| Limit age | "As of 14:02." Add it after the limit bar label. |
| Roast | "Roast:" then the text. |
| Footer buttons | "Settings", "Refresh", "Quit TokenBar". |

Combine each provider row into one accessibility element. Give the popover a logical order from top to bottom.

### 9.2 Text size

macOS 14 has no system-wide Dynamic Type for apps. Requirements:

1. Use text styles, not fixed point sizes, in the popover.
2. The popover must work at the largest text size that the user can set in Accessibility settings. Test at this size.
3. The menu bar item uses the system menu bar font. Do not scale it.

### 9.3 Color is never the only signal

1. Each bar shows its percentage as text.
2. The Warning and Limit hit states use a different symbol shape, not only a color.
3. Test all states with **Increase Contrast** and **Differentiate Without Color** on.

### 9.4 Keyboard

The user can reach all controls in the popover and in Settings with the keyboard. Show a focus ring on each control.

### 9.5 Localization readiness

1. v1 is English only (decided 2026-10-08). Spanish comes after the launch.
2. Put all UI strings in a String Catalog. Do not concatenate strings in code.
3. Use `{placeholders}` in roasts and alerts, not string order.
4. Format numbers, currency, dates and times with the user's locale. The currency is always EUR. Spanish uses a comma for decimals.
5. Write roasts in each language. Do not machine-translate roasts. A joke must work in the target language.
6. When Spanish comes, allow 30% more text width. Test the popover with long strings.

---

## 10. Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Resolved 2026-10-08: no automatic notch or hidden-item detection. Compact is the only mode (Section 2.3). | — |
| 2 | Does `MenuBarExtra` support the fixed label width? Or does TokenBar need `NSStatusItem`? | TRD |
| 3 | Resolved 2026-10-08: one fixed USD to EUR rate in `prices.json`, with a date and the note "community estimate". No network source (PRD Q3). | — |
| 4 | Resolved 2026-10-08: EUR everywhere. No currency setting (PRD Q3). | — |
| 5 | Resolved 2026-10-08: "Today" starts at local midnight. "Week" is the rolling last 7 days (PRD Section 1). | — |
| 6 | Does each limit have its own 95% and limit-hit alerts, or do alerts use only the highest limit? | PRD |
| 7 | Resolved 2026-10-08: the maintainer alone approves each roast. One safe set only (Section 7.1, PRD Q7). A review checklist in CONTRIBUTING is still useful. | — |
| 8 | Resolved 2026-10-08: tuition is a benchmark, not a café unit (Section 7.6). | — |
| 9 | Resolved 2026-10-08: the share card is a v0.2 Must (Section 7.7). | — |
| 10 | Future idea, not v1: a mood mascot in the popover that reacts to the usage level. | Later |
| 11 | Future idea, not v1: an opt-in class leaderboard (README roadmap). It needs its own privacy design. | Later |
