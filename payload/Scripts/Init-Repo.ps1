# Scripts/Init-Repo.ps1
# PowerShell 7+ repo bootstrap for an Unreal Engine project repository.
# Usage (from anywhere inside the repo):
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1
#
# Optional:
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -RepoRoot C:\Path\To\UEProject
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -SkipUnrealSync
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -NoBuild
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -SkipLfsPull
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -SkipShellAliases
#   pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/Init-Repo.ps1 -SkipOptionalToolSetup

[CmdletBinding()]
param(
  [switch]$SkipLfsPull,
  [switch]$SkipUnrealSync,
  [switch]$SkipShellAliases,
  [switch]$SkipOptionalToolSetup,
  [switch]$SkipDocsSetup,
  [switch]$SkipDocsNpmInstall,
  [switch]$ForceDocsNpmInstall,
  [switch]$SkipDocsBridgeInstall,
  [switch]$NoBuild,
  [switch]$NoRegen,
  [string]$RepoRoot,
  [string]$UProjectPath,
  [string]$WorkspacePath,

  [ValidateSet("Development", "Debug")]
  [string]$Config = "Development",

  [ValidateSet("Win64")]
  [string]$Platform = "Win64"
)

$ErrorActionPreference = "Stop"

$runtimeHelperPath = Join-Path $PSScriptRoot "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  function Get-UEToolSuiteCoreModuleEntryPathFromScriptsRoot {
    param([Parameter(Mandatory)][string]$ScriptsRoot)

    $manifestPath = Join-Path $ScriptsRoot "UETools\UETools.psd1"
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
      return $manifestPath
    }

    $modulePath = Join-Path $ScriptsRoot "UETools\UEToolSuite.Core.psm1"
    if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
      return $modulePath
    }

    return $null
  }

  function Import-UEToolSuiteCoreModuleFromScriptsRoot {
    param(
      [Parameter(Mandatory)][string]$ScriptsRoot,
      [Parameter(Mandatory)][string]$StateKey
    )

    $modulePath = Get-UEToolSuiteCoreModuleEntryPathFromScriptsRoot -ScriptsRoot $ScriptsRoot
    if ([string]::IsNullOrWhiteSpace($modulePath)) {
      return $false
    }

    Import-Module -Name $modulePath -Force
    return $true
  }
}

function Import-UEToolSuiteCoreModule {
  return (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $PSScriptRoot -StateKey "init-repo")
}

function Info($m) { Write-Host "[Init] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[Init] $m" -ForegroundColor Yellow }
function Err ($m) { Write-Host "[Init] $m" -ForegroundColor Red }
function Ok  ($m) { Write-Host "[Init] $m" -ForegroundColor Green }

$script:ToolReadiness = New-Object System.Collections.Generic.List[object]

function Add-ToolReadiness {
  param(
    [Parameter(Mandatory)][string]$Tool,
    [Parameter(Mandatory)][ValidateSet("OK", "WARN", "SKIP")][string]$Status,
    [Parameter(Mandatory)][string]$Detail
  )

  [void]$script:ToolReadiness.Add([pscustomobject]@{
      Tool = $Tool
      Status = $Status
      Detail = $Detail
    })
}

function Test-CommandAvailable {
  param([Parameter(Mandatory)][string]$Name)
  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function Assert-CommandAvailable {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$InstallHint
  )

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    throw "$Name not found. $InstallHint"
  }

  return $command
}

function Assert-NodeVersion {
  $nodeVersion = ((& node --version 2>$null) | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($nodeVersion)) {
    throw "node --version failed. Install Node.js 20+ and try again."
  }

  $versionText = $nodeVersion.Trim()
  if ($versionText -notmatch '^v?(?<major>\d+)') {
    throw "Could not parse Node.js version '$versionText'. Install Node.js 20+ and try again."
  }

  $major = [int]$Matches.major
  if ($major -lt 20) {
    throw "Node.js 20+ is required for docs tooling. Current: $versionText"
  }

  return $versionText
}

