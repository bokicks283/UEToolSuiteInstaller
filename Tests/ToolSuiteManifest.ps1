[CmdletBinding()]
param()

function New-UEToolSuiteTestEntry {
  param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Category,
    [string]$Description = "",
    [bool]$DefaultEnabled = $true,
    [bool]$RequiresCleanRepo = $false,
    [bool]$RequiresCommits = $false,
    [bool]$MutatesRepo = $false,
    [bool]$ExclusiveRepoAccess = $false,
    [bool]$RequiresInstalledFixture = $false,
    [bool]$ScriptInInstallerRoot = $false,
    [bool]$SupportsNoCleanup = $false,
    [bool]$SupportsFailFast = $false,
    [string]$ResultDirectory = ""
  )

  [pscustomobject]@{
    Id                  = $Id
    Name                = $Name
    Path                = $Path
    Category            = $Category
    Description         = $Description
    DefaultEnabled      = $DefaultEnabled
    RequiresCleanRepo   = $RequiresCleanRepo
    RequiresCommits     = $RequiresCommits
    MutatesRepo         = $MutatesRepo
    ExclusiveRepoAccess = $ExclusiveRepoAccess
    RequiresInstalledFixture = $RequiresInstalledFixture
    ScriptInInstallerRoot = $ScriptInInstallerRoot
    SupportsNoCleanup   = $SupportsNoCleanup
    SupportsFailFast    = $SupportsFailFast
    ResultDirectory     = $ResultDirectory
  }
}

function Get-UEToolSuiteTestManifest {
  [CmdletBinding()]
  param()

  @(
    (New-UEToolSuiteTestEntry `
      -Id "installer" `
      -Name "Installer Regression Suite" `
      -Path "Tests/Test-Install-UEToolSuite.ps1" `
      -Category "installer" `
      -Description "Validates fresh install, update, backups, legacy cleanup, and RunInit behavior." `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Tests/Test-Install-UEToolSuiteResults")

    (New-UEToolSuiteTestEntry `
      -Id "upgrade-compatibility" `
      -Name "Upgrade Compatibility" `
      -Path "Tests/Test-UpgradeCompatibility.ps1" `
      -Category "upgrade" `
      -Description "Validates stable direct entrypoints and profile aliases before and after an update without reinstalling shell aliases." `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Tests/Test-UpgradeCompatibilityResults")

    (New-UEToolSuiteTestEntry `
      -Id "hooks" `
      -Name "Hook Plumbing" `
      -Path "Scripts/git-hooks/Test-Hooks.ps1" `
      -Category "hooks" `
      -Description "Validates committed hook plumbing, core.hooksPath, and hook-common sourcing." `
      -RequiresInstalledFixture $true)

    (New-UEToolSuiteTestEntry `
      -Id "shell-aliases" `
      -Name "Shell Alias Compatibility" `
      -Path "Scripts/Tests/Test-UESyncShellAliases.ps1" `
      -Category "shell" `
      -Description "Validates ue-tools, optional art-tools, docs-tools, codex-tools, and profile bootstrap behavior." `
      -RequiresInstalledFixture $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-UESyncShellAliasesResults")

    (New-UEToolSuiteTestEntry `
      -Id "docs-tools" `
      -Name "Docs Tools" `
      -Path "Scripts/Tests/Test-DocsTools.ps1" `
      -Category "docs" `
      -Description "Validates docs-tools scaffolding, optional VS Code bridge integration, and docs-site checks." `
      -RequiresInstalledFixture $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-DocsToolsResults")

    (New-UEToolSuiteTestEntry `
      -Id "codex-startup-prompt" `
      -Name "Codex Startup Prompt" `
      -Path "Scripts/Tests/Test-CodexStartupPrompt.ps1" `
      -Category "codex" `
      -Description "Validates the Codex startup prompt builder output and local private-context handling." `
      -RequiresInstalledFixture $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-CodexStartupPromptResults")

    (New-UEToolSuiteTestEntry `
      -Id "ue-sync-regeneration" `
      -Name "UE Sync Regeneration" `
      -Path "Scripts/Tests/Test-UnrealSync-Regeneration.ps1" `
      -Category "unreal" `
      -Description "Validates project-file regeneration and engine-resolution fallback paths in isolation." `
      -RequiresInstalledFixture $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-UnrealSync-RegenerationResults")

    (New-UEToolSuiteTestEntry `
      -Id "init-repo-tool-readiness" `
      -Name "Init Repo Tool Readiness" `
      -Path "Scripts/Tests/Test-InitRepoToolReadiness.ps1" `
      -Category "init" `
      -Description "Validates Init-Repo optional tool prerequisite setup and readiness reporting in a scratch repo." `
      -RequiresInstalledFixture $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-InitRepoToolReadinessResults")

    (New-UEToolSuiteTestEntry `
      -Id "new-artsource-path" `
      -Name "New ArtSource Path" `
      -Path "Scripts/Tests/Test-New-ArtSourcePath.ps1" `
      -Category "art" `
      -Description "Validates canonical ArtSource/_Template handling and new asset folder creation." `
      -RequiresInstalledFixture $true `
      -SupportsNoCleanup $true `
      -ResultDirectory "Scripts/Tests/Test-New-ArtSourcePathResults")

    (New-UEToolSuiteTestEntry `
      -Id "ue-sync-automated" `
      -Name "UE Sync Automated" `
      -Path "Scripts/Tests/Test-UnrealSync.ps1" `
      -Category "unreal" `
      -Description "Validates structural trigger detection and hook/non-interactive behavior on a committed clean repo." `
      -RequiresInstalledFixture $true `
      -RequiresCleanRepo $true `
      -RequiresCommits $true `
      -MutatesRepo $true `
      -ExclusiveRepoAccess $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-UnrealSyncResults")

    (New-UEToolSuiteTestEntry `
      -Id "binary-guard-fixes" `
      -Name "Binary Guard Fixes" `
      -Path "Scripts/Tests/Test-BinaryGuard-Fixes.ps1" `
      -Category "binary-guard" `
      -Description "Validates guarded binary conflict helpers across merge and rebase flows." `
      -RequiresInstalledFixture $true `
      -RequiresCleanRepo $true `
      -RequiresCommits $true `
      -MutatesRepo $true `
      -ExclusiveRepoAccess $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-BinaryGuard-FixesResults")
  )
}
