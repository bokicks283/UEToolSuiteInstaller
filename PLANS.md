# Execution plans

Use a plan for work crossing three or more boundaries:

- React UI
- Tiptap/Markdown serialization
- API client/runtime discovery
- PowerShell transport
- filesystem mutation
- Docusaurus navigation/domain catalog
- installer/managed payload
- CI/test infrastructure

---

## Plan: <task name>

### Goal

State the user-visible result.

### Non-goals

List excluded behavior.

### Current failure

Include reproduction steps, exact input/path examples, and actual result.

### Invariants

List relevant contracts from `docs/agent/EDITOR_CONTRACTS.md`.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| | | |

### Milestones

- [ ] Reproduce with a failing test.
- [ ] Identify root cause.
- [ ] Implement the smallest coherent fix.
- [ ] Run targeted tests.
- [ ] Run cross-boundary validation.
- [ ] Review final diff for generated/unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| | | |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| | | |

### Rollback/recovery

Explain recovery from partial work or failed multi-file mutation.

### Remaining risks

List anything not proven or intentionally deferred.

---

## Plan: Install-Time Legacy Docs Section Normalization

### Goal

Normalize legacy docs directories that the editor exposes as sections but that lack `_category_.json` into the standard persistent section model during install, init, explicit CLI migration, doctor reporting, and structural-edit fallback.

### Non-goals

- Do not introduce a second permanent metadata-less section model.
- Do not create `README.md`, generated indexes, or category links for legacy sections.
- Do not refactor unrelated docs authoring, Docusaurus build, or Unreal tooling flows.

### Current failure

- Real project example: `Docs/WorkflowStandards/ProjectStructure/` contains only Markdown children and no `_category_.json`.
- The editor tree exposes it as a movable section, but structural edits and persistence depend on durable section metadata.
- Existing installer behavior has a separate installer-only `_category_.json` creator and the docs/editor runtime still treats implicit sections as a separate model.

### Invariants

