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
| Provider | One usage source: Claude Code, Codex, OpenAI API or Anthropic API. |
| Limit | A usage cap with a reset time, for example the Claude 5-hour limit. |
| Primary metric | The single number in the menu bar item. |
| Cost | Real API cost, or API-equivalent cost for a subscription. |
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

The menu bar item shows one primary metric. The user selects the primary metric in **Settings > General > Menu bar shows**.

| Option | Example | Rule |
|---|---|---|
| Auto (default) | `62%` | The highest limit percentage of all providers. This is the limit that is closest to a reset problem. |
| A specific limit | `62%` | One provider limit, for example "Claude Code 5-hour". |
| Today's cost | `€3.40` | The sum of cost for today, all providers. |
| Today's café index | `3.4 ☕` | Today's cost in the selected unit. |

If no provider has a limit, Auto uses today's cost.

The user can also set **Show café index next to the number** (default: on in Standard mode). This adds today's café-index value after the primary metric.

### 2.2 Display modes and width

| Mode | Content | Maximum width |
|---|---|---|
| Standard | Symbol, primary metric, café index | 90 pt |
| Compact | Symbol and one value. The bar style (Section 2.5) selects the value. | 52 pt |
| Icon only | Symbol only | 22 pt |

The symbol in all modes changes with the state (Section 2.4). The Icon only mode uses the state symbol as the only signal. The popover shows the number.

Use monospaced digits. The width must not change when the number changes from `9%` to `10%`. Reserve the width for the longest value in the mode.

### 2.3 The notch constraint

On a MacBook with a camera notch, status items share the space to the right of the notch. When the space is full, macOS hides the items that do not fit. The hidden items are behind the notch. macOS does not tell the user.

Requirements:

1. Use Compact mode as the default on a Mac with a notch. Use Standard mode as the default on other displays.
2. Detect a notch with `NSScreen.auxiliaryTopLeftArea`. The TRD specifies the detection method.
3. If TokenBar detects that its item is hidden, change to the next smaller mode. Do this one time per launch. Do not change the mode again if the user selected a mode manually.
4. In first run, show this tip: "Hold ⌘ and drag TokenBar to the right to keep it visible."
5. Do not use a text label such as "TokenBar" in the menu bar item.

### 2.4 States

| State | Condition | Standard | Compact | Symbol candidate |
|---|---|---|---|---|
| Normal | Data is current. Primary metric < 80%. | `◐ 62% · 3.4 ☕` | `◐ 62%` | `gauge.with.dots.needle.33percent` or `circle.lefthalf.filled` |
| Warning | Primary metric ≥ 80% and < 100%. | `⚠ 87% · 6.1 ☕` | `⚠ 87%` | `exclamationmark.triangle.fill` |
| Limit hit | A limit is at 100%. | `⌛ 1h 48m` | `⌛ 1h48` | `hourglass` |
| No data | First run, or no provider found. | `◌` | `◌` | `circle.dashed` |
| Error | All providers failed to read. | `◐ !` | `◐ !` | `exclamationmark.circle` |
| Stale | Newest data is older than 15 minutes. | `◐ 62%` (dimmed) | `◐ 62%` (dimmed) | Normal symbol, 50% opacity |

Rules:

1. In the Limit hit state, show the time to reset, not the percentage. The percentage is always 100%.
2. If one provider fails and others work, use the Normal state. Show the error in the popover only.
3. In the Stale state, dim the number and the symbol. Do not hide the number.
4. Render all symbols as template images. The menu bar item has no color. The symbol shape is the state signal.
5. The `☕` in this document and in the README is the `cup.and.saucer.fill` symbol. Do not use a color emoji in the menu bar.

Verify each symbol name in the SF Symbols app for macOS 14 before implementation.

### 2.5 Bar style: Funny or Serious

The user selects the bar style in onboarding (Section 4.5). The user can change it in **Settings > General > Bar style**. There is no default. The user must select one.

| Bar style | Compact, Normal state | Compact, Warning or Limit hit state | Standard mode |
|---|---|---|---|
| Funny | Café-index value: `☕ 3.4` | Limit value: `⚠ 87%` or `⌛ 1h48` | Primary metric and café index |
| Serious | Primary metric: `◐ 62%` | Limit value: `⚠ 87%` or `⌛ 1h48` | Primary metric only. Roasts off. |