function Invoke-CheckedTool {
  param(
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory
  )

  $oldLocation = (Get-Location).Path
  try {
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      Set-Location -LiteralPath $WorkingDirectory
    }

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Description failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Set-Location -LiteralPath $oldLocation
  }
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $runtimeWriter = Get-Command -Name "Write-UEToolSuiteRuntimeUtf8NoBomFile" -ErrorAction SilentlyContinue
  if ($runtimeWriter) {
    Write-UEToolSuiteRuntimeUtf8NoBomFile -ScriptsRoot $PSScriptRoot -Path $Path -Content $Content
    return
  }

  if (Import-UEToolSuiteCoreModule) {
    $writer = Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue
    if ($writer) {
      Write-UEToolSuiteUtf8NoBomFile -Path $Path -Content $Content
      return
    }
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-GitHubRepoSlugFromRemoteUrl {
  param([string]$RemoteUrl)

  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
    return $null
  }

  $trimmed = $RemoteUrl.Trim()
  if ($trimmed -match 'github\.com[:/](?<slug>[^/\s]+/[^/\s]+?)(?:\.git)?$') {
    return $Matches.slug
  }

  return $null
}

function ConvertTo-TypeScriptSingleQuotedString {
  param([Parameter(Mandatory)][string]$Value)

  return "'" + (($Value -replace "\\", "\\") -replace "'", "\'") + "'"
}

function Set-TypeScriptStringProperty {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$PropertyName,
    [Parameter(Mandatory)][string]$Value
  )

  $quotedValue = ConvertTo-TypeScriptSingleQuotedString -Value $Value
  $pattern = "(?m)^(\s*" + [regex]::Escape($PropertyName) + "\s*:\s*)(['""]).*?\2(,?\s*)$"
  if (-not [regex]::IsMatch($Text, $pattern)) {
    return $Text
  }

  return [regex]::Replace(
    $Text,
    $pattern,
    [System.Text.RegularExpressions.MatchEvaluator] {
      param($match)
      return $match.Groups[1].Value + $quotedValue + $match.Groups[3].Value
    },
    1
  )
}

function Update-DocusaurusGitHubMetadata {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [AllowNull()][string]$RepoSlug
  )

  $configPath = Join-Path $ResolvedRepoRoot "website\docusaurus.config.ts"
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Add-ToolReadiness -Tool "docs site metadata" -Status "SKIP" -Detail "website/docusaurus.config.ts is not installed."
    return
  }

  if ([string]::IsNullOrWhiteSpace($RepoSlug) -or $RepoSlug -notmatch '^(?<owner>[^/]+)/(?<name>[^/]+)$') {
    Add-ToolReadiness -Tool "docs site metadata" -Status "SKIP" -Detail "origin does not point to a GitHub owner/repo slug."
    return
  }

  $owner = $Matches.owner
  $repoName = $Matches.name
  $configText = Get-Content -LiteralPath $configPath -Raw
  $updatedText = Set-TypeScriptStringProperty -Text $configText -PropertyName "organizationName" -Value $owner
  $updatedText = Set-TypeScriptStringProperty -Text $updatedText -PropertyName "projectName" -Value $repoName

  if ($updatedText -eq $configText) {
    Add-ToolReadiness -Tool "docs site metadata" -Status "WARN" -Detail "Could not find organizationName/projectName in website/docusaurus.config.ts."
    return
  }

  Write-Utf8NoBomFile -Path $configPath -Content $updatedText
  Add-ToolReadiness -Tool "docs site metadata" -Status "OK" -Detail "Set Docusaurus GitHub owner/repo metadata to $owner/$repoName."
}

