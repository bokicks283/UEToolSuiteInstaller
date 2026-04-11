---
title: Codex Context
slug: /codex-context
---

# Codex Context

Use this section to give Codex stable repo context without relying on old chat threads.

## Goals

- Shared repo context lives in tracked files.
- Private user context stays local and untracked.
- `AGENTS.md` stays short and points Codex at the right docs.
- New chats should start by reading the repo docs, not by assuming old chat history still applies.

## Read Order

1. [Shared vs Private Context](./Shared-vs-Private.md)

## Structure

- `AGENTS.md`: short repo-wide instructions for Codex
- `Docs/Codex/`: shared, committed Codex-facing docs
- `.codex-local/`: local-only repo context for the current user
- `C:\Users\<user>\.codex\`: global Codex defaults across many repos

## Starter Workflow

1. Start a new Codex chat in the repo root.
2. Generate a startup prompt with `codex-prompt` or `codex-tools prompt`.
3. Let `AGENTS.md` drive the startup read order across the repo docs.
4. Add a project-specific `Docs/Codex/Project-Context.md` when you want an explicit shared brief in the prompt.
5. If you want local-only guidance included, also point Codex at `.codex-local/Private-Context.md`.
6. Keep durable decisions in `Docs/`, not in chat history.

## Command Examples

```powershell
codex-tools help
codex-tools prompt -Task "Fix UnrealSync regeneration output"
codex-prompt -Task "Review coding standards docs" -IncludePrivate -CopyToClipboard
```

## Automatic Loading Reality

The repo can strongly instruct Codex to read the docs at startup through `AGENTS.md`, but the repo cannot hard-guarantee a platform-level preload of every document in every new chat.

Use this stack for the most reliable behavior:

1. `AGENTS.md` tells Codex to read the repo docs on startup.
2. Your opening prompt names the highest-priority docs for the task.
3. Stable team knowledge stays in `Docs/` so a fresh chat can re-read it.

## Example Opening Message

```text
Read AGENTS.md and the repo docs it points to.
Then read Docs/Testing.md and any project-specific context docs.
Also use .codex-local/Private-Context.md for my local preferences.
Then help me update the Unreal tooling docs.
```

## Later, Not Now

Custom Codex skills can layer on top of this structure later. Get the shared docs and private local notes working first.
