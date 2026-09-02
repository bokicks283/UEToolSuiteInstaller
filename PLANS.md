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

## Plan: Provenance-Aware VS Code Workspace Settings Synchronization

### Goal

Preserve explicitly owned VS Code `.code-workspace` additions, modifications, and removals across Unreal project-file regeneration while retaining new Unreal-generated content, allowing obsolete unowned content to disappear, and stopping safely on ownership conflicts.

### Non-goals

- Do not manage VS Code user profiles, extensions, Settings Sync, or UI state.
- Do not infer ownership for unknown workspace differences during ordinary sync or build.
- Do not retain the previous copy-missing-properties merge as a competing fallback.
- Do not mutate a real Unreal project in automated tests.

### Current failure

- `Merge-UEToolSuiteVSCodeWorkspaceJson` copies properties and selected array entries that are missing after regeneration.
- The merge has no generated baseline, effective-state ledger, ownership metadata, or removal tombstones.
- A user-removed Unreal Engine folder is regenerated and cannot be distinguished from an obsolete generated field, while old generated values can be resurrected as though they were custom.

### Invariants

- Team configuration is portable and tracked; user/project overlays and runtime state are private and ignored.
- Only explicit fine-grained operations own workspace content.
- New and changed unowned Unreal content survives; obsolete unowned content is not restored.
- Owned non-removal values use strict three-way conflict detection before any write.
- Removal tombstones reapply without conflict and semantic selectors fail on ambiguity.
- Dry run and apply use the same planner; writes are atomic or rollback-safe.
- Existing project-owned installer files and overlays survive upgrades.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| command/settings domain | `payload/Scripts/UETools/UEToolSuite.Settings.psm1` | Own schemas, JSON pointers, layers, ledger, planner, sync, capture, adopt, status, and atomic writes |
| command routing/runtime facade | `payload/Scripts/UETools/UEToolSuite.Dispatcher.psm1`, `payload/Scripts/ue-tools.ps1`, `payload/Scripts/UETools/UETools.psd1` | Expose command-first `settings` commands through both launchers |
| Unreal build/regeneration | `payload/Scripts/UETools/UEToolSuite.Unreal.psm1` | Replace heuristic workspace restoration with the shared provenance planner and add `-SkipSettingsSync` |
| project/engine context | `payload/Scripts/Unreal/ProjectContext.ps1` | Reuse authoritative workspace and Engine-root resolution for portable selectors |
| installer/managed payload | `payload/ue-tool-suite.manifest.json`, `payload/.gitignore`, installer tests | Install the domain and enforce tracked/private storage boundaries |
| tests | focused settings tests, Unreal regeneration tests, installer and packaging contracts | Protect operations, conflicts, transactions, integration, and deployment |
| user/developer docs | script/workflow/command/configuration documentation | Explain storage, ownership, capture/adoption, conflicts, and recovery |

### Milestones

- [x] Reproduce current heuristic limitations with focused failing tests.
- [x] Implement and validate schemas, operations, selectors, and three-way planner.
- [x] Add sync, capture, adopt, status, and command-first help.
- [x] Integrate the planner into regeneration, `-NoRegen`, hooks, and dry run.
- [x] Update installer privacy/managed-file contracts and upgrade preservation.
- [x] Run targeted settings and regeneration suites, then installer and packaging contracts.
- [x] Review the final diff for generated or unrelated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Add a focused settings domain module | Keeps provenance and structured JSON operations reusable by CLI and Unreal build without expanding the dispatcher or docs modules | Keeping the logic embedded in Unreal would make capture/adopt/status and unit testing harder |
| Store explicit ordered operations per layer | Supports fine-grained ownership, durable removals, precedence, and future operation kinds | A materialized merged settings object cannot distinguish absence from removal intent |
| Store pristine and effective snapshots in a versioned ignored ledger | Enables three-way conflict checks and capture of live removals | Comparing only pre/post regeneration repeats the unsafe heuristic |
| Represent Engine-folder removal with a semantic selector | Keeps team intent portable across machine-specific Engine paths | Storing an absolute Engine path leaks machine state and fails for teammates |

### Validation evidence

