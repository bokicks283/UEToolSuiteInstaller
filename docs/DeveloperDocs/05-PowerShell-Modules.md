# PowerShell Modules

## Module layout

The installed CLI entrypoint imports these modules from `payload/Scripts/UETools/`:

- `UEToolSuite.Core.psm1`
- `UEToolSuite.Unreal.psm1`
- `UEToolSuite.Docs.psm1`
- `UEToolSuite.Art.psm1`
- `UEToolSuite.AI.psm1`
- `UEToolSuite.Init.psm1`
- `UEToolSuite.Git.psm1`
- `UEToolSuite.Dispatcher.psm1`

The module manifest `payload/Scripts/UETools/UETools.psd1` sets `RootModule = "UEToolSuite.Core.psm1"` and `NestedModules = ...`.

## Key authored PowerShell files

| File | Purpose | Public/entry symbols | Notable dependencies | Tests |
|---|---|---|---|---|
| `Install-UEToolSuite.ps1` | installer and updater | script entrypoint, helper functions | manifest JSON, file ledgers, target repo files | `Tests/Test-Install-UEToolSuite.ps1` |
| `payload/Scripts/ue-tools.ps1` | public installed CLI entrypoint | script entrypoint | imports nested modules, resolves repo root, dispatches commands | upgrade, alias, docs, Unreal tests |
| `payload/Scripts/UETools/UEToolSuite.Core.psm1` | shared runtime helpers | `Resolve-UEToolSuiteRepoRoot`, `Set-UEToolSuiteRuntimeContext` | filesystem, process helpers | indirectly covered by most payload tests |
| `payload/Scripts/UETools/UEToolSuite.Dispatcher.psm1` | public command router | `Invoke-UEToolSuiteDispatcher` | Core, Unreal, Docs, AI, Init, Git modules | alias/dispatcher behaviors |
| `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | docs CLI, runtime lifecycle, theme/site helpers | `Invoke-DocsToolsMain`, `Invoke-DocsSectionMigration` | website root, docs root, `DocsEditorApiHost.ps1`, npm, VS Code, runtime state files | `payload/Scripts/Tests/Test-DocsTools.ps1` |
| `payload/Scripts/UETools/DocsEditorApiHost.ps1` | loopback authoring API host | script entrypoint, `Invoke-EditorApiRequest` | `HttpListener`, docs files, theme/site config, link and metadata rewrites | docs-tools route and runtime cases |
| `payload/Scripts/UETools/UEToolSuite.Init.psm1` | first-run bootstrap orchestration | `Invoke-UEToolSuiteInitRuntime` | git, git-lfs, docs tools, node/npm, Unreal build flow | `payload/Scripts/Tests/Test-InitRepoToolReadiness.ps1` |
| `payload/Scripts/UETools/UEToolSuite.Unreal.psm1` | Unreal sync/build logic | `Invoke-UEToolSuiteUnrealRuntime` | git context, engine detection, build tools | `Test-UnrealSync*.ps1` |
| `payload/Scripts/UETools/UEToolSuite.Git.psm1` | guarded binary conflict workflows | `Invoke-UEToolSuiteGitCommand` | git state, ledgers, merge/rebase helpers | `Test-BinaryGuard-Fixes.ps1` |
| `payload/Scripts/UETools/UEToolSuite.AI.psm1` | AI startup prompt helper | `Invoke-UEToolSuiteAIPromptCommand` | repo markdown scan | `Test-AIStartupPrompt.ps1` |
| `payload/Scripts/UETools/UEToolSuite.Aliases.psm1` | shell alias installation/bootstrap | `Install-ProjectShellAliases`, global aliases | profile bootstrap file, dispatcher | `Test-UESyncShellAliases.ps1` |
| `payload/Scripts/UETools/UEToolSuite.Art.psm1` | ArtSource helpers | art domain entrypoints | ArtSource template tree | `Test-New-ArtSourcePath.ps1` |

## Shared state and files

| State/file | Producer | Consumer |
|---|---|---|
| `.ue-tools/state/docs-server.json` | `UEToolSuite.Docs.psm1` | docs start/stop/status |
| `.ue-tools/state/docs-editor-api.json` within composite state | `UEToolSuite.Docs.psm1` | docs editor API lifecycle |
| `website/static/ue-tools/editor-runtime.json` | `UEToolSuite.Docs.psm1` | frontend runtime discovery |
| `.ue-tools/state/docs-managed-ledger.json` | installer | installer reruns |
| `.ue-tools/state/website-managed-ledger.json` | installer | installer reruns |
| `.ue-tools/ownership.json` under `website/` | installer/docs theme helpers | website adoption and managed-state checks |

## External commands used

Confirmed command dependencies across modules include:

- `pwsh` / `powershell`
- `git`
- `git-lfs`
- `npm`
- `node`
- `code` (optional VS Code bridge)
- Unreal project-file/build tooling through `UEToolSuite.Unreal.psm1`
- `taskkill.exe` for Windows process-tree shutdown in docs runtime stop flows

## Error and output style

Common patterns across the PowerShell layer:

- terminating errors for failed mutations
- structured `pscustomobject` return values for runtime status commands
- user-facing status lines with domain-specific prefixes (`[UE Tool Suite Installer]`, `[Init]`, docs messages)
- helper wrappers like `Info`, `Warn`, `Ok`, and test-harness assertion helpers

## Associated catalogs

- [modules/PowerShell-Function-Catalog.md](modules/PowerShell-Function-Catalog.md)
- [modules/Configuration-Catalog.md](modules/Configuration-Catalog.md)
- [13-Testing.md](13-Testing.md)
