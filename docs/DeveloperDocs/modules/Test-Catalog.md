# Test Catalog

## Suite inventory

The current root manifest exposes 13 named suites. Across the current `Step "Case ..."` inventory in `Tests/` and `payload/Scripts/Tests/`, 97 named cases exist.

| Suite id | File | Category | Installed fixture required | Exclusive | Default | Behavior covered |
|---|---|---|---|---|---|---|
| `installer` | `Tests/Test-Install-UEToolSuite.ps1` | installer | no | no | yes | fresh install, update, backups, docs migration, website adoption, theme/logo, legacy cleanup |
| `upgrade-compatibility` | `Tests/Test-UpgradeCompatibility.ps1` | upgrade | no | no | yes | stable entrypoints and alias behavior across updates |
| `packaging-contracts` | `Tests/Test-PackagingContracts.ps1` | packaging | no | no | yes | GUI packaging and committed payload contract |
| `standards-advisory` | `Tests/Test-Standards-Advisory.ps1` | standards | no | no | yes | advisory static analysis checks |
| `hooks` | `Scripts/git-hooks/Test-Hooks.ps1` | hooks | yes | no | yes | git hook plumbing |
| `shell-aliases` | `payload/Scripts/Tests/Test-UESyncShellAliases.ps1` | shell | yes | no | yes | alias registration/bootstrap behavior |
| `docs-tools` | `payload/Scripts/Tests/Test-DocsTools.ps1` | docs | yes | no | yes | docs CLI, API, lifecycle, bridge, build, visibility, domains |
| `ai-startup-prompt` | `payload/Scripts/Tests/Test-AIStartupPrompt.ps1` | ai | yes | no | yes | prompt generation |
| `ue-sync-regeneration` | `payload/Scripts/Tests/Test-UnrealSync-Regeneration.ps1` | unreal | yes | no | yes | project-file regen/build fallback rules |
| `init-repo-tool-readiness` | `payload/Scripts/Tests/Test-InitRepoToolReadiness.ps1` | init | yes | no | yes | init optional-tool readiness and docs migration integration |
| `new-artsource-path` | `payload/Scripts/Tests/Test-New-ArtSourcePath.ps1` | art | yes | no | yes | ArtSource path handling |
| `ue-sync-automated` | `payload/Scripts/Tests/Test-UnrealSync.ps1` | unreal | yes | yes | no | hook trigger classification and automation behavior |
| `binary-guard-fixes` | `payload/Scripts/Tests/Test-BinaryGuard-Fixes.ps1` | binary-guard | yes | yes | no | guarded binary conflict helpers |

## Case inventory by file

| File | Named cases | Example coverage |
|---|---:|---|
| `Tests/Test-Install-UEToolSuite.ps1` | 19 | install/update, docs migration, runtime stop, managed website refresh, theme/logo, preserve existing site |
| `payload/Scripts/Tests/Test-DocsTools.ps1` | 32 | help, theme list/apply, API routes, cross-domain move, domain-root reorder, migrate-sections, start/stop/status, docs check |
| `payload/Scripts/Tests/Test-InitRepoToolReadiness.ps1` | 9 | optional tool setup, docs npm drift recovery, skip flags, docs migration failure surfacing |
| `payload/Scripts/Tests/Test-UnrealSync.ps1` | 12 | hook context, rebase skip logic, DryRun, tty/noninteractive behavior |
| `payload/Scripts/Tests/Test-UnrealSync-Regeneration.ps1` | 11 | UVS success/fallback, engine-root failure, VS Code workspace preservation, build-vs-regen triggers |
| `payload/Scripts/Tests/Test-UESyncShellAliases.ps1` | 4 | alias registration, bootstrap markers, lazy loading, active repo resolution |
| `payload/Scripts/Tests/Test-AIStartupPrompt.ps1` | 3 | default prompt, task/private context, freshness reporting |
| Other named-case files in the current search | 7 | remaining explicit `Case` steps reported by `rg` | 

## Docs-tools case map

`payload/Scripts/Tests/Test-DocsTools.ps1` is the highest-value integration suite for the docs system.

| Case range | Main topic |
|---|---|
| `1` to `1g` | CLI help, theme list/apply, API endpoint smoke coverage |
| `1h` to `1ii` | cross-domain moves, legacy normalization, long-distance same-parent reorder |
| `1j` | legacy section migration and doctor |
| `2` to `2e` | section creation and reorder |
| `3` to `3f` | page creation and visibility |
| `4` | VS Code bridge install |
| `5` to `5e` | foreground/background lifecycle, status, stop, API port conflict |
| `6` to `6b` | passthrough website scripts and raw Docusaurus args |
| `7` | TOC queueing via bridge |
| `8` to `10` | docs check, slug validation, TOC marker validation |

## Coverage matrix

| Feature | Primary automated coverage | Gaps |
|---|---|---|
| installer copy/update | `Test-Install-UEToolSuite.ps1` | live user repo acceptance still environment-dependent |
| docs CLI | `Test-DocsTools.ps1` | browser-rendered authoring UI still relies on integration/manual verification |
| docs API routes | `Test-DocsTools.ps1` | full hostile-input negative coverage was not proven in this pass |
| runtime lifecycle | `Test-DocsTools.ps1` Case `5*` | live multi-process desktop/debugger scenarios remain partially environment-specific |
| runtime discovery frontend | source-backed docs + integration behavior | no separate dedicated frontend unit test file was identified in this checkout |
| packaging contracts | `Test-PackagingContracts.ps1` | served-bundle parity still requires installed-site inspection |
| UnrealSync | `Test-UnrealSync.ps1`, `Test-UnrealSync-Regeneration.ps1` | real engine/toolchain integration still depends on environment |

## Known test-system limitations

- Several suites rely on scratch installed fixtures rather than narrow unit seams.
- Exclusive suites are intentionally excluded from default runs.
- Background docs lifecycle coverage can depend on environment toggles and available process startup behavior.
