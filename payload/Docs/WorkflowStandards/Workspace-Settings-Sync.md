---
title: VS Code Workspace Settings Sync
sidebar_position: 5
slug: /workspace-settings-sync
---

# VS Code Workspace Settings Sync

UETools reconciles explicitly owned `.code-workspace` changes after Unreal regenerates project files. It does not guess that every pre-regeneration difference is custom. A versioned ledger records the last pristine Unreal workspace and the last effective workspace, and ordered overlays record fine-grained additions, modifications, and removal tombstones.

## Commands

```powershell
ue settings sync
ue settings sync -DryRun
ue settings capture -Scope Team -Path /settings/editor.formatOnSave
ue settings capture -Scope User -Path /extensions/recommendations
ue settings capture -Scope Project -Path /tasks/tasks
ue settings status
ue settings adopt -Scope User -Path /settings -NonInteractive
```

Use `ue settings <command> help` for command-first help. `-RepoRoot`, `-WorkspacePath`, `-DryRun`, and `-NonInteractive` are accepted where applicable. Noninteractive capture and adoption require explicit paths; unknown arrays are rejected unless their identity strategy is known.

## Storage and precedence

Layers apply from lowest to highest precedence:

1. Team: `.ue-tools/workspace-settings/team.jsonc` (portable and tracked).
2. User: `%LOCALAPPDATA%/UEToolSuite/workspace-settings/profiles/default.jsonc` (private and reusable across projects).
3. Project: `.ue-tools/local/workspace-settings.jsonc` (private to this user/project).

The ignored `.ue-tools/local/workspace-profile.json` may select another user profile with `{"profileId":"name"}`. Runtime state is stored under `.ue-tools/state/workspace-sync/`. Team overlays reject absolute paths, hosts, credential-like fields, tokens, and account state. User and project overlays may contain machine-specific values.

## Ownership operations

Schema version 1 supports `set`, `mergeObject`, `removeProperty`, `addStringItem`, `removeStringItem`, `upsertKeyedItem`, `removeKeyedItem`, and `removeSemantic`. Paths are JSON Pointers. Objects are owned at leaf granularity. Known keyed arrays are workspace folders (`path`), tasks (`label`), launch configurations and compounds (`name`), and inputs (`id`).

Removal operations are durable tombstones. A regenerated removed item is removed again and is not itself a conflict. `removeSemantic` with selector `activeUnrealEngineRoot` resolves the current project's Engine root on each machine, normalizes relative/absolute Windows paths, separators, case, and trailing separators, and removes only the single matching Engine or Engine source folder. More than one match is an error.

## Workflows

For a team setting, edit the workspace, run `ue settings capture -Scope Team -Path ...`, review `.ue-tools/workspace-settings/team.jsonc`, and commit it. Teammates receive it on `settings sync` or build.

To remove the Engine workspace folder portably, remove that folder from the live `folders` array and run:

```powershell
ue settings capture -Scope Team -Path /folders
```

Capture recognizes the missing active Engine root and stores the semantic selector, never the machine's absolute Engine path.

For reusable personal settings, capture to `User`. For one-project personal settings, capture to `Project`.

Existing customized workspaces need adoption. `settings adopt` snapshots the current workspace, invokes the existing Unreal regeneration workflow with settings sync explicitly skipped, compares old effective content with pristine Unreal output, records only selected paths, and restores the original workspace if any step fails. Build without a ledger initializes automatically only when pre/post regeneration workspaces are semantically identical; otherwise it restores the workspace and requires adoption.

## Conflict and recovery

Owned non-removal values use a strict three-way comparison. If Unreal changes the previously generated value at an owned path, sync reports the path, previous/new Unreal values, layer, custom operation, and resolution guidance, then writes nothing. New unowned fields and array entries survive; obsolete unowned fields disappear.

Use `settings status` to inspect layer order, operations, ledger location, and live drift. To stop owning a path or remove a tombstone, delete its operation from the owning overlay and run sync. To move ownership, remove it from one overlay and add/capture it in the other before syncing. To resolve a conflict, review the Unreal value and then update or remove the operation. A malformed overlay or state fails closed; repair JSON/schema or restore it from backup. To rebuild only the ledger, preserve overlays, delete the ignored workspace state file, then run adoption (or a regeneration when the workspace is known pristine).

## Build integration

Regeneration snapshots the effective workspace, obtains the new pristine Unreal workspace, runs the same planner used by `settings sync`, atomically writes effective workspace/state, and only then builds. Failure restores the pre-operation workspace and `.ignore`. `-NoRegen` still synchronizes; `-SkipSettingsSync` is the explicit opt-out. Dry run uses the planner and does not write workspace, overlay, ledger, selection, or backup files.
