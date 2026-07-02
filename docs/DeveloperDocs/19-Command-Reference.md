# Command Reference

## Scope

This file lists commands that are explicitly visible from the current repository. Paths and switches come from `README.md`, `payload/Scripts/UETools/UEToolSuite.Docs.psm1`, `Tests/Run-UEToolSuiteTests.ps1`, `Scripts/Publish-InstallerExe.ps1`, and associated tests.

## Installer and update commands

| Purpose | Working dir | Shell | Exact command | Side effects | Safe on active project |
|---|---|---|---|---|---|
| Install or update UEToolSuite | repo root | `pwsh` | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync` | Copies payload, may remove old managed files, may run init | No |
| Install without backups | repo root | `pwsh` | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -NoBackup` | Same as install, but does not write backup copy | No |
| Adopt an existing website and apply a theme | repo root | `pwsh` | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -AdoptExistingWebsite -WebsiteTheme neutral` | Converts website to installer-managed state | No |

## Root test runner

| Purpose | Working dir | Shell | Exact command | Side effects | Safe on active project |
|---|---|---|---|---|---|
| Default root suite | repo root | `pwsh` | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -FailFast` | Creates result logs; may build scratch installed fixtures | Usually yes |
| Narrow named suite | repo root | `pwsh` | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -Name docs-tools -FailFast` | Runs the selected suite only | Usually yes |
| Mutating exclusive suite | repo root | `pwsh` | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -IncludeExclusive -Name ue-sync-automated -FailFast` | Can mutate test fixtures and expects exclusive access | No |

## Docs CLI commands

These commands run inside an installed repo through `Scripts/ue-tools.ps1`, which imports `UEToolSuite.Docs.psm1` and dispatches to `Invoke-DocsToolsMain`.

| Purpose | Working dir | Exact command | Expected result | Side effects |
|---|---|---|---|---|
| Root help | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs help` | Prints supported `docs` commands | None |
| Create section | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs new-section DocsSite -Title "Docs Site"` | Creates section directory and `_category_.json` | Writes Docs files |
| Create page | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs new-page Setup -Title "Setup"` | Creates page markdown file | Writes Docs files |
| Reorder page or section | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs reorder Art-Source 4` | Rewrites sidebar positions | Writes Docs files |
| Migrate legacy sections | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs migrate-sections` | Creates missing `_category_.json` files where needed | Writes Docs files |
| Preview migration only | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs migrate-sections --what-if` | Prints planned normalizations only | Read-only |
| Hide page or section | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs visibility Workflow/Daily-Flow hide` | Adds `unlisted: true` to front matter or landing doc | Writes Docs files |
| Show page or section | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs visibility Workflow show` | Removes hidden state | Writes Docs files |
| Start Docs in foreground | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs start` | Starts Docusaurus in current terminal and reports URL/API URL | Starts processes |
| Start Docs in background | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs start --background --port 3001` | Starts detached Docusaurus and API, prints log paths | Starts processes and writes runtime state |
| Stop background Docs | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs stop` | Stops tracked docs server and editor API | Stops processes and removes runtime state |
| Show runtime status | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs status` | Reports docs server/API status, URLs, log paths | May prune stale state |
| Validate docs build | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs check` | Runs docs validation/build checks and reports file count | Builds website |
| Diagnose docs environment | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs doctor` | Prints Node/npm/bridge/runtime status and migration warnings | Read-only |
| Install VS Code TOC bridge | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs install-bridge` | Copies optional bridge and reports extension state | Writes bridge files |
| List themes | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs theme list` | Prints all committed theme presets | Read-only |
| Apply theme | installed repo root | `pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Scripts\ue-tools.ps1 docs theme apply neutral` | Applies theme assets to a managed website | Writes website files |

## Website developer commands

| Purpose | Working dir | Shell | Exact command | Side effects |
|---|---|---|---|---|
| Typecheck website | `payload/website` | `npm` | `npm run typecheck` | Reads source only |
| Build website | `payload/website` | `npm` | `npm run build` | Writes `build/` output |
| Start Docusaurus directly | `payload/website` | `npm` | `npm run start` | Starts dev server |
| Pass through other package scripts | installed repo `website/` through `ue-tools docs` | `pwsh` + `npm` | `ue-tools docs <package-script> [args]` | Depends on target script |

## Packaging and release commands

| Purpose | Working dir | Exact command | Side effects |
|---|---|---|---|
| Build GUI installer EXE | repo root | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0` | Publishes GUI EXE under `dist/` |

## Verification and troubleshooting commands

| Purpose | Working dir | Exact command | Read-only |
|---|---|---|---|
| Inspect repo status | repo root | `git status --short --branch` | Yes |
| Show listener ownership | any | `Get-NetTCPConnection -LocalPort 38473 -State Listen | Select-Object -Property LocalAddress,LocalPort,OwningProcess` | Yes |
| Probe API health | installed repo or any shell | `Invoke-WebRequest -UseBasicParsing http://127.0.0.1:38473/health | Select-Object -ExpandProperty Content` | Yes |
| Compare source vs installed script hashes | repo root | `Get-FileHash .\payload\Scripts\UETools\UEToolSuite.Docs.psm1, C:\Users\Rim28\Projects\cppCozyRPG\Scripts\UETools\UEToolSuite.Docs.psm1` | Yes |

## Common errors visible from code/tests

| Area | Observed message or behavior | Evidence |
|---|---|---|
| reorder CLI | `Error: TargetPath is required.` or `Error: Position is required.` | `Test-DocsTools.ps1` Case `1c` |
| unmanaged theme apply | `Website is unmanaged.` guidance | `Test-DocsTools.ps1` Case `1e`, `UEToolSuite.Docs.psm1:704` |
| API port conflict | `Docs editor API port ... is already in use` | `Start-DocsEditorApiBackground` |
| bad docs command | `Unknown ue-tools docs command` | `Invoke-DocsToolsMain` |
