---
title: "CLI: build"
sidebar_position: 2
slug: /cli/build
---

# `ue build`

The `build` command runs the Unreal synchronization workflow. Depending on its options and trigger context, it can clean generated data, regenerate project files, reconcile workspace settings, and build the Editor target.

## Usage

```powershell
ue build [options]
ue-tools build [options]
```

Manual dispatcher invocation forces evaluation of the requested workflow. Git hooks use the same runtime with revision metadata and run only the actions selected by changed-file triggers.

## Workflow phases

1. Resolve the repository, `.uproject`, workspace, Engine, platform, and configuration.
2. Validate settings overlays and provenance when settings sync is enabled.
3. Optionally clean selected generated/cache directories.
4. Regenerate Unreal project files unless `-NoRegen` is set.
5. Reconcile Team, User, and Project workspace operations.
6. Build the Editor unless `-NoBuild` is set.

Failures stop later phases. Regeneration/settings failures restore protected workspace artifacts where the runtime contract requires rollback.

## Options

| Option | Meaning |
|---|---|
| `-RepoRoot <path>` | Select the repository explicitly. |
| `-UProjectPath <path>` | Select a `.uproject` when resolution is ambiguous. |
| `-WorkspacePath <path>` | Select a `.code-workspace` explicitly. |
| `-Config <value>` | Choose `Development` or `Debug`; default is `Development`. |
| `-Platform <Win64>` | Choose the supported platform; currently `Win64`. |
| `-CleanGenerated` | Remove `Binaries` and `Intermediate` before selected actions. |
| `-CleanSaved` | Remove the project `Saved` directory. |
| `-CleanCache` | Remove `DerivedDataCache`. |
| `-NoRegen` | Skip project-file generation. Settings synchronization still runs. |
| `-NoBuild` | Skip the Editor build phase. |
| `-SkipSettingsSync` | Explicitly bypass workspace settings reconciliation. |
| `-DryRun` | Validate detection and prompt flow without cleanup, regeneration, or build writes. |
| `-NonInteractive` | Disable prompts for automation. |
| `-Force` | Force the runtime workflow; public `ue build` already supplies this through the dispatcher. |

`-OldRev`, `-NewRev`, and `-Flag` are accepted for Git-hook integration. Normal users should not need to provide them.

## Examples

```powershell
# Preview the workflow.
ue build -DryRun

# Regenerate and reconcile settings without compiling the Editor.
ue build -NoBuild -WorkspacePath ".\Game.code-workspace" -NonInteractive

# Apply owned workspace settings without regeneration or build.
ue build -NoRegen -NoBuild -WorkspacePath ".\Game.code-workspace"

# Build Debug Editor without regenerating project files.
ue build -NoRegen -Config Debug -Platform Win64
```

## Safety notes

- Cleanup switches delete generated or cache directories; use them deliberately.
- `-NoRegen` is not a settings-sync opt-out. Use `-SkipSettingsSync` only for a controlled diagnostic or adoption workflow.
- A workspace conflict fails closed before settings writes and before the Editor build.
- See [`ue settings`](./Settings.md) for ownership, provenance, and conflict details.
