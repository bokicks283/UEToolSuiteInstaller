---
title: Shared vs Private Context
slug: /codex-context/shared-vs-private
---

# Shared vs Private Context

Use the following split.

## Shared, Committed, Team-Visible

- `AGENTS.md`
  Use for short repo instructions and pointers.
- `Docs/Codex/`
  Use for Codex-facing project context, examples, and workflow guidance.
- The rest of `Docs/`
  Use for the actual project rules, setup, testing, architecture, and process docs.

## Private, Local, Not Committed

- `.codex-local/`
  Use for repo-specific personal notes, prompt starters, and preferences that should stay on one machine.
- `C:\Users\<user>\.codex\`
  Use for global personal defaults that should apply across many repos.

## Quick Guide

| Location | Shared? | Good for | Avoid |
| --- | --- | --- | --- |
| `AGENTS.md` | Yes | Short instructions and doc pointers | Long design docs |
| `Docs/Codex/` | Yes | Stable Codex-facing repo context | Temporary personal notes |
| `.codex-local/` | No | Personal repo notes and private prompt snippets | Secrets or huge scratchpads |
| `C:\Users\<user>\.codex\` | No | Global defaults, skills, and rules | Repo-specific team docs |

## Example Shared Note

```md
## Unreal Tooling
- Use Scripts/Tests/Run-AllTests.ps1 as the default test runner.
- Read Docs/Testing.md before running branch-mutating tests.
```

## Example Private Note

```md
## My Working Preferences
- When I ask for test changes, start with the serial master runner.
- Call out branch-mutating scripts before you run them.
- Prefer docs updates in the same change when tooling behavior changes.
```

## Safety Notes

- Do not store tokens, passwords, or secrets in `.codex-local/`.
- If a private note becomes team policy, move it into `Docs/`.
- If a shared doc becomes too long, split it instead of bloating `AGENTS.md`.
