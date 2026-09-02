# Source File Index

This index covers the most meaningful authored files a new maintainer should read first. It intentionally excludes dependency trees and generated website output.

## Governance and maintainer behavior

| Path | Subsystem | Purpose | Key symbols or contract | Risk | Reading priority |
|---|---|---|---|---|---|
| `AGENTS.md` | repo governance | Root repo instructions for bounded fixes, docs validation, and test strategy | repository rules | High | 1 |
| `docs/agent/EDITOR_ARCHITECTURE.md` | editor contracts | High-level docs editor architecture | architecture contract | High | 1 |
| `docs/agent/EDITOR_CONTRACTS.md` | editor contracts | Mutation/runtime invariants for docs authoring | authoring contracts | High | 1 |
| `docs/agent/TEST_MATRIX.md` | testing | Required test selection by change type | test matrix | Medium | 1 |
| `README.md` | repo overview | Current install/test/release entrypoints | installer switches | Medium | 1 |
| `MAINTAINER_GUIDE.md` | maintainer docs | Existing operational maintainer guidance | maintainer procedures | Medium | 2 |
| `payload/Scripts/README.md` | payload docs | Script-folder responsibilities and init/docs notes | `ue-tools init`, docs readiness | Medium | 2 |

## Installer, packaging, and release

| Path | Subsystem | Purpose | Key symbols | Primary dependencies | Risk |
|---|---|---|---|---|---|
| `Install-UEToolSuite.ps1` | installer | Main installer/update entrypoint | `Read-UEToolSuitePayloadManifest`, `Invoke-ManagedDocsSmartUpdate`, `Write-ManagedWebsiteLedger` | payload manifest, filesystem, PowerShell modules | High |
| `payload/ue-tool-suite.manifest.json` | packaging contract | Declares managed payload groups and legacy cleanup paths | `managedItems`, `legacyCleanupPaths` | installer | High |
| `Scripts/Publish-InstallerExe.ps1` | release | Builds the GUI installer EXE | publish script | .NET publish, payload | Medium |
| `Scripts/Publish-GitHubRelease.ps1` | release | Validates, builds, tags, and creates the GitHub Release | release gates, tag checks, `gh release create` | git, gh, publish script, tests | High |
| `src/UEToolSuiteInstaller.Gui/Program.cs` | GUI wrapper | Single-file WinForms installer frontend | progress/log parsing, theme loading | installer script, payload | High |
| `src/UEToolSuiteInstaller.Gui/UEToolSuiteInstaller.Gui.csproj` | GUI packaging | Publish and content-inclusion contract | `PublishSingleFile`, bundled payload rules | dotnet publish | Medium |
| `.github/workflows/dependency-pr-validation.yml` | CI/validation | Dependency PR validation | workflow steps | npm/typecheck/build/tests | Medium |
| `.github/dependabot.yml` | dependency policy | Automated dependency updates for website packages | update schedule | GitHub Dependabot | Low |
| `docs/EXE-Installer-Architecture.md` | packaging docs | GUI installer architecture note | installer EXE architecture | Program.cs | Medium |
| `docs/Usage-Build-Release-Guide.md` | release docs | Release/build process note | local release publisher | publish and release scripts | Medium |

## PowerShell tool suite

