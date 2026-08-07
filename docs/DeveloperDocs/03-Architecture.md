# Architecture

## High-level shape

The repository is split between a root installer/release layer and an installed payload layer. The docs-authoring system then adds a third runtime split inside the installed project: browser frontend, local Docusaurus dev server, and a loopback PowerShell API.

## Component architecture

```mermaid
flowchart LR
  A["Repository Root"] --> B["Install-UEToolSuite.ps1"]
  A --> C["Scripts/Publish-InstallerExe.ps1"]
  A --> D["Tests/Run-UEToolSuiteTests.ps1"]
  A --> E["src/UEToolSuiteInstaller.Gui/Program.cs"]
  B --> F["payload/"]
  F --> G["Scripts/ue-tools.ps1"]
  F --> H["Scripts/UETools/*.psm1"]
  F --> I["Docs/"]
  F --> J["website/"]
  J --> K["Docusaurus + React"]
  H --> L["DocsEditorApiHost.ps1"]
  K --> L
```

Explanation:

- The root installer selects and copies payload content.
- The GUI wrapper packages the same installer and payload instead of replacing them.
- After installation, the project-local command surface is `Scripts/ue-tools.ps1` plus nested modules.
- The docs site and docs API are coupled but still split into frontend and PowerShell transport layers.

## Source repository to installed-project deployment

```mermaid
flowchart LR
  A["Authored repo"] --> B["payload/ue-tool-suite.manifest.json"]
  B --> C["Install-UEToolSuite.ps1"]
  C --> D["Target UE project root"]
  D --> E["Scripts/"]
  D --> F["Docs/"]
  D --> G["website/"]
  D --> H[".ue-tools/state/"]
```

Explanation:

- `payload/ue-tool-suite.manifest.json` defines category membership and legacy cleanup paths.
- `Install-UEToolSuite.ps1` applies manifest categories plus command-line switches to compute the effective install set.
- `Docs/` and `website/` are not treated identically: docs use a smart-update ledger/candidate model, while website installation also merges structured config and tracks managed build assets.

## Browser to Docusaurus proxy to Editor API

```mermaid
sequenceDiagram
  participant Browser
  participant DocusaurusDev as Docusaurus dev server
  participant Frontend as React authoring client
  participant API as DocsEditorApiHost.ps1
  participant Repo as Active repository files

  Browser->>DocusaurusDev: GET /docs/... and /site-settings
  Frontend->>Browser: load runtime descriptor paths
  Frontend->>DocusaurusDev: /__ue_docs_api__/health
  DocusaurusDev->>API: proxy to http://127.0.0.1:38473/health
  Frontend->>API: authoring requests via proxy base
  API->>Repo: read/write Docs, _domains.json, _category_.json, config files
  API-->>Frontend: JSON responses
```

Explanation:

- The development proxy is declared in `payload/website/docusaurus.config.ts`.
- The frontend still validates runtime identity and does not blindly trust any responding loopback service.
- The API writes directly to repository files; there is no database or remote service layer.

## Installer and managed-file ownership

```mermaid
flowchart TD
  A["payload manifest"] --> B["managedTextItems"]
  A --> C["managedItems by category"]
  A --> D["legacyCleanupPaths"]
  C --> E["docs managed index"]
  C --> F["website managed index"]
  E --> G["docs smart update ledger"]
  F --> H["website managed ledger"]
```

Explanation:

- Root text files are marker-managed instead of wholly replaced.
- Docs and website each have separate managed-file indexes and target ledgers.
- The website ledger also governs cleanup of obsolete managed build assets.

## Runtime process ownership

```mermaid
flowchart LR
  A["ue-tools docs start"] --> B["Start-DocsEditorApiBackground"]
  A --> C["npm run start"]
  B --> D["DocsEditorApiHost.ps1 child pwsh"]
  B --> E["editor-runtime.json"]
  C --> F["Docusaurus dev server"]
  A --> G["docs-server.json"]
```

Explanation:

- The docs module owns both the dev server state and the editor API state.
- Background start writes tracked state files under `.ue-tools/state/**` and `website/static/ue-tools/editor-runtime.json`.
- Stop/status logic attempts to reconcile tracked state with live processes and live `/health` responses.

## Docs content and generated navigation relationships

```mermaid
flowchart TD
  A["Docs/**/*.md, .mdx"] --> B["front matter"]
  A --> C["directory metadata _category_.json"]
  A --> D["Docs/_domains.json"]
  B --> E["doc ids and route slugs"]
  C --> F["labels, positions, landing docs"]
  D --> G["domain ownership and sidebar ids"]
  E --> H["domainCatalog.ts"]
  F --> H
  G --> H
  H --> I["sidebars.ts config"]
  H --> J["docusaurus.config.ts navbar items"]
```

Explanation:

- `domainCatalog.ts` is the central authored-side synthesis step for docs routes, labels, and sidebars.
- `sidebars.ts` is intentionally thin and delegates to `buildDocsSidebarsConfig()`.
- The Site Settings tree and the generated Docusaurus sidebar are related but not identical views; the tree includes mutable structure state, while the sidebar is derived from the docs/domain model.

## Key boundaries

| Boundary | Primary source | Why it matters |
|---|---|---|
| installer vs payload | `Install-UEToolSuite.ps1` vs `payload/**` | Source repo decides updates; installed payload does not self-update |
| CLI dispatch vs domain logic | `payload/Scripts/ue-tools.ps1`, `UEToolSuite.Dispatcher.psm1` | Public command surface stays stable while implementation changes inside modules |
| docs frontend vs docs transport | `payload/website/src/**` vs `DocsEditorApiHost.ps1` | UI state and filesystem mutation are intentionally separate |
| authored source vs generated state | `payload/website/src/**` vs `website/build/**`, `.ue-tools/state/**` | Bugs often come from drift between these layers |
| release packaging vs install runtime | `Program.cs`, `.csproj`, `Publish-InstallerExe.ps1` | GUI packaging contracts do not define project-local runtime behavior by themselves |
