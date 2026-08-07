# Debugging and Troubleshooting

## API unreachable

Symptoms:

- Site Settings shows connection failure
- doc pages hide Edit/Hide controls

First checks:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File Tests/Run-UEToolSuiteTests.ps1 -Name docs-tools -FailFast
pwsh -NoLogo -NoProfile -Command "Get-Content -Raw .\\payload\\website\\static\\ue-tools\\editor-runtime.json"
```

Relevant source:

- `payload/website/src/theme/authoring/runtimeDiscovery.ts`
- `payload/Scripts/UETools/UEToolSuite.Docs.psm1`
- `payload/Scripts/UETools/DocsEditorApiHost.ps1`

## Health returns 200 but frontend rejects it

Likely subsystem:

- runtime identity validation

Relevant checks:

- `applicationId`
- `apiVersion`
- `capabilities.authoringApiVersion`
- normalized `repoRoot`
- normalized `docsRoot`
- `processId`

Relevant source:

- `compareRuntimeIdentity()` in `runtimeDiscovery.ts`
- `Invoke-DocsEditorApiHealthProbe` in `UEToolSuite.Docs.psm1`

## Runtime descriptor is stale

Symptoms:

- `editor-runtime.json` exists
- frontend still cannot connect
- status may report stale state or conflict

Safe recovery:

1. run `ue-tools docs status`
2. run `ue-tools docs stop`
3. run `ue-tools docs start --background`

## Duplicate API processes or occupied ports

Likely subsystem:

- docs lifecycle ownership

Relevant source:

- `Resolve-DocsEditorApiPort`
- `Get-DocsEditorApiStatus`
- `Start-DocsEditorApiBackground`
- `Stop-DocsEditorApiBackground`

## Edit button missing on a doc page

Likely reasons:

- page token is not a markdown page
- runtime is not available
- page fell back to source-only mode

Relevant source:

- `getDocPageAuthoringState()` in `docPageAuthoring.ts`
- `DocItem/Layout/index.tsx`

## Domain/sidebar/navbar mismatch

Inspect:

- `Docs/_domains.json`
- relevant `_category_.json`
- page front matter for `slug`, `sidebar_position`, `unlisted`

Relevant source:

- `payload/website/domainCatalog.ts`
- `payload/Scripts/UETools/DocsEditorApiHost.ps1`
- `payload/Scripts/Tests/Test-DocsTools.ps1` cross-domain and same-parent cases

## Stale JavaScript bundle served

Likely subsystem:

- website managed build assets / installed build drift

Checks:

- installed `website/build/index.html`
- installed `website/build/assets/js/**`
- `.ue-tools/state/website-managed-ledger.json`

Relevant source:

- installer website ledger helpers
- packaging contracts
- installer Cases `2f` and `2g`

## Actions that may destroy evidence

- reinstalling before preserving runtime state files and logs
- deleting `.ue-tools/state/**` by hand before checking status/stop behavior
- rebuilding `website/build/**` before comparing served vs installed bundle