| Path | Subsystem | Purpose | Key symbols | Associated tests | Risk |
|---|---|---|---|---|---|
| `payload/Scripts/ue-tools.ps1` | CLI entrypoint | Imports modules and dispatches commands | `Invoke-UEToolSuiteDispatcher` | upgrade compatibility, shell aliases | High |
| `payload/Scripts/UETools/UETools.psd1` | module manifest | Root module manifest and version metadata | `NestedModules`, `PowerShellVersion` | packaging contracts | Medium |
| `payload/Scripts/UETools/UEToolSuite.Core.psm1` | shared core | Cross-module repo/path/process helpers | core helpers | many suites | High |
| `payload/Scripts/UETools/UEToolSuite.Dispatcher.psm1` | command routing | Top-level `ue-tools` dispatcher | `Invoke-UEToolSuiteDispatcher` | shell alias compatibility | High |
| `payload/Scripts/UETools/UEToolSuite.Docs.psm1` | docs runtime | Docs CLI, lifecycle, migration, theme, and Docusaurus orchestration | `Invoke-DocsToolsMain`, `Start-DocsEditorApiBackground`, `Invoke-DocsDoctor` | docs-tools, init readiness | High |
| `payload/Scripts/UETools/DocsEditorApiHost.ps1` | docs API | Local HTTP API for tree/content/domain/site mutations | `Invoke-EditorApiRequest`, `Move-DocsNode`, `Save-DocsContent` | docs-tools | High |
| `payload/Scripts/UETools/UEToolSuite.Unreal.psm1` | Unreal workflows | UE sync/build/regen behavior | UnrealSync helpers | ue-sync suites | High |
| `payload/Scripts/UETools/UEToolSuite.Init.psm1` | repo bootstrap | `ue-tools init` logic and optional tool readiness | init helpers | init readiness | High |
| `payload/Scripts/UETools/UEToolSuite.Git.psm1` | git helpers | Git-specific commands and safety wrappers | git helpers | hook/binary-guard suites | Medium |
| `payload/Scripts/UETools/UEToolSuite.Art.psm1` | ArtSource | ArtSource helpers and validation | art helpers | new-artsource-path | Medium |
| `payload/Scripts/UETools/UEToolSuite.AI.psm1` | AI prompt tools | AI startup prompt generation | AI helpers | AI startup prompt | Medium |
| `payload/Scripts/UETools/UEToolSuite.Aliases.psm1` | shell aliases | Shell alias install/register behavior | alias helpers | shell alias compatibility | Medium |

## Docs website and frontend authoring

| Path | Subsystem | Purpose | Key symbols | Associated tests | Risk |
|---|---|---|---|---|---|
| `payload/website/docusaurus.config.ts` | website config | Docusaurus config and dev proxy | proxy plugin, navbar setup | docs-tools build/check | High |
| `payload/website/domainCatalog.ts` | docs navigation | Builds domain catalog, navbar items, and sidebars from Docs files | `getDocsDomainCatalog`, `buildDocsSidebarsConfig` | docs-tools, live authoring acceptance | High |
| `payload/website/sidebars.ts` | Docusaurus sidebars | Exposes generated sidebars | sidebar export | docs build | Medium |
| `payload/website/package.json` | website package | Node scripts and dependencies | npm scripts | docs-tools build/check | Medium |
| `payload/website/package-lock.json` | dependency lock | Website dependency install contract | lockfile | init/docs setup, packaging | Medium |
| `payload/website/tsconfig.json` | TypeScript config | Website TS settings | tsconfig | typecheck | Low |
| `payload/website/theme-presets/theme-catalog.json` | theme config | Committed theme preset catalog | theme ids | theme list/apply, GUI | Medium |
| `payload/website/static/ue-tools/editor-runtime.json` | runtime example | Served runtime descriptor location | descriptor schema | runtime discovery | Medium |
| `payload/website/src/pages/site-settings.tsx` | site admin page | Dedicated Site Settings route | `SiteSettingsPage` | runtime discovery behavior | High |
| `payload/website/src/pages/index.tsx` | landing page | Website home page | default page component | docs build | Low |
| `payload/website/src/theme/authoring/api.ts` | frontend API client | Shared hook and path/token helpers | `useDocsAuthoringApi`, `resolveSourceToken` | runtime discovery behavior | High |
| `payload/website/src/theme/authoring/runtimeDiscovery.ts` | runtime discovery | Runtime descriptor load, health probing, retry/backoff, diagnostics | `resolveAuthoringConnection`, `createAuthoringConnectionController` | runtime discovery behavior | High |
| `payload/website/src/theme/authoring/docPageAuthoring.ts` | document gating | Determines whether page authoring UI can render | `getDocPageAuthoringState` | document-page authoring logic | Medium |
| `payload/website/src/theme/authoring/AuthoringConnectionStatusCard.tsx` | error UI | Renders structured runtime failures | status card component | runtime discovery behavior | Medium |
| `payload/website/src/theme/authoring/SiteAdminPanel.tsx` | site administration | Main domain/tree/theme/site settings editor UI | `SiteAdminPanel` | live authoring acceptance | High |
| `payload/website/src/theme/authoring/shortcodes.ts` | editor utilities | Emoji/icon shortcode parsing | `parseShortcodeToken` | inline editor behavior | Low |
| `payload/website/src/theme/DocItem/Layout/index.tsx` | document authoring UI | Inline editor, save/hide/edit affordances, drafts, formatting | default layout component | docs authoring acceptance | High |
| `payload/website/src/theme/DocSidebar/index.tsx` | docs sidebar wrapper | Wraps original Docusaurus sidebar | `DocSidebarWrapper` | docs UI | Low |
| `payload/website/src/clientModules/lucideShortcodes.ts` | client module | Shortcode-related client bootstrap | client module | docs runtime | Low |

