# Installs or updates the portable UE 5 tooling payload into a target project.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory)][string]$TargetRepoRoot,
  [string]$PayloadRoot,
  [string]$TargetUProjectPath,
  [string]$WebsiteTheme = "neutral",
  [string]$WebsiteLogoPath,
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
    [Parameter(Mandatory)][string]$BackupRoot
  )

  if ($NoBackup) { return }

  $backupPath = Join-Path $BackupRoot $RelativePath
  $backupParent = Split-Path -Path $backupPath -Parent
  if ($backupParent) {
    New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
  }

  Copy-Item -LiteralPath $ExistingPath -Destination $backupPath -Recurse -Force
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

function Apply-WebsiteThemeAndBranding {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$TargetUProjectPath,
    [string]$RequestedTheme,
    [string]$LogoPath
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

  $themeDestinationPath = Join-Path $websiteRoot "src\css\custom.css"
  $themeDestinationParent = Split-Path -Path $themeDestinationPath -Parent
  if ($themeDestinationParent -and $PSCmdlet.ShouldProcess($themeDestinationParent, "Ensure website theme destination directory")) {
    New-Item -ItemType Directory -Force -Path $themeDestinationParent | Out-Null
  }
  if ($PSCmdlet.ShouldProcess($themeDestinationPath, "Apply website theme '$($themeEntry.id)'")) {
    Copy-Item -LiteralPath $themeSourcePath -Destination $themeDestinationPath -Force
  }

  $resolvedLogoPath = $null
  $logoRelativePath = [string]$themeEntry.logoPath
  $faviconRelativePath = [string]$themeEntry.faviconPath
  $socialCardRelativePath = [string]$themeEntry.socialCardPath
  if (-not [string]::IsNullOrWhiteSpace($LogoPath)) {
    $resolvedLogoPath = Resolve-ExistingFile -Path $LogoPath -Name "WebsiteLogoPath"
    $logoExtension = ([System.IO.Path]::GetExtension($resolvedLogoPath) ?? "").ToLowerInvariant()
    if (($logoExtension -ne ".svg") -and ($logoExtension -ne ".png")) {
      throw "WebsiteLogoPath must use .svg or .png. Received: $resolvedLogoPath"
    }

    $logoRelativePath = "img/branding/project-logo$logoExtension"
    $faviconRelativePath = $logoRelativePath
    $socialCardRelativePath = $logoRelativePath
    $logoDestination = Join-Path $websiteRoot ("static\" + $logoRelativePath.Replace("/", "\"))
    $logoDestinationParent = Split-Path -Path $logoDestination -Parent
    if ($logoDestinationParent -and $PSCmdlet.ShouldProcess($logoDestinationParent, "Ensure website branding directory")) {
      New-Item -ItemType Directory -Force -Path $logoDestinationParent | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($logoDestination, "Install website logo asset")) {
      Copy-Item -LiteralPath $resolvedLogoPath -Destination $logoDestination -Force
    }
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
    [Parameter(Mandatory)][string]$ThemeId
  )

  $markerPath = Get-WebsiteOwnershipMarkerPath -TargetRoot $TargetRoot
  $marker = [ordered]@{
    schemaVersion = 1
    managedBy = "UEToolSuiteInstaller"
    payloadVersion = $PayloadVersion
    projectName = $ProjectName
    installMode = $InstallMode
    themeId = $ThemeId
    updatedUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }

  if ($PSCmdlet.ShouldProcess($markerPath, "Write website ownership marker")) {
    Write-Utf8NoBomFile -Path $markerPath -Content ($marker | ConvertTo-Json -Depth 10)
  }
}

function Resolve-WebsiteInstallMode {
  param(
    [Parameter(Mandatory)][string]$TargetRoot,
    [switch]$AdoptExisting
  )

  $websitePath = Join-Path $TargetRoot "website"
  if (-not (Test-Path -LiteralPath $websitePath)) {
    return "install_new"
  }

  if (Test-WebsiteOwnershipMarkerInstalled -TargetRoot $TargetRoot) {
    return "managed_update"
  }

  if ($AdoptExisting) {
    return "adopt_existing"
  }

  return "preserve_existing"
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
    reportRoot = [System.IO.Path]::GetRelativePath($TargetRoot, $ReportRoot).Replace("\", "/")
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

  return [System.IO.Path]::GetRelativePath($TargetRoot, $candidatePath).Replace("\", "/")
}

function Invoke-ManagedDocsSmartUpdate {
  param(
    [Parameter(Mandatory)][string]$PayloadRoot,
    [Parameter(Mandatory)][string]$TargetRoot,
    [Parameter(Mandatory)][string]$BackupRoot,
    [Parameter(Mandatory)]$PayloadManifest,
    [Parameter(Mandatory)][string]$InstallStamp,
    [Parameter(Mandatory)]$InstalledList,
    [switch]$IncludeCodingStandards
  )

  $index = Read-DocsManagedFileIndex -PayloadRoot $PayloadRoot -PayloadManifest $PayloadManifest
  $selectedFiles = @($index.Files | Where-Object {
      $_.category.Equals("docs", [System.StringComparison]::OrdinalIgnoreCase) -or
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
    $ledgerEntry = $entriesByPath[$relativePath]

    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
      $currentHash = Get-FileSha256 -Path $targetPath

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
      $childRelativePath = [System.IO.Path]::GetRelativePath($source, $sourceDirectory.FullName)
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
      $childRelativePath = [System.IO.Path]::GetRelativePath($source, $sourceFile.FullName)
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

$websiteInstallMode = $null
if (-not $SkipWebsite) {
  $websiteInstallMode = Resolve-WebsiteInstallMode -TargetRoot $resolvedTargetRoot -AdoptExisting:$AdoptExistingWebsite
  if ($websiteInstallMode -eq "preserve_existing") {
    Warn "Existing website directory is not managed by this installer. Preserving current Docusaurus site; website payload and theme override are skipped."
    if (-not [string]::IsNullOrWhiteSpace($WebsiteTheme) -or -not [string]::IsNullOrWhiteSpace($WebsiteLogoPath)) {
      Warn "WebsiteTheme/WebsiteLogoPath were provided but are blocked for unmanaged sites. Re-run with -AdoptExistingWebsite to adopt + override now, or run 'ue-tools docs theme apply -Theme <id> --adopt-existing' later."
    }
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

if (-not $SkipWebsite -and $websiteInstallMode -ne "preserve_existing") {
  foreach ($item in @($payloadManifest.ManagedWebsiteItems)) {
    [void]$managedItems.Add($item)
  }
}

if ($websiteInstallMode -eq "adopt_existing") {
  $existingWebsitePath = Join-Path $resolvedTargetRoot "website"
  if (Test-Path -LiteralPath $existingWebsitePath) {
    Copy-ToBackup -TargetRoot $resolvedTargetRoot -RelativePath "website-adopt-snapshot" -ExistingPath $existingWebsitePath -BackupRoot $backupRoot
    Info "Backed up existing website before adoption: $existingWebsitePath"
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

if (-not $SkipDocs) {
  Invoke-ManagedDocsSmartUpdate `
    -PayloadRoot $resolvedPayloadRoot `
    -TargetRoot $resolvedTargetRoot `
    -BackupRoot $backupRoot `
    -PayloadManifest $payloadManifest `
    -InstallStamp $installStamp `
    -InstalledList $installed `
    -IncludeCodingStandards:(-not $SkipCodingStandardsTools)
}

if (-not $SkipWebsite -and $websiteInstallMode -ne "preserve_existing") {
  $themeResult = Apply-WebsiteThemeAndBranding `
    -PayloadRoot $resolvedPayloadRoot `
    -TargetRoot $resolvedTargetRoot `
    -TargetUProjectPath $targetUProject `
    -RequestedTheme $WebsiteTheme `
    -LogoPath $WebsiteLogoPath

  if ($null -ne $themeResult) {
    Write-WebsiteOwnershipMarker `
      -TargetRoot $resolvedTargetRoot `
      -PayloadVersion ([string]$payloadManifest.PayloadVersion) `
      -ProjectName ([string]$themeResult.ProjectName) `
      -InstallMode ([string]$websiteInstallMode) `
      -ThemeId ([string]$themeResult.ThemeId)
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
