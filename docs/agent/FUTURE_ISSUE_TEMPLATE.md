# Future local editor issue prompt

```text
Goal:
[One observable outcome.]

Observed behavior:
[Exact reproduction steps and result.]

Expected behavior:
[Expected result.]

Environment:
- Branch/commit:
- PowerShell/Node versions:
- Command:
- Browser route:
- Docs path token:
- Reproduces after clean restart?:

Evidence:
- Exact error:
- Screenshot/video:
- Logs:
- Smallest fixture:

Read:
- AGENTS.md
- closest nested AGENTS.md
- docs/agent/EDITOR_ARCHITECTURE.md
- docs/agent/EDITOR_CONTRACTS.md

Constraints:
- Reproduce with a targeted regression test before production edits.
- Trace browser state through API and filesystem output.
- Keep the diff bounded.
- Do not edit generated output.
- Use a scratch Docs tree.
- Preserve stable routes, drafts, conflicts, and content round trips.

Required process:
1. State a falsifiable failure assertion.
2. Find the first actual/expected divergence.
3. Identify root cause.
4. Add the failing test.
5. Implement the smallest coherent fix.
6. Run focused tests, relevant suite, typecheck, and build.
7. Report results and remaining uncertainty.

Definition of done:
[Specific browser, API, filesystem, and navigation assertions.]
```