| Command/scenario | Result | Key output |
|---|---|---|
| Source inspection of current workspace merge | Confirmed failure mechanism | Missing-only merge has no ownership, removals, or baseline ledger |
| `Tests/Run-UEToolSuiteTests.ps1 -Name workspace-settings -FailFast` | Passed | Initial `PASS=22 FAIL=0`; CLI, capture, hook-trigger, and nested-help follow-up `PASS=38 FAIL=0` |
| `payload/Scripts/Tests/Test-UnrealSync-Regeneration.ps1 -FailFast` | Passed | `PASS=73 FAIL=0`, including settings-only apply, Team-overlay deletion, and conflict/no-write recovery guidance |
| `Tests/Run-UEToolSuiteTests.ps1 -Name hooks -FailFast` | Passed | Installed-fixture hook plumbing checks passed |
| `Tests/Run-UEToolSuiteTests.ps1 -Name packaging-contracts -FailFast` | Passed | Latest follow-up run: `PASS=565 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name installer -FailFast` | Passed | `PASS=209 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name upgrade-compatibility -FailFast` | Passed | `PASS=70 FAIL=0` |
| `payload/website: npm run build` after CLI help and nested guide expansion | Passed | Docusaurus client/server compiled and static files generated |
| `payload/website: npm run typecheck` | Known existing configuration conflict | Pinned compiler reports `TS5103` for required `ignoreDeprecations: "6.0"`; no settings change made |
| Scratch `git check-ignore` validation | Passed | Team overlay trackable; project overlay and state ignored |

### Rollback/recovery

The planner validates all inputs and conflicts before writing. Apply stages sibling temporary files, preserves original bytes, and rolls back already-replaced files if a later replacement fails. Unreal regeneration restores the pre-regeneration workspace and `.ignore` on any settings failure and does not proceed to build.

### Remaining risks

- Interactive Unreal Editor regeneration and live VS Code reload behavior require final user verification.
- JSONC comments are accepted on read but may be normalized when a semantic write is required because PowerShell provides no native comment-preserving JSON syntax tree.
- The installed-fixture hook plumbing and revision-driven runtime integration pass, but a real teammate pull/checkout and live VS Code reload still require final user verification after installing this branch.

### Follow-up: settings CLI binding and operator guide (2026-08-20)

- Reproduced `ue settings sync -WorkspacePath ...` failing because the shared parser always splatted a capture-only empty `Path` parameter into `sync`.
- Made option parsing subcommand-specific, retained repeated `-Path` values as a real string array, and added command-specific invalid-option messages.
- Allowed the empty JSON Pointer used by interactive capture/adoption while rejecting invalid `~` escapes.
- Fixed omitted-`-Path` detection for typed null arrays, stable handling of empty workspace arrays during whole-workspace comparison, and single-operation interactive selection.
- Added actionable validation for malformed or stale pristine/effective ledgers.
- Expanded the managed workspace-settings guide with first-run choices, complete command/option behavior, JSON Pointer rules, storage/privacy, workflows, troubleshooting, and a manual verification checklist.
- Added public-launcher regression coverage for relative `WorkspacePath`, sync, status, repeated capture paths, interactive whole-workspace folder deletion, adoption dry run, and invalid option routing.

### Follow-up: automatic Team-overlay hook synchronization (2026-08-20)

- Treat `.ue-tools/workspace-settings/team.jsonc` creation, modification, deletion, and rename as a dedicated settings-only action-plan trigger.
- Reuse the existing post-merge/post-checkout revision flow and provenance planner instead of adding a second shell-level synchronization path.
- Run settings-only hook changes without a prompt, generated-folder cleanup, Unreal project-file regeneration, or Editor build.
- Preserve fail-closed behavior: conflicts change neither workspace nor ledger and emit an actionable `ue settings status` command while Git remains completed.
- Add focused trigger coverage plus installed-runtime integration cases for automatic apply, overlay deletion, and conflict/no-write behavior.

### Follow-up: complete nested settings CLI help and Docusaurus guide (2026-09-01)

