# Installs or updates the portable UE 5 tooling payload into a target project.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory)][string]$TargetRepoRoot,
  [string]$PayloadRoot,
  [string]$TargetUProjectPath,
  [ValidateSet("MergeExisting", "PreserveExisting", "ReplaceExisting")][string]$WebsiteInstallMode = "MergeExisting",
  [string]$WebsiteTheme = "neutral",
  [string]$WebsiteGlobalIconPath,
  [string]$WebsiteLogoPath,
  [string]$WebsiteFaviconPath,
  [string]$WebsiteSocialCardPath,
  [string[]]$WebsiteForceSuitePath = @(),
  [string[]]$WebsiteForceProjectPath = @(),
  [switch]$AdoptExistingWebsite,
  [switch]$RunInit,
  [switch]$InitNonInteractive,
  [switch]$SkipLfsPull,
  [switch]$SkipDocs,
  [switch]$SkipWebsite,
  [switch]$SkipTests,
  [switch]$SkipAITools,
  [switch]$SkipArtSourceTools,
  [switch]$SkipCodingStandardsTools,
  [switch]$SkipShellAliases,
  [switch]$SkipOptionalToolSetup,
  [switch]$SkipDocsSetup,
  [switch]$SkipDocsSectionMigration,
  [switch]$SkipDocsNpmInstall,
  [switch]$ForceDocsNpmInstall,
  [switch]$SkipDocsBridgeInstall,
  [switch]$SkipUnrealSync,
  [switch]$NoBuild,
  [switch]$NoRegen,
  [switch]$NoBackup,
  [switch]$NoLegacyCleanup
)

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[UE Tool Suite Installer] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[UE Tool Suite Installer] $m" -ForegroundColor Yellow }
function Ok($m) { Write-Host "[UE Tool Suite Installer] $m" -ForegroundColor Green }

function Resolve-ExistingDirectory {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name
  )

  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
    throw "$Name does not exist or is not a directory: $resolved"
  }

  return (Resolve-Path -LiteralPath $resolved).Path
}

function Resolve-ExistingFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Name
  )

  $resolved = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "$Name does not exist or is not a file: $resolved"
  }

  return (Resolve-Path -LiteralPath $resolved).Path
}

function Get-RelativePathCompat {
  param(
    [Parameter(Mandatory)][string]$BasePath,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $baseFull = [System.IO.Path]::GetFullPath($BasePath)
  $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
  $trimmedBase = $baseFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $trimmedTarget = $targetFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if ($trimmedBase.Equals($trimmedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
    return "."
  }

  $baseUri = New-Object System.Uri(($trimmedBase + [System.IO.Path]::DirectorySeparatorChar))
  $targetUri = New-Object System.Uri($targetFull)
  $relativeUri = $baseUri.MakeRelativeUri($targetUri)
  $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())
  return $relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function ConvertTo-HashtableCompat {
  param([AllowNull()]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [string] -or $Value -is [ValueType]) {
    return $Value
  }

  if ($Value -is [System.Collections.IDictionary]) {
    $table = @{}
    foreach ($key in @($Value.Keys)) {
      $table[[string]$key] = ConvertTo-HashtableCompat -Value $Value[$key]
    }
    return $table
  }

  if (($Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [psobject])) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Value) {
      $items.Add((ConvertTo-HashtableCompat -Value $item)) | Out-Null
    }
    return @($items.ToArray())
  }

  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [pscustomobject]) {
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Value) {
      $items.Add((ConvertTo-HashtableCompat -Value $item)) | Out-Null
    }
    return @($items.ToArray())
  }

  $properties = $Value.PSObject.Properties
  if ($properties.Count -gt 0) {
    $table = @{}
    foreach ($property in $properties) {
      $table[$property.Name] = ConvertTo-HashtableCompat -Value $property.Value
    }
    return $table
  }

  return $Value
}

function Get-DefaultPayloadRoot {
  $scriptDir = Split-Path -Path $PSCommandPath -Parent
  if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    throw "Could not resolve installer script path. Pass -PayloadRoot explicitly."
  }

  return Join-Path $scriptDir "payload"
}

function ConvertTo-StringArray {
  param(
    [AllowNull()]$Value,
    [Parameter(Mandatory)][string]$Name
  )

  if ($null -eq $Value) { return @() }

  $result = New-Object System.Collections.Generic.List[string]
  foreach ($item in @($Value)) {
    if ($null -eq $item) { continue }

    $text = [string]$item
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    $result.Add($text.Trim()) | Out-Null
  }

  if ($result.Count -eq 0) { return @() }
  return @($result.ToArray())
}

function Resolve-PayloadManifestPath {
  param([Parameter(Mandatory)][string]$PayloadRoot)

  return (Join-Path $PayloadRoot "ue-tool-suite.manifest.json")
}

function Read-UEToolSuitePayloadManifest {
  param([Parameter(Mandatory)][string]$PayloadRoot)

  $manifestPath = Resolve-PayloadManifestPath -PayloadRoot $PayloadRoot
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Payload manifest is missing: $manifestPath"
  }

  $rawText = Get-Content -LiteralPath $manifestPath -Raw
  try {
    $manifest = $rawText | ConvertFrom-Json
  }
  catch {
    throw "Payload manifest is not valid JSON: $manifestPath"
  }

  if (-not $manifest.managedItems) {
    throw "Payload manifest missing required object: managedItems"
  }

  $baseItems = ConvertTo-StringArray -Value $manifest.managedItems.base -Name "managedItems.base"
  if ($baseItems.Count -eq 0) {
    throw "Payload manifest requires at least one managed base item: managedItems.base"
  }

  return [pscustomobject]@{
    ManifestPath = $manifestPath
    PayloadVersion = [string]$manifest.payloadVersion
    DocsManagedFileIndexPath = [string]$manifest.docsManagedFileIndexPath
    WebsiteManagedFileIndexPath = [string]$manifest.websiteManagedFileIndexPath
    ManagedTextItems = ConvertTo-StringArray -Value $manifest.managedTextItems -Name "managedTextItems"
    ManagedBaseItems = $baseItems
    ManagedArtToolsItems = ConvertTo-StringArray -Value $manifest.managedItems.artTools -Name "managedItems.artTools"
    ManagedAIToolsItems = ConvertTo-StringArray -Value $manifest.managedItems.aiTools -Name "managedItems.aiTools"
    ManagedTestsItems = ConvertTo-StringArray -Value $manifest.managedItems.tests -Name "managedItems.tests"
    ManagedDocsItems = ConvertTo-StringArray -Value $manifest.managedItems.docs -Name "managedItems.docs"
    ManagedCodingStandardsItems = ConvertTo-StringArray -Value $manifest.managedItems.codingStandards -Name "managedItems.codingStandards"
    ManagedDocsToolsItems = ConvertTo-StringArray -Value $manifest.managedItems.docsTools -Name "managedItems.docsTools"
    ManagedWebsiteItems = ConvertTo-StringArray -Value $manifest.managedItems.website -Name "managedItems.website"
    LegacyCleanupPaths = ConvertTo-StringArray -Value $manifest.legacyCleanupPaths -Name "legacyCleanupPaths"
  }
}

function Test-PathInsideRoot {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path
  )

  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  return (
    $pathFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
    $pathFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
  )
}

function Resolve-TargetUProjectPath {
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [string]$UProjectPath
  )

  if (-not [string]::IsNullOrWhiteSpace($UProjectPath)) {
    $candidate = if ([System.IO.Path]::IsPathRooted($UProjectPath)) { $UProjectPath } else { Join-Path $RepoRoot $UProjectPath }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      throw "Target .uproject path does not exist: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
  }

  $uprojects = @(Get-ChildItem -LiteralPath $RepoRoot -Filter "*.uproject" -File -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($uprojects.Count -eq 1) { return $uprojects[0].FullName }
  if ($uprojects.Count -eq 0) { throw "No .uproject file found in target repo root: $RepoRoot" }
  throw "Multiple .uproject files found in target repo root. Pass -TargetUProjectPath explicitly."
}

function Test-TargetLooksLikeUE5Project {
  param([Parameter(Mandatory)][string]$UProjectPath)

  $uprojectJson = Get-Content -LiteralPath $UProjectPath -Raw | ConvertFrom-Json
  $association = [string]$uprojectJson.EngineAssociation
  if ([string]::IsNullOrWhiteSpace($association)) {
    Warn "Target .uproject has no EngineAssociation. Continuing, but UE5 version could not be verified."
    return
  }

  if ($association -notmatch '^(UE_)?5(\.|$)') {
    Warn "Target EngineAssociation is '$association'. This installer is intended for UE 5 projects."
  }
}

function Copy-ToBackup {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$ExistingPath,
    [Parameter(Mandatory)][string]$BackupRoot,
    [string[]]$ExcludeDirectoryPrefixes = @()
  )

  if ($NoBackup) { return }

  $backupPath = Join-Path $BackupRoot $RelativePath
  $backupParent = Split-Path -Path $backupPath -Parent
  if ($backupParent) {
    New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
  }

  $sourceIsDirectory = Test-Path -LiteralPath $ExistingPath -PathType Container
  $normalizedExcludes = @($ExcludeDirectoryPrefixes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Replace("/", "\").TrimStart("\") })
  if (-not $sourceIsDirectory -or $normalizedExcludes.Count -eq 0) {
    Copy-Item -LiteralPath $ExistingPath -Destination $backupPath -Recurse -Force
    return
  }

  if (-not (Test-Path -LiteralPath $backupPath -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
  }

  $sourceRoot = [System.IO.Path]::GetFullPath($ExistingPath)
  Get-ChildItem -LiteralPath $ExistingPath -Recurse -Force | ForEach-Object {
    $relativeChildPath = Get-RelativePathCompat -BasePath $sourceRoot -TargetPath $_.FullName
    if ($relativeChildPath -eq ".") {
      return
    }

    $normalizedRelativeChildPath = $relativeChildPath.Replace("/", "\").TrimStart("\")
    foreach ($prefix in $normalizedExcludes) {
      if ($normalizedRelativeChildPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
      }
    }

    $destinationPath = Join-Path $backupPath $relativeChildPath
    if ($_.PSIsContainer) {
      New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
      return
    }

    $destinationParent = Split-Path -Path $destinationPath -Parent
    if ($destinationParent) {
      New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    }
    Copy-Item -LiteralPath $_.FullName -Destination $destinationPath -Force
  }
}

function Write-Utf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $parent = Split-Path -Path $Path -Parent
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-TypeScriptSingleQuotedValue {
  param([AllowEmptyString()][string]$Value)

  return $Value.Replace("\", "\\").Replace("'", "\'")
}

function Set-TypeScriptSingleQuotedProperty {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][string]$Pattern,
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$PropertyDisplayName
  )

  $match = [regex]::Match($Text, $Pattern)
  if (-not $match.Success) {
    throw "Could not locate $PropertyDisplayName in website/docusaurus.config.ts."
  }

  $escapedValue = ConvertTo-TypeScriptSingleQuotedValue -Value $Value
  $replacement = ('$1''{0}'',' -f $escapedValue)
  $updated = [regex]::Replace($Text, $Pattern, $replacement, 1)
  return $updated
}

function Read-WebsiteThemeCatalog {
  param([Parameter(Mandatory)][string]$PayloadRoot)

  $catalogPath = Join-Path $PayloadRoot "website\theme-presets\theme-catalog.json"
  if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Website theme catalog is missing: $catalogPath"
  }

  $catalogRaw = Get-Content -LiteralPath $catalogPath -Raw
  try {
    $catalog = $catalogRaw | ConvertFrom-Json
  }
  catch {
    throw "Website theme catalog is not valid JSON: $catalogPath"
  }

  if (-not $catalog.themes) {
    throw "Website theme catalog is missing required array 'themes': $catalogPath"
  }

  $themes = @($catalog.themes)
  if ($themes.Count -eq 0) {
    throw "Website theme catalog has no themes: $catalogPath"
  }

  $defaultTheme = [string]$catalog.defaultTheme
  if ([string]::IsNullOrWhiteSpace($defaultTheme)) {
    throw "Website theme catalog is missing required value 'defaultTheme': $catalogPath"
  }

  $normalizedThemes = New-Object System.Collections.Generic.List[object]
  foreach ($theme in $themes) {
    if ($null -eq $theme) { continue }

    $themeId = [string]$theme.id
    $themeLabel = [string]$theme.label
    $themeCssPath = [string]$theme.cssPath
    $themeLogoPath = [string]$theme.logoPath
    $themeFaviconPath = [string]$theme.faviconPath
    $themeSocialCardPath = [string]$theme.socialCardPath

    if (
      [string]::IsNullOrWhiteSpace($themeId) -or
      [string]::IsNullOrWhiteSpace($themeCssPath) -or
      [string]::IsNullOrWhiteSpace($themeLogoPath) -or
      [string]::IsNullOrWhiteSpace($themeFaviconPath) -or
      [string]::IsNullOrWhiteSpace($themeSocialCardPath)
    ) {
      throw "Website theme catalog has an entry with missing required fields (id/cssPath/logoPath/faviconPath/socialCardPath): $catalogPath"
    }

    $normalizedThemes.Add([pscustomobject]@{
      id = $themeId.Trim()
      label = if ([string]::IsNullOrWhiteSpace($themeLabel)) { $themeId.Trim() } else { $themeLabel.Trim() }
      cssPath = $themeCssPath.Trim()
      logoPath = ($themeLogoPath.Trim().Replace("\", "/").TrimStart("/"))
      faviconPath = ($themeFaviconPath.Trim().Replace("\", "/").TrimStart("/"))
      socialCardPath = ($themeSocialCardPath.Trim().Replace("\", "/").TrimStart("/"))
    }) | Out-Null
  }

  $defaultThemeEntry = @($normalizedThemes.ToArray() | Where-Object { $_.id.Equals($defaultTheme, [System.StringComparison]::OrdinalIgnoreCase) })
  if ($defaultThemeEntry.Count -eq 0) {
    throw "Website theme catalog defaultTheme '$defaultTheme' is not present in themes: $catalogPath"
  }

  return [pscustomobject]@{
    CatalogPath = $catalogPath
    DefaultTheme = $defaultThemeEntry[0].id
    Themes = @($normalizedThemes.ToArray())
  }
}

function Resolve-WebsiteThemeEntry {
  param(
    [Parameter(Mandatory)]$ThemeCatalog,
    [string]$RequestedTheme
  )

  $themeId = if ([string]::IsNullOrWhiteSpace($RequestedTheme)) { [string]$ThemeCatalog.DefaultTheme } else { $RequestedTheme.Trim() }
  $matches = @($ThemeCatalog.Themes | Where-Object { $_.id.Equals($themeId, [System.StringComparison]::OrdinalIgnoreCase) })
  if ($matches.Count -gt 0) {
    return $matches[0]
  }

  $allowed = @($ThemeCatalog.Themes | ForEach-Object { $_.id } | Sort-Object -Unique)
  throw "Unknown website theme '$themeId'. Allowed themes: $($allowed -join ', ')."
}

function Convert-DocsDirectoryNameToLabel {
  param([Parameter(Mandatory)][string]$Name)

  $normalized = $Name.Trim()
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return $Name
  }

  $normalized = [regex]::Replace($normalized, '([a-z0-9])([A-Z])', '$1 $2')
  $normalized = $normalized -replace '[_\-]+', ' '
  $normalized = [regex]::Replace($normalized, '\s+', ' ').Trim()

  $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  return $textInfo.ToTitleCase($normalized.ToLowerInvariant())
}

function Get-DocsDirectoryDisplayLabel {
  param(
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)][string]$FallbackName
  )

  $readmePath = Join-Path $DirectoryPath "README.md"
  if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
    try {
      $readmeText = Get-Content -LiteralPath $readmePath -Raw
      $frontMatterMatch = [regex]::Match($readmeText, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---')
      if ($frontMatterMatch.Success) {
        $frontMatter = $frontMatterMatch.Groups['frontMatter'].Value
        $titleMatch = [regex]::Match($frontMatter, '(?m)^\s*title\s*:\s*(?<title>.+?)\s*$')
        if ($titleMatch.Success) {
          $title = $titleMatch.Groups['title'].Value.Trim().Trim('"', "'")
          if (-not [string]::IsNullOrWhiteSpace($title)) {
            return $title
          }
        }
      }

      $headingMatch = [regex]::Match($readmeText, '(?m)^\#\s+(?<title>.+?)\s*$')
      if ($headingMatch.Success) {
        $title = $headingMatch.Groups['title'].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($title)) {
          return $title
        }
      }
    }
    catch {
    }
  }

  return (Convert-DocsDirectoryNameToLabel -Name $FallbackName)
}

function Get-DocsDirectoryCategoryPosition {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    return $null
  }

  try {
    $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
    if ($null -eq $categoryJson.position) {
      return $null
    }

    $parsed = 0.0
    if ([double]::TryParse("$($categoryJson.position)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
      return $parsed
    }
  }
  catch {
  }

  return $null
}

function Test-DocsDirectoryNeedsCategoryFile {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
    return $false
  }

  if (Test-Path -LiteralPath (Join-Path $DirectoryPath "_category_.json") -PathType Leaf) {
    return $false
  }

  $directMarkdown = @(Get-ChildItem -LiteralPath $DirectoryPath -File -Filter *.md -ErrorAction SilentlyContinue)
  if ($directMarkdown.Count -gt 0) {
    return $true
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $DirectoryPath -Directory -ErrorAction SilentlyContinue)) {
    if (Test-DocsDirectoryNeedsCategoryFile -DirectoryPath $childDir.FullName) {
      return $true
    }
    if (Test-Path -LiteralPath (Join-Path $childDir.FullName "_category_.json") -PathType Leaf) {
      return $true
    }
    $childMarkdown = Get-ChildItem -LiteralPath $childDir.FullName -Recurse -File -Filter *.md -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $childMarkdown) {
      return $true
    }
  }

  return $false
}