function Resolve-InitRepoRoot {
  param([string]$ExplicitRepoRoot)

  $runtimeResolver = Get-Command -Name "Resolve-UEToolSuiteRuntimeRepoRoot" -ErrorAction SilentlyContinue
  if ($runtimeResolver) {
    if ([string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
      return (Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $PSScriptRoot -InvocationName "Init-Repo")
    }

    $candidate = Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $PSScriptRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "Init-Repo" -AllowFilePath
    $gitRootFromCandidate = ((git -C $candidate rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($gitRootFromCandidate)) {
      throw "RepoRoot is not inside a git repository: $candidate"
    }

    return $gitRootFromCandidate.Trim()
  }

  if (Import-UEToolSuiteCoreModule) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoRoot" -ErrorAction SilentlyContinue
    if ($resolver) {
      if ([string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
        return (Resolve-UEToolSuiteRepoRoot -InvocationName "Init-Repo")
      }

      $candidate = Resolve-UEToolSuiteRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "Init-Repo"
      $gitRootFromCandidate = ((git -C $candidate rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
      if ([string]::IsNullOrWhiteSpace($gitRootFromCandidate)) {
        throw "RepoRoot is not inside a git repository: $candidate"
      }

      return $gitRootFromCandidate.Trim()
    }
  }

  if ([string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    $gitRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($gitRoot)) {
      throw "Not inside a git repository (git rev-parse failed). Pass -RepoRoot when running from outside the repo."
    }

    return $gitRoot.Trim()
  }

  $candidate = [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
  if (-not (Test-Path -LiteralPath $candidate)) {
    throw "RepoRoot does not exist: $candidate"
  }

  $gitRootFromCandidate = ((git -C $candidate rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($gitRootFromCandidate)) {
    throw "RepoRoot is not inside a git repository: $candidate"
  }

  return $gitRootFromCandidate.Trim()
}

function Initialize-DocsTooling {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [switch]$SkipAll,
    [switch]$SkipDocs,
    [switch]$SkipNpmInstall,
    [switch]$ForceNpmInstall,
    [switch]$SkipBridgeInstall
  )

  $docsToolsScript = Join-Path $ResolvedRepoRoot "Scripts\Docs\DocsTools.ps1"
  if (-not (Test-Path -LiteralPath $docsToolsScript)) {
    Add-ToolReadiness -Tool "docs-tools" -Status "SKIP" -Detail "Scripts\Docs\DocsTools.ps1 is not installed in this repo."
    return
  }

  $websiteRoot = Join-Path $ResolvedRepoRoot "website"
  $websitePackagePath = Join-Path $websiteRoot "package.json"
  if (-not (Test-Path -LiteralPath $websitePackagePath)) {
    Add-ToolReadiness -Tool "docs-tools" -Status "SKIP" -Detail "No website/package.json found; docs site setup is not applicable."
    return
  }

  if ($SkipAll -or $SkipDocs) {
    Warn "Skipping docs tooling prerequisite setup."
    Add-ToolReadiness -Tool "docs-tools" -Status "SKIP" -Detail "Docs tooling prerequisite setup skipped by parameter."
    return
  }

  Info "Preparing docs tooling prerequisites..."
  $null = Assert-CommandAvailable -Name "node" -InstallHint "Install Node.js 20+ and rerun Init-Repo."
  $null = Assert-CommandAvailable -Name "npm" -InstallHint "Install npm and rerun Init-Repo."
  $nodeVersion = Assert-NodeVersion
  Add-ToolReadiness -Tool "node/npm" -Status "OK" -Detail "Node.js $nodeVersion and npm are available."

  $nodeModulesPath = Join-Path $websiteRoot "node_modules"
  if ($SkipNpmInstall) {
    Warn "Skipping docs npm install (SkipDocsNpmInstall set)."
    Add-ToolReadiness -Tool "docs dependencies" -Status "SKIP" -Detail "website/node_modules setup skipped by parameter."
  }
  elseif ($ForceNpmInstall -or -not (Test-Path -LiteralPath $nodeModulesPath)) {
    Info "Installing docs site dependencies with npm install..."
    Invoke-CheckedTool `
      -Description "npm install for docs site" `
      -FilePath "npm" `
      -Arguments @("install") `
      -WorkingDirectory $websiteRoot
    Add-ToolReadiness -Tool "docs dependencies" -Status "OK" -Detail "npm install completed in website/."
  }
  else {
    Add-ToolReadiness -Tool "docs dependencies" -Status "OK" -Detail "website/node_modules already exists."
  }

  if ($SkipBridgeInstall) {
    Warn "Skipping docs VS Code bridge install (SkipDocsBridgeInstall set)."
    Add-ToolReadiness -Tool "docs VS Code bridge" -Status "SKIP" -Detail "Bridge install skipped by parameter."
  }
  elseif (Test-CommandAvailable -Name "code") {
    Info "Installing optional docs VS Code bridge..."
    Invoke-CheckedTool `
      -Description "docs-tools install-bridge" `
      -FilePath "pwsh" `
      -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $docsToolsScript, "-RepoRoot", $ResolvedRepoRoot, "install-bridge")
    Add-ToolReadiness -Tool "docs VS Code bridge" -Status "OK" -Detail "VS Code bridge installed. Reload VS Code windows to activate it."
  }
  else {
    Warn "Skipping docs VS Code bridge install because the 'code' CLI is not available."
    Add-ToolReadiness -Tool "docs VS Code bridge" -Status "WARN" -Detail "Install or expose the VS Code 'code' CLI, then run: docs-tools install-bridge"
  }

  Info "Running docs-tools doctor..."
  Invoke-CheckedTool `
    -Description "docs-tools doctor" `
    -FilePath "pwsh" `
    -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $docsToolsScript, "-RepoRoot", $ResolvedRepoRoot, "doctor")
  Add-ToolReadiness -Tool "docs-tools" -Status "OK" -Detail "docs-tools doctor completed."
}

function Test-ArtSourceTemplateReady {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $artToolScript = Join-Path $ResolvedRepoRoot "Scripts\Unreal\New-ArtSourcePath.ps1"
  if (-not (Test-Path -LiteralPath $artToolScript)) {
    Add-ToolReadiness -Tool "art-tools" -Status "SKIP" -Detail "ArtSource helper is not installed in this repo."
    return
  }

  $artSourceRoot = Join-Path $ResolvedRepoRoot "ArtSource"
  if (-not (Test-Path -LiteralPath $artSourceRoot -PathType Container)) {
    Add-ToolReadiness -Tool "art-tools" -Status "SKIP" -Detail "No ArtSource folder found; art tooling is not applicable yet."
    return
  }

  $missing = @()
  foreach ($relativePath in @("_Template", "_Template\Source", "_Template\Textures", "_Template\Exports")) {
    $candidate = Join-Path $artSourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
      $missing += (Join-Path "ArtSource" $relativePath)
    }
  }

  if ($missing.Count -gt 0) {
    Add-ToolReadiness -Tool "art-tools" -Status "WARN" -Detail "Missing template folder(s): $($missing -join ', '). Run art-tools once after restoring the template."
    return
  }

  Add-ToolReadiness -Tool "art-tools" -Status "OK" -Detail "ArtSource/_Template contains Source, Textures, and Exports."
}

function Show-ToolReadinessSummary {
  if ($script:ToolReadiness.Count -eq 0) {
    return
  }

  Info "Tool readiness summary:"
  $entries = $script:ToolReadiness.ToArray()
  foreach ($entry in $entries) {
    $color = [ConsoleColor]::Gray
    if ($entry.Status -eq "OK") {
      $color = [ConsoleColor]::Green
    }
    elseif ($entry.Status -eq "WARN") {
      $color = [ConsoleColor]::Yellow
    }
    elseif ($entry.Status -eq "SKIP") {
      $color = [ConsoleColor]::DarkYellow
    }

    Write-Host ("  [{0}] {1}: {2}" -f $entry.Status, $entry.Tool, $entry.Detail) -ForegroundColor $color
  }
}

# --- Require PowerShell 7+ ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "PowerShell 7+ is required. Current: $($PSVersionTable.PSVersion)"
}

# --- Optional: ensure ANSI is not downgraded in nested calls ---
# This helps if a user has changed OutputRendering elsewhere.
try { $PSStyle.OutputRendering = 'Host' } catch { }

# --- Require git ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git not found. Install Git for Windows and try again."
}

# --- Find repo root and move there ---
$repoRoot = Resolve-InitRepoRoot -ExplicitRepoRoot $RepoRoot

Set-Location $repoRoot
Info "Repo root: $repoRoot"

$projectContextHelpers = Join-Path $repoRoot "Scripts\Unreal\ProjectContext.ps1"
if (-not (Test-Path -LiteralPath $projectContextHelpers)) {
  throw "Project context helpers not found: $projectContextHelpers"
}
. $projectContextHelpers

$projectContext = Get-ProjectContext -RepoRoot $repoRoot -UProjectPath $UProjectPath -WorkspacePath $WorkspacePath
Info "Project: $($projectContext.ProjectName)"
Info "Primary module: $($projectContext.PrimaryModuleName)"

$leaf = Split-Path $repoRoot -Leaf
if ($leaf -ne $projectContext.ProjectName) {
  Warn "Repo folder name '$leaf' differs from project name '$($projectContext.ProjectName)'."
  Warn "This is allowed, but keep generated workspace/tooling paths aligned with the current repo root."
}

# --- Ensure Git LFS is available and initialized ---
if (-not (Get-Command git-lfs -ErrorAction SilentlyContinue)) {
  throw "git-lfs not found. Install Git LFS and try again."
}

# IMPORTANT:
# - We do NOT want git lfs to attempt to install hook files into the repo because we commit our own hooks.
# - --skip-repo installs/configures LFS filters but skips repo hook installation.  (see git-lfs-install(1))
Info "Initializing Git LFS filters for this repo (skipping repo hook install)..."
& git lfs install --local --skip-repo
if ($LASTEXITCODE -ne 0) { throw "git lfs install failed (exit $LASTEXITCODE)." }
Add-ToolReadiness -Tool "git-lfs" -Status "OK" -Detail "LFS filters initialized for this repo."

if (-not $SkipLfsPull) {
  Info "Pulling LFS content (this may take a while on first run)..."
  & git lfs pull
  if ($LASTEXITCODE -ne 0) { throw "git lfs pull failed (exit $LASTEXITCODE)." }
  Add-ToolReadiness -Tool "git-lfs content" -Status "OK" -Detail "git lfs pull completed."
}
else {
  Warn "Skipping 'git lfs pull' (SkipLfsPull set)."
  Add-ToolReadiness -Tool "git-lfs content" -Status "SKIP" -Detail "git lfs pull skipped by parameter."
}

# --- Configure recommended repo-local git settings ---
Info "Applying recommended repo-local git config..."
& git config --local core.hooksPath .githooks
& git config --local fetch.prune true
& git config --local pull.ff only
& git config --local core.autocrlf input
& git config --local core.eol lf
& git config --local core.safecrlf warn
& git config --local advice.mergeConflict false

Ok "Git config applied:"
& git config --local --get core.hooksPath | ForEach-Object { Write-Host "  core.hooksPath=$_" }
& git config --local --get pull.ff        | ForEach-Object { Write-Host "  pull.ff=$_" }
& git config --local --get fetch.prune    | ForEach-Object { Write-Host "  fetch.prune=$_" }
& git config --local --get core.autocrlf  | ForEach-Object { Write-Host "  core.autocrlf=$_" }
& git config --local --get core.eol       | ForEach-Object { Write-Host "  core.eol=$_" }
& git config --local --get core.safecrlf  | ForEach-Object { Write-Host "  core.safecrlf=$_" }
& git config --local --get advice.mergeConflict | ForEach-Object { Write-Host "  advice.mergeConflict=$_" }
Add-ToolReadiness -Tool "git config" -Status "OK" -Detail "Hooks path, pull, LFS-safe line ending, and conflict advice settings applied."

$originUrl = ((git remote get-url origin 2>$null) | Select-Object -First 1)
$repoSlug = Get-GitHubRepoSlugFromRemoteUrl -RemoteUrl $originUrl

if (Get-Command gh -ErrorAction SilentlyContinue) {
  if (-not [string]::IsNullOrWhiteSpace($repoSlug)) {
    Info "Configuring GitHub CLI (gh) defaults for this repo (best-effort)..."
    & gh repo set-default $repoSlug
    if ($LASTEXITCODE -eq 0) {
      Add-ToolReadiness -Tool "gh" -Status "OK" -Detail "Default GitHub repo set to $repoSlug."
    }
    else {
      Add-ToolReadiness -Tool "gh" -Status "WARN" -Detail "gh repo set-default failed for $repoSlug."
    }
  }
  else {
    Warn "Skipping GitHub CLI default repo setup because origin does not point to a GitHub repo."
    Add-ToolReadiness -Tool "gh" -Status "SKIP" -Detail "origin does not point to a GitHub repo."
  }
}
else {
  Add-ToolReadiness -Tool "gh" -Status "SKIP" -Detail "GitHub CLI is not installed."
}

Update-DocusaurusGitHubMetadata -ResolvedRepoRoot $repoRoot -RepoSlug $repoSlug

# --- Ensure hook scripts exist ---
$requiredHooks = @(
  ".githooks\pre-commit",
  ".githooks\pre-push",
  ".githooks\post-checkout",
  ".githooks\post-merge",
  ".githooks\post-commit",
  ".githooks\post-rewrite"
)

$requiredShared = @(
  "Scripts\git-hooks\colors.sh",
  "Scripts\git-hooks\hook-common.sh"
)

$requiredHelpers = @(
  "Scripts\git-tools\conflicts.ps1",
  "Scripts\git-tools\GitConflictHelpers.ps1",
  "Scripts\Unreal\ProjectContext.ps1",
  "Scripts\Unreal\ProjectShellAliases.ps1"
)

$requiredTests = @(
  "Scripts\git-hooks\Test-Hooks.ps1"
)

$missing = @()
foreach ($p in @($requiredHooks + $requiredShared + $requiredHelpers + $requiredTests)) {
  if (-not (Test-Path (Join-Path $repoRoot $p))) { $missing += $p }
}

if ($missing.Count -gt 0) {
  Err "Missing required file(s):"
  $missing | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  throw "Required files are missing. Pull latest changes and re-run Init-Repo."
}

$projectAliasHelpers = Join-Path $repoRoot "Scripts\Unreal\ProjectShellAliases.ps1"
. $projectAliasHelpers

# --- Mark hook scripts and shared sh scripts executable in the index (best-effort) ---
Info "Ensuring hooks + shared hook scripts are marked executable in git index..."
$chmodPaths = @(
  ".githooks/pre-commit",
  ".githooks/pre-push",
  ".githooks/post-checkout",
  ".githooks/post-merge",
  ".githooks/post-commit",
  ".githooks/post-rewrite",
  "Scripts/git-hooks/colors.sh",
  "Scripts/git-hooks/hook-common.sh"
)

foreach ($p in $chmodPaths) {
  & git update-index --chmod=+x -- $p 2>$null | Out-Null
}
Ok "Exec bits updated (best-effort)."
Add-ToolReadiness -Tool "hook scripts" -Status "OK" -Detail "Hook and shared shell scripts are marked executable in the git index where applicable."

# --- Run hook enable script (idempotent) ---
$enableHooks = Join-Path $repoRoot "Scripts\git-hooks\Enable-GitHooks.ps1"
if (Test-Path $enableHooks) {
  Info "Running Enable-GitHooks.ps1..."
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $enableHooks
  if ($LASTEXITCODE -ne 0) { throw "Enable-GitHooks.ps1 failed (exit $LASTEXITCODE)." }
  Add-ToolReadiness -Tool "git hooks" -Status "OK" -Detail "Enable-GitHooks.ps1 completed."
}
else {
  Warn "Enable-GitHooks.ps1 not found at Scripts\git-hooks\Enable-GitHooks.ps1 (skipping)."
  Add-ToolReadiness -Tool "git hooks" -Status "WARN" -Detail "Enable-GitHooks.ps1 was not found."
}

# --- Configure git aliases for conflict helpers ---
Info "Configuring git aliases: ours / theirs / conflicts ..."
& git config --local alias.ours     '!pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-tools/conflicts.ps1 ours'
& git config --local alias.theirs   '!pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-tools/conflicts.ps1 theirs'
& git config --local alias.conflicts '!pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/git-tools/conflicts.ps1'

if ($LASTEXITCODE -ne 0) { throw "Failed to configure conflict helper aliases." }

Ok "Aliases configured:"
& git config --local --get alias.ours      | ForEach-Object { Write-Host "  alias.ours=$_" -ForegroundColor Green }
& git config --local --get alias.theirs    | ForEach-Object { Write-Host "  alias.theirs=$_" -ForegroundColor Green }
& git config --local --get alias.conflicts | ForEach-Object { Write-Host "  alias.conflicts=$_" -ForegroundColor Green }
Write-Host "  usage: git ours <patterns...>" -ForegroundColor Green
Write-Host "  usage: git theirs <patterns...>" -ForegroundColor Green
Write-Host "  usage: git conflicts <status|sync|continue|abort|restart|help>" -ForegroundColor Green
Add-ToolReadiness -Tool "git conflict helpers" -Status "OK" -Detail "git ours/theirs/conflicts aliases configured."

# --- Configure shell aliases for project scripts ---
if ($SkipShellAliases) {
  Warn "Skipping shell alias install (SkipShellAliases set)."
  Add-ToolReadiness -Tool "PowerShell aliases" -Status "SKIP" -Detail "Shell alias install skipped by parameter."
}
else {
  Info "Configuring PowerShell aliases for project script wrappers ..."
  try {
    $aliasInstall = Install-ProjectShellAliases
    Ok "PowerShell aliases installed."
    Write-Host "  profile: $($aliasInstall.ProfilePath)" -ForegroundColor Green

    foreach ($group in @($aliasInstall.AliasGroups)) {
      $aliasList = @($group.Aliases) -join ", "
      Write-Host "  function: $($group.FunctionName)  aliases: $aliasList" -ForegroundColor Green
    }

    Write-Host "  usage: ue-tools help" -ForegroundColor Green
    Write-Host "  usage: ue-tools build -DryRun" -ForegroundColor Green
    Write-Host "  usage: ue-tools build -NoBuild -NoRegen" -ForegroundColor Green
    if ($aliasInstall.Aliases -contains "art-tools") {
      Write-Host "  usage: art-tools --help" -ForegroundColor Green
      Write-Host "  usage: art-tools" -ForegroundColor Green
    }
    if ($aliasInstall.Aliases -contains "docs-tools") {
      Write-Host "  usage: docs-tools help" -ForegroundColor Green
      Write-Host "  usage: docs-tools new-page Workflow Daily-Flow -Title `"Daily Flow`"" -ForegroundColor Green
    }
    if ($aliasInstall.Aliases -contains "codex-tools") {
      Write-Host "  usage: codex-tools help" -ForegroundColor Green
      Write-Host "  usage: codex-prompt -Task `"Fix UnrealSync tests`"" -ForegroundColor Green
    }
    Warn "Open a new PowerShell session (or run: . `"$($aliasInstall.ProfilePath)`") to load aliases."
    Add-ToolReadiness -Tool "PowerShell aliases" -Status "OK" -Detail "Installed aliases: $(@($aliasInstall.Aliases) -join ', ')."
  }
  catch {
    Warn "Could not install PowerShell script aliases."
    Warn $_.Exception.Message
    Add-ToolReadiness -Tool "PowerShell aliases" -Status "WARN" -Detail $_.Exception.Message
  }
}

# --- Hook self-test ---
$hookTest = Join-Path $repoRoot "Scripts\git-hooks\Test-Hooks.ps1"
Info "Running hook self-test..."
& pwsh -NoProfile -ExecutionPolicy Bypass -File $hookTest
if ($LASTEXITCODE -ne 0) { throw "Hook self-test failed (exit $LASTEXITCODE)." }
Ok "Hook self-test completed."
Add-ToolReadiness -Tool "hook self-test" -Status "OK" -Detail "Scripts\git-hooks\Test-Hooks.ps1 completed."

Initialize-DocsTooling `
  -ResolvedRepoRoot $repoRoot `
  -SkipAll:$SkipOptionalToolSetup `
  -SkipDocs:$SkipDocsSetup `
  -SkipNpmInstall:$SkipDocsNpmInstall `
  -ForceNpmInstall:$ForceDocsNpmInstall `
  -SkipBridgeInstall:$SkipDocsBridgeInstall

if ($SkipOptionalToolSetup) {
  Add-ToolReadiness -Tool "art-tools" -Status "SKIP" -Detail "Optional tool setup skipped by parameter."
}
else {
  Test-ArtSourceTemplateReady -ResolvedRepoRoot $repoRoot
}

# --- Optional: run UnrealSync once for first-time setup ---
$unrealSync = Join-Path $repoRoot "Scripts\Unreal\UnrealSync.ps1"
if (-not $SkipUnrealSync -and (Test-Path $unrealSync)) {
  Info "Running UnrealSync for first-time setup..."

  $_args = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $unrealSync,
    "-RepoRoot", $repoRoot,
    "-Force",
    "-Config", $Config,
    "-Platform", $Platform
  )
  if ($NoBuild) { $_args += "-NoBuild" }
  if ($NoRegen) { $_args += "-NoRegen" }
  if (-not [string]::IsNullOrWhiteSpace($UProjectPath)) { $_args += @("-UProjectPath", $UProjectPath) }
  if (-not [string]::IsNullOrWhiteSpace($WorkspacePath)) { $_args += @("-WorkspacePath", $WorkspacePath) }

  & pwsh @_args
  if ($LASTEXITCODE -ne 0) { throw "UnrealSync failed (exit $LASTEXITCODE)." }

  Ok "UnrealSync completed."
  Add-ToolReadiness -Tool "ue-tools" -Status "OK" -Detail "UnrealSync completed for first-time setup."
}
elseif ($SkipUnrealSync) {
  Warn "Skipping UnrealSync (SkipUnrealSync set)."
  Add-ToolReadiness -Tool "ue-tools" -Status "SKIP" -Detail "UnrealSync skipped by parameter."
}
else {
  Warn "UnrealSync script not found at Scripts/Unreal/UnrealSync.ps1 (skipping)."
  Add-ToolReadiness -Tool "ue-tools" -Status "WARN" -Detail "Scripts\Unreal\UnrealSync.ps1 was not found."
}

Ok "Repo initialization complete."
Show-ToolReadinessSummary
Info "Next steps:"
Write-Host "  - Open repo folder in VS Code" -ForegroundColor Cyan
Write-Host "  - Verify hooks by attempting a small commit" -ForegroundColor Cyan
Write-Host "  - During merge/rebase conflicts of binary files, use: git ours / git theirs" -ForegroundColor Cyan
Write-Host "  - Run Unreal tools manually with: ue-tools help" -ForegroundColor Cyan
if (Test-Path -LiteralPath (Join-Path $repoRoot "Scripts\Unreal\New-ArtSourcePath.ps1")) {
  Write-Host "  - Run ArtSource tools manually with: art-tools --help" -ForegroundColor Cyan
}
if (Test-Path -LiteralPath (Join-Path $repoRoot "Scripts\Docs\DocsTools.ps1")) {
  Write-Host "  - Run docs tools manually with: docs-tools help" -ForegroundColor Cyan
}
if (Test-Path -LiteralPath (Join-Path $repoRoot "Scripts\Codex\Get-CodexStartupPrompt.ps1")) {
  Write-Host "  - Build a Codex startup prompt with: codex-prompt -IncludePrivate" -ForegroundColor Cyan
}
