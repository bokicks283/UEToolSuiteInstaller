[CmdletBinding()]
param()

function New-TestManifestEntry {
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
    SupportsNoCleanup   = $SupportsNoCleanup
    SupportsFailFast    = $SupportsFailFast
    ResultDirectory     = $ResultDirectory
  }
}

function Get-ProjectTestManifest {
  [CmdletBinding()]
  param()

  @(
    (New-TestManifestEntry `
      -Id "hooks" `
      -Name "Hook Plumbing" `
      -Path "Scripts/git-hooks/Test-Hooks.ps1" `
      -Category "hooks" `
      -Description "Validates committed hook plumbing, core.hooksPath, and hook-common sourcing.")

    (New-TestManifestEntry `
      -Id "ue-sync-shell-aliases" `
      -Name "UE Sync Shell Aliases" `
      -Path "Scripts/Tests/Test-UESyncShellAliases.ps1" `
      -Category "shell" `
      -Description "Validates ue-tools, optional art-tools, and PowerShell profile bootstrap." `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-UESyncShellAliasesResults")

    (New-TestManifestEntry `
      -Id "docs-tools" `
      -Name "Docs Tools" `
      -Path "Scripts/Tests/Test-DocsTools.ps1" `
      -Category "docs" `
      -Description "Validates docs-tools scaffolding, optional VS Code bridge integration, and docs-site checks." `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-DocsToolsResults")

    (New-TestManifestEntry `
      -Id "codex-startup-prompt" `
      -Name "Codex Startup Prompt" `
      -Path "Scripts/Tests/Test-CodexStartupPrompt.ps1" `
      -Category "codex" `
      -Description "Validates the Codex startup prompt builder output and local private-context handling." `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-CodexStartupPromptResults")

    (New-TestManifestEntry `
      -Id "ue-sync-regeneration" `
      -Name "UE Sync Regeneration" `
      -Path "Scripts/Tests/Test-UnrealSync-Regeneration.ps1" `
      -Category "unreal" `
      -Description "Validates project-file regeneration and engine-resolution fallback paths in isolation." `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-UnrealSync-RegenerationResults")

    (New-TestManifestEntry `
      -Id "init-repo-tool-readiness" `
      -Name "Init Repo Tool Readiness" `
      -Path "Scripts/Tests/Test-InitRepoToolReadiness.ps1" `
      -Category "init" `
      -Description "Validates Init-Repo optional tool prerequisite setup and readiness reporting in a scratch repo." `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-InitRepoToolReadinessResults")

    (New-TestManifestEntry `
      -Id "new-artsource-path" `
      -Name "New ArtSource Path" `
      -Path "Scripts/Tests/Test-New-ArtSourcePath.ps1" `
      -Category "art" `
      -Description "Validates canonical ArtSource/_Template handling and new asset folder creation." `
      -SupportsNoCleanup $true `
      -ResultDirectory "Scripts/Tests/Test-New-ArtSourcePathResults")

    (New-TestManifestEntry `
      -Id "ue-sync-automated" `
      -Name "UE Sync Automated" `
      -Path "Scripts/Tests/Test-UnrealSync.ps1" `
      -Category "unreal" `
      -Description "Validates structural trigger detection and hook/non-interactive behavior on a committed clean repo." `
      -RequiresCleanRepo $true `
      -RequiresCommits $true `
      -MutatesRepo $true `
      -ExclusiveRepoAccess $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-UnrealSyncResults")

    (New-TestManifestEntry `
      -Id "binary-guard-fixes" `
      -Name "Binary Guard Fixes" `
      -Path "Scripts/Tests/Test-BinaryGuard-Fixes.ps1" `
      -Category "binary-guard" `
      -Description "Validates guarded binary conflict helpers across merge and rebase flows." `
      -RequiresCleanRepo $true `
      -RequiresCommits $true `
      -MutatesRepo $true `
      -ExclusiveRepoAccess $true `
      -SupportsNoCleanup $true `
      -SupportsFailFast $true `
      -ResultDirectory "Scripts/Tests/Test-BinaryGuard-FixesResults")
  )
}
