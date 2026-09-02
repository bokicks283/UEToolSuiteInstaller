---
title: UETools CLI
slug: /cli
toc_min_heading_level: 2
toc_max_heading_level: 3
---

# UETools CLI

The UETools command-line interface provides one entrypoint for Unreal project synchronization, workspace settings ownership, documentation, AI context, art-source layout, repository initialization, and guarded Git conflict workflows.

Use either launcher:

```powershell
ue <command> [options]
ue-tools <command> [options]
```

`ue` is the convenient installed alias. `ue-tools` is the long-form launcher used by scripts and examples. Both route to the same installed per-user runtime and resolve project data from the selected repository.

## First use in a team checkout

The tracked `.ue-tools/global-cli.json` marker contains only portable version and bootstrap metadata. It never records a developer's LocalAppData path, global runtime directory, or launcher path.

The project-local `Scripts/ue-tools.ps1` shim resolves the declared runtime independently for the current Windows user:

1. Use `UE_TOOLS_GLOBAL_CLI_ROOT` when an explicit per-user override is configured.
2. Otherwise use `%LOCALAPPDATA%\UEToolSuite`.
3. Look for `versions\<projectVersion>\Scripts\ue-tools.ps1`, so each checkout uses the version it declares instead of another project's current version.
4. If that runtime is present, forward the original command to it.
5. If it is missing in an interactive shell, show the project-declared repository, release tag, and install target, then ask whether to install.
6. After approval, download the exact declared tag, run its installer for this checkout, and resume the original command.

For a fresh clone without the aliases installed yet, start the portable shim directly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 help
```

The automatic bootstrap requires Git, PowerShell 7, and a published Git tag matching the marker's `releaseTag`. It never prompts or installs from Git hooks, CI, or an invocation that includes `-NonInteractive`; those paths fail with the interactive command the developer should run. Declining the prompt leaves the per-user global CLI absent.

## Main command inventory

| Command | Purpose | Detailed page |
|---|---|---|
| `help` | Discover the root command surface and command-specific help. | [`ue help`](./Help.md) |
| `build` | Run Unreal project-file regeneration, settings reconciliation, and Editor build phases. | [`ue build`](./Build.md) |
| `settings` | Manage provenance-aware `.code-workspace` ownership with Team, User, and Project layers. | [`ue settings`](./Settings.md) |
| `docs` | Create, organize, validate, run, and administer the local Docusaurus documentation site. | [`ue docs`](./Docs.md) |
| `ai` | Generate a repository-aware AI startup prompt. | [`ue ai`](./AI.md) |
| `art` | Interactively create canonical ArtSource item directories from the project template. | [`ue art`](./Art.md) |
| `init` | Bootstrap Git, hooks, aliases, optional docs tooling, ArtSource, and first Unreal synchronization. | [`ue init`](./Init.md) |
| `git` | Resolve and audit guarded binary conflicts during merge and rebase workflows. | [`ue git`](./Git.md) |

## Command selection rules

### Repository selection

Run UETools inside the Unreal repository or pass `-RepoRoot` where the selected command supports it. Paths such as `-WorkspacePath` and `-UProjectPath` are resolved against that repository.

```powershell
ue settings status -RepoRoot "C:\Projects\Game" `
  -WorkspacePath ".\Game.code-workspace"
```

### Default build routing

If the first argument starts with `-` or `/`, the dispatcher treats it as a `build` option. These are equivalent:

```powershell
ue -DryRun
ue build -DryRun
```

Prefer the explicit form in documentation and automation.

### Installed domains

Root help reports whether the optional command modules are installed for the current project/runtime. A missing domain fails with the required path and installer guidance rather than silently falling back.

## Help conventions

Start with:

```powershell
ue help
ue help <command>
```

Commands with subcommands also expose their own help. For example:

```powershell
ue settings help sync
ue docs help new-page
ue git help
```

See the [help command page](./Help.md) for the supported forms and the individual command pages for complete inventories.

## Safety conventions

- Use `-DryRun` when a command supports it and you need a no-write preview.
- Use `-NonInteractive` for hooks and automation only after supplying every required choice.
- Treat `-SkipSettingsSync`, cleanup flags, adoption, Git conflict resolution, and documentation ownership overrides as deliberate operations.
- Keep Team configuration portable and tracked; keep User and Project machine-specific settings private.
- Update/install the current UEToolSuite revision into a target repository before expecting the stable `ue` alias to use source-checkout changes.
