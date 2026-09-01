---
title: "CLI: ai"
sidebar_position: 5
slug: /cli/ai
---

# `ue ai`

The `ai` domain currently provides the `prompt` command. It assembles a repository-aware startup prompt from project documentation and optional private machine context.

## Usage

```powershell
ue ai prompt [options]
ue-tools ai prompt [options]
```

## Options

| Option | Meaning |
|---|---|
| `-Task <text>` | Add a concrete task-context line to the generated prompt. |
| `-IncludePrivate` | Include `.ai-local/Private-Context.md` guidance when that ignored file exists. |
| `-CopyToClipboard` | Copy the generated prompt with PowerShell `Set-Clipboard`. |

## Examples

```powershell
ue ai prompt -Task "Investigate UnrealSync failures"
ue ai prompt -IncludePrivate
ue ai prompt -Task "Review coding standards docs" -IncludePrivate -CopyToClipboard
```

## Behavior

- Resolves the active repository before collecting context.
- Uses shared repository Markdown and coding-standard context.
- Includes private context only when explicitly requested.
- Warns when private context was requested but the expected file is absent.
- Always writes the generated prompt to standard output, even when it also copies it to the clipboard.

## Help

```powershell
ue help ai
ue ai prompt help
```
