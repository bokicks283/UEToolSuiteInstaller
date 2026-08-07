# Docs PowerShell test instructions

## Isolation

- Build scratch repositories under the test result directory.
- Allocate free ports dynamically.
- Stop API host and child processes in `finally`.
- Restore environment variables and locations in `finally`.
- Keep fixtures small and explicit.
- Stub global tools where possible.

## Structure assertions

For create/move/reorder/delete operations, verify:

- API result
- filesystem tree
- front matter and category metadata
- domain ownership
- rewritten links/doc IDs
- stable route/slug behavior
- rollback or retry behavior after injected failure
- Docusaurus rebuild/reload behavior when applicable

## Local runtime assertions

Verify:

- startup on default and non-default ports
- stale state cleanup
- stop/status behavior
- restart behavior
- clear errors when ports are occupied
- no orphaned tracked process state

New tests should be selectable by case/tag so agents can run the minimum relevant behavior.
