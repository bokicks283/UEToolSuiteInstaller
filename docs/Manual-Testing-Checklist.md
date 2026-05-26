# UE Tool Suite Manual Testing Checklist

Use this checklist when validating a release candidate or any large refactor of installer/payload behavior.

This checklist is intentionally end-to-end. It covers installer/update flow, command routing, each tool domain, hook behavior, multi-repo shell safety, and packaging track checks.

## 1) Test Scope

Validate all of the following in one run:

- Installer engine (`Install-UEToolSuite.ps1`)
- Payload install/update from `payload/ue-tool-suite.manifest.json`
- Unified dispatcher CLI (`Scripts/ue-tools.ps1`)
- Domain commands:
  - `build`
  - `docs`
  - `ai prompt`
  - `art`
  - `init`
  - `git`
- Git hooks and guarded binary conflict helpers
- PowerShell profile bootstrap behavior for multiple UE repos
- GUI installer packaging path (`Scripts/Publish-InstallerExe.ps1` + `src/UEToolSuiteInstaller.Gui/`)

## 2) Preconditions

Run these checks first.

- [ ] `git --version` succeeds.
- [ ] `git lfs version` succeeds.
- [ ] `pwsh --version` is 7+.
- [ ] Unreal Engine 5.x is installed and discoverable by at least one supported mechanism.
- [ ] Node.js 20+ and npm are installed if validating docs workflow (`ue-tools docs ...`).
- [ ] Working tree for this installer repo is clean before mutating validations:
  - `git status --short` returns no tracked changes.
- [ ] You can create temporary folders outside the installer repo for scratch UE repos.

## 3) Test Environment Matrix

Prepare at least these environments:

- [ ] **Env A: Fresh target repo** (never had this suite installed).
- [ ] **Env B: Upgrade target repo** (contains an older suite layout or legacy files).
- [ ] **Env C: Second target repo** (for multi-repo alias conflict checks).

Recommended structure:

```text
C:\Temp\UEToolSuiteManual\
  FreshRepo\
  UpgradeRepo\
  SecondRepo\
```

Each target repo should contain:

- a git repository with at least one commit
- one `.uproject` file at repo root or a known path for `-TargetUProjectPath`

## 4) Installer Validation

### 4.1 Fresh install (Env A)

- [ ] Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install-UEToolSuite.ps1 `
  -TargetRepoRoot C:\Temp\UEToolSuiteManual\FreshRepo `
  -RunInit `
  -SkipUnrealSync
```

- [ ] Confirm installer exits with success.
- [ ] Confirm managed payload paths exist in Env A:
  - `.githooks\`
  - `Scripts\ue-tools.ps1`
  - `Scripts\Init-Repo.Runtime.ps1`
  - `Scripts\UETools\`
  - `Scripts\git-hooks\`
  - `Scripts\git-tools\`
  - `Scripts\Unreal\ProjectContext.ps1`
  - `Scripts\Unreal\UnrealSync.Runtime.ps1`
- [ ] Confirm `.gitattributes` and `.gitignore` contain managed marker blocks and preserve any pre-existing non-managed content.
- [ ] Confirm backup folder exists when managed files were replaced:
  - `.ue-tools-installer-backups\<timestamp>\...`

### 4.2 Update install (Env B)

- [ ] Seed Env B with older/legacy suite files (or install a prior tag first).
- [ ] Run installer update with `-RunInit` and `-SkipUnrealSync`.
- [ ] Confirm update succeeds without deleting target-only files under managed directories.
- [ ] Confirm legacy cleanup paths are removed only when cleanup is enabled.
- [ ] Confirm replaced files are backed up.

### 4.3 Installer switches

- [ ] Validate `-NoBackup` (no backup folder written for replaced managed content).
- [ ] Validate `-NoLegacyCleanup` (legacy paths remain after update).
- [ ] Validate `-SkipDocs` (docs payload excluded, base payload still installed).
- [ ] Validate `-SkipWebsite` (website excluded, docs tooling still usable when expected).
- [ ] Validate `-SkipTests` (payload test scripts excluded).
- [ ] Validate `-SkipAITools`, `-SkipArtSourceTools`, `-SkipCodingStandardsTools` category handling against manifest expectations.

## 5) Unified CLI and Alias Contract

Run these in an initialized target repo shell (Env A).

- [ ] `ue-tools help` succeeds and shows root + domain commands.
- [ ] `ue help` succeeds and matches dispatcher help behavior.
- [ ] `ue-tools help build`, `ue-tools help docs`, `ue-tools help ai`, `ue-tools help art`, `ue-tools help init`, `ue-tools help git` each return domain help.
- [ ] Invalid command fails with clear guidance:
  - `ue-tools does-not-exist`
- [ ] Option-first compatibility behavior routes to build:
  - `ue-tools -DryRun`

### 5.1 Profile/bootstrap behavior

- [ ] Verify profile contains exactly one managed block:
  - `# >>> ue project shell aliases >>>`
  - `# <<< ue project shell aliases <<<`
