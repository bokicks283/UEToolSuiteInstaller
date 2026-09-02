# Developer Takeover Guide

## First-day setup

Required software visible from the code:

- PowerShell 7
- Git
- Git LFS
- Node.js 20+
- .NET 10 SDK for GUI packaging work
- Unreal Engine tooling when changing Unreal build flows

Suggested first commands:

```powershell
git status --short --branch
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Tests/Run-UEToolSuiteTests.ps1 -List
Push-Location payload/website; npm run typecheck; Pop-Location
```

## Mental model

Think of the repo as a distribution source for a project-local tool platform:

- root decides installation and release behavior
- payload becomes the installed command/runtime surface
- docs authoring is a local full-stack feature inside the installed project
- tests are split between distribution behavior and installed-domain behavior

## High-risk files

| File | Why risky | What depends on it |
|---|---|---|
| `Install-UEToolSuite.ps1` | touches managed-file ownership, update semantics, init invocation | install/update, GUI, installer tests |
| `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | owns docs lifecycle, site helpers, CLI surface, runtime state | docs commands, frontend discovery, docs tests |
| `payload/Scripts/UETools/DocsEditorApiHost.ps1` | owns direct repo mutation routes | Site Settings, inline editor, docs API tests |
| `payload/website/domainCatalog.ts` | central route/sidebar/nav synthesis | Docusaurus config, Site Settings expectations, docs tests |
| `payload/website/src/theme/DocItem/Layout/index.tsx` | large concentration point for editor behavior | inline editing, save/visibility UX |
| `src/UEToolSuiteInstaller.Gui/Program.cs` | packages and forwards public installer behavior | publish flow, packaging contracts |

## Safe starter changes

- documentation updates outside install contracts
- small additions to command/help text with matching tests
- packaging/readme changes that do not affect runtime behavior

## Change checklists

For any non-trivial change, verify at least:

- owning tests run
- packaging contracts still match if managed files changed
- install/runtime parity still makes sense for the affected subsystem

## Release checklist

1. Run non-mutating suites.
2. Run exclusive mutating suites separately if the change touches those areas.
3. Run website checks if frontend/docs source changed.
4. Validate a release through `Scripts/Publish-GitHubRelease.ps1 -Version <version> -ValidateOnly`.
5. Publish through `Scripts/Publish-GitHubRelease.ps1 -Version <version>`; it runs release gates, builds the installer, pushes the tag, and creates the GitHub Release.

## Incident checklist

Before restarting or reinstalling:

- preserve `.ue-tools/state/**`
- preserve `website/static/ue-tools/editor-runtime.json`
- preserve docs runtime stdout/stderr logs
- capture installed-vs-source parity evidence when drift is suspected
