# EXE Installer Architecture Guide

This document explains how the public Windows installer executable is built, how the GUI works, and how GUI options map to installer flags.

## 1) Build and Packaging Model

The GUI executable is a thin launcher around the existing PowerShell installer engine.

Runtime/build components:

- GUI app: `src/UEToolSuiteInstaller.Gui/Program.cs`
- GUI project file: `src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj`
- Installer engine: `Install-UEToolSuite.ps1`
- Payload source-of-truth: `payload/`
- Publish script: `Scripts/Publish-InstallerExe.ps1`

Packaging behavior:

- `dotnet publish` creates a self-contained single-file WinForms executable.
- `Install-UEToolSuite.ps1` and `payload/**` are included as content in the publish output.
- The GUI locates the bundled installer/payload at runtime and executes `pwsh.exe -File Install-UEToolSuite.ps1 ...`.

## 2) GUI Structure and Control Flow

Main form structure:

- Top panel:
  - title/subtitle
  - `.uproject` picker
  - core options
  - advanced options (hidden by default, collapsible)
  - install/cancel buttons + terminal toggle
  - always-visible progress bar and status text
- Bottom panel:
  - terminal output textbox (hidden by default)
  - resizable split pane when shown

Install lifecycle:

1. User picks `.uproject`.
2. GUI resolves project root from selected file.
3. GUI validates bundled installer/payload and `pwsh.exe`.
4. GUI constructs installer arguments from selected options.
5. GUI starts installer process with stdout/stderr redirected.
6. GUI updates progress from installer/init log markers.
7. On success:
   - prompt `Install in another project?`
   - `Yes` resets form for next project
   - `No` exits app
8. On failure/timeout/cancel:
   - terminal pane is forced visible
   - user sees explicit message with failure context
   - form remains open

## 3) Option-to-Flag Mapping

Core options:

| GUI option | Installer switch |
|---|---|
| Run repo initialization after install | `-RunInit` |
| Init non-interactive mode | `-InitNonInteractive` (only when `-RunInit`) |
| Skip Git LFS pull during init | `-SkipLfsPull` (only when `-RunInit`) |
| Skip first Unreal sync during init | `-SkipUnrealSync` (only when `-RunInit`) |
| Skip PowerShell shell alias install during init | `-SkipShellAliases` (only when `-RunInit`) |
| Replace managed paths without backups | `-NoBackup` |

Advanced payload scope options:

| GUI option | Installer switch |
|---|---|
| Skip Docs payload | `-SkipDocs` |
| Skip website payload | `-SkipWebsite` |
| Adopt existing unmanaged website | `-AdoptExistingWebsite` |
| Skip payload test scripts | `-SkipTests` |
| Skip AI docs/tooling payload | `-SkipAITools` |
| Skip ArtSource tooling payload | `-SkipArtSourceTools` |
| Skip coding standards payload | `-SkipCodingStandardsTools` |

Advanced init/build options:

| GUI option | Installer switch |
|---|---|
| Skip optional tool setup during init | `-SkipOptionalToolSetup` |
| Skip docs setup during init | `-SkipDocsSetup` |
| Skip docs npm install during init | `-SkipDocsNpmInstall` |
| Force docs npm install during init | `-ForceDocsNpmInstall` |
| Skip docs VS Code bridge install | `-SkipDocsBridgeInstall` |
| Run init build flow without compile step | `-NoBuild` |
| Run init build flow without regen step | `-NoRegen` |

Internal switches intentionally not exposed in GUI:

- `-PayloadRoot`
- `-NoLegacyCleanup`

## 4) Dependency Rules in GUI

The GUI enforces option dependencies before command construction:

- If `Run repo initialization after install` is disabled:
  - all init-specific options are disabled.
- If `Skip website payload` is enabled:
  - website theme/logo controls are disabled.
  - `Adopt existing unmanaged website` is disabled.
- If `Skip docs setup during init` is enabled:
  - docs setup sub-options (`Skip/Force npm install`, `Skip docs bridge install`) are disabled.
- `Skip docs npm install` and `Force docs npm install` are mutually exclusive.
- If `Skip first Unreal sync during init` is enabled:
  - `NoBuild` and `NoRegen` are disabled.

## 5) Process, Progress, Timeout, and Cancel

Process execution details:

- `ProcessStartInfo.UseShellExecute = false`
- `RedirectStandardOutput = true`
- `RedirectStandardError = true`
- output is appended to GUI terminal textbox

Progress behavior:

- progress bar is always visible
- progress increments on known markers such as:
  - payload discovery / manifest load
  - managed path copy completion
  - init bootstrap start
  - init repo stage markers
  - final installer completion marker

Timeout/cancel behavior:

- idle timeout: no output for configured window triggers termination
- max runtime timeout: hard upper bound for install duration
- cancel button:
  - signals cancellation token
  - attempts process tree kill best-effort
  - surfaces cancellation status in UI/log

## 6) Icon and Branding

Current icon wiring:

- placeholder icon file: `src/UEToolSuiteInstaller.Gui/Assets/UEToolSuiteInstaller.ico`
- project property: `<ApplicationIcon>Assets\UEToolSuiteInstaller.ico</ApplicationIcon>`
- form icon set from executable icon at runtime

To replace branding:

1. Replace `Assets/UEToolSuiteInstaller.ico` with your production icon.
2. Re-run publish script.
3. Validate icon in Explorer and in window title bar.

## 7) How to Add a New GUI Option Safely

When adding a new installer switch to GUI:

1. Add control field + UI label in `Program.cs`.
2. Add dependency behavior in `ApplyOptionDependencies()` if needed.
3. Add mapping into `CollectInstallOptions()` and installer argument builder.
4. Update `Tests/Test-PackagingContracts.ps1` with a contract assertion.
5. Update docs (`README.md`, `MAINTAINER_GUIDE.md`, `docs/Usage-Build-Release-Guide.md`, and this guide).
6. Run full test cadence:
   - non-mutating suite
   - `ue-sync-automated`
   - `binary-guard-fixes`