function Ensure-DocsCategoryMetadataFiles {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)]$InstalledList
  )

  $docsRoot = Join-Path $TargetRoot "Docs"
  if (-not (Test-Path -LiteralPath $docsRoot -PathType Container)) {
    return @()
  }

  $created = New-Object System.Collections.Generic.List[string]

  function Ensure-DocsCategoryMetadataChildren {
    param(
      [Parameter(Mandatory)][string]$DocsRootPath,
      [Parameter(Mandatory)][string]$ParentDir,
      [AllowEmptyCollection()][System.Collections.Generic.List[string]]$CreatedList
    )

    $existingMax = 0.0
    foreach ($childDir in @(Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue)) {
      $position = Get-DocsDirectoryCategoryPosition -DirectoryPath $childDir.FullName
      if ($null -ne $position -and [double]$position -gt $existingMax) {
        $existingMax = [double]$position
      }
    }
    $nextPosition = [math]::Floor($existingMax) + 1

    foreach ($childDir in @(Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
      if (-not (Test-DocsDirectoryNeedsCategoryFile -DirectoryPath $childDir.FullName)) {
        continue
      }

      $categoryPath = Join-Path $childDir.FullName "_category_.json"
      if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
        $label = Get-DocsDirectoryDisplayLabel -DirectoryPath $childDir.FullName -FallbackName $childDir.Name
        $metadata = [ordered]@{
          label = $label
          position = [int]$nextPosition
        }

        $readmePath = Join-Path $childDir.FullName "README.md"
        if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
          $docId = (Get-RelativePathCompat -BasePath $DocsRootPath -TargetPath $readmePath).Replace('\', '/')
          if ($docId.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
            $docId = $docId.Substring(0, $docId.Length - 3)
          }
          $metadata.link = [ordered]@{
            type = "doc"
            id = $docId
          }
        }

        Write-Utf8NoBomFile -Path $categoryPath -Content (($metadata | ConvertTo-Json -Depth 10) + "`r`n")
        $relativeCategoryPath = (Get-RelativePathCompat -BasePath $TargetRoot -TargetPath $categoryPath).Replace('\', '/')
        $CreatedList.Add($relativeCategoryPath) | Out-Null
        $InstalledList.Add($relativeCategoryPath) | Out-Null
        $nextPosition += 1
      }

      Ensure-DocsCategoryMetadataChildren -DocsRootPath $DocsRootPath -ParentDir $childDir.FullName -CreatedList $CreatedList
    }
  }

  Ensure-DocsCategoryMetadataChildren -DocsRootPath $docsRoot -ParentDir $docsRoot -CreatedList $created
  return @($created.ToArray())
}

