---
title: Workflow
slug: /workflow
---

# Daily Workflow

This is the required day-to-day workflow for normal project work.

Git-specific repo standards now live in one place:

- [Git Workflow Standards](./Git-Branch-And-PR-Workflow.md)

Use that page for:

- branch naming
- rebasing and branch cleanup before review
- PR and merge policy
- guarded conflict handling

## Required Practices

- Move `.uasset` and `.umap` files in Unreal Editor, not with filesystem tools.
- Start fresh AI sessions with `ai-prompt` or `ai-tools prompt` when you want the repo docs and local context called out consistently.
- Run the relevant script tests before changing hook or automation behavior.
- Let the automated `ue-sync` hook decide whether a C++ branch switch needs a build, project-file regeneration, or both.
- Use `docs-tools new-section` and `docs-tools new-page` for routine docs scaffolding.
- Use `docs-tools reorder` instead of hand-editing multiple sibling positions when docs nav order changes.
- Run `docs-tools check` before merging docs-structure or docs-site workflow changes.
- Preview docs locally when editing navigation or structure-heavy pages with `docs-tools start`, or `docs-tools start --background` when you want detached tracked mode.

## UE Sync Actions

`Scripts/Unreal/UnrealSync.ps1` separates project-file regeneration from editor builds so branch changes do only the work they need.

- Build only: modified existing C++ implementation/header files under `Source/` or `Plugins/`.
- Regenerate project files and build: `.uproject`, `.uplugin`, `*.Build.cs`, `*.Target.cs`, or added/deleted/renamed C++ files under `Source/` or `Plugins/`.
- No UE sync action: docs, content, config, or other files that do not affect C++ build/project structure.

When a git hook invokes `ue-sync`, it calculates that action plan from the changed files and can run build only, regeneration only, or regeneration plus build. Manual runs still support explicit control:

```powershell
ue-tools build -NoRegen
ue-tools build -NoBuild
ue-tools build -CleanGenerated -NoRegen -NoBuild
ue-tools build -NoBuild -NoRegen -DryRun
```

`-CleanGenerated` explicitly deletes `Binaries/` and `Intermediate/`. Use it for a manual cleanup-only pass or when you want a build-only run to start from clean generated folders. Hook-triggered build-only runs skip that cleanup by default.

Project-file regeneration is allowed to rewrite VS Code workspace artifacts. After regeneration, `ue-sync` preserves user-owned VS Code workspace customization by merging previous extra folders, `settings`, extension recommendations, custom tasks, and custom launch configurations back into the generated `.code-workspace`. It also restores the pre-regen `.ignore` content when that file existed before regeneration, which prevents Unreal-generated `.ignore` churn from appearing as a tracked git change.

## Do Not

- Mix large content migrations with unrelated gameplay work.
- Treat Confluence as the live source of truth for this project.

## Worked Example

Goal: move Unreal assets under a new content folder and document the policy change.

1. Create a correctly named branch using [Git Workflow Standards](./Git-Branch-And-PR-Workflow.md).
2. Move the assets in Unreal Editor.
3. Fix redirectors in the moved folder.
4. Update the project structure docs if the canonical layout changed.
5. Run the relevant smoke test in editor.
6. Commit only the moved assets and docs updates.