- Route `ue help settings <command>` through the same canonical help source as `ue settings help <command>` and `ue settings <command> help`.
- Give `sync`, `capture`, `adopt`, and `status` complete pages covering behavior, valid options, examples, prerequisites, and safety boundaries.
- Keep the settings overview current with every subcommand, first-run guidance, and supported help spelling.
- Organize the managed workspace-settings guide with a Docusaurus-compatible level-two/level-three table of contents, CLI guide map, command reference, workflows, recovery, and manual verification.
- Protect all four help pages and both nested/command-first routes with public-launcher regression coverage.

### Follow-up: complete Workflow Standards CLI command reference (2026-09-01)

- Add a managed `WorkflowStandards/CLI` Docusaurus category with a landing page that inventories the complete root dispatcher surface.
- Provide one page for every main command: `help`, `build`, `settings`, `docs`, `ai`, `art`, `init`, and `git`.
- Move the existing detailed workspace-settings guide into the `settings` command page instead of maintaining a duplicate root-level document.
- Derive command/subcommand/option inventories from the dispatcher and domain modules, including docs site/theme/runtime commands and Git binary-conflict helpers.
- Protect the complete category/page inventory in packaging contracts and verify the generated sidebar and routes through a production Docusaurus build.

Validation completed for this follow-up:

| Command/scenario | Result | Key output |
|---|---|---|
| `Tests/Run-UEToolSuiteTests.ps1 -Name packaging-contracts -FailFast` | Passed | `PASS=565 FAIL=0`, including the complete managed CLI-doc inventory and hashes |
| `Tests/Run-UEToolSuiteTests.ps1 -Name docs-tools -FailFast` | Passed | `PASS=652 FAIL=0 WARN=0 SKIP=1`; optional background lifecycle cases remained disabled |
| `npm run build` in `payload/website` | Passed | Docusaurus client/server compiled and all nine `/docs/cli` landing/command routes were generated |
| `npm run typecheck` in `payload/website` | Known existing configuration conflict | Pinned compiler reports `TS5103` for the intentionally retained `ignoreDeprecations: "6.0"` value |

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

---

## Plan: Per-User Global CLI Cutover

### Goal

Store the reusable PowerShell runtime once per Windows user for every installation while keeping each Unreal project's Docs content, Docusaurus website, Git hooks, Git metadata, and project configuration local.

### Non-goals

- Do not globalize the Docusaurus website, its dependencies, themes, or project Docs content.
- Do not retain a second project-local runtime installation mode.
- Do not add simultaneous multi-project docs authoring or dynamic editor API ports. A second project must fail clearly when the fixed API port belongs to another project.
- Keep payload cleanup bounded to excluding repository test suites and generated test output; do not expand into unrelated payload reclassification.
- Do not add a machine-wide elevated installation in this change.

### Current limitation

- The public entrypoint and its modules are copied into every target project under `Scripts/`.
- PowerShell aliases, Git aliases, hook helpers, and Init assume `Scripts/ue-tools.ps1` is a complete project-local runtime.
- The reusable CLI implementation cannot currently be updated once and shared by multiple Unreal projects.

### Invariants

- Global installation is per-user and requires no elevation.
- The global runtime is versioned under LocalAppData and selected through an atomically written current-version descriptor.
- A project using the global runtime keeps a small forwarding shim at `Scripts/ue-tools.ps1`, so existing hooks and direct entrypoints remain compatible.
- Repository resolution still comes from explicit `-RepoRoot` or the active Git working tree; global code location never becomes the project root.
- Website and Docs mutations remain confined to the resolved project.
- Existing project-local installs migrate safely to the global runtime layout.
- Switching an existing project to global mode removes only known suite-owned runtime files and preserves project-owned files.

### Files and boundaries

| Boundary | Files expected to change | Why |
|---|---|---|
| Installer and manifest | `Install-UEToolSuite.ps1`, `payload/ue-tool-suite.manifest.json` | Install the versioned global runtime, write stable launchers, and separate reusable runtime from project payload ownership |
| Project/global entrypoints | `payload/Scripts/ue-tools.ps1`, new global/project launcher templates or installer helpers | Preserve direct, hook, Git-alias, and shell-alias invocation while dispatching to the shared runtime |
| Runtime integration | PowerShell modules under `payload/Scripts/UETools/` and hook helpers as narrowly required | Remove assumptions that reusable modules physically live in the active project |
| GUI | `src/UEToolSuiteInstaller.Gui/Program.cs` | Use the global runtime model without exposing a redundant install-mode choice |
| Tests | installer, upgrade, docs, and packaging suites under `Tests/` and `payload/Scripts/Tests/` | Prove global reuse, project isolation, migration, and compatibility |
| Documentation | README, maintainer, architecture, release, and manual-test docs | Explain install modes, storage, version selection, and limitations |