- [ ] Verify bootstrap file exists:
  - `%LOCALAPPDATA%\UEToolSuite\Shell\UEToolsBootstrap.ps1`
- [ ] Verify profile block uses lazy load wrappers (`Initialize-UEToolsShell` / `Invoke-UEToolsLazyShellCommand`) and does not eagerly dot-source bootstrap on shell startup.
- [ ] Open a new shell and confirm `ue-tools` and `ue` resolve.

## 6) Domain Functionality Validation

Run from Env A repo root.

### 6.1 Unreal domain (`ue-tools build`)

- [ ] Dry run succeeds:
  - `ue-tools build -DryRun`
- [ ] `-NoBuild -NoRegen` path succeeds without build/regeneration attempt.
- [ ] `-CleanGenerated -NoBuild -NoRegen` cleans generated folders only.
- [ ] Hook-oriented params parse correctly:
  - `ue-tools build -OldRev <sha> -NewRev <sha> -Flag 1 -NonInteractive -DryRun`
- [ ] Missing/invalid options fail with clear errors.

### 6.2 Docs domain (`ue-tools docs`)

- [ ] `ue-tools docs help` prints docs command list.
- [ ] Section scaffold:
  - `ue-tools docs new-section <SectionName>`
- [ ] Page scaffold:
  - `ue-tools docs new-page <SectionName> <PageName> -Title "<Title>"`
- [ ] Reorder command updates sidebar position:
  - `ue-tools docs reorder <ItemSlug> <Position>`
- [ ] Prereq check:
  - `ue-tools docs doctor`
- [ ] Production check:
  - `ue-tools docs check`
- [ ] Server lifecycle:
  - `ue-tools docs start --background --port 3001`
  - `ue-tools docs status`
  - `ue-tools docs stop`
- [ ] Optional bridge install path:
  - `ue-tools docs install-bridge`

### 6.3 AI domain (`ue-tools ai prompt`)

- [ ] Baseline prompt generation:
  - `ue-tools ai prompt`
- [ ] Task injection:
  - `ue-tools ai prompt -Task "Investigate Unreal sync build regression"`
- [ ] Private context behavior:
  1. Create `.ai-local/Private-Context.md` in Env A.
  2. Run `ue-tools ai prompt -IncludePrivate`.
  3. Confirm output references private context usage line.
- [ ] Clipboard flow:
  - `ue-tools ai prompt -CopyToClipboard`

### 6.4 Art domain (`ue-tools art`)

- [ ] Run `ue-tools art` and verify canonical `ArtSource/_Template` normalization.
- [ ] Create one new art item via interactive flow.
- [ ] Verify created folder includes expected template subfolders:
  - `Source`
  - `Textures`
  - `Exports`
- [ ] Verify duplicate/reserved name guards block invalid folder names.

