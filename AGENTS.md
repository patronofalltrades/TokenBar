# AGENTS.md

This file is the agreement for all AI coding agents that work on TokenBar. It applies to agents from all providers: Claude, Codex, Gemini, Grok, Cursor and others. It also applies to human contributors.

Read this file completely before you change the repository.

## 1. Project summary

TokenBar is a macOS menu bar app. It shows LLM usage and converts the cost into funny IESE units.

- Product scope: [docs/PRD.md](docs/PRD.md)
- Technical scope: [docs/TRD.md](docs/TRD.md)
- Design scope: [docs/DRD.md](docs/DRD.md)

If this file and a requirements document do not agree, stop. Ask the maintainer.

## 2. Writing standard: ASD-STE100

Write all persistent text in ASD-STE100 Simplified Technical English. Persistent text includes:

- Documentation and Markdown files
- Code comments
- Commit messages
- Pull request titles and descriptions
- Linear issues and comments

Rules:

1. Use a maximum of 20 words in an instruction sentence. Use a maximum of 25 words in a descriptive sentence.
2. Use the active voice.
3. Use the imperative for instructions. Example: "Run the tests."
4. Write one instruction in each sentence.
5. Use one term for one thing. Do not use synonyms for variety.
6. Do not use idioms, slang or phrasal verbs when a single verb is available.
7. Use a pronoun only when its noun is clear.

**Exception:** User-facing humor strings (roasts and café-index labels) do not follow ASD-STE100. Follow the voice rules in [docs/DRD.md](docs/DRD.md) for these strings.

## 3. Skills

This repository includes skills in `.agents/skills/`. The folder `.claude/skills` is a link to the same folder.

| Skill | When to use it | Source |
|---|---|---|
| `caveman` | All chat replies to the maintainer. | [juliusbrussee/caveman](https://github.com/juliusbrussee/caveman) (Apache-2.0) |
| `caveman-commit` | Commit messages. | same |
| `caveman-review` | Code review comments. | same |
| `ponytail` | All code that you write or change. Use the `full` level. | [dietrichgebert/ponytail](https://github.com/dietrichgebert/ponytail) (MIT) |
| `ponytail-review` | A review for complexity before you open a pull request. | same |

If your tool does not load skills automatically, read the `SKILL.md` files in `.agents/skills/` at the start of the session.

**Priority rules:**

- `caveman` applies to chat only. Persistent text follows ASD-STE100 (Section 2).
- `ponytail` does not permit you to remove input validation, error handling, security controls or accessibility.
- If a skill and this file do not agree, this file has priority.

## 4. Technology stack

| Area | Decision |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI `MenuBarExtra` |
| Minimum OS | macOS 14 (Sonoma) |
| Project | Swift Package Manager |
| Tests | Swift Testing |
| Secrets | macOS Keychain |
| Release | GitHub Actions, GitHub Releases (DMG), Homebrew cask |

Do not add a third-party dependency without approval from the maintainer. Use the Swift standard library and Apple frameworks first.

## 5. Architecture rules

1. Each usage source is a `UsageProvider`. Each provider is in its own file in `Sources/TokenBar/Providers/`.
2. A provider returns usage data. A provider does not format text or show UI.
3. The cost conversion (café index) is data, not code. Keep units in a data file.
4. Do not read prompt content or response content from logs. Read only token counts, model names and timestamps.
5. Do not send usage data off the Mac. Do not add telemetry or analytics.
6. Keep API keys only in the Keychain. Do not write keys to files, logs or `UserDefaults`.

## 6. Concurrent work with other agents

More than one agent works on this repository at the same time. Agents can come from different providers. Obey these rules to prevent conflicts.

### 6.1 Linear is the source of truth

1. Work only on a Linear issue that the maintainer assigned to you.
2. Before you start, set the issue to **In Progress**. Add a comment with your agent name and model.
3. If the issue is already **In Progress** for a different agent, do not start. Tell the maintainer.
4. When you open the pull request, link it to the issue.

### 6.2 Branches and worktrees

1. Do not commit to `main`. Do not push to `main`.
2. Use one branch for each issue. Name the branch `<agent>/<issue-id>-<short-name>`.
   Example: `claude/TOK-12-claude-code-provider`.
3. Use a separate git worktree for each branch. Do not change files in the worktree of a different agent.
4. Do not rebase, force-push or delete the branch of a different agent.

### 6.3 File ownership

1. Change only the files that your issue needs.
2. If you must change a shared file, write the file names in your Linear comment before you change them. Shared files are `Package.swift`, `AGENTS.md`, `docs/*.md` and files in `Sources/TokenBar/Core/`.
3. Do not reformat or rename code that is not part of your issue.

### 6.4 Handoff

When you stop work, write a Linear comment with this information:

- The work that is complete
- The work that is not complete
- The commands that you used to test
- Problems that the next agent must know about

## 7. Definition of done

A task is done only when all of these conditions are true:

1. `swift build` completes without errors or warnings.
2. `swift test` completes, and all tests pass.
3. New logic has a minimum of one test. Parsers and cost calculations must have tests.
4. You did a `ponytail-review` of your diff.
5. You updated the documentation if the behavior changed.
6. The pull request description tells what changed, why, and how you tested it.

Do not write "done" if a step failed or if you did not do a step. Report the result honestly.

## 8. Commits

- Use Conventional Commits format: `<type>(<scope>): <summary>`.
- Write the summary in the imperative. Example: `feat(providers): add Codex log parser`.
- Include the Linear issue ID in the commit body. Example: `Refs TOK-12`.
- If your tool requires an AI attribution trailer, add it as a trailer.

## 9. Actions that need approval

Ask the maintainer before you do any of these actions:

- Add a dependency
- Change the minimum macOS version
- Change the CI or release workflow
- Change signing, notarization or Homebrew configuration
- Delete a file that a different issue created
- Make a network request to a new host
