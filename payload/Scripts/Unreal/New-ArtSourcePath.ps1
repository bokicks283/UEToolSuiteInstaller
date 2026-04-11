[CmdletBinding()]
param(
  [string]$RepoRoot,
  [string]$ArtSourceRelativePath = "ArtSource"
)

$ErrorActionPreference = "Stop"

$script:RequiredArtItemDirs = @("Source", "Textures", "Exports")
$script:ReservedFolderNames = @("_Template", "Source", "Textures", "Exports")

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

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $Path
  }

  return ($Path -replace '\\', '/')
}

function Get-RepoRootPath {
  param([string]$ExplicitRepoRoot)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    if (-not (Test-Path -LiteralPath $ExplicitRepoRoot)) {
      throw "Provided RepoRoot does not exist: $(Convert-ToUnixPath -Path $ExplicitRepoRoot)"
    }
    return (Resolve-Path -LiteralPath $ExplicitRepoRoot).Path
  }

  $root = (git rev-parse --show-toplevel 2>$null | Select-Object -First 1).Trim()
  if ([string]::IsNullOrWhiteSpace($root)) {
    throw "Could not resolve repository root. Run from inside the repo or pass -RepoRoot."
  }
  return $root
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

  $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
  $path = [System.IO.Path]::GetFullPath($FullPath)

  if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return (Convert-ToUnixPath -Path $path.Substring($root.Length).TrimStart('\'))
  }
  return (Convert-ToUnixPath -Path $path)
}

function Ensure-TemplateShape {
  param([Parameter(Mandatory)][string]$TemplatePath)

  if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template path does not exist: $(Convert-ToUnixPath -Path $TemplatePath)"
  }

  foreach ($required in $script:RequiredArtItemDirs) {
    $requiredPath = Join-Path $TemplatePath $required
    if (Test-Path -LiteralPath $requiredPath) {
      $item = Get-Item -LiteralPath $requiredPath -ErrorAction Stop
      if (-not $item.PSIsContainer) {
        throw "Template path '$(Convert-ToUnixPath -Path $requiredPath)' exists but is not a directory."
      }
      continue
    }

    New-Item -ItemType Directory -Path $requiredPath -Force | Out-Null
    Write-WarnLine "Template was missing '$required'. Added directory at $(Get-RelativeDisplayPath -RootPath $TemplatePath -FullPath $requiredPath)."
  }
}

function Merge-TemplateIntoCanonical {
  param(
    [Parameter(Mandatory)][string]$SourceTemplatePath,
    [Parameter(Mandatory)][string]$CanonicalTemplatePath
  )

  $sourceRoot = [System.IO.Path]::GetFullPath($SourceTemplatePath).TrimEnd('\')
  $destRoot = [System.IO.Path]::GetFullPath($CanonicalTemplatePath).TrimEnd('\')

  $sourceDirs = Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
    Sort-Object FullName
  foreach ($dir in $sourceDirs) {
    $relative = $dir.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $destDir = Join-Path $destRoot $relative
    if (-not (Test-Path -LiteralPath $destDir)) {
      New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
  }

  $sourceFiles = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force -ErrorAction SilentlyContinue
  foreach ($file in $sourceFiles) {
    $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
    $destFile = Join-Path $destRoot $relative
    $destDir = Split-Path -Path $destFile -Parent
    if (-not (Test-Path -LiteralPath $destDir)) {
      New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force
  }
}

function Ensure-CanonicalTemplate {
  param([Parameter(Mandatory)][string]$ArtSourceRoot)

  $canonicalTemplatePath = Join-Path $ArtSourceRoot "_Template"
  $domainTemplatePaths = @(
    Get-ChildItem -LiteralPath $ArtSourceRoot -Directory -ErrorAction Stop |
    Where-Object { $_.Name -ne "_Template" } |
    ForEach-Object { Join-Path $_.FullName "_Template" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Sort-Object
  )

  if (-not (Test-Path -LiteralPath $canonicalTemplatePath)) {
    if ($domainTemplatePaths.Count -eq 0) {
      throw "No _Template directory found. Expected either '$(Convert-ToUnixPath -Path $canonicalTemplatePath)' or a domain-level _Template."
    }

    $seedTemplatePath = $domainTemplatePaths[0]
    Write-InfoLine "Creating canonical template at ArtSource/_Template from $(Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $seedTemplatePath)."
    Copy-Item -LiteralPath $seedTemplatePath -Destination $canonicalTemplatePath -Recurse -Force
  }
  else {
    Write-InfoLine "Using existing canonical template: $(Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $canonicalTemplatePath)."
  }

  foreach ($templatePath in $domainTemplatePaths) {
    Merge-TemplateIntoCanonical -SourceTemplatePath $templatePath -CanonicalTemplatePath $canonicalTemplatePath
    Remove-Item -LiteralPath $templatePath -Recurse -Force
    Write-InfoLine "Removed duplicate template: $(Get-RelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $templatePath)."
  }

  Ensure-TemplateShape -TemplatePath $canonicalTemplatePath
  return $canonicalTemplatePath
}

function Assert-AvailableFolderName {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$ParentPath
  )

  $trimmed = $Name.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    throw "Name cannot be empty."
  }

  if ($trimmed -ne $Name) {
    throw "Name cannot start or end with spaces."
  }

  foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
    if ($trimmed.Contains($invalidChar)) {
      throw "Name '$trimmed' contains invalid character '$invalidChar'."
    }
  }

  if ($script:ReservedFolderNames -contains $trimmed) {
    throw "Name '$trimmed' is reserved and cannot be used."
  }

  $targetPath = Join-Path $ParentPath $trimmed
  if (Test-Path -LiteralPath $targetPath) {
    throw "Path already exists: $(Convert-ToUnixPath -Path $targetPath)"
  }

  return $trimmed
}

function New-DirectoryChecked {
  param(
    [Parameter(Mandatory)][string]$ParentPath,
    [Parameter(Mandatory)][string]$Name
  )

  $safeName = Assert-AvailableFolderName -Name $Name -ParentPath $ParentPath
  $path = Join-Path $ParentPath $safeName
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
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

  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }

  $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.PSIsContainer) {
    return $false
  }

  foreach ($required in $script:RequiredArtItemDirs) {
    $requiredPath = Join-Path $Path $required
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      return $false
    }

    $requiredItem = Get-Item -LiteralPath $requiredPath -ErrorAction SilentlyContinue
    if (-not $requiredItem -or -not $requiredItem.PSIsContainer) {
      return $false
    }
  }

  return $true
}

function Get-NavigableChildDirectories {
  param([Parameter(Mandatory)][string]$ParentPath)

  return @(
    Get-ChildItem -LiteralPath $ParentPath -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "_Template" } |
    Where-Object { -not (Test-IsArtItemDirectory -Path $_.FullName) } |
    Sort-Object Name
  )
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

  if (Test-Path -LiteralPath $DestinationPath) {
    throw "Art item path already exists: $(Convert-ToUnixPath -Path $DestinationPath)"
  }

  Copy-Item -LiteralPath $TemplatePath -Destination $DestinationPath -Recurse -Force
  Ensure-TemplateShape -TemplatePath $DestinationPath
  return $DestinationPath
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