### 6.5 Init domain (`ue-tools init`)

- [ ] Run:
  - `ue-tools init -SkipUnrealSync`
- [ ] Confirm success summary prints readiness entries for optional tools.
- [ ] Validate docs setup controls:
  - `-SkipDocsSetup`
  - `-SkipDocsNpmInstall`
  - `-ForceDocsNpmInstall`
  - `-SkipDocsBridgeInstall`
- [ ] Validate `-SkipOptionalToolSetup` skips optional setup while leaving core init behavior intact.

### 6.6 Git domain (`ue-tools git`)

- [ ] `ue-tools git help` prints command help.
- [ ] `ue-tools git status` returns current guard status.
- [ ] `ue-tools git sync` completes without error.
- [ ] `ue-tools git ours "<pattern>"` and `ue-tools git theirs "<pattern>"` parse and route correctly.
- [ ] `ue-tools git continue --skip-editor`, `abort`, and `restart` show expected behavior/messages for current repo state.

### 6.7 Git aliases

- [ ] Confirm aliases are installed:
  - `git config --get alias.ours`
  - `git config --get alias.theirs`
  - `git config --get alias.conflicts`
- [ ] Confirm `git ours`, `git theirs`, and `git conflicts status` route through dispatcher behavior.

## 7) Hook Validation

- [ ] Enable hooks and verify `core.hooksPath`:
  - `Scripts\git-hooks\Enable-GitHooks.ps1`
  - `git config --get core.hooksPath`
- [ ] Run hook plumbing test script:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-hooks/Test-Hooks.ps1`
- [ ] Perform one branch/checkout scenario with a C++ structural change and confirm expected `ue-sync` action plan behavior.

## 8) Multi-Repo Coexistence Validation

Use Env A and Env C.

- [ ] Install/init suite in Env C.
- [ ] In shell from Env A, run `ue-tools help` and confirm it targets Env A.
- [ ] In shell from Env C, run `ue-tools help` and confirm it targets Env C.
- [ ] Re-run installer/init in one repo and confirm profile still has only one managed alias block.
- [ ] Confirm no per-repo duplicate profile snippets are appended.

## 9) Packaging-Track Validation

- [ ] Build installer exe locally:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Scripts\Publish-InstallerExe.ps1 -Version 0.1.0-manual
```

- [ ] Confirm output exists:
  - `dist\UEToolSuiteInstaller-0.1.0-manual-win-x64.exe`
- [ ] Launch built exe and run a smoke install into a scratch target repo.
- [ ] Confirm GUI flow executes the same installer behavior as CLI (managed paths + logs + backups).

## 10) Automated Gate Checklist (Run After Manual)

Run non-mutating first, then mutating.

The mutating suite performs merge/rebase-style operations inside installer-managed fixture repos, so run it only after non-mutating gates are green.

- [ ] Non-mutating suite:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Tests\Run-UEToolSuiteTests.ps1 -FailFast
```

- [ ] Mutating/exclusive suite:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& '.\Tests\Run-UEToolSuiteTests.ps1' -IncludeExclusive -Name @('ue-sync-automated','binary-guard-fixes') -FailFast"
```

- [ ] Review result directories for failed assertions:
  - `Tests\UEToolSuiteResults\`
  - `Tests\Test-Install-UEToolSuiteResults\`
  - `Tests\Test-UpgradeCompatibilityResults\`
  - `payload\Scripts\Tests\*Results\` (inside installed fixture repos)

## 11) Exit Criteria

Do not ship until all are true:

- [ ] Fresh install, upgrade, and multi-repo coexistence checks pass.
- [ ] All dispatcher commands and domain flows above pass.
- [ ] Hook + git conflict workflows pass.
- [ ] Manual packaging smoke check passes.
- [ ] Non-mutating and mutating automated suites pass.
- [ ] Any regression found during checklist run has a linked fix commit and revalidation evidence.
