# UE Tool Suite Installer

Standalone installer/updater for the portable Unreal Engine 5 repo tooling used by this workspace.

The installer copies the bundled `payload/` into a target UE 5 project, updates older installed versions, optionally runs the target repo's `Scripts/Init-Repo.ps1`, and removes the old in-project transfer script path (`Scripts/Install-UEProjectTools.ps1`) when present.

## Quick Start

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync
```

Use this for an update pass:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync
```

The installer overwrites managed tool-suite paths by design and backs up replaced paths under `.ue-tools-installer-backups/<timestamp>/` unless `-NoBackup` is supplied.

## What It Installs

- Git hooks and hook helpers under `.githooks/` and `Scripts/git-hooks/`
- Git conflict helpers under `Scripts/git-tools/`
- Unreal tools under `Scripts/Unreal/`
- Repo bootstrap under `Scripts/Init-Repo.ps1`
- Docs tooling under `Scripts/Docs/`
- Optional Codex helpers under `Scripts/Codex/`
- Optional tests under `Scripts/Tests/`
- Generic setup/workflow docs under `Docs/`
- Docusaurus app under `website/`

Source-project-specific game design, target-structure, and local project-context docs are not bundled in the payload.

## Profile Behavior

`Init-Repo.ps1` installs one managed PowerShell profile block with stable markers:

```text
# >>> ue project shell aliases >>>
# <<< ue project shell aliases <<<
```

Installing this suite into another project updates that single block instead of adding a new block per project. The aliases resolve commands from the current git repo, so `ue-tools`, `docs-tools`, `art-tools`, and `codex-tools` work from any project that has the suite installed.

Use `-SkipShellAliases` when running in CI or when you do not want the installer-run init step to touch the PowerShell profile.

## Useful Switches

- `-RunInit`: run the target repo bootstrap after copying.
- `-SkipLfsPull`: skip `git lfs pull` during the optional init step.
- `-SkipUnrealSync`: skip the first Unreal sync during init.
- `-NoBuild`: run project-file setup without the first editor build.
- `-NoRegen`: skip project-file regeneration during init.
- `-SkipDocsNpmInstall`: copy docs and website files without running npm install during init.
- `-SkipDocsBridgeInstall`: skip optional VS Code docs bridge install.
- `-SkipDocs`, `-SkipWebsite`, `-SkipTests`, `-SkipCodexTools`, `-SkipArtSourceTools`: install a smaller subset.
- `-NoBackup`: replace managed paths without writing `.ue-tools-installer-backups/`.

## Maintaining The Payload

Refresh `payload/` from the source tool-suite repo when the tools change. Keep installer/updater logic in this repository; installed UE projects should only contain the usable suite files.
