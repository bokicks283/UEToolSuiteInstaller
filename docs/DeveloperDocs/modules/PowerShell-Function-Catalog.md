# PowerShell Function Catalog

This catalog focuses on the most meaningful authored PowerShell functions a maintainer will touch while changing installer, docs, runtime, or repo-bootstrap behavior. It is intentionally selective rather than a dump of every tiny helper in the checkout.

## Installer (`Install-UEToolSuite.ps1`)

| Function | Kind | Purpose | Side effects | Main callers or coverage |
|---|---|---|---|---|
| `Read-UEToolSuitePayloadManifest` | internal | Load and validate payload manifest | reads manifest JSON | installer entrypoint, packaging tests |
| `Copy-ToBackup` | internal | Copy replaced managed content to backup root | writes backup files | installer Cases `1`, `2` |
| `Ensure-DocsCategoryMetadataFiles` | internal | Ensure required docs metadata exists during install flows | writes `_category_.json` when needed | installer migration coverage |
| `Invoke-InstalledDocsSectionMigration` | internal | Run installed docs-section normalization | writes Docs metadata | installer Cases `2d`-`2f` |
| `Stop-InstalledDocsRuntimeIfPresent` | internal | Stop tracked docs runtime before updates | stops processes, removes runtime state | installer Case runtime stop |
| `Apply-WebsiteThemeAndBranding` | internal | Apply theme/logo overrides during install | writes website theme assets/config | installer Cases `5b`-`5h` |
| `Read-ManagedDocsLedger` | internal | Load docs ledger from installed repo | reads ledger JSON | docs preserve-first update |
| `Write-ManagedDocsLedger` | internal | Persist docs ledger | writes ledger JSON | installer |
| `Read-ManagedWebsiteLedger` | internal | Load website ledger from installed repo | reads ledger JSON | website update logic |
| `Write-ManagedWebsiteLedger` | internal | Persist website ledger | writes ledger JSON | installer |
| `Merge-WebsitePackageJson` | internal | Merge or preserve website package metadata | writes `package.json` | website update logic |
| `Invoke-ManagedDocsSmartUpdate` | internal | Preserve-first Docs update logic | writes docs, update candidates | installer tests |

## CLI entry and dispatch

| Function | Kind | Purpose | Side effects | Main callers or coverage |
|---|---|---|---|---|
| `Write-UEToolSuiteEntrypointError` | internal | Friendly red CLI error output | writes console output | `payload/Scripts/ue-tools.ps1` |
| `Invoke-UEToolSuiteDispatcher` | exported | Top-level `ue-tools` routing | dispatches subcommands | alias and upgrade tests |
| `Set-UEToolSuiteRuntimeContext` | exported/core | Record script runtime context | writes process-scoped state | `ue-tools.ps1` |
| `Resolve-UEToolSuiteRepoRoot` | exported/core | Resolve active repo root from args or current location | filesystem reads | `ue-tools.ps1`, many modules |

## Docs module lifecycle and command surface (`UEToolSuite.Docs.psm1`)

