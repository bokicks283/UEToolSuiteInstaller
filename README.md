# UE Tool Suite Installer

Standalone installer/updater for a portable Unreal Engine 5 tooling suite.

This repository owns:
- installer/update logic (`Install-UEToolSuite.ps1`)
- installable payload (`payload/`)
- validation suites (`Tests/` and `payload/Scripts/Tests/`)
- `.exe` packaging wrapper (`src/UEToolSuiteInstaller.Gui/`)

For full architecture, tool-by-tool behavior, implementation details, and maintainer workflows, read:
- [MAINTAINER_GUIDE.md](MAINTAINER_GUIDE.md)

## Quick Start

Install/update into a target UE5 repo:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync
```

The installer uses `payload/ue-tool-suite.manifest.json` to decide managed paths and marker-managed root text blocks (`.gitattributes`, `.gitignore`).

By default, replaced managed content is backed up under:
- `.ue-tools-installer-backups/<timestamp>/`

## Common Installer Switches

- `-RunInit`
- `-SkipLfsPull`
- `-SkipShellAliases`
- `-SkipOptionalToolSetup`
- `-SkipDocsSetup`
- `-SkipDocsNpmInstall`
- `-SkipDocsBridgeInstall`
- `-SkipUnrealSync`
- `-NoBuild`
- `-NoRegen`
- `-SkipDocs`, `-SkipWebsite`, `-SkipTests`, `-SkipCodexTools`, `-SkipArtSourceTools`, `-SkipCodingStandardsTools`
- `-NoBackup`
- `-NoLegacyCleanup`

## Test Entry Points

Non-mutating/default suite:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -FailFast
```

Mutating/exclusive suites:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '.\Tests\Run-UEToolSuiteTests.ps1' -IncludeExclusive -Name @('ue-sync-automated','binary-guard-fixes') -FailFast"
```

## Build `.exe` Installer

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0
```

Output:
- `dist/UEToolSuiteInstaller-<version>-win-x64.exe`

## Related Docs

- [MAINTAINER_GUIDE.md](MAINTAINER_GUIDE.md)
- [docs/Usage-Build-Release-Guide.md](docs/Usage-Build-Release-Guide.md)
- [docs/Tooling-Unification-Architecture.md](docs/Tooling-Unification-Architecture.md)
- [payload/Scripts/README.md](payload/Scripts/README.md)
