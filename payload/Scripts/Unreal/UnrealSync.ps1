[CmdletBinding()]
param(
  # Hook parameters (optional for manual use)
  [string]$OldRev,
  [string]$NewRev,
  [int]$Flag = 1,

  # Manual / control flags
  [switch]$Force,           # Always run regen+build even if no structural triggers detected
  [switch]$CleanGenerated,  # Delete Binaries and Intermediate before selected actions
  [switch]$CleanSaved,      # Delete the Saved directory
  [switch]$CleanCache,      # Delete the DerivedDataCache directory
  [switch]$NoRegen,         # Skip generating project files
  [switch]$NoBuild,         # Skip building
  [switch]$NonInteractive,  # Tells the script to avoid prompting the user
  [switch]$DryRun,          # Validate detection/prompt flow without cleanup/build

  # Optional: explicitly point at a repo root when running from outside the UE project
  [string]$RepoRoot,

  # Optional: explicitly point at a .code-workspace file
  [string]$WorkspacePath,

  # Optional: explicitly point at a .uproject file when the repo has more than one
  [string]$UProjectPath,

  [ValidateSet("Development", "Debug")]
  [string]$Config = "Development",

  [ValidateSet("Win64")]
  [string]$Platform = "Win64"
)

$ErrorActionPreference = "Stop"

$projectContextHelper = Join-Path $PSScriptRoot "ProjectContext.ps1"
if (-not (Test-Path -LiteralPath $projectContextHelper)) {
  throw "Project context helper not found: $projectContextHelper"
}
. $projectContextHelper
$script:UnrealScriptsRoot = Split-Path -Parent $PSScriptRoot
$runtimeHelperPath = Join-Path $script:UnrealScriptsRoot "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  throw "Runtime helper not found: $runtimeHelperPath"
}

function Import-UEToolSuiteCoreModule {
  return (Import-UEToolSuiteCoreModuleFromScriptsRoot -ScriptsRoot $script:UnrealScriptsRoot -StateKey "unreal-sync")
}

function Info($msg) { Write-Host "[UE Sync] $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "[UE Sync] $msg" -ForegroundColor Yellow }
function Err ($msg) { Write-Host "[UE Sync] $msg" -ForegroundColor Red }
function Success($msg) { Write-Host "[UE Sync] $msg" -ForegroundColor Green }

function Test-IsInteractiveConsole {
  try {
    if (-not [Environment]::UserInteractive) { return $false }
    if ($env:CI -or $env:GITHUB_ACTIONS -or $env:TF_BUILD -or $env:JENKINS_URL) { return $false }
    if ($Host.Name -eq "ServerRemoteHost") { return $false }

    # Preferred signal: real console host with usable RawUI and non-redirected input.
    if ($Host.UI -and $Host.UI.RawUI -and -not [Console]::IsInputRedirected) {
      return $true
    }

    # Fallback for hook contexts launched from an interactive shell (TTY can be hidden).
    if ($env:TERM -and $env:TERM -ne "dumb") { return $true }

    return $false
  }
  catch { return $false }
}

function Test-CanPrompt {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteUnrealCanPrompt" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteUnrealCanPrompt)
  }

  try {
    if (-not [Environment]::UserInteractive) { return $false }
    if (-not $Host.UI -or -not $Host.UI.RawUI) { return $false }
    if ([Console]::IsInputRedirected) { return $false }
    if ([Console]::IsOutputRedirected) { return $false }
    return $true
  }
  catch { return $false }
}

function Test-EnvTrue {
  param([string]$Value)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteUnrealEnvTrue" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteUnrealEnvTrue -Value $Value)
  }

  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  switch ($Value.Trim().ToLowerInvariant()) {
    "1" { return $true }
    "true" { return $true }
    "yes" { return $true }
    default { return $false }
  }
}

function Get-UProjectRootFromLocation {
  $candidate = (Get-Location).Path
  while (-not [string]::IsNullOrWhiteSpace($candidate)) {
    $uprojects = @(
      Get-ChildItem -LiteralPath $candidate -Filter "*.uproject" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    )
    if ($uprojects.Count -gt 0) {
      return $candidate
    }

    $parent = Split-Path -Path $candidate -Parent
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
      break
    }

    $candidate = $parent
  }

  return $null
}

function Resolve-UnrealSyncRoot {
  param([string]$ExplicitRepoRoot)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    return (Resolve-RepoRootOrThrow -RepoRoot $ExplicitRepoRoot)
  }

  $gitRoot = Get-RepoRootFromGit
  if (-not [string]::IsNullOrWhiteSpace($gitRoot)) {
    return $gitRoot
  }

  $uprojectRoot = Get-UProjectRootFromLocation
  if (-not [string]::IsNullOrWhiteSpace($uprojectRoot)) {
    return $uprojectRoot
  }

  throw "Could not resolve project root. Run from inside a git repository or UE project directory, or pass -RepoRoot."
}


function Remove-IfExists {
  param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$NonInteractive,
    [int]$MaxAutoRetries = 2
  )

  if (-not (Test-Path $Path)) { return $true }

  $attempt = 0
  while ($true) {
    try {
      # Some hosts leave stale progress rows after large recursive deletes.
      # Suppress progress for cleanup to keep hook/manual output stable.
      $oldProgressPreference = $ProgressPreference
      try {
        $ProgressPreference = "SilentlyContinue"
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      }
      finally {
        $ProgressPreference = $oldProgressPreference
      }
      return $true
    }
    catch {
      $attempt++
      $errMsg = $_.Exception.Message

      if ($attempt -le $MaxAutoRetries) {
        Start-Sleep -Milliseconds 250
        continue
      }

      if ($NonInteractive) {
        Warn "Could not clean '$Path' because a file is in use. Continuing without deleting this folder."
        Warn $errMsg
        return $false
      }

      Warn "Could not clean '$Path' because a file is in use."
      Warn "Close apps/files using this path (for example VS Code tab, indexer, compiler), then choose Retry."
      $choice = (Read-Host "[UE Sync] Cleanup failed. [R]etry / [S]kip cleanup / [A]bort").Trim().ToLowerInvariant()

      switch ($choice) {
        { $_ -in @("", "r", "retry") } {
          $attempt = 0
          continue
        }
        { $_ -in @("s", "skip") } {
          Warn "Skipping cleanup for '$Path'."
          return $false
        }
        default {
          throw "Aborted by user during cleanup of '$Path'."
        }
      }
    }
  }
}