### Milestones

- [x] Add failing global-install and shared-launcher regression cases.
- [x] Implement atomic per-user version installation and stable launcher discovery.
- [x] Install project-local content plus a forwarding shim in global mode.
- [x] Preserve aliases, hooks, Init, Docs API launch, and explicit `-RepoRoot` behavior.
- [x] Add the GUI option and update documentation.
- [x] Run targeted and cross-boundary validation.
- [x] Review the final diff for unrelated/generated changes.

### Decisions

| Decision | Reason | Alternatives rejected |
|---|---|---|
| Use `%LOCALAPPDATA%\UEToolSuite` by default | Per-user storage avoids elevation and works across multiple projects | A Program Files installation adds administrative and multi-user complexity |
| Keep version directories plus a stable launcher | Updates can be selected atomically and running processes retain their versioned paths | Overwriting one mutable runtime makes rollback and in-use updates unsafe |
| Keep a project-local forwarding shim | Existing Git hooks, Git aliases, and direct script paths continue to work | Requiring PATH-only invocation would break non-interactive hooks and existing project contracts |
| Keep the website and Docs project-local | This matches Docusaurus's project model and preserves independent dependencies and customization | A global multi-project Docusaurus host would be a much larger architecture migration |
| Keep one fixed editor API port | Concurrent docs editing is not required; a clear ownership error is sufficient | Dynamic ports add lifecycle and browser-discovery work without current product value |
| Keep repository tests source-only | Tests validate the suite from this repository and do not belong in every Unreal project or public installer bundle | Project-local test payload duplicates maintainer infrastructure and bloats installations |
| Create the ArtSource layout by default | New projects should be ready for `ue-tools art`; only the dedicated ArtSource skip option should disable this project-local setup | Treating a missing folder or the general optional docs setup switch as an implicit ArtSource opt-out |

### Validation

- A fresh install uses the global runtime and project shim by default.
- First global install creates the versioned runtime, current descriptor, stable launcher, and project shim.
- A second project reuses the same global version and independently resolves its own repository root.
- Paths containing spaces work for direct, wrapped, hook, Git-alias, and PowerShell-alias invocation.
- Updating an existing project-local install backs up/removes only known runtime files and preserves project-owned files.
- Missing, corrupt, or stale global descriptors fail with repair instructions rather than falling back to another project.
- Docs API health continues to report and enforce the active project's repository and Docs roots.
- A second docs authoring start reports that the fixed API port belongs to another project and does not adopt or stop it.
- Installer, upgrade compatibility, docs-tools, packaging contracts, website typecheck/build, and GUI publish checks pass.

Validation completed for this focused change:

| Command/scenario | Result | Key output |
|---|---|---|
| PowerShell parser checks for installer, Init, and hook scripts | Passed | No parser errors |
| `dotnet build src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj --configuration Release` | Passed | 0 warnings, 0 errors |
| `Tests/Run-UEToolSuiteTests.ps1 -Name packaging-contracts -FailFast` | Passed | `PASS=535 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name installer -FailFast` | Passed | `PASS=202 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name upgrade-compatibility -FailFast` | Passed | `PASS=70 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name shell-aliases -FailFast` | Passed | `PASS=43 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name init-repo-tool-readiness -FailFast` | Passed | `PASS=60 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name new-artsource-path -FailFast` | Passed | `PASS=26 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name docs-tools -FailFast` | Passed on clean rerun | `PASS=652 FAIL=0 WARN=0 SKIP=1` |
| Direct global `-RunInit` smoke case with spaces in project/global paths | Passed | Hook self-test and repo initialization completed |
| Clean install and retired-test upgrade cleanup | Passed | PowerShell and website tests absent; suite-owned legacy tests removed; project-owned `Scripts/Tests` file preserved |
| Default and skipped ArtSource install/init cases | Passed | Canonical template created by default; `-SkipArtSourceTools` leaves it absent |
| Rebuilt single-file installer extraction smoke | Passed | Installer remained running, manifest extracted, `payload/Scripts/Tests` absent, no .NET runtime errors |
| `npm run build` in `payload/website` | Passed | Docusaurus client and server compiled successfully |
| `npm run typecheck` in `payload/website` | Passed | TypeScript 5.6 configuration validated |

