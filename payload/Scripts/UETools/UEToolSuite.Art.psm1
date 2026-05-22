function Get-UEToolSuiteArtRequiredItemDirectories {
  [CmdletBinding()]
  param()
  return @("Source", "Textures", "Exports")
}

function Get-UEToolSuiteArtReservedFolderNames {
  [CmdletBinding()]
  param()
  return @("_Template", "Source", "Textures", "Exports")
}

function Convert-UEToolSuiteArtToUnixPath {
  [CmdletBinding()]
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $Path
  }

  return ($Path -replace '\\', '/')
}

function Get-UEToolSuiteArtRelativeDisplayPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RootPath,
    [Parameter(Mandatory)][string]$FullPath
  )

  $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
  $path = [System.IO.Path]::GetFullPath($FullPath)
  if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return (Convert-UEToolSuiteArtToUnixPath -Path $path.Substring($root.Length).TrimStart('\'))
  }

  return (Convert-UEToolSuiteArtToUnixPath -Path $path)
}

function Assert-UEToolSuiteArtAvailableFolderName {
  [CmdletBinding()]
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

  $reserved = @(Get-UEToolSuiteArtReservedFolderNames)
  if ($reserved -contains $trimmed) {
    throw "Name '$trimmed' is reserved and cannot be used."
  }

  $targetPath = Join-Path $ParentPath $trimmed
  if (Test-Path -LiteralPath $targetPath) {
    throw "Path already exists: $(Convert-UEToolSuiteArtToUnixPath -Path $targetPath)"
  }

  return $trimmed
}

function New-UEToolSuiteArtDirectoryChecked {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$ParentPath,
    [Parameter(Mandatory)][string]$Name
  )

  $safeName = Assert-UEToolSuiteArtAvailableFolderName -Name $Name -ParentPath $ParentPath
  $path = Join-Path $ParentPath $safeName
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  return $path
}

function Test-UEToolSuiteArtItemDirectory {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }

  $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $item -or -not $item.PSIsContainer) {
    return $false
  }

  foreach ($required in @(Get-UEToolSuiteArtRequiredItemDirectories)) {
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

function Get-UEToolSuiteArtNavigableChildDirectories {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ParentPath)

  return @(
    Get-ChildItem -LiteralPath $ParentPath -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -ne "_Template" } |
      Where-Object { -not (Test-UEToolSuiteArtItemDirectory -Path $_.FullName) } |
      Sort-Object Name
  )
}

function Merge-UEToolSuiteArtTemplateIntoCanonical {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$SourceTemplatePath,
    [Parameter(Mandatory)][string]$CanonicalTemplatePath
  )

  $sourceRoot = [System.IO.Path]::GetFullPath($SourceTemplatePath).TrimEnd('\')
  $destRoot = [System.IO.Path]::GetFullPath($CanonicalTemplatePath).TrimEnd('\')

  $sourceDirs = Get-ChildItem -LiteralPath $sourceRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName
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

function Ensure-UEToolSuiteArtTemplateShape {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$TemplatePath)

  if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template path does not exist: $(Convert-UEToolSuiteArtToUnixPath -Path $TemplatePath)"
  }

  foreach ($required in @(Get-UEToolSuiteArtRequiredItemDirectories)) {
    $requiredPath = Join-Path $TemplatePath $required
    if (-not (Test-Path -LiteralPath $requiredPath)) {
      New-Item -ItemType Directory -Path $requiredPath -Force | Out-Null
      continue
    }

    $item = Get-Item -LiteralPath $requiredPath -ErrorAction Stop
    if (-not $item.PSIsContainer) {
      throw "Template path '$(Convert-UEToolSuiteArtToUnixPath -Path $requiredPath)' exists but is not a directory."
    }
  }
}

function Ensure-UEToolSuiteArtCanonicalTemplate {
  [CmdletBinding()]
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
      throw "No _Template directory found. Expected either '$(Convert-UEToolSuiteArtToUnixPath -Path $canonicalTemplatePath)' or a domain-level _Template."
    }

    Copy-Item -LiteralPath $domainTemplatePaths[0] -Destination $canonicalTemplatePath -Recurse -Force
  }

  foreach ($templatePath in $domainTemplatePaths) {
    Merge-UEToolSuiteArtTemplateIntoCanonical -SourceTemplatePath $templatePath -CanonicalTemplatePath $canonicalTemplatePath
    Remove-Item -LiteralPath $templatePath -Recurse -Force
  }

  Ensure-UEToolSuiteArtTemplateShape -TemplatePath $canonicalTemplatePath
  return $canonicalTemplatePath
}

