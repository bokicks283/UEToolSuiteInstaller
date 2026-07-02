# Frontend Hook and Utility Catalog

## Shared API helpers (`payload/website/src/theme/authoring/api.ts`)

| Symbol | Kind | Purpose | Returned state or output | Callers | Failure behavior |
|---|---|---|---|---|---|
| `broadcastDocsStructureChanged` | utility | Emit in-page and local-storage structure-changed signal | `void` | admin mutations and doc UI refresh flows | ignores storage write failures |
| `getDocsStructureChangedStorageKey` | utility | Return the local-storage key used for structure-changed events | string | event listeners | none |
| `resolveSourceToken` | utility | Normalize source paths into Docs tokens | string token | document-page authoring UI | returns empty string on invalid input |
| `getSectionPathFromToken` | utility | Derive parent section token from a page token | string | document UI | returns empty string if not applicable |
| `getDocsRouteFromToken` | utility | Convert a source token into `/docs/...` route form | string route | navigation helpers | falls back to `/docs/` |
| `getSidebarIdFromDomainPath` | utility | Produce stable sidebar id from domain path | string sidebar id | admin/domain UI | returns `general-sidebar` for empty path |
| `useDocsAuthoringApi` | hook | Shared runtime discovery, retry, request helper, and authoring availability state | `apiBaseUrl`, `connectionStatus`, `docsRuntimeBaseUrl`, `retryConnection`, `runtimeAvailable`, `runtimeReady`, `requestJson` | `site-settings.tsx`, `DocItem/Layout/index.tsx` | throws request errors from `requestJson`; surfaces structured runtime failures |

## Document-page helper (`payload/website/src/theme/authoring/docPageAuthoring.ts`)

| Symbol | Kind | Purpose | Output | Callers | Failure behavior |
|---|---|---|---|---|---|
| `getDocPageAuthoringState` | utility | Decide whether the current page supports edit or visibility UI | `DocPageAuthoringState` | `DocItem/Layout/index.tsx` | never throws; converts runtime failure into state |

## Runtime discovery (`payload/website/src/theme/authoring/runtimeDiscovery.ts`)

| Symbol | Kind | Purpose | Output | Callers | Failure behavior |
|---|---|---|---|---|---|
| `normalizeApiBase` | utility | Normalize base URLs with trailing slash | string | API hook and probe helpers | falls back to default proxy URL on blank input |
| `normalizeComparablePath` | utility | Normalize Windows/path comparisons | string | identity validation | none |
| `formatDiagnosticValue` | utility | Convert arbitrary values into log/display strings | string | diagnostics | catches JSON stringify failures |
| `compareRuntimeIdentity` | utility | Validate health payload against runtime descriptor | failure or `null` | `probeApiBase` | returns structured mismatch instead of throwing |
| `probeApiBase` | async utility | Probe one candidate API base URL | success or failure object | `resolveAuthoringConnection` | classifies timeout/network/HTTP/schema failures |
| `resolveAuthoringConnection` | async utility | Load runtime descriptor, try candidate URLs, select best result | success or failure object | connection controller | returns preferred structured failure |
| `shouldAutoRetryConnection` | utility | Decide whether a failure should back off and retry | boolean | controller | none |
| `getRetryDelayMs` | utility | Map attempt index to retry delay | number | controller | clamps to configured range |
| `getConnectionLogSignature` | utility | Deduplicate repeated failure logs | string | controller | none |
| `formatConnectionLogMessage` | utility | Render failure diagnostics for console logging | string | API hook | none |
| `createAuthoringConnectionController` | controller factory | Own runtime probes, retry timers, and connected polling | start/retry/stop/getStatus methods | `useDocsAuthoringApi` | suppresses duplicate logs and cleans timers on stop |
| `getAuthoringConnectionPresentation` | utility | Convert failure categories into UI copy and technical details | presentation object | status card | none |

## Editor shortcode utilities (`payload/website/src/theme/authoring/shortcodes.ts`)

| Symbol | Kind | Purpose | Output | Callers | Failure behavior |
|---|---|---|---|---|---|
| `parseShortcodeToken` | utility | Parse emoji or icon shortcode token | `ShortcodeMatch` or `null` | inline editor behavior | returns `null` for invalid input |
| `toLucideExportName` | utility | Convert icon slug to Lucide export name | string | shortcode/icon rendering | returns transformed string |

## Count note

This catalog covers 22 meaningful hooks and utilities that drive authoring discovery, routing, diagnostics, and editor helper behavior in the current checkout.
