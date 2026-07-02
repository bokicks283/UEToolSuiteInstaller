# UEToolSuite Developer Documentation

## What UEToolSuite is

UEToolSuite is a Windows-first Unreal Engine project tooling suite distributed from this repository into target UE repositories. The authored source of truth lives here in two layers:

- Repository root: installer, release, GUI wrapper, test orchestration, packaging, and maintainer docs.
- `payload/`: the installable tool suite copied into target projects.

Confirmed source anchors:

- Installer entrypoint: `Install-UEToolSuite.ps1` (`param(...)`, `Read-UEToolSuitePayloadManifest`, `Invoke-ManagedDocsSmartUpdate`, `if ($RunInit)` at `Install-UEToolSuite.ps1:4`, `Install-UEToolSuite.ps1:178`, `Install-UEToolSuite.ps1:2000`, `Install-UEToolSuite.ps1:2828`)
- Public CLI entrypoint: `payload/Scripts/ue-tools.ps1`
- Command dispatcher: `payload/Scripts/UETools/UEToolSuite.Dispatcher.psm1` (`Invoke-UEToolSuiteDispatcher`)
- Docs runtime/API: `payload/Scripts/UETools/UEToolSuite.Docs.psm1`, `payload/Scripts/UETools/DocsEditorApiHost.ps1`
- Docs website: `payload/website/docusaurus.config.ts`, `payload/website/domainCatalog.ts`, `payload/website/src/theme/**`
- GUI wrapper: `src/UEToolSuiteInstaller.Gui/Program.cs`

## What this documentation covers

This suite documents the current authored repository, including:

- installer/update flow
- managed payload layout and ownership
- PowerShell module structure
- docs website, runtime discovery, and local authoring API
- domains, sidebars, navigation, and visibility behavior
- process lifecycle and runtime state
- test system and release packaging
- known risks, unresolved areas, and takeover guidance

## Intended audience

Use this documentation if you are:

- taking over repository ownership
- debugging install/update behavior
- changing `ue-tools` PowerShell behavior
- changing docs authoring, Site Settings, or the local Docs Editor API
- validating packaging, release, or deployment parity

## Recommended reading order

Start with [00-Reading-Order.md](00-Reading-Order.md), then [01-Project-Overview.md](01-Project-Overview.md), [02-Repository-Map.md](02-Repository-Map.md), and [03-Architecture.md](03-Architecture.md).

## Documentation conventions

- `Confirmed behavior`: directly supported by current source and, where noted, current tests.
- `Inferred intent`: likely design intent inferred from code structure, naming, tests, or older repo docs, but not fully proven by one source.
- `Unresolved`: a behavior or guarantee that could not be proven from the current checkout without a live experiment or broader evidence.
- `Generated files`: build output or runtime state such as `payload/website/build/**`, `.docusaurus/**`, or installed runtime state under `.ue-tools/state/**`.
- `Installed files`: files copied into a target UE repo during install/update.
- `Source files`: authored files in this repository that define installer, payload, tests, docs website, or packaging behavior.

## Source-reference conventions

- Paths are repository-relative.
- Symbols are named explicitly whenever the behavior is tied to a function, component, route handler, manifest key, or test case.
- Line numbers are included when they materially help navigation in the current checkout.
- Existing docs are treated as secondary evidence unless the current source matches them.

## Document map

- [00-Reading-Order.md](00-Reading-Order.md)
- [01-Project-Overview.md](01-Project-Overview.md)
- [02-Repository-Map.md](02-Repository-Map.md)
- [03-Architecture.md](03-Architecture.md)
- [04-Installation-and-Updates.md](04-Installation-and-Updates.md)
- [05-PowerShell-Modules.md](05-PowerShell-Modules.md)
- [06-Docs-System.md](06-Docs-System.md)
- [07-Docs-Editor-API.md](07-Docs-Editor-API.md)
- [08-Frontend-Authoring.md](08-Frontend-Authoring.md)
- [09-Domains-Sidebars-and-Navigation.md](09-Domains-Sidebars-and-Navigation.md)
- [10-Process-Lifecycle.md](10-Process-Lifecycle.md)
- [11-File-Management-and-Packaging.md](11-File-Management-and-Packaging.md)
- [12-Configuration-and-State.md](12-Configuration-and-State.md)
- [13-Testing.md](13-Testing.md)
- [14-Debugging-and-Troubleshooting.md](14-Debugging-and-Troubleshooting.md)
- [15-Extending-UEToolSuite.md](15-Extending-UEToolSuite.md)
- [16-Developer-Takeover-Guide.md](16-Developer-Takeover-Guide.md)
- [17-Known-Risks-and-Technical-Debt.md](17-Known-Risks-and-Technical-Debt.md)
- [18-Glossary.md](18-Glossary.md)
- [19-Command-Reference.md](19-Command-Reference.md)
- [20-API-Reference.md](20-API-Reference.md)
- [21-Source-File-Index.md](21-Source-File-Index.md)
- [22-Data-Flows-and-Sequences.md](22-Data-Flows-and-Sequences.md)
- [23-Security-and-Trust-Boundaries.md](23-Security-and-Trust-Boundaries.md)
- [24-Deployment-Verification.md](24-Deployment-Verification.md)
- [25-Open-Questions.md](25-Open-Questions.md)
- [modules/PowerShell-Function-Catalog.md](modules/PowerShell-Function-Catalog.md)
- [modules/Frontend-Component-Catalog.md](modules/Frontend-Component-Catalog.md)
- [modules/Frontend-Hook-and-Utility-Catalog.md](modules/Frontend-Hook-and-Utility-Catalog.md)
- [modules/API-Route-Catalog.md](modules/API-Route-Catalog.md)
- [modules/Test-Catalog.md](modules/Test-Catalog.md)
- [modules/Configuration-Catalog.md](modules/Configuration-Catalog.md)