Rules:

1. In the Warning and Limit hit states, both styles show the limit value. The joke never hides a warning (principle 4).
2. The Funny style uses the unit of Section 7.6. The `☕` is the symbol of the selected unit.
3. The Serious style sets **Roasts** and **Café index** to off. The user can turn them on again in Settings.

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
| Cost | `€2.10 today`. Add `(API-equivalent)` for subscription providers. |

An API provider without a limit shows cost only. It has no bar.

### 3.3 Normal state

```
┌──────────────────────────────────────────┐
│ TokenBar                     Today  Week │  ← segmented control
├──────────────────────────────────────────┤
│ Claude Code                              │
│ ███████████████░░░░░░░░░  62% of 5-hour  │
│ resets in 1 h 48 min                     │
│ ██████░░░░░░░░░░░░░░░░░░  24% of weekly  │
│ resets Mon 09:00                         │
│ €2.10 today (API-equivalent)             │
│                                          │
│ Codex                                    │
│ ████░░░░░░░░░░░░░░░░░░░░  18% of weekly  │
│ resets Thu 14:00                         │
│                                          │
│ OpenAI API                    €1.30 today│
├──────────────────────────────────────────┤
│ Today  €3.40        This week  €21.80    │
│ ☕ Today = 3.4 cafés con leche            │
│          = 0.6 Bar Tomàs patatas bravas  │
├──────────────────────────────────────────┤
│ "The protagonist has 38% of Opus left    │
│  and a 9 AM deadline. Discuss."          │
├──────────────────────────────────────────┤
│ ⚙  ↻                Updated 2 min ago  ⏻ │
└──────────────────────────────────────────┘
```

The **Today / Week** control changes the totals and the café-index line. It does not change the limit bars.

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
│ Codex still available: 18% of weekly     │
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
2. **Report a problem** opens a prefilled GitHub issue in the browser. The issue includes the app version and macOS version only. It does not include usage data.
3. Never use a roast in an error message.

### 3.8 Stale state

```
│ ⏱ Data is 23 min old. Last update 14:02. [Refresh] │
```

Show this banner below the header. Keep the old numbers visible and dimmed.

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
│ ○ I use the OpenAI or Anthropic API      │
│   → [Add API key]                        │
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

### 4.3 Add an API key

1. The user clicks **Add API key**. The Settings window opens on the Providers tab.
2. The user selects OpenAI or Anthropic.
3. The user pastes the key into a secure text field. The field never shows the key again after save.
4. TokenBar tests the key with one usage request. Show a check mark, or show the error in plain words.
5. Tell the user that the key must be an admin key. Link to the provider page that creates admin keys.
6. Tell the user: "TokenBar keeps this key in your Mac's Keychain. It never leaves your Mac except to ask OpenAI or Anthropic for your usage."

### 4.4 Permission prompts

| Prompt | When to ask | Never ask |
|---|---|---|
| Notifications | When the user enables alerts, or at the first 80% event with a one-time in-popover question. | At first launch. |
| Open at login | Show a toggle in the welcome screen. Default off. | As a system dialog at launch. |
| Folder access | Only if the TRD requires a sandbox. Then explain the folder before the open panel shows. | Without an explanation. |

### 4.5 Bar style choice

After detection, the welcome popover asks the user to select a bar style (Section 2.5). Show the two options with a live preview of the menu bar item.

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

### 4.6 Onboarding tone

Use the voice of Section 7.1, but keep instructions literal. Humor is allowed in the welcome line only.

```
Welcome to TokenBar. Your AI spending is now a case study. You are the protagonist.
```

---

## 5. Settings window

A standard macOS Settings window with tabs. Use the SwiftUI `Settings` scene. Width 480 pt.

```
┌─ TokenBar Settings ─────────────────────────────────────┐
│ [General] [Providers] [Alerts] [Humor] [About]          │
├─────────────────────────────────────────────────────────┤
│ Menu bar shows      [ Auto (closest limit)        ▾ ]   │
│ Display mode        [ Compact ▾ ]  (notch detected)     │
│ Café index in bar   [✓]                                 │
│ Currency            [ EUR ▾ ]                           │
│ Refresh every       [ 2 min ▾ ]                         │
│ Open at login       [ ]                                 │
└─────────────────────────────────────────────────────────┘
```

