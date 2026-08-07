# Frontend Authoring

## Primary files

- runtime discovery and connection state: `payload/website/src/theme/authoring/runtimeDiscovery.ts`
- frontend API wrapper and path helpers: `payload/website/src/theme/authoring/api.ts`
- connection diagnostics UI: `payload/website/src/theme/authoring/AuthoringConnectionStatusCard.tsx`
- page-level authoring gating: `payload/website/src/theme/authoring/docPageAuthoring.ts`
- site admin UI: `payload/website/src/theme/authoring/SiteAdminPanel.tsx`
- inline editor wrapper: `payload/website/src/theme/DocItem/Layout/index.tsx`
- site settings route: `payload/website/src/pages/site-settings.tsx`

## Runtime discovery

The frontend discovery flow is explicit and typed:

1. Load runtime descriptor JSON from known paths.
2. Validate descriptor schema.
3. Build API candidates from the descriptor URL, proxy URL, and direct default URL.
4. Probe `/health`.
5. Validate application id, API version, capabilities, repo root, docs root, and process id.
6. Emit one of:
   - `checking`
   - `connected`
   - a structured failure kind

Confirmed exports:

- `normalizeApiBase`
- `compareRuntimeIdentity`
- `resolveAuthoringConnection`
- `createAuthoringConnectionController`
- `getAuthoringConnectionPresentation`

## Retry and polling behavior

Current behavior in `runtimeDiscovery.ts`:

- retry delays: `1000`, `2000`, `5000`, `10000`, `30000` ms
- connected health poll: `5000` ms
- only one discovery attempt may be active at a time
- failures are categorized as transient or non-transient
- manual retry is exposed by the controller

## Shared API hook

`useDocsAuthoringApi()` in `api.ts`:

- owns connection status state
- starts/stops the controller
- exposes `requestJson()`
- exposes `retryConnection()`
- surfaces `runtimeReady` and `runtimeAvailable`
- computes `docsRuntimeBaseUrl`

This hook is the shared integration point for Site Settings and doc-page authoring UI.

## Site Settings

`src/pages/site-settings.tsx` is intentionally thin:

- it calls `useDocsAuthoringApi()`
- it renders `AuthoringConnectionStatusCard` when the runtime is not available
- it renders `SiteAdminPanel` only when the runtime is ready and connected

## SiteAdminPanel responsibilities

Confirmed from the current component:

- loads site config, domains, and trees
- keeps local selection in `localStorage`
- maintains draft structure mutations
- supports theme, branding, override, domain, page, section, move, reorder, rename, delete, and visibility operations
- broadcasts structure-changed events after successful saves

Important boundary note from `payload/website/src/theme/authoring/AGENTS.md`:

- tree/path/request/mutation helpers should stay outside component-local rendering where possible

## Inline document editing

`DocItem/Layout/index.tsx` is a concentration point. It currently owns:

- Docusaurus layout integration
- Tiptap editor configuration
- markdown preprocessing and save serialization
- draft persistence in `localStorage`
- content load/save/delete/visibility actions
- TOC generation and marker handling
- Mermaid/admonition/code-block/shortcode node views
- edit-mode and source-mode fallback logic

Confirmed authoring actions:

- page load through `/api/content`
- save through `/api/content` POST with `expectedHash`
- delete through `/api/delete`
- visibility toggle through `/api/visibility`

## Error rendering

The shared error surface is `AuthoringConnectionStatusCard`, backed by `getAuthoringConnectionPresentation()` in `runtimeDiscovery.ts`.

This means Site Settings and doc pages can show structured failures like:

- runtime descriptor missing
- API timeout
- repo-root mismatch
- docs-root mismatch
- process-id mismatch
- capability mismatch

## Component and utility catalogs

- [modules/Frontend-Component-Catalog.md](modules/Frontend-Component-Catalog.md)
- [modules/Frontend-Hook-and-Utility-Catalog.md](modules/Frontend-Hook-and-Utility-Catalog.md)
