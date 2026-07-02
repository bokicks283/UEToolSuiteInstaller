# Confirmed root cause

The document-page Edit and Hide controls are gated in `payload/website/src/theme/DocItem/Layout/index.tsx` and never mount unless `authoringAvailable` is `true`.

Relevant code:

- `payload/website/src/theme/DocItem/Layout/index.tsx:1651-1667`
  - `const {requestJson, runtimeAvailable, runtimeReady} = useDocsAuthoringApi();`
  - `const authoringAvailable = runtimeReady && runtimeAvailable;`
  - `const pageIsEditable = sourceToken.toLowerCase().endsWith('.md');`
  - `const pageCanManageVisibility = authoringAvailable && !sourceToken.toLowerCase().endsWith('/_category_.json') && !!sourceToken;`
- `payload/website/src/theme/DocItem/Layout/index.tsx:1791-1814`
  - `if (!pageIsEditable || !authoringAvailable) { return undefined; }`
- `payload/website/src/theme/DocItem/Layout/index.tsx:3109-3122`
  - `((pageIsEditable && authoringAvailable) || pageCanManageVisibility) ? ... : null`

Expected state on `http://localhost:3000/docs/workflow-standards`:

- `sourceToken = "WorkflowStandards/README.md"`
- `pageIsEditable = true`
- `authoringAvailable = true`

Actual state during this investigation on `July 2, 2026`:

- The served doc metadata resolves correctly:
  - `id = "WorkflowStandards/README"`
  - `source = "@site/../Docs/WorkflowStandards/README.md"`
  - `permalink = "/docs/workflow-standards"`
- `sourceToken` therefore resolves to `WorkflowStandards/README.md`, so route/doc identity is valid for this page.
- `authoringAvailable` is false because `useDocsAuthoringApi()` reaches the shared health probe path and the live site currently returns `504 Gateway Timeout` for `/__ue_docs_api__/health`.
- The runtime descriptor at `/ue-tools/editor-runtime.json` points to `http://127.0.0.1:38473/` with `processId = 90056`, but that process is no longer running and direct loopback access is refused.

Evidence that changing only that condition would allow initialization to continue:

- With the current metadata, `pageIsEditable` is already true.
- `payload/website/src/theme/DocItem/Layout/index.tsx:1794` is the early-return that blocks page-specific initialization.
- `payload/website/src/theme/DocItem/Layout/index.tsx:3109-3118` is the only render gate for the header controls.
- If `authoringAvailable` becomes true, both the `/api/content` initialization effect and the Edit/Hide render path proceed without any other failing current-page condition.

# Edit control rendering path

1. Docusaurus renders the swizzled document layout component:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:1647`
2. `DocItemLayout()` calls `useDoc()` for current metadata and `useDocsAuthoringApi()` for authoring runtime state:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:1650-1652`
3. The current doc source is normalized through `resolveSourceToken()`:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:1658-1665`
   - `payload/website/src/theme/authoring/api.ts:102-119`
4. The Edit button renders only here:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:3116-3119`
5. Render condition:
   - `pageIsEditable && authoringAvailable`

# Hide control rendering path

1. The same `DocItemLayout()` path computes `sourceToken`, `pageIsEditable`, and `pageCanManageVisibility`:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:1658-1667`
2. The Hide/Show button renders only here:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:3111-3114`
3. Click handler:
   - `payload/website/src/theme/DocItem/Layout/index.tsx:2590-2625`
4. API endpoint used by the handler:
   - `POST /api/visibility`
5. Render condition:
   - `pageCanManageVisibility`
   - which expands to `authoringAvailable && !!sourceToken && !sourceToken.endsWith('/_category_.json')`

# Failed rendering or initialization condition

For the inspected page, the failed condition is `authoringAvailable`.

Confirmed non-failing conditions for `http://localhost:3000/docs/workflow-standards`:

- `sourceToken` is not empty.
- `sourceToken` resolves to a `.md` file.
- The page permalink is already under `/docs/`.
- The page is not a `_category_.json` section record.

Failed condition:

- `authoringAvailable = runtimeReady && runtimeAvailable`
- `runtimeReady` becomes true after the probe.
- `runtimeAvailable` stays false because the shared health probe reports `504 Gateway Timeout` on `/__ue_docs_api__/health`.

Secondary consequence:

- `payload/website/src/theme/DocItem/Layout/index.tsx:1794-1795` prevents page-specific authoring initialization entirely.
- The doc page then falls back to static rendering with no authoring UI.

# Site Settings versus document-page API path

Both surfaces use the same shared authoring hook and the same shared runtime discovery logic. They do not use separate legacy document-page endpoints.

