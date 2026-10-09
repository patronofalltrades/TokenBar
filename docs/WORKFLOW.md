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
8. **Merge.** The Claude coordinator merges when three checks pass: its pre-review, green CI, and a wave integration check (all open branches of the wave merged together, then `swift build` and `swift test`). An agent never merges its own pull request. The maintainer can revert any merge (decided 2026-10-09, D36).
9. **Done.** The maintainer sets the Linear issue to **Done**.

When an agent stops work, it writes a handoff comment in Linear. Use the format in AGENTS.md 6.4.

## 2. Task owners

**Current rule (decided 2026-10-08, D35):** Claude agents build all issues. The OpenCode and Codex setup in Section 4 is parked. The table below is the target split when the maintainer starts them again.

Tasks are split by layer (decided 2026-10-08). The layers share few files, so agents can work in parallel.

| Layer | Owner | Tasks |
|---|---|---|
| Core, providers and release | Claude | TRD-T01, T02, T03, T04, T05, T07, T10, T12, T13, T26 |
| Humor | OpenCode (`opencode-go/kimi-k3`) | TRD-T06, T14 |
| UI | Codex (ChatGPT) | TRD-T08, T09, T15, T16, T27 |
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
| 6 | T18, then T23; T28 | v1.0 |
| After the alpha | T11, only if the maintainer approves | v1.0 |

## 4. Agents from other providers

Claude starts OpenCode and Codex from the command line, one run for each issue (decided 2026-10-08). Both tools passed a pilot task and a permission probe on 2026-10-08.

### 4.1 Run steps

1. Claude makes the branch and the worktree for the issue. Claude adds the Linear claim comment with the tool and the model.
2. Claude starts the tool in the worktree. The prompt is the Linear issue text and this instruction: "Read AGENTS.md and the skills in `.agents/skills/` first."
3. When the tool stops, Claude runs `swift build` and `swift test` again. Claude does not trust the tool report alone.
4. Claude does the pre-review (Section 1, step 6). Claude also checks that the diff changes only the files that the issue owns.
5. Claude opens the pull request. The description names the tool and the model.

### 4.2 OpenCode

| Item | Value |
|---|---|
| Command | `opencode run --dir <worktree> -m opencode-go/kimi-k3 "<prompt>"` |
| Permissions | [`opencode.json`](../opencode.json) in the repository root. Do not use `--auto`. |
| Allowed shell commands | `swift build`, `swift test`, `git status`, `git diff`, `git add`, `git commit`, `ls`. All other commands are denied. |
| Other limits | No web fetch. No access outside the worktree. |
| Commits | OpenCode commits on its branch. |

The probe showed that OpenCode checks each part of a compound command. `git status && touch FILE` is denied.

### 4.3 Codex

| Item | Value |
|---|---|
| Command | `codex exec -C <worktree> --sandbox workspace-write "<prompt>"` |
| Sandbox | Writes only in the worktree. No network. `.git` is read-only. |
| Tests | Codex runs `swift test --disable-sandbox`, because the SwiftPM sandbox cannot run inside the Codex sandbox. |
| Commits | Codex cannot write to `.git`. Claude commits the Codex changes on the branch. |

**Known limit:** the Codex sandbox does not block reads. Codex can read files outside the worktree, for example credential files. The maintainer accepted this risk (2026-10-08). Before each Codex commit, Claude checks the diff for secrets and for files outside the issue scope.

## 5. Time budget

The maintainer has 3 to 5 hours a week (PRD R11). Manual testing, alpha users and posts use most of this time. Plan about 2 waves a week. If a wave is late, cut Should stories first (PRD R11).