function Get-UProjectPath {
  $projectContext = Get-ProjectContext -RepoRoot $script:ResolvedRepoRoot -UProjectPath $UProjectPath -WorkspacePath $WorkspacePath
  return $projectContext.UProjectPath
}

function Get-ProjectName([string]$uprojectPath) {
  $projectContext = Get-ProjectContext -RepoRoot $script:ResolvedRepoRoot -UProjectPath $uprojectPath -WorkspacePath $WorkspacePath
  return $projectContext.ProjectName
}

function Add-DiagnosticAttempt([System.Collections.Generic.List[string]]$Attempts, [string]$Message) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Add-UEToolSuiteUnrealDiagnosticAttempt" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Add-UEToolSuiteUnrealDiagnosticAttempt -Attempts $Attempts -Message $Message
    return
  }

  if ($null -ne $Attempts) {
    [void]$Attempts.Add($Message)
  }
}

function Resolve-PathRelativeTo([string]$baseDir, [string]$path) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Resolve-UEToolSuiteUnrealPathRelativeTo" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Resolve-UEToolSuiteUnrealPathRelativeTo -BaseDir $baseDir -Path $path)
  }

  if (-not $path) { return $null }
  if ([IO.Path]::IsPathRooted($path)) { return $path }
  Join-Path $baseDir $path
}