| Tab | Field | Type | Default |
|---|---|---|---|
| General | Bar style | Funny / Serious (Section 2.5) | Selected in onboarding |
| General | Menu bar shows | Picker (Section 2.1) | Auto |
| General | Display mode | Standard / Compact / Icon only | Compact with notch, else Standard |
| General | Café index in bar | Toggle | On |
| General | Currency | EUR / USD | EUR |
| General | Refresh every | 1, 2, 5, 15 min | 2 min |
| General | Open at login | Toggle | Off |
| Providers | Claude Code | Toggle and status ("Found", "Not found") | On if found |
| Providers | Codex | Toggle and status | On if found |
| Providers | OpenAI API | Key field, Test button, Remove button | Off |
| Providers | Anthropic API | Key field, Test button, Remove button | Off |
| Alerts | Alerts on | Toggle | On |
| Alerts | Thresholds | Toggles: 80%, 95%, limit hit, reset | All on |
| Alerts | Quiet hours | Toggle, start time, end time | Off, 00:00–08:00 |
| Alerts | Roast in alerts | Toggle | On |
| Humor | Roasts | Toggle | On |
| Humor | Café index | Toggle | On |
| Humor | Preferred unit | Picker: Auto or one unit | Auto |
| Humor | Late-night roasts | Toggle | On |
| About | Version, license, GitHub link, "Add a unit or a roast" link, disclaimer | Read-only | — |

When the user turns off Roasts and Café index, TokenBar shows numbers only. This is "serious mode". It must work fully.

---

## 6. Notifications

### 6.1 Events

| Event | Condition | Interruption level |
|---|---|---|
| Warning 80% | A limit crosses 80%. | Passive |
| Warning 95% | A limit crosses 95%. | Active |
| Limit hit | A limit reaches 100%. | Active |
| Reset | A limit resets after a Limit hit event. | Passive |

Do not send a Reset notification if the limit did not hit 100% in that window.

### 6.2 Rate limits

1. Send each event a maximum of one time for each limit window.
2. Send a maximum of 3 notifications in 60 minutes, for all providers.
3. If two events occur in 5 minutes, send only the more severe event.
4. Do not send a notification for data that is older than 15 minutes.
5. In quiet hours, hold Passive events. Deliver Limit hit events only. Drop held events that are no longer true.
6. Obey macOS Focus modes. Do not use the Time Sensitive level.

### 6.3 Copy

The title is literal. The body has the number first, then an optional roast. If **Roast in alerts** is off, use the body without the roast.

| Event | Title | Body |
|---|---|---|
| Warning 80% | `Claude Code: 80% of 5-hour limit` | `Resets in 2 h 10 min. Pace yourself, protagonist.` |
| Warning 95% | `Claude Code: 95% of 5-hour limit` | `Resets in 38 min. Save the last 5% for the slide that matters.` |
| Limit hit | `Claude Code: limit reached` | `Resets at 14:30. Codex still has 82% left. Or, radical idea: read the case.` |
| Reset | `Claude Code: limit reset` | `Back to 0%. The protagonist returns for the second half.` |

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
| Short | Maximum 140 characters. Two sentences maximum. | Use multi-line jokes. |
| Safe for class | A student can show it on a projector. | Use profanity, alcohol excess or sexual content. |

The case format is the signature: a short situation, a number, and a prompt such as "Discuss." Use "Discuss." in a maximum of 1 in 4 roasts.

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
| `spend` | Cost today is in the top unit range (Section 7.6) or above €20. |
| `career` | Any time. Low weight. Recruiting, consulting and banking jokes. |
| `tuition` | 7 or more days of data. Low weight. Uses the tuition benchmark (Section 7.6). |
| `provider` | A provider-specific condition, for example Codex use only. |

Selection order:

