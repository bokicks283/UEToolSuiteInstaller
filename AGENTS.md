# UEToolSuiteInstaller repository instructions

## Repository shape

This repository has two layers:

- Repository root: installer, packaging, release, and bootstrap logic.
- `payload/`: the managed tool suite installed into Unreal Engine repositories.

The local docs authoring system spans:

- `payload/website/` — Docusaurus, React, TypeScript, and Tiptap.
- `payload/Scripts/UETools/DocsEditorApiHost.ps1` — local filesystem authoring API.
- `payload/Scripts/UETools/UEToolSuite.Docs.psm1` — docs CLI/runtime behavior.
- `payload/Scripts/Tests/Test-DocsTools.ps1` — docs integration coverage.

The docs website and API are local development tools, not deployment targets. Optimize for reliable local editing and repository integrity.

Read before editor changes:

- `docs/agent/EDITOR_ARCHITECTURE.md`
- `docs/agent/EDITOR_CONTRACTS.md`
- `docs/agent/TEST_MATRIX.md`

## Working agreements

- Fix one bounded behavior at a time.
- Reproduce with a regression test before production edits whenever practical.
- Prefer the smallest coherent diff.
- Do not combine a feature, architecture migration, formatting sweep, and dependency update.
- Preserve Windows PowerShell 7 behavior and Windows path semantics.
- Never claim success from compilation alone when behavior crosses browser, API, and filesystem boundaries.
- Report exact commands run, results, and anything not validated.
- Do not weaken validation, conflict detection, rollback, or assertions to make tests pass.
- Do not add dependencies without explaining why current tools are insufficient.

## Generated and derived files

Do not inspect or edit these unless the task explicitly concerns generated output:

- `**/node_modules/**`
- `payload/website/.docusaurus/**`
- `payload/website/build/**`
- `payload/website/build-debug/**`
- `**/*Results/**`
- `dist/**`
- `src/**/bin/**`
- `src/**/obj/**`

## Validation

Website:

```powershell
Push-Location payload/website
try {
  npm run typecheck
  npm run build
}
finally {
  Pop-Location
}
```

Docs tools:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File Tests/Run-UEToolSuiteTests.ps1 `
  -Name docs-tools `
  -FailFast
```

Packaging contracts when managed payload paths change:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File Tests/Run-UEToolSuiteTests.ps1 `
  -Name packaging-contracts `
  -FailFast
```

Use the narrowest applicable test first. Do not run every suite by default.

## Long changes

For work spanning three or more boundaries, create or update an execution plan using `PLANS.md`.

## Definition of done

A task is complete when:

1. The behavior is reproduced or the failure mechanism is demonstrated.
2. A focused test protects the behavior.
3. Relevant targeted checks pass.
4. Cross-boundary behavior is integration-tested when applicable.
5. No generated or unrelated files are included.
6. Remaining uncertainty is stated.