function New-UEToolSuiteArtItemFromTemplate {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$DestinationPath
  )

  if (Test-Path -LiteralPath $DestinationPath) {
    throw "Art item path already exists: $(Convert-UEToolSuiteArtToUnixPath -Path $DestinationPath)"
  }

  Copy-Item -LiteralPath $TemplatePath -Destination $DestinationPath -Recurse -Force
  Ensure-UEToolSuiteArtTemplateShape -TemplatePath $DestinationPath
  return $DestinationPath
}

function Write-UEToolSuiteArtInfoLine {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "[ArtSource] $Message" -ForegroundColor Cyan
}

function Write-UEToolSuiteArtWarnLine {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "[ArtSource] $Message" -ForegroundColor Yellow
}

function Write-UEToolSuiteArtOkLine {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "[ArtSource] $Message" -ForegroundColor Green
}

function Resolve-UEToolSuiteArtSourceRootPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ArtSourcePathInput
  )

  $candidate = $ArtSourcePathInput
  if (-not [System.IO.Path]::IsPathRooted($candidate)) {
    $candidate = Join-Path $RepoRoot $candidate
  }

  if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
    throw "ArtSource path does not exist: $(Convert-UEToolSuiteArtToUnixPath -Path $candidate)"
  }

  return (Resolve-Path -LiteralPath $candidate).Path
}

function Read-UEToolSuiteArtMenuChoice {
  [CmdletBinding()]
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

    Write-UEToolSuiteArtWarnLine "Enter a number between $Min and $Max."
  }
}

function Read-UEToolSuiteArtYesNo {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Prompt)

  while ($true) {
    $raw = ([string](Read-Host $Prompt)).Trim().ToLowerInvariant()
    switch ($raw) {
      "y" { return $true }
      "yes" { return $true }
      "n" { return $false }
      "no" { return $false }
      default { Write-UEToolSuiteArtWarnLine "Enter 'y' or 'n'." }
    }
  }
}

function Read-UEToolSuiteArtUniqueFolderName {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Prompt,
    [Parameter(Mandatory)][string]$ParentPath
  )

  while ($true) {
    $raw = [string](Read-Host $Prompt)
    try {
      return (Assert-UEToolSuiteArtAvailableFolderName -Name $raw -ParentPath $ParentPath)
    }
    catch {
      Write-UEToolSuiteArtWarnLine $_.Exception.Message
    }
  }
}

function Get-UEToolSuiteArtDomainDirectories {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ArtSourceRoot)

  return @(
    Get-ChildItem -LiteralPath $ArtSourceRoot -Directory -ErrorAction Stop |
      Where-Object { $_.Name -ne "_Template" } |
      Sort-Object Name
  )
}

function Select-UEToolSuiteArtDomainPath {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ArtSourceRoot)

  $domains = Get-UEToolSuiteArtDomainDirectories -ArtSourceRoot $ArtSourceRoot

  while ($true) {
    Write-Host ""
    Write-UEToolSuiteArtInfoLine "Select an ArtSource domain:"
    if ($domains.Count -gt 0) {
      for ($i = 0; $i -lt $domains.Count; $i++) {
        Write-Host ("{0}) {1}" -f ($i + 1), $domains[$i].Name)
      }
    }
    else {
      Write-UEToolSuiteArtWarnLine "No domains currently exist under ArtSource."
    }

    $createOption = $domains.Count + 1
    $cancelOption = $createOption + 1
    Write-Host ("{0}) Create new domain" -f $createOption)
    Write-Host ("{0}) Cancel" -f $cancelOption)

    $choice = Read-UEToolSuiteArtMenuChoice -Prompt "Choose option" -Min 1 -Max $cancelOption
    if ($choice -eq $cancelOption) {
      return $null
    }

    if ($choice -eq $createOption) {
      $name = Read-UEToolSuiteArtUniqueFolderName -Prompt "Enter new domain name" -ParentPath $ArtSourceRoot
      $domainPath = New-UEToolSuiteArtDirectoryChecked -ParentPath $ArtSourceRoot -Name $name
      Write-UEToolSuiteArtOkLine "Created domain: $(Get-UEToolSuiteArtRelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $domainPath)"
      return $domainPath
    }

    return $domains[$choice - 1].FullName
  }
}

