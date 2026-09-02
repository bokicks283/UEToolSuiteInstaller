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

Every install places the reusable CLI runtime under `%LOCALAPPDATA%\UEToolSuite\versions\<version>`, maintains stable launchers under `%LOCALAPPDATA%\UEToolSuite\bin`, and leaves a small `Scripts\ue-tools.ps1` forwarding shim in the project. Git hooks, docs content, and the Docusaurus site remain project-local. Repository test suites stay in this source repository and are not shipped to installed projects.

Unless `-SkipArtSourceTools` is selected, installation creates the project-local `ArtSource/_Template` layout with `Source`, `Textures`, and `Exports` folders so a new project is immediately ready for `ue-tools art`.

The installer uses `payload/ue-tool-suite.manifest.json` to decide managed paths and marker-managed root text blocks (`.gitattributes`, `.gitignore`).

Docs and website updates are preserve-first:
- existing unmanaged `website/` folders are left untouched by default
- managed docs defaults are only auto-updated when the file matches the last installed hash
- customized/default-missing docs files are preserved and staged as candidates under `.ue-tools-installer-updates/<timestamp>/`
- when init runs docs setup, website npm dependencies are synchronized deterministically (uses `npm ci` when `website/package-lock.json` is present, otherwise `npm install`)
- dependency synchronization now validates required packages from `website/package.json` and re-runs npm when deps drift, not just when `website/node_modules` is missing

By default, replaced managed content is backed up under:
- `.ue-tools-installer-backups/<timestamp>/`

## Common Installer Switches

- `-RunInit`
- `-InitNonInteractive` (runs `ue-tools init` without prompts; recommended for automation/GUI)
- `-SkipLfsPull`
- `-SkipShellAliases`
- `-SkipOptionalToolSetup`
- `-SkipDocsSetup`
- `-SkipDocsNpmInstall`
- `-SkipDocsBridgeInstall`
- `-SkipUnrealSync`
- `-NoBuild`
- `-NoRegen`
- `-SkipDocs`, `-SkipWebsite`, `-SkipAITools`, `-SkipArtSourceTools`, `-SkipCodingStandardsTools`
- `-AdoptExistingWebsite` (explicitly convert an existing unmanaged `website/` folder to installer-managed)
- `-WebsiteTheme <id>` (default: `neutral`)
- `-WebsiteLogoPath <path-to-svg-or-png>`
- `-NoBackup`
- `-NoLegacyCleanup`

The GUI installer now runs `-RunInit` with `-InitNonInteractive` by default, shows stage progress in a progress bar, and keeps terminal output available behind a `Show terminal output` toggle.
The terminal panel starts hidden by default, can be toggled on demand, and is resizable when shown. After a successful install, the GUI asks whether to install into another project (Yes resets the form, No exits).
Core installer controls include docs theme preset selection and optional SVG/PNG logo branding; advanced options remain hidden by default and expose all user-safe installer/init flags, including explicit `-SkipShellAliases` control.

Docs dependency update policy:
- `payload/website/package-lock.json` is committed and treated as the install contract.
- Installer/init prefers `npm ci` against that lockfile to avoid unexpected dependency drift.
- `.github/dependabot.yml` opens weekly dependency PRs for `payload/website`.
- Dependency PRs should pass docs build + suite gates before merge.

Website theme presets:
- `neutral`, `graphite`, `ocean`, `forest`, `amber`, `violet`
- `cobalt`, `teal`, `jade`, `indigo`, `crimson`, `rose`, `copper`, `slate`

Override behavior for existing websites:
- managed `website/`: installer applies theme/branding immediately
- unmanaged `website/`: installer preserves by default and blocks overrides
- explicit adopt + override:
  - `Install-UEToolSuite.ps1 ... -AdoptExistingWebsite -WebsiteTheme <id> [-WebsiteLogoPath <path>]`
  - `ue-tools docs theme apply <id> --adopt-existing [-LogoPath <path>]`

## Test Entry Points

Non-mutating/default suite:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -FailFast
```

Mutating/exclusive suites:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -IncludeExclusive -Name ue-sync-automated -FailFast
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -IncludeExclusive -Name binary-guard-fixes -FailFast
```

## Build `.exe` Installer

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 1.0.0
```

Output:
- `dist/UEToolSuiteInstaller-<version>-win-x64.exe`

## Related Docs

- [MAINTAINER_GUIDE.md](MAINTAINER_GUIDE.md)
- [docs/Manual-Testing-Checklist.md](docs/Manual-Testing-Checklist.md)
- [docs/EXE-Code-Signing-Certificate-Guide.md](docs/EXE-Code-Signing-Certificate-Guide.md)
- [docs/Usage-Build-Release-Guide.md](docs/Usage-Build-Release-Guide.md)
- [docs/EXE-Installer-Architecture.md](docs/EXE-Installer-Architecture.md)
- [docs/Tooling-Unification-Architecture.md](docs/Tooling-Unification-Architecture.md)
- [payload/Scripts/README.md](payload/Scripts/README.md)
