# UE Tool Suite Unification Architecture

This document describes the current architecture after the hard-cut command consolidation and module migration.

## Design Goals

- One command surface for end users (`ue-tools`, plus `ue` alias).
- Domain behavior owned by module code, not spread across unrelated scripts.
- Installer/update logic remains in this repository only.
- Installed payload stays portable and runnable inside any UE5 project repo.
- Multiple UE repos on one machine must not conflict in shell/profile behavior.

## Public Command Contract

Primary command names:

- `ue-tools`
- `ue`

Command grammar:

- Root commands: `ue-tools help`, `ue-tools build ...`
- Domain commands:
  - `ue-tools docs ...`
  - `ue-tools ai prompt ...`
  - `ue-tools art ...`
  - `ue-tools init ...`
  - `ue-tools git ...`

Git convenience aliases remain supported:

- `git ours <pattern...>`
- `git theirs <pattern...>`
- `git conflicts <subcommand>`

Those aliases route into the same dispatcher-owned git domain behavior.

## Current Payload Runtime Layout

```text
payload/
  Scripts/
    ue-tools.ps1                         only public script entrypoint
    Init-Repo.Runtime.ps1                init runtime implementation
    UETools/
      UETools.psd1                       facade manifest
      UEToolSuite.Core.psm1              shared primitives/helpers
      UEToolSuite.Dispatcher.psm1        command parse + route
      UEToolSuite.Aliases.psm1           profile/bootstrap alias install
      UEToolSuite.Unreal.psm1            build domain adapter + helpers
      UEToolSuite.Docs.psm1              docs domain adapter + helpers
      UEToolSuite.Art.psm1               art domain implementation
      UEToolSuite.AI.psm1                AI prompt domain implementation
      UEToolSuite.Init.psm1              init domain adapter + helpers
      UEToolSuite.Git.psm1               git conflict domain adapter + helpers
      UEToolSuite.Runtime.ps1            shared runtime context glue
    Unreal/
      UnrealSync.Runtime.ps1             Unreal runtime implementation
      ProjectContext.ps1                 project/engine context helpers
    Docs/
      DocsTools.Runtime.ps1              docs runtime implementation
      VSCodeBridge/                      optional docs VS Code bridge
    git-hooks/
      hook-common.sh
      colors.sh
      Enable-GitHooks.ps1
      Test-Hooks.ps1
    git-tools/
      GitConflictHelpers.Runtime.ps1
```

## Module Boundaries

- `UEToolSuite.Core.psm1`: shared path/repo/process/file utilities.
- `UEToolSuite.Dispatcher.psm1`: command parsing, help text, domain routing, install guidance.
- Domain modules:
  - Unreal, Docs, Init, and Git currently call runtime scripts (`*.Runtime.ps1`) through controlled module entrypoints.
  - AI and Art domains are implemented directly in module code.
- `UEToolSuite.Aliases.psm1`: managed profile block + bootstrap generation + alias registration.

This boundary keeps user-facing CLI stable while allowing incremental internal migration from runtime scripts into module code.

## Installer Boundary

`Install-UEToolSuite.ps1` owns:

- target repo + `.uproject` discovery/validation
- manifest-driven managed-path selection (`payload/ue-tool-suite.manifest.json`)
- marker-managed root text updates (`.gitattributes`, `.gitignore`)
- copy/merge/update of managed payload content
- backups (`.ue-tools-installer-backups/<timestamp>/`)
- legacy cleanup by explicit path list
- optional init invocation after install/update

Installed payload scripts do not self-update. Updates always come from rerunning the installer.

## Multi-Repo Shell/Profile Behavior

- One managed profile block is used:
  - `# >>> ue project shell aliases >>>`
  - `# <<< ue project shell aliases <<<`
- The block sources `%LOCALAPPDATA%\UEToolSuite\Shell\UEToolsBootstrap.ps1`.
- The bootstrap resolves the active git repo at invocation time and runs that repo's `Scripts/ue-tools.ps1`.

This prevents cross-project alias conflicts and avoids profile clutter when many UE repos are installed.

## Extension Rules

When adding tooling:

1. Add/extend module/domain code under `payload/Scripts/UETools/`.
2. Keep command parsing in dispatcher/domain module entrypoints.
3. Add payload files under `payload/` only.
4. Update `payload/ue-tool-suite.manifest.json` for managed install ownership.
5. Add/adjust tests in `Tests/` and/or `payload/Scripts/Tests/`.
6. Update docs in the same change.

Do not add new standalone public script entrypoints unless there is a strong installer/runtime reason.

## Packaging Direction

- GUI executable (`src/UEToolSuiteInstaller.Gui/`) remains a thin launcher over `Install-UEToolSuite.ps1`.
- PowerShell installer remains the single install engine for both CLI and GUI flows.
- Future packaging should continue bundling installer + payload together rather than duplicating install logic in C#.
