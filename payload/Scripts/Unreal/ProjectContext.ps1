$script:ProjectContextScriptPath = if ($PSCommandPath) {
  [System.IO.Path]::GetFullPath($PSCommandPath)
}
else {
  $null
}

function Get-RepoRootFromGit {
  $root = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($root)) {
    return $null
  }

  return $root.Trim()
}

function Resolve-RepoRootOrThrow {
  param([string]$RepoRoot)

  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    if (-not (Test-Path -LiteralPath $RepoRoot)) {
      throw "Repo root does not exist: $RepoRoot"
    }
    return (Resolve-Path -LiteralPath $RepoRoot).Path
  }

  $gitRoot = Get-RepoRootFromGit
  if (-not [string]::IsNullOrWhiteSpace($gitRoot)) {
    return $gitRoot
  }

  throw "Could not resolve repo root. Run from inside a git repository or pass -RepoRoot."
}

function Resolve-RepoPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return (Join-Path $RepoRoot $Path)
}

function Get-UProjectFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)

  return @(
    Get-ChildItem -LiteralPath $RepoRoot -Filter "*.uproject" -File -ErrorAction SilentlyContinue |
      Sort-Object Name
  )
}

function Resolve-UProjectPathFromRepo {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$UProjectPath
  )

  if (-not [string]::IsNullOrWhiteSpace($UProjectPath)) {
    $resolved = Resolve-RepoPath -RepoRoot $RepoRoot -Path $UProjectPath
    if (-not (Test-Path -LiteralPath $resolved)) {
      throw ".uproject path does not exist: $resolved"
    }
    return (Resolve-Path -LiteralPath $resolved).Path
  }

  $uprojects = @(Get-UProjectFiles -RepoRoot $RepoRoot)
  if ($uprojects.Count -eq 1) {
    return $uprojects[0].FullName
  }

  $repoLeaf = Split-Path -Path $RepoRoot -Leaf
  $matchingName = @(
    $uprojects |
      Where-Object { $_.BaseName -eq $repoLeaf } |
      Select-Object -First 1
  )
  if ($matchingName.Count -gt 0) {
    return $matchingName[0].FullName
  }

  if ($uprojects.Count -eq 0) {
    throw "No .uproject file found under repo root '$RepoRoot'."
  }

  throw "Multiple .uproject files found under '$RepoRoot'. Pass -UProjectPath explicitly."
}

function Get-UProjectJson {
  param([Parameter(Mandatory)][string]$UProjectPath)

  try {
    return (Get-Content -LiteralPath $UProjectPath -Raw | ConvertFrom-Json)
  }
  catch {
    throw "Could not parse .uproject JSON at '$UProjectPath': $($_.Exception.Message)"
  }
}

function Get-WorkspaceFiles {
  param([Parameter(Mandatory)][string]$RepoRoot)

  return @(
    Get-ChildItem -LiteralPath $RepoRoot -Filter "*.code-workspace" -File -ErrorAction SilentlyContinue |
      Sort-Object Name
  )
}

function Resolve-WorkspacePathFromRepo {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$WorkspacePath,
    [string]$PreferredName
  )

  if (-not [string]::IsNullOrWhiteSpace($WorkspacePath)) {
    $resolved = Resolve-RepoPath -RepoRoot $RepoRoot -Path $WorkspacePath
    if (-not (Test-Path -LiteralPath $resolved)) {
      throw "Workspace path does not exist: $resolved"
    }
    return (Resolve-Path -LiteralPath $resolved).Path
  }

  $workspaces = @(Get-WorkspaceFiles -RepoRoot $RepoRoot)
  if ($workspaces.Count -eq 0) {
    return $null
  }

  if (-not [string]::IsNullOrWhiteSpace($PreferredName)) {
    $preferredMatch = @(
      $workspaces |
        Where-Object { $_.BaseName -eq $PreferredName } |
        Select-Object -First 1
    )
    if ($preferredMatch.Count -gt 0) {
      return $preferredMatch[0].FullName
    }
  }

  $repoLeaf = Split-Path -Path $RepoRoot -Leaf
  $repoMatch = @(
    $workspaces |
      Where-Object { $_.BaseName -eq $repoLeaf } |
      Select-Object -First 1
  )
  if ($repoMatch.Count -gt 0) {
    return $repoMatch[0].FullName
  }

  return $workspaces[0].FullName
}