function Write-DocsSectionMigrationReport {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$InstallStamp,
    [AllowNull()]$MigrationResult = $null,
    [string]$Status = "completed",
    [string]$ErrorMessage = ""
  )

  $reportRoot = Join-Path $TargetRoot ".ue-tools-installer-updates\$InstallStamp"
  if (-not (Test-Path -LiteralPath $reportRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
  }

  $jsonPath = Join-Path $reportRoot "docs-section-migration.json"
  $markdownPath = Join-Path $reportRoot "Docs-Section-Migration.md"

  $plannedFiles = @()
  $detectedLegacySections = @()
  $createdFiles = @()
  $skippedEntries = @()
  $warnings = @()
  $changed = $false
  if ($null -ne $MigrationResult) {
    $plannedFiles = @($MigrationResult.PlannedFiles | ForEach-Object {
        [ordered]@{
          relativePath = [string]$_.RelativePath
          label        = [string]$_.Label
          position     = $_.Position
        }
      })
    $detectedLegacySections = @($MigrationResult.DetectedLegacySections | ForEach-Object {
        [ordered]@{
          relativePath = [string]$_.RelativePath
          reason       = [string]$_.Reason
        }
      })
    $createdFiles = @($MigrationResult.CreatedFiles | ForEach-Object {
        (Get-RelativePathCompat -BasePath $TargetRoot -TargetPath ([string]$_)).Replace("\", "/")
      })
    $skippedEntries = @($MigrationResult.SkippedEntries | ForEach-Object {
        [ordered]@{
          kind         = [string]$_.Kind
          relativePath = [string]$_.RelativePath
          reason       = [string]$_.Reason
        }
      })
    $warnings = @($MigrationResult.Warnings | ForEach-Object {
        [ordered]@{
          relativePath = [string]$_.RelativePath
          reason       = [string]$_.Reason
        }
      })
    $changed = [bool]$MigrationResult.Changed
  }

  $document = [ordered]@{
    schemaVersion         = 1
    generatedUtc          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    status                = $Status
    changed               = $changed
    detectedLegacySections = $detectedLegacySections
    plannedFiles          = $plannedFiles
    createdFiles          = $createdFiles
    skippedEntries        = $skippedEntries
    warnings              = $warnings
    error                 = $ErrorMessage
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# UE Tool Suite Docs Section Migration Report") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Status: $Status") | Out-Null
  $lines.Add("- Changed: $changed") | Out-Null
  $lines.Add("- Legacy sections detected: $($detectedLegacySections.Count)") | Out-Null
  $lines.Add("- Metadata files created: $($createdFiles.Count)") | Out-Null
  $lines.Add("- Skipped entries: $($skippedEntries.Count)") | Out-Null
  $lines.Add("") | Out-Null

  if ($plannedFiles.Count -gt 0) {
    $lines.Add("## Planned Files") | Out-Null
    foreach ($plannedFile in $plannedFiles) {
      $lines.Add("- $($plannedFile.relativePath) -> label=`"$($plannedFile.label)`", position=$($plannedFile.position)") | Out-Null
    }
    $lines.Add("") | Out-Null
  }

  if ($skippedEntries.Count -gt 0) {
    $lines.Add("## Skipped Entries") | Out-Null
    foreach ($skippedEntry in $skippedEntries) {
      $lines.Add("- $($skippedEntry.kind): $($skippedEntry.relativePath) ($($skippedEntry.reason))") | Out-Null
    }
    $lines.Add("") | Out-Null
  }

  if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
    $lines.Add("## Error") | Out-Null
    $lines.Add($ErrorMessage) | Out-Null
    $lines.Add("") | Out-Null
  }

  Write-Utf8NoBomFile -Path $jsonPath -Content ($document | ConvertTo-Json -Depth 12)
  Write-Utf8NoBomFile -Path $markdownPath -Content ($lines -join "`n")

  return [pscustomobject]@{
    JsonPath     = $jsonPath
    MarkdownPath = $markdownPath
  }
}

function Invoke-InstalledDocsSectionMigration {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$InstallStamp,
    [switch]$SkipMigration
  )

  $docsRoot = Join-Path $TargetRoot "Docs"
  $docsModulePath = Join-Path $TargetRoot "Scripts\UETools\UEToolSuite.Docs.psm1"
  if (-not (Test-Path -LiteralPath $docsRoot -PathType Container) -or -not (Test-Path -LiteralPath $docsModulePath -PathType Leaf)) {
    return [pscustomobject]@{
      Status     = "not-applicable"
      Changed    = $false
      ReportPath = $null
      Result     = $null
    }
  }

  if ($SkipMigration) {
    $reportPaths = Write-DocsSectionMigrationReport -TargetRoot $TargetRoot -InstallStamp $InstallStamp -Status "skipped-by-parameter"
    return [pscustomobject]@{
      Status     = "skipped-by-parameter"
      Changed    = $false
      ReportPath = $reportPaths.MarkdownPath
      Result     = $null
    }
  }

  $docsModule = Import-Module -Name $docsModulePath -Force -DisableNameChecking -PassThru
  try {
    $result = & $docsModule { param($repoRoot) Invoke-DocsSectionMigration -ResolvedRepoRoot $repoRoot } $TargetRoot
    $reportPaths = Write-DocsSectionMigrationReport -TargetRoot $TargetRoot -InstallStamp $InstallStamp -MigrationResult $result -Status "completed"
    return [pscustomobject]@{
      Status     = "completed"
      Changed    = [bool]$result.Changed
      ReportPath = $reportPaths.MarkdownPath
      Result     = $result
    }
  }
  catch {
    $reportPaths = Write-DocsSectionMigrationReport -TargetRoot $TargetRoot -InstallStamp $InstallStamp -Status "failed" -ErrorMessage $_.Exception.Message
    throw ("Docs section migration failed. Review: {0}. {1}" -f $reportPaths.MarkdownPath, $_.Exception.Message)
  }
}

function Apply-WebsiteThemeAndBranding {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$TargetUProjectPath,
    [string]$RequestedTheme,
    [string]$GlobalIconPath,
    [string]$LogoPath,
    [string]$FaviconPath,
    [string]$SocialCardPath
  )

  $websiteRoot = Join-Path $TargetRoot "website"
  if (-not (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    Warn "Skipping website theme/branding because website payload is not installed."
    return
  }

  $configPath = Join-Path $websiteRoot "docusaurus.config.ts"
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Warn "Skipping website theme/branding because docusaurus config is missing: $configPath"
    return
  }

  $themeCatalog = Read-WebsiteThemeCatalog -PayloadRoot $PayloadRoot
  $themeEntry = Resolve-WebsiteThemeEntry -ThemeCatalog $themeCatalog -RequestedTheme $RequestedTheme
  $themeSourcePath = Join-Path $PayloadRoot $themeEntry.cssPath
  if (-not (Test-Path -LiteralPath $themeSourcePath -PathType Leaf)) {
    throw "Theme CSS payload is missing for '$($themeEntry.id)': $themeSourcePath"
  }
  $themeLogoSourcePath = Join-Path $PayloadRoot ("website\static\" + $themeEntry.logoPath.Replace("/", "\"))
  $themeFaviconSourcePath = Join-Path $PayloadRoot ("website\static\" + $themeEntry.faviconPath.Replace("/", "\"))
  $themeSocialCardSourcePath = Join-Path $PayloadRoot ("website\static\" + $themeEntry.socialCardPath.Replace("/", "\"))
  foreach ($asset in @(
    [pscustomobject]@{ Name = "logoPath"; Path = $themeLogoSourcePath; Relative = [string]$themeEntry.logoPath },
    [pscustomobject]@{ Name = "faviconPath"; Path = $themeFaviconSourcePath; Relative = [string]$themeEntry.faviconPath },
    [pscustomobject]@{ Name = "socialCardPath"; Path = $themeSocialCardSourcePath; Relative = [string]$themeEntry.socialCardPath }
  )) {
    if (-not (Test-Path -LiteralPath $asset.Path -PathType Leaf)) {
      throw "Theme asset '$($asset.Name)' is missing for '$($themeEntry.id)': $($asset.Path) (catalog value: $($asset.Relative))"
    }
  }

  $themeDestinationPath = Join-Path $websiteRoot "theme-presets\active-theme.css"
  $themeDestinationParent = Split-Path -Path $themeDestinationPath -Parent
  if ($themeDestinationParent -and $PSCmdlet.ShouldProcess($themeDestinationParent, "Ensure website theme destination directory")) {
    New-Item -ItemType Directory -Force -Path $themeDestinationParent | Out-Null
  }
  if ($PSCmdlet.ShouldProcess($themeDestinationPath, "Apply website theme '$($themeEntry.id)'")) {
    Copy-Item -LiteralPath $themeSourcePath -Destination $themeDestinationPath -Force
  }

  $effectiveLogoPath = if (-not [string]::IsNullOrWhiteSpace($LogoPath)) { $LogoPath } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { $GlobalIconPath } else { "" }
  $effectiveFaviconPath = if (-not [string]::IsNullOrWhiteSpace($FaviconPath)) { $FaviconPath } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { $GlobalIconPath } elseif (-not [string]::IsNullOrWhiteSpace($LogoPath)) { $LogoPath } else { "" }
  $effectiveSocialCardPath = if (-not [string]::IsNullOrWhiteSpace($SocialCardPath)) { $SocialCardPath } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { $GlobalIconPath } elseif (-not [string]::IsNullOrWhiteSpace($LogoPath)) { $LogoPath } else { "" }

  $resolvedLogoPath = $null
  $resolvedFaviconPath = $null
  $resolvedSocialCardPath = $null
  $logoRelativePath = [string]$themeEntry.logoPath
  $faviconRelativePath = [string]$themeEntry.faviconPath
  $socialCardRelativePath = [string]$themeEntry.socialCardPath
  if (-not [string]::IsNullOrWhiteSpace($effectiveLogoPath)) {
    $resolvedLogoPath = Resolve-ExistingFile -Path $effectiveLogoPath -Name $(if (-not [string]::IsNullOrWhiteSpace($LogoPath)) { "WebsiteLogoPath" } else { "WebsiteGlobalIconPath" })
    $logoExtension = [string]([System.IO.Path]::GetExtension($resolvedLogoPath))
    $logoExtension = $logoExtension.ToLowerInvariant()
    if (($logoExtension -ne ".svg") -and ($logoExtension -ne ".png")) {
      throw "$(if (-not [string]::IsNullOrWhiteSpace($LogoPath)) { "WebsiteLogoPath" } else { "WebsiteGlobalIconPath" }) must use .svg or .png. Received: $resolvedLogoPath"
    }

    $logoRelativePath = "img/branding/project-logo$logoExtension"
    $logoDestination = Join-Path $websiteRoot ("static\" + $logoRelativePath.Replace("/", "\"))
    $logoDestinationParent = Split-Path -Path $logoDestination -Parent
    if ($logoDestinationParent -and $PSCmdlet.ShouldProcess($logoDestinationParent, "Ensure website branding directory")) {
      New-Item -ItemType Directory -Force -Path $logoDestinationParent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($logoDestination, "Install website logo asset")) {
      Copy-Item -LiteralPath $resolvedLogoPath -Destination $logoDestination -Force
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($effectiveFaviconPath)) {
    $resolvedFaviconPath = Resolve-ExistingFile -Path $effectiveFaviconPath -Name $(if (-not [string]::IsNullOrWhiteSpace($FaviconPath)) { "WebsiteFaviconPath" } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { "WebsiteGlobalIconPath" } else { "WebsiteLogoPath" })
    $faviconExtension = [string]([System.IO.Path]::GetExtension($resolvedFaviconPath))
    $faviconExtension = $faviconExtension.ToLowerInvariant()
    if (($faviconExtension -ne ".svg") -and ($faviconExtension -ne ".png") -and ($faviconExtension -ne ".ico")) {
      throw "$(if (-not [string]::IsNullOrWhiteSpace($FaviconPath)) { "WebsiteFaviconPath" } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { "WebsiteGlobalIconPath" } else { "WebsiteLogoPath" }) must use .svg, .png, or .ico. Received: $resolvedFaviconPath"
    }

    $faviconRelativePath = "img/branding/project-favicon$faviconExtension"
    $faviconDestination = Join-Path $websiteRoot ("static\" + $faviconRelativePath.Replace("/", "\"))
    $faviconDestinationParent = Split-Path -Path $faviconDestination -Parent
    if ($faviconDestinationParent -and $PSCmdlet.ShouldProcess($faviconDestinationParent, "Ensure website branding directory")) {
      New-Item -ItemType Directory -Force -Path $faviconDestinationParent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($faviconDestination, "Install website favicon asset")) {
      Copy-Item -LiteralPath $resolvedFaviconPath -Destination $faviconDestination -Force
    }
  }
  elseif ($resolvedLogoPath) {
    $faviconRelativePath = $logoRelativePath
  }

  if (-not [string]::IsNullOrWhiteSpace($effectiveSocialCardPath)) {
    $resolvedSocialCardPath = Resolve-ExistingFile -Path $effectiveSocialCardPath -Name $(if (-not [string]::IsNullOrWhiteSpace($SocialCardPath)) { "WebsiteSocialCardPath" } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { "WebsiteGlobalIconPath" } else { "WebsiteLogoPath" })
    $socialExtension = [string]([System.IO.Path]::GetExtension($resolvedSocialCardPath))
    $socialExtension = $socialExtension.ToLowerInvariant()
    if (($socialExtension -ne ".svg") -and ($socialExtension -ne ".png") -and ($socialExtension -ne ".jpg") -and ($socialExtension -ne ".jpeg") -and ($socialExtension -ne ".webp")) {
      throw "$(if (-not [string]::IsNullOrWhiteSpace($SocialCardPath)) { "WebsiteSocialCardPath" } elseif (-not [string]::IsNullOrWhiteSpace($GlobalIconPath)) { "WebsiteGlobalIconPath" } else { "WebsiteLogoPath" }) must use .svg, .png, .jpg, .jpeg, or .webp. Received: $resolvedSocialCardPath"
    }

    $socialCardRelativePath = "img/branding/project-social-card$socialExtension"
    $socialCardDestination = Join-Path $websiteRoot ("static\" + $socialCardRelativePath.Replace("/", "\"))
    $socialCardDestinationParent = Split-Path -Path $socialCardDestination -Parent
    if ($socialCardDestinationParent -and $PSCmdlet.ShouldProcess($socialCardDestinationParent, "Ensure website branding directory")) {
      New-Item -ItemType Directory -Force -Path $socialCardDestinationParent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($socialCardDestination, "Install website social card asset")) {
      Copy-Item -LiteralPath $resolvedSocialCardPath -Destination $socialCardDestination -Force
    }
  }
  elseif ($resolvedLogoPath) {
    $socialCardRelativePath = $logoRelativePath
  }

  $projectName = [System.IO.Path]::GetFileNameWithoutExtension($TargetUProjectPath)
  $docsTitle = "$projectName Docs"
  $tagline = "Repo tooling, Unreal workflow, and living project documentation for $projectName."
  $logoAlt = "$docsTitle"

  $configText = Get-Content -LiteralPath $configPath -Raw
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $configText -Pattern "(?m)^(\s*title:\s*)'[^']*'," -Value $docsTitle -PropertyDisplayName "config title"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*favicon:\s*)'[^']*'," -Value $faviconRelativePath -PropertyDisplayName "config favicon"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*image:\s*)'[^']*'," -Value $socialCardRelativePath -PropertyDisplayName "themeConfig.image"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?ms)(navbar:\s*\{.*?^\s*title:\s*)'[^']*'," -Value $projectName -PropertyDisplayName "navbar title"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?ms)(logo:\s*\{.*?^\s*alt:\s*)'[^']*'," -Value $logoAlt -PropertyDisplayName "navbar logo alt"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?ms)(logo:\s*\{.*?^\s*src:\s*)'[^']*'," -Value $logoRelativePath -PropertyDisplayName "navbar logo src"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteProjectName:\s*)'[^']*'," -Value $projectName -PropertyDisplayName "customFields.suiteProjectName"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteDocsTitle:\s*)'[^']*'," -Value $docsTitle -PropertyDisplayName "customFields.suiteDocsTitle"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteTagline:\s*)'[^']*'," -Value $tagline -PropertyDisplayName "customFields.suiteTagline"
  $updatedConfig = Set-TypeScriptSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteThemeId:\s*)'[^']*'," -Value $themeEntry.id -PropertyDisplayName "customFields.suiteThemeId"

  if ($PSCmdlet.ShouldProcess($configPath, "Apply website project branding metadata")) {
    Write-Utf8NoBomFile -Path $configPath -Content $updatedConfig
  }

  if ($resolvedLogoPath) {
    Ok ("Applied website theme '{0}' and custom logo '{1}' for project '{2}'." -f $themeEntry.id, [System.IO.Path]::GetFileName($resolvedLogoPath), $projectName)
  }
  else {
    Ok ("Applied website theme '{0}' and project branding for '{1}'." -f $themeEntry.id, $projectName)
  }

  return [pscustomobject]@{
    ThemeId = $themeEntry.id
    ProjectName = $projectName
    LogoPath = $logoRelativePath
    FaviconPath = $faviconRelativePath
    SocialCardPath = $socialCardRelativePath
  }
}

function ConvertTo-RelativeForwardSlashPath {
  param([Parameter(Mandatory)][string]$RelativePath)

  $normalized = $RelativePath.Replace("\", "/").Trim()
  $normalized = $normalized.TrimStart("/")
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    throw "Relative path cannot be empty."
  }

  return $normalized
}

function Get-FileSha256 {
  param([Parameter(Mandatory)][string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ManagedDocsLedgerPath {
  param([Parameter(Mandatory)][string]$TargetRoot)

  return (Join-Path $TargetRoot ".ue-tools\state\docs-managed-ledger.json")
}

function Read-ManagedDocsLedger {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $ledgerPath = Get-ManagedDocsLedgerPath -TargetRoot $TargetRoot
  $entries = @{}
  if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
    return [pscustomobject]@{
      LedgerPath = $ledgerPath
      EntriesByPath = $entries
    }
  }

  try {
    $raw = Get-Content -LiteralPath $ledgerPath -Raw
    $parsed = $raw | ConvertFrom-Json
  }
  catch {
    Warn "Docs ledger is invalid and will be ignored for this run: $ledgerPath"
    return [pscustomobject]@{
      LedgerPath = $ledgerPath
      EntriesByPath = $entries
    }
  }

  foreach ($entry in @($parsed.files)) {
    if ($null -eq $entry) { continue }
    $relativePath = [string]$entry.relativePath
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
    $normalizedPath = ConvertTo-RelativeForwardSlashPath -RelativePath $relativePath
    $installedHash = [string]$entry.installedHash
    if ([string]::IsNullOrWhiteSpace($installedHash)) { continue }
    $entries[$normalizedPath] = [pscustomobject]@{
      relativePath = $normalizedPath
      installedPayloadVersion = [string]$entry.installedPayloadVersion
      installedHash = $installedHash.ToLowerInvariant()
      updatedUtc = [string]$entry.updatedUtc
      category = [string]$entry.category
    }
  }

  return [pscustomobject]@{
    LedgerPath = $ledgerPath
    EntriesByPath = $entries
  }
}

function Write-ManagedDocsLedger {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][hashtable]$EntriesByPath,
    [Parameter(Mandatory)][string]$PayloadVersion
  )

  $ledgerPath = Get-ManagedDocsLedgerPath -TargetRoot $TargetRoot
  $entries = @()
  foreach ($path in @($EntriesByPath.Keys | Sort-Object)) {
    $entry = $EntriesByPath[$path]
    if ($null -eq $entry) { continue }
    $entries += [pscustomobject]@{
      relativePath = $path
      installedPayloadVersion = [string]$entry.installedPayloadVersion
      installedHash = [string]$entry.installedHash
      updatedUtc = [string]$entry.updatedUtc
      category = [string]$entry.category
    }
  }

  $ledgerDocument = [ordered]@{
    schemaVersion = 1
    payloadVersion = $PayloadVersion
    updatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    files = $entries
  }

  $content = $ledgerDocument | ConvertTo-Json -Depth 10
  if ($PSCmdlet.ShouldProcess($ledgerPath, "Write managed docs ledger")) {
    Write-Utf8NoBomFile -Path $ledgerPath -Content $content
  }
}

function Resolve-DocsManagedFileIndexPath {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)]$PayloadManifest
  )

  $configured = [string]$PayloadManifest.DocsManagedFileIndexPath
  $relativePath = if ([string]::IsNullOrWhiteSpace($configured)) { "docs-managed-file-index.json" } else { $configured.Trim() }
  return (Join-Path $PayloadRoot ($relativePath -replace "/", "\"))
}

function Read-DocsManagedFileIndex {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)]$PayloadManifest
  )

  $indexPath = Resolve-DocsManagedFileIndexPath -PayloadRoot $PayloadRoot -PayloadManifest $PayloadManifest
  if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Docs managed file index is missing: $indexPath"
  }

  try {
    $parsed = (Get-Content -LiteralPath $indexPath -Raw) | ConvertFrom-Json
  }
  catch {
    throw "Docs managed file index is not valid JSON: $indexPath"
  }

  if (-not $parsed.files) {
    throw "Docs managed file index is missing required array 'files': $indexPath"
  }

  $normalizedFiles = New-Object System.Collections.Generic.List[object]
  foreach ($file in @($parsed.files)) {
    if ($null -eq $file) { continue }
    $relativePath = ConvertTo-RelativeForwardSlashPath -RelativePath ([string]$file.relativePath)
    $category = [string]$file.category
    $sha256 = ([string]$file.sha256).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($category) -or [string]::IsNullOrWhiteSpace($sha256)) {
      throw "Docs managed file index entry is missing required category/hash: $indexPath"
    }
    if ($sha256 -notmatch "^[0-9a-f]{64}$") {
      throw "Docs managed file index entry has invalid sha256 for '$relativePath': $sha256"
    }

    $normalizedFiles.Add([pscustomobject]@{
      relativePath = $relativePath
      category = $category.Trim()
      sha256 = $sha256
    }) | Out-Null
  }

  return [pscustomobject]@{
    IndexPath = $indexPath
    PayloadVersion = [string]$parsed.payloadVersion
    Files = @($normalizedFiles.ToArray())
  }
}

