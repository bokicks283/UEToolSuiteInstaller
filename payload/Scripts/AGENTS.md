# PowerShell instructions

## Style and behavior

- Target PowerShell 7 on Windows unless a file explicitly supports another environment.
- Use `-LiteralPath` for repository and user-supplied paths.
- Normalize paths at clear boundaries.
- Use `System.StringComparison.OrdinalIgnoreCase` for Windows path equality.
- Preserve structured return objects and existing CLI/API contracts.
- Use terminating errors for failed mutations.
- Write UTF-8 without BOM where docs tooling requires it.
- Restore environment, process, and location changes in `finally`.

## Local authoring design

The docs API is intentionally local and writes directly to the active repository.

Optimize for:

- deterministic path handling
- complete validation before mutation
- conflict detection
- rollback or safe retry
- useful local error reporting
- clean process startup/shutdown
- importable/testable domain functions

Keep HTTP transport separate from docs-domain operations.

## Testing

- Use scratch repositories.
- Never mutate the checked-out repository's real `Docs/` tree in tests.
- Add API integration tests for request/response changes.
- Add lower-level tests when behavior can be reproduced without starting the listener.