function Get-ProjectContext {
  param(
    [string]$RepoRoot,
    [string]$UProjectPath,
    [string]$WorkspacePath
  )

  $resolvedRepoRoot = Resolve-RepoRootOrThrow -RepoRoot $RepoRoot
  $resolvedUProjectPath = Resolve-UProjectPathFromRepo -RepoRoot $resolvedRepoRoot -UProjectPath $UProjectPath
  $uprojectJson = Get-UProjectJson -UProjectPath $resolvedUProjectPath
  $projectName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedUProjectPath)
  $modules = @($uprojectJson.Modules)
  $primaryModuleName = if ($modules.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$modules[0].Name)) {
    [string]$modules[0].Name
  }
  else {
    $projectName
  }

  $resolvedWorkspacePath = Resolve-WorkspacePathFromRepo `
    -RepoRoot $resolvedRepoRoot `
    -WorkspacePath $WorkspacePath `
    -PreferredName $projectName

  return [pscustomobject]@{
    RepoRoot          = $resolvedRepoRoot
    RepoName          = Split-Path -Path $resolvedRepoRoot -Leaf
    ProjectName       = $projectName
    UProjectPath      = $resolvedUProjectPath
    UProjectFileName  = Split-Path -Path $resolvedUProjectPath -Leaf
    EngineAssociation = [string]$uprojectJson.EngineAssociation
    Modules           = $modules
    PrimaryModuleName = $primaryModuleName
    ModuleSourceRoot  = Join-Path $resolvedRepoRoot ("Source\" + $primaryModuleName)
    WorkspacePath     = $resolvedWorkspacePath
  }
}

function Add-EngineResolutionAttempt {
  param(
    [System.Collections.Generic.List[string]]$Attempts,
    [string]$Message
  )

  if ($null -ne $Attempts) {
    [void]$Attempts.Add($Message)
  }
}

function Test-EngineRoot {
  param([string]$Root)

  if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
  if (-not (Test-Path -LiteralPath $Root)) { return $false }

  return (Test-Path -LiteralPath (Join-Path $Root "Engine\Build\BatchFiles\Build.bat"))
}

function Get-RegistryPropertyString {
  param(
    [Parameter(Mandatory)][string]$KeyPath,
    [Parameter(Mandatory)][string]$PropertyName
  )

  if (-not (Test-Path -LiteralPath $KeyPath)) { return $null }
  $props = Get-ItemProperty -LiteralPath $KeyPath -ErrorAction SilentlyContinue
  if (-not $props) { return $null }

  $property = $props.PSObject.Properties[$PropertyName]
  if ($property) {
    return [string]$property.Value
  }

  return $null
}

function Get-EngineRootFromWorkspaceContext {
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePath,
    [System.Collections.Generic.List[string]]$Attempts
  )

  $workspaceCandidate = if (-not [string]::IsNullOrWhiteSpace($WorkspacePath)) {
    Resolve-RepoPath -RepoRoot $ProjectContext.RepoRoot -Path $WorkspacePath
  }
  else {
    $ProjectContext.WorkspacePath
  }

  if ([string]::IsNullOrWhiteSpace($workspaceCandidate)) {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace path unavailable"
    return $null
  }

  if (-not (Test-Path -LiteralPath $workspaceCandidate)) {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace not found: '$workspaceCandidate'"
    return $null
  }

  try {
    $workspaceJson = Get-Content -LiteralPath $workspaceCandidate -Raw | ConvertFrom-Json
  }
  catch {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace parse failed: $($_.Exception.Message)"
    return $null
  }

  $folders = @($workspaceJson.folders)
  if ($folders.Count -eq 0) {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace has no folders[] entries"
    return $null
  }

  $preferred = @(
    $folders |
      Where-Object { $_.name -and $_.name -match '^UE' } |
      Select-Object -First 1
  )
  if ($preferred.Count -gt 0) {
    $preferredPath = Resolve-RepoPath -RepoRoot $ProjectContext.RepoRoot -Path $preferred[0].path
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace preferred UE folder '$($preferred[0].name)' -> '$preferredPath'"
    if (Test-EngineRoot -Root $preferredPath) {
      return $preferredPath
    }
  }

  foreach ($folder in $folders) {
    $candidatePath = Resolve-RepoPath -RepoRoot $ProjectContext.RepoRoot -Path $folder.path
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { continue }

    Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace folder '$($folder.name)' -> '$candidatePath'"
    if (Test-EngineRoot -Root $candidatePath) {
      return $candidatePath
    }

    $engineIndex = $candidatePath.ToLowerInvariant().IndexOf("\engine\")
    if ($engineIndex -ge 0) {
      $engineRoot = $candidatePath.Substring(0, $engineIndex)
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace folder points inside Engine; trying '$engineRoot'"
      if (Test-EngineRoot -Root $engineRoot) {
        return $engineRoot
      }
    }

    if ($candidatePath.ToLowerInvariant().EndsWith("\engine")) {
      $engineParent = Split-Path -Path $candidatePath -Parent
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "workspace folder points to Engine dir; trying '$engineParent'"
      if (Test-EngineRoot -Root $engineParent) {
        return $engineParent
      }
    }
  }

  return $null
}

function Get-EngineRootFromRegistryAssociation {
  param(
    [string]$EngineAssociation,
    [System.Collections.Generic.List[string]]$Attempts
  )

  if ([string]::IsNullOrWhiteSpace($EngineAssociation)) {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "EngineAssociation unavailable"
    return $null
  }

  $hkcuBuilds = "Registry::HKEY_CURRENT_USER\SOFTWARE\Epic Games\Unreal Engine\Builds"
  $hkcuRoot = Get-RegistryPropertyString -KeyPath $hkcuBuilds -PropertyName $EngineAssociation
  if (-not [string]::IsNullOrWhiteSpace($hkcuRoot)) {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "HKCU Builds[$EngineAssociation] -> '$hkcuRoot'"
    if (Test-EngineRoot -Root $hkcuRoot) {
      return $hkcuRoot
    }
  }
  else {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "HKCU Builds[$EngineAssociation] not present"
  }

  foreach ($candidate in @(
      "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\EpicGames\Unreal Engine\$EngineAssociation",
      "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\EpicGames\Unreal Engine\$EngineAssociation"
    )) {
    $installedDirectory = Get-RegistryPropertyString -KeyPath $candidate -PropertyName "InstalledDirectory"
    if ([string]::IsNullOrWhiteSpace($installedDirectory)) {
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "registry key missing InstalledDirectory: $candidate"
      continue
    }

    Add-EngineResolutionAttempt -Attempts $Attempts -Message "registry InstalledDirectory -> '$installedDirectory'"
    if (Test-EngineRoot -Root $installedDirectory) {
      return $installedDirectory
    }
  }

  return $null
}

function Get-CommonEngineInstallRoots {
  $roots = New-Object System.Collections.Generic.List[string]
  $customRoots = [string](Get-Item -Path "Env:UE_ENGINE_COMMON_INSTALL_ROOTS" -ErrorAction SilentlyContinue).Value
  if (-not [string]::IsNullOrWhiteSpace($customRoots)) {
    foreach ($root in @($customRoots -split [regex]::Escape([System.IO.Path]::PathSeparator))) {
      $trimmed = $root.Trim()
      if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not ($roots -contains $trimmed)) {
        [void]$roots.Add($trimmed)
      }
    }
  }

  foreach ($root in @(
      "C:\Program Files\Epic Games",
      "C:\Program Files (x86)\Epic Games"
    )) {
    if (-not ($roots -contains $root)) {
      [void]$roots.Add($root)
    }
  }

  return @($roots.ToArray())
}

function Get-EngineFolderCandidates {
  param([string]$EngineAssociation)

  $folderCandidates = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($EngineAssociation)) {
    $trimmedAssociation = $EngineAssociation.Trim()
    if ($trimmedAssociation -match '^UE_') {
      [void]$folderCandidates.Add($trimmedAssociation)
    }
    elseif ($trimmedAssociation -match '^\d+(\.\d+)*$') {
      [void]$folderCandidates.Add("UE_$trimmedAssociation")
    }
  }

  return @($folderCandidates.ToArray())
}

function Get-EngineRootFromCommonInstalls {
  param(
    [string]$EngineAssociation,
    [System.Collections.Generic.List[string]]$Attempts
  )

  $disableCommonScan = [string](Get-Item -Path "Env:UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN" -ErrorAction SilentlyContinue).Value
  if (-not [string]::IsNullOrWhiteSpace($disableCommonScan) -and $disableCommonScan.Trim().ToLowerInvariant() -in @("1", "true", "yes")) {
    Add-EngineResolutionAttempt -Attempts $Attempts -Message "common install root scan disabled by UE_ENGINE_DISABLE_COMMON_INSTALL_SCAN"
    return $null
  }

  $folderCandidates = @(Get-EngineFolderCandidates -EngineAssociation $EngineAssociation)

  foreach ($installRoot in @(Get-CommonEngineInstallRoots)) {
    if (-not (Test-Path -LiteralPath $installRoot)) {
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "common install root missing: $installRoot"
      continue
    }

    foreach ($folderName in $folderCandidates) {
      $candidate = Join-Path $installRoot $folderName
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "common install candidate: '$candidate'"
      if (Test-EngineRoot -Root $candidate) {
        return $candidate
      }
    }

    $installed = @(
      Get-ChildItem -LiteralPath $installRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "UE_*" } |
        Sort-Object Name -Descending
    )
    foreach ($engineDir in $installed) {
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "scanning installed engine dir: '$($engineDir.FullName)'"
      if (Test-EngineRoot -Root $engineDir.FullName) {
        return $engineDir.FullName
      }
    }
  }

  return $null
}

function Resolve-UnrealEngineRoot {
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePath,
    [System.Collections.Generic.List[string]]$Attempts
  )

  $workspaceRoot = Get-EngineRootFromWorkspaceContext `
    -ProjectContext $ProjectContext `
    -WorkspacePath $WorkspacePath `
    -Attempts $Attempts
  if (-not [string]::IsNullOrWhiteSpace($workspaceRoot)) {
    return $workspaceRoot
  }

  foreach ($envVar in @("UE_ENGINE_DIR", "UE_ENGINE_ROOT", "UNREAL_ENGINE_DIR")) {
    $candidate = [string](Get-Item -Path "Env:$envVar" -ErrorAction SilentlyContinue).Value
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      Add-EngineResolutionAttempt -Attempts $Attempts -Message "$envVar is unset"
      continue
    }

    Add-EngineResolutionAttempt -Attempts $Attempts -Message "$envVar -> '$candidate'"
    if (Test-EngineRoot -Root $candidate) {
      return $candidate
    }
  }

  $registryRoot = Get-EngineRootFromRegistryAssociation `
    -EngineAssociation $ProjectContext.EngineAssociation `
    -Attempts $Attempts
  if (-not [string]::IsNullOrWhiteSpace($registryRoot)) {
    return $registryRoot
  }

  return (Get-EngineRootFromCommonInstalls -EngineAssociation $ProjectContext.EngineAssociation -Attempts $Attempts)
}

