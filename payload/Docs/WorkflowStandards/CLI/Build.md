---
title: "CLI: build"
sidebar_position: 2
slug: /cli/build
---

# `ue build`

The `build` command runs the Unreal synchronization workflow. Depending on its options and trigger context, it can clean generated data, regenerate project files, reconcile workspace settings, and build a project target.

## Usage

```powershell
ue build [options]
ue build choices
ue build show
ue build use -Target <name> -Config <configuration>
ue-tools build [options]
```

Manual dispatcher invocation forces evaluation of the requested workflow. Git hooks use the same runtime with revision metadata and run only the actions selected by changed-file triggers.

## Workflow phases

1. Resolve the repository, `.uproject`, workspace, Engine, platform, and configuration.
2. Validate settings overlays and provenance when settings sync is enabled.
3. Optionally clean selected generated/cache directories.
4. Regenerate Unreal project files unless `-NoRegen` is set.
5. Reconcile Team, User, and Project workspace operations.
6. Build the selected target unless `-NoBuild` is set.

Failures stop later phases. Regeneration/settings failures restore protected workspace artifacts where the runtime contract requires rollback.

## Options

| Option | Meaning |
|---|---|
| `-RepoRoot <path>` | Select the repository explicitly. |
| `-UProjectPath <path>` | Select a `.uproject` when resolution is ambiguous. |
| `-WorkspacePath <path>` | Select a `.code-workspace` explicitly. |
| `-Target <name>` | Choose a target from `ue build choices`, such as `AmericanCartel` or `AmericanCartelEditor`. |
| `-Config <value>` | Choose a configuration shown for that target. Unreal commonly generates `Debug`, `DebugGame`, and `Development` for Editor, plus `Test` and `Shipping` for Game. |
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

## Saved selection and discovery

`ue build choices` reads the project's targets and generated workspace Build tasks to list available target/configuration combinations. `ue build show` prints the current selection. Save a private project default with `ue build use`; setting either value alone retains the other saved or default value. The selection is stored in ignored `.ue-tools/local/build-selection.json` and is never shared with teammates.

An explicit `-Target` or `-Config` overrides only that part of the saved selection for the current invocation. With no saved selection, `ue build` defaults to `<ProjectName>Editor Win64 Development`. Git hooks ignore the private selection. Invalid values fail before cleanup or compilation and point to `ue build choices`.

```powershell
ue build choices
ue build use -Target AmericanCartelEditor -Config DebugGame
ue build show
ue build
ue build -Config Development # One run; saved DebugGame remains in effect afterward.
```

After UETools regenerates a `.code-workspace`, its settings transaction routes Unreal-generated Build and Rebuild tasks through `ue build -NoRegen` with explicit target, platform, and configuration. Their labels and launch `preLaunchTask` references stay intact. Rebuild retains its generated Clean dependency. A VS Code task therefore ignores the saved CLI selection and synchronizes owned workspace settings before compilation. Use UETools for regeneration so it can restore settings and adapt the newly generated tasks; a direct Unreal regeneration does not run that reconciliation.

## Examples

```powershell
# Preview the workflow.
ue build -DryRun

# Regenerate and reconcile settings without compiling the Editor.
ue build -NoBuild -WorkspacePath ".\Game.code-workspace" -NonInteractive

# Apply owned workspace settings without regeneration or build.
ue build -NoRegen -NoBuild -WorkspacePath ".\Game.code-workspace"

# Build DebugGame Editor without regenerating project files.
ue build -NoRegen -Target AmericanCartelEditor -Config DebugGame -Platform Win64
```

## Safety notes

- Cleanup switches delete generated or cache directories; use them deliberately.
- `-NoRegen` is not a settings-sync opt-out. Use `-SkipSettingsSync` only for a controlled diagnostic or adoption workflow.
- A workspace conflict fails closed before settings writes and before the Editor build.
- See [`ue settings`](./Settings.md) for ownership, provenance, and conflict details.
