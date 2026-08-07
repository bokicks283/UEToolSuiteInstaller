# Glossary

## Core repository terms

| Term | Meaning | Primary source |
|---|---|---|
| installer repository | This repository. It owns install/update logic, payload contents, tests, packaging, and maintainer docs. | `Install-UEToolSuite.ps1`, `README.md` |
| payload | The installable tool suite under `payload/`. These files are copied into target Unreal project repositories. | `payload/ue-tool-suite.manifest.json` |
| target repo | A user Unreal project repository that receives the payload. | `Install-UEToolSuite.ps1` |
| managed file | A file or directory the installer considers under its ownership and may overwrite or remove during updates. | `payload/ue-tool-suite.manifest.json`, `Install-UEToolSuite.ps1` |
| managed ledger | JSON index written into installed projects to remember previously managed Docs or website files. | `Read-ManagedDocsLedger`, `Write-ManagedDocsLedger`, `Read-ManagedWebsiteLedger`, `Write-ManagedWebsiteLedger` |
| preserve-first update | Current Docs/website update behavior that avoids overwriting customized user content when hashes or markers show drift. | `Invoke-ManagedDocsSmartUpdate`, `README.md` |
| backup root | Timestamped install backup directory under `.ue-tools-installer-backups/`. | `Copy-ToBackup` |
| update candidates | Preserved files staged under `.ue-tools-installer-updates/<timestamp>/` when the installer declines to overwrite local drift. | `Invoke-ManagedDocsSmartUpdate` |

## Docs system terms

| Term | Meaning | Primary source |
|---|---|---|
| Docs root | The `Docs/` tree inside an installed repo. Docusaurus reads content from here. | `payload/website/docusaurus.config.ts` |
| website root | The installed `website/` folder that contains Docusaurus config, source, static assets, and builds. | `payload/website/package.json` |
| domain | A top-level documentation ownership grouping defined in `Docs/_domains.json` and consumed by `domainCatalog.ts`. | `payload/website/domainCatalog.ts`, `DocsEditorApiHost.ps1` |
| general docs | Docs not owned by an explicit domain. The catalog may assign them a separate sidebar. | `getDocsDomainCatalog` |
| landing doc | The README or index page associated with a directory or domain. | `domainCatalog.ts` |
| section | A directory treated as a navigable docs grouping, usually backed by `_category_.json`. | `UEToolSuite.Docs.psm1`, `DocsEditorApiHost.ps1` |
| legacy section | A directory that behaves like a section but lacks `_category_.json`, requiring migration. | `Invoke-DocsSectionMigration`, `Test-DocsTools.ps1` Case `1j` |
| visibility / unlisted | Docusaurus front matter state used to hide a page or landing doc from navigation. | `Set-DocsPageVisibility`, `isDocHiddenFromSidebar` |
| sidebar id | Stable identifier used by Docusaurus sidebar config and frontend/domain APIs. | `getSidebarIdFromDomainPath`, `toSidebarId` |
| source token | Repo-relative Docs path token used by page authoring UI and API routes. | `resolveSourceToken`, `getDocPageAuthoringState` |

## Runtime and API terms

| Term | Meaning | Primary source |
|---|---|---|
| Docs Editor API | Local `HttpListener` process hosted by `DocsEditorApiHost.ps1` for authoring, tree, domain, and site-setting mutations. | `DocsEditorApiHost.ps1` |
| runtime descriptor | `editor-runtime.json` written by the docs lifecycle code so the frontend can find and validate the local API. | `Write-DocsEditorRuntimeConfig`, `runtimeDiscovery.ts` |
| health identity | The `/health` payload fields used to prove the API matches the expected project, docs root, process, and API version. | `Invoke-EditorApiRequest`, `compareRuntimeIdentity` |
| tracked runtime | Background docs server or API process with state recorded under `.ue-tools/state/**`. | `Get-DocsServerEntries`, `Get-DocsEditorApiEntry` |
| stale state | Recorded runtime metadata whose process is gone or no longer validates. | `Get-DocsEditorApiStatus`, `Invoke-DocsStatus` |
| background mode | `ue-tools docs start --background`, which starts Docusaurus and the editor API in detached processes and writes state/log paths. | `Invoke-DocsStartBackground` |
| foreground mode | `ue-tools docs start`, which starts Docusaurus in the current terminal and usually starts/stops the editor API around it. | `Invoke-DocsStartForeground` |

## Testing and packaging terms

| Term | Meaning | Primary source |
|---|---|---|
| suite manifest | Test metadata returned by `Get-UEToolSuiteTestManifest`, used by the root test runner. | `Tests/ToolSuiteManifest.ps1` |
| installed fixture | Scratch Unreal repo created by tests, installed with the tool suite, then used for integration scenarios. | `New-InstalledToolSuiteFixture` |
| packaging contracts | Tests that validate which files the repo promises to ship in payloads, GUI packaging, and release automation. | `Tests/Test-PackagingContracts.ps1` |
| exclusive suite | A test suite marked as mutating or requiring exclusive repo access, not run by default. | `ToolSuiteManifest.ps1` |

## Documentation status vocabulary

| Label | Meaning |
|---|---|
| Confirmed behavior | Directly supported by the current source, and by tests where cited. |
| Inferred intent | Likely design intent supported by structure or naming, but not proved by one authoritative source. |
| Unresolved | A behavior or guarantee that could not be proved from the current checkout without a live experiment or missing evidence. |
