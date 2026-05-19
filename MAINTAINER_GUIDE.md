# UE Tool Suite Maintainer Guide

Standalone installer/updater for a portable Unreal Engine 5 tooling suite.

This repo is the source of truth for:
- Installer/update logic (`Install-UEToolSuite.ps1`)
- Installable payload (`payload/`)
- Tests for installer + payload behavior
- GUI `.exe` packaging wrapper (`src/UEToolSuiteInstaller.Gui/`)

The target design is conservative and compatibility-first: stable user commands, thin wrappers, and shared internals.

## 1) What This Project Delivers

When you install into a UE5 repo, the suite provides:
- Git hook plumbing + binary conflict guard workflows
- Unreal sync/build automation
- ArtSource scaffolding helpers
- Docs tooling + optional docs bridge integration
- AI startup prompt helper
- Optional payload test scripts

It also supports repeated updates, preserves project-local files where possible, and keeps managed changes auditable through backup snapshots.

## 2) High-Level Architecture

### Installer boundary vs payload boundary

- Installer logic lives in this repo root (`Install-UEToolSuite.ps1`).
- Installed projects receive payload assets only (scripts/docs/hooks/tests/website).
- Payload does **not** self-update; updates are driven by running installer again.

### Manifest-driven install/update

`payload/ue-tool-suite.manifest.json` defines:
- `managedTextItems`: marker-managed root text files (`.gitattributes`, `.gitignore`)
- `managedItems` by category (base, docs, website, tests, codex, art tools, etc.)
- `legacyCleanupPaths` for old-path removals

Installer behavior is data-driven from manifest categories plus install flags.

### Unified command model

Current public command surface is intentionally stable:
- `ue-tools`
- `art-tools`
- `docs-tools`
- `ai-tools`
- `ai-prompt`

Compatibility aliases remain available: `codex-tools`, `codex-prompt`.
Deprecation policy: keep compatibility aliases until one full release cycle passes with tests proving `ai-tools`/`ai-prompt` behavior parity in install, upgrade, and profile bootstrap flows.

Command specs and registry live in:
- `payload/Scripts/UETools/UEToolSuite.Core.psm1`
- `payload/Scripts/UETools/UETools.psd1`

Compatibility wrappers are retained (`Scripts/UETools/ue-tools.ps1` forwards to `Scripts/ue-tools.ps1`).

## 3) Repository Layout (Maintainer View)

Top-level:
- `Install-UEToolSuite.ps1`: installer/update engine
- `payload/`: installable suite content
- `Tests/`: installer-level and upgrade-level test runner + suites
- `Scripts/`: build/signing helper scripts for publishing installer `.exe`
- `src/UEToolSuiteInstaller.Gui/`: WinForms launcher that invokes installer

Payload structure:
- `payload/Scripts/Init-Repo.ps1`: first-run bootstrap orchestration
- `payload/Scripts/ue-tools.ps1`: unified entrypoint
- `payload/Scripts/UETools/`: shared command registry + module manifest + compatibility wrapper
- `payload/Scripts/Unreal/`: UnrealSync + project context + alias/bootstrap logic + ArtSource tool
- `payload/Scripts/Docs/DocsTools.ps1`: docs command system
- `payload/Scripts/Codex/Get-CodexStartupPrompt.ps1`: AI prompt tool (stable script path)
- `payload/Scripts/git-hooks/` + `.githooks/`: hook plumbing
- `payload/Scripts/git-tools/`: `git ours`, `git theirs`, `git conflicts` support
- `payload/Scripts/Tests/`: payload-level suites
- `payload/Docs/`, `payload/website/`: docs content and Docusaurus app

## 4) Installer Internals (`Install-UEToolSuite.ps1`)

### Core flow

