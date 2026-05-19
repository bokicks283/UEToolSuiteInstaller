# UE Tool Suite Unification Architecture

This document defines the recovery path for making the installed UE tool suite feel like one coherent product while preserving existing project installs.

## Goals

- Keep user-facing commands stable while internals become cleaner.
- Make each tool domain easy to extend without editing one giant script.
- Keep installer and updater behavior in this repository, not in installed UE projects.
- Keep installed payloads limited to usable tools, docs, hook files, setup assets, and compatibility wrappers.
- Support eventual `.exe` packaging without duplicating installer logic in C#.

## Compatibility Contract

The following entrypoints should continue to work during the migration:

- `ue-tools`
- `docs-tools`
- `art-tools`
- `codex-tools`
- `codex-prompt`
- Direct PowerShell invocation of `Scripts/Unreal/UnrealSync.ps1`
- Direct PowerShell invocation of `Scripts/Docs/DocsTools.ps1`
- Direct PowerShell invocation of `Scripts/Codex/Get-CodexStartupPrompt.ps1`

New names such as `ai-tools` or `ai-prompt` can be added later, but they must be aliases or wrappers first. Do not replace the Codex-facing names until tests prove a safe deprecation path.

## Installed Payload Shape

Target shape:

```text
Scripts/
  ue-tools.ps1                         stable unified CLI entrypoint
  Init-Repo.ps1                        repo bootstrap entrypoint
  UETools/
    ue-tools.ps1                       compatibility wrapper for older installs/docs
    UETools.psd1                       module manifest
    Core.psm1
    Unreal.psm1
    Docs.psm1
    Git.psm1
    Hooks.psm1
    Prompt.psm1
    Art.psm1
    Crash.psm1
  Unreal/
    UnrealSync.ps1                     thin compatibility entrypoint
    ProjectContext.ps1                 shared project context helpers
    ProjectShellAliases.ps1            profile/bootstrap installer
    New-ArtSourcePath.ps1
  Docs/
    DocsTools.ps1                      thin compatibility entrypoint
  Codex/
    Get-CodexStartupPrompt.ps1         thin compatibility entrypoint
  git-hooks/
    hook-common.sh
    colors.sh
    Enable-GitHooks.ps1
    Test-Hooks.ps1
  git-tools/
    conflicts.ps1
    GitConflictHelpers.ps1
```

The thin compatibility entrypoints can delegate into modules over time. They should remain as stable public contracts even after the internal code moves.

## Module Rules

- A module may depend on `Core`, but cross-domain dependencies should be explicit and rare.
- The unified CLI should import a module manifest, not rely on accidental import order across loose `.psm1` files.
- Public commands should parse command names and route to domain functions; domain modules should own domain behavior.
- Shared path and project context resolution belongs in `Core` or a dedicated project context module, not copied across tools.
- Bash hook files should stay thin and call PowerShell entrypoints.

## Installer Responsibilities

The installer owns:

- target `.uproject` discovery and validation
- payload version detection
- managed path copy/merge/update
- backups
- manifest-driven migrations
- legacy cleanup policy
- optional target init execution
- `.exe` orchestration compatibility

The installed payload should not contain update logic for replacing itself.

## Payload Manifest Direction

Add a manifest before broad file moves:

```text
payload/ue-tool-suite.manifest.json
```

Minimum useful fields:

- payload version
- managed file paths
- managed directory paths
- compatibility wrapper paths
- deprecated paths to warn about
- deprecated paths safe to remove only with explicit cleanup
- profile bootstrap version
- supported installer minimum version

The installer should use the manifest as data. This avoids hard-coding every future migration directly into installer control flow.

## Shell Profile Strategy

Use one managed PowerShell profile block:

```text
# >>> ue project shell aliases >>>
# <<< ue project shell aliases <<<
```

That block should source a stable bootstrap under `%LOCALAPPDATA%\UEToolSuite\Shell\UEToolsBootstrap.ps1`. The bootstrap should resolve the current Git repo at command time and call that repo's installed CLI. This avoids pinning a user's profile to whichever UE project was initialized most recently.

Bootstrap updates must remain idempotent and versioned enough that older installed projects can be upgraded safely.

## Testing Requirements Before File Moves

Before moving entrypoints or converting major scripts into modules, add tests for:

- fresh install
- update from current `main`
- update from `feat/unify-tools-legacy-cleanup` layout
- profile bootstrap installed before an entrypoint move
- `codex-tools` and `codex-prompt` compatibility
- `-SkipCodexTools` compatibility
- direct script invocation compatibility
- docs tooling command routing
- Unreal sync dry-run/no-build/no-regen routing
- target-only docs and tests preserved on normal update
- explicit legacy cleanup backs up before removal

## Phased Plan

1. Add root-owned compatibility tests and fixture helpers.
2. Add `Scripts/ue-tools.ps1` while keeping `Scripts/UETools/ue-tools.ps1` as a forwarding wrapper.
3. Update shell bootstrap to support both old and new CLI locations.
4. Add a payload manifest and teach the installer to read it for managed paths.
5. Move one domain at a time behind compatibility entrypoints.
6. Convert `ProjectContext.ps1` and shared helpers before converting higher-level command tools.
7. Keep installer `.exe` as an orchestrator over the same PowerShell install engine.

## First Implementation Step

Start with tests and compatibility wrappers, not module extraction. The first code change should prove that an older installed suite can be updated and still run the old command names while also exposing the new unified CLI path.