- Preserve visible navigation order.
- Preserve child Markdown/MDX bytes, slugs, links, front matter, and domain metadata.
- Never overwrite an existing `_category_.json`.
- Keep all writes inside `Docs/`.
- Structural mutations must roll back migration-created files on failure.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| installer/managed payload | `Install-UEToolSuite.ps1` | Replace installer-only category creation with shared migration integration and skip flag |
| docs CLI/runtime | `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | Shared detection/planning/apply/doctor/command implementation |
| init/runtime readiness | `payload/Scripts/UETools/UEToolSuite.Init.psm1` | Reuse shared migration during init and support staged skip flow |
| editor API/filesystem mutation | `payload/Scripts/UETools/DocsEditorApiHost.ps1` | Normalize affected legacy sections transactionally before structural edits |
| test infrastructure | `payload/Scripts/Tests/Test-DocsTools.ps1`, `payload/Scripts/Tests/Test-InitRepoToolReadiness.ps1`, `Tests/Test-Install-UEToolSuite.ps1`, `Tests/Test-PackagingContracts.ps1` | Lock the new contract across CLI, installer, init, doctor, and API fallback |
| user docs | `payload/Scripts/README.md`, `payload/Docs/WorkflowStandards/DocsSite/Authoring.md`, `payload/Docs/WorkflowStandards/Setup.md` | Document migration command, doctor, and install behavior |

### Milestones

- [ ] Reproduce with a failing test.
- [ ] Identify root cause.
- [ ] Implement the smallest coherent fix.
- [ ] Run targeted tests.
- [ ] Run cross-boundary validation.
- [ ] Review final diff for generated/unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Reuse the docs module as the single migration implementation | It is callable from CLI, installer, init, and the editor API | Keeping installer-only and API-only logic would preserve the current disagreement |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| Real cppCozyRPG pre-migration capture | Pending | `WorkflowStandards/ProjectStructure` has Markdown children and no `_category_.json` |

### Rollback/recovery

Migration writes only newly created `_category_.json` files and tracks them so failed apply/validation and failed structural edits can remove those files before surfacing the error.

### Remaining risks

- GUI installer forwarding for the new skip flag may require a direct `Program.cs` update if packaging/runtime contracts prove it is necessary.
- Exact doctor warning formatting and staged init skip mechanics still need to be proven with tests.

---

## Plan: Long-Distance Same-Parent Section Reordering

### Goal

Make a SiteAdmin same-parent move place a section at the exact requested final index, including top and bottom moves, and persist that order through fresh tree reads, runtime restart, and generated sidebar output.

### Non-goals

- Do not reopen legacy-section migration behavior unless the reorder fix directly depends on it.
- Do not change cross-domain move/sidebar behavior beyond what the reorder regression proves necessary.
- Do not broadly refactor SiteAdmin or the docs editor API.

### Current failure

- In the live `cppCozyRPG` Workflow & Standards domain, `WorkflowStandards/DocsSite` starts at index `1` in the `/api/tree` domain-root child list.
- SiteAdmin `Move To Target` with target parent `WorkflowStandards` drafts the node at the bottom, then saves through `POST /api/move`.
- The live request is:
  - `sourcePath = WorkflowStandards/DocsSite`
  - `destinationDomainPath = WorkflowStandards`
  - `destinationParentPath = WorkflowStandards`
  - `insertIndex = 7`
- The API returns success, but a fresh `/api/tree` still shows the original order because the server reorders the physical `Docs/WorkflowStandards` directory siblings instead of the domain-root `/api/tree` child list.

### Invariants

- The destination parent `/api/tree` `children` array is the authoritative reorderable list.
- Hidden landing docs omitted from that list must not affect reorder indices.
- Successful saves must persist the exact requested final order and validate it with a fresh tree read.
- Position metadata must remain unique and deterministic after reorder.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| editor API/filesystem mutation | `payload/Scripts/UETools/DocsEditorApiHost.ps1` | Reorder same-parent domain-root children against the canonical tree list and persist validated positions |
| docs runtime helpers | `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | Reuse or extend shared ordering helpers if the API fix needs runtime-level sibling ordering support |
| docs integration tests | `payload/Scripts/Tests/Test-DocsTools.ps1` | Lock long-distance same-parent move cases, hidden-landing control, persistence, and error policy |
| SiteAdmin/frontend | `payload/website/src/theme/authoring/SiteAdminPanel.tsx`, `payload/website/src/theme/authoring/api.ts` | Only if the live payload contract proves wrong or refresh behavior needs correction |

### Milestones

- [ ] Reproduce with a failing test.
- [ ] Identify root cause.
- [ ] Implement the smallest coherent fix.
- [ ] Run targeted tests.
- [ ] Run cross-boundary validation.
- [ ] Review final diff for generated/unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Treat `destinationParentPath = domainPath` as a virtual domain-root reorder context when the `/api/tree` child list is flattened | The live failure is a mismatch between domain-root UI indices and physical-folder persistence | Reusing physical folder sibling groups for domain-root moves cannot represent the visible parent list |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| Live `/api/tree` for `workflow-standards-sidebar` | Captured | `DocsSite` index `1`, total child count `7` |
| Live SiteAdmin bottom move for `DocsSite` | Reproduced | Draft moves to bottom, save returns success, fresh tree remains unchanged |
| Direct replay of live `POST /api/move` payload | Reproduced | API returns `ok: true` for a no-op persisted order |

### Rollback/recovery

The reorder path must stage all affected position writes, reread the resulting tree, compare it with the requested final path order, and roll back any changed metadata if validation fails.

### Remaining risks

- If mixed page/section domain-root ordering follows a different intentional contract, that rule still needs to be proven with a control fixture.
- Frontend changes may still be required if the live payload is correct for this case but not for another long-distance drag path.

---

## Plan: Docs Editor API Single-Instance Ownership

### Goal

Make docs authoring use one verified Docs Editor API instance per project so creating a domain and moving `Completed Projects` updates the sidebar and navbar without requiring a restart.

### Non-goals

- Do not redesign the docs content/domain model beyond what the lifecycle fix requires.
- Do not add a second discovery protocol beside the existing runtime config plus dev proxy.
- Do not kill unrelated `node.exe`, `pwsh.exe`, or `powershell.exe` processes.

### Current failure