1. Resolve and validate payload root + target repo root.
2. Resolve target `.uproject` (explicit path or auto-discovery in repo root).
3. Light UE5 compatibility warning via `.uproject.EngineAssociation`.
4. Read manifest (`Read-UEToolSuitePayloadManifest`).
5. Build effective managed item set from manifest categories + installer switches.
6. Apply managed text block updates (`.gitattributes`, `.gitignore`) via marker blocks.
7. Copy managed file/dir items (merge directories, replace overlapping managed files, backup replaced paths).
8. Optional legacy cleanup (remove old paths like `Scripts/Install-UEProjectTools.ps1`).
9. Optional target bootstrap (`-RunInit`) with forwarded init switches.

### Backup model

By default, replaced managed files/paths are copied to:
- `.ue-tools-installer-backups/<yyyyMMdd-HHmmss>/...`

Disable with:
- `-NoBackup`

### Managed text marker model

Installer does not overwrite full root `.gitattributes` / `.gitignore` by default.
It updates a marker block only:
- `.gitattributes` markers:
  - `# >>> ue tool suite git attributes >>>`
  - `# <<< ue tool suite git attributes <<<`
- `.gitignore` markers:
  - `# >>> ue tool suite git ignore >>>`
  - `# <<< ue tool suite git ignore <<<`

This preserves project-specific rules while keeping suite-managed rules current.

### Installer command reference

Primary:
- `-TargetRepoRoot` (required)
- `-PayloadRoot`
- `-TargetUProjectPath`
- `-RunInit`

Install scope toggles:
- `-SkipDocs`
- `-SkipWebsite`
- `-SkipTests`
- `-SkipCodexTools`
- `-SkipArtSourceTools`
- `-SkipCodingStandardsTools`

Init forwarding toggles (used only with `-RunInit`):
- `-SkipLfsPull`
- `-SkipShellAliases`
- `-SkipOptionalToolSetup`
- `-SkipDocsSetup`
- `-SkipDocsNpmInstall`
- `-ForceDocsNpmInstall`
- `-SkipDocsBridgeInstall`
- `-SkipUnrealSync`
- `-NoBuild`
- `-NoRegen`

Safety/cleanup:
- `-NoBackup`
- `-NoLegacyCleanup`

## 5) Payload Tooling: What Each Tool Does

### A) `Scripts/Init-Repo.ps1` (bootstrap orchestrator)

Responsibilities:
- Initializes repo-local Git LFS filters
- Applies recommended local git config
- Enables hooks (`core.hooksPath=.githooks`)
- Configures git aliases (`ours`, `theirs`, `conflicts`)
- Installs shell alias bootstrap block (unless skipped)
- Runs hook self-test
- Optionally prepares docs tooling prerequisites
- Optionally validates ArtSource template shape
- Optionally runs initial Unreal sync
- Emits readiness summary (`OK` / `WARN` / `SKIP`)

Key switches:
- `-RepoRoot`, `-UProjectPath`, `-WorkspacePath`
- `-SkipLfsPull`, `-SkipShellAliases`, `-SkipOptionalToolSetup`
- `-SkipDocsSetup`, `-SkipDocsNpmInstall`, `-ForceDocsNpmInstall`, `-SkipDocsBridgeInstall`
- `-SkipUnrealSync`, `-NoBuild`, `-NoRegen`
- `-Config`, `-Platform`

### B) `ue-tools` command family

Entrypoints:
- `Scripts/ue-tools.ps1` (primary)
- `Scripts/UETools/ue-tools.ps1` (compat wrapper)

Current commands:
- `ue-tools help`
- `ue-tools build [UnrealSync options]`

Behavior:
- `build` forwards to `Scripts/Unreal/UnrealSync.ps1` and always includes `-Force`
- option-first invocation defaults to `build` (for compatibility)

### C) `Scripts/Unreal/UnrealSync.ps1`

