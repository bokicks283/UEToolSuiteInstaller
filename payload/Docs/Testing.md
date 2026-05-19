---
title: Testing
sidebar_position: 7
slug: /testing
---

# Tooling And Workflow Tests

The transferred automation is only useful if it can be revalidated after future repo moves or script changes. Keep this suite green.

## Preferred Entrypoint

- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Run-AllTests.ps1`

The master runner executes tests serially on purpose. Some tests create branches, reset the repo, or otherwise require exclusive access to the working tree, so the suite is not parallel-safe in a live repo.

## Recommended Order

- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-hooks/Test-Hooks.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UESyncShellAliases.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-DocsTools.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-AIStartupPrompt.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UnrealSync-Regeneration.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UEProjectToolsInstaller.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-InitRepoToolReadiness.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-New-ArtSourcePath.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-UnrealSync.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Tests/Test-BinaryGuard-Fixes.ps1`

## What Each Test Covers

- `Test-Hooks.ps1`: validates committed hook plumbing, `core.hooksPath`, git helper aliases, and Git Bash sourcing.
- `Test-UESyncShellAliases.ps1`: validates `ue-tools`, optional `art-tools`, profile bootstrap, and compatibility shims.
- `Test-DocsTools.ps1`: validates `docs-tools` scaffolding, optional VS Code bridge install flow, TOC request queuing, and docs-site validation behavior.
- `Test-AIStartupPrompt.ps1`: validates the AI startup prompt builder output and local private-context handling.
- `Test-UnrealSync-Regeneration.ps1`: validates project-file regeneration, action-plan decisions, workspace artifact preservation, and engine-resolution fallback paths in isolation. One case intentionally forces an unresolved-engine failure and should still end in a green summary.
- `Test-UEProjectToolsInstaller.ps1`: validates portable tooling installation into a scratch UE project repo.
- `Test-InitRepoToolReadiness.ps1`: validates `Init-Repo.ps1` optional tool prerequisite setup and readiness reporting in a scratch UE project repo.
- `Test-New-ArtSourcePath.ps1`: validates canonical `ArtSource/_Template` handling and new asset folder creation.
- `Test-UnrealSync.ps1`: validates structural trigger detection and hook/non-interactive behavior on a committed clean repo.
- `Test-BinaryGuard-Fixes.ps1`: validates guarded binary conflict helpers across merge and rebase flows.

## Master Runner

- `Run-AllTests.ps1` reads `Scripts/Tests/TestManifest.ps1` and launches each selected test in a fresh `pwsh` process.
- Default behavior is serial execution of the automated suite.
- Tests that require a clean repo or existing commits are skipped with an explicit reason instead of being forced to run unsafely.
- Child test output is streamed directly to the console so native `Write-Host` colors and normal script formatting are preserved.
- Use `-List` to inspect the manifest-backed catalog.
- Use `-Name` or `-Category` to run a subset, for example `-Category unreal`.
- `-NoCleanup` and `-FailFast` are forwarded only to scripts that support those switches.
- Use `-WriteJson` when you want the runner to emit a machine-readable JSON summary alongside the suite log.

## Adding Tests

- Add the new automated test script under `Scripts/Tests/`.
- Add one entry to `Scripts/Tests/TestManifest.ps1` with its path, category, and repo-safety metadata.
- Keep repo-mutating tests marked with `RequiresCleanRepo`, `RequiresCommits`, and `MutatesRepo` so the runner can serialize and gate them correctly.
- Keep manual helpers and operational scripts out of the default automated manifest unless they are safe for unattended runs.

## Preconditions

- `Test-UnrealSync.ps1` and `Test-BinaryGuard-Fixes.ps1` require a clean repo with at least one commit.
- `Run-AllTests.ps1` will skip those tests automatically when the repo is dirty or has no commits.
- Tests write logs under `Scripts/Tests/*Results/`.
- Crash-capture scripts are opt-in operational tools, not part of the normal quick suite.

## Crash-Capture Tools

- `Collect-CrashEvidence.ps1`: bundles Unreal logs, crash folders, event logs, and system metadata.
- `Run-CrashCaptureSession.ps1`: launches the editor and arms a post-crash collection flow.

## Manual Validation Helper

Use `Scripts/Tests/Test-Setup-UESync-Manual.ps1` when you want a disposable branch that introduces a structural C++ change to manually exercise the `post-checkout` Unreal sync hook. Run it only from a clean working tree.