- Live target repo: `G:\Programs\Epic\Epic Games\Unreal Projects\CPP_Tests_UE58`.
- Current source and installed payload match for the docs runtime, API host, authoring client, and move/sidebar logic.
- The docs runtime starts an editor API on `38473` when free, but `Resolve-DocsEditorApiPort` silently falls forward to `38474..38490` when the default port is occupied.
- `website/docusaurus.config.ts` keeps the dev proxy target fixed at `http://127.0.0.1:38473`.
- `website/src/theme/authoring/api.ts` initializes requests against `/__ue_docs_api__/`, then probes `38473..38490` and accepts the first endpoint that reports capability version `2`, without validating project identity, process identity, or startup time.
- `payload/Scripts/Tests/Test-DocsTools.ps1` Case `5c` currently treats starting another background docs server instance as acceptable behavior.

### Invariants

- Only one active Docs Editor API instance may manage a given `RepoRoot` and `DocsRoot`.
- Startup must handle stale runtime files and occupied ports clearly.
- Shutdown must clean tracked runtime state and stop the owned process tree.
- Browser/API runtime discovery must prefer one authoritative endpoint and must not trust an arbitrary responding port.
- `/health` must stay cheap and side-effect free.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| API client/runtime discovery | `payload/website/src/theme/authoring/api.ts`, `payload/website/docusaurus.config.ts` | Stop broad alternate-port selection and align the client with one authoritative endpoint |
| PowerShell transport/runtime lifecycle | `payload/Scripts/UETools/UEToolSuite.Docs.psm1`, `payload/Scripts/UETools/DocsEditorApiHost.ps1` | Enforce single-instance ownership, validate identity, surface clear occupied-port errors, and expose health identity data |
| installer/managed payload | `Install-UEToolSuite.ps1` | Stop or invalidate incompatible docs runtime state during install/update |
| test infrastructure | `payload/Scripts/Tests/Test-DocsTools.ps1`, `Tests/Test-Install-UEToolSuite.ps1` | Lock single-instance, occupied-port, runtime-config, and install/update lifecycle behavior |

### Milestones

- [ ] Reproduce with a failing test or controlled stale-instance scenario.
- [ ] Identify the exact lifecycle/discovery flaw.
- [ ] Implement the smallest coherent fix.
- [ ] Run targeted tests.
- [ ] Run cross-boundary validation.
- [ ] Review final diff for generated/unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Prefer a single verified API port per project instead of silent alternate-port fallback | The proxy is fixed to `38473`, and mixed-port discovery lets the UI talk to the wrong instance | Keeping silent fallback would continue to permit split-brain authoring state |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| `ue-tools docs start --background --port 3000` in `CPP_Tests_UE58` | Captured | Editor API starts at `http://127.0.0.1:38473/`; runtime config writes that URL |
| `GET /health` on `38473` | Captured | Reports `repoRoot = CPP_Tests_UE58`, `docsRoot = ...\\Docs`, capabilities version `2` |
| `netsh http show servicestate` after API start | Captured | `HTTP://127.0.0.1:38473:127.0.0.1/` is attached through `http.sys`, request queue process `87704` |
| Source inspection of runtime discovery | Captured | `Resolve-DocsEditorApiPort` falls through `38473..38490`; authoring client probes the same range without project validation |

### Rollback/recovery

Lifecycle changes must keep runtime state removable through `docs stop`, tolerate stale state files, and leave the project able to restart one clean API even if startup validation rejects a conflicting process.

### Remaining risks

- The user-facing sidebar/nav symptoms may still include a separate hot-reload issue after the split-instance lifecycle flaw is fixed.
- Installer-side stop/invalidate logic must handle both current and older payload shapes without blocking clean upgrades.

---

## Plan: Docs Frontend Runtime Identity, Diagnostics, and Build Parity

### Goal

Accept the correct local Docs Editor API for the active project, surface precise frontend/runtime failure reasons, back off appropriately on transient failures, emit invariant timestamps, and ensure the installed/served website bundle actually matches the fixed source.

### Non-goals

- Do not redesign the authoring protocol beyond the confirmed `startedAt` issue.
- Do not remove project/process identity validation.
- Do not revisit unrelated docs navigation, sidebar, or editor-formatting bugs.
- Do not patch only installed generated assets without fixing the source and deployment path.