| Concern | Site Settings | Document controls |
| --- | --- | --- |
| Runtime descriptor source | `useDocsAuthoringApi()` -> `resolveAuthoringConnection()` -> `/ue-tools/editor-runtime.json` first, then `/.ue-tools/editor-runtime.json` fallback | Same hook, same runtime-discovery path |
| Health endpoint | Shared probe candidates from `runtimeDiscovery.ts`; currently observed failure is `/__ue_docs_api__/health` | Same |
| API client/hook | `useDocsAuthoringApi()` in `payload/website/src/pages/site-settings.tsx:11` | `useDocsAuthoringApi()` in `payload/website/src/theme/DocItem/Layout/index.tsx:1651` |
| Connection state | Full `connectionStatus`, `runtimeReady`, `runtimeAvailable`, `retryConnection` | Only `runtimeReady` and `runtimeAvailable` are consumed |
| Required capabilities | Same shared capability check: `authoringApiVersion=2`, `siteConfig=true`, `domains=true`, `tree=true`, `visibility=true` | Same shared capability check before authoring is marked connected |
| Route assumptions | No current-doc mapping required | Requires valid `sourceToken`; Edit also requires `.md`; Hide excludes `/_category_.json` |
| Error handling | Renders `AuthoringConnectionStatusCard` when runtime is unavailable | Swallows the authoring UI entirely and keeps static doc rendering |
| Retry behavior | Shared controller auto-retry plus visible `Retry connection` button | Shared controller auto-retry only; no visible retry affordance |
| UI failure behavior | Structured diagnostics card | No Edit/Hide buttons and no visible authoring error |

# Browser network findings

Observed in the live browser on `July 2, 2026`:

- On `http://localhost:3000/docs/workflow-standards`, the console logged:
  - `[UEToolSuite Docs] Docs Editor API returned an HTTP error`
  - `Endpoint: /__ue_docs_api__/health`
  - `HTTP status: 504`
  - `Message: Gateway Timeout`
- On `http://localhost:3000/site-settings`, the same warning appeared and the page later rendered the structured connection error card.

Observed via direct endpoint checks against the running site:

- `GET http://localhost:3000/ue-tools/editor-runtime.json` -> `200`
- `GET http://localhost:3000/.ue-tools/editor-runtime.json` -> `404`
- `GET http://localhost:3000/__ue_docs_api__/health` -> `504`
- `GET http://127.0.0.1:38473/health` -> connection refused
- `GET http://127.0.0.1:38473/api/content?path=WorkflowStandards%2FREADME.md` -> connection refused

Runtime descriptor payload currently served:

- `apiUrl = "http://127.0.0.1:38473/"`
- `repoRoot = "C:\\Users\\Rim28\\Projects\\cppCozyRPG"`
- `docsRoot = "C:\\Users\\Rim28\\Projects\\cppCozyRPG\\Docs"`
- `processId = 90056`

Host-side process check:

- `processId 90056` is missing, so the runtime descriptor is stale and the loopback API it points to is gone.

Important note:

- The browser tooling available in this run did not expose a raw fetch list/HAR for `editor-runtime.json`.
- Its use is still confirmed by code path:
  - `payload/website/src/theme/authoring/runtimeDiscovery.ts:679-705`
  - `resolveAuthoringConnection()` always loads the runtime descriptor before probing health.

# Browser DOM findings

On `http://localhost:3000/docs/workflow-standards` after allowing the authoring probe to settle:

- Visible buttons in the doc header were only:
  - `Pages`
  - `TOC`
- `Edit` was not present in the DOM text.
- `Hide From Site` was not present in the DOM text.
- No `Retry connection` button was present.
- No authoring error text was present.

On `http://localhost:3000/site-settings` after the same delay:

- The page displayed the structured connection error content:
  - `Docs Editor API returned an HTTP error`
  - `Endpoint /__ue_docs_api__/health`
  - `HTTP status 504`
  - `Retry connection`

Conclusion:

- The document-page controls are not mounted.
- They are not mounted-and-hidden.

CSS check:

- `payload/website/src/theme/DocItem/Layout/ueAuthoring.module.css:472-511`
  - `.editActions` uses `display: flex`
  - `.primaryButton` and `.secondaryButton` use `display: inline-flex`
- The relevant control styles are not hiding the buttons by default.
- The `display: none` rules in this stylesheet apply to unrelated scrollbar elements, not to the edit controls.

# Route and document identity findings

Current site config:

- `payload/website/docusaurus.config.ts:67`
  - `baseUrl: '/'`
- `payload/website/docusaurus.config.ts:94`
  - `routeBasePath: 'docs'`