1. Make a list of all roasts whose conditions are true.
2. If `limit` roasts are in the list, select only from `limit`.
3. Else give `high`, `late` and `spend` a weight of 3. Give all other categories a weight of 1.
4. Remove roasts in the rotation history (Section 7.4).
5. Select one roast at random by weight.

### 7.4 Rotation rules

1. Do not repeat a roast within the last 15 roasts shown.
2. Do not show two roasts from the same category one after the other, except `limit`.
3. Change the roast a maximum of one time in 10 minutes. Keep the same roast when the user opens the popover again in that time.
4. Change the roast immediately when the state changes, for example Normal to Warning.
5. If no roast is available, show no roast line. Do not show an empty quote.
6. Store the rotation history locally. Do not send it off the Mac.

### 7.5 Starter roasts

| ID | Category | Text |
|---|---|---|
| zero-01 | zero | `No tokens today. A rare case of an MBA doing the reading. Teaching note pending.` |
| low-01 | low | `{percent}% of your limit used. The board asks if AI is a strategy or a press release.` |
| low-02 | low | `Low usage. Either you finished the case yourself, or you did not open it. Discuss.` |
| mid-01 | mid | `The protagonist delegated the analysis to an LLM. The LLM delegated it to a sub-agent. A classic consulting pyramid.` |
| mid-02 | mid | `{unit_value} {unit_plural} of compute today. The IESE café line is slower, but it does not hallucinate.` |
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
| spend-01 | spend | `Today's API-equivalent cost is {cost}. Your landlord in Sant Gervasi would like to discuss the business model.` |
| spend-02 | spend | `Your token spend is now higher than the case packet. Unlike the case packet, someone actually read it.` |
| career-01 | career | `The protagonist asked the model to "make it more MECE". The model agreed. Nobody knows what changed.` |
| career-02 | career | `{percent}% utilization. Banking recruiters call this "a great culture fit".` |
| career-03 | career | `You used AI to write a cover letter about your passion for the firm. The firm used AI to read it.` |
| career-04 | career | `The model gave you three frameworks and a 2x2. You are now ready for consulting.` |
| provider-01 | provider | `Codex wrote 400 lines today. Your commit message was "fix".` |
| tuition-01 | tuition | `At your current burn rate, your tokens will cover your IESE tuition in {tuition_years}. The financing office is not impressed.` |
| tuition-02 | tuition | `{tuition_percent} of your IESE tuition, paid in tokens. The ROI case writes itself.` |
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

All prices are **community estimates — verify**. They are not official prices. Contributors must update `source` and `updated` with each change.

| id | singular | plural | symbol | emoji | price_eur | source |
|---|---|---|---|---|---|---|
| `cafe_con_leche` | café con leche | cafés con leche | `cup.and.saucer.fill` | ☕ | 1.80 | Typical Barcelona café bar. Verify. |
| `cana` | caña | cañas | `mug.fill` | 🍺 | 3.00 | Typical Barcelona bar. Verify. |
| `pa_amb_tomaquet` | pa amb tomàquet | pa amb tomàquets | `fork.knife` | 🍅 | 3.50 | Typical Barcelona bar. Verify. |
| `bravas_bar_tomas` | Bar Tomàs patatas bravas | Bar Tomàs patatas bravas | `flame.fill` | 🥔 | 6.00 | Bar Tomàs, Sarrià. Verify. |
| `case_packet` | case packet | case packets | `doc.text.fill` | 📄 | 10.00 | Typical single-case price. Verify. |
| `t_casual` | T-casual metro card | T-casual metro cards | `tram.fill` | 🚇 | 12.00 | TMB, 10 trips, zone 1. Verify. |
| `menu_del_dia` | menú del día | menús del día | `takeoutbag.and.cup.and.straw.fill` | 🍽️ | 15.00 | Typical Barcelona lunch menu. Verify. |
| `ryanair_weekend` | Ryanair weekend escape | Ryanair weekend escapes | `airplane` | ✈️ | 40.00 | Return flight from BCN, booked early. Verify. |
| `bcn_room_month` | month of Barcelona room rent | months of Barcelona room rent | `house.fill` | 🏠 | 750.00 | Shared flat room near IESE. Verify. |

#### The tuition benchmark

IESE tuition is not a café unit. A daily cost is always a very small part of tuition, so a unit value is never in range. TokenBar uses tuition as a **benchmark** for total spend over time.