function Get-EngineRootFromWorkspace(
  [string]$repoRoot,
  [string]$explicitWorkspacePath,
  [System.Collections.Generic.List[string]]$attempts = $null
) {
  $wsFile = $null

  if ($explicitWorkspacePath) {
    $workspaceCandidate = Resolve-PathRelativeTo $repoRoot $explicitWorkspacePath
    Add-DiagnosticAttempt $attempts "workspace override path: '$workspaceCandidate'"
    $wsFile = Get-Item -LiteralPath $workspaceCandidate -ErrorAction SilentlyContinue
    if (-not $wsFile) {
      Add-DiagnosticAttempt $attempts "workspace override not found"
    }
  }
  else {
    $workspaceCandidates = @(Get-ChildItem -Path $repoRoot -Filter *.code-workspace -File -ErrorAction SilentlyContinue)
    if ($workspaceCandidates.Count -gt 0) {
      $wsFile = $workspaceCandidates | Select-Object -First 1
      Add-DiagnosticAttempt $attempts "workspace auto-discovery: using '$($wsFile.FullName)'"
    }
    else {
      Add-DiagnosticAttempt $attempts "workspace auto-discovery: no *.code-workspace in repo root"
    }
  }

  if (-not $wsFile) { return $null }

  try {
    $json = Get-Content $wsFile.FullName -Raw | ConvertFrom-Json
  }
  catch {
    Add-DiagnosticAttempt $attempts "workspace parse failed: $($wsFile.FullName) ($($_.Exception.Message))"
    return $null
  }

  $folders = @($json.folders)
  if (-not $folders -or $folders.Count -eq 0) {
    Add-DiagnosticAttempt $attempts "workspace has no folders[] entries"
    return $null
  }

  # Prefer folders named UE5 / UE*
  $preferred = $folders | Where-Object { $_.name -and $_.name -match '^UE' } | Select-Object -First 1
  if ($preferred) {
    $p = Resolve-PathRelativeTo $repoRoot $preferred.path
    Add-DiagnosticAttempt $attempts "workspace preferred UE folder '$($preferred.name)' -> '$p'"
    if (Test-EngineRoot $p) {
      Add-DiagnosticAttempt $attempts "workspace preferred UE folder validated"
      return $p
    }
  }

  # Otherwise, find any folder path that looks like UE_5.x and validates
  foreach ($f in $folders) {
    $p = Resolve-PathRelativeTo $repoRoot $f.path
    if (-not $p) { continue }
    $folderName = if ($f.name) { $f.name } else { "<unnamed>" }
    Add-DiagnosticAttempt $attempts "workspace folder '$folderName' -> '$p'"

    if ($p -match 'UE_\d' -and (Test-EngineRoot $p)) {
      Add-DiagnosticAttempt $attempts "workspace UE_* path validated"
      return $p
    }

    # If path points inside ...\Engine\..., walk up to root
    $idx = $p.ToLower().IndexOf("\engine\")
    if ($idx -ge 0) {
      $root = $p.Substring(0, $idx)
      Add-DiagnosticAttempt $attempts "workspace folder points into Engine subpath; testing root '$root'"
      if (Test-EngineRoot $root) {
        Add-DiagnosticAttempt $attempts "workspace Engine-subpath root validated"
        return $root
      }
    }

    # Path points to ...\Engine
    if ($p.ToLower().EndsWith("\engine")) {
      $root = Split-Path $p -Parent
      Add-DiagnosticAttempt $attempts "workspace folder points to Engine dir; testing root '$root'"
      if (Test-EngineRoot $root) {
        Add-DiagnosticAttempt $attempts "workspace Engine parent root validated"
        return $root
      }
    }
  }

  return $null
}

function Get-UProjectEngineAssociation(
  [string]$uprojectPath,
  [System.Collections.Generic.List[string]]$attempts = $null
) {
  if (-not $uprojectPath) {
    Add-DiagnosticAttempt $attempts ".uproject path not provided for EngineAssociation lookup"
    return $null
  }
  if (-not (Test-Path -LiteralPath $uprojectPath)) {
    Add-DiagnosticAttempt $attempts ".uproject not found for EngineAssociation lookup: $uprojectPath"
    return $null
  }

  try {
    $uprojectJson = Get-Content -LiteralPath $uprojectPath -Raw | ConvertFrom-Json
  }
  catch {
    Add-DiagnosticAttempt $attempts ".uproject parse failed for EngineAssociation lookup ($($_.Exception.Message))"
    return $null
  }

  $association = [string]$uprojectJson.EngineAssociation
  if ([string]::IsNullOrWhiteSpace($association)) {
    Add-DiagnosticAttempt $attempts ".uproject has no EngineAssociation value"
    return $null
  }

  Add-DiagnosticAttempt $attempts ".uproject EngineAssociation='$association'"
  return $association.Trim()
}

function Get-EngineRootFromEngineAssociation(
  [string]$engineAssociation,
  [System.Collections.Generic.List[string]]$attempts = $null
) {
  if ([string]::IsNullOrWhiteSpace($engineAssociation)) { return $null }

  $hkcuBuilds = "Registry::HKEY_CURRENT_USER\SOFTWARE\Epic Games\Unreal Engine\Builds"
  if (Test-Path $hkcuBuilds) {
    $hkcuRoot = Get-RegistryPropertyString $hkcuBuilds $engineAssociation
    if ($hkcuRoot) {
      Add-DiagnosticAttempt $attempts "HKCU Builds[$engineAssociation] -> '$hkcuRoot'"
      if (Test-EngineRoot $hkcuRoot) {
        Add-DiagnosticAttempt $attempts "HKCU Builds[$engineAssociation] validated"
        return $hkcuRoot
      }
      Add-DiagnosticAttempt $attempts "HKCU Builds[$engineAssociation] failed engine-root validation"
    }
    else {
      Add-DiagnosticAttempt $attempts "HKCU Builds[$engineAssociation] not present"
    }
  }
  else {
    Add-DiagnosticAttempt $attempts "HKCU Builds registry key missing"
  }

  $hklmCandidates = @(
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\EpicGames\Unreal Engine\$engineAssociation",
    "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\EpicGames\Unreal Engine\$engineAssociation"
  )
  foreach ($candidate in $hklmCandidates) {
    if (-not (Test-Path $candidate)) {
      Add-DiagnosticAttempt $attempts "HKLM candidate missing: $candidate"
      continue
    }

    $installedDirectory = Get-RegistryPropertyString $candidate "InstalledDirectory"
    if (-not $installedDirectory) {
      Add-DiagnosticAttempt $attempts "HKLM candidate has no InstalledDirectory: $candidate"
      continue
    }

    Add-DiagnosticAttempt $attempts "HKLM InstalledDirectory -> '$installedDirectory'"
    if (Test-EngineRoot $installedDirectory) {
      Add-DiagnosticAttempt $attempts "HKLM InstalledDirectory validated"
      return $installedDirectory
    }

    Add-DiagnosticAttempt $attempts "HKLM InstalledDirectory failed engine-root validation"
  }

  return $null
}

function Resolve-EngineRootForBuild([string]$workspacePathOverride, [string]$uprojectPath) {
  $projectContext = Get-ProjectContext `
    -RepoRoot $script:ResolvedRepoRoot `
    -UProjectPath $uprojectPath `
    -WorkspacePath $workspacePathOverride

  $attempts = [System.Collections.Generic.List[string]]::new()
  $workspaceRoot = Get-EngineRootFromWorkspaceContext `
    -ProjectContext $projectContext `
    -WorkspacePath $workspacePathOverride `
    -Attempts $attempts
  if (-not [string]::IsNullOrWhiteSpace($workspaceRoot)) {
    Info "Engine root resolved from workspace: $workspaceRoot"
    return $workspaceRoot
  }

  foreach ($envVar in @("UE_ENGINE_DIR", "UE_ENGINE_ROOT", "UNREAL_ENGINE_DIR")) {
    $candidate = [string](Get-Item -Path "Env:$envVar" -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      Add-DiagnosticAttempt $attempts "$envVar is unset"
      continue
    }

    Add-DiagnosticAttempt $attempts "$envVar -> '$candidate'"
    if (Test-EngineRoot $candidate) {
      Info "Engine root resolved from ${envVar}: $candidate"
      return $candidate
    }

    Add-DiagnosticAttempt $attempts "$envVar failed engine-root validation"
  }

  if (-not [string]::IsNullOrWhiteSpace($projectContext.EngineAssociation)) {
    Add-DiagnosticAttempt $attempts ".uproject EngineAssociation='$($projectContext.EngineAssociation)'"
  }
  else {
    Add-DiagnosticAttempt $attempts ".uproject has no EngineAssociation value"
  }

  $registryRoot = Get-EngineRootFromRegistryAssociation `
    -EngineAssociation $projectContext.EngineAssociation `
    -Attempts $attempts
  if (-not [string]::IsNullOrWhiteSpace($registryRoot)) {
    Info "Engine root resolved from registry using EngineAssociation '$($projectContext.EngineAssociation)': $registryRoot"
    return $registryRoot
  }

  $commonInstallRoot = Get-EngineRootFromCommonInstalls `
    -EngineAssociation $projectContext.EngineAssociation `
    -Attempts $attempts
  if (-not [string]::IsNullOrWhiteSpace($commonInstallRoot)) {
    Info "Engine root resolved from common install roots: $commonInstallRoot"
    return $commonInstallRoot
  }

  $attemptLines = if ($attempts.Count -gt 0) {
    $attempts | ForEach-Object { "- $_" }
  }
  else {
    @("- no discovery attempts were recorded")
  }
  $attemptText = $attemptLines -join "`n"

  throw @"
Could not resolve Unreal Engine install path for project-file fallback.

Attempted sources (in order):
$attemptText

Action:
- Re-generate the VS Code workspace in Unreal so it contains the UE install folder under folders[].
- Or set UE_ENGINE_DIR / UE_ENGINE_ROOT / UNREAL_ENGINE_DIR on this machine.
- Or ensure the .uproject EngineAssociation maps to an installed engine in registry.
"@
}

function Get-UProjectProgId {
  # Example: ".uproject=Unreal.ProjectFile" -> returns "Unreal.ProjectFile"
  $assoc = cmd /c assoc .uproject 2>$null
  if (-not $assoc) { return $null }
  ($assoc -replace '^.*=').Trim()
}

$script:LastUVSResolution = $null

function Resolve-UVSPathFromRegistry {
  # Optional explicit override for local troubleshooting or deterministic tests.
  $explicitUvs = [string]$env:UE_SYNC_UVS_PATH
  if (-not [string]::IsNullOrWhiteSpace($explicitUvs)) {
    $resolvedExplicit = Resolve-PathRelativeTo (Get-Location).Path $explicitUvs
    if (Test-Path $resolvedExplicit) {
      return [pscustomobject]@{
        Path    = $resolvedExplicit
        Source  = "UE_SYNC_UVS_PATH"
        Command = "<env override>"
      }
    }
  }

  # Reads the same command Explorer runs for right-click "Generate Visual Studio project files"
  # and extracts UnrealVersionSelector.exe path from it.
  $progId = Get-UProjectProgId
  $candidateShellRoots = @()

  if ($progId) {
    $candidateShellRoots += "Registry::HKEY_CLASSES_ROOT\$progId\shell"
  }
  # common fallback ProgID
  $candidateShellRoots += "Registry::HKEY_CLASSES_ROOT\Unreal.ProjectFile\shell"
  $candidateShellRoots += "Registry::HKEY_CLASSES_ROOT\.uproject\shell"

  foreach ($shellRoot in $candidateShellRoots | Select-Object -Unique) {
    if (-not (Test-Path $shellRoot)) { continue }

    foreach ($verbKey in Get-ChildItem $shellRoot -ErrorAction SilentlyContinue) {
      $cmdKey = Join-Path $verbKey.PSPath "command"
      if (-not (Test-Path $cmdKey)) { continue }

      $cmd = (Get-ItemProperty $cmdKey -ErrorAction SilentlyContinue).'(default)'
      if (-not $cmd) { continue }

      # We only care about verbs that run UnrealVersionSelector.exe /projectfiles.
      if ($cmd -match 'UnrealVersionSelector\.exe"\s+/projectfiles\s+"%1"' -or
        $cmd -match 'UnrealVersionSelector\.exe"\s+/projectfiles') {

        # Extract the exe path between quotes.
        if ($cmd -match '^"(?<exe>[^"]+UnrealVersionSelector\.exe)"') {
          $exe = $Matches.exe
          if (Test-Path $exe) {
            return [pscustomobject]@{
              Path    = $exe
              Source  = "$shellRoot\$($verbKey.PSChildName)"
              Command = $cmd
            }
          }
        }
      }
    }
  }

  return $null
}

function Get-UVSPathFromRegistry {
  $script:LastUVSResolution = Resolve-UVSPathFromRegistry
  if ($script:LastUVSResolution) {
    return [string]$script:LastUVSResolution.Path
  }
  return $null
}

function Resolve-RegenerateFallbackTool([string]$engineRoot) {
  $candidates = @(
    [pscustomobject]@{
      Name = "RunUBT.bat"
      Path = Join-Path $engineRoot "Engine\Build\BatchFiles\RunUBT.bat"
    },
    [pscustomobject]@{
      Name = "Build.bat"
      Path = Join-Path $engineRoot "Engine\Build\BatchFiles\Build.bat"
    }
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate.Path) {
      return [pscustomobject]@{
        Name       = $candidate.Name
        Path       = $candidate.Path
        Candidates = $candidates
      }
    }
  }

  return [pscustomobject]@{
    Name       = $null
    Path       = $null
    Candidates = $candidates
  }
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  Write-UEToolSuiteRuntimeUtf8NoBomFile -ScriptsRoot $script:UnrealScriptsRoot -Path $Path -Content $Content -EnsureParentDirectory
}

