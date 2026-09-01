# Scripts

This folder contains automation that keeps Git/LFS/Unreal workflows consistent for the team.

## Folder Responsibilities

- `Scripts/AI/`: reserved for AI payload assets (domain execution lives in `Scripts/UETools/`).
- `Scripts/Docs/`: Docusaurus authoring helpers and the optional VS Code bridge for docs automation.
- `Scripts/git-hooks/`: shared hook utilities and setup scripts.
- `Scripts/git-tools/`: conflict helper commands (`git ours`, `git theirs`, `git conflicts`).
- `Scripts/UETools/`: dispatcher and domain modules for `ue-tools`.
- `Scripts/Unreal/`: Unreal sync/build helper scripts and project-context resolution helpers.

Concrete examples:

- `Scripts/UETools/UEToolSuite.Docs.psm1`
- `Scripts/ue-tools.ps1`
- `Scripts/git-hooks/Enable-GitHooks.ps1`
- `Scripts/UETools/UEToolSuite.Git.psm1`
- `Scripts/UETools/UEToolSuite.Unreal.psm1`
- `Scripts/UETools/UEToolSuite.Dispatcher.psm1`

## Do

- Place new scripts in the closest existing category folder.
- Use verb-based script names (`Enable-*`, `Sync-*`, `Test-*`).
- Add or update tests in the UEToolSuiteInstaller source repository for behavior changes.
- Document user-facing workflow changes in `Docs/Pipeline/README.md`.
- Keep docs-site authoring helpers in `Scripts/Docs/` instead of mixing them into Unreal-only tooling folders.
- Return non-zero exit code on script failure.
- Prefer friendly command-line errors for end-user tools over raw PowerShell traces.
- Keep project tooling portable: derive the project from `.uproject` metadata and `-RepoRoot` inputs instead of hardcoded project names.

## Do Not

- Add generic names like `script1.ps1`.
- Add destructive behavior without explicit user confirmation.
- Swallow errors and continue silently.

## Naming And Path Examples

Good:

- `Scripts/UETools/UEToolSuite.AI.psm1`
- `Scripts/Unreal/Sync-ProjectAssets.ps1`

Bad:

- `Scripts/Unreal/misc.ps1`
- `Scripts/git-tools/newtool.ps1`

## Worked Example Flow: Add A New Validation Script

Goal: add a script that validates plugin bootstrap setup.

1. Create script:
   - `Scripts/Unreal/Sync-PluginBootstrap.ps1`
2. Add its regression coverage in the UEToolSuiteInstaller source repository.
3. Verify the script fails fast with clear errors and supports safe execution.
4. Update `Docs/Pipeline/README.md` if daily workflow changes.
5. Commit the script and test with an explicit message.

## Repo Init Readiness

`ue-tools init` is the first-run bootstrap command. It configures Git/LFS, hooks, conflict-helper aliases, project shell aliases, and the optional first `UnrealSync` run.

It also prepares installed optional tooling so commands are ready after init:

- If `Scripts/UETools/UEToolSuite.Docs.psm1` and `website/package.json` exist, init verifies Node.js 20+ and npm, synchronizes website dependencies (`npm ci` when `website/package-lock.json` exists, otherwise `npm install`), validates required packages listed in `website/package.json`, installs the optional VS Code docs bridge when the `code` CLI is available, and runs `ue-tools docs doctor`.
- If `Scripts/UETools/UEToolSuite.Art.psm1` and `ArtSource/` exist, init checks that `ArtSource/_Template` has the expected `Source`, `Textures`, and `Exports` folders.
- If optional tools are not installed in a target UE repo, init reports them as skipped instead of failing the core bootstrap.

Docs section normalization is also part of installed repo readiness:

- Normal installs and updates automatically normalize legacy docs sections that behave like real sections in SiteAdmin but still lack `_category_.json`.
- `ue-tools init` reruns the same normalization pass unless `-SkipDocsSectionMigration` is supplied.
- `ue-tools docs migrate-sections` exposes the same normalization logic directly, and `ue-tools docs migrate-sections --what-if` plans changes without writing files.
- `ue-tools docs doctor` reports qualifying legacy sections and points to `ue-tools docs migrate-sections` as the remediation command.
- Normalization writes only deterministic `_category_.json` files. It does not create `README.md`, landing docs, or generated-index links.

Use `-SkipOptionalToolSetup` to skip optional docs prerequisite work entirely. ArtSource initialization remains enabled unless `-SkipArtSourceTools` is explicitly supplied. Use `-SkipDocsSetup`, `-SkipDocsNpmInstall`, `-ForceDocsNpmInstall`, or `-SkipDocsBridgeInstall` for docs-specific control.
Use `-SkipDocsSectionMigration` only when you intentionally need installer or init recovery without touching the target `Docs/` tree.

## UE Sync Workflow

`Scripts/UETools/UEToolSuite.Unreal.psm1` classifies hook-triggered changes before doing work:

- Modified existing C++ source/header files trigger a build only.
- Project/module/plugin metadata and added/deleted/renamed C++ files trigger project-file regeneration plus a build.
- Non-C++ files stay silent in hook contexts.

Build-only hook runs skip `Binaries/` and `Intermediate/` cleanup by default. Use `ue-tools build -CleanGenerated -NoRegen -NoBuild` when you want a manual cleanup-only pass.

When regeneration runs, UETools validates provenance-aware workspace overlays/state before cleanup, snapshots the effective `.code-workspace` and `.ignore`, treats Unreal's result as the new pristine baseline, and applies only explicitly owned additions, modifications, and removal tombstones. New unowned Unreal fields survive and obsolete unowned fields are not restored. A conflict restores the pre-regeneration workspace and stops before build. `-NoRegen` still runs settings sync; use `-SkipSettingsSync` only for an explicit opt-out. See `Docs/WorkflowStandards/CLI/Settings.md`.

## Validation Ownership

The full PowerShell regression suites live in the UEToolSuiteInstaller source repository. They are intentionally excluded from published installers and installed Unreal projects. The project-local `Scripts/git-hooks/Test-Hooks.ps1` health check remains available because `ue-tools init` uses it to validate hook setup.
