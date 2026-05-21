[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string]$ArtSourceRelativePath = "ArtSource"
)

$ErrorActionPreference = "Stop"

$script:ArtToolsScriptsRoot = Split-Path -Parent $PSScriptRoot
$runtimeHelperPath = Join-Path $script:ArtToolsScriptsRoot "UETools\UEToolSuite.Runtime.ps1"
if (Test-Path -LiteralPath $runtimeHelperPath -PathType Leaf) {
  . $runtimeHelperPath
}
else {
  throw "Runtime helper not found: $runtimeHelperPath"
}
Set-UEToolSuiteRuntimeContext -ScriptsRoot $script:ArtToolsScriptsRoot -StateKey "new-artsource-path"

if (-not (Import-UEToolSuiteCoreModule)) {
  throw "UETools module entry not found under $script:ArtToolsScriptsRoot\UETools."
}

$artDomainModulePath = Join-Path $script:ArtToolsScriptsRoot "UETools\UEToolSuite.Art.psm1"
if (-not (Test-Path -LiteralPath $artDomainModulePath -PathType Leaf)) {
  throw "Art domain module not found: $artDomainModulePath"
}
Import-Module -Name $artDomainModulePath -Force

function Write-InfoLine([string]$Message) {
  Write-Host "[ArtSource] $Message" -ForegroundColor Cyan
}

function Write-WarnLine([string]$Message) {
  Write-Host "[ArtSource] $Message" -ForegroundColor Yellow
}

function Write-OkLine([string]$Message) {
  Write-Host "[ArtSource] $Message" -ForegroundColor Green
}

function Write-ErrLine([string]$Message) {
  Write-Host "[ArtSource] $Message" -ForegroundColor Red
}

function Convert-ToUnixPath {
  param([string]$Path)
  return (Convert-UEToolSuiteArtToUnixPath -Path $Path)
}

function Get-RepoRootPath {
  param([string]$ExplicitRepoRoot)
  return (Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $script:ArtToolsScriptsRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "New-ArtSourcePath.ps1")
}

function Resolve-ArtSourceRootPath {
  param(
    [Parameter(Mandatory)][string]$RepoRootPath,
    [Parameter(Mandatory)][string]$ArtSourcePathInput
  )

  $candidate = $ArtSourcePathInput
  if (-not [System.IO.Path]::IsPathRooted($candidate)) {
    $candidate = Join-Path $RepoRootPath $candidate
  }

  if (-not (Test-Path -LiteralPath $candidate)) {
    throw "ArtSource path does not exist: $(Convert-ToUnixPath -Path $candidate)"
  }

  return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-RelativeDisplayPath {
  param(
    [Parameter(Mandatory)][string]$RootPath,
    [Parameter(Mandatory)][string]$FullPath
  )
  return (Get-UEToolSuiteArtRelativeDisplayPath -RootPath $RootPath -FullPath $FullPath)
}

function Ensure-TemplateShape {
  param([Parameter(Mandatory)][string]$TemplatePath)

  $requiredDirs = @(Get-UEToolSuiteArtRequiredItemDirectories)
  $missingDirs = @()
  foreach ($required in $requiredDirs) {
    $requiredPath = Join-Path $TemplatePath $required
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      $missingDirs += $requiredPath
    }
  }

  Ensure-UEToolSuiteArtTemplateShape -TemplatePath $TemplatePath

  foreach ($requiredPath in $missingDirs) {
    $requiredName = Split-Path -Path $requiredPath -Leaf
    Write-WarnLine "Template was missing '$requiredName'. Added directory at $(Get-RelativeDisplayPath -RootPath $TemplatePath -FullPath $requiredPath)."
  }
}

function Merge-TemplateIntoCanonical {
  param(
    [Parameter(Mandatory)][string]$SourceTemplatePath,
    [Parameter(Mandatory)][string]$CanonicalTemplatePath
  )
  Merge-UEToolSuiteArtTemplateIntoCanonical -SourceTemplatePath $SourceTemplatePath -CanonicalTemplatePath $CanonicalTemplatePath
}

function Ensure-CanonicalTemplate {
  param([Parameter(Mandatory)][string]$ArtSourceRoot)
  return (Ensure-UEToolSuiteArtCanonicalTemplate -ArtSourceRoot $ArtSourceRoot)
}