function Get-ChangedFileRecords([string]$oldrev, [string]$newrev) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteUnrealChangedFileRecords" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return @(Get-UEToolSuiteUnrealChangedFileRecords -OldRev $oldrev -NewRev $newrev)
  }

  if ([string]::IsNullOrWhiteSpace($oldrev) -or [string]::IsNullOrWhiteSpace($newrev)) { return @() }

  $out = git diff --name-status $oldrev $newrev 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }

  $records = @()
  foreach ($line in @($out)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $parts = @($line -split "`t")
    if ($parts.Count -lt 2) { continue }

    $status = [string]$parts[0]
    if (($status.StartsWith("R") -or $status.StartsWith("C")) -and $parts.Count -ge 3) {
      $records += [pscustomobject]@{
        Status = $status
        Path = [string]$parts[2]
        OldPath = [string]$parts[1]
      }
      continue
    }

    $records += [pscustomobject]@{
      Status = $status
      Path = [string]$parts[1]
      OldPath = $null
    }
  }

  return @($records)
}

function Test-IsUnrealCppPath([string]$Path) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteUnrealCppPath" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteUnrealCppPath -Path $Path)
  }

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return (
    $Path -match '^Source/.*\.(h|hpp|cpp|inl)$' -or
    $Path -match '^Plugins/.*\.(h|hpp|cpp|inl)$'
  )
}

function Test-IsUnrealProjectStructurePath([string]$Path) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteUnrealProjectStructurePath" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteUnrealProjectStructurePath -Path $Path)
  }

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return (
    $Path -match '\.Build\.cs$' -or
    $Path -match '\.Target\.cs$' -or
    $Path -match '\.uproject$' -or
    $Path -match '^Plugins/.*\.uplugin$'
  )
}

function Test-IsAddDeleteOrRenameStatus([string]$Status) {
  if ([string]::IsNullOrWhiteSpace($Status)) { return $false }
  return (
    $Status.StartsWith("A") -or
    $Status.StartsWith("D") -or
    $Status.StartsWith("R")
  )
}

function Get-UnrealSyncActionPlan([object[]]$ChangedFileRecords) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteUnrealSyncActionPlan" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteUnrealSyncActionPlan -ChangedFileRecords $ChangedFileRecords)
  }

  if (-not $ChangedFileRecords -or $ChangedFileRecords.Count -eq 0) {
    return [pscustomobject]@{
      BuildTriggers = @()
      RegenTriggers = @()
      ShouldBuild = $false
      ShouldRegen = $false
    }
  }

  $buildTriggers = @()
  $regenTriggers = @()

  foreach ($record in @($ChangedFileRecords)) {
    $paths = @($record.Path, $record.OldPath) |
      Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
      Sort-Object -Unique

    foreach ($path in $paths) {
      if (Test-IsUnrealCppPath -Path $path) {
        $buildTriggers += $path
        if (Test-IsAddDeleteOrRenameStatus -Status $record.Status) {
          $regenTriggers += $path
        }
        continue
      }

      if (Test-IsUnrealProjectStructurePath -Path $path) {
        $buildTriggers += $path
        $regenTriggers += $path
      }
    }
  }

  $buildTriggers = @($buildTriggers | Sort-Object -Unique)
  $regenTriggers = @($regenTriggers | Sort-Object -Unique)

  return [pscustomobject]@{
    BuildTriggers = $buildTriggers
    RegenTriggers = $regenTriggers
    ShouldBuild = ($buildTriggers.Count -gt 0)
    ShouldRegen = ($regenTriggers.Count -gt 0)
  }
}

