# Class Leaderboard Roadmap

| Field | Value |
|---|---|
| Status | Proposal. Roadmap only. |
| Scope | v1.1 or Later |
| Date | 2026-10-10 |
| Related | [PRD](PRD.md), [DRD](DRD.md), [TRD](TRD.md), [AGENTS.md](../AGENTS.md) |

## 1. Vision

An optional class leaderboard ranks classmates by the three TokenBar indexes.

- Café Index. The ranking uses cafés con leche.
- Water Footprint. The ranking uses litres of water.
- Tuition Meter. The ranking uses the share of the MBA tuition.

Each index has its own ranking. The feature is opt-in.

## 2. Principles

These rules come from existing decisions. Do not break them.

1. No data leaves the Mac unless the user opts in (AGENTS 5.5, TRD 1.3).
2. The user submits daily totals only (TRD 5). The submission has no model names, no project paths and no prompt content.
3. Each user appears under a pseudonym. No real name.
4. The user can delete the handle and the data at any time.
5. The leaderboard needs one new network host. The host needs maintainer approval (AGENTS 9).
6. Public text stays neutral (D25). Use "class", "Section B" and "your MBA". Do not use the school name.

## 3. Phases

### Phase 0 — Design and decisions

- Define the pseudonym model. Use a handle and an optional Section.
- Define the totals for each index. Use the same values as the popover.
- Choose a ranking rule for each index. Use the daily total, the weekly total or the running total.
- Choose the backend. Use a small class server or a managed table service.
- Write the privacy design. Cover consent, retention and deletion.
- Record each decision in [DECISIONS.md](DECISIONS.md).

### Phase 1 — Opt-in submitter

- Add a Leaderboard section to Settings (DRD 5).
- The section has a toggle, a handle and a Section.
- Aggregate the three daily totals locally. Send no other field.
- Submit one time each day. Retry on failure.
- Build against a stub server. Do nothing when the toggle is off.

### Phase 2 — Server

- Get host approval. Add the host to the HTTP allowlist (TRD-T18).
- Build the ingest endpoint. Store the handle, the Section, the totals and the date.
- Build the rankings API for each index.
- Build a simple public page. Show each ranking.
- Build the deletion endpoint.

### Phase 3 — Leaderboard in TokenBar

- Add a leaderboard line to the popover (DRD 3).
- Show "You rank #14 of 89 in Section B" for each index.
- Add rank roasts. The maintainer approves each roast (D24).
- Reuse the share card for "My rank" (DRD 7.7).

### Phase 4 — Class launch

- Add the leaderboard opt-in to onboarding (DRD 4).
- Launch in one Section first. Then launch in the class.
- Add a weekly view. Use "This week's burn".

### Phase 5 — Optional extras

- Add an overall blended score.
- Add Section averages.
- Add a seasonal board for each term.
- Keep the opt-out at any time and the data deletion request.

## 4. Open questions

| ID | Question | Owner |
|---|---|---|
| LQ1 | Who hosts the server? Who pays for it? | Maintainer |
| LQ2 | Which index is the primary ranking? | Maintainer |
| LQ3 | Does the handle need verification? | Maintainer |
| LQ4 | How long does the server keep the data? | Maintainer |
| LQ5 | Does the leaderboard need a Section filter? | Maintainer |

## 5. Scope cuts

These items are not in the first version. Add them only when a user asks.

- No real names and no email sign-in.
- No blended score.
- No mobile app. Use a simple page only.

## 6. Related documents

- PRD: the class leaderboard is a "Later" item.
- DRD: the class leaderboard is open question 11.
- TRD: the class leaderboard needs a backend and a privacy design.
