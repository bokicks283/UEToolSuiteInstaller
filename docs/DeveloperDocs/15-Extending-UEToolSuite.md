# Extending UEToolSuite

## General rule

Extend the smallest layer that owns the behavior already. Do not fix an installer concern in the frontend or a docs tree concern in the GUI wrapper.

## Common extension patterns

### Add a PowerShell command

- usually change `payload/Scripts/UETools/UEToolSuite.Dispatcher.psm1`
- change the owning domain module
- add or update tests in `payload/Scripts/Tests/` or `Tests/`

### Add a shared PowerShell helper

- prefer `UEToolSuite.Core.psm1` only for truly cross-domain helpers
- otherwise keep helpers inside the owning domain module

### Add an Editor API route

- add handler logic to `DocsEditorApiHost.ps1`
- add typed frontend caller if needed
- add docs-tools route coverage in `Test-DocsTools.ps1`

### Add a frontend API client call

- add typed helper or hook in `payload/website/src/theme/authoring/`
- keep rendering separate from transport

### Add a docs metadata field

- confirm whether it belongs in page front matter, `_category_.json`, or `_domains.json`
- update both PowerShell and TypeScript readers if the field crosses frontend/API boundaries

### Add an installer-managed file

- update `payload/ue-tool-suite.manifest.json`
- update the relevant managed-file index if the file belongs to docs or website indexing
- run packaging contracts

### Add a test

- root install/packaging behavior: `Tests/`
- installed payload behavior: `payload/Scripts/Tests/`
- prefer a new named case over weakening an existing assertion

## Compatibility checklist

- keep public command names stable
- keep managed path names stable unless install contracts intentionally change
- keep runtime identity fields aligned between docs module, API host, and frontend
- update packaging tests when a managed asset list changes

## Deployment concerns

- website source changes may require build/install parity review
- runtime changes may require both lifecycle validation and frontend identity validation
- docs model changes may require both `domainCatalog.ts` and API mutation updates
