# UETools docs-module instructions

## Intended dependency direction

1. HTTP host parses local request input.
2. Application service coordinates one operation.
3. Docs-domain functions validate and produce a mutation plan.
4. Filesystem adapter applies the plan.
5. Host serializes the result.

Do not add unrelated responsibilities to `DocsEditorApiHost.ps1` or `UEToolSuite.Docs.psm1`. Prefer focused modules imported by the existing entrypoint.

## Mutation rules

- Browser/API paths are relative to `Docs/` and use `/`.
- Resolve paths consistently before mutation.
- Reject invalid source/destination identity, descendant moves, collisions, invalid names, and unsupported item types before changing disk.
- Preserve stable routes/slugs unless explicitly changing route semantics.
- Keep `_domains.json`, `_category_.json`, front matter, sidebar references, ownership, and moved Markdown links consistent.
- Multi-file changes must be atomic or safely resumable.
- A failed operation must not leave an unexplained partial state.

## Local runtime rules

- `/health` must be cheap and side-effect free.
- Startup must handle stale runtime files and occupied ports clearly.
- Shutdown must clean tracked runtime state.
- Error responses should have stable codes/types instead of requiring text parsing.
- Local debug mode may include detailed stack information; ordinary mode should stay readable.

## Validation

For docs API or structure changes:

- run focused docs-tools cases
- run the complete docs-tools suite before completion
- run website typecheck/build
- add a narrowly named regression case
