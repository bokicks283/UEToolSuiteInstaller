# Confirmed root cause

In the current checked-in frontend source, the runtime is rejected by `matchesExpectedRuntimeIdentity()` in [payload/website/src/theme/authoring/api.ts](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/theme/authoring/api.ts:227). The failing condition is the exact string comparison of `startedAt`.

I confirmed this by executing the existing frontend validation logic from `C:\Users\Rim28\Projects\cppCozyRPG\website\src\theme\authoring\api.ts` against the captured runtime and health objects without modifying source. With the captured objects, `matchesExpectedRuntimeIdentity()` returned `false` and `probeApiBase()` returned `false`. When only `startedAt` was aligned, both returned `true`.

# Exact failed comparison

Frontend source comparison:

```ts
if (expected.startedAt && payload.startedAt !== expected.startedAt) {
  return false;
}
```

Source location: [payload/website/src/theme/authoring/api.ts](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/theme/authoring/api.ts:252)

Expected value from `editor-runtime.json`:

```json
"startedAt": "07/01/2026 23:48:57"
```

Actual value from `/health`:

```json
"startedAt": "2026-07-01T23:48:57.5905015-04:00"
```

These are not equal as JavaScript strings, so the probe is treated as failed even though the HTTP response is `200` and the payload is otherwise healthy.

# Relevant code path

Runtime descriptor fetch:

- `useDocsAuthoringApi()`
- inner function `loadRuntimeConfig()`
- fetches `'/ue-tools/editor-runtime.json'`, then `'/.ue-tools/editor-runtime.json'`
- source: [payload/website/src/theme/authoring/api.ts](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/theme/authoring/api.ts:323)

Health fetch:

- `probeApiBase(apiBase, expectedRuntime, timeoutMs)`
- fetches `${apiBase}health`
- source: [payload/website/src/theme/authoring/api.ts](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/theme/authoring/api.ts:259)

Validation logic:

- `probeApiBase()` checks:
  - `response.ok`
  - `payload.ok !== false`
  - `payload.applicationId === 'UEToolSuiteDocsEditorApi'`
  - `payload.apiVersion === 2`
  - `payload.capabilities.authoringApiVersion === 2`
  - `payload.capabilities.siteConfig === true`
  - `payload.capabilities.domains === true`
  - `payload.capabilities.tree === true`
  - `payload.capabilities.visibility === true`
  - `matchesExpectedRuntimeIdentity(payload, expectedRuntime)`
- source: [payload/website/src/theme/authoring/api.ts](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/theme/authoring/api.ts:279)

Identity checks inside `matchesExpectedRuntimeIdentity()`:

- `applicationId`: exact equality
- `apiVersion`: exact equality
- `repoRoot`: normalized path equality, case-insensitive
- `docsRoot`: normalized path equality, case-insensitive
- `processId`: exact equality
- `startedAt`: exact equality

Not compared there:

- `modulePath`
- `scriptPath`
- whole-object equality
- serialized JSON equality

UI message source:

- `runtimeReady && !runtimeAvailable` renders “Local authoring runtime not reachable”
- source: [payload/website/src/pages/site-settings.tsx](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/pages/site-settings.tsx:22)

Backend response producers:

- runtime descriptor writer: [payload/Scripts/UETools/UEToolSuite.Docs.psm1](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/Scripts/UETools/UEToolSuite.Docs.psm1:1448)
- `/health` endpoint: [payload/Scripts/UETools/DocsEditorApiHost.ps1](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/Scripts/UETools/DocsEditorApiHost.ps1:4233)

# Expected versus actual values

Compared fields in current source:

- `applicationId`
  - expected: `UEToolSuiteDocsEditorApi`
  - actual: `UEToolSuiteDocsEditorApi`
  - result: pass
- `apiVersion`
  - expected: `2`
  - actual: `2`
  - result: pass
- `repoRoot`
  - expected: `C:\Users\Rim28\Projects\cppCozyRPG`
  - actual: `C:\Users\Rim28\Projects\cppCozyRPG`
  - result: pass
- `docsRoot`
  - expected: `C:\Users\Rim28\Projects\cppCozyRPG\Docs`
  - actual: `C:\Users\Rim28\Projects\cppCozyRPG\Docs`
  - result: pass
- `processId`
  - expected: `83288`
  - actual: `83288`
  - result: pass
- `startedAt`
  - expected: `07/01/2026 23:48:57`
  - actual: `2026-07-01T23:48:57.5905015-04:00`
  - result: fail

Observed but not compared in current source:

- `modulePath`
- `scriptPath`

