# Data Flows and Sequences

Each sequence below is intentionally narrow. It maps current source paths rather than an idealized architecture.

## 1. Fresh installation

Source anchors: `Install-UEToolSuite.ps1`, `payload/ue-tool-suite.manifest.json`, `Tests/Test-Install-UEToolSuite.ps1` Case `1`.

```mermaid
sequenceDiagram
  participant User
  participant Installer as Install-UEToolSuite.ps1
  participant Manifest as ue-tool-suite.manifest.json
  participant Target as Target UE repo
  User->>Installer: run install with TargetRepoRoot
  Installer->>Manifest: read managed items and cleanup paths
  Installer->>Target: validate repo and create backup/update dirs
  Installer->>Target: copy payload groups
  Installer->>Target: write managed ledgers
  Installer->>Target: optionally run init
```

## 2. Update over an existing installation

Source anchors: `Invoke-ManagedDocsSmartUpdate`, `Read-ManagedWebsiteLedger`, installer Cases `2`-`2g`.

```mermaid
sequenceDiagram
  participant Installer
  participant Ledgers as Managed ledgers
  participant Runtime as Docs runtime
  participant Target
  Installer->>Ledgers: load prior managed files
  Installer->>Runtime: stop tracked docs runtime if present
  Installer->>Target: remove obsolete managed paths
  Installer->>Target: preserve drifted docs defaults as update candidates
  Installer->>Target: copy refreshed payload
  Installer->>Ledgers: write refreshed ledgers
```

## 3. Docs foreground start

Source anchors: `Invoke-DocsStartForeground`, `Start-DocsEditorApiBackground`.

```mermaid
sequenceDiagram
  participant User
  participant DocsCli as Invoke-DocsToolsMain
  participant DocsModule as UEToolSuite.Docs.psm1
  participant Api as DocsEditorApiHost.ps1
  participant Npm
  User->>DocsCli: ue-tools docs start
  DocsCli->>DocsModule: Invoke-DocsStartForeground
  DocsModule->>Api: Start-DocsEditorApiBackground
  DocsModule->>Npm: npm run start
  Npm-->>User: dev server output in current terminal
```

## 4. Docs background start

Source anchors: `Invoke-DocsStartBackground`, `Get-DocsServerEntries`.

```mermaid
sequenceDiagram
  participant User
  participant DocsModule
  participant Api
  participant Npm
  participant State as .ue-tools/state
  User->>DocsModule: ue-tools docs start --background
  DocsModule->>Api: ensure editor API is running
  DocsModule->>Npm: detached npm run start
  DocsModule->>State: save docs server entry and runtime descriptor
  DocsModule-->>User: URL, PID, log paths
```

## 5. Runtime discovery

Source anchors: `runtimeDiscovery.ts`, `docusaurus.config.ts`.

```mermaid
sequenceDiagram
  participant Page
  participant Hook as useDocsAuthoringApi
  participant Discovery as runtimeDiscovery.ts
  participant Site as Docusaurus site
  participant Api
  Page->>Hook: mount
  Hook->>Discovery: start controller
  Discovery->>Site: fetch /ue-tools/editor-runtime.json
  Discovery->>Api: probe /__ue_docs_api__/health
  Discovery->>Api: probe direct fallback if needed
  Discovery-->>Hook: connected or structured failure
```

## 6. Health identity validation

Source anchors: `compareRuntimeIdentity`, `probeApiBase`.

```mermaid
sequenceDiagram
  participant Discovery
  participant Descriptor as editor-runtime.json
  participant Health as /health
  Discovery->>Descriptor: read expected apiUrl, repoRoot, docsRoot, processId
  Discovery->>Health: GET health
  Discovery->>Discovery: compare applicationId, apiVersion, repoRoot, docsRoot, processId
  Discovery-->>Discovery: accept connected or emit mismatch category
```

## 7. Site Settings initialization

Source anchors: `site-settings.tsx`, `SiteAdminPanel.tsx`.

```mermaid
sequenceDiagram
  participant Browser
  participant Page as site-settings.tsx
  participant Hook as useDocsAuthoringApi
  participant Panel as SiteAdminPanel
  Browser->>Page: open /site-settings
  Page->>Hook: request runtime state
  Hook-->>Page: runtimeAvailable or failure
  Page->>Panel: render only when runtimeAvailable
```

## 8. Normal document-page initialization

Source anchors: `DocItem/Layout/index.tsx`, `docPageAuthoring.ts`.

```mermaid
sequenceDiagram
  participant Browser
  participant Layout as DocItem/Layout
  participant Hook as useDocsAuthoringApi
  participant Gate as getDocPageAuthoringState
  Browser->>Layout: open docs page
  Layout->>Hook: request runtime state
  Layout->>Gate: evaluate source token and visibility/edit support
  Gate-->>Layout: page authoring state
```

## 9. Edit document load

Source anchors: `DocItem/Layout/index.tsx`, `GET /api/content`.

```mermaid
sequenceDiagram
  participant Layout
  participant ApiClient as api.ts
  participant Api
  Layout->>ApiClient: requestJson(/content?path=token)
  ApiClient->>Api: GET /api/content
  Api-->>ApiClient: content, hash, modifiedUtc
  ApiClient-->>Layout: editable payload
```