Core behavior:
- Detects project context (`.uproject`, workspace, engine root)
- Computes action plan from changed files (build-only vs regen+build)
- Supports hook and manual invocation modes
- Handles non-interactive safety paths in hook contexts
- Supports cleanup toggles for generated/saved/cache dirs
- Can snapshot/restore workspace artifacts around regeneration

Important switches:
- Hook args: `-OldRev`, `-NewRev`, `-Flag`
- Control: `-Force`, `-NoRegen`, `-NoBuild`, `-DryRun`, `-NonInteractive`
- Cleanup: `-CleanGenerated`, `-CleanSaved`, `-CleanCache`
- Context: `-RepoRoot`, `-WorkspacePath`, `-UProjectPath`
- Build: `-Config`, `-Platform`

### D) `Scripts/Unreal/New-ArtSourcePath.ps1` (`art-tools`)

Responsibilities:
- Normalizes ArtSource template shape to canonical `ArtSource/_Template`
- Supports creating new art item folders from canonical template
- Handles path/domain selection and folder naming checks

Wrapper command:
- `art-tools`

### E) `Scripts/Docs/DocsTools.ps1` (`docs-tools`)

Responsibilities:
- Docs section/page scaffolding
- Docs item reordering
- Docusaurus command pass-through
- Local docs server start/stop/status
- Prerequisite diagnostics (`doctor`)
- Optional VS Code bridge install + TOC request queueing

Primary command groups:
- `help`
- `new-section` / `create-section`
- `new-page` / `create-page`
- `reorder`
- `start`, `stop`, `status`, `check`, `doctor`
- `install-bridge`
- pass-through: `build`, `clear`, `deploy`, `serve`, `swizzle`, `write-translations`, `write-heading-ids`, `typecheck`, `docusaurus`

### F) Codex helpers

Script:
- `Scripts/Codex/Get-CodexStartupPrompt.ps1`

Wrapper commands:
- `ai-prompt`
- `ai-tools prompt` (`codex-tools prompt` compatibility alias)

Responsibilities:
- Build startup prompt text from repo markdown context
- Include private context optionally
- Optional clipboard copy
- Snapshot-staleness notice for coding standards source

Switches:
- `-Task`
- `-IncludePrivate`
- `-CopyToClipboard`
- `-RepoRoot`

### G) Git conflict tooling (`git ours`, `git theirs`, `git conflicts`)

Scripts:
- `Scripts/git-tools/conflicts.ps1`
- `Scripts/git-tools/GitConflictHelpers.ps1`

Responsibilities:
- Guarded binary conflict workflows for merges/rebases
- Enforced approvals before continue/commit paths
- Status/sync/continue/abort/restart operations

Commands:
- `git ours <pattern...>`
- `git theirs <pattern...>`
- `git conflicts status|sync|continue|abort|restart|help`

### H) Hook plumbing

Scripts:
- `.githooks/*`
- `Scripts/git-hooks/hook-common.sh`
- `Scripts/git-hooks/Enable-GitHooks.ps1`
- `Scripts/git-hooks/Test-Hooks.ps1`

Responsibilities:
- Standardize hook execution context
- Suppress duplicate nested UnrealSync calls where required
- Validate hook environment + helper sourcing

## 6) Multi-Project Safety and Profile Behavior

This suite is designed so multiple UE repos can coexist on one machine without alias conflicts.

Mechanism:
- One managed profile block:
  - `# >>> ue project shell aliases >>>`
  - `# <<< ue project shell aliases <<<`
- Block sources `%LOCALAPPDATA%\UEToolSuite\Shell\UEToolsBootstrap.ps1`
- Bootstrap resolves **current git repo at command runtime** and invokes that repo's scripts

Result:
- Running `ue-tools` from Repo A targets Repo A
- Running `ue-tools` from Repo B targets Repo B
- Installing into a second repo updates the same managed profile block instead of appending duplicates

## 7) How The Code Is Organized (for Extension Work)

### Shared runtime helpers