function Assert-AvailableFolderName {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$ParentPath
  )
  return (Assert-UEToolSuiteArtAvailableFolderName -Name $Name -ParentPath $ParentPath)
}

function New-DirectoryChecked {
  param(
    [Parameter(Mandatory)][string]$ParentPath,
    [Parameter(Mandatory)][string]$Name
  )
  return (New-UEToolSuiteArtDirectoryChecked -ParentPath $ParentPath -Name $Name)
}

function Read-UniqueFolderName {
  param(
    [Parameter(Mandatory)][string]$Prompt,
    [Parameter(Mandatory)][string]$ParentPath
  )

  while ($true) {
    $raw = [string](Read-Host $Prompt)
    try {
      return (Assert-AvailableFolderName -Name $raw -ParentPath $ParentPath)
    }
    catch {
      Write-WarnLine $_.Exception.Message
    }
  }
}

function Read-MenuChoice {
  param(
    [Parameter(Mandatory)][string]$Prompt,
    [Parameter(Mandatory)][int]$Min,
    [Parameter(Mandatory)][int]$Max
  )

  while ($true) {
    $raw = ([string](Read-Host $Prompt)).Trim()
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge $Min -and $parsed -le $Max) {
      return $parsed
    }

    Write-WarnLine "Enter a number between $Min and $Max."
  }
}

function Read-YesNo {
  param([Parameter(Mandatory)][string]$Prompt)

  while ($true) {
    $raw = ([string](Read-Host $Prompt)).Trim().ToLowerInvariant()
    switch ($raw) {
      "y" { return $true }
      "yes" { return $true }
      "n" { return $false }
      "no" { return $false }
      default { Write-WarnLine "Enter 'y' or 'n'." }
    }
  }
}

function Get-DomainDirectories {
  param([Parameter(Mandatory)][string]$ArtSourceRoot)

  return @(
    Get-ChildItem -LiteralPath $ArtSourceRoot -Directory -ErrorAction Stop |
    Where-Object { $_.Name -ne "_Template" } |
    Sort-Object Name
  )
}

function Test-IsArtItemDirectory {
  param([Parameter(Mandatory)][string]$Path)
  return (Test-UEToolSuiteArtItemDirectory -Path $Path)
}

function Get-NavigableChildDirectories {
  param([Parameter(Mandatory)][string]$ParentPath)
  return @(Get-UEToolSuiteArtNavigableChildDirectories -ParentPath $ParentPath)
}

function Select-OrCreateDomainPath {
  param([Parameter(Mandatory)][string]$ArtSourceRoot)

  $domains = Get-DomainDirectories -ArtSourceRoot $ArtSourceRoot

  while ($true) {
    Write-Host ""
    Write-InfoLine "Select an ArtSource domain:"
    if ($domains.Count -gt 0) {
      for ($i = 0; $i -lt $domains.Count; $i++) {
        Write-Host ("{0}) {1}" -f ($i + 1), $domains[$i].Name)
      }
    }
    else {
      Write-WarnLine "No domains currently exist under ArtSource."
    }

    $createOption = $domains.Count + 1
    $cancelOption = $createOption + 1
    Write-Host ("{0}) Create new domain" -f $createOption)
    Write-Host ("{0}) Cancel" -f $cancelOption)

    $choice = Read-MenuChoice -Prompt "Choose option" -Min 1 -Max $cancelOption
    if ($choice -eq $cancelOption) {
      return $null
    }

    if ($choice -eq $createOption) {
      $name = Read-UniqueFolderName -Prompt "Enter new domain name" -ParentPath $ArtSourceRoot
      $domainPath = New-DirectoryChecked -ParentPath $ArtSourceRoot -Name $name
      Write-OkLine "Created domain: $(Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $domainPath)"
      return $domainPath
    }

    return $domains[$choice - 1].FullName
  }
}

function New-ArtItemFromTemplate {
  param(
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$DestinationPath
  )
  return (New-UEToolSuiteArtItemFromTemplate -TemplatePath $TemplatePath -DestinationPath $DestinationPath)
}