| Function | Kind | Purpose | Side effects | Main callers or coverage |
|---|---|---|---|---|
| `Invoke-DocsToolsMain` | exported | Main `ue-tools docs` command dispatcher | may start processes or mutate files | most docs-tools cases |
| `Get-DocsToolsRootHelp` | internal | Build root help text | none | docs help cases |
| `Get-DocsToolsCommandHelp` | internal | Build per-command help text | none | docs help cases |
| `Resolve-DocsToolsCommandAlias` | internal | Normalize aliases like `create-page` -> `new-page` | none | docs help/dispatch |
| `Invoke-NewSection` | internal | CLI section scaffolding | writes Docs directory and metadata | Cases `2`, `2b`, `2c` |
| `Invoke-NewPage` | internal | CLI page scaffolding | writes markdown page | Cases `3`-`3d` |
| `Invoke-DocsReorder` | internal | CLI reorder wrapper | writes position metadata | Cases `2d`, `2e` |
| `Invoke-DocsVisibility` | internal | CLI hide/show wrapper | writes front matter | Case `3f` |
| `Invoke-DocsSectionMigration` | exported | Shared legacy-section migration implementation | writes `_category_.json` | installer/init/docs doctor coverage |
| `Invoke-DocsCheck` | internal | Validate docs content and run Docusaurus build | runs build process | Cases `8`-`10` |
| `Invoke-InstallBridge` | internal | Install optional VS Code bridge | writes bridge files | Case `4` |
| `Get-DocsEditorApiStatus` | internal | Determine whether a tracked or untracked API runtime is healthy | reads process/runtime state | lifecycle commands |
| `Start-DocsEditorApiBackground` | internal | Start or reuse background editor API | starts process, writes runtime descriptor/state | Cases `5c`-`5e` |
| `Stop-DocsEditorApiBackground` | internal | Stop tracked API and clean runtime state | kills process tree, removes state | lifecycle commands |
| `Invoke-DocsStartForeground` | internal | Foreground `docs start` path | starts API and npm start | Case `5` |
| `Invoke-DocsStartBackground` | internal | Detached `docs start --background` path | starts processes, writes logs/state | Cases `5b`-`5e` |
| `Invoke-DocsStop` | internal | Stop tracked docs server(s) and API | kills process trees, clears state | stop/status cases |
| `Invoke-DocsStatus` | internal | Report docs runtime state | may prune stale state | lifecycle cases |
| `Invoke-DocsDoctor` | internal | Print docs environment and runtime diagnostics | reads tool/runtime state | doctor and migration cases |

## Docs Editor API host (`DocsEditorApiHost.ps1`)

| Function | Kind | Purpose | Side effects | Main callers or coverage |
|---|---|---|---|---|
| `Write-JsonResponse` | internal | Serialize success JSON | writes HTTP response | every route |
| `Write-JsonTextResponse` | internal | Write already-serialized JSON text | writes HTTP response | content route |
| `Write-ErrorResponse` | internal | Serialize API error JSON | writes HTTP response | route error handling |
| `Read-JsonBody` | internal | Parse request JSON | reads request body | POST routes |
| `Get-DocsDomainDefinitions` | internal | Load normalized domain definitions | reads `_domains.json` and Docs tree | domain/tree routes |
| `Get-DocsTree` | internal | Build visible tree payload | reads Docs tree | `/api/tree` |
| `Get-DocsTreeChildren` | internal | Recursive tree child enumeration | reads Docs tree | `/api/tree` |
| `Get-DocsContent` | internal | Read page content with hash/mtime | reads markdown file | `GET /api/content` |
| `Save-DocsContent` | internal | Save page content with hash check | writes markdown file | `POST /api/content` |
| `Set-DocsPageVisibility` | internal | Toggle hidden/unlisted state | writes front matter | `POST /api/visibility` |
| `Update-DocsNodeMetadata` | internal | Update page/section labels or titles | writes metadata | `POST /api/node/metadata` |
| `Create-DocsPage` | internal | Create a page through API | writes markdown file | `POST /api/create/page` |
| `Create-DocsSection` | internal | Create section tree and metadata | writes directory, `_category_.json`, optional landing doc | `POST /api/create/section` |
| `Create-DocsDomain` | internal | Create domain metadata and optional landing content | writes `_domains.json` and Docs files | `POST /api/create/domain` |
| `Move-DocsDomain` | internal | Reorder domains | writes `_domains.json` | `POST /api/domains/reorder` |
| `Update-DocsDomain` | internal | Rename or relabel domain | writes `_domains.json`, possibly docs paths | `POST /api/domains/update` |
| `Remove-DocsDomain` | internal | Delete domain definition | writes `_domains.json` | `POST /api/domains/delete` |
| `Remove-DocsNode` | internal | Delete page or section | removes files/directories | `POST /api/delete` |
| `Move-DocsNode` | internal | Move page or section, including cross-domain and reorder semantics | renames/moves files and metadata | `POST /api/move` |
| `Rename-DocsNode` | internal | Rename path token and filesystem path | renames files/directories | `POST /api/rename` |
| `Reorder-DocsNode` | internal | Update order/position | writes front matter or category position | `POST /api/reorder` |
| `Apply-SiteThemeFromApiBody` | internal | Apply theme changes from API body | writes website theme files | site settings routes |
| `Apply-SiteBrandingFromApiBody` | internal | Apply branding changes from API body | writes site assets/config | site settings routes |
| `Apply-SiteOverridesFromApiBody` | internal | Apply site override settings | writes config files | site settings routes |
| `Invoke-EditorApiRequest` | internal | Central router and method dispatcher | reads/writes through route functions | every API request |