### Current failure

- Current checked-in frontend source in `payload/website/src/theme/authoring/api.ts` rejects a healthy API when runtime descriptor `startedAt` and `/health` `startedAt` represent the same process in different string formats.
- `site-settings.tsx` collapses all failures into a generic “not reachable” message and a fixed one-second retry loop.
- Installed `cppCozyRPG\website\src` matches current source, but `cppCozyRPG\website\build` is older and still serves stale JS behavior.
- Installer-managed website files currently exclude `website/build`, and the managed website ledger has no entries for built assets, so build artifacts can drift from source indefinitely.

### Invariants

- Windows path identity remains case-insensitive and slash-insensitive.
- `applicationId`, `apiVersion`, `processId`, normalized `repoRoot`, and normalized `docsRoot` remain enforced.
- Only one discovery attempt may be active per mounted hook instance.
- Discovery backs off after failures.
- Static docs rendering remains usable when authoring is unavailable.
- Managed payload paths remain installation contracts, including cleanup of obsolete managed artifacts when the managed file set changes.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| API client/runtime discovery | `payload/website/src/theme/authoring/api.ts`, new focused runtime-discovery helper(s) under `payload/website/src/theme/authoring/` | Remove `startedAt` identity rejection, add structured diagnostics, and implement retry/backoff/manual retry |
| React UI | `payload/website/src/pages/site-settings.tsx` | Show actionable error states instead of one generic message |
| PowerShell runtime lifecycle | `payload/Scripts/UETools/UEToolSuite.Docs.psm1`, `payload/Scripts/UETools/DocsEditorApiHost.ps1` | Emit invariant ISO timestamps in runtime descriptor and health |
| Website test harness | `payload/website/package.json`, new test script files under `payload/website/scripts/` | Add focused unit/editor tests without broad dependency changes |
| Docs/runtime tests | `payload/Scripts/Tests/Test-DocsTools.ps1` | Lock runtime-config timestamp and API-health expectations |
| Installer/managed payload | `Install-UEToolSuite.ps1`, `payload/website-managed-file-index.json`, `Tests/Test-Install-UEToolSuite.ps1`, `Tests/Test-PackagingContracts.ps1` | Include built website artifacts as managed files, remove obsolete managed build assets, and validate install/update parity |

### Milestones

- [ ] Reproduce with a failing test.
- [ ] Identify root cause.
- [ ] Implement the smallest coherent fix.
- [ ] Run targeted tests.
- [ ] Run cross-boundary validation.
- [ ] Review final diff for generated/unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Keep runtime identity validation but remove `startedAt` from acceptance | The confirmed bug is format drift, not identity drift | Adding a new protocol `instanceId` now would expand scope without proof it is required |
| Add structured frontend connection results instead of more booleans | UI and retry policy need failure categories and local diagnostics | Keeping a single `runtimeAvailable` flag would preserve the current misleading behavior |
| Manage `website/build` through the installer and clean obsolete managed assets | The installed build is stale while installed source is current | Rebuilding only locally or patching hashed JS files would not fix deployment parity |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| Installed source timestamps in `cppCozyRPG\website` | Captured | `src` updated July 1, 2026 while `build` JS assets remained June 22, 2026 |
| Managed website ledger in `cppCozyRPG` | Captured | No `website/build/...` entries present |
| Installed `build/index.html` | Captured | Still references stale hashed bundles from June 22, 2026 |

### Rollback/recovery

Installer changes must only remove obsolete files that were previously recorded as managed website files. Frontend retry state must clean up timers on unmount, and deployment validation should restart only the tracked docs frontend/API processes for the active project.

### Remaining risks

- The current `localhost:3000` process may not be launched through the standard `ue-tools docs start` path, so final served-bundle verification must inspect the actual live process and response body, not just local files.
- Adding managed `build` artifacts will increase the managed website index size and requires careful regeneration to avoid stale hashes.

---

## Plan: Docs Runtime Lifecycle and Document Page Authoring Status

### Goal

Keep one verified Docs Editor API runtime alive for the active project, repair stale runtime state automatically, and surface the shared structured connection status on editable document pages without breaking static doc rendering.