function Get-WebsiteSiteOverridesRelativePath {
  return "website/.ue-tools/site-overrides.json"
}

function Get-WebsiteSiteOverridesPath {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $relativePath = Get-WebsiteSiteOverridesRelativePath
  return (Join-Path $TargetRoot ($relativePath -replace "/", "\"))
}

function Get-DefaultWebsiteOverrideDocument {
  param(
    [string]$ThemeId = "neutral",
    [string]$LogoPath = "",
    [string]$FaviconPath = "",
    [string]$SocialCardPath = ""
  )

  return [ordered]@{
    schemaVersion = 1
    theme = [ordered]@{
      themeId = $ThemeId
      logoPath = $LogoPath
      faviconPath = $FaviconPath
      socialCardPath = $SocialCardPath
    }
    fileOverrides = @()
  }
}

function Get-WebsiteOverrideCandidatePaths {
  return @(
    "website/docusaurus.config.ts",
    "website/src/css/custom.css",
    "website/src/pages/index.tsx",
    "website/src/pages/index.module.css",
    "Docs/README.md"
  )
}

function Read-WebsiteSiteOverrides {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $overridesPath = Get-WebsiteSiteOverridesPath -TargetRoot $TargetRoot
  $defaultDocument = Get-DefaultWebsiteOverrideDocument
  if (-not (Test-Path -LiteralPath $overridesPath -PathType Leaf)) {
    return [pscustomobject]@{
      OverridesPath = $overridesPath
      Document = $defaultDocument
    }
  }

  try {
    $parsed = (Get-Content -LiteralPath $overridesPath -Raw) | ConvertFrom-Json
  }
  catch {
    Warn "Website override config is invalid and will be reset: $overridesPath"
    return [pscustomobject]@{
      OverridesPath = $overridesPath
      Document = $defaultDocument
    }
  }

  $theme = $parsed.theme
  $themeId = [string]$theme.themeId
  $logoPath = [string]$theme.logoPath
  $faviconPath = [string]$theme.faviconPath
  $socialCardPath = [string]$theme.socialCardPath

  $fileOverrides = New-Object System.Collections.Generic.List[object]
  foreach ($entry in @($parsed.fileOverrides)) {
    if ($null -eq $entry) { continue }
    $relativePath = [string]$entry.path
    $mode = [string]$entry.mode
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [string]::IsNullOrWhiteSpace($mode)) {
      continue
    }

    $normalizedPath = ConvertTo-RelativeForwardSlashPath -RelativePath $relativePath
    $normalizedMode = $mode.Trim().ToLowerInvariant()
    if ($normalizedMode -notin @("suite", "project")) {
      continue
    }

    $fileOverrides.Add([ordered]@{
      path = $normalizedPath
      mode = $normalizedMode
    }) | Out-Null
  }

  return [pscustomobject]@{
    OverridesPath = $overridesPath
    Document = [ordered]@{
      schemaVersion = 1
      theme = [ordered]@{
        themeId = if ([string]::IsNullOrWhiteSpace($themeId)) { "neutral" } else { $themeId.Trim() }
        logoPath = if ($null -eq $logoPath) { "" } else { $logoPath }
        faviconPath = if ($null -eq $faviconPath) { "" } else { $faviconPath }
        socialCardPath = if ($null -eq $socialCardPath) { "" } else { $socialCardPath }
      }
      fileOverrides = @($fileOverrides.ToArray())
    }
  }
}

function Write-WebsiteSiteOverrides {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)]$Document
  )

  $overridesPath = Get-WebsiteSiteOverridesPath -TargetRoot $TargetRoot
  if ($PSCmdlet.ShouldProcess($overridesPath, "Write website override config")) {
    Write-Utf8NoBomFile -Path $overridesPath -Content ($Document | ConvertTo-Json -Depth 10)
  }
}

function Resolve-WebsiteOverrideMap {
  param(
    [Parameter(Mandatory)]$PersistedOverrideDocument,
    [string[]]$ForceSuitePaths = @(),
    [string[]]$ForceProjectPaths = @()
  )

  $entries = @{}
  foreach ($entry in @($PersistedOverrideDocument.fileOverrides)) {
    if ($null -eq $entry) { continue }
    $relativePath = [string]$entry.path
    $mode = [string]$entry.mode
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [string]::IsNullOrWhiteSpace($mode)) {
      continue
    }

    $entries[(ConvertTo-RelativeForwardSlashPath -RelativePath $relativePath)] = $mode.Trim().ToLowerInvariant()
  }

  foreach ($relativePath in @($ForceProjectPaths)) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
    $entries[(ConvertTo-RelativeForwardSlashPath -RelativePath $relativePath)] = "project"
  }
  foreach ($relativePath in @($ForceSuitePaths)) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
    $entries[(ConvertTo-RelativeForwardSlashPath -RelativePath $relativePath)] = "suite"
  }

  return $entries
}

function Get-WebsiteOverrideModeForPath {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][hashtable]$OverrideMap,
    [string]$DefaultMode = "suite"
  )

  $normalizedPath = ConvertTo-RelativeForwardSlashPath -RelativePath $RelativePath
  if ($OverrideMap.ContainsKey($normalizedPath)) {
    return [string]$OverrideMap[$normalizedPath]
  }

  foreach ($key in @($OverrideMap.Keys | Sort-Object Length -Descending)) {
    $normalizedKey = ConvertTo-RelativeForwardSlashPath -RelativePath ([string]$key)
    if ($normalizedPath.StartsWith($normalizedKey.TrimEnd("/") + "/", [System.StringComparison]::OrdinalIgnoreCase)) {
      return [string]$OverrideMap[$normalizedKey]
    }
  }

  return $DefaultMode
}

function Get-ManagedWebsiteLedgerPath {
  param([Parameter(Mandatory)][string]$TargetRoot)

  return (Join-Path $TargetRoot ".ue-tools\state\website-managed-ledger.json")
}

function Read-ManagedWebsiteLedger {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $ledgerPath = Get-ManagedWebsiteLedgerPath -TargetRoot $TargetRoot
  $entries = @{}
  if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) {
    return [pscustomobject]@{
      LedgerPath = $ledgerPath
      EntriesByPath = $entries
    }
  }

  try {
    $parsed = (Get-Content -LiteralPath $ledgerPath -Raw) | ConvertFrom-Json
  }
  catch {
    Warn "Website managed ledger is invalid and will be ignored: $ledgerPath"
    return [pscustomobject]@{
      LedgerPath = $ledgerPath
      EntriesByPath = $entries
    }
  }

  foreach ($entry in @($parsed.files)) {
    if ($null -eq $entry) { continue }
    $relativePath = [string]$entry.relativePath
    $installedHash = [string]$entry.installedHash
    if ([string]::IsNullOrWhiteSpace($relativePath) -or [string]::IsNullOrWhiteSpace($installedHash)) {
      continue
    }

    $normalizedPath = ConvertTo-RelativeForwardSlashPath -RelativePath $relativePath
    $entries[$normalizedPath] = [pscustomobject]@{
      relativePath = $normalizedPath
      installedPayloadVersion = [string]$entry.installedPayloadVersion
      installedHash = $installedHash.ToLowerInvariant()
      updatedUtc = [string]$entry.updatedUtc
      category = [string]$entry.category
    }
  }

  return [pscustomobject]@{
    LedgerPath = $ledgerPath
    EntriesByPath = $entries
  }
}

function Write-ManagedWebsiteLedger {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][hashtable]$EntriesByPath,
    [Parameter(Mandatory)][string]$PayloadVersion
  )

  $ledgerPath = Get-ManagedWebsiteLedgerPath -TargetRoot $TargetRoot
  $entries = @()
  foreach ($path in @($EntriesByPath.Keys | Sort-Object)) {
    $entry = $EntriesByPath[$path]
    if ($null -eq $entry) { continue }
    $entries += [ordered]@{
      relativePath = $path
      installedPayloadVersion = [string]$entry.installedPayloadVersion
      installedHash = [string]$entry.installedHash
      updatedUtc = [string]$entry.updatedUtc
      category = [string]$entry.category
    }
  }

  $ledgerDocument = [ordered]@{
    schemaVersion = 1
    payloadVersion = $PayloadVersion
    updatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    files = $entries
  }

  if ($PSCmdlet.ShouldProcess($ledgerPath, "Write managed website ledger")) {
    Write-Utf8NoBomFile -Path $ledgerPath -Content ($ledgerDocument | ConvertTo-Json -Depth 10)
  }
}

function Resolve-WebsiteManagedFileIndexPath {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)]$PayloadManifest
  )

  $configured = [string]$PayloadManifest.WebsiteManagedFileIndexPath
  $relativePath = if ([string]::IsNullOrWhiteSpace($configured)) { "website-managed-file-index.json" } else { $configured.Trim() }
  return (Join-Path $PayloadRoot ($relativePath -replace "/", "\"))
}

function Read-WebsiteManagedFileIndex {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)]$PayloadManifest
  )

  $indexPath = Resolve-WebsiteManagedFileIndexPath -PayloadRoot $PayloadRoot -PayloadManifest $PayloadManifest
  if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Website managed file index is missing: $indexPath"
  }

  try {
    $parsed = (Get-Content -LiteralPath $indexPath -Raw) | ConvertFrom-Json
  }
  catch {
    throw "Website managed file index is not valid JSON: $indexPath"
  }

  if (-not $parsed.files) {
    throw "Website managed file index is missing required array 'files': $indexPath"
  }

  $normalizedFiles = New-Object System.Collections.Generic.List[object]
  foreach ($file in @($parsed.files)) {
    if ($null -eq $file) { continue }
    $relativePath = ConvertTo-RelativeForwardSlashPath -RelativePath ([string]$file.relativePath)
    $category = ([string]$file.category).Trim()
    $sha256 = ([string]$file.sha256).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($category) -or [string]::IsNullOrWhiteSpace($sha256)) {
      throw "Website managed file index entry is missing required category/hash: $indexPath"
    }
    if ($sha256 -notmatch "^[0-9a-f]{64}$") {
      throw "Website managed file index entry has invalid sha256 for '$relativePath': $sha256"
    }

    $normalizedFiles.Add([pscustomobject]@{
      relativePath = $relativePath
      category = $category
      sha256 = $sha256
    }) | Out-Null
  }

  return [pscustomobject]@{
    IndexPath = $indexPath
    PayloadVersion = [string]$parsed.payloadVersion
    Files = @($normalizedFiles.ToArray())
  }
}

function Get-WebsiteOwnershipMarkerRelativePath {
  return "website/.ue-tools/ownership.json"
}

