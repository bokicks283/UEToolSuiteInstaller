# UE Tool Suite Installer

Standalone installer/updater for the portable Unreal Engine 5 repo tooling used by this workspace.

The installer copies the bundled `payload/` into a target UE 5 project, updates older installed versions, optionally runs the target repo's `Scripts/Init-Repo.ps1`, and removes the old in-project transfer script path (`Scripts/Install-UEProjectTools.ps1`) when present.

Root `.gitattributes` and `.gitignore` are installed as managed marker blocks instead of whole-file replacements, so existing project-specific rules are preserved while the tool suite can keep the Unreal/Git LFS binary guard rules current.

For the full user, maintainer, build, release, and code-signing guide, see [docs/Usage-Build-Release-Guide.md](docs/Usage-Build-Release-Guide.md).

## Quick Start

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync
```

Use this for an update pass:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync
```

The installer overwrites managed tool-suite paths by design and backs up replaced paths under `.ue-tools-installer-backups/<timestamp>/` unless `-NoBackup` is supplied.

Backups mirror the original relative paths, so a backed-up `Scripts/Unreal/UnrealSync.ps1` is restored by copying it from the matching timestamp folder back to `Scripts/Unreal/UnrealSync.ps1`. Root `.gitattributes` and `.gitignore` are backed up before their managed blocks are inserted or refreshed.

When a managed payload directory already exists in the target repo, the installer merges payload files into that directory instead of deleting the whole directory first. Target-only files such as `Docs/Codex/Project-Context.md`, local docs pages, or project-specific test scripts are preserved. Files that are also present in `payload/` are replaced and backed up before replacement.

## What It Installs

- Git hooks and hook helpers under `.githooks/` and `Scripts/git-hooks/`
- Managed Unreal/Git LFS rules in `.gitattributes` and Unreal/generated-file ignores in `.gitignore`
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
- `-SkipCodingStandardsTools`: omit the bundled coding-standard docs.
- `-NoBackup`: replace managed paths without writing `.ue-tools-installer-backups/`.
- `-NoLegacyCleanup`: leave the old `Scripts/Install-UEProjectTools.ps1` path in place.

## Distribution Options

To avoid asking teammates to clone this repo:

- Recommended: build a signed self-contained installer executable that bundles `payload/`, opens a file picker for the target UE 5 `.uproject`, and calls the same installer logic. This is the cleanest teammate flow, but adds signing, versioning, and antivirus reputation work.
- Publish a GitHub Release zip that contains `Install-UEToolSuite.ps1` and `payload/`. This is simple and transparent, but users still need to unzip and run a PowerShell command.
- Add a release bootstrap script that downloads the latest zip, expands it to a temp folder, and invokes the installer for the current repo. This keeps the artifact small, but still asks users to run a command.
- For a larger team, publish an internal package through winget, Chocolatey, or a private package feed. That gives versioned installs and updates without manual zip handling.

## Public Release Build

The public Windows artifact is a .NET Windows Forms launcher at `src/UEToolSuiteInstaller.Gui/`. It bundles `Install-UEToolSuite.ps1` and `payload/`, lets the user choose a `.uproject` file, and invokes the existing installer with safe defaults:

- Run repo initialization after install.
- Skip the first Git LFS pull during init.
- Skip the first Unreal sync during init.
- Install the managed PowerShell alias block.
- Keep backups enabled.

Build it with the .NET 10 SDK:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0
```

For public releases, sign the artifact:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0 -CertificateThumbprint <thumbprint>
```

The release output is written to `dist/UEToolSuiteInstaller-<version>-win-x64.exe`. Users still need PowerShell 7 installed because the bundled tool suite scripts run on `pwsh`.

The GitHub Actions release workflow builds on `v*` tags and supports optional signing with these repository secrets:

- `WINDOWS_CODESIGN_PFX_BASE64`: base64-encoded code-signing `.pfx`.
- `WINDOWS_CODESIGN_PFX_PASSWORD`: password for the `.pfx`.

A self-signed local test certificate helper is available at `Scripts/New-TestCodeSigningCertificate.ps1`, but public releases should use a trusted certificate or signing service. See the guide for details.

## Maintaining The Payload

This repository is the source of truth for the portable UE tool suite. Update `payload/` directly when the tools change, then run the installer tests before publishing a release. Keep installer/updater logic in this repository; installed UE projects should only contain the usable suite files.