## 10. Edit document save

Source anchors: `Save-DocsContent`, `POST /api/content`.

```mermaid
sequenceDiagram
  participant Layout
  participant ApiClient
  participant Api
  participant Fs as Docs file
  Layout->>ApiClient: save content with expectedHash
  ApiClient->>Api: POST /api/content
  Api->>Fs: validate current hash and write content
  Api-->>ApiClient: ok + result
  ApiClient-->>Layout: save success or conflict
```

## 11. Hide document

Source anchors: `Set-DocsPageVisibility`, Case `3f`.

```mermaid
sequenceDiagram
  participant Layout
  participant Api
  participant Fs as Markdown/front matter
  Layout->>Api: POST /api/visibility hidden=true
  Api->>Fs: add or update unlisted front matter
  Api-->>Layout: updated visibility result
```

## 12. Show document

Source anchors: same as hide flow.

```mermaid
sequenceDiagram
  participant Layout
  participant Api
  participant Fs as Markdown/front matter
  Layout->>Api: POST /api/visibility hidden=false
  Api->>Fs: remove or reset hidden state
  Api-->>Layout: updated visibility result
```

## 13. Create domain

Source anchors: `Create-DocsDomain`, `POST /api/create/domain`.

```mermaid
sequenceDiagram
  participant Panel as SiteAdminPanel
  participant Api
  participant DomainFile as Docs/_domains.json
  participant DocsFs as Docs tree
  Panel->>Api: POST /api/create/domain
  Api->>DomainFile: append domain definition
  Api->>DocsFs: optionally create landing doc/structure
  Api-->>Panel: created domain result
```

## 14. Move section into domain

Source anchors: `Move-DocsNode`, cross-domain tests Cases `1h` and `1i`.

```mermaid
sequenceDiagram
  participant Panel
  participant Api
  participant DocsFs
  participant Nav as domain/sidebar metadata
  Panel->>Api: POST /api/move
  Api->>DocsFs: move/rename directories and docs
  Api->>Nav: rewrite affected ownership and sidebar values
  Api-->>Panel: move result
```

## 15. Navbar/sidebar refresh

Source anchors: `domainCatalog.ts`, frontend structure-change broadcast.

```mermaid
sequenceDiagram
  participant Mutation
  participant Browser
  participant Broadcast as DOCS_STRUCTURE_CHANGED_EVENT
  participant Catalog as domainCatalog.ts
  Mutation->>Browser: update structure
  Browser->>Broadcast: fire structure changed event
  Catalog->>Catalog: rebuild sidebar/navbar model on next load/build
```

## 16. API shutdown

Source anchors: `Stop-DocsEditorApiBackground`.

```mermaid
sequenceDiagram
  participant User
  participant DocsModule
  participant Process
  participant State
  User->>DocsModule: ue-tools docs stop
  DocsModule->>Process: taskkill /T /F tracked root or child PID
  DocsModule->>DocsModule: verify process and runtime no longer active
  DocsModule->>State: remove API entry and runtime descriptor
```

## 17. Stale descriptor recovery

Source anchors: `Get-DocsEditorApiStatus`, `Invoke-DocsStatus`.

```mermaid
sequenceDiagram
  participant Status as Invoke-DocsStatus
  participant State
  participant Probe as health probe
  Status->>State: load tracked API entry
  Status->>Probe: test process and health
  Probe-->>Status: stale_state
  Status->>State: clear stale entry and runtime descriptor
```

## 18. Frontend reconnection after API restart

Source anchors: `createAuthoringConnectionController`, retry backoff list.

```mermaid
sequenceDiagram
  participant Hook
  participant Discovery
  participant Timer
  participant Api
  Hook->>Discovery: initial probe fails
  Discovery->>Timer: schedule retry 1s, 2s, 5s, 10s, 30s
  Timer->>Discovery: run probe again
  Discovery->>Api: GET /health
  Api-->>Discovery: healthy response
  Discovery-->>Hook: connected
```

## 19. Website source-to-served-bundle deployment

Source anchors: `payload/website/package.json`, installer website copy logic, packaging tests.

```mermaid
sequenceDiagram
  participant Source as payload/website/src
  participant Build as npm run build
  participant Payload as payload/website
  participant Installer
  participant Installed as target website/
  participant Server as npm run start
  Source->>Build: produce build/
  Build->>Payload: commit build output into payload contract
  Installer->>Installed: copy managed website files
  Server->>Installed: serve current installed source/build assets
```

## 20. Relevant test execution

Source anchors: `Tests/Run-UEToolSuiteTests.ps1`, `Tests/ToolSuiteManifest.ps1`.

```mermaid
sequenceDiagram
  participant User
  participant Runner as Run-UEToolSuiteTests.ps1
  participant Manifest as ToolSuiteManifest.ps1
  participant Fixture as installed fixture helper
  participant Suite
  User->>Runner: select suite name/category
  Runner->>Manifest: load suite metadata
  Runner->>Fixture: prepare installed repo if required
  Runner->>Suite: execute script with log/result tracking
  Suite-->>Runner: pass/fail/skip
```