function Get-RebuildTriggers([string[]]$ChangedFiles) {
  if (-not $ChangedFiles -or $ChangedFiles.Count -eq 0) {
    return @()
  }

  $triggers = @()

  foreach ($f in $ChangedFiles) {
    if ((Test-IsUnrealCppPath -Path $f) -or (Test-IsUnrealProjectStructurePath -Path $f)) {
      $triggers += $f
      continue
    }
  }

  return ($triggers | Sort-Object -Unique)
}

function Show-UnrealSyncActionPlan($ActionPlan) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Write-UEToolSuiteUnrealSyncActionPlan" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Write-UEToolSuiteUnrealSyncActionPlan -ActionPlan $ActionPlan -WarnWriter {
      param([string]$Message)
      Warn $Message
    }
    return
  }

  if (-not $ActionPlan -or (-not $ActionPlan.ShouldBuild -and -not $ActionPlan.ShouldRegen)) {
    return
  }

  $actions = @()
  if ($ActionPlan.ShouldRegen) { $actions += "regenerate project files" }
  if ($ActionPlan.ShouldBuild) { $actions += "build the editor" }
  Warn "UE Sync action plan: $($actions -join ' and ')."

  if ($ActionPlan.RegenTriggers.Count -gt 0) {
    Warn "Project-file regeneration triggers:"
    foreach ($t in @($ActionPlan.RegenTriggers)) {
      Warn " - $t"
    }
  }

  if ($ActionPlan.BuildTriggers.Count -gt 0) {
    Warn "Build triggers:"
    foreach ($t in @($ActionPlan.BuildTriggers)) {
      Warn " - $t"
    }
  }
}

