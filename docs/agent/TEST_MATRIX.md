# Docs editor test matrix

| Level | Purpose | Candidate tooling |
|---|---|---|
| Pure TypeScript | paths, trees, mutation planning, Markdown transforms | Vitest |
| React component | dialogs, state transitions, errors/conflicts | Vitest + React Testing Library |
| PowerShell unit | paths, plans, reference rewriting, rollback | existing harness |
| API integration | request contract against scratch repository | docs-tools suite |
| Browser integration | Docusaurus + API + resulting files | Playwright |
| Production build | Docusaurus compile, links, SSR | `npm run build` |
| Packaging | managed-file/release contracts | packaging-contracts |

## Content scenarios

- load ordinary Markdown
- save a localized edit
- no-op edit remains unchanged
- conflict after external change
- draft recovery with matching hash
- stale draft ignored
- advanced MDX remains source-only
- unsupported import/export save rejected
- LF and CRLF
- quoted/special front matter
- code fences containing Markdown-like text
- tables, tasks, links, images, admonitions, Mermaid, shortcodes, TOC behavior

## Structure scenarios

- create page at root and in section
- create section with doc/generated-index/no link
- move page between parents
- move section with descendants
- cross-domain move
- reorder first/middle/last
- rename page and section
- hide/show
- delete page, section, domain
- reject self/descendant move
- reject collision
- spaces/no-spaces
- mixed slash input
- case-only differences
- rewrite Markdown links/category IDs/navbar/sidebar doc IDs
- preserve stable slugs
- injected failure after operation N with rollback or safe retry

## Runtime scenarios

- proxy available
- runtime descriptor on non-default port
- default direct port available
- all candidates unavailable
- no overlapping discovery
- backoff timing
- recovery after API starts
- stale state file
- occupied port
- stop/status/restart
- no orphaned process state

## Suggested commands after harness work

```powershell
Push-Location payload/website
try {
  npm run test:unit
  npm run test:editor
  npm run test:e2e -- --project=chromium
  npm run typecheck
  npm run build
}
finally {
  Pop-Location
}

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File Tests/Run-UEToolSuiteTests.ps1 `
  -Name docs-tools `
  -FailFast
```
