# Project Overview

## Purpose

UEToolSuite packages a portable set of Unreal project automation assets and local docs-authoring tooling, then installs or updates them into a target UE repository. The installer is conservative: it tracks managed files, preserves project-owned material where possible, and records backups and update candidates instead of assuming full ownership of the target repo.

Confirmed sources:

- `README.md`
- `MAINTAINER_GUIDE.md`
- `payload/ue-tool-suite.manifest.json`
- `Install-UEToolSuite.ps1`

## Major features

- portable installer/updater with backup and managed-file ledgers
- public `ue-tools` command surface for Unreal, docs, AI, init, art, and git workflows
- local Docusaurus site sourced from `Docs/`
- inline page editing and Site Settings authoring over a local loopback API
- GUI installer packaging as a self-contained Windows executable
- test runners covering installer, docs, init, packaging, shell aliases, Unreal sync, and binary conflict helpers

## Major subsystems

| Subsystem | Primary sources | Role |
|---|---|---|
| Installer | `Install-UEToolSuite.ps1`, `payload/ue-tool-suite.manifest.json` | Selects managed payload, updates target files, writes ledgers, runs init |
| Payload CLI | `payload/Scripts/ue-tools.ps1`, `payload/Scripts/UETools/*.psm1` | Implements project-local commands after installation |
| Docs website | `payload/website/docusaurus.config.ts`, `payload/website/domainCatalog.ts`, `payload/website/src/**` | Renders docs, Site Settings UI, inline editor UI |
| Docs Editor API | `payload/Scripts/UETools/DocsEditorApiHost.ps1` | Loopback HTTP API for content, structure, site settings, and visibility |
| Runtime lifecycle | `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | Starts/stops docs dev server and editor API, writes runtime state |
| GUI wrapper | `src/UEToolSuiteInstaller.Gui/Program.cs`, `Scripts/Publish-InstallerExe.ps1` | Bundles installer and payload into a Windows executable |
| Test system | `Tests/*.ps1`, `payload/Scripts/Tests/*.ps1`, `Tests/Run-UEToolSuiteTests.ps1` | Regression, contract, runtime, and workflow validation |

## Supported environments visible from the code

Confirmed from the current source:

- Windows is the explicit target for the public GUI (`net10.0-windows` in `src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj`).
- PowerShell 7 is the expected runtime for installer and payload entrypoints because the scripts invoke `pwsh`, but the module manifest still declares `PowerShellVersion = "5.1"` in `payload/Scripts/UETools/UETools.psd1`.
- Node.js 20+ is required for the docs website (`payload/website/package.json`, `engines.node`).
- Git and Git LFS are assumed for init/bootstrap flows.

> Unresolved: The exact support contract between the `pwsh`-centric runtime and the `PowerShellVersion = "5.1"` module manifest is not fully documented in-source. See [25-Open-Questions.md](25-Open-Questions.md).

## Installation targets

The authored repo installs into a target Unreal project root that contains a `.uproject` file. The installer validates the target and then writes managed paths such as `Scripts/`, `Docs/`, `.githooks/`, and `website/`.

Key installer functions:

- `Resolve-TargetUProjectPath`
- `Test-TargetLooksLikeUE5Project`
- `Read-UEToolSuitePayloadManifest`
- `Invoke-ManagedDocsSmartUpdate`

## Source repository versus installed layout

| Layer | Owner | Mutable by installer | Typical path |
|---|---|---|---|
| Authored source | This repo | No | `Install-UEToolSuite.ps1`, `payload/**`, `Tests/**` |
| Managed payload copy | Target UE repo | Yes | `Scripts/**`, `Docs/**`, `website/**` |
| Generated/runtime state | Target UE repo | Yes | `.ue-tools/state/**`, `website/static/ue-tools/editor-runtime.json`, `website/build/**` |
| Project-owned content | Target UE repo | Sometimes preserved, sometimes merged | custom docs, website overrides, game-specific files |

## Important entry points

- CLI install/update: `Install-UEToolSuite.ps1`
- GUI install/update: `src/UEToolSuiteInstaller.Gui/Program.cs`
- Installed CLI dispatcher: `payload/Scripts/ue-tools.ps1`
- Docs runtime entrypoint: `Invoke-DocsToolsMain` in `payload/Scripts/UETools/UEToolSuite.Docs.psm1`
- Docs API request entrypoint: `Invoke-EditorApiRequest` in `payload/Scripts/UETools/DocsEditorApiHost.ps1`
- Test suite entrypoint: `Tests/Run-UEToolSuiteTests.ps1`

## Expected developer workflow

1. Change installer, payload, or website source in this repo.
2. Run the narrowest relevant test suite first.
3. If payload paths or packaging contracts changed, run packaging validation.
4. Reinstall into a scratch or reference project when install behavior matters.
5. For docs runtime work, validate source, runtime descriptor, and live API identity separately.

## System in one page

The repository is not just a script collection. It is a distribution source for a project-local tool platform.

- Root scripts decide what gets installed and how updates behave.
- `payload/` is the install contract for the target project.
- Inside the target project, `ue-tools.ps1` loads nested modules and dispatches domain commands.
- The docs subsystem is split between a Docusaurus frontend and a PowerShell loopback API that writes directly to the active repo.
- The GUI wrapper does not replace the PowerShell installer; it packages and launches it.
- Tests are split between root-level installer/packaging suites and payload-level domain suites.