Current inspected page:

- Browser URL: `http://localhost:3000/docs/workflow-standards`
- Browser pathname: `/docs/workflow-standards`
- Served doc metadata:
  - `id = "WorkflowStandards/README"`
  - `source = "@site/../Docs/WorkflowStandards/README.md"`
  - `slug = "/workflow-standards"`
  - `permalink = "/docs/workflow-standards"`

Interpretation:

- The docs site home can correctly live at `http://localhost:3000/docs/` while the overall website root is `http://localhost:3000/`.
- That is the expected combination for `baseUrl: '/'` plus `routeBasePath: 'docs'`.
- For the inspected page, the actual route already matches the expected editable docs route.
- I found no evidence that the prior `http://localhost:3000/docs/` versus `http://localhost:3000/` note is the cause of the missing controls on this page.

# Capability findings

The document page does not require a capability beyond what Site Settings uses.

Shared capability contract:

- `payload/website/src/theme/authoring/runtimeDiscovery.ts:596-615`
- Required:
  - `authoringApiVersion = 2`
  - `siteConfig = true`
  - `domains = true`
  - `tree = true`
  - `visibility = true`

Document-page-specific requirements beyond capabilities:

- Valid `sourceToken`
- `.md` source for Edit
- Not `/_category_.json` for Hide

Current blocker:

- The request never reaches a healthy capability payload in the current live state because the health probe fails first with `504`.
- There is no evidence of a document-page-only capability mismatch.

# Source, build, install, and served-bundle parity

Source vs installed source:

- `payload/website/src/theme/DocItem/Layout/index.tsx`
  - source SHA-256 matches installed `cppCozyRPG` copy
- `payload/website/src/theme/authoring/api.ts`
  - source SHA-256 matches installed `cppCozyRPG` copy
- `payload/website/src/pages/site-settings.tsx`
  - source SHA-256 matches installed `cppCozyRPG` copy

Served bundle parity:

- The live doc page loaded the current document-layout chunk:
  - `__comp---theme-doc-item-178-a40.js`
- That served chunk contains:
  - `./src/theme/DocItem/Layout/index.tsx`
  - `./src/theme/authoring/api.ts`
  - `Edit`
  - `Hide From Site`
- The live content chunk for the inspected doc contains the expected metadata:
  - `source = "@site/../Docs/WorkflowStandards/README.md"`
  - `permalink = "/docs/workflow-standards"`

Conclusion:

- I found no evidence that the missing controls are caused by stale document-page source, stale installed source, or an old document-layout bundle.
- The served document page appears to contain the expected current code.

# Smallest recommended fix

To restore the buttons in the current observed live state, repair the authoring runtime/proxy so `useDocsAuthoringApi()` can mark the connection as `connected`.

The smallest product fix for the silent failure mode is separate:

- Update `DocItemLayout` to consume `connectionStatus` from `useDocsAuthoringApi()` and render the same `AuthoringConnectionStatusCard` used by `site-settings` whenever `runtimeReady && !runtimeAvailable`.

That fix would not force the buttons to render incorrectly. It would expose the real blocking condition instead of silently dropping Edit/Hide.

# Regression tests needed

1. React/component test for `DocItemLayout` where:
   - `metadata.source = "@site/../Docs/WorkflowStandards/README.md"`
   - `runtimeReady = true`
   - `runtimeAvailable = true`
   - Expected: `Edit` and `Hide From Site` render.
2. React/component test for `DocItemLayout` where:
   - same doc metadata
   - `runtimeReady = true`
   - `runtimeAvailable = false`
   - Expected: static doc still renders and connection diagnostics are shown instead of silent disappearance.
3. Unit test for `resolveSourceToken()` with:
   - `@site/../Docs/WorkflowStandards/README.md`
   - Expected: `WorkflowStandards/README.md`
4. Browser integration test covering a live doc page with a healthy API:
   - Expected: Edit and Hide render on `/docs/workflow-standards`
   - Expected: `GET /api/content?path=WorkflowStandards%2FREADME.md` occurs after connection succeeds

# Remaining uncertainty

- I could not reproduce the earlier state described in the prompt where `/site-settings` was fully connected while document pages were not. During this investigation on `July 2, 2026`, both surfaces were using the same shared authoring hook and both were blocked by the same `504` health failure.
- Because of that current runtime drift, the report can confirm the present cause of the missing buttons and the structural difference in UI behavior, but it cannot prove a separate historical document-page-only runtime defect from the live browser alone.
- Browser tooling in this run did not expose a raw network HAR, so `editor-runtime.json` usage is confirmed from source flow plus direct endpoint checks rather than a captured browser request list.