### Non-goals

- Do not redesign the docs editor architecture beyond the current runtime discovery and status surfaces.
- Do not force Edit or Hide controls to appear while the Docs Editor API is unavailable.
- Do not broaden the work into unrelated navigation, markdown serialization, or domain-tree behavior.

### Current failure

- The prior live investigation in `cppCozyRPG` found `/ue-tools/editor-runtime.json` pointing to `processId = 90056` on `http://127.0.0.1:38473/`, but that process no longer existed and `/__ue_docs_api__/health` returned `504`.
- `Site Settings` already consumes structured connection status and shows `AuthoringConnectionStatusCard`.
- `DocItem/Layout` still consumes only `runtimeReady` and `runtimeAvailable`, so document pages drop Edit/Hide with no visible diagnosis or retry affordance.
- Background docs lifecycle cases in `payload/Scripts/Tests/Test-DocsTools.ps1` now pass in this checkout when `UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS=1`, so the remaining live risk is install/build/runtime parity rather than an already-reproducible source-suite failure.

### Invariants

- Runtime descriptors are discovery metadata, not proof of a live API.
- Status/startup must distinguish live, stale, mismatched, and unreachable runtimes.
- Static docs rendering stays usable when authoring is unavailable.
- Editable document pages use the same shared connection state and retry path as `Site Settings`.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| React UI | `payload/website/src/theme/DocItem/Layout/index.tsx`, `payload/website/src/theme/DocItem/Layout/ueAuthoring.module.css` | Reuse shared structured runtime status on document pages |
| API client/runtime discovery | `payload/website/src/theme/authoring/docPageAuthoring.ts`, `payload/website/src/theme/authoring/api.ts`, `payload/website/src/theme/authoring/runtimeDiscovery.ts` | Keep one shared connection contract and testable page-level gating |
| docs lifecycle/runtime | `payload/Scripts/UETools/UEToolSuite.Docs.psm1`, `payload/Scripts/UETools/DocsEditorApiHost.ps1` | Enforce verified runtime ownership and stale-state repair |
| test infrastructure | `payload/website/scripts/test-authoring-runtime.cjs`, `payload/Scripts/Tests/Test-DocsTools.ps1`, install/packaging tests as needed | Lock document-page status behavior and runtime lifecycle parity |
| installer/managed payload | `Install-UEToolSuite.ps1`, `payload/website-managed-file-index.json`, packaging/install tests as needed | Ensure installed files and served bundles match the fixed source |

### Milestones

- [x] Reproduce with existing findings and focused runtime checks.
- [x] Identify the current root cause split between runtime availability and document-page UI behavior.
- [ ] Implement the smallest coherent fix.
- [ ] Run targeted tests.
- [ ] Run cross-boundary validation.
- [ ] Review final diff for generated/unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Reuse the existing structured `AuthoringConnectionStatusCard` on document pages | Site Settings already proves the shared connection model and retry behavior | Duplicating a second error-message formatter would drift immediately |
| Add a pure document-page authoring-state helper | The full `DocItem/Layout` component is too heavy for narrow unit coverage | Leaving the gating inline would keep the behavior difficult to test and easy to regress |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File payload/Scripts/Tests/Test-DocsTools.ps1 -FailFast` | Passed | `PASS=652 FAIL=0 WARN=0 SKIP=1` |
| Same command with `UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS=1` | Passed | `PASS=691 FAIL=0 WARN=0 SKIP=0`; background cases `5b`..`5e` green |
| Live browser investigation before this task | Captured | `/__ue_docs_api__/health -> 504`, stale `editor-runtime.json`, document page hid controls while Site Settings showed diagnostics |

### Rollback/recovery

Keep runtime cleanup ownership-safe: only remove the runtime descriptor when it belongs to the process being stopped, and keep the document-page change additive so static docs rendering remains the fallback if the runtime disappears.

### Remaining risks

- The live `cppCozyRPG` runtime still needs end-to-end validation after install to prove the served bundle matches the fixed source and the supported launcher path keeps the API alive.
- If the user’s prior `localhost:3000` server was started outside the supported command path, the final live diagnosis must call that out explicitly instead of attributing the failure to the source checkout alone.