function Get-WebsiteOwnershipMarkerPath {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $relativePath = Get-WebsiteOwnershipMarkerRelativePath
  return (Join-Path $TargetRoot ($relativePath -replace "/", "\"))
}

function Test-WebsiteOwnershipMarkerInstalled {
  param([Parameter(Mandatory)][string]$TargetRoot)

  $markerPath = Get-WebsiteOwnershipMarkerPath -TargetRoot $TargetRoot
  return (Test-Path -LiteralPath $markerPath -PathType Leaf)
}

function Write-WebsiteOwnershipMarker {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$PayloadVersion,
    [Parameter(Mandatory)][string]$ProjectName,
    [Parameter(Mandatory)][string]$InstallMode,
    [Parameter(Mandatory)][string]$ThemeId,
    [string]$LogoPath,
    [string]$FaviconPath,
    [string]$SocialCardPath,
    [int]$OverrideSchemaVersion = 1,
    [string]$OverrideSource = "site-overrides.json"
  )

  $markerPath = Get-WebsiteOwnershipMarkerPath -TargetRoot $TargetRoot
  $marker = [ordered]@{
    schemaVersion = 2
    managedBy = "UEToolSuiteInstaller"
    payloadVersion = $PayloadVersion
    projectName = $ProjectName
    installMode = $InstallMode
    theme = [ordered]@{
      themeId = $ThemeId
      logoPath = $LogoPath
      faviconPath = $FaviconPath
      socialCardPath = $SocialCardPath
    }
    overridePolicy = [ordered]@{
      schemaVersion = $OverrideSchemaVersion
      source = $OverrideSource
    }
    updatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }

  if ($PSCmdlet.ShouldProcess($markerPath, "Write website ownership marker")) {
    Write-Utf8NoBomFile -Path $markerPath -Content ($marker | ConvertTo-Json -Depth 10)
  }
}

function Resolve-WebsiteInstallMode {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RequestedInstallMode,
    [switch]$AdoptExisting,
    [switch]$WebsiteWasExplicitlyRequested
  )

  $websitePath = Join-Path $TargetRoot "website"
  if (-not (Test-Path -LiteralPath $websitePath)) {
    return "install_new"
  }

  $normalizedRequestedMode = if ([string]::IsNullOrWhiteSpace($RequestedInstallMode)) { "MergeExisting" } else { $RequestedInstallMode.Trim() }
  if ($AdoptExisting -and ($WebsiteWasExplicitlyRequested -and -not $normalizedRequestedMode.Equals("MergeExisting", [System.StringComparison]::OrdinalIgnoreCase))) {
    Warn "-AdoptExistingWebsite is deprecated and only maps to MergeExisting. The explicit -WebsiteInstallMode '$normalizedRequestedMode' will be used."
  }
  elseif ($AdoptExisting -and (-not $WebsiteWasExplicitlyRequested)) {
    Warn "-AdoptExistingWebsite is deprecated. Using -WebsiteInstallMode MergeExisting."
    $normalizedRequestedMode = "MergeExisting"
  }

  switch ($normalizedRequestedMode.ToLowerInvariant()) {
    "mergeexisting" {
      if (Test-WebsiteOwnershipMarkerInstalled -TargetRoot $TargetRoot) {
        return "managed_update"
      }
      return "merge_existing"
    }
    "replaceexisting" {
      return "replace_existing"
    }
    "preserveexisting" {
      return "preserve_existing"
    }
    default {
      throw "Unsupported WebsiteInstallMode '$RequestedInstallMode'."
    }
  }
}

function Merge-WebsitePackageJson {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $source = ConvertTo-HashtableCompat -Value ((Get-Content -LiteralPath $SourcePath -Raw) | ConvertFrom-Json)
  $target = if (Test-Path -LiteralPath $TargetPath -PathType Leaf) {
    try {
      ConvertTo-HashtableCompat -Value ((Get-Content -LiteralPath $TargetPath -Raw) | ConvertFrom-Json)
    }
    catch {
      @{}
    }
  }
  else {
    @{}
  }

  $merged = [ordered]@{}
  foreach ($key in @($target.Keys)) {
    $merged[$key] = $target[$key]
  }

  foreach ($key in @($source.Keys)) {
    if ($key -in @("scripts", "dependencies", "devDependencies", "peerDependencies", "browserslist", "engines")) {
      $targetSection = @{}
      if ($target.ContainsKey($key) -and $target[$key] -is [hashtable]) {
        $targetSection = $target[$key]
      }

      $section = [ordered]@{}
      foreach ($sectionKey in @($targetSection.Keys)) {
        $section[$sectionKey] = $targetSection[$sectionKey]
      }
      foreach ($sectionKey in @($source[$key].Keys)) {
        $section[$sectionKey] = $source[$key][$sectionKey]
      }
      $merged[$key] = $section
      continue
    }

    if ($key -in @("name", "version", "private")) {
      $merged[$key] = $source[$key]
      continue
    }

    if (-not $merged.Contains($key)) {
      $merged[$key] = $source[$key]
    }
  }

  return ($merged | ConvertTo-Json -Depth 20)
}

function Copy-ManagedWebsiteIndexedFile {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$BackupRoot
  )

  $sourcePath = Join-Path $PayloadRoot ($RelativePath -replace "/", "\")
  $targetPath = Join-Path $TargetRoot ($RelativePath -replace "/", "\")
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Managed website source file is missing: $sourcePath"
  }

  if (Test-Path -LiteralPath $targetPath) {
    Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $targetPath -BackupRoot $BackupRoot
  }

  $parent = Split-Path -Path $targetPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    $current = $parent
    $directoryChain = New-Object System.Collections.Generic.List[string]
    while (-not [string]::IsNullOrWhiteSpace($current) -and (Test-PathInsideRoot -Root $TargetRoot -Path $current)) {
      $directoryChain.Add($current) | Out-Null
      $current = Split-Path -Path $current -Parent
    }

    $directoryPaths = @($directoryChain.ToArray())
    [array]::Reverse($directoryPaths)
    foreach ($directoryPath in $directoryPaths) {
      if ((Test-Path -LiteralPath $directoryPath) -and -not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        $backupRelativePath = Get-RelativePathCompat -BasePath $TargetRoot -TargetPath $directoryPath
        Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $backupRelativePath -ExistingPath $directoryPath -BackupRoot $BackupRoot
        Remove-Item -LiteralPath $directoryPath -Force
      }
      if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $directoryPath | Out-Null
      }
    }
  }

  Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
}

