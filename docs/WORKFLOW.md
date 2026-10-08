# TokenBar Workflow

This file tells how work moves from a Linear issue to a merged pull request. [AGENTS.md](../AGENTS.md) has the full rules. If this file and AGENTS.md do not agree, AGENTS.md has priority.

## 1. Flow

1. **Issue.** The maintainer creates a Linear issue in the TokenBar project (team key `IES`). The issue title has the task ID, for example `TRD-T05`.
2. **Claim.** An agent from any provider claims the issue. The agent sets the issue to **In Progress** and adds a comment with its agent name and model (AGENTS.md 6.1).
3. **Branch.** The agent makes a branch `<agent>/<issue-id>-<slug>` in its own git worktree. Example: `claude/IES-187-claude-code-provider` (AGENTS.md 6.2).
4. **Skills.** The agent uses `caveman` for chat and `ponytail` (level `full`) for code (AGENTS.md 3).
5. **Pull request.** The agent opens a pull request with tests. The pull request links the issue and meets the definition of done (AGENTS.md 7).
6. **Pre-review.** Claude reviews the pull request: a code review and a `ponytail-review`. The author fixes the findings.
7. **CI.** CI must be green: `swift build` and `swift test` (TRD 13).
8. **Merge.** The maintainer merges. An agent never merges its own pull request.
9. **Done.** The maintainer sets the Linear issue to **Done**.

When an agent stops work, it writes a handoff comment in Linear. Use the format in AGENTS.md 6.4.

## 2. Task owners

Tasks are split by layer (decided 2026-10-08). The layers share few files, so agents can work in parallel.

| Layer | Owner | Tasks |
|---|---|---|
| Core, providers and release | Claude | TRD-T01, T02, T03, T04, T05, T07, T10, T12, T13, T26 |
| Humor and UI | Agents from other providers | TRD-T06, T08, T09, T14, T15, T16, T27 |
| Remaining v1.0 tasks | Assigned later | TRD-T11, T18, T23 |
| Later | Not assigned | TRD-T17, T19, T20, T21, T22, T24 |

## 3. Wave order

A wave is a set of tasks that can run at the same time. Start a wave only when the tasks that it depends on are merged. [TRD Section 14](TRD.md#14-work-breakdown) has the dependencies and the acceptance criteria. If this table and the TRD do not agree, the TRD has priority.

| Wave | Tasks | Stage |
|---|---|---|
| 1 | T01 | v0.1 |
| 2 | T02, T03, T06, T10, T14 | v0.1 |
| 3 | T04, T05, T07, T12, T26 | v0.1 (T12: v0.2) |
| 4 | T08, T09, T13, T15, T16 | v0.1 (T13, T15, T16: v0.2) |
| 5 | T27 | v0.2 |
| 6 | T18, then T23 | v1.0 |
| After the alpha | T11, only if the maintainer approves | v1.0 |

## 4. Time budget

The maintainer has 3 to 5 hours a week (PRD R11). Reviews and merges use most of this time. Plan about 2 waves a week. If a wave is late, cut Should stories first (PRD R11).
