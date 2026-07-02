# API Reference

## Overview

The Docs Editor API is implemented in `payload/Scripts/UETools/DocsEditorApiHost.ps1` and started by `Start-DocsEditorApiBackground` in `payload/Scripts/UETools/UEToolSuite.Docs.psm1:4758`.

Confirmed behavior:

- transport: `System.Net.HttpListener`
- listener prefix: `http://127.0.0.1:<port>/`
- default port: `38473`
- application id: `UEToolSuiteDocsEditorApi`
- capability/API version: `2`
- JSON success helper: `Write-JsonResponse`
- JSON error helper: `Write-ErrorResponse`

The frontend entrypoint is `useDocsAuthoringApi` in `payload/website/src/theme/authoring/api.ts`. Runtime discovery and identity validation live in `payload/website/src/theme/authoring/runtimeDiscovery.ts`.

## Request lifecycle

1. `Invoke-EditorApiRequest` normalizes the path and method.
2. `GET /health` is handled without JSON request-body parsing.
3. Read-only GET routes return tree, domains, content, or site config.
4. POST routes parse JSON with `Read-JsonBody`.
5. Route-specific functions validate path tokens, domain paths, or mutation arguments.
6. Success returns `ok = true`.
7. Exceptions become JSON error payloads with HTTP `400` or `409`.

## Health contract

`GET /health` is the identity contract used by both lifecycle code and the frontend.

Example response shape derived from the current code:

```json
{
  "ok": true,
  "applicationId": "UEToolSuiteDocsEditorApi",
  "apiVersion": 2,
  "processId": 12345,
  "repoRoot": "C:/Path/To/Repo",
  "docsRoot": "C:/Path/To/Repo/Docs",
  "startedAt": "2026-07-02T12:34:56.0000000+00:00",
  "modulePath": "C:/Path/To/UEToolSuite.Docs.psm1",
  "scriptPath": "C:/Path/To/DocsEditorApiHost.ps1",
  "capabilities": {
    "authoringApiVersion": 2,
    "siteConfig": true,
    "domains": true,
    "tree": true,
    "visibility": true
  }
}
```

## Error model

Observed API error pattern:

```json
{
  "ok": false,
  "error": "Human-readable message"
}
```

Confirmed behavior:

- most validation failures surface as `400`
- messages containing `conflict` are promoted to `409`
- there is no documented machine-readable error code enum in the PowerShell host

## Identity validation performed by the frontend

`runtimeDiscovery.ts` does not trust health alone. It validates:

- `applicationId`
- `apiVersion`
- `processId`
- normalized `repoRoot`
- normalized `docsRoot`
- capability flags

The frontend can also reject:

- missing runtime descriptor
- invalid descriptor JSON/schema
- network failures
- timeouts
- HTTP errors
- capability mismatches

## Route families

| Family | Routes | Main backend functions | Main frontend callers |
|---|---|---|---|
| health | `/health` | inline handler in `Invoke-EditorApiRequest` | `probeApiBase` |
| tree and domains | `/api/tree`, `/api/domains` | `Get-DocsTree`, `Get-DocsDomainDefinitions` | `SiteAdminPanel`, document UI refresh |
| content | `/api/content` | `Get-DocsContent`, `Save-DocsContent` | `DocItem/Layout/index.tsx` |
| metadata and structure | `/api/node/metadata`, `/api/reorder`, `/api/move`, `/api/rename`, `/api/delete`, `/api/visibility` | `Update-DocsNodeMetadata`, `Reorder-DocsNode`, `Move-DocsNode`, `Rename-DocsNode`, `Remove-DocsNode`, `Set-DocsPageVisibility` | `SiteAdminPanel`, document UI |
| domain management | `/api/create/domain`, `/api/domains/reorder`, `/api/domains/update`, `/api/domains/delete` | `Create-DocsDomain`, `Move-DocsDomain`, `Update-DocsDomain`, `Remove-DocsDomain` | `SiteAdminPanel` |
| site settings | `/api/site/config`, `/api/site/theme-catalog`, `/api/site/theme`, `/api/site/branding`, `/api/site/overrides` | `Get-SiteConfigPayload`, `Get-SiteThemeCatalogPayload`, `Apply-SiteThemeFromApiBody`, `Apply-SiteBrandingFromApiBody`, `Apply-SiteOverridesFromApiBody` | `SiteAdminPanel`, `site-settings.tsx` |

## Confirmed route set

The current route set is:

- `GET /health`
- `GET /api/tree`
- `GET /api/domains`
- `GET /api/content`
- `GET /api/site/config`
- `GET /api/site/theme-catalog`
- `POST /api/content`
- `POST /api/create/page`
- `POST /api/create/section`
- `POST /api/create/domain`
- `POST /api/move`
- `POST /api/rename`
- `POST /api/node/metadata`
- `POST /api/reorder`
- `POST /api/delete`
- `POST /api/visibility`
- `POST /api/domains/reorder`
- `POST /api/domains/update`
- `POST /api/domains/delete`
- `POST /api/site/theme`
- `POST /api/site/branding`
- `POST /api/site/overrides`

See [modules/API-Route-Catalog.md](modules/API-Route-Catalog.md) for per-route fields, side effects, and callers.

## Concurrency and write model

Confirmed behavior:

- `Save-DocsContent` uses `expectedHash` optimistic concurrency.
- Structural routes mutate the filesystem immediately.
- Some structural operations implement rollback-oriented helpers.
- There is no single transaction wrapper covering all routes.

Unresolved:

- exact guarantees when two clients mutate different structure endpoints concurrently
- whether all multi-file domain operations are durably atomic across restart or crash boundaries

See [25-Open-Questions.md](25-Open-Questions.md).