`payload/Scripts/UETools/UEToolSuite.Core.psm1` now centralizes shared runtime primitives used across tools:
- UTF8 (no BOM) writes
- Repo root resolution
- Repo-relative path resolution with typed existence checks
- Unified command registry/specs for wrappers

Module entry is defined by:
- `payload/Scripts/UETools/UETools.psd1`

Tools import module manifest when present and fall back to direct `.psm1` import for compatibility.

### Thin wrapper strategy

User-facing commands should stay thin:
- parse command-level intent
- resolve repo + target script
- delegate domain behavior

Domain behavior stays in domain scripts/modules (Unreal/Docs/Codex/Git).

### Manifest-first installer changes

For adding/removing payload paths:
1. Update `payload/ue-tool-suite.manifest.json`
2. Add/update files in `payload/`
3. Add/adjust tests proving update behavior and compatibility

Avoid hardcoding new path logic directly in installer control flow when manifest can model it.

## 8) Testing Strategy

### Test runners

Installer-level runner:
- `Tests/Run-UEToolSuiteTests.ps1`

Payload-level runner:
- `payload/Scripts/Tests/Run-AllTests.ps1`

### Current installer-level suite map

Defined in `Tests/ToolSuiteManifest.ps1`:
- Non-mutating/default suites:
  - installer regression
  - upgrade compatibility
  - hooks
  - shell aliases
  - docs tools
  - codex startup prompt
  - UE sync regeneration
  - init repo readiness
  - artsource path
- Mutating/exclusive suites:
  - `ue-sync-automated`
  - `binary-guard-fixes`

### Recommended run sequence during refactors

1. Run non-mutating suites first:
```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -FailFast
```

2. Run mutating suites separately:
```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '.\Tests\Run-UEToolSuiteTests.ps1' -IncludeExclusive -Name @('ue-sync-automated','binary-guard-fixes') -FailFast"
```

These mutating suites perform branch/rebase/merge operations in installed fixture repos, not in this source repo branch.

## 9) Build and Ship the `.exe` Installer

GUI project:
- `src/UEToolSuiteInstaller.Gui/`
- WinForms app targeting `net10.0-windows`
- Bundles `Install-UEToolSuite.ps1` and full `payload/`
- Launches installer through `pwsh.exe`

Build script:
- `Scripts/Publish-InstallerExe.ps1`

Example:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0
```

Output:
- `dist/UEToolSuiteInstaller-<version>-win-x64.exe`

Optional signing:
- `-CertificateThumbprint` or `-CertificatePath` (+ `-CertificatePassword`)

Local signing test cert helper:
- `Scripts/New-TestCodeSigningCertificate.ps1`

## 10) Maintainer Workflow

For normal maintenance:
1. Edit payload scripts/docs or installer logic in this repo.
2. Keep public command names stable unless adding compatibility wrappers.
3. Update manifest if payload path membership changes.
4. Run non-mutating suite, then mutating suite.
5. Commit in bounded slices.
6. For release candidates, build/sign `.exe` and validate on a clean UE5 repo.

## 11) Quick Usage Examples

Install/update suite into target repo:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 -TargetRepoRoot C:\Path\To\UEProject -RunInit -SkipUnrealSync
```

Run unified Unreal tooling:
```powershell
ue-tools help
ue-tools build -DryRun
```

Run docs tooling:
```powershell
docs-tools help
docs-tools check
docs-tools start --port 3001
```

Run Codex prompt helper:
```powershell
ai-prompt -Task "Investigate UnrealSync regression" -IncludePrivate -CopyToClipboard
```

Run conflict helpers:
```powershell
git conflicts status
git ours "Content/**/*.uasset"
git conflicts continue --skip-editor
```

## 12) Related Docs

- Full build/release guide: `docs/Usage-Build-Release-Guide.md`
- Unification architecture: `docs/Tooling-Unification-Architecture.md`
- Payload script guidance: `payload/Scripts/README.md`