function Invoke-UEToolSuiteArtItemPrompt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$StartPath,
    [Parameter(Mandatory)][string]$TemplatePath,
    [Parameter(Mandatory)][string]$ArtSourceRoot
  )

  $start = [System.IO.Path]::GetFullPath($StartPath).TrimEnd('\')
  $currentPath = $start

  while ($true) {
    $currentDisplay = Get-UEToolSuiteArtRelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $currentPath
    if ([string]::IsNullOrWhiteSpace($currentDisplay)) { $currentDisplay = "." }
    $containerDirs = Get-UEToolSuiteArtNavigableChildDirectories -ParentPath $currentPath

    Write-Host ""
    Write-UEToolSuiteArtInfoLine "Current folder: $currentDisplay"
    $canGoUp = ([System.IO.Path]::GetFullPath($currentPath).TrimEnd('\') -ne $start)

    $menu = @()
    foreach ($dir in $containerDirs) {
      $menu += [pscustomobject]@{
        Label = $dir.Name
        Action = "enter_existing"
        Path = $dir.FullName
      }
    }

    $menu += [pscustomobject]@{ Label = "Create new folder"; Action = "create_container"; Path = $null }
    $menu += [pscustomobject]@{ Label = "Create art item"; Action = "create_art_item"; Path = $null }
    $menu += [pscustomobject]@{ Label = "Go Back"; Action = "go_back"; Path = $null }
    $menu += [pscustomobject]@{ Label = "Cancel"; Action = "cancel"; Path = $null }

    for ($i = 0; $i -lt $menu.Count; $i++) {
      Write-Host ("{0}) {1}" -f ($i + 1), $menu[$i].Label)
    }

    $choice = Read-UEToolSuiteArtMenuChoice -Prompt "Choose option" -Min 1 -Max $menu.Count
    $selected = $menu[$choice - 1]

    switch ($selected.Action) {
      "enter_existing" {
        $currentPath = $selected.Path
        continue
      }
      "create_container" {
        $containerName = Read-UEToolSuiteArtUniqueFolderName -Prompt "Enter nested folder name" -ParentPath $currentPath
        $currentPath = New-UEToolSuiteArtDirectoryChecked -ParentPath $currentPath -Name $containerName
        Write-UEToolSuiteArtOkLine "Created folder: $(Get-UEToolSuiteArtRelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $currentPath)"
        continue
      }
      "create_art_item" {
        $artItemName = Read-UEToolSuiteArtUniqueFolderName -Prompt "Enter new art item folder name" -ParentPath $currentPath
        $artItemPath = Join-Path $currentPath $artItemName
        $createdPath = New-UEToolSuiteArtItemFromTemplate -TemplatePath $TemplatePath -DestinationPath $artItemPath
        Write-UEToolSuiteArtOkLine "Created art item folder: $(Get-UEToolSuiteArtRelativeDisplayPath -RootPath $ArtSourceRoot -FullPath $createdPath)"
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

function Get-UEToolSuiteArtCommandOptions {
  [CmdletBinding()]
  param([AllowNull()][string[]]$CommandArguments = @())

  $options = [ordered]@{
    ArtSourceRelativePath = "ArtSource"
    ShowHelp = $false
  }

  $normalizedArgs = New-Object System.Collections.Generic.List[string]
  foreach ($arg in @($CommandArguments)) {
    if ($null -eq $arg) { continue }
    $text = [string]$arg
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    $normalizedArgs.Add($text) | Out-Null
  }
  $argsList = @($normalizedArgs.ToArray())
  $i = 0
  while ($i -lt $argsList.Count) {
    $token = [string]$argsList[$i]
    $normalized = $token.Trim().ToLowerInvariant()
    switch ($normalized) {
      "help" { $options.ShowHelp = $true; $i += 1; continue }
      "--help" { $options.ShowHelp = $true; $i += 1; continue }
      "-help" { $options.ShowHelp = $true; $i += 1; continue }
      "-h" { $options.ShowHelp = $true; $i += 1; continue }
      "/?" { $options.ShowHelp = $true; $i += 1; continue }
      "-?" { $options.ShowHelp = $true; $i += 1; continue }
      "-artsourcerelativepath" {
        if (($i + 1) -ge $argsList.Count) {
          throw "Missing value for -ArtSourceRelativePath."
        }
        $options.ArtSourceRelativePath = [string]$argsList[$i + 1]
        $i += 2
        continue
      }
      "-reporoot" {
        if (($i + 1) -ge $argsList.Count) {
          throw "Missing value for -RepoRoot."
        }
        $i += 2
        continue
      }
      default {
        if (-not $token.StartsWith("-") -and $options.ArtSourceRelativePath -eq "ArtSource") {
          $options.ArtSourceRelativePath = $token
          $i += 1
          continue
        }

        throw "Unknown art option '$token'. Run 'ue-tools help art'."
      }
    }
  }

  return [pscustomobject]$options
}

function Invoke-UEToolSuiteArtCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $options = Get-UEToolSuiteArtCommandOptions -CommandArguments $CommandArguments
  if ($options.ShowHelp) {
    @(
      "Usage: ue-tools art [options]"
      "Options:"
      "  -ArtSourceRelativePath <path>   ArtSource root (relative to repo root unless absolute)."
      "Examples:"
      "  ue-tools art"
      "  ue-tools art -ArtSourceRelativePath ArtSource"
      "  ue-tools art D:\Shared\ProjectArtSource"
    ) | Write-Output
    return
  }

  $resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
  if (-not (Test-Path -LiteralPath $resolvedRepoRoot -PathType Container)) {
    throw "RepoRoot does not exist or is not a directory: $resolvedRepoRoot"
  }

  $artSourceRoot = Resolve-UEToolSuiteArtSourceRootPath -RepoRoot $resolvedRepoRoot -ArtSourcePathInput ([string]$options.ArtSourceRelativePath)

  Write-UEToolSuiteArtInfoLine "Repo root: $(Convert-UEToolSuiteArtToUnixPath -Path $resolvedRepoRoot)"
  Write-UEToolSuiteArtInfoLine "ArtSource: $(Convert-UEToolSuiteArtToUnixPath -Path $artSourceRoot)"

  $templatePath = Ensure-UEToolSuiteArtCanonicalTemplate -ArtSourceRoot $artSourceRoot
  Write-UEToolSuiteArtOkLine "Canonical template ready: $(Get-UEToolSuiteArtRelativeDisplayPath -RootPath $artSourceRoot -FullPath $templatePath)"

  while ($true) {
    $domainPath = Select-UEToolSuiteArtDomainPath -ArtSourceRoot $artSourceRoot
    if ($null -eq $domainPath) {
      Write-UEToolSuiteArtInfoLine "Canceled by user."
      break
    }

    $createdPath = Invoke-UEToolSuiteArtItemPrompt -StartPath $domainPath -TemplatePath $templatePath -ArtSourceRoot $artSourceRoot
    if ($null -eq $createdPath) {
      continue
    }

    if (-not (Read-UEToolSuiteArtYesNo -Prompt "Create another art item path? (y/n)")) {
      Write-UEToolSuiteArtOkLine "Done."
      break
    }
  }
}

Export-ModuleMember -Function `
  Get-UEToolSuiteArtRequiredItemDirectories, `
  Get-UEToolSuiteArtReservedFolderNames, `
  Convert-UEToolSuiteArtToUnixPath, `
  Get-UEToolSuiteArtRelativeDisplayPath, `
  Assert-UEToolSuiteArtAvailableFolderName, `
  New-UEToolSuiteArtDirectoryChecked, `
  Test-UEToolSuiteArtItemDirectory, `
  Get-UEToolSuiteArtNavigableChildDirectories, `
  Merge-UEToolSuiteArtTemplateIntoCanonical, `
  Ensure-UEToolSuiteArtTemplateShape, `
  Ensure-UEToolSuiteArtCanonicalTemplate, `
  New-UEToolSuiteArtItemFromTemplate, `
  Invoke-UEToolSuiteArtCommand