## Test system

| Path | Subsystem | Purpose | Key symbols | Risk |
|---|---|---|---|---|
| `Tests/Run-UEToolSuiteTests.ps1` | root test runner | Selects and runs suites from the manifest | `Resolve-TestSelection`, `Invoke-TestEntry` | High |
| `Tests/ToolSuiteManifest.ps1` | suite manifest | Declares suite ids, categories, and safety flags | `Get-UEToolSuiteTestManifest` | High |
| `Tests/Test-Install-UEToolSuite.ps1` | installer tests | Fresh install/update/backups/theme/website coverage | installer regression cases | High |
| `Tests/Test-PackagingContracts.ps1` | packaging tests | Confirms shipped-file and packaging contracts | packaging assertions | High |
| `Tests/Test-UpgradeCompatibility.ps1` | upgrade tests | Entry-point and alias compatibility across update | upgrade compatibility | Medium |
| `Tests/Test-Standards-Advisory.ps1` | advisory checks | Non-blocking standards scans | advisory checks | Low |
| `Tests/TestSupport/UEProjectFixtures.ps1` | test fixture helper | Creates Unreal project fixtures for root tests | fixture helpers | Medium |
| `payload/Scripts/Tests/TestHarness.ps1` | test harness | Shared assert/log helpers | harness helpers | High |
| `payload/Scripts/Tests/TestManifest.ps1` | payload test manifest | Payload-local suite metadata | manifest helpers | Medium |
| `payload/Scripts/Tests/Test-DocsTools.ps1` | docs integration | Docs CLI, API, lifecycle, authoring, move, visibility coverage | Cases `1`-`10` | High |
| `payload/Scripts/Tests/Test-InitRepoToolReadiness.ps1` | init readiness | Optional-tool readiness and migration/init behavior | Cases `1`-`6` | High |
| `payload/Scripts/Tests/Test-UnrealSync-Regeneration.ps1` | Unreal regen | UVS/build fallback and regen decisions | Cases `1`-`11` | High |
| `payload/Scripts/Tests/Test-UnrealSync.ps1` | UE Sync | Hook-context and trigger classification behavior | Cases `1`-`12` | High |
| `payload/Scripts/Tests/Test-UESyncShellAliases.ps1` | alias tests | Alias registration/bootstrap behavior | Cases `1`-`3` | Medium |
| `payload/Scripts/Tests/Test-AIStartupPrompt.ps1` | AI tests | Prompt-builder output | Cases `1`-`3` | Low |
| `payload/Scripts/Tests/BinaryGuard-Test-Functions.ps1` | binary-guard helpers | Shared binary-guard test support | helper functions | Medium |

## Reading order note

For takeover work, read these first:

1. `Install-UEToolSuite.ps1`
2. `payload/Scripts/UETools/UEToolSuite.Docs.psm1`
3. `payload/Scripts/UETools/DocsEditorApiHost.ps1`
4. `payload/website/domainCatalog.ts`
5. `payload/website/src/theme/authoring/runtimeDiscovery.ts`
6. `payload/website/src/theme/DocItem/Layout/index.tsx`
7. `Tests/Test-Install-UEToolSuite.ps1`
8. `payload/Scripts/Tests/Test-DocsTools.ps1`
