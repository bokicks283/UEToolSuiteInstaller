# Local docs editor architecture

## Purpose

The docs feature provides:

1. A local Docusaurus site over the repository `Docs/` tree.
2. Inline page editing through Tiptap.
3. Site/domain administration and staged structure editing.
4. A local PowerShell HTTP API that reads and mutates repository files.
5. CLI commands to scaffold, validate, build, and serve docs.

It is not intended as a deployed public service.

## Current runtime flow

```text
Local browser
  ├─ Docusaurus route and generated metadata
  ├─ DocItem/Layout inline editor
  ├─ SiteAdminPanel structure editor
  └─ authoring/api runtime discovery + fetch
          │
          ├─ Docusaurus dev proxy
          └─ direct loopback fallback
                    │
                    ▼
        DocsEditorApiHost.ps1
          ├─ HttpListener transport
          ├─ path resolution
          ├─ content load/save
          ├─ page/section/domain mutations
          ├─ move/link/docId/slug repair
          ├─ Docusaurus invalidation
          └─ theme/branding/override mutations
                    │
                    ▼
        UEToolSuite.Docs.psm1 + repository files
```

## Current concentration points

### `DocItem/Layout/index.tsx`

Owns:

- Docusaurus layout integration
- Tiptap schema/extensions/node views
- Markdown preprocessing and serialization
- TOC generation and ignore metadata
- local draft persistence
- editor state and toolbar actions
- load/save/delete/visibility requests
- dialogs and rendering

### `SiteAdminPanel.tsx`

Owns:

- site settings
- domain/tree loading
- tree algorithms
- draft state
- pending mutation queue
- sequential persistence
- dialogs and rendering

### `DocsEditorApiHost.ps1`

Owns:

- HTTP listener and response formatting
- request parsing/routing
- path resolution
- content/front matter operations
- domains and trees
- structural mutations
- link/docId/slug rewriting
- dev-server invalidation
- site customization

## Target boundaries

Gradual target:

```text
website/src/docs-authoring/
  api/
    client.ts
    discovery.ts
    contracts.ts
  paths/
    docsPaths.ts
  editor/
    markdown/
    extensions/
    components/
    useDocAuthoring.ts
  structure/
    model.ts
    reducer.ts
    planner.ts
    components/

Scripts/UETools/DocsEditor/
  DocsEditor.Contracts.psm1
  DocsEditor.Paths.psm1
  DocsEditor.Content.psm1
  DocsEditor.Structure.psm1
  DocsEditor.Site.psm1
  DocsEditor.Transport.psm1
```

The exact names are flexible. Transport, pure planning, and disk application should become independently testable.

## Authoritative data

- Docs content: files under `Docs/`.
- Domain ownership/order: `Docs/_domains.json` when present.
- Section metadata: `_category_.json`.
- Page metadata: Markdown/MDX front matter.
- Docusaurus sidebar/catalog output: derived.
- Browser draft: temporary local state.
- Runtime descriptor: temporary local process state.

## Change strategy

Do not perform a big-bang rewrite. Establish tests, then extract one subsystem at a time while preserving external behavior.
