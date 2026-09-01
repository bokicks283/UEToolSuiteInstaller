---
title: "CLI: help"
sidebar_position: 1
slug: /cli/help
---

# `ue help`

The `help` command discovers the root CLI surface and routes to command-specific summaries.

## Usage

```powershell
ue help
ue help <command>
ue-tools help
ue-tools help <command>
```

## Root help contents

Root help shows:

- the `ue` and `ue-tools` launch forms;
- every main command;
- installed/not-installed status for command domains;
- representative examples;
- the default rule that option-first invocations route to `build`.

## Command help

| Command | Help entrypoint |
|---|---|
| Build | `ue help build` or `ue build help` |
| Settings | `ue help settings`, then `ue help settings <command>` for `sync`, `capture`, `adopt`, or `status` |
| Docs | `ue docs help`, then `ue docs help <docs-command>` |
| AI | `ue help ai` or `ue ai prompt help` |
| Art | `ue help art` or `ue art help` |
| Init | `ue help init` or `ue init help` |
| Git | `ue help git` or `ue git help` |

The settings command supports three equivalent detailed forms:

```powershell
ue help settings sync
ue settings help sync
ue settings sync help
```

The docs command uses its domain help for detailed subcommands:

```powershell
ue docs help new-section
ue docs help new-page
ue docs help theme
ue docs help site
```

## Help tokens

The dispatcher recognizes `help`, `--help`, `-help`, `-h`, `/?`, and `-?` where command routing permits a help token.

## Installed runtime note

The stable `ue` command loads the installed global runtime. If source help and target-project help disagree, update/install UEToolSuite in that project before diagnosing the command implementation.
