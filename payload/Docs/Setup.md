---
title: Setup
sidebar_position: 2
slug: /setup
---

# Project Setup

Use this flow when bootstrapping a fresh clone or when moving the repo to a new machine.

## Required Tools

- Unreal Engine 5.x
- Git for Windows
- Git LFS
- PowerShell 7+
- Node.js 20+ and npm for the docs site

## First-Run Flow

1. Open PowerShell in the repo root.
2. Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1
```

3. Open the project `.uproject` and let Unreal regenerate local workspace data if needed.
4. If the repo was moved, verify the `.code-workspace` file points at the current repo root and local engine install.
5. Start the docs site when you need a local preview:

```powershell
docs-tools start
```

`Init-Repo.ps1` prepares installed optional tool prerequisites during first-run setup. When `website/package.json` is present, it verifies Node.js 20+ and npm, runs `npm install` if `website/node_modules` is missing, installs the optional docs VS Code bridge when the `code` CLI is available, and runs `docs-tools doctor`.

After init installs project shell aliases, open a new PowerShell session or reload the profile path printed by the script before using commands like `ue-tools`, `art-tools`, `docs-tools`, or `ai-prompt`.

The Docusaurus site is already set up in `website/`. You do not need to create a new site scaffold for this repo. See [Docusaurus Setup](./DocsSite/Docusaurus-Setup.md) for the edit/preview/build workflow.

`docs-tools start` now stays attached to the current terminal so you can see live server output. If you want the old detached tracked mode instead, run `docs-tools start --background`.

When you are done with the tracked background docs server:

```powershell
docs-tools stop
```

If `Init-Repo.ps1` skipped the bridge because the `code` CLI was unavailable, or if you want to rerun the install manually:

```powershell
docs-tools help
docs-tools install-bridge
```

`docs-tools install-bridge` is optional. It only enables table-of-contents generation for new pages and sections when `Markdown All in One` is also installed in VS Code.

## Engine Discovery Rules

The shared Unreal tooling resolves the engine in this order:

1. The local `.code-workspace` UE folder
2. `UE_ENGINE_DIR`, `UE_ENGINE_ROOT`, or `UNREAL_ENGINE_DIR`
3. Registry lookup from `EngineAssociation`
4. EngineAssociation-specific folders under common UE install roots
5. Installed `UE_*` folders under common UE install roots

Set `UE_ENGINE_COMMON_INSTALL_ROOTS` to a semicolon-separated list when this machine uses nonstandard Epic Games install roots. If automated Unreal tooling cannot find the engine, fix one of those sources instead of hardcoding project-specific paths.

## Recommended Variants

- Use `-NoBuild` when you only want hooks, aliases, and repo config without a first build.
- Use `-SkipUnrealSync` when the local engine path is not resolved yet.
- Use `-SkipShellAliases` on CI or any environment where PowerShell profiles should remain untouched.
- Use `-SkipOptionalToolSetup` when you want only the core git/hook/Unreal bootstrap without optional tool prerequisite work.
- Use `-SkipDocsSetup`, `-SkipDocsNpmInstall`, `-ForceDocsNpmInstall`, or `-SkipDocsBridgeInstall` to control the docs-specific setup steps.

## UE Sync Behavior

The git-hook `ue-sync` workflow decides between build and project-file regeneration based on the changed files:

- Modified existing C++ files build the editor without regenerating project files.
- `.uproject`, `.uplugin`, `*.Build.cs`, `*.Target.cs`, and added/deleted/renamed C++ files regenerate project files and then build.
- Build-only hook runs skip `Binaries/` and `Intermediate/` cleanup by default; use `ue-tools build -CleanGenerated -NoRegen -NoBuild` for a manual cleanup-only pass.
- Project-file regeneration preserves user VS Code workspace customization and restores pre-regen `.ignore` content so Unreal-generated churn does not keep dirtying tracked files.

## Tool Suite Updates

Use the standalone UE tool suite installer repo to install or update these tools in a project. Installer/updater logic should stay outside this project; this repo should contain only the usable tools and docs payload.