function Invoke-Regenerate-ProjectFiles(
  [string]$uprojectPath,
  [string]$engineRootForFallback,
  [string]$workspacePathOverride
) {
  $uvs = Get-UVSPathFromRegistry
  if (-not $uvs) {
    Warn "UVS not found via registry; using batch-file project-file fallback..."
  }
  else {
    $uvsArgs = @("/projectfiles", $uprojectPath)
    Warn "Regenerating project files (context menu UVS)..."
    Info "UVS path: $uvs"
    if ($script:LastUVSResolution -and $script:LastUVSResolution.Source) {
      Info "UVS source: $($script:LastUVSResolution.Source)"
    }
    if ($script:LastUVSResolution -and $script:LastUVSResolution.Command) {
      Info "UVS command: $($script:LastUVSResolution.Command)"
    }
    Info "UVS args: $($uvsArgs -join ' ')"
    Info "UVS cwd : $((Get-Location).Path)"

    $maxAttempts = 2
    if ($env:UE_SYNC_UVS_MAX_ATTEMPTS -as [int]) {
      $maxAttempts = [int]$env:UE_SYNC_UVS_MAX_ATTEMPTS
    }
    if ($maxAttempts -lt 1) {
      $maxAttempts = 1
    }

    $uvsExitCode = -1
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
      try {
        $uvsProcess = Start-Process `
          -FilePath $uvs `
          -ArgumentList @("/projectfiles", "`"$uprojectPath`"") `
          -WorkingDirectory (Split-Path -Path $uprojectPath -Parent) `
          -Wait `
          -PassThru `
          -ErrorAction Stop
        $uvsExitCode = [int]$uvsProcess.ExitCode
      }
      catch {
        Warn "UVS invocation failed on attempt $attempt/${maxAttempts}: $($_.Exception.Message)"
        $uvsExitCode = -1
      }

      if ($uvsExitCode -eq 0) {
        Success "UVS project-file regeneration succeeded."
        return
      }

      if ($attempt -lt $maxAttempts) {
        Warn "UVS returned non-zero exit ($uvsExitCode) on attempt $attempt/$maxAttempts. Retrying..."
        Start-Sleep -Milliseconds 300
      }
    }

    Warn "UVS failed (exit $uvsExitCode) after $maxAttempts attempt(s). Falling back to batch-file project generation..."
  }

  if (-not $engineRootForFallback) {
    Warn "Engine root was not pre-resolved for fallback. Resolving now..."
    $engineRootForFallback = Resolve-EngineRootForBuild $workspacePathOverride $uprojectPath
  }
  Info "Engine (fallback): $engineRootForFallback"

  $fallbackTool = Resolve-RegenerateFallbackTool $engineRootForFallback
  if (-not $fallbackTool.Path) {
    $candidateText = $fallbackTool.Candidates | ForEach-Object { "- $($_.Name): $($_.Path)" }
    throw @"
Cannot run project-file fallback. No supported tool was found under engine root:
$engineRootForFallback

Checked:
$($candidateText -join "`n")
"@
  }

  $regenLogDir = Join-Path (Get-Location).Path "Intermediate\UnrealSync"
  New-Item -ItemType Directory -Force -Path $regenLogDir | Out-Null
  $regenLog = Join-Path $regenLogDir ("ProjectFiles-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

  $fallbackArgs = @(
    "-projectfiles",
    "-vscode",
    "-project=$uprojectPath",
    "-game",
    "-engine",
    "-log=$regenLog"
  )
  if ($fallbackTool.Name -eq "RunUBT.bat") {
    $fallbackArgs += "-dotnet"
  }

  Warn "Regenerating project files (fallback via $($fallbackTool.Name))..."
  Info "Fallback tool: $($fallbackTool.Path)"
  Info "Fallback args: $($fallbackArgs -join ' ')"
  & $fallbackTool.Path @fallbackArgs | Out-Host

  if ($LASTEXITCODE -ne 0) {
    throw "Project-file fallback failed via $($fallbackTool.Name) (exit $LASTEXITCODE). See log: $regenLog"
  }

  Success "Fallback project-file regeneration succeeded."
}


function Build-Editor([string]$engineRoot, [string]$uprojectPath, [string]$projectName, [string]$platform, [string]$config) {
  $buildBat = Join-Path $engineRoot "Engine\Build\BatchFiles\Build.bat"
  if (-not (Test-Path $buildBat)) { throw "Build.bat not found: $buildBat" }

  $target = "${projectName}Editor"
  Warn "Building $target ($platform $config) using engine root: $engineRoot"
  & $buildBat $target $platform $config -Project="`"$uprojectPath`"" -WaitMutex | Out-Host
}

function Test-GitTrackedPath([string]$RelativePath) {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteUnrealGitTrackedPath" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteUnrealGitTrackedPath -RelativePath $RelativePath)
  }

  if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
  & git ls-files --error-unmatch -- $RelativePath 2>$null | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Get-WorkspaceProtectionPaths {
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePathOverride
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteUnrealWorkspaceProtectionPaths" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return @(Get-UEToolSuiteUnrealWorkspaceProtectionPaths -ProjectContext $ProjectContext -WorkspacePathOverride $WorkspacePathOverride)
  }

  $paths = New-Object System.Collections.Generic.List[string]

  if (-not [string]::IsNullOrWhiteSpace($WorkspacePathOverride)) {
    [void]$paths.Add((Resolve-PathRelativeTo $ProjectContext.RepoRoot $WorkspacePathOverride))
  }

  if (-not [string]::IsNullOrWhiteSpace($ProjectContext.WorkspacePath)) {
    [void]$paths.Add($ProjectContext.WorkspacePath)
  }

  [void]$paths.Add((Join-Path $ProjectContext.RepoRoot "$($ProjectContext.ProjectName).code-workspace"))

  return @(
    $paths.ToArray() |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
      Sort-Object -Unique
  )
}

function New-ProjectFileArtifactSnapshot {
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePathOverride
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "New-UEToolSuiteUnrealProjectFileArtifactSnapshot" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (New-UEToolSuiteUnrealProjectFileArtifactSnapshot -ProjectContext $ProjectContext -WorkspacePathOverride $WorkspacePathOverride)
  }

  $workspaceSnapshots = @()
  foreach ($workspacePath in @(Get-WorkspaceProtectionPaths -ProjectContext $ProjectContext -WorkspacePathOverride $WorkspacePathOverride)) {
    if (-not (Test-Path -LiteralPath $workspacePath -PathType Leaf)) { continue }

    $workspaceSnapshots += [pscustomobject]@{
      Path = $workspacePath
      Content = Get-Content -LiteralPath $workspacePath -Raw
    }
  }

  $ignorePath = Join-Path $ProjectContext.RepoRoot ".ignore"
  $ignoreExists = Test-Path -LiteralPath $ignorePath -PathType Leaf
  $ignoreTracked = Test-GitTrackedPath -RelativePath ".ignore"

  return [pscustomobject]@{
    WorkspaceSnapshots = @($workspaceSnapshots)
    IgnorePath = $ignorePath
    IgnoreExists = $ignoreExists
    IgnoreTracked = $ignoreTracked
    IgnoreContent = if ($ignoreExists) { Get-Content -LiteralPath $ignorePath -Raw } else { $null }
  }
}

function Test-JsonObjectProperty {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteJsonObjectProperty" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteJsonObjectProperty -Object $Object -Name $Name)
  }

  return ($null -ne $Object.PSObject.Properties[$Name])
}

function Get-JsonObjectPropertyValue {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteJsonObjectPropertyValue" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteJsonObjectPropertyValue -Object $Object -Name $Name)
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($property) { return $property.Value }
  return $null
}

function Set-JsonObjectPropertyValue {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name,
    [AllowNull()]$Value
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Set-UEToolSuiteJsonObjectPropertyValue" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Set-UEToolSuiteJsonObjectPropertyValue -Object $Object -Name $Name -Value $Value
    return
  }

  if (Test-JsonObjectProperty -Object $Object -Name $Name) {
    $Object.$Name = $Value
    return
  }

  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
}

function Test-IsJsonObject {
  param([AllowNull()]$Value)
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteJsonObject" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteJsonObject -Value $Value)
  }
  return ($null -ne $Value -and $Value -is [pscustomobject])
}

function Merge-MissingJsonObjectProperties {
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Source
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Merge-UEToolSuiteMissingJsonObjectProperties" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Merge-UEToolSuiteMissingJsonObjectProperties -Target $Target -Source $Source
    return
  }

  foreach ($sourceProperty in @($Source.PSObject.Properties)) {
    $targetValue = Get-JsonObjectPropertyValue -Object $Target -Name $sourceProperty.Name
    if (-not (Test-JsonObjectProperty -Object $Target -Name $sourceProperty.Name)) {
      Set-JsonObjectPropertyValue -Object $Target -Name $sourceProperty.Name -Value $sourceProperty.Value
      continue
    }

    if ((Test-IsJsonObject -Value $targetValue) -and (Test-IsJsonObject -Value $sourceProperty.Value)) {
      Merge-MissingJsonObjectProperties -Target $targetValue -Source $sourceProperty.Value
    }
  }
}

function Merge-StringArrayProperty {
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)][string]$PropertyName
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Merge-UEToolSuiteStringArrayProperty" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Merge-UEToolSuiteStringArrayProperty -Target $Target -Source $Source -PropertyName $PropertyName
    return
  }

  if (-not (Test-JsonObjectProperty -Object $Source -Name $PropertyName)) { return }

  $existing = @()
  if (Test-JsonObjectProperty -Object $Target -Name $PropertyName) {
    $existing = @(Get-JsonObjectPropertyValue -Object $Target -Name $PropertyName)
  }

  $merged = @($existing + @(Get-JsonObjectPropertyValue -Object $Source -Name $PropertyName)) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    Select-Object -Unique

  Set-JsonObjectPropertyValue -Object $Target -Name $PropertyName -Value @($merged)
}

function Merge-NamedObjectArrayProperty {
  param(
    [Parameter(Mandatory)]$Target,
    [Parameter(Mandatory)]$Source,
    [Parameter(Mandatory)][string]$ArrayPropertyName,
    [Parameter(Mandatory)][string]$KeyPropertyName
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Merge-UEToolSuiteNamedObjectArrayProperty" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Merge-UEToolSuiteNamedObjectArrayProperty -Target $Target -Source $Source -ArrayPropertyName $ArrayPropertyName -KeyPropertyName $KeyPropertyName
    return
  }

  if (-not (Test-JsonObjectProperty -Object $Source -Name $ArrayPropertyName)) { return }

  $targetItems = @()
  if (Test-JsonObjectProperty -Object $Target -Name $ArrayPropertyName) {
    $targetItems = @(Get-JsonObjectPropertyValue -Object $Target -Name $ArrayPropertyName)
  }

  $targetKeys = @{}
  foreach ($item in $targetItems) {
    $key = [string](Get-JsonObjectPropertyValue -Object $item -Name $KeyPropertyName)
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $targetKeys[$key] = $true
    }
  }

  $mergedItems = @($targetItems)
  foreach ($sourceItem in @(Get-JsonObjectPropertyValue -Object $Source -Name $ArrayPropertyName)) {
    $sourceKey = [string](Get-JsonObjectPropertyValue -Object $sourceItem -Name $KeyPropertyName)
    if ([string]::IsNullOrWhiteSpace($sourceKey) -or $targetKeys.ContainsKey($sourceKey)) {
      continue
    }

    $mergedItems += $sourceItem
    $targetKeys[$sourceKey] = $true
  }

  Set-JsonObjectPropertyValue -Object $Target -Name $ArrayPropertyName -Value @($mergedItems)
}

function Merge-VSCodeWorkspaceJson {
  param(
    [Parameter(Mandatory)]$GeneratedWorkspace,
    [Parameter(Mandatory)]$PreviousWorkspace
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Merge-UEToolSuiteVSCodeWorkspaceJson" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Merge-UEToolSuiteVSCodeWorkspaceJson -GeneratedWorkspace $GeneratedWorkspace -PreviousWorkspace $PreviousWorkspace)
  }

  Merge-MissingJsonObjectProperties -Target $GeneratedWorkspace -Source $PreviousWorkspace

  Merge-NamedObjectArrayProperty -Target $GeneratedWorkspace -Source $PreviousWorkspace -ArrayPropertyName "folders" -KeyPropertyName "path"

  $generatedExtensions = Get-JsonObjectPropertyValue -Object $GeneratedWorkspace -Name "extensions"
  $previousExtensions = Get-JsonObjectPropertyValue -Object $PreviousWorkspace -Name "extensions"
  if ((Test-IsJsonObject -Value $generatedExtensions) -and (Test-IsJsonObject -Value $previousExtensions)) {
    Merge-StringArrayProperty -Target $generatedExtensions -Source $previousExtensions -PropertyName "recommendations"
    Merge-StringArrayProperty -Target $generatedExtensions -Source $previousExtensions -PropertyName "unwantedRecommendations"
  }

  $generatedTasks = Get-JsonObjectPropertyValue -Object $GeneratedWorkspace -Name "tasks"
  $previousTasks = Get-JsonObjectPropertyValue -Object $PreviousWorkspace -Name "tasks"
  if ((Test-IsJsonObject -Value $generatedTasks) -and (Test-IsJsonObject -Value $previousTasks)) {
    Merge-NamedObjectArrayProperty -Target $generatedTasks -Source $previousTasks -ArrayPropertyName "tasks" -KeyPropertyName "label"
  }

  $generatedLaunch = Get-JsonObjectPropertyValue -Object $GeneratedWorkspace -Name "launch"
  $previousLaunch = Get-JsonObjectPropertyValue -Object $PreviousWorkspace -Name "launch"
  if ((Test-IsJsonObject -Value $generatedLaunch) -and (Test-IsJsonObject -Value $previousLaunch)) {
    Merge-NamedObjectArrayProperty -Target $generatedLaunch -Source $previousLaunch -ArrayPropertyName "configurations" -KeyPropertyName "name"
  }

  return $GeneratedWorkspace
}

function Restore-ProjectFileArtifactSnapshot {
  param([Parameter(Mandatory)]$Snapshot)

  foreach ($workspaceSnapshot in @($Snapshot.WorkspaceSnapshots)) {
    if (-not (Test-Path -LiteralPath $workspaceSnapshot.Path -PathType Leaf)) {
      Write-Utf8NoBomFile -Path $workspaceSnapshot.Path -Content $workspaceSnapshot.Content
      Warn "Restored VS Code workspace file after project-file regeneration: $($workspaceSnapshot.Path)"
      continue
    }

    try {
      $currentWorkspaceContent = Get-Content -LiteralPath $workspaceSnapshot.Path -Raw
      if ($currentWorkspaceContent -ceq $workspaceSnapshot.Content) {
        continue
      }

      $previousWorkspace = $workspaceSnapshot.Content | ConvertFrom-Json
      $generatedWorkspace = $currentWorkspaceContent | ConvertFrom-Json
      $mergedWorkspace = Merge-VSCodeWorkspaceJson -GeneratedWorkspace $generatedWorkspace -PreviousWorkspace $previousWorkspace
      $mergedContent = ($mergedWorkspace | ConvertTo-Json -Depth 100)
      Write-Utf8NoBomFile -Path $workspaceSnapshot.Path -Content ($mergedContent + "`r`n")
      Warn "Preserved user VS Code workspace settings after project-file regeneration: $($workspaceSnapshot.Path)"
    }
    catch {
      Warn "Could not merge VS Code workspace customization after project-file regeneration. Restoring the pre-regen workspace file."
      Warn $_.Exception.Message
      Write-Utf8NoBomFile -Path $workspaceSnapshot.Path -Content $workspaceSnapshot.Content
    }
  }

  if ($Snapshot.IgnoreExists -and (Test-Path -LiteralPath $Snapshot.IgnorePath -PathType Leaf)) {
    $currentIgnoreContent = Get-Content -LiteralPath $Snapshot.IgnorePath -Raw
    if ($currentIgnoreContent -cne $Snapshot.IgnoreContent) {
      Write-Utf8NoBomFile -Path $Snapshot.IgnorePath -Content $Snapshot.IgnoreContent
      Warn "Restored .ignore after project-file regeneration to avoid tracked file churn."
    }
  }
  elseif (-not $Snapshot.IgnoreExists -and $Snapshot.IgnoreTracked -and (Test-Path -LiteralPath $Snapshot.IgnorePath -PathType Leaf)) {
    Remove-Item -LiteralPath $Snapshot.IgnorePath -Force
    Warn "Removed generated .ignore because it is tracked but did not exist before regeneration."
  }
}

# ---- Main ----
$script:ResolvedRepoRoot = Resolve-UnrealSyncRoot -ExplicitRepoRoot $RepoRoot
Set-Location $script:ResolvedRepoRoot

$manual = $Force -or $CleanGenerated -or $CleanSaved -or $CleanCache -or $NoRegen -or $NoBuild

# If invoked from hook, only run on branch checkouts.
if (-not $manual -and $Flag -ne 1) {
  exit 0
}

# Rebase can execute hooks at many internal steps. Keep hook execution silent there.
$reflogAction = [string]$env:GIT_REFLOG_ACTION
if (-not $manual -and $reflogAction -match 'rebase') {
  exit 0
}

# Skip silently during active merge/rebase contexts when running from hooks.
if (-not $manual) {
  $gitDir = (git rev-parse --git-dir 2>$null | Select-Object -First 1).Trim()
  if ([string]::IsNullOrWhiteSpace($gitDir)) { $gitDir = ".git" }
  if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
    $gitDir = Join-Path (Get-Location).Path $gitDir
  }

  if (
      (Test-Path (Join-Path $gitDir "rebase-apply")) -or
      (Test-Path (Join-Path $gitDir "rebase-merge")) -or
      (Test-Path (Join-Path $gitDir "MERGE_HEAD")) -or
      (Test-Path (Join-Path $gitDir "CHERRY_PICK_HEAD")) -or
      (Test-Path (Join-Path $gitDir "REVERT_HEAD"))
    ) {
    exit 0
  }
}

$actionPlan = [pscustomobject]@{
  BuildTriggers = @()
  RegenTriggers = @()
  ShouldBuild = $Force -and -not $NoBuild
  ShouldRegen = $Force -and -not $NoRegen
}
if (-not $manual) {
  $changedRecords = Get-ChangedFileRecords $OldRev $NewRev
  $actionPlan = Get-UnrealSyncActionPlan $changedRecords
  if (-not $actionPlan.ShouldBuild -and -not $actionPlan.ShouldRegen) {
    # No UE C++/project trigger => no-op, keep hook output clean.
    exit 0
  }
}

$projectContext = Get-ProjectContext -RepoRoot $script:ResolvedRepoRoot -UProjectPath $UProjectPath -WorkspacePath $WorkspacePath
$uprojectPath = $projectContext.UProjectPath
$projectName = $projectContext.ProjectName

$shouldRunRegen = -not $NoRegen -and ($manual -or $actionPlan.ShouldRegen)
$shouldRunBuild = -not $NoBuild -and ($manual -or $actionPlan.ShouldBuild)

Info "UProject Path: $uprojectPath"
if (-not $manual) {
  Info "Checking UE sync actions between $OldRev and $NewRev..."
  Show-UnrealSyncActionPlan $actionPlan
}

if (-not $manual) {
  $rootInteractive = Test-EnvTrue $env:UE_SYNC_ROOT_INTERACTIVE
  $hookHasTty = Test-EnvTrue $env:UE_SYNC_HOOK_HAS_TTY
  $isNonInteractive = $NonInteractive.IsPresent
  $promptRequested = $false
  if (-not $isNonInteractive) {
    if ($rootInteractive -and -not $hookHasTty) {
      Warn "Interactive root command detected but this hook has no terminal access. Skipping UE Sync to avoid an unconfirmed rebuild."
      exit 0
    }
    elseif ($rootInteractive) {
      # Hook layer captured the original git command as interactive.
      # Prefer prompting even if this child process has detached stdio.
      $promptRequested = $true
    }
    elseif (-not (Test-CanPrompt)) {
      $isNonInteractive = $true
    }
  }

  if (-not $isNonInteractive) {
    $actionDescription = if ($shouldRunRegen -and $shouldRunBuild) {
      "regenerating project files and building the editor"
    }
    elseif ($shouldRunRegen) {
      "regenerating project files"
    }
    elseif ($shouldRunBuild) {
      "building the editor"
    }
    else {
      "the selected UE sync action"
    }

    Info "Would you like to proceed with $actionDescription? (y/n)"
    try {
      $response = Read-Host
    }
    catch {
      if ($promptRequested) {
        Warn "Interactive root command detected but prompt could not be shown. Skipping UE Sync to avoid an unconfirmed rebuild."
        exit 0
      }
      $isNonInteractive = $true
      $response = $null
    }

    if ($promptRequested -and [string]::IsNullOrWhiteSpace([string]$response)) {
      Warn "Interactive root command detected but no input was received. Skipping UE Sync to avoid an unconfirmed rebuild."
      exit 0
    }
  }

  if (-not $isNonInteractive) {
    $responseText = ([string]$response).Trim()
    if ($responseText -ne 'y' -and $responseText -ne 'Y') {
      Warn "User chose not to proceed. Exiting."
      exit 0
    }
  }
  else {
    Warn "Non-interactive execution detected; proceeding without confirmation."
  }
}
else {
  $isNonInteractive = $NonInteractive.IsPresent
  if (-not $isNonInteractive) {
    $isNonInteractive = -not (Test-CanPrompt)
  }
}

if ($DryRun) {
  Info "DryRun enabled. Skipping cleanup/regeneration/build."
  exit 0
}

$shouldCleanGeneratedFolders = $shouldRunRegen -or $CleanGenerated -or $CleanSaved -or $CleanCache
if ($shouldCleanGeneratedFolders) {
  Info "Cleaning generated folders..."
  if ($shouldRunRegen -or $CleanGenerated) {
    [void](Remove-IfExists -Path "Binaries" -NonInteractive:$isNonInteractive)
    [void](Remove-IfExists -Path "Intermediate" -NonInteractive:$isNonInteractive)
  }
}
else {
  Info "Skipping generated folder cleanup for build-only sync."
}

if ($CleanCache) { [void](Remove-IfExists -Path "DerivedDataCache" -NonInteractive:$isNonInteractive) }
if ($CleanSaved) { [void](Remove-IfExists -Path "Saved" -NonInteractive:$isNonInteractive) }

$engineRoot = $null
if ($shouldRunBuild) {
  $engineRoot = Resolve-EngineRootForBuild $WorkspacePath $uprojectPath
  Info "Engine (build): $engineRoot"
}

$artifactSnapshot = $null
if ($shouldRunRegen) {
  $artifactSnapshot = New-ProjectFileArtifactSnapshot -ProjectContext $projectContext -WorkspacePathOverride $WorkspacePath
  try {
    Invoke-Regenerate-ProjectFiles $uprojectPath $engineRoot $WorkspacePath
  }
  finally {
    if ($artifactSnapshot) {
      Restore-ProjectFileArtifactSnapshot -Snapshot $artifactSnapshot
    }
  }
}
else {
  Warn "Skipping project file regeneration..."
}

if ($shouldRunBuild) {
  Build-Editor $engineRoot $uprojectPath $projectName $Platform $Config
}
else {
  Warn "Skipping build..."
}

Success "Done."
exit 0
