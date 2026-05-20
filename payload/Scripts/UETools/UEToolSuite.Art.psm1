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
  New-UEToolSuiteArtItemFromTemplate