function Write-WebsiteMergeReport {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$InstallStamp,
    [Parameter(Mandatory)][hashtable]$Report
  )

  $reportRoot = Join-Path $TargetRoot (".ue-tools-installer-updates\" + $InstallStamp)
  if (-not (Test-Path -LiteralPath $reportRoot -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
  }

  $markdownPath = Join-Path $reportRoot "Website-Update-Report.md"
  $jsonPath = Join-Path $reportRoot "website-update-report.json"

  $jsonDocument = [ordered]@{
    schemaVersion = 1
    generatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    installMode = $Report.InstallMode
    installedNew = @($Report.InstalledNew)
    replacedSuiteManaged = @($Report.ReplacedSuiteManaged)
    preservedProjectOverrides = @($Report.PreservedProjectOverrides)
    mergedConfigs = @($Report.MergedConfigs)
    restoredProjectOverrides = @($Report.RestoredProjectOverrides)
  }
  Write-Utf8NoBomFile -Path $jsonPath -Content ($jsonDocument | ConvertTo-Json -Depth 20)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# UE Tool Suite Website Merge Report") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Install mode: $($Report.InstallMode)") | Out-Null
  $lines.Add("- Installed new files: $($Report.InstalledNew.Count)") | Out-Null
  $lines.Add("- Replaced suite-managed files: $($Report.ReplacedSuiteManaged.Count)") | Out-Null
  $lines.Add("- Preserved project overrides: $($Report.PreservedProjectOverrides.Count)") | Out-Null
  $lines.Add("- Structured merges: $($Report.MergedConfigs.Count)") | Out-Null
  $lines.Add("- Restored project overrides after replace: $($Report.RestoredProjectOverrides.Count)") | Out-Null
  $lines.Add("") | Out-Null

  foreach ($section in @(
      [pscustomobject]@{ Title = "Installed New Files"; Items = @($Report.InstalledNew) },
      [pscustomobject]@{ Title = "Replaced Suite-Managed Files"; Items = @($Report.ReplacedSuiteManaged) },
      [pscustomobject]@{ Title = "Preserved Project Overrides"; Items = @($Report.PreservedProjectOverrides) },
      [pscustomobject]@{ Title = "Structured Merges"; Items = @($Report.MergedConfigs) },
      [pscustomobject]@{ Title = "Restored Project Overrides"; Items = @($Report.RestoredProjectOverrides) }
    )) {
    if ($section.Items.Count -eq 0) { continue }
    $lines.Add("## $($section.Title)") | Out-Null
    foreach ($item in @($section.Items)) {
      $lines.Add("- $item") | Out-Null
    }
    $lines.Add("") | Out-Null
  }

  Write-Utf8NoBomFile -Path $markdownPath -Content ($lines -join [Environment]::NewLine)
  return $markdownPath
}

function Invoke-ManagedWebsiteUpdate {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$BackupRoot,
    [Parameter(Mandatory)]$PayloadManifest,
    [Parameter(Mandatory)][string]$InstallStamp,
    [Parameter(Mandatory)][string]$RequestedMode,
    [Parameter(Mandatory)][hashtable]$OverrideMap
  )

  $index = Read-WebsiteManagedFileIndex -PayloadRoot $PayloadRoot -PayloadManifest $PayloadManifest
  $websiteRoot = Join-Path $TargetRoot "website"
  $report = @{
    InstallMode = $RequestedMode
    InstalledNew = New-Object System.Collections.Generic.List[string]
    ReplacedSuiteManaged = New-Object System.Collections.Generic.List[string]
    PreservedProjectOverrides = New-Object System.Collections.Generic.List[string]
    MergedConfigs = New-Object System.Collections.Generic.List[string]
    RestoredProjectOverrides = New-Object System.Collections.Generic.List[string]
  }

  $ledger = Read-ManagedWebsiteLedger -TargetRoot $TargetRoot
  $nextEntries = @{}
  $replaceSnapshotRoot = $null

  if ($RequestedMode -eq "replace_existing" -and (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    $replaceSnapshotRoot = Join-Path $BackupRoot "website-replace-snapshot"
    Copy-ToBackup `
      -TargetRoot $TargetRoot `
      -RelativePath "website-replace-snapshot" `
      -ExistingPath $websiteRoot `
      -BackupRoot $BackupRoot `
      -ExcludeDirectoryPrefixes @("node_modules\", "build\", ".docusaurus\", ".cache\")

    if ($PSCmdlet.ShouldProcess($websiteRoot, "Replace existing website shell")) {
      Remove-Item -LiteralPath $websiteRoot -Recurse -Force
    }
  }

  foreach ($file in @($index.Files)) {
    $relativePath = [string]$file.relativePath
    $category = [string]$file.category
    $sourcePath = Join-Path $PayloadRoot ($relativePath -replace "/", "\")
    $targetPath = Join-Path $TargetRoot ($relativePath -replace "/", "\")
    $defaultMode = if ($category -eq "overridable") { "suite" } else { "suite" }
    $overrideMode = Get-WebsiteOverrideModeForPath -RelativePath $relativePath -OverrideMap $OverrideMap -DefaultMode $defaultMode

    if ($category -eq "structured") {
      $parent = Split-Path -Path $targetPath -Parent
      if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
      }

      if ([System.IO.Path]::GetFileName($targetPath).Equals("package.json", [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $targetPath) {
          Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $relativePath -ExistingPath $targetPath -BackupRoot $BackupRoot
        }
        $mergedPackage = Merge-WebsitePackageJson -SourcePath $sourcePath -TargetPath $targetPath
        Write-Utf8NoBomFile -Path $targetPath -Content $mergedPackage
        $report.MergedConfigs.Add($relativePath) | Out-Null
      }
      else {
        if (Test-Path -LiteralPath $targetPath) {
          Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $relativePath -ExistingPath $targetPath -BackupRoot $BackupRoot
        }
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        $report.MergedConfigs.Add($relativePath) | Out-Null
      }
    }
    elseif ($overrideMode -eq "project" -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
      $report.PreservedProjectOverrides.Add($relativePath) | Out-Null
    }
    else {
      $existing = Test-Path -LiteralPath $targetPath -PathType Leaf
      Copy-ManagedWebsiteIndexedFile -PayloadRoot $PayloadRoot -TargetRoot $TargetRoot -RelativePath $relativePath -BackupRoot $BackupRoot
      if ($existing) {
        $report.ReplacedSuiteManaged.Add($relativePath) | Out-Null
      }
      else {
        $report.InstalledNew.Add($relativePath) | Out-Null
      }
    }

    if ($RequestedMode -eq "replace_existing" -and $overrideMode -eq "project" -and $replaceSnapshotRoot) {
      $snapshotPath = Join-Path $replaceSnapshotRoot ($relativePath -replace "/", "\")
      if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $targetParent = Split-Path -Path $targetPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($targetParent)) {
          New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
        }
        Copy-Item -LiteralPath $snapshotPath -Destination $targetPath -Force
        $report.RestoredProjectOverrides.Add($relativePath) | Out-Null
      }
    }

    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
      $nextEntries[$relativePath] = [pscustomobject]@{
        relativePath = $relativePath
        installedPayloadVersion = [string]$PayloadManifest.PayloadVersion
        installedHash = (Get-FileSha256 -Path $targetPath)
        updatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        category = $category
      }
    }
  }

  Write-ManagedWebsiteLedger -TargetRoot $TargetRoot -EntriesByPath $nextEntries -PayloadVersion ([string]$PayloadManifest.PayloadVersion)
  $reportPath = Write-WebsiteMergeReport -TargetRoot $TargetRoot -InstallStamp $InstallStamp -Report $report

  return [pscustomobject]@{
    LedgerEntries = $nextEntries
    ReportPath = $reportPath
  }
}

function Write-DocsSmartUpdateReport {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$ReportRoot,
    [Parameter(Mandatory)][hashtable]$Report
  )

  $preservedCount = $Report.PreservedCustomized.Count + $Report.MissingPreserved.Count
  if ($preservedCount -eq 0) {
    return $null
  }

  $jsonPath = Join-Path $ReportRoot "update-report.json"
  $markdownPath = Join-Path $ReportRoot "Update-Report.md"
  $autoUpdated = @($Report.AutoUpdated | ForEach-Object { $_ })
  $installedNew = @($Report.InstalledNew | ForEach-Object { $_ })
  $alreadyCurrent = @($Report.AlreadyCurrent | ForEach-Object { $_ })
  $preservedCustomized = @($Report.PreservedCustomized | ForEach-Object { $_ })
  $missingPreserved = @($Report.MissingPreserved | ForEach-Object { $_ })
  $jsonDocument = [pscustomobject]@{
    schemaVersion = 1
    generatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    reportRoot = (Get-RelativePathCompat -BasePath $TargetRoot -TargetPath $ReportRoot).Replace("\", "/")
    autoUpdated = $autoUpdated
    installedNew = $installedNew
    alreadyCurrent = $alreadyCurrent
    preservedCustomized = $preservedCustomized
    missingPreserved = $missingPreserved
  }

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("# UE Tool Suite Docs Smart Update Report") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("- Auto-updated files: $($Report.AutoUpdated.Count)") | Out-Null
  $lines.Add("- Newly installed defaults: $($Report.InstalledNew.Count)") | Out-Null
  $lines.Add("- Already current files: $($Report.AlreadyCurrent.Count)") | Out-Null
  $lines.Add("- Preserved customized files: $($Report.PreservedCustomized.Count)") | Out-Null
  $lines.Add("- Missing defaults preserved: $($Report.MissingPreserved.Count)") | Out-Null
  $lines.Add("") | Out-Null

  if ($Report.PreservedCustomized.Count -gt 0) {
    $lines.Add("## Preserved Customized Files") | Out-Null
    foreach ($entry in @($Report.PreservedCustomized | ForEach-Object { $_ })) {
      $lines.Add("- $($entry.relativePath) (`$reason=$($entry.reason)`) -> candidate: $($entry.candidateRelativePath)") | Out-Null
    }
    $lines.Add("") | Out-Null
  }

  if ($Report.MissingPreserved.Count -gt 0) {
    $lines.Add("## Missing Defaults (Not Recreated)") | Out-Null
    foreach ($entry in @($Report.MissingPreserved | ForEach-Object { $_ })) {
      $lines.Add("- $($entry.relativePath) -> candidate: $($entry.candidateRelativePath)") | Out-Null
    }
    $lines.Add("") | Out-Null
  }

  $lines.Add("Use the candidate files to manually merge payload updates into project-customized docs.") | Out-Null

  if ($PSCmdlet.ShouldProcess($jsonPath, "Write docs update report json")) {
    Write-Utf8NoBomFile -Path $jsonPath -Content ($jsonDocument | ConvertTo-Json -Depth 12)
  }
  if ($PSCmdlet.ShouldProcess($markdownPath, "Write docs update report markdown")) {
    Write-Utf8NoBomFile -Path $markdownPath -Content ($lines -join "`n")
  }

  return [pscustomobject]@{
    ReportRoot = $ReportRoot
    JsonPath = $jsonPath
    MarkdownPath = $markdownPath
  }
}

function Copy-DocsUpdateCandidate {
  param(
    [Parameter(Mandatory)][string]$ReportRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$TargetRoot
  )

  $relativeCandidatePath = (Join-Path "candidates" ($RelativePath -replace "/", "\")).Replace("\", "/")
  $candidatePath = Join-Path $ReportRoot ($relativeCandidatePath -replace "/", "\")
  $candidateParent = Split-Path -Path $candidatePath -Parent
  if ($candidateParent -and -not (Test-PathInsideRoot -Root $TargetRoot -Path $candidateParent)) {
    throw "Refusing to write docs update candidate outside target repo root: $candidatePath"
  }

  if ($candidateParent -and $PSCmdlet.ShouldProcess($candidateParent, "Ensure docs update candidate directory")) {
    New-Item -ItemType Directory -Force -Path $candidateParent | Out-Null
  }
  if ($PSCmdlet.ShouldProcess($candidatePath, "Write docs update candidate file")) {
    Copy-Item -LiteralPath $SourcePath -Destination $candidatePath -Force
  }

  return (Get-RelativePathCompat -BasePath $TargetRoot -TargetPath $candidatePath).Replace("\", "/")
}

function Invoke-ManagedDocsSmartUpdate {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$BackupRoot,
    [Parameter(Mandatory)]$PayloadManifest,
    [Parameter(Mandatory)][string]$InstallStamp,
    [Parameter(Mandatory)]$InstalledList,
    [hashtable]$OverrideMap = @{},
    [switch]$IncludeCodingStandards
  )

  $index = Read-DocsManagedFileIndex -PayloadRoot $PayloadRoot -PayloadManifest $PayloadManifest
  $selectedFiles = @($index.Files | Where-Object {
      $_.category.Equals("docs", [System.StringComparison]::OrdinalIgnoreCase) -or
      $_.category.Equals("docsShell", [System.StringComparison]::OrdinalIgnoreCase) -or
      ($IncludeCodingStandards -and $_.category.Equals("codingStandards", [System.StringComparison]::OrdinalIgnoreCase))
    })
  if ($selectedFiles.Count -eq 0) {
    return
  }

  $ledger = Read-ManagedDocsLedger -TargetRoot $TargetRoot
  $entriesByPath = @{}
  foreach ($existingKey in @($ledger.EntriesByPath.Keys)) {
    $entriesByPath[$existingKey] = $ledger.EntriesByPath[$existingKey]
  }

  $report = @{
    AutoUpdated = New-Object System.Collections.Generic.List[object]
    InstalledNew = New-Object System.Collections.Generic.List[object]
    AlreadyCurrent = New-Object System.Collections.Generic.List[object]
    PreservedCustomized = New-Object System.Collections.Generic.List[object]
    MissingPreserved = New-Object System.Collections.Generic.List[object]
  }
  $reportRoot = Join-Path $TargetRoot ".ue-tools-installer-updates\$InstallStamp"
  $docsRoot = Join-Path $TargetRoot "Docs"
  $targetHasExistingDocsTree = $false
  if (Test-Path -LiteralPath $docsRoot -PathType Container) {
    $existingDocsArtifacts = @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @(".md", ".mdx", ".json") -or $_.Name.Equals("_category_.json", [System.StringComparison]::OrdinalIgnoreCase)
      })
    $targetHasExistingDocsTree = $existingDocsArtifacts.Count -gt 0
  }

  foreach ($file in $selectedFiles) {
    $relativePath = ConvertTo-RelativeForwardSlashPath -RelativePath ([string]$file.relativePath)
    $sourcePath = Join-Path $PayloadRoot ($relativePath -replace "/", "\")
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
      throw "Managed docs source file is missing from payload: $relativePath"
    }

    $targetPath = Join-Path $TargetRoot ($relativePath -replace "/", "\")
    if (-not (Test-PathInsideRoot -Root $TargetRoot -Path $targetPath)) {
      throw "Refusing to update docs file outside target repo root: $targetPath"
    }

    $payloadHash = ([string]$file.sha256).ToLowerInvariant()
    $nowUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $category = [string]$file.category
    $isDocsShell = $category.Equals("docsShell", [System.StringComparison]::OrdinalIgnoreCase)
    $ledgerEntry = $entriesByPath[$relativePath]
    $overrideMode = if ($OverrideMap.ContainsKey($relativePath)) { [string]$OverrideMap[$relativePath] } else { "" }

    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
      $currentHash = Get-FileSha256 -Path $targetPath

      if ($overrideMode -eq "suite" -and -not $currentHash.Equals($payloadHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        Copy-ToBackup -TargetRoot $TargetRoot -RelativePath ($relativePath -replace "/", "\") -ExistingPath $targetPath -BackupRoot $BackupRoot
        if ($PSCmdlet.ShouldProcess($targetPath, "Force suite-managed docs file update")) {
          Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }
        $entriesByPath[$relativePath] = [pscustomobject]@{
          relativePath = $relativePath
          installedPayloadVersion = [string]$PayloadManifest.PayloadVersion
          installedHash = $payloadHash
          updatedUtc = $nowUtc
          category = $category
        }
        $InstalledList.Add($relativePath) | Out-Null
        $report.AutoUpdated.Add([pscustomobject]@{ relativePath = $relativePath }) | Out-Null
        continue
      }

      if ($currentHash.Equals($payloadHash, [System.StringComparison]::OrdinalIgnoreCase)) {
        $entriesByPath[$relativePath] = [pscustomobject]@{
          relativePath = $relativePath
          installedPayloadVersion = [string]$PayloadManifest.PayloadVersion
          installedHash = $payloadHash
          updatedUtc = $nowUtc
          category = $category
        }
        $report.AlreadyCurrent.Add([pscustomobject]@{ relativePath = $relativePath }) | Out-Null
        continue
      }

      if ($overrideMode -eq "project") {
        $candidateRelative = Copy-DocsUpdateCandidate -ReportRoot $reportRoot -RelativePath $relativePath -SourcePath $sourcePath -TargetRoot $TargetRoot
        $report.PreservedCustomized.Add([pscustomobject]@{
          relativePath = $relativePath
          reason = "explicit-project-override"
          candidateRelativePath = $candidateRelative
        }) | Out-Null
        continue
      }

      $canAutoUpdate = $false
      if ($null -ne $ledgerEntry) {
        $installedHash = [string]$ledgerEntry.installedHash
        if (-not [string]::IsNullOrWhiteSpace($installedHash) -and $currentHash.Equals($installedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
          $canAutoUpdate = $true
        }
      }

      if ($canAutoUpdate) {
        Copy-ToBackup -TargetRoot $TargetRoot -RelativePath ($relativePath -replace "/", "\") -ExistingPath $targetPath -BackupRoot $BackupRoot
        if ($PSCmdlet.ShouldProcess($targetPath, "Auto-update managed docs file")) {
          Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        }

        $entriesByPath[$relativePath] = [pscustomobject]@{
          relativePath = $relativePath
          installedPayloadVersion = [string]$PayloadManifest.PayloadVersion
          installedHash = $payloadHash
          updatedUtc = $nowUtc
          category = $category
        }
        $InstalledList.Add($relativePath) | Out-Null
        $report.AutoUpdated.Add([pscustomobject]@{ relativePath = $relativePath }) | Out-Null
        continue
      }

      $candidateRelative = Copy-DocsUpdateCandidate -ReportRoot $reportRoot -RelativePath $relativePath -SourcePath $sourcePath -TargetRoot $TargetRoot
      $reason = if ($null -eq $ledgerEntry) { "no-ledger-entry" } else { "modified-since-last-managed-version" }
      $report.PreservedCustomized.Add([pscustomobject]@{
        relativePath = $relativePath
        reason = $reason
        candidateRelativePath = $candidateRelative
      }) | Out-Null
      continue
    }

    if (Test-Path -LiteralPath $targetPath -PathType Container) {
      $candidateRelative = Copy-DocsUpdateCandidate -ReportRoot $reportRoot -RelativePath $relativePath -SourcePath $sourcePath -TargetRoot $TargetRoot
      $report.PreservedCustomized.Add([pscustomobject]@{
        relativePath = $relativePath
        reason = "path-conflict-directory"
        candidateRelativePath = $candidateRelative
      }) | Out-Null
      continue
    }

    if ($null -ne $ledgerEntry) {
      $candidateRelative = Copy-DocsUpdateCandidate -ReportRoot $reportRoot -RelativePath $relativePath -SourcePath $sourcePath -TargetRoot $TargetRoot
      $report.MissingPreserved.Add([pscustomobject]@{
        relativePath = $relativePath
        reason = "missing-from-target"
        candidateRelativePath = $candidateRelative
      }) | Out-Null
      continue
    }

    if ($targetHasExistingDocsTree -and -not $isDocsShell -and $overrideMode -ne "suite") {
      $candidateRelative = Copy-DocsUpdateCandidate -ReportRoot $reportRoot -RelativePath $relativePath -SourcePath $sourcePath -TargetRoot $TargetRoot
      $report.MissingPreserved.Add([pscustomobject]@{
        relativePath = $relativePath
        reason = "existing-project-docs-tree"
        candidateRelativePath = $candidateRelative
      }) | Out-Null
      continue
    }

    $targetParent = Split-Path -Path $targetPath -Parent
    if ($targetParent -and $PSCmdlet.ShouldProcess($targetParent, "Ensure managed docs directory")) {
      New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($targetPath, "Install managed docs default file")) {
      Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }

    $entriesByPath[$relativePath] = [pscustomobject]@{
      relativePath = $relativePath
      installedPayloadVersion = [string]$PayloadManifest.PayloadVersion
      installedHash = $payloadHash
      updatedUtc = $nowUtc
      category = $category
    }
    $InstalledList.Add($relativePath) | Out-Null
    $report.InstalledNew.Add([pscustomobject]@{ relativePath = $relativePath }) | Out-Null
  }

  Write-ManagedDocsLedger -TargetRoot $TargetRoot -EntriesByPath $entriesByPath -PayloadVersion ([string]$PayloadManifest.PayloadVersion
  )

  $reportPaths = Write-DocsSmartUpdateReport -TargetRoot $TargetRoot -ReportRoot $reportRoot -Report $report
  if ($null -ne $reportPaths) {
    Warn ("Preserved customized docs files were not overwritten. Review update report: {0}" -f $reportPaths.MarkdownPath)
  }
}

function Get-ManagedTextBlockMarkers {
  param([Parameter(Mandatory)][string]$RelativePath)

  switch ($RelativePath) {
    ".gitattributes" {
      return [pscustomobject]@{
        Start = "# >>> ue tool suite git attributes >>>"
        End   = "# <<< ue tool suite git attributes <<<"
      }
    }
    ".gitignore" {
      return [pscustomobject]@{
        Start = "# >>> ue tool suite git ignore >>>"
        End   = "# <<< ue tool suite git ignore <<<"
      }
    }
    default {
      throw "No managed text block markers are defined for: $RelativePath"
    }
  }
}

function ConvertTo-NormalizedLfText {
  param([AllowEmptyString()][string]$Text)

  if ($null -eq $Text) {
    return ""
  }

  return (($Text -replace "`r`n", "`n") -replace "`r", "`n")
}

function ConvertTo-ManagedTextLines {
  param([AllowEmptyString()][string]$Text)

  if ([string]::IsNullOrEmpty($Text)) {
    return @()
  }

  $trimmed = $Text.TrimEnd("`n")
  if ($trimmed.Length -eq 0) {
    return @()
  }

  return @($trimmed.Split("`n"))
}

function Get-ManagedTextEntryKey {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Line
  )

  $trimmed = $Line.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
    return $null
  }

  switch ($RelativePath) {
    ".gitattributes" { return (($trimmed -split "\s+") -join " ") }
    default { return $trimmed }
  }
}

function Get-ManagedTextPayloadDefinition {
  param(
    [Parameter(Mandatory)][string]$SourceText,
    [Parameter(Mandatory)][pscustomobject]$Markers,
    [Parameter(Mandatory)][string]$RelativePath
  )

  $normalizedSourceText = ConvertTo-NormalizedLfText -Text $SourceText
  $sourceLines = @(ConvertTo-ManagedTextLines -Text $normalizedSourceText)
  $startIndex = [Array]::IndexOf($sourceLines, $Markers.Start)
  $endIndex = [Array]::IndexOf($sourceLines, $Markers.End)
  if ($startIndex -lt 0 -or $endIndex -le $startIndex) {
    throw "Managed text payload is missing expected marker block: $RelativePath"
  }

  $bodyLines = if ($endIndex -gt ($startIndex + 1)) {
    @($sourceLines[($startIndex + 1)..($endIndex - 1)])
  }
  else {
    @()
  }

  $entryKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($line in $bodyLines) {
    $entryKey = Get-ManagedTextEntryKey -RelativePath $RelativePath -Line $line
    if ($null -ne $entryKey) {
      [void]$entryKeys.Add($entryKey)
    }
  }

  return [pscustomobject]@{
    BlockText = ($normalizedSourceText.TrimEnd("`n") + "`n")
    BodyLines = $bodyLines
    EntryKeys = $entryKeys
  }
}

function Remove-ManagedTextLineSequence {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Sequence
  )

  if ($Sequence.Count -eq 0 -or $Lines.Count -lt $Sequence.Count) {
    return @($Lines)
  }

  $result = New-Object System.Collections.Generic.List[string]
  for ($index = 0; $index -lt $Lines.Count;) {
    $isMatch = $true
    if (($index + $Sequence.Count) -gt $Lines.Count) {
      $isMatch = $false
    }
    else {
      for ($sequenceIndex = 0; $sequenceIndex -lt $Sequence.Count; $sequenceIndex++) {
        if ($Lines[$index + $sequenceIndex] -ne $Sequence[$sequenceIndex]) {
          $isMatch = $false
          break
        }
      }
    }

    if ($isMatch) {
      $index += $Sequence.Count
      continue
    }

    [void]$result.Add([string]$Lines[$index])
    $index++
  }

  return @($result.ToArray())
}

function Clean-ManagedTextUnmanagedSection {
  param(
    [AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][pscustomobject]$PayloadDefinition,
    [Parameter(Mandatory)][string]$RelativePath
  )

  $lines = @(ConvertTo-ManagedTextLines -Text (ConvertTo-NormalizedLfText -Text $Text))
  $withoutLegacyBlock = @(Remove-ManagedTextLineSequence -Lines $lines -Sequence $PayloadDefinition.BodyLines)

  $filteredLines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $withoutLegacyBlock) {
    $entryKey = Get-ManagedTextEntryKey -RelativePath $RelativePath -Line $line
    if ($null -ne $entryKey -and $PayloadDefinition.EntryKeys.Contains($entryKey)) {
      continue
    }

    [void]$filteredLines.Add([string]$line)
  }

  if ($filteredLines.Count -eq 0) {
    return ""
  }

  return (($filteredLines.ToArray() -join "`n").TrimEnd("`n"))
}

function Join-ManagedTextSections {
  param(
    [AllowEmptyCollection()][string[]]$Sections
  )

  $contentSections = @(
    @($Sections) |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { ([string]$_).TrimEnd("`n") }
  )

  if ($contentSections.Count -eq 0) {
    return ""
  }

  return (($contentSections -join "`n`n").TrimEnd("`n") + "`n")
}

function Update-ManagedTextFile {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$BackupRoot
  )

  $source = Join-Path $SourceRoot $RelativePath
  $destination = Join-Path $TargetRoot $RelativePath

  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Required managed text payload missing: $source"
  }

  if (-not (Test-PathInsideRoot -Root $TargetRoot -Path $destination)) {
    throw "Refusing to update managed text file outside target repo root: $destination"
  }

  $sourceText = Get-Content -LiteralPath $source -Raw
  $markers = Get-ManagedTextBlockMarkers -RelativePath $RelativePath
  $payloadDefinition = Get-ManagedTextPayloadDefinition -SourceText $sourceText -Markers $markers -RelativePath $RelativePath

  $destinationParent = Split-Path -Path $destination -Parent
  if (-not (Test-Path -LiteralPath $destination)) {
    if ($destinationParent -and $PSCmdlet.ShouldProcess($destinationParent, "Ensure destination directory")) {
      New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($destination, "Install managed text file $RelativePath")) {
      Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    return $true
  }

  $targetText = Get-Content -LiteralPath $destination -Raw
  $normalizedTargetText = ConvertTo-NormalizedLfText -Text $targetText
  $blockPattern = "(?ms)^" + [regex]::Escape($markers.Start) + "\n.*?^" + [regex]::Escape($markers.End) + "\n?"
  $match = [regex]::Match($normalizedTargetText, $blockPattern)

  if ($match.Success) {
    $prefix = Clean-ManagedTextUnmanagedSection -Text $normalizedTargetText.Substring(0, $match.Index) -PayloadDefinition $payloadDefinition -RelativePath $RelativePath
    $suffix = Clean-ManagedTextUnmanagedSection -Text $normalizedTargetText.Substring($match.Index + $match.Length) -PayloadDefinition $payloadDefinition -RelativePath $RelativePath
    $updatedText = Join-ManagedTextSections -Sections @($prefix, $payloadDefinition.BlockText, $suffix)
  }
  else {
    $cleanedTargetText = Clean-ManagedTextUnmanagedSection -Text $normalizedTargetText -PayloadDefinition $payloadDefinition -RelativePath $RelativePath
    $updatedText = Join-ManagedTextSections -Sections @($cleanedTargetText, $payloadDefinition.BlockText)
  }

  if ($updatedText -eq $targetText) {
    return $true
  }

  Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $destination -BackupRoot $BackupRoot
  if ($PSCmdlet.ShouldProcess($destination, "Update managed text block in $RelativePath")) {
    Write-Utf8NoBomFile -Path $destination -Content $updatedText
  }

  return $true
}

function Copy-ManagedItem {
  param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$BackupRoot,
    [switch]$Optional
  )

  $source = Join-Path $SourceRoot $RelativePath
  $destination = Join-Path $TargetRoot $RelativePath

  if (-not (Test-Path -LiteralPath $source)) {
    if ($Optional) {
      Warn "Optional payload path missing, skipping: $RelativePath"
      return $false
    }

    throw "Required payload path missing: $source"
  }

  if (-not (Test-PathInsideRoot -Root $TargetRoot -Path $destination)) {
    throw "Refusing to copy outside target repo root: $destination"
  }

  $destinationParent = Split-Path -Path $destination -Parent
  if ($destinationParent -and -not (Test-PathInsideRoot -Root $TargetRoot -Path $destinationParent)) {
    throw "Refusing to create directory outside target repo root: $destinationParent"
  }

  $sourceIsDirectory = Test-Path -LiteralPath $source -PathType Container
  $destinationExists = Test-Path -LiteralPath $destination
  $destinationIsDirectory = Test-Path -LiteralPath $destination -PathType Container
  $relativePathNormalized = ($RelativePath.Replace("/", "\").Trim("\")).ToLowerInvariant()
  $excludeDirectoryPrefixes = @()
  if ($relativePathNormalized -eq "website") {
    $excludeDirectoryPrefixes = @(
      "node_modules\",
      "build\",
      ".docusaurus\",
      ".cache\"
    )
  }

  if ($sourceIsDirectory -and (($destinationExists -and $destinationIsDirectory) -or $excludeDirectoryPrefixes.Count -gt 0)) {
    if ($destinationExists -and -not $destinationIsDirectory) {
      Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $destination -BackupRoot $BackupRoot
      if ($PSCmdlet.ShouldProcess($destination, "Replace conflicting file with managed directory")) {
        Remove-Item -LiteralPath $destination -Force
      }
      $destinationExists = $false
      $destinationIsDirectory = $false
    }

    if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
      if ($destinationParent -and $PSCmdlet.ShouldProcess($destinationParent, "Ensure destination directory")) {
        New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
      }
      if ($PSCmdlet.ShouldProcess($destination, "Ensure managed directory")) {
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
      }
    }

    $sourceDirectories = @(Get-ChildItem -LiteralPath $source -Recurse -Directory -Force)
    foreach ($sourceDirectory in $sourceDirectories) {
      $childRelativePath = Get-RelativePathCompat -BasePath $source -TargetPath $sourceDirectory.FullName
      $childRelativePathNormalized = ($childRelativePath.Replace("/", "\").Trim("\")).ToLowerInvariant()
      if ($excludeDirectoryPrefixes.Count -gt 0) {
        $shouldExcludeDirectory = $false
        foreach ($prefix in $excludeDirectoryPrefixes) {
          if ($childRelativePathNormalized -eq $prefix.TrimEnd("\")) {
            $shouldExcludeDirectory = $true
            break
          }
          if ($childRelativePathNormalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $shouldExcludeDirectory = $true
            break
          }
        }
        if ($shouldExcludeDirectory) {
          continue
        }
      }

      $targetDirectory = Join-Path $destination $childRelativePath
      if (-not (Test-PathInsideRoot -Root $TargetRoot -Path $targetDirectory)) {
        throw "Refusing to create directory outside target repo root: $targetDirectory"
      }
      if ((Test-Path -LiteralPath $targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
        $backupRelativePath = Join-Path $RelativePath $childRelativePath
        Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $backupRelativePath -ExistingPath $targetDirectory -BackupRoot $BackupRoot
        if ($PSCmdlet.ShouldProcess($targetDirectory, "Replace conflicting file with managed directory")) {
          Remove-Item -LiteralPath $targetDirectory -Force
        }
      }
      if ($PSCmdlet.ShouldProcess($targetDirectory, "Ensure managed directory")) {
        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
      }
    }

    $sourceFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File -Force)
    foreach ($sourceFile in $sourceFiles) {
      $childRelativePath = Get-RelativePathCompat -BasePath $source -TargetPath $sourceFile.FullName
      $childRelativePathNormalized = ($childRelativePath.Replace("/", "\").Trim("\")).ToLowerInvariant()
      if ($excludeDirectoryPrefixes.Count -gt 0) {
        $shouldExcludeFile = $false
        foreach ($prefix in $excludeDirectoryPrefixes) {
          if ($childRelativePathNormalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $shouldExcludeFile = $true
            break
          }
        }
        if ($shouldExcludeFile) {
          continue
        }
      }

      $targetFile = Join-Path $destination $childRelativePath
      if (-not (Test-PathInsideRoot -Root $TargetRoot -Path $targetFile)) {
        throw "Refusing to copy outside target repo root: $targetFile"
      }

      $targetParent = Split-Path -Path $targetFile -Parent
      if ($targetParent -and $PSCmdlet.ShouldProcess($targetParent, "Ensure destination directory")) {
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
      }

      if (Test-Path -LiteralPath $targetFile) {
        $backupRelativePath = Join-Path $RelativePath $childRelativePath
        Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $backupRelativePath -ExistingPath $targetFile -BackupRoot $BackupRoot
        if (Test-Path -LiteralPath $targetFile -PathType Container) {
          if ($PSCmdlet.ShouldProcess($targetFile, "Replace conflicting directory with managed file")) {
            Remove-Item -LiteralPath $targetFile -Recurse -Force
          }
        }
      }

      if ($PSCmdlet.ShouldProcess($targetFile, "Install $RelativePath managed file")) {
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetFile -Force
      }
    }

    return $true
  }

  if (Test-Path -LiteralPath $destination) {
    Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $destination -BackupRoot $BackupRoot
    if ($PSCmdlet.ShouldProcess($destination, "Replace managed UE tool suite path")) {
      Remove-Item -LiteralPath $destination -Recurse -Force
    }
  }

  if ($destinationParent -and $PSCmdlet.ShouldProcess($destinationParent, "Ensure destination directory")) {
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
  }

  if ($PSCmdlet.ShouldProcess($destination, "Install $RelativePath")) {
    Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
  }

  return $true
}

function Remove-LegacyTargetPath {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$BackupRoot
  )

  $target = Join-Path $TargetRoot $RelativePath
  if (-not (Test-Path -LiteralPath $target)) { return }

  Copy-ToBackup -TargetRoot $TargetRoot -RelativePath $RelativePath -ExistingPath $target -BackupRoot $BackupRoot
  if ($PSCmdlet.ShouldProcess($target, "Remove legacy in-project installer path")) {
    Remove-Item -LiteralPath $target -Recurse -Force
  }
}

$resolvedPayloadRoot = if ([string]::IsNullOrWhiteSpace($PayloadRoot)) {
  Resolve-ExistingDirectory -Path (Get-DefaultPayloadRoot) -Name "PayloadRoot"
}
else {
  Resolve-ExistingDirectory -Path $PayloadRoot -Name "PayloadRoot"
}

$resolvedTargetRoot = Resolve-ExistingDirectory -Path $TargetRepoRoot -Name "TargetRepoRoot"
$targetUProject = Resolve-TargetUProjectPath -RepoRoot $resolvedTargetRoot -UProjectPath $TargetUProjectPath
Test-TargetLooksLikeUE5Project -UProjectPath $targetUProject

$installStamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$backupRoot = Join-Path $resolvedTargetRoot (".ue-tools-installer-backups\" + $installStamp)

Info "Payload: $resolvedPayloadRoot"
Info "Target repo: $resolvedTargetRoot"
Info "Target project: $targetUProject"
if (-not $NoBackup) { Info "Backup root for replaced paths: $backupRoot" }
 
$payloadManifest = Read-UEToolSuitePayloadManifest -PayloadRoot $resolvedPayloadRoot
Info "Payload manifest: $($payloadManifest.ManifestPath)"

$resolvedWebsiteInstallMode = $null
$websiteRequestedModeWasExplicit = $PSBoundParameters.ContainsKey("WebsiteInstallMode")
$websiteOverridesState = $null
$websiteOverrideMap = @{}
if (-not $SkipWebsite) {
  $resolvedWebsiteInstallMode = Resolve-WebsiteInstallMode `
    -TargetRoot $resolvedTargetRoot `
    -RequestedInstallMode $WebsiteInstallMode `
    -AdoptExisting:$AdoptExistingWebsite `
    -WebsiteWasExplicitlyRequested:$websiteRequestedModeWasExplicit
  if ($resolvedWebsiteInstallMode -eq "preserve_existing") {
    Warn "Existing website directory is not managed by this installer. Preserving current Docusaurus site; website payload and theme override are skipped."
    if (-not [string]::IsNullOrWhiteSpace($WebsiteTheme) -or -not [string]::IsNullOrWhiteSpace($WebsiteLogoPath) -or -not [string]::IsNullOrWhiteSpace($WebsiteFaviconPath) -or -not [string]::IsNullOrWhiteSpace($WebsiteSocialCardPath)) {
      Warn "Website theme/branding overrides were provided but are blocked for unmanaged sites. Re-run with -WebsiteInstallMode MergeExisting or run 'ue-tools docs theme apply -Theme <id> --adopt-existing' later."
    }
  }
  else {
    $websiteOverridesState = Read-WebsiteSiteOverrides -TargetRoot $resolvedTargetRoot
    $websiteOverrideMap = Resolve-WebsiteOverrideMap `
      -PersistedOverrideDocument $websiteOverridesState.Document `
      -ForceSuitePaths $WebsiteForceSuitePath `
      -ForceProjectPaths $WebsiteForceProjectPath
  }
}

$managedItems = New-Object System.Collections.Generic.List[string]
foreach ($item in @($payloadManifest.ManagedBaseItems)) {
  [void]$managedItems.Add($item)
}

if (-not $SkipArtSourceTools) {
  foreach ($item in @($payloadManifest.ManagedArtToolsItems)) {
    [void]$managedItems.Add($item)
  }
}
if (-not $SkipAITools) {
  foreach ($item in @($payloadManifest.ManagedAIToolsItems)) {
    [void]$managedItems.Add($item)
  }
}
if (-not $SkipTests) {
  foreach ($item in @($payloadManifest.ManagedTestsItems)) {
    [void]$managedItems.Add($item)
  }
}

if ((-not $SkipWebsite) -or (-not $SkipDocs)) {
  foreach ($item in @($payloadManifest.ManagedDocsToolsItems)) {
    [void]$managedItems.Add($item)
  }
}

if ($resolvedWebsiteInstallMode -in @("merge_existing", "replace_existing")) {
  $existingWebsitePath = Join-Path $resolvedTargetRoot "website"
  if (Test-Path -LiteralPath $existingWebsitePath) {
    Copy-ToBackup `
      -TargetRoot $resolvedTargetRoot `
      -RelativePath "website-merge-snapshot" `
      -ExistingPath $existingWebsitePath `
      -BackupRoot $backupRoot `
      -ExcludeDirectoryPrefixes @(
        "node_modules\",
        "build\",
        ".docusaurus\",
        ".cache\"
      )
    Info "Backed up existing website before merge: $existingWebsitePath"
  }
}

$installed = New-Object System.Collections.Generic.List[string]
foreach ($item in @($payloadManifest.ManagedTextItems)) {
  if (Update-ManagedTextFile -SourceRoot $resolvedPayloadRoot -TargetRoot $resolvedTargetRoot -RelativePath $item -BackupRoot $backupRoot) {
    [void]$installed.Add($item)
  }
}

foreach ($item in @($managedItems.ToArray() | Sort-Object -Unique)) {
  if (Copy-ManagedItem -SourceRoot $resolvedPayloadRoot -TargetRoot $resolvedTargetRoot -RelativePath $item -BackupRoot $backupRoot -Optional) {
    [void]$installed.Add($item)
  }
}

if (-not $SkipWebsite -and $resolvedWebsiteInstallMode -ne "preserve_existing") {
  $websiteUpdateResult = Invoke-ManagedWebsiteUpdate `
    -PayloadRoot $resolvedPayloadRoot `
    -TargetRoot $resolvedTargetRoot `
    -BackupRoot $backupRoot `
    -PayloadManifest $payloadManifest `
    -InstallStamp $installStamp `
    -RequestedMode $resolvedWebsiteInstallMode `
    -OverrideMap $websiteOverrideMap
  if ($websiteUpdateResult.ReportPath) {
    Info "Website merge report: $($websiteUpdateResult.ReportPath)"
  }
}

if (-not $SkipDocs) {
  Invoke-ManagedDocsSmartUpdate `
    -PayloadRoot $resolvedPayloadRoot `
    -TargetRoot $resolvedTargetRoot `
    -BackupRoot $backupRoot `
    -PayloadManifest $payloadManifest `
    -InstallStamp $installStamp `
    -InstalledList $installed `
    -OverrideMap $websiteOverrideMap `
    -IncludeCodingStandards:(-not $SkipCodingStandardsTools)

  $docsSectionMigration = Invoke-InstalledDocsSectionMigration `
    -TargetRoot $resolvedTargetRoot `
    -InstallStamp $installStamp `
    -SkipMigration:$SkipDocsSectionMigration
  if ($docsSectionMigration.ReportPath) {
    Info "Docs section migration report: $($docsSectionMigration.ReportPath)"
  }
  if ($docsSectionMigration.Status -eq "skipped-by-parameter") {
    Warn "Skipped docs section migration by parameter."
  }
  elseif ($docsSectionMigration.Changed) {
    Info "Created docs section metadata files: $(@($docsSectionMigration.Result.CreatedFiles).Count)"
  }
}

if (-not $SkipWebsite -and $resolvedWebsiteInstallMode -ne "preserve_existing") {
  $themeResult = Apply-WebsiteThemeAndBranding `
    -PayloadRoot $resolvedPayloadRoot `
    -TargetRoot $resolvedTargetRoot `
    -TargetUProjectPath $targetUProject `
    -RequestedTheme $WebsiteTheme `
    -GlobalIconPath $WebsiteGlobalIconPath `
    -LogoPath $WebsiteLogoPath `
    -FaviconPath $WebsiteFaviconPath `
    -SocialCardPath $WebsiteSocialCardPath

  if ($null -ne $themeResult) {
    if ($null -eq $websiteOverridesState) {
      $websiteOverridesState = Read-WebsiteSiteOverrides -TargetRoot $resolvedTargetRoot
    }
    if ($null -eq $websiteOverridesState.Document.theme) {
      $websiteOverridesState.Document.theme = [ordered]@{}
    }
    $websiteOverridesState.Document.theme.themeId = [string]$themeResult.ThemeId
    $websiteOverridesState.Document.theme.logoPath = if ((-not [string]::IsNullOrWhiteSpace($WebsiteGlobalIconPath)) -or (-not [string]::IsNullOrWhiteSpace($WebsiteLogoPath))) { [string]$themeResult.LogoPath } else { "" }
    $websiteOverridesState.Document.theme.faviconPath = if ((-not [string]::IsNullOrWhiteSpace($WebsiteGlobalIconPath)) -or (-not [string]::IsNullOrWhiteSpace($WebsiteFaviconPath)) -or (-not [string]::IsNullOrWhiteSpace($WebsiteLogoPath))) { [string]$themeResult.FaviconPath } else { "" }
    $websiteOverridesState.Document.theme.socialCardPath = if ((-not [string]::IsNullOrWhiteSpace($WebsiteGlobalIconPath)) -or (-not [string]::IsNullOrWhiteSpace($WebsiteSocialCardPath)) -or (-not [string]::IsNullOrWhiteSpace($WebsiteLogoPath))) { [string]$themeResult.SocialCardPath } else { "" }
    $websiteOverridesState.Document.fileOverrides = @(
      foreach ($key in @($websiteOverrideMap.Keys | Sort-Object)) {
        [ordered]@{
          path = $key
          mode = [string]$websiteOverrideMap[$key]
        }
      }
    )
    Write-WebsiteSiteOverrides -TargetRoot $resolvedTargetRoot -Document $websiteOverridesState.Document

    Write-WebsiteOwnershipMarker `
      -TargetRoot $resolvedTargetRoot `
      -PayloadVersion ([string]$payloadManifest.PayloadVersion) `
      -ProjectName ([string]$themeResult.ProjectName) `
      -InstallMode ([string]$resolvedWebsiteInstallMode) `
      -ThemeId ([string]$themeResult.ThemeId) `
      -LogoPath ([string]$themeResult.LogoPath) `
      -FaviconPath ([string]$themeResult.FaviconPath) `
      -SocialCardPath ([string]$themeResult.SocialCardPath)
  }
}

if (-not $NoLegacyCleanup) {
  foreach ($legacyPath in @($payloadManifest.LegacyCleanupPaths)) {
    Remove-LegacyTargetPath -TargetRoot $resolvedTargetRoot -RelativePath $legacyPath -BackupRoot $backupRoot
  }
}

Ok "Installed/updated UE tool suite paths: $($installed.Count)"

if ($RunInit) {
  $dispatcherScript = Join-Path $resolvedTargetRoot "Scripts\ue-tools.ps1"
  $initArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $dispatcherScript,
    "-RepoRoot", $resolvedTargetRoot,
    "init",
    "-UProjectPath", $targetUProject
  )

  if ($SkipShellAliases) { $initArgs += "-SkipShellAliases" }
  if ($SkipLfsPull) { $initArgs += "-SkipLfsPull" }
  if ($SkipOptionalToolSetup) { $initArgs += "-SkipOptionalToolSetup" }
  if ($SkipDocsSetup) { $initArgs += "-SkipDocsSetup" }
  if ($SkipDocsSectionMigration) { $initArgs += "-SkipDocsSectionMigration" }
  if ($SkipDocsNpmInstall) { $initArgs += "-SkipDocsNpmInstall" }
  if ($ForceDocsNpmInstall) { $initArgs += "-ForceDocsNpmInstall" }
  if ($SkipDocsBridgeInstall) { $initArgs += "-SkipDocsBridgeInstall" }
  if ($SkipUnrealSync) { $initArgs += "-SkipUnrealSync" }
  if ($NoBuild) { $initArgs += "-NoBuild" }
  if ($NoRegen) { $initArgs += "-NoRegen" }
  if ($InitNonInteractive) { $initArgs += "-NonInteractive" }

  Info "Running target bootstrap: pwsh $($initArgs -join ' ')"
  if ($PSCmdlet.ShouldProcess($resolvedTargetRoot, "Run ue-tools init in target repo")) {
    & pwsh @initArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Target ue-tools init failed with exit code $LASTEXITCODE."
    }
  }
}
else {
  Info "Next step in the target repo:"
  Write-Host "  pwsh -NoProfile -ExecutionPolicy Bypass -File Scripts/ue-tools.ps1 -RepoRoot `"$resolvedTargetRoot`" init" -ForegroundColor Cyan
}

Ok "Done."
