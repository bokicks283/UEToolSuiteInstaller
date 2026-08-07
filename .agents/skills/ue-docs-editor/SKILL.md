---
name: ue-docs-editor
description: Debug, test, or change the UEToolSuite local Docusaurus editor, SiteAdmin structure editor, PowerShell docs API, Markdown serialization, domains, paths, runtime lifecycle, or navigation. Do not use for unrelated Unreal tooling.
---

# UE docs editor workflow

1. Read:
   - instruction chain
   - `docs/agent/EDITOR_ARCHITECTURE.md`
   - `docs/agent/EDITOR_CONTRACTS.md`
   - `docs/agent/TEST_MATRIX.md`

2. Classify the task:
   - inline content editing
   - Markdown/Tiptap serialization
   - SiteAdmin draft model
   - API client/discovery
   - PowerShell transport
   - path/filesystem mutation
   - domains/navigation
   - runtime lifecycle
   - installation/packaging

3. Reproduce narrowly.
   - Prefer a pure test.
   - Use a scratch docs repository.
   - Capture path tokens, expected files, route result, and runtime state.
   - Ignore generated build output as source evidence.

4. Trace the first divergence:
   - browser state
   - request payload
   - API routing
   - mutation plan
   - disk changes/reference rewrites
   - Docusaurus invalidation/reload
   - rendered navigation

5. Add a regression test before the fix when practical.

6. Implement the smallest coherent change.
   - Do not combine repair with broad refactoring.
   - Preserve stable routes/slugs unless requested.
   - Preserve drafts and optimistic conflicts.
   - Validate full structural mutations before writing.
   - Keep local runtime state deterministic.

7. Validate:
   - focused unit/case
   - relevant frontend or PowerShell suite
   - typecheck/build
   - browser/filesystem scenario for cross-boundary work
   - packaging contracts when managed paths change

8. Final report:
   - root cause
   - files changed
   - tests added
   - commands/results
   - unvalidated behavior
   - separate follow-up work