The data file has one tuition entry:

| Field | Value |
|---|---|
| `id` | `iese_mba_tuition` |
| `label` | IESE MBA tuition |
| `price_eur` | Community estimate. Use the published program fee. Verify. |
| `source`, `updated` | Same rules as café units. |

TokenBar calculates two values from it:

| Value | Formula | Example |
|---|---|---|
| `{tuition_percent}` | Spend since first launch ÷ tuition × 100 | `0.04%` |
| `{tuition_years}` | Years to reach tuition at the average daily spend of the last 30 days | `412 years` |

Rules:

1. Show the tuition benchmark in the popover under the café-index line, in the Funny style only. Example: `🎓 0.04% of your IESE tuition, paid in tokens.`
2. Use it in roasts with the `tuition` category (Section 7.3).
3. The joke is about the tokens, not about the cost of tuition. Do not suggest that the user cannot pay tuition.
4. If there are less than 7 days of data, do not show `{tuition_years}`.

Note: the plural of `bravas_bar_tomas` is the same as the singular. This is correct.

#### Unit selection rules

1. Convert cost to EUR with the rate in the data file. Mark this rate as a community estimate.
2. Calculate `value = cost_eur / price_eur` for each unit.
3. Keep the units with `0.5 ≤ value ≤ 20`.
4. If the user selected a preferred unit and it is in range, use it.
5. Else select the in-range unit with `value` closest to 3. Keep this unit for the full day, to prevent flicker.
6. If no unit is in range and cost is below the range, use the unit with the lowest price. Show two decimal places, for example `0.12 cafés con leche`.
7. If no unit is in range and cost is above the range, use the unit with the highest price.
8. The popover shows a second line with a different in-range unit, if one exists.
9. If cost is 0, show no café-index line. Show the `zero` roast.

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
│  🎓 0.04% of IESE tuition     │
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
| Stale content | Current color at 50% opacity |
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
| Menu bar item, Stale | Normal label, then "Data is 23 minutes old." |
| Limit bar | "Claude Code 5-hour limit, 62 percent used, resets in 1 hour 48 minutes." Use `.accessibilityValue`. |
| Café-index line | "Today's cost, 3 euros 40, equals 3.4 cafés con leche." |
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

1. English is the v1 language. Spanish is the next language.
2. Put all UI strings in a String Catalog. Do not concatenate strings in code.
3. Use `{placeholders}` in roasts and alerts, not string order.
4. Format numbers, currency, dates and times with the user's locale. Spanish uses a comma for decimals.
5. Write roasts in each language. Do not machine-translate roasts. A joke must work in the target language.
6. Allow 30% more text width for Spanish. Test the popover with long strings.

---

## 10. Open questions

| # | Question | Owner |
|---|---|---|
| 1 | Can TokenBar reliably detect that macOS hid its item behind the notch? If not, remove automatic mode change (Section 2.3, rule 3). | TRD |
| 2 | Does `MenuBarExtra` support the custom label width and dimming? Or does TokenBar need `NSStatusItem`? | TRD |
| 3 | Which USD to EUR rate does TokenBar use? A fixed rate in the data file, or a rate from a network source? A network source needs approval (AGENTS.md, Section 9). | Maintainer |
| 4 | Is the default currency EUR or USD? Providers bill in USD. IESE students think in EUR. | Maintainer |
| 5 | Does "This week" start on Monday, or is it a rolling 7 days? Does "Today" start at local midnight? | PRD |
| 6 | Does each limit have its own threshold, or does Auto mode use only the highest limit for alerts? | PRD |
| 7 | Who reviews new community roasts for the voice rules? Define a review checklist in CONTRIBUTING. | Maintainer |
| 8 | Resolved 2026-10-08: tuition is a benchmark, not a café unit (Section 7.6). | — |
| 9 | Resolved 2026-10-08: the share card is a v0.2 Must (Section 7.7). | — |
| 10 | Future idea, not v1: a mood mascot in the popover that reacts to the usage level. | Later |
| 11 | Future idea, not v1: an opt-in class leaderboard (README roadmap). It needs its own privacy design. | Later |
