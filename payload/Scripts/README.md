# Scripts

This folder contains automation that keeps Git/LFS/Unreal workflows consistent for the team.

## Folder Responsibilities

- `Scripts/Codex/`: Codex session helpers and prompt-building utilities.
- `Scripts/Docs/`: Docusaurus authoring helpers and the optional VS Code bridge for docs automation.
- `Scripts/git-hooks/`: shared hook utilities and setup scripts.
- `Scripts/git-tools/`: conflict helper commands (`git ours`, `git theirs`, `git conflicts`).
- `Scripts/Unreal/`: Unreal sync/build helper scripts and ArtSource scaffolding tools.
- `Scripts/Tests/`: script tests and structured test output folders.

Concrete examples:

- `Scripts/Codex/Get-CodexStartupPrompt.ps1`
- `Scripts/Docs/DocsTools.ps1`
- `Scripts/git-hooks/Enable-GitHooks.ps1`
- `Scripts/git-tools/conflicts.ps1`
- `Scripts/Unreal/UnrealSync.ps1`
- `Scripts/Unreal/New-ArtSourcePath.ps1`
- `Scripts/Unreal/ProjectShellAliases.ps1`
- `Scripts/Tests/Test-BinaryGuard-Fixes.ps1`

## Do

- Place new scripts in the closest existing category folder.
- Use verb-based script names (`Enable-*`, `Sync-*`, `Test-*`).
- Add/update tests in `Scripts/Tests` for behavior changes.
- Document user-facing workflow changes in `Docs/Pipeline/README.md`.
- Keep docs-site authoring helpers in `Scripts/Docs/` instead of mixing them into Unreal-only tooling folders.
- Return non-zero exit code on script failure.
- Prefer friendly command-line errors for end-user tools over raw PowerShell traces.
- Keep project tooling portable: derive the project from `.uproject` metadata and `-RepoRoot` inputs instead of hardcoded project names.

## Do Not

- Add generic names like `script1.ps1`.
- Add destructive behavior without explicit user confirmation.
- Swallow errors and continue silently.
- Commit ad-hoc logs outside `Scripts/Tests/*Results/`.

## Naming And Path Examples

Good:

- `Scripts/Codex/Get-CodexStartupPrompt.ps1`
- `Scripts/Unreal/Sync-ProjectAssets.ps1`
- `Scripts/Tests/Test-PluginBootstrap.ps1`

Bad:

- `Scripts/Unreal/misc.ps1`
- `Scripts/git-tools/newtool.ps1`

## Worked Example Flow: Add A New Validation Script

Goal: add a script that validates plugin bootstrap setup.

1. Create script:
   - `Scripts/Unreal/Sync-PluginBootstrap.ps1`
2. Add test:
   - `Scripts/Tests/Test-PluginBootstrap.ps1`
3. Run test locally and write output to:
   - `Scripts/Tests/Test-PluginBootstrapResults/`
4. Verify script fails fast with clear errors and supports safe execution.
5. Update `Docs/Pipeline/README.md` if daily workflow changes.
6. Commit script and test with explicit message.

## Repo Init Readiness

`Scripts/Init-Repo.ps1` is the first-run bootstrap. It configures Git/LFS, hooks, conflict-helper aliases, project shell aliases, and the optional first `UnrealSync` run.

It also prepares installed optional tooling so commands are ready after init:

- If `Scripts/Docs/DocsTools.ps1` and `website/package.json` exist, init verifies Node.js 20+ and npm, runs `npm install` when `website/node_modules` is missing, installs the optional VS Code docs bridge when the `code` CLI is available, and runs `docs-tools doctor`.
- If `Scripts/Unreal/New-ArtSourcePath.ps1` and `ArtSource/` exist, init checks that `ArtSource/_Template` has the expected `Source`, `Textures`, and `Exports` folders.
- If optional tools are not installed in a target UE repo, init reports them as skipped instead of failing the core bootstrap.

Use `-SkipOptionalToolSetup` to skip optional prerequisite work entirely. Use `-SkipDocsSetup`, `-SkipDocsNpmInstall`, `-ForceDocsNpmInstall`, or `-SkipDocsBridgeInstall` for docs-specific control.

## UE Sync Workflow

`Scripts/Unreal/UnrealSync.ps1` classifies hook-triggered changes before doing work:

- Modified existing C++ source/header files trigger a build only.
- Project/module/plugin metadata and added/deleted/renamed C++ files trigger project-file regeneration plus a build.
- Non-C++ files stay silent in hook contexts.

Build-only hook runs skip `Binaries/` and `Intermediate/` cleanup by default. Use `ue-tools build -CleanGenerated -NoRegen -NoBuild` when you want a manual cleanup-only pass.

When regeneration runs, the script snapshots VS Code workspace artifacts and `.ignore` first. After Unreal regenerates project files, it merges user workspace customization, including extra folders, settings, extension recommendations, custom tasks, and custom launch configurations, back into the generated `.code-workspace` and restores `.ignore` content that existed before the regen.

## Test Output Hygiene

Recommended layout:

```text
Scripts/Tests/
|- Test-BinaryGuard-Fixes.ps1
|- Test-BinaryGuard-FixesResults/
|  |- BinaryGuardTest-20260221-173435.log
```

Keep cleanup of old logs in separate maintenance commits.
