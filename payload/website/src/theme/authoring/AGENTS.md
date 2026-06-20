# Site authoring frontend instructions

Read:

- `docs/agent/EDITOR_ARCHITECTURE.md`
- `docs/agent/EDITOR_CONTRACTS.md`
- `docs/agent/TEST_MATRIX.md`

## Required separation

Keep these concerns separate:

- API client and typed errors
- local runtime discovery
- docs path/route conversion
- pure tree operations
- pending mutation planning/reduction
- React rendering and dialogs

Do not add more tree, path, request, or mutation helpers directly to `SiteAdminPanel.tsx` unless truly component-local.

## Draft structure changes

- The draft must be deterministic from baseline plus pending operations.
- Never mutate baseline objects.
- Every operation needs a stable ID and explicit ordering/dependencies.
- A failed save must not cause retry to repeat already-applied mutations.
- Prefer one atomic batch request.
- Until atomic batching exists, track completed operations and reconcile before retry.
- Reject invalid sequences before submission.
- Preserve draft state when persistence fails.

## Runtime discovery

- Only one discovery attempt may be active.
- Prefer the known proxy/runtime descriptor over scanning.
- Back off after failures.
- Distinguish discovering, unavailable, stale runtime, and ready states.
- Static docs rendering must remain usable when authoring is unavailable.

## Tests

Pure tree and mutation logic must be tested without React. Browser tests must verify resulting repository files and navigation.