### Rollback/recovery

The installer stages a complete version directory before switching the current-version descriptor. Project migration uses the existing backup mechanism before replacing local runtime files with the forwarding shim.

### Remaining risks

- Global uninstall is not part of this first install-mode feature.
- Dynamic docs API ports and simultaneous multi-project authoring remain intentionally out of scope; the existing fixed-port ownership error is the supported behavior.
- The optional background docs lifecycle cases remain skipped unless `UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS=1`; fixed-port ownership behavior is unchanged by this cutover.

### Follow-up: portable team checkout and missing-user bootstrap (2026-09-01)

- [x] Reproduce and remove the absolute `globalRoot`, `installRoot`, and `launcherPath` values written into the tracked project marker.
- [x] Keep only deterministic version/bootstrap metadata in `.ue-tools/global-cli.json`; resolve LocalAppData independently for each Windows user.
- [x] Preserve advanced/test root selection through `UE_TOOLS_GLOBAL_CLI_ROOT` without committing that value.
- [x] When the declared runtime is missing, prompt in an interactive shell before fetching the exact project-declared release tag, installing it for this user, and resuming the original command.
- [x] Fail with an actionable interactive command and make no install attempt from hooks, CI, or explicit `-NonInteractive` invocations.
- [x] Cover separate user roots, consent/decline, non-interactive refusal, project-version pinning, path-free marker regeneration, installer upgrades, hook helpers, and team onboarding documentation.

Validation completed for this follow-up:

| Command/scenario | Result | Key output |
|---|---|---|
| PowerShell parser checks for changed installer/test/hook scripts | Passed | No parser errors |
| `Tests/Run-UEToolSuiteTests.ps1 -Name installer -FailFast` | Passed | `PASS=222 FAIL=0` |
| Clean-runner bootstrap scenarios under CI environment markers | Passed | `-RunInit` uses the installer-selected runtime root; interactive consent tests explicitly isolate CI while CI refusal remains covered |
| `Tests/Run-UEToolSuiteTests.ps1 -Name packaging-contracts -FailFast` | Passed | `PASS=585 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name upgrade-compatibility -FailFast` | Passed | `PASS=70 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -Name hooks -FailFast` | Passed | installed-fixture hook plumbing passed |
| Fresh teammate roots: non-interactive, decline, and approve | Passed | no-write refusals; approved install resumed original `help` command |
| Project marker with a different global current version | Passed | project-declared version executed |
| `npm run build` in `payload/website` | Passed | Docusaurus client/server compiled |
| `dotnet build src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj --configuration Release` | Passed | 0 warnings, 0 errors |
| `npm run typecheck` in `payload/website` | Passed | TypeScript 5.6 configuration validated |
| Remaining default release suites | Passed | settings `38`, UE regeneration `73`, AI prompt `17`, init readiness `60`, ArtSource `26`, docs tools `652`, shell aliases `43`, plus hooks and standards advisory |
| `Tests/Run-UEToolSuiteTests.ps1 -IncludeExclusive -Name ue-sync-automated -FailFast` | Passed | `PASS=48 FAIL=0` |
| `Tests/Run-UEToolSuiteTests.ps1 -IncludeExclusive -Name binary-guard-fixes -FailFast` | Passed | `PASS=98 FAIL=0 WARN=0 SKIP=1`; manual Unreal Editor integration remains intentionally separate |
| `Scripts/Publish-InstallerExe.ps1 -Version 1.0.0` | Passed | versioned `win-x64` single-file artifact produced; local build is unsigned because no certificate was supplied |
| `git ls-remote --tags origin refs/tags/v1.0.0` before release | Passed | no pre-existing `v1.0.0` tag; safe to publish the validated release commit |
