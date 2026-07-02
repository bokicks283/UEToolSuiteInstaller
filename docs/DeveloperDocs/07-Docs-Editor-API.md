# Docs Editor API

## Host and startup

The local API host is `payload/Scripts/UETools/DocsEditorApiHost.ps1`. The docs module starts it through `Start-DocsEditorApiBackground` in `payload/Scripts/UETools/UEToolSuite.Docs.psm1:4758`.

Confirmed defaults:

- listener type: `System.Net.HttpListener`
- bind prefix: `http://127.0.0.1:<port>/`
- default port: `38473` (`Get-DocsEditorApiDefaultPort`)
- application id: `UEToolSuiteDocsEditorApi`
- API version: `2`

## Request handling

The main request router is `Invoke-EditorApiRequest` (`DocsEditorApiHost.ps1:4219`).

High-level flow:

1. Normalize request path.
2. Handle `OPTIONS`.
3. Handle `GET /health`.
4. Handle GET read routes.
5. Parse POST JSON body.
6. Dispatch by exact route string.
7. Convert exceptions into JSON error responses with status `400` or `409`.

## Health and identity contract

`GET /health` returns:

- `ok`
- `applicationId`
- `apiVersion`
- `processId`
- `repoRoot`
- `docsRoot`
- `startedAt`
- `modulePath`
- `scriptPath`
- `capabilities.authoringApiVersion`
- `capabilities.siteConfig`
- `capabilities.domains`
- `capabilities.tree`
- `capabilities.visibility`

This payload is the runtime identity source used by the frontend and by docs lifecycle validation.

## Response and error format

Confirmed helpers:

- success serialization: `Write-JsonResponse`
- text JSON special-case: `Write-JsonTextResponse`
- failures: `Write-ErrorResponse`

Observed route pattern:

- success payloads usually return `ok = $true` plus `tree`, `domains`, `content`, `config`, `catalog`, or `result`
- error payloads return `ok = $false` plus an error message

## Local-only assumptions

- The host binds to `127.0.0.1`, not `0.0.0.0`.
- There is no authentication layer in the current source.
- Trust is based on local-loopback binding plus project/docs-root identity checks in both runtime lifecycle and the frontend.

## Concurrency and writes

Confirmed from current code shape:

- writes happen directly against repository files
- optimistic concurrency exists for page save through `expectedHash`
- multiple structure and metadata routes mutate files immediately rather than batching server-side transactions across the entire API
- the API contains rollback/snapshot logic for some structure operations, but not a uniform cross-route transaction framework

> Unresolved: There is no single documented concurrency model beyond route-specific validation and rollback helpers. See [25-Open-Questions.md](25-Open-Questions.md).

## Logging and shutdown

- the host runs until `HttpListener` stops
- the lifecycle owner is `UEToolSuite.Docs.psm1`, not the host itself
- background startup redirects stdout/stderr to runtime log files under `.ue-tools/state/**`
- shutdown is process-oriented: `Stop-DocsEditorApiBackground` kills the tracked process tree and then verifies that the runtime is no longer active

## Route summary

The current route set is documented in [modules/API-Route-Catalog.md](modules/API-Route-Catalog.md) and [20-API-Reference.md](20-API-Reference.md).

Confirmed route handlers in `DocsEditorApiHost.ps1`:

- `/health`
- `/api/tree`
- `/api/domains`
- `/api/content`
- `/api/site/config`
- `/api/site/theme-catalog`
- `/api/create/page`
- `/api/create/section`
- `/api/create/domain`
- `/api/move`
- `/api/rename`
- `/api/node/metadata`
- `/api/reorder`
- `/api/delete`
- `/api/visibility`
- `/api/domains/reorder`
- `/api/domains/update`
- `/api/domains/delete`
- `/api/site/theme`
- `/api/site/branding`
- `/api/site/overrides`