## Other meaningful modules

| Function | Source | Kind | Purpose | Coverage |
|---|---|---|---|---|
| `Register-ProjectShellAliases` | `UEToolSuite.Aliases.psm1` | exported | Register `ue-tools` and related aliases | alias cases |
| `Install-ProjectShellAliases` | `UEToolSuite.Aliases.psm1` | exported | Write alias bootstrap markers/files | alias cases |
| `Invoke-InitRepo` | `UEToolSuite.Init.psm1` | exported | Main `ue-tools init` path | init readiness cases |
| `Sync-DocsToolReadiness` | `UEToolSuite.Init.psm1` | internal | Docs-specific readiness checks and npm sync | init readiness cases |
| `New-UEToolSuiteAIStartupPrompt` | `UEToolSuite.AI.psm1` | exported | Build AI startup prompt payload | AI startup prompt cases |
| `New-ArtSourcePath` | `UEToolSuite.Art.psm1` | exported | Create or validate canonical ArtSource paths | new-artsource-path suite |
| `Invoke-UEToolSuiteUnrealRuntime` | `UEToolSuite.Unreal.psm1` | exported | Main Unreal runtime/build entrypoint used by CLI flows | UnrealSync suites |
| `Invoke-UnrealProjectRegeneration` | `UEToolSuite.Unreal.psm1` | internal | Handle project-file regeneration/build sequencing | Unreal regen suite |
| `Enable-GitHooks` | `UEToolSuite.Git.psm1` or git hook support layer | exported/helper | Configure shared git hook plumbing | hook suite |

## Test infrastructure helpers

| Function | Source | Purpose | Coverage |
|---|---|---|---|
| `Initialize-TestHarness` | `payload/Scripts/Tests/TestHarness.ps1` | Shared test logging/assert initialization | many payload suites |
| `Assert-Condition` | `payload/Scripts/Tests/TestHarness.ps1` | Core assertion helper | many payload suites |
| `Write-Utf8NoBomFile` | `payload/Scripts/Tests/TestHarness.ps1` | Deterministic file writing in tests | many payload suites |
| `New-UEToolSuiteTestEntry` | `Tests/ToolSuiteManifest.ps1` | Create root suite manifest entry | root runner |
| `Get-UEToolSuiteTestManifest` | `Tests/ToolSuiteManifest.ps1` | Return root suite metadata | root runner |
| `Resolve-TestSelection` | `Tests/Run-UEToolSuiteTests.ps1` | Select suites by name/category/default/exclusive flags | root runner |
| `Invoke-TestEntry` | `Tests/Run-UEToolSuiteTests.ps1` | Execute one selected suite | root runner |
| `New-InstalledToolSuiteFixture` | `Tests/Run-UEToolSuiteTests.ps1` | Build a scratch installed repo fixture | root runner |

## Count note

This catalog covers 77 meaningful PowerShell functions or function-level entrypoints across installer, docs runtime, API, and test infrastructure.