function Resolve-UnrealEditorPath {
  param(
    [Parameter(Mandatory)]$ProjectContext,
    [string]$WorkspacePath,
    [string]$UnrealEditorPath,
    [System.Collections.Generic.List[string]]$Attempts
  )

  if (-not [string]::IsNullOrWhiteSpace($UnrealEditorPath)) {
    $explicitEditor = Resolve-RepoPath -RepoRoot $ProjectContext.RepoRoot -Path $UnrealEditorPath
    if (-not (Test-Path -LiteralPath $explicitEditor)) {
      throw "UnrealEditor.exe path does not exist: $explicitEditor"
    }
    return (Resolve-Path -LiteralPath $explicitEditor).Path
  }

  $engineRoot = Resolve-UnrealEngineRoot -ProjectContext $ProjectContext -WorkspacePath $WorkspacePath -Attempts $Attempts
  if ([string]::IsNullOrWhiteSpace($engineRoot)) {
    return $null
  }

  $editorPath = Join-Path $engineRoot "Engine\Binaries\Win64\UnrealEditor.exe"
  if (Test-Path -LiteralPath $editorPath) {
    return (Resolve-Path -LiteralPath $editorPath).Path
  }

  Add-EngineResolutionAttempt -Attempts $Attempts -Message "UnrealEditor.exe missing under '$engineRoot'"
  return $null
}
