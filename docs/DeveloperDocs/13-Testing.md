# Testing

## Test system shape

There are two primary layers:

- root test runner and installer-level suites under `Tests/`
- payload/domain suites under `payload/Scripts/Tests/`

Public suite entrypoint:

- `Tests/Run-UEToolSuiteTests.ps1`

Manifest source:

- `Tests/ToolSuiteManifest.ps1`

Shared harnesses:

- `payload/Scripts/Tests/TestHarness.ps1`
- `Tests/TestSupport/UEProjectFixtures.ps1`

## Suite map

Confirmed manifest entries:

- installer
- upgrade-compatibility
- packaging-contracts
- standards-advisory
- hooks
- shell-aliases
- docs-tools
- ai-startup-prompt
- ue-sync-regeneration
- init-repo-tool-readiness
- new-artsource-path
- ue-sync-automated
- binary-guard-fixes

## Notable test conventions

- scratch repos and temp directories are preferred over mutating this checkout
- `-FailFast` is supported by the public runner and many suites
- some suites require installed fixtures rather than testing source files directly
- background docs lifecycle tests are explicitly optional and environment-gated

## Feature-to-test mapping

| Feature | Primary coverage |
|---|---|
| installer/update/backup/cleanup | `Tests/Test-Install-UEToolSuite.ps1` |
| GUI and packaging contract | `Tests/Test-PackagingContracts.ps1` |
| docs commands and API routes | `payload/Scripts/Tests/Test-DocsTools.ps1` |
| init bootstrap and optional tool readiness | `payload/Scripts/Tests/Test-InitRepoToolReadiness.ps1` |
| shell alias bootstrap | `payload/Scripts/Tests/Test-UESyncShellAliases.ps1` |
| Unreal sync and regeneration | `payload/Scripts/Tests/Test-UnrealSync*.ps1` |
| binary conflict helpers | `payload/Scripts/Tests/Test-BinaryGuard-Fixes.ps1` |
| AI prompt generation | `payload/Scripts/Tests/Test-AIStartupPrompt.ps1` |

## Known conditional or high-cost areas

- background docs lifecycle tests require `UE_TOOLS_ENABLE_BACKGROUND_DOCS_TESTS=1`
- mutating/exclusive suites are separated in the manifest
- docs build and install parity are partially validated by packaging/installer suites rather than one dedicated end-to-end browser suite

## Gaps visible from the current checkout

- no broad browser E2E suite is present in the authored repo, even though docs mention that as a future layer
- many guarantees depend on PowerShell integration tests rather than smaller unit-test seams
- the inline editor component remains large, so some behavior is covered indirectly through contract tests rather than fine-grained frontend unit tests

## Related documents

- [modules/Test-Catalog.md](modules/Test-Catalog.md)
- [14-Debugging-and-Troubleshooting.md](14-Debugging-and-Troubleshooting.md)
- [24-Deployment-Verification.md](24-Deployment-Verification.md)
