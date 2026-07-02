# Known Risks and Technical Debt

## Confirmed concentration points

| Item | Evidence | Severity | Consequence |
|---|---|---|---|
| Very large inline editor component | `payload/website/src/theme/DocItem/Layout/index.tsx` | High | small edits can affect serialization, drafts, toolbar behavior, and visibility together |
| Very large docs runtime module | `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | High | lifecycle, theme/site helpers, CLI parsing, docs mutation, and runtime state are tightly coupled |
| Large API host with route + domain logic mixed together | `payload/Scripts/UETools/DocsEditorApiHost.ps1` | High | transport and filesystem mutation concerns are not cleanly separated |
| Split PowerShell version signals | repo instructions target PowerShell 7, but `UETools.psd1` declares `PowerShellVersion = "5.1"` | Medium | takeover confusion and possible runtime expectation drift |
| Managed build artifacts in install contract | website build files are tracked by installer tests and ledgers | Medium | source/build/install drift remains a recurring risk area |

## Current technical-debt themes

- duplicated or layered lifecycle validation between frontend and PowerShell
- partial transaction models instead of one global mutation framework
- runtime-state staleness as a first-class failure mode
- large functions/components that make small changes high-risk
- many guarantees proved by integration tests rather than smaller unit seams

## Possible but not fully proven risks

| Risk | Why it is only possible, not fully proven |
|---|---|
| Another local process could mimic the docs API health contract | current source validates identity fields, but there is no authentication layer |
| Some installed-site drift may still escape source-only checks | the repo has parity tests, but live served-bundle validation is still environment-dependent |
| Route-specific rollback logic may not compose cleanly across multi-step mutations | tests cover several cases, but not every possible mutation interleave |

## Suggested follow-up investigation

- continue shrinking `DocItem/Layout/index.tsx`
- continue separating `DocsEditorApiHost.ps1` transport from docs-domain operations
- keep packaging/build parity checks strong whenever website assets or runtime discovery changes
