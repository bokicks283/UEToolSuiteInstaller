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