The current live responses I fetched on July 2, 2026 also showed that `modulePath` and `scriptPath` both use `Scripts` casing, so the lowercase `scripts` values from the attached note were not reproduced from the current endpoint state.

# Why the UI message is misleading

The UI does not distinguish:

- network failure
- non-`200` HTTP response
- unhealthy API payload
- healthy payload that fails identity validation

All of those collapse into `runtimeAvailable = false`, and [site-settings.tsx](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/pages/site-settings.tsx:22) renders the same “not reachable” message. In the current source, a healthy `200` `/health` response is still classified as unavailable if `matchesExpectedRuntimeIdentity()` returns `false`.

There is also no runtime schema validator. The health payload is cast to `EditorApiHealthPayload` and then manually checked. With the captured values, the manual checks all pass except `startedAt`.

# Why polling continues

`useDocsAuthoringApi()` schedules a retry whenever `resolveReachableApiBase()` returns `runtimeAvailable: false`:

```ts
if (!resolvedApi.runtimeAvailable) {
  retryTimeoutId = globalThis.setTimeout(() => {
    if (!cancelled) {
      void loadRuntimeConfig();
    }
  }, 1000);
}
```

Source location: [payload/website/src/theme/authoring/api.ts](C:/Users/Rim28/Projects/UEToolSuiteInstaller/payload/website/src/theme/authoring/api.ts:349)

So in the current source, failed identity validation causes the same one-second retry loop as a truly unreachable runtime.

This is one retry loop per mounted `useDocsAuthoringApi()` instance. On the site settings page there is one such instance. The loop is not overlapping within one mount because the next timeout is scheduled only after the current probe sequence completes.

# Served bundle versus source parity

The checked-in source files are in parity with each other:

- `C:\Users\Rim28\Projects\UEToolSuiteInstaller\payload\website\src\theme\authoring\api.ts`
- `C:\Users\Rim28\Projects\cppCozyRPG\website\src\theme\authoring\api.ts`

I verified they have the same SHA-256 hash:

- `CB488288528C58AAA7BF600D4104B8A6C155EBF03053CF7F031CF7945E78D504`

But the bundle currently served from `http://localhost:3000/main.js` and the installed build asset [C:\Users\Rim28\Projects\cppCozyRPG\website\build\assets\js\17896441.42bd7700.js](C:/Users/Rim28/Projects/cppCozyRPG/website/build/assets/js/17896441.42bd7700.js:1) do not use the same validation logic:

- they fetch `'/ue-tools/editor-runtime.json'`
- they do not call `matchesExpectedRuntimeIdentity()`
- they do not compare `startedAt`
- they do not compare `processId`, `repoRoot`, or `docsRoot`
- they only require a successful health response with the expected capability flags
- they also scan extra ports `38474` through `38490`

That means:

1. The current source-level root cause is confirmed: exact `startedAt` equality would reject the captured healthy runtime.
2. The bundle currently being served on `localhost:3000` is stale relative to source and does not contain that identity check.
3. The browser behavior described in the attached note (`/editor-runtime.json` polling and repeated rejection despite healthy `200` responses) does not match the current source or the current `localhost:3000/main.js` bundle I fetched during this investigation.

# Smallest recommended fix

For the current source-level bug, the smallest fix is to stop using exact string equality for `startedAt` in `matchesExpectedRuntimeIdentity()`.

Smallest low-risk options:

- remove `startedAt` from frontend identity matching entirely
- or normalize/parse both timestamps before comparison

Removing that single comparison is the smallest change that makes the existing captured runtime and health payload pass the current frontend probe.

Separately, the served bundle/source mismatch should be resolved before relying on browser behavior as evidence for the source-level fix.

# Tests needed for the fix

Focused frontend tests around `useDocsAuthoringApi` / `probeApiBase`:

- a unit test where runtime descriptor and health payload differ only by `startedAt` formatting and the probe still succeeds
- a unit test proving `repoRoot` and `docsRoot` remain case-insensitive
- a unit test proving `processId`, `applicationId`, and `apiVersion` still reject mismatches
- a retry-loop test proving a healthy identity match stops one-second polling
- a parity/integration check to ensure the served frontend bundle is rebuilt from the same source logic before browser validation

# Remaining uncertainty

- I confirmed the exact frontend comparison failure in current source and confirmed source/build divergence.
- I did not find any current source or current served bundle on this machine that requests `/editor-runtime.json` at the site root; current source and current served bundle both use `/ue-tools/editor-runtime.json`.
- Because of that, the attached browser behavior likely came from an older or otherwise different frontend asset than the source and bundle I inspected on July 2, 2026.
- I did not modify implementation, rebuild, or reinstall during this investigation.