function Invoke-RecursiveArtItemPrompt {
  param(
    [Parameter(Mandatory)][string]$StartPath,
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$ArtSourceRoot
  )

  $start = [System.IO.Path]::GetFullPath($StartPath).TrimEnd('\')
  $currentPath = $start

  while ($true) {
    $currentDisplay = Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $currentPath
    if ([string]::IsNullOrWhiteSpace($currentDisplay)) { $currentDisplay = "." }
    $containerDirs = Get-NavigableChildDirectories -ParentPath $currentPath

    Write-Host ""
    Write-InfoLine "Current folder: $currentDisplay"
    $canGoUp = ([System.IO.Path]::GetFullPath($currentPath).TrimEnd('\') -ne $start)

    $menu = @()

    foreach ($dir in $containerDirs) {
      $menu += [pscustomobject]@{
        Label = $dir.Name
        Action = "enter_existing"
        Path = $dir.FullName
      }
    }

    $menu += [pscustomobject]@{
      Label = "Create new folder"
      Action = "create_container"
      Path = $null
    }

    $menu += [pscustomobject]@{
      Label = "Create art item"
      Action = "create_art_item"
      Path = $null
    }

    $menu += [pscustomobject]@{
      Label = "Go Back"
      Action = "go_back"
      Path = $null
    }

    $menu += [pscustomobject]@{
      Label = "Cancel"
      Action = "cancel"
      Path = $null
    }

    for ($i = 0; $i -lt $menu.Count; $i++) {
      Write-Host ("{0}) {1}" -f ($i + 1), $menu[$i].Label)
    }

    $choice = Read-MenuChoice -Prompt "Choose option" -Min 1 -Max $menu.Count
    $selected = $menu[$choice - 1]

    switch ($selected.Action) {
      "enter_existing" {
        $currentPath = $selected.Path
        continue
      }
      "create_container" {
        $containerName = Read-UniqueFolderName -Prompt "Enter nested folder name" -ParentPath $currentPath
        $currentPath = New-DirectoryChecked -ParentPath $currentPath -Name $containerName
        Write-OkLine "Created folder: $(Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $currentPath)"
        continue
      }
      "create_art_item" {
        $artItemName = Read-UniqueFolderName -Prompt "Enter new art item folder name" -ParentPath $currentPath
        $artItemPath = Join-Path $currentPath $artItemName
        $createdPath = New-ArtItemFromTemplate -TemplatePath $TemplatePath -DestinationPath $artItemPath
        Write-OkLine "Created art item folder: $(Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $createdPath)"
        return $createdPath
      }
      "go_back" {
        if ($canGoUp) {
          $currentPath = Split-Path -Path $currentPath -Parent
          continue
        }

        return $null
      }
      "cancel" {
        throw "Canceled by user."
      }
      default {
        throw "Unknown menu action: $($selected.Action)"
      }
    }
  }
}

function Invoke-ArtSourcePathWizard {
  param(
    [string]$RepoRootInput,
    [string]$ArtSourcePathInput
  )

  $repoRootPath = Get-RepoRootPath -ExplicitRepoRoot $RepoRootInput
  $artSourceRoot = Resolve-ArtSourceRootPath -RepoRootPath $repoRootPath -ArtSourcePathInput $ArtSourcePathInput

  Write-InfoLine "Repo root: $(Convert-ToUnixPath -Path $repoRootPath)"
  Write-InfoLine "ArtSource: $(Convert-ToUnixPath -Path $artSourceRoot)"

  $templatePath = Ensure-CanonicalTemplate -ArtSourceRoot $artSourceRoot
  Write-OkLine "Canonical template ready: $(Get-RelativeDisplayPath -RootPath $artSourceRoot -FullPath $templatePath)"

  while ($true) {
    $domainPath = Select-OrCreateDomainPath -ArtSourceRoot $artSourceRoot
    if ($null -eq $domainPath) {
      Write-InfoLine "Canceled by user."
      break
    }

    $createdPath = Invoke-RecursiveArtItemPrompt -StartPath $domainPath -TemplatePath $templatePath -ArtSourceRoot $artSourceRoot

    if ($null -eq $createdPath) {
      continue
    }

    $again = Read-YesNo -Prompt "Create another art item path? (y/n)"
    if (-not $again) {
      Write-OkLine "Done."
      break
    }
  }
}

if ($MyInvocation.InvocationName -ne ".") {
  try {
    Invoke-ArtSourcePathWizard -RepoRootInput $RepoRoot -ArtSourcePathInput $ArtSourceRelativePath
    exit 0
  }
  catch {
    Write-ErrLine $_.Exception.Message
    exit 1
  }
}
