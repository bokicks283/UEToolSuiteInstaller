---
title: "CLI: init"
sidebar_position: 7
slug: /cli/init
---

# `ue init`

The `init` command bootstraps an installed UEToolSuite repository. It prepares Git/LFS behavior, hooks, aliases, optional docs tooling, ArtSource, and the first Unreal synchronization according to the selected options.

## Usage

```powershell
ue init [options]
ue-tools init [options]
```

## Project selection

| Option | Meaning |
|---|---|
| `-RepoRoot <path>` | Select the target repository. |
| `-UProjectPath <path>` | Select a `.uproject` explicitly. |
| `-WorkspacePath <path>` | Select a `.code-workspace` explicitly. |
| `-Config <value>` | Choose `Development` or `Debug` for the initial Editor build. |
| `-Platform <Win64>` | Choose the supported platform. |

## Skip and control options

| Option | Meaning |
|---|---|
| `-SkipLfsPull` | Configure LFS filters but skip `git lfs pull`. |
| `-SkipUnrealSync` | Skip the first `ue build` workflow. |
| `-SkipShellAliases` | Skip PowerShell profile alias registration. |
| `-SkipOptionalToolSetup` | Skip the optional tool setup group. |
| `-SkipArtSourceTools` | Skip creation/readiness of the canonical ArtSource template. |
| `-SkipDocsSetup` | Skip docs setup. |
| `-SkipDocsSectionMigration` | Skip normalization of legacy docs sections. |
| `-SkipDocsNpmInstall` | Skip docs-site dependency installation. |
| `-ForceDocsNpmInstall` | Force docs-site dependency installation. |
| `-SkipDocsBridgeInstall` | Skip the optional VS Code TOC bridge install. |
| `-NoBuild` | Forward build suppression to the initial Unreal workflow. |
| `-NoRegen` | Forward project-file regeneration suppression to the initial Unreal workflow. |
| `-NonInteractive` | Avoid prompts and use safe defaults. |
| `-SkipIgnoredUntrack` | Do not remove already tracked files that are now ignored. |

## What initialization configures

- Git repository/LFS readiness and recommended repository-local Git config;
- `.githooks` activation and hook self-test;
- binary conflict helper aliases;
- optional PowerShell aliases;
- docs metadata, dependencies, section normalization, doctor, and optional TOC bridge;
- canonical `ArtSource/_Template` readiness;
- initial Unreal project-file/settings/build workflow unless skipped;
- a final tool-readiness summary with next steps.

## Examples

```powershell
# Safe automation-oriented bootstrap without pulling LFS content or opening optional setup.
ue init -SkipLfsPull -SkipOptionalToolSetup -NonInteractive

# Configure repository tooling but defer Unreal synchronization.
ue init -SkipUnrealSync -NonInteractive

# Initialize a specific project/workspace without compiling the Editor.
ue init -UProjectPath ".\Game.uproject" `
  -WorkspacePath ".\Game.code-workspace" -NoBuild -NonInteractive
```

## Help

```powershell
ue help init
ue init help
```

Initialization is designed to be idempotent, but it changes repository Git configuration and may install optional local tooling. Review skip flags before using it in an existing customized repository.
