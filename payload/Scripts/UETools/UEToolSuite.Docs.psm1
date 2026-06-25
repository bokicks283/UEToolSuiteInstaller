$coreModulePath = Join-Path $PSScriptRoot 'UEToolSuite.Core.psm1'

if (-not (Test-Path -LiteralPath $coreModulePath -PathType Leaf)) {
  throw "Required UEToolSuite Core module was not found: $coreModulePath"
}

Import-Module -Name $coreModulePath -ErrorAction Stop

function Get-UEToolSuiteDocsNormalizedArgumentList {
  [CmdletBinding()]
  param([AllowNull()][string[]]$Values)

  $normalized = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }

    $stringValue = [string]$value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
      continue
    }

    $normalized.Add($stringValue) | Out-Null
  }

  return $normalized.ToArray()
}

function Resolve-UEToolSuiteDocsCommandAlias {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$CommandName)

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Test-UEToolSuiteDocsHelpToken {
  [CmdletBinding()]
  param([string]$Token)

  if ([string]::IsNullOrWhiteSpace($Token)) {
    return $false
  }

  $normalized = $Token.Trim().ToLowerInvariant()
  return ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?"))
}

function Split-UEToolSuiteDocsStartArguments {
  [CmdletBinding()]
  param([string[]]$StartArgsInput = @())

  $background = $false
  $passThroughArgs = New-Object System.Collections.Generic.List[string]
  foreach ($token in @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $StartArgsInput)) {
    $normalized = [string]$token
    if ($normalized -in @("--background", "-background")) {
      $background = $true
      continue
    }

    $passThroughArgs.Add($normalized) | Out-Null
  }

  return [pscustomobject]@{
    Background = $background
    StartArgs  = $passThroughArgs.ToArray()
  }
}

function Resolve-UEToolSuiteDocsHelpTopicAlias {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$CommandName)

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Get-UEToolSuiteDocsRootHelpText {
  [CmdletBinding()]
  param()

  @"
UE project docs automation.

Usage:
  ue-tools docs <command> [options]

Create:
  new-section, create-section   Create a docs section
  new-page, create-page         Create a page at Docs root or inside a section
  reorder                       Reorder a page or section and shift sibling positions
  migrate-sections              Normalize legacy docs sections into _category_.json sections
  visibility                    Hide/show a doc page from site navigation using front matter

Run:
  start                         Start Docusaurus (and the editor API) in the current terminal
  stop                          Stop the tracked background Docusaurus server
  status                        Show tracked background server status
  check                         Validate docs and run the production build
  doctor                        Check local docs prerequisites

Pass-through:
  build, clear, deploy, serve, swizzle
  write-translations, write-heading-ids, typecheck
  docusaurus <args...>

Other:
  install-bridge                Install the optional VS Code TOC bridge
  theme <list|apply>            List/apply docs website theme presets
  help [command]

Examples:
  ue-tools docs help new-section
  ue-tools docs create-section DocsSite -LinkType generated-index -GeneratedIndexSlug /docs-site
  ue-tools docs create-page Setup -Title "Setup"
  ue-tools docs create-page Workflow Daily-Flow -Title "Daily Flow" -SidebarLabel "Daily Flow"
  ue-tools docs reorder Art-Source 4
  ue-tools docs visibility Workflow/README hide
  ue-tools docs start --port 3001
  ue-tools docs start --background --port 3001
  ue-tools docs docusaurus docs:version 1.0.0 --skip-feedback
  ue-tools docs theme list
  ue-tools docs theme apply neutral

Notes:
  - Docs are authored in Docs/ and rendered by website/.
  - Inline page editing is available directly on docs pages when the local editor API is running.
  - TOC generation is optional and only runs when the bridge + Markdown All in One are installed.
  - Use ue-tools docs help <command> for detailed option help.
"@
}

function Test-UEToolSuiteDocsProcessRunning {
  [CmdletBinding()]
  param([int]$ProcessId)

  if ($ProcessId -le 0) {
    return $false
  }

  try {
    Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null
    return $true
  }
  catch {
    return $false
  }
}

function Get-UEToolSuiteDocsDescendantProcessId {
  [CmdletBinding()]
  param([int]$RootProcessId)

  if ($RootProcessId -le 0) {
    return $null
  }

  $queue = New-Object System.Collections.Generic.Queue[int]
  $queue.Enqueue($RootProcessId)

  while ($queue.Count -gt 0) {
    $parentId = $queue.Dequeue()

    try {
      $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId" -ErrorAction Stop)
    }
    catch {
      $children = @()
    }

    foreach ($child in $children) {
      $childId = [int]$child.ProcessId
      if (Test-UEToolSuiteDocsProcessRunning -ProcessId $childId) {
        return $childId
      }

      $queue.Enqueue($childId)
    }
  }

  return $null
}

function Get-UEToolSuiteDocsStartUrl {
  [CmdletBinding()]
  param([string[]]$StartArgs = @())

  $normalizedStartArgs = @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $StartArgs)
  $port = 3000
  for ($i = 0; $i -lt $normalizedStartArgs.Count; $i++) {
    $token = [string]$normalizedStartArgs[$i]
    if ($token -match '^--port=(?<port>\d+)$') {
      $parsedEqualsPort = 0
      if ([int]::TryParse($Matches.port, [ref]$parsedEqualsPort)) {
        $port = $parsedEqualsPort
      }
      break
    }

    if ($token -eq "--port" -or $token -eq "-p") {
      if (($i + 1) -lt $normalizedStartArgs.Count) {
        $parsedPort = 0
        if ([int]::TryParse([string]$normalizedStartArgs[$i + 1], [ref]$parsedPort)) {
          $port = $parsedPort
        }
      }
      break
    }
  }

  return "http://localhost:$port/docs/"
}

function Test-UEToolSuiteDocsCommandAvailable {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Name)

  return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}

function ConvertTo-UEToolSuiteDocsCmdArgument {
  [CmdletBinding()]
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  if ($Value.Length -eq 0) {
    return '""'
  }

  if ($Value -notmatch '[\s"&|<>^]') {
    return $Value
  }

  return '"' + ($Value -replace '"', '""') + '"'
}

function Get-UEToolSuiteDocsServerState {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$StatePath)

  if (-not (Test-Path -LiteralPath $StatePath)) {
    return $null
  }

  return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
}

function Remove-UEToolSuiteDocsServerState {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$StatePath)

  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
}

function Save-UEToolSuiteDocsServerState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$StatePath,
    [Parameter(Mandatory)][object]$State
  )

  $stateDirectory = Split-Path -Parent $StatePath
  if (-not [string]::IsNullOrWhiteSpace($stateDirectory)) {
    New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
  }

  $stateJson = $State | ConvertTo-Json -Depth 6
  if (Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue) {
    Write-UEToolSuiteUtf8NoBomFile -Path $StatePath -Content $stateJson
  }
  else {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($StatePath, $stateJson, $utf8NoBom)
  }
  return $StatePath
}

function Get-UEToolSuiteDocsWorkspaceRequestKey {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $normalized = [System.IO.Path]::GetFullPath($ResolvedRepoRoot).ToLowerInvariant()
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = $sha1.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
  }
  finally {
    $sha1.Dispose()
  }
}

function Get-UEToolSuiteDocsBridgeRequestDirectory {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $workspaceKey = Get-UEToolSuiteDocsWorkspaceRequestKey -ResolvedRepoRoot $ResolvedRepoRoot
  return (Join-Path ([System.IO.Path]::GetTempPath()) "ueproject-ue-tools-docs\$workspaceKey")
}

function New-UEToolSuiteDocsBridgeStatus {
  [CmdletBinding()]
  param(
    [string]$CodeCliPath,
    [bool]$MarkdownAllInOneInstalled = $false,
    [bool]$BridgeInstalled = $false
  )

  return [pscustomobject]@{
    CodeCliPath               = $CodeCliPath
    MarkdownAllInOneInstalled = [bool]$MarkdownAllInOneInstalled
    BridgeInstalled           = [bool]$BridgeInstalled
    TocReady                  = ([bool]$CodeCliPath -and [bool]$MarkdownAllInOneInstalled -and [bool]$BridgeInstalled)
  }
}

function Invoke-UEToolSuiteDocsCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $resolvedRepoRoot = $RepoRoot

  [string[]]$effectiveArgs = @()
  foreach ($argument in @($CommandArguments)) {
    if ($null -eq $argument) { continue }
    $effectiveArgs += [string]$argument
  }

  if (-not (Get-Command -Name "Invoke-DocsToolsMain" -CommandType Function -ErrorAction SilentlyContinue)) {
    throw "Docs command entrypoint function is unavailable in UEToolSuite.Docs.psm1."
  }

  $invokeParameters = @{
    ResolvedRepoRoot = $resolvedRepoRoot
  }
  if ($effectiveArgs.Count -gt 0) {
    $invokeParameters.CommandArguments = @($effectiveArgs)
  }

  Invoke-DocsToolsMain @invokeParameters
}

Export-ModuleMember -Function `
  Get-UEToolSuiteDocsNormalizedArgumentList, `
  Resolve-UEToolSuiteDocsCommandAlias, `
  Test-UEToolSuiteDocsHelpToken, `
  Split-UEToolSuiteDocsStartArguments, `
  Resolve-UEToolSuiteDocsHelpTopicAlias, `
  Get-UEToolSuiteDocsRootHelpText, `
  Test-UEToolSuiteDocsProcessRunning, `
  Get-UEToolSuiteDocsDescendantProcessId, `
  Get-UEToolSuiteDocsStartUrl, `
  Test-UEToolSuiteDocsCommandAvailable, `
  ConvertTo-UEToolSuiteDocsCmdArgument, `
  Get-UEToolSuiteDocsServerState, `
  Remove-UEToolSuiteDocsServerState, `
  Save-UEToolSuiteDocsServerState, `
  Get-UEToolSuiteDocsWorkspaceRequestKey, `
  Get-UEToolSuiteDocsBridgeRequestDirectory, `
  New-UEToolSuiteDocsBridgeStatus, `
  Invoke-UEToolSuiteDocsCommand, `
  Invoke-DocsToolsMain

# -----------------------------------------------------------------------------
# Migrated runtime implementation (DocsTools)
# Source previously lived in: payload/Scripts/UETools/UEToolSuite.Docs.psm1
# -----------------------------------------------------------------------------
$script:DocsToolsScriptsRoot = Split-Path -Parent $PSScriptRoot
$script:MarkdownAllInOneExtensionId = "yzhang.markdown-all-in-one"
$script:DocsToolsBridgeExtensionId = "ueproject.docs-tools-bridge"
$script:TocMarker = "<!-- docs-tools-toc -->"

function Get-DocsToolsRepoRoot {
  param([string]$ExplicitRepoRoot)

  $runtimeResolver = Get-Command -Name "Resolve-UEToolSuiteRuntimeRepoRoot" -ErrorAction SilentlyContinue
  if ($runtimeResolver) {
    return (Resolve-UEToolSuiteRuntimeRepoRoot -ScriptsRoot $script:DocsToolsScriptsRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "ue-tools docs")
  }

  if (Import-UEToolSuiteCoreModule) {
    $resolver = Get-Command -Name "Resolve-UEToolSuiteRepoRoot" -ErrorAction SilentlyContinue
    if ($resolver) {
      return (Resolve-UEToolSuiteRepoRoot -ExplicitRepoRoot $ExplicitRepoRoot -InvocationName "ue-tools docs")
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ExplicitRepoRoot)) {
    return [System.IO.Path]::GetFullPath($ExplicitRepoRoot)
  }

  $gitRoot = ((git rev-parse --show-toplevel 2>$null) | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($gitRoot)) {
    throw "ue-tools docs must be run from inside a git repository or passed -RepoRoot."
  }

  return $gitRoot.Trim()
}

function Get-DocsRoot {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path $ResolvedRepoRoot "Docs")
}

function Get-WebsiteRoot {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path $ResolvedRepoRoot "website")
}

function ConvertTo-DocsThemeSingleQuotedValue {
  param([AllowEmptyString()][string]$Value)

  return $Value.Replace("\", "\\").Replace("'", "\'")
}

function Set-DocsThemeSingleQuotedProperty {
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

  $escapedValue = ConvertTo-DocsThemeSingleQuotedValue -Value $Value
  return [regex]::Replace($Text, $Pattern, ('$1''{0}'',' -f $escapedValue), 1)
}

function Write-DocsThemeUtf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  if (Get-Command -Name "Write-UEToolSuiteUtf8NoBomFile" -ErrorAction SilentlyContinue) {
    Write-UEToolSuiteUtf8NoBomFile -Path $Path -Content $Content -EnsureParentDirectory
    return
  }

  $parent = Split-Path -Path $Path -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-DocsWebsiteOwnershipMarkerPath {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  return (Join-Path (Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot) ".ue-tools\ownership.json")
}

function Get-DocsWebsiteOverridesPath {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  return (Join-Path (Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot) ".ue-tools\site-overrides.json")
}

function Get-DefaultDocsWebsiteOverridesDocument {
  param(
    [string]$ThemeId = "neutral",
    [string]$LogoPath = "",
    [string]$FaviconPath = "",
    [string]$SocialCardPath = ""
  )

  return [ordered]@{
    schemaVersion = 1
    theme         = [ordered]@{
      themeId        = $ThemeId
      logoPath       = $LogoPath
      faviconPath    = $FaviconPath
      socialCardPath = $SocialCardPath
    }
    fileOverrides = @()
  }
}

function Get-DocsWebsiteOverrideCandidatePaths {
  return @(
    "website/docusaurus.config.ts",
    "website/src/css/project-overrides.css",
    "website/src/pages/index.tsx",
    "website/src/pages/index.module.css",
    "Docs/README.md"
  )
}

function Read-DocsWebsiteOverrides {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $path = Get-DocsWebsiteOverridesPath -ResolvedRepoRoot $ResolvedRepoRoot
  $defaultDocument = Get-DefaultDocsWebsiteOverridesDocument
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{
      Path     = $path
      Document = $defaultDocument
    }
  }

  try {
    $parsed = (Get-Content -LiteralPath $path -Raw) | ConvertFrom-Json
  }
  catch {
    return [pscustomobject]@{
      Path     = $path
      Document = $defaultDocument
    }
  }

  $fileOverrides = @()
  foreach ($entry in @($parsed.fileOverrides)) {
    if ($null -eq $entry) { continue }
    $relativePath = [string]$entry.path
    $mode = ([string]$entry.mode).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($relativePath) -or $mode -notin @("suite", "project")) {
      continue
    }
    $fileOverrides += [ordered]@{
      path = $relativePath.Replace("\", "/").TrimStart("/")
      mode = $mode
    }
  }

  return [pscustomobject]@{
    Path     = $path
    Document = [ordered]@{
      schemaVersion = 1
      theme         = [ordered]@{
        themeId        = if ([string]::IsNullOrWhiteSpace([string]$parsed.theme.themeId)) { "neutral" } else { [string]$parsed.theme.themeId }
        logoPath       = [string]$parsed.theme.logoPath
        faviconPath    = [string]$parsed.theme.faviconPath
        socialCardPath = [string]$parsed.theme.socialCardPath
      }
      fileOverrides = $fileOverrides
    }
  }
}

function Write-DocsWebsiteOverrides {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)]$Document
  )

  $path = Get-DocsWebsiteOverridesPath -ResolvedRepoRoot $ResolvedRepoRoot
  Write-DocsThemeUtf8NoBomFile -Path $path -Content ($Document | ConvertTo-Json -Depth 10)
}

function Test-DocsWebsiteManaged {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $markerPath = Get-DocsWebsiteOwnershipMarkerPath -ResolvedRepoRoot $ResolvedRepoRoot
  return (Test-Path -LiteralPath $markerPath -PathType Leaf)
}

function Write-DocsWebsiteOwnershipMarker {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$ThemeId,
    [string]$InstallMode = "managed_update",
    [string]$LogoPath = "",
    [string]$FaviconPath = "",
    [string]$SocialCardPath = "",
    [switch]$Adopted
  )

  $markerPath = Get-DocsWebsiteOwnershipMarkerPath -ResolvedRepoRoot $ResolvedRepoRoot
  $projectName = Split-Path -Leaf $ResolvedRepoRoot
  $marker = [ordered]@{
    schemaVersion  = 2
    managedBy      = "UEToolSuiteInstaller"
    projectName    = $projectName
    installMode    = $InstallMode
    theme          = [ordered]@{
      themeId        = $ThemeId
      logoPath       = $LogoPath
      faviconPath    = $FaviconPath
      socialCardPath = $SocialCardPath
    }
    overridePolicy = [ordered]@{
      schemaVersion       = 1
      source              = "site-overrides.json"
      adoptedViaDocsTheme = [bool]$Adopted
    }
    updatedUtc     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }

  Write-DocsThemeUtf8NoBomFile -Path $markerPath -Content ($marker | ConvertTo-Json -Depth 8)
}

function Resolve-DocsThemeProjectName {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $uprojects = @(Get-ChildItem -LiteralPath $ResolvedRepoRoot -Filter "*.uproject" -File -ErrorAction SilentlyContinue | Sort-Object Name)
  if ($uprojects.Count -gt 0) {
    return [System.IO.Path]::GetFileNameWithoutExtension($uprojects[0].Name)
  }

  return (Split-Path -Leaf $ResolvedRepoRoot)
}

function Read-DocsThemeCatalog {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $catalogPath = Join-Path (Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot) "theme-presets\theme-catalog.json"
  if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "Website theme catalog is missing: $catalogPath"
  }

  try {
    $catalog = (Get-Content -LiteralPath $catalogPath -Raw) | ConvertFrom-Json
  }
  catch {
    throw "Website theme catalog is not valid JSON: $catalogPath"
  }

  $themes = @($catalog.themes)
  if ($themes.Count -eq 0) {
    throw "Website theme catalog has no themes: $catalogPath"
  }

  return [pscustomobject]@{
    CatalogPath  = $catalogPath
    DefaultTheme = [string]$catalog.defaultTheme
    Themes       = @($themes | ForEach-Object {
        [pscustomobject]@{
          id             = ([string]$_.id).Trim()
          label          = ([string]$_.label).Trim()
          description    = [string]$_.description
          cssPath        = ([string]$_.cssPath).Trim()
          logoPath       = ([string]$_.logoPath).Trim().Replace("\", "/").TrimStart("/")
          faviconPath    = ([string]$_.faviconPath).Trim().Replace("\", "/").TrimStart("/")
          socialCardPath = ([string]$_.socialCardPath).Trim().Replace("\", "/").TrimStart("/")
        }
      })
  }
}

function Resolve-DocsThemeEntry {
  param(
    [Parameter(Mandatory)]$ThemeCatalog,
    [string]$ThemeId
  )

  $requested = if ([string]::IsNullOrWhiteSpace($ThemeId)) { [string]$ThemeCatalog.DefaultTheme } else { $ThemeId.Trim() }
  $match = @($ThemeCatalog.Themes | Where-Object { $_.id.Equals($requested, [System.StringComparison]::OrdinalIgnoreCase) })
  if ($match.Count -gt 0) {
    return $match[0]
  }

  $allowed = @($ThemeCatalog.Themes | ForEach-Object { $_.id } | Sort-Object -Unique)
  throw "Unknown website theme '$requested'. Allowed themes: $($allowed -join ', ')."
}

function Invoke-DocsThemeList {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $catalog = Read-DocsThemeCatalog -ResolvedRepoRoot $ResolvedRepoRoot
  $defaultTheme = [string]$catalog.DefaultTheme
  Write-Output ("Default theme: {0}" -f $defaultTheme)
  foreach ($theme in @($catalog.Themes | Sort-Object id)) {
    Write-Output ("- {0}: {1}" -f $theme.id, $theme.label)
  }
}

function Invoke-DocsThemeApply {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string]$ThemeId,
    [string]$LogoPath,
    [string]$FaviconPath,
    [string]$SocialCardPath,
    [switch]$AdoptExisting
  )

  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    throw "No website directory was found at '$websiteRoot'. Install website payload first."
  }

  $isManaged = Test-DocsWebsiteManaged -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not $isManaged -and -not $AdoptExisting) {
    throw "Website is unmanaged. Theme overrides are blocked by default. Re-run with 'ue-tools docs theme apply --adopt-existing' or use installer -WebsiteInstallMode MergeExisting."
  }

  $configPath = Join-Path $websiteRoot "docusaurus.config.ts"
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Docusaurus config is missing: $configPath"
  }

  $catalog = Read-DocsThemeCatalog -ResolvedRepoRoot $ResolvedRepoRoot
  $themeEntry = Resolve-DocsThemeEntry -ThemeCatalog $catalog -ThemeId $ThemeId
  $themeSourcePath = Join-Path $ResolvedRepoRoot ($themeEntry.cssPath -replace "/", "\")
  if (-not (Test-Path -LiteralPath $themeSourcePath -PathType Leaf)) {
    throw "Theme CSS file is missing for '$($themeEntry.id)': $themeSourcePath"
  }
  if ([string]::IsNullOrWhiteSpace($themeEntry.logoPath) -or [string]::IsNullOrWhiteSpace($themeEntry.faviconPath) -or [string]::IsNullOrWhiteSpace($themeEntry.socialCardPath)) {
    throw "Theme entry '$($themeEntry.id)' is missing logoPath/faviconPath/socialCardPath metadata in theme catalog."
  }
  $themeLogoPath = Join-Path $websiteRoot ("static\" + $themeEntry.logoPath.Replace("/", "\"))
  $themeFaviconPath = Join-Path $websiteRoot ("static\" + $themeEntry.faviconPath.Replace("/", "\"))
  $themeSocialCardPath = Join-Path $websiteRoot ("static\" + $themeEntry.socialCardPath.Replace("/", "\"))
  foreach ($asset in @(
      [pscustomobject]@{ Name = "logoPath"; Path = $themeLogoPath; Relative = [string]$themeEntry.logoPath },
      [pscustomobject]@{ Name = "faviconPath"; Path = $themeFaviconPath; Relative = [string]$themeEntry.faviconPath },
      [pscustomobject]@{ Name = "socialCardPath"; Path = $themeSocialCardPath; Relative = [string]$themeEntry.socialCardPath }
    )) {
    if (-not (Test-Path -LiteralPath $asset.Path -PathType Leaf)) {
      throw "Theme asset '$($asset.Name)' is missing for '$($themeEntry.id)': $($asset.Path) (catalog value: $($asset.Relative))"
    }
  }

  $themeDestination = Join-Path $websiteRoot "theme-presets\active-theme.css"
  $themeDestinationParent = Split-Path -Path $themeDestination -Parent
  if (-not [string]::IsNullOrWhiteSpace($themeDestinationParent)) {
    New-Item -ItemType Directory -Force -Path $themeDestinationParent | Out-Null
  }
  Copy-Item -LiteralPath $themeSourcePath -Destination $themeDestination -Force

  $projectName = Resolve-DocsThemeProjectName -ResolvedRepoRoot $ResolvedRepoRoot
  $docsTitle = "$projectName Docs"
  $tagline = "Repo tooling, Unreal workflow, and living project documentation for $projectName."
  $logoAlt = $docsTitle
  $logoRelativePath = [string]$themeEntry.logoPath
  $faviconRelativePath = [string]$themeEntry.faviconPath
  $socialCardRelativePath = [string]$themeEntry.socialCardPath
  if (-not [string]::IsNullOrWhiteSpace($LogoPath)) {
    if (-not (Test-Path -LiteralPath $LogoPath -PathType Leaf)) {
      throw "LogoPath does not exist or is not a file: $LogoPath"
    }

    $extension = [System.IO.Path]::GetExtension($LogoPath).ToLowerInvariant()
    if ($extension -ne ".svg" -and $extension -ne ".png") {
      throw "LogoPath must end with .svg or .png. Received: $LogoPath"
    }

    $logoRelativePath = "img/branding/project-logo$extension"
    $faviconRelativePath = $logoRelativePath
    $socialCardRelativePath = $logoRelativePath
    $logoDestination = Join-Path $websiteRoot ("static\" + $logoRelativePath.Replace("/", "\"))
    $logoParent = Split-Path -Path $logoDestination -Parent
    if (-not [string]::IsNullOrWhiteSpace($logoParent)) {
      New-Item -ItemType Directory -Force -Path $logoParent | Out-Null
    }
    Copy-Item -LiteralPath $LogoPath -Destination $logoDestination -Force
  }
  if (-not [string]::IsNullOrWhiteSpace($FaviconPath)) {
    if (-not (Test-Path -LiteralPath $FaviconPath -PathType Leaf)) {
      throw "FaviconPath does not exist or is not a file: $FaviconPath"
    }
    $extension = [System.IO.Path]::GetExtension($FaviconPath).ToLowerInvariant()
    if ($extension -notin @(".svg", ".png", ".ico")) {
      throw "FaviconPath must end with .svg, .png, or .ico. Received: $FaviconPath"
    }
    $faviconRelativePath = "img/branding/project-favicon$extension"
    $faviconDestination = Join-Path $websiteRoot ("static\" + $faviconRelativePath.Replace("/", "\"))
    $faviconParent = Split-Path -Path $faviconDestination -Parent
    if (-not [string]::IsNullOrWhiteSpace($faviconParent)) {
      New-Item -ItemType Directory -Force -Path $faviconParent | Out-Null
    }
    Copy-Item -LiteralPath $FaviconPath -Destination $faviconDestination -Force
  }
  elseif (-not [string]::IsNullOrWhiteSpace($LogoPath)) {
    $faviconRelativePath = $logoRelativePath
  }

  if (-not [string]::IsNullOrWhiteSpace($SocialCardPath)) {
    if (-not (Test-Path -LiteralPath $SocialCardPath -PathType Leaf)) {
      throw "SocialCardPath does not exist or is not a file: $SocialCardPath"
    }
    $extension = [System.IO.Path]::GetExtension($SocialCardPath).ToLowerInvariant()
    if ($extension -notin @(".svg", ".png", ".jpg", ".jpeg", ".webp")) {
      throw "SocialCardPath must end with .svg, .png, .jpg, .jpeg, or .webp. Received: $SocialCardPath"
    }
    $socialCardRelativePath = "img/branding/project-social-card$extension"
    $socialCardDestination = Join-Path $websiteRoot ("static\" + $socialCardRelativePath.Replace("/", "\"))
    $socialCardParent = Split-Path -Path $socialCardDestination -Parent
    if (-not [string]::IsNullOrWhiteSpace($socialCardParent)) {
      New-Item -ItemType Directory -Force -Path $socialCardParent | Out-Null
    }
    Copy-Item -LiteralPath $SocialCardPath -Destination $socialCardDestination -Force
  }
  elseif (-not [string]::IsNullOrWhiteSpace($LogoPath)) {
    $socialCardRelativePath = $logoRelativePath
  }

  $configText = Get-Content -LiteralPath $configPath -Raw
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $configText -Pattern "(?m)^(\s*title:\s*)'[^']*'," -Value $docsTitle -PropertyDisplayName "config title"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*favicon:\s*)'[^']*'," -Value $faviconRelativePath -PropertyDisplayName "config favicon"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*image:\s*)'[^']*'," -Value $socialCardRelativePath -PropertyDisplayName "themeConfig.image"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?ms)(navbar:\s*\{.*?^\s*title:\s*)'[^']*'," -Value $projectName -PropertyDisplayName "navbar title"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?ms)(logo:\s*\{.*?^\s*alt:\s*)'[^']*'," -Value $logoAlt -PropertyDisplayName "navbar logo alt"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?ms)(logo:\s*\{.*?^\s*src:\s*)'[^']*'," -Value $logoRelativePath -PropertyDisplayName "navbar logo src"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteProjectName:\s*)'[^']*'," -Value $projectName -PropertyDisplayName "customFields.suiteProjectName"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteDocsTitle:\s*)'[^']*'," -Value $docsTitle -PropertyDisplayName "customFields.suiteDocsTitle"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteTagline:\s*)'[^']*'," -Value $tagline -PropertyDisplayName "customFields.suiteTagline"
  $updatedConfig = Set-DocsThemeSingleQuotedProperty -Text $updatedConfig -Pattern "(?m)^(\s*suiteThemeId:\s*)'[^']*'," -Value $themeEntry.id -PropertyDisplayName "customFields.suiteThemeId"
  Write-DocsThemeUtf8NoBomFile -Path $configPath -Content $updatedConfig

  $overridesState = Read-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot
  $overridesState.Document.theme.themeId = $themeEntry.id
  $overridesState.Document.theme.logoPath = if (-not [string]::IsNullOrWhiteSpace($LogoPath)) { $logoRelativePath } else { "" }
  $overridesState.Document.theme.faviconPath = if (-not [string]::IsNullOrWhiteSpace($FaviconPath)) { $faviconRelativePath } elseif (-not [string]::IsNullOrWhiteSpace($LogoPath)) { $faviconRelativePath } else { "" }
  $overridesState.Document.theme.socialCardPath = if (-not [string]::IsNullOrWhiteSpace($SocialCardPath)) { $socialCardRelativePath } elseif (-not [string]::IsNullOrWhiteSpace($LogoPath)) { $socialCardRelativePath } else { "" }
  Write-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot -Document $overridesState.Document

  $installMode = "managed_update"
  if ($AdoptExisting -and -not $isManaged) {
    $installMode = "merge_existing"
  }

  Write-DocsWebsiteOwnershipMarker `
    -ResolvedRepoRoot $ResolvedRepoRoot `
    -ThemeId $themeEntry.id `
    -InstallMode $installMode `
    -LogoPath $logoRelativePath `
    -FaviconPath $faviconRelativePath `
    -SocialCardPath $socialCardRelativePath `
    -Adopted:$AdoptExisting
  if ($AdoptExisting -and -not $isManaged) {
    Write-Output ("Adopted existing website for suite-managed theme updates.")
  }
  Write-Output ("Applied website theme '{0}'." -f $themeEntry.id)
}

function Invoke-DocsThemeCommand {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments
  )

  $argsList = @(Get-NormalizedArgumentList -Values $CommandArguments)
  if ($argsList.Count -eq 0) {
    Write-Output (Get-DocsToolsCommandHelp -CommandName "theme")
    return
  }

  $subcommand = [string]$argsList[0]
  if (Test-DocsToolsHelpToken -Token $subcommand) {
    Write-Output (Get-DocsToolsCommandHelp -CommandName "theme")
    return
  }

  $normalizedSubcommand = $subcommand.Trim().ToLowerInvariant()
  switch ($normalizedSubcommand) {
    "list" {
      Invoke-DocsThemeList -ResolvedRepoRoot $ResolvedRepoRoot
      return
    }
    "apply" {
      $themeId = $null
      $logoPath = $null
      $faviconPath = $null
      $socialCardPath = $null
      $adoptExisting = $false
      $tokens = if ($argsList.Count -gt 1) { @(Get-NormalizedArgumentTail -Values $argsList -Skip 1) } else { @() }
      for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = [string]$tokens[$i]
        $normalizedToken = $token.Trim().ToLowerInvariant()

        if ($normalizedToken -eq "-theme" -or $normalizedToken -eq "--theme") {
          if (($i + 1) -ge $tokens.Count) { throw "Missing value for $token." }
          if (-not [string]::IsNullOrWhiteSpace($themeId)) { throw "Theme is already set to '$themeId'. Provide only one theme id." }
          $themeId = [string]$tokens[$i + 1]
          $i++
          continue
        }

        if ($normalizedToken -eq "-logopath" -or $normalizedToken -eq "--logo-path") {
          if (($i + 1) -ge $tokens.Count) { throw "Missing value for $token." }
          $logoPath = [string]$tokens[$i + 1]
          $i++
          continue
        }

        if ($normalizedToken -eq "-faviconpath" -or $normalizedToken -eq "--favicon-path") {
          if (($i + 1) -ge $tokens.Count) { throw "Missing value for $token." }
          $faviconPath = [string]$tokens[$i + 1]
          $i++
          continue
        }

        if ($normalizedToken -eq "-socialcardpath" -or $normalizedToken -eq "--social-card-path") {
          if (($i + 1) -ge $tokens.Count) { throw "Missing value for $token." }
          $socialCardPath = [string]$tokens[$i + 1]
          $i++
          continue
        }

        if ($normalizedToken -eq "--adopt-existing" -or $normalizedToken -eq "-adoptexisting" -or $normalizedToken -eq "-adoptexistingwebsite") {
          $adoptExisting = $true
          continue
        }

        if ($normalizedToken.StartsWith("-")) {
          throw "Unknown theme apply option '$token'. Run 'ue-tools docs help theme'."
        }

        if (-not [string]::IsNullOrWhiteSpace($themeId)) {
          throw "Theme is already set to '$themeId'. Unexpected extra argument '$token'."
        }

        $themeId = $token
      }

      Invoke-DocsThemeApply -ResolvedRepoRoot $ResolvedRepoRoot -ThemeId $themeId -LogoPath $logoPath -FaviconPath $faviconPath -SocialCardPath $socialCardPath -AdoptExisting:$adoptExisting
      return
    }
    default {
      throw "Unknown ue-tools docs theme command '$subcommand'. Run 'ue-tools docs help theme'."
    }
  }
}

function Read-DocsWebsiteOwnershipMarker {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $path = Get-DocsWebsiteOwnershipMarkerPath -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return $null
  }

  try {
    return ((Get-Content -LiteralPath $path -Raw) | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

function Invoke-DocsSiteStatus {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $ownership = Read-DocsWebsiteOwnershipMarker -ResolvedRepoRoot $ResolvedRepoRoot
  $overrides = Read-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot
  $themeId = [string]$overrides.Document.theme.themeId
  if ([string]::IsNullOrWhiteSpace($themeId) -and $ownership -and $ownership.theme.themeId) {
    $themeId = [string]$ownership.theme.themeId
  }

  return [pscustomobject]@{
    Managed        = [bool]($null -ne $ownership)
    OwnershipPath  = Get-DocsWebsiteOwnershipMarkerPath -ResolvedRepoRoot $ResolvedRepoRoot
    OverridesPath  = $overrides.Path
    InstallMode    = if ($ownership) { [string]$ownership.installMode } else { "unmanaged" }
    ThemeId        = $themeId
    LogoPath       = [string]$overrides.Document.theme.logoPath
    FaviconPath    = [string]$overrides.Document.theme.faviconPath
    SocialCardPath = [string]$overrides.Document.theme.socialCardPath
    OverrideCount  = @($overrides.Document.fileOverrides).Count
    OverridePaths  = @($overrides.Document.fileOverrides | ForEach-Object { [string]$_.path })
  }
}

function Invoke-DocsSiteOverrideList {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $overrides = Read-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot
  return @($overrides.Document.fileOverrides)
}

function Invoke-DocsSiteOverrideSet {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$RelativePath,
    [Parameter(Mandatory)][string]$Mode
  )

  $normalizedPath = $RelativePath.Replace("\", "/").Trim().TrimStart("/")
  $normalizedMode = $Mode.Trim().ToLowerInvariant()
  if ($normalizedMode -notin @("suite", "project")) {
    throw "Mode must be 'suite' or 'project'."
  }

  $overrides = Read-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot
  $remaining = New-Object System.Collections.Generic.List[object]
  foreach ($entry in @($overrides.Document.fileOverrides)) {
    if ($null -eq $entry) { continue }
    if ([string]$entry.path -eq $normalizedPath) {
      continue
    }
    $remaining.Add($entry) | Out-Null
  }
  $remaining.Add([ordered]@{ path = $normalizedPath; mode = $normalizedMode }) | Out-Null
  $overrides.Document.fileOverrides = @($remaining.ToArray() | Sort-Object path)
  Write-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot -Document $overrides.Document

  return [pscustomobject]@{
    Path = $normalizedPath
    Mode = $normalizedMode
  }
}

function Invoke-DocsSiteOverrideClear {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$RelativePath
  )

  $normalizedPath = $RelativePath.Replace("\", "/").Trim().TrimStart("/")
  $overrides = Read-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot
  $remaining = New-Object System.Collections.Generic.List[object]
  foreach ($entry in @($overrides.Document.fileOverrides)) {
    if ($null -eq $entry) { continue }
    if ([string]$entry.path -eq $normalizedPath) {
      continue
    }
    $remaining.Add($entry) | Out-Null
  }
  $overrides.Document.fileOverrides = @($remaining.ToArray() | Sort-Object path)
  Write-DocsWebsiteOverrides -ResolvedRepoRoot $ResolvedRepoRoot -Document $overrides.Document

  return [pscustomobject]@{
    Path = $normalizedPath
  }
}

function Invoke-DocsSiteCommand {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments
  )

  $argsList = @(Get-NormalizedArgumentList -Values $CommandArguments)
  if ($argsList.Count -eq 0) {
    Write-Output (Get-DocsToolsCommandHelp -CommandName "site")
    return
  }

  $subcommand = [string]$argsList[0]
  if (Test-DocsToolsHelpToken -Token $subcommand) {
    Write-Output (Get-DocsToolsCommandHelp -CommandName "site")
    return
  }

  switch ($subcommand.Trim().ToLowerInvariant()) {
    "status" {
      $result = Invoke-DocsSiteStatus -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output ("Managed: {0}" -f $result.Managed)
      Write-Output ("Install mode: {0}" -f $result.InstallMode)
      Write-Output ("Theme: {0}" -f $result.ThemeId)
      Write-Output ("Logo path: {0}" -f $result.LogoPath)
      Write-Output ("Favicon path: {0}" -f $result.FaviconPath)
      Write-Output ("Social card path: {0}" -f $result.SocialCardPath)
      Write-Output ("Overrides path: {0}" -f $result.OverridesPath)
      Write-Output ("Override count: {0}" -f $result.OverrideCount)
      return
    }
    "override" {
      if ($argsList.Count -lt 2) {
        throw "Missing site override subcommand. Run 'ue-tools docs help site'."
      }
      $overrideCommand = [string]$argsList[1]
      $remaining = if ($argsList.Count -gt 2) { @(Get-NormalizedArgumentTail -Values $argsList -Skip 2) } else { @() }
      switch ($overrideCommand.Trim().ToLowerInvariant()) {
        "list" {
          foreach ($entry in @(Invoke-DocsSiteOverrideList -ResolvedRepoRoot $ResolvedRepoRoot)) {
            Write-Output ("- {0}: {1}" -f [string]$entry.path, [string]$entry.mode)
          }
          return
        }
        "set" {
          $parsed = Parse-SubcommandArguments -CommandArguments $remaining -ValueNames @("path", "mode")
          $result = Invoke-DocsSiteOverrideSet -ResolvedRepoRoot $ResolvedRepoRoot -RelativePath ([string]$parsed.Values["path"]) -Mode ([string]$parsed.Values["mode"])
          Write-Output ("Set override: {0} -> {1}" -f $result.Path, $result.Mode)
          return
        }
        "clear" {
          $parsed = Parse-SubcommandArguments -CommandArguments $remaining -ValueNames @("path")
          $result = Invoke-DocsSiteOverrideClear -ResolvedRepoRoot $ResolvedRepoRoot -RelativePath ([string]$parsed.Values["path"])
          Write-Output ("Cleared override: {0}" -f $result.Path)
          return
        }
        default {
          throw "Unknown ue-tools docs site override command '$overrideCommand'. Run 'ue-tools docs help site'."
        }
      }
    }
    default {
      throw "Unknown ue-tools docs site command '$subcommand'. Run 'ue-tools docs help site'."
    }
  }
}

function Get-DocsToolsRuntimeDirectory {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path (Get-BridgeRequestDirectory -ResolvedRepoRoot $ResolvedRepoRoot) "runtime")
}

function Get-DocsServerStatePath {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)
  return (Join-Path (Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot) "docs-server.json")
}

function Get-DocsEditorRuntimeConfigPath {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  return (Join-Path $websiteRoot "static\ue-tools\editor-runtime.json")
}

function Get-LegacyDocsEditorRuntimeConfigPath {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  return (Join-Path $websiteRoot "static\.ue-tools\editor-runtime.json")
}

function ConvertTo-CmdArgument {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "ConvertTo-UEToolSuiteDocsCmdArgument" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (ConvertTo-UEToolSuiteDocsCmdArgument -Value $Value)
  }

  if ($Value.Length -eq 0) {
    return '""'
  }

  if ($Value -notmatch '[\s"&|<>^]') {
    return $Value
  }

  return '"' + ($Value -replace '"', '""') + '"'
}

function Get-NormalizedArgumentList {
  param([AllowNull()][string[]]$Values)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsNormalizedArgumentList" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return @(Get-UEToolSuiteDocsNormalizedArgumentList -Values $Values)
  }

  $normalized = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    if ($null -eq $value) {
      continue
    }

    $stringValue = [string]$value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
      continue
    }

    $normalized.Add($stringValue) | Out-Null
  }

  return $normalized.ToArray()
}

function Get-NormalizedArgumentTail {
  param(
    [AllowNull()][string[]]$Values,
    [int]$Skip = 1
  )

  if ($null -eq $Values) {
    return @()
  }

  if ($Skip -lt 0) {
    $Skip = 0
  }

  $tail = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values | Select-Object -Skip $Skip)) {
    if ($null -eq $value) {
      continue
    }

    $stringValue = [string]$value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
      continue
    }

    $tail.Add($stringValue) | Out-Null
  }

  return @($tail.ToArray())
}

function Resolve-DocsToolsCommandAlias {
  param([Parameter(Mandatory)][string]$CommandName)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Resolve-UEToolSuiteDocsCommandAlias" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Resolve-UEToolSuiteDocsCommandAlias -CommandName $CommandName)
  }

  $normalized = $CommandName.Trim().ToLowerInvariant()
  switch ($normalized) {
    "create-page" { return "new-page" }
    "create-section" { return "new-section" }
    default { return $normalized }
  }
}

function Test-DocsToolsHelpToken {
  param([string]$Token)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteDocsHelpToken" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteDocsHelpToken -Token $Token)
  }

  if ([string]::IsNullOrWhiteSpace($Token)) {
    return $false
  }

  $normalized = $Token.Trim().ToLowerInvariant()
  return ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?"))
}

function Test-ProcessRunning {
  param([int]$ProcessId)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Test-UEToolSuiteDocsProcessRunning" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Test-UEToolSuiteDocsProcessRunning -ProcessId $ProcessId)
  }

  if ($ProcessId -le 0) {
    return $false
  }

  try {
    Get-Process -Id $ProcessId -ErrorAction Stop | Out-Null
    return $true
  }
  catch {
    return $false
  }
}

function Get-DescendantProcessId {
  param([int]$RootProcessId)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsDescendantProcessId" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsDescendantProcessId -RootProcessId $RootProcessId)
  }

  if ($RootProcessId -le 0) {
    return $null
  }

  $queue = New-Object System.Collections.Generic.Queue[int]
  $queue.Enqueue($RootProcessId)

  while ($queue.Count -gt 0) {
    $parentId = $queue.Dequeue()

    try {
      $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $parentId" -ErrorAction Stop)
    }
    catch {
      $children = @()
    }

    foreach ($child in $children) {
      $childId = [int]$child.ProcessId
      if (Test-ProcessRunning -ProcessId $childId) {
        return $childId
      }

      $queue.Enqueue($childId)
    }
  }

  return $null
}

function Get-DocsServerState {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $statePath = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsServerState" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsServerState -StatePath $statePath)
  }

  if (-not (Test-Path -LiteralPath $statePath)) { return $null }
  return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
}

function Remove-DocsServerState {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $statePath = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Remove-UEToolSuiteDocsServerState" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    Remove-UEToolSuiteDocsServerState -StatePath $statePath
    return
  }

  if (Test-Path -LiteralPath $statePath) {
    Remove-Item -LiteralPath $statePath -Force
  }
}

function Save-DocsServerState {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][object]$State
  )

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Save-UEToolSuiteDocsServerState" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Save-UEToolSuiteDocsServerState -StatePath (Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot) -State $State)
  }

  $runtimeDir = Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

  $statePath = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
  $json = $State | ConvertTo-Json -Depth 6
  Write-UEToolSuiteUtf8NoBomFile `
    -Path $statePath `
    -Content $json `
    -EnsureParentDirectory
  return $statePath
}

function Get-DocsServerEntries {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $state = Get-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not $state) {
    return @()
  }

  if ($state.PSObject.Properties["servers"]) {
    return @($state.servers)
  }

  return @($state)
}

function Save-DocsServerEntries {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries
  )

  $existingState = Get-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  $existingEditorEntry = $null
  if ($existingState -and $existingState.PSObject.Properties["editorApi"]) {
    $existingEditorEntry = $existingState.editorApi
  }

  $payload = [ordered]@{
    version = if ($null -ne $existingEditorEntry) { 3 } else { 2 }
    servers = @($Entries)
  }
  if ($null -ne $existingEditorEntry) {
    $payload.editorApi = $existingEditorEntry
  }

  if (@($Entries).Count -eq 0 -and $null -eq $existingEditorEntry) {
    Remove-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
    return $null
  }

  return (Save-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot -State $payload)
}

function Save-DocsServerCompositeState {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [AllowEmptyCollection()][object[]]$ServerEntries = @(),
    [AllowNull()]$EditorApiEntry = $null
  )

  $servers = @($ServerEntries)
  if ($servers.Count -eq 0 -and $null -eq $EditorApiEntry) {
    Remove-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
    return $null
  }

  $payload = [ordered]@{
    version = if ($null -ne $EditorApiEntry) { 3 } else { 2 }
    servers = $servers
  }
  if ($null -ne $EditorApiEntry) {
    $payload.editorApi = $EditorApiEntry
  }

  return (Save-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot -State $payload)
}

function Get-DocsEditorApiEntry {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $state = Get-DocsServerState -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not $state) {
    return $null
  }

  if ($state.PSObject.Properties["editorApi"]) {
    return $state.editorApi
  }

  return $null
}

function Save-DocsEditorApiEntry {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [AllowNull()]$Entry = $null
  )

  $serverEntries = @(Get-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot)
  return (Save-DocsServerCompositeState -ResolvedRepoRoot $ResolvedRepoRoot -ServerEntries $serverEntries -EditorApiEntry $Entry)
}

function Write-DocsEditorRuntimeConfig {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$ApiUrl,
    [AllowNull()]$Metadata = $null
  )

  $configPath = Get-DocsEditorRuntimeConfigPath -ResolvedRepoRoot $ResolvedRepoRoot
  $parent = Split-Path -Path $configPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  $payload = [ordered]@{
    apiUrl      = $ApiUrl
    generatedAt = (Get-Date).ToString("o")
  }
  if ($null -ne $Metadata) {
    $metadataFields = @(
      @{ JsonKey = "applicationId"; PropertyNames = @("ApplicationId") },
      @{ JsonKey = "apiVersion"; PropertyNames = @("ApiVersion") },
      @{ JsonKey = "repoRoot"; PropertyNames = @("RepoRoot") },
      @{ JsonKey = "docsRoot"; PropertyNames = @("DocsRoot") },
      @{ JsonKey = "processId"; PropertyNames = @("ProcessId") },
      @{ JsonKey = "startedAt"; PropertyNames = @("StartedAt") },
      @{ JsonKey = "modulePath"; PropertyNames = @("ModulePath") },
      @{ JsonKey = "scriptPath"; PropertyNames = @("ScriptPath") }
    )
    foreach ($field in $metadataFields) {
      foreach ($propertyName in @($field.PropertyNames)) {
        $property = $Metadata.PSObject.Properties[$propertyName]
        if ($null -eq $property) {
          continue
        }

        $value = $property.Value
        if ($null -eq $value) {
          continue
        }

        if ($value -is [string] -and [string]::IsNullOrWhiteSpace([string]$value)) {
          continue
        }

        $payload[$field.JsonKey] = $value
        break
      }
    }
  }
  Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $configPath -Content ($payload | ConvertTo-Json -Depth 5)
  $legacyConfigPath = Get-LegacyDocsEditorRuntimeConfigPath -ResolvedRepoRoot $ResolvedRepoRoot
  if (Test-Path -LiteralPath $legacyConfigPath -PathType Leaf) {
    Remove-Item -LiteralPath $legacyConfigPath -Force
  }
  return $configPath
}

function Remove-DocsEditorRuntimeConfig {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $configPath = Get-DocsEditorRuntimeConfigPath -ResolvedRepoRoot $ResolvedRepoRoot
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Remove-Item -LiteralPath $configPath -Force
  }
  $legacyConfigPath = Get-LegacyDocsEditorRuntimeConfigPath -ResolvedRepoRoot $ResolvedRepoRoot
  if (Test-Path -LiteralPath $legacyConfigPath -PathType Leaf) {
    Remove-Item -LiteralPath $legacyConfigPath -Force
  }
}

function Test-DocsStartPromptAvailable {
  try {
    if (-not [Environment]::UserInteractive) { return $false }
    if (-not $Host.UI -or -not $Host.UI.RawUI) { return $false }
    if ([Console]::IsInputRedirected) { return $false }
    if ([Console]::IsOutputRedirected) { return $false }
    return $true
  }
  catch {
    return $false
  }
}

function Read-DocsStartContinueChoice {
  param([Parameter(Mandatory)][string]$Prompt)

  $forceChoice = [string]$env:UE_TOOLS_DOCS_START_CONTINUE
  if (-not [string]::IsNullOrWhiteSpace($forceChoice)) {
    $normalizedForceChoice = $forceChoice.Trim().ToLowerInvariant()
    if ($normalizedForceChoice -in @("1", "y", "yes", "true")) {
      return $true
    }
    if ($normalizedForceChoice -in @("0", "n", "no", "false")) {
      return $false
    }
  }

  return $true
}

function Get-DocsStartPort {
  param([string[]]$StartArgs = @())

  $url = Get-DocsStartUrl -StartArgs $StartArgs
  if ($url -match "localhost:(?<port>\d+)/") {
    return [int]$Matches.port
  }

  return 3000
}

function Test-DocsStartPortInUse {
  param([int]$Port)

  if ($Port -le 0) {
    return $false
  }

  try {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
    return ($listeners.Count -gt 0)
  }
  catch {
    return $false
  }
}

function Get-WebsitePackageScriptNames {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  if ($null -ne $script:WebsitePackageScriptNames) {
    return $script:WebsitePackageScriptNames
  }

  $packagePath = Join-Path (Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot) "package.json"
  if (-not (Test-Path -LiteralPath $packagePath)) {
    $script:WebsitePackageScriptNames = @()
    return $script:WebsitePackageScriptNames
  }

  $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  if (-not $packageJson.scripts) {
    $script:WebsitePackageScriptNames = @()
    return $script:WebsitePackageScriptNames
  }

  $script:WebsitePackageScriptNames = @($packageJson.scripts.PSObject.Properties.Name)
  return $script:WebsitePackageScriptNames
}

function Get-DocsToolsRootHelp {
  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsRootHelpText" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsRootHelpText)
  }

  @"
UE project docs automation.

Usage:
  ue-tools docs <command> [options]

Create:
  new-section, create-section   Create a docs section
  new-page, create-page         Create a page at Docs root or inside a section
  reorder                       Reorder a page or section and shift sibling positions

Run:
  start                         Start Docusaurus (and the editor API) in the current terminal
  stop                          Stop the tracked background Docusaurus server
  status                        Show tracked background server status
  check                         Validate docs and run the production build
  doctor                        Check local docs prerequisites

Pass-through:
  build, clear, deploy, serve, swizzle
  write-translations, write-heading-ids, typecheck
  docusaurus <args...>

Other:
  install-bridge                Install the optional VS Code TOC bridge
  theme <list|apply>            List/apply docs website theme presets
  help [command]

Examples:
  ue-tools docs help new-section
  ue-tools docs create-section DocsSite -LinkType generated-index -GeneratedIndexSlug /docs-site
  ue-tools docs create-page Setup -Title "Setup"
  ue-tools docs create-page Workflow Daily-Flow -Title "Daily Flow" -SidebarLabel "Daily Flow"
  ue-tools docs reorder Art-Source 4
  ue-tools docs migrate-sections --what-if
  ue-tools docs start --port 3001
  ue-tools docs start --background --port 3001
  ue-tools docs docusaurus docs:version 1.0.0 --skip-feedback
  ue-tools docs theme list
  ue-tools docs theme apply neutral

Notes:
  - Docs are authored in Docs/ and rendered by website/.
  - Inline page editing is available directly on docs pages when the local editor API is running.
  - TOC generation is optional and only runs when the bridge + Markdown All in One are installed.
  - Use 'ue-tools docs help <command>' for detailed option help.
"@
}

function Get-DocsToolsCommandHelp {
  param([Parameter(Mandatory)][string]$CommandName)

  [void](Import-UEToolSuiteCoreModule)
  $topicResolver = Get-Command -Name "Resolve-UEToolSuiteDocsHelpTopicAlias" -ErrorAction SilentlyContinue
  if ($topicResolver) {
    $normalized = Resolve-UEToolSuiteDocsHelpTopicAlias -CommandName $CommandName
  }
  else {
    $normalized = $CommandName.Trim().ToLowerInvariant()
    switch ($normalized) {
      "new-page" { break }
      "create-page" { $normalized = "new-page"; break }
      "new-section" { break }
      "create-section" { $normalized = "new-section"; break }
      default { }
    }
  }

  switch ($normalized) {
    "new-page" {
      @"
ue-tools docs new-page
Alias: ue-tools docs create-page

Usage:
  ue-tools docs new-page <PageName> [options]
  ue-tools docs new-page <SectionPath> <PageName> [options]

Required:
  <PageName>                    File stem source, for example Setup or Fear-Loop
  <SectionPath>                 Optional existing Docs/ section path, for example Workflow

Scaffold:
  -Title <text>                 Front matter title
  -Slug <path>                  Doc slug, for example /workflow/daily-flow
  -Position <number>            sidebar_position
  -Force                        Overwrite an existing file
  -NoToc                        Skip optional VS Code TOC generation

Common doc front matter:
  -Description <text>           description
  -Image <path>                 image
  -Keywords <a,b,c>             keywords string list
  -Tags <a,b,c>                 tags string list
  -TagsJson <json>              tags as full JSON
  -SidebarLabel <text>          sidebar_label
  -SidebarClassName <text>      sidebar_class_name
  -SidebarKey <text>            sidebar_key
  -SidebarCustomPropsJson <json> sidebar_custom_props
  -DisplayedSidebar <id>        displayed_sidebar
  -PaginationLabel <text>       pagination_label
  -PaginationNext <id|null>     pagination_next
  -PaginationPrev <id|null>     pagination_previous
  -HideTitle <true|false>       hide_title
  -HideTableOfContents <true|false> hide_table_of_contents
  -TocMinHeadingLevel <int>     toc_min_heading_level
  -TocMaxHeadingLevel <int>     toc_max_heading_level
  -CustomEditUrl <url|null>     custom_edit_url
  -Draft <true|false>           draft
  -Unlisted <true|false>        unlisted
  -ParseNumberPrefixes <true|false> parse_number_prefixes
  -LastUpdateDate <YYYY-MM-DD>  last_update.date
  -LastUpdateAuthor <text>      last_update.author

Generic front matter passthrough:
  -Field <key=value>            Set any front matter key as a string
  -FieldJson <key=json>         Set any front matter key with JSON values
                                Arrays/objects/bools/numbers should use -FieldJson

Examples:
  ue-tools docs create-page Setup -Title "Setup"
  ue-tools docs create-page Workflow Daily-Flow -Title "Daily Flow" -Position 2
  ue-tools docs create-page DocsSite Cli-Guide -Slug /docs-site/cli-guide -Keywords docs,cli,docusaurus
  ue-tools docs create-page Workflow Release-Checklist -FieldJson last_update={\"date\":\"2026-04-08\",\"author\":\"Team\"}
"@
      return
    }
    "new-section" {
      @"
ue-tools docs new-section
Alias: ue-tools docs create-section

Usage:
  ue-tools docs new-section <SectionPath> [options]

Required:
  <SectionPath>                   New Docs/ section path, for example DocsSite

Section README front matter:
  -Title <text>                   README title
  -Slug <path>                    README slug, for example /docs-site
  -DocSidebarPosition <number>    README sidebar_position, default: 1
  -Description <text>             README description
  -Image <path>                   README image
  -Keywords <a,b,c>               README keywords
  -Tags <a,b,c>                   README tags
  -TagsJson <json>                README tags as full JSON
  -SidebarLabel <text>            README sidebar_label
  -SidebarClassName <text>        README sidebar_class_name
  -SidebarKey <text>              README sidebar_key
  -SidebarCustomPropsJson <json>  README sidebar_custom_props
  -DisplayedSidebar <id>          README displayed_sidebar
  -PaginationLabel <text>         README pagination_label
  -PaginationNext <id|null>       README pagination_next
  -PaginationPrev <id|null>       README pagination_previous
  -HideTitle <true|false>         README hide_title
  -HideTableOfContents <true|false> README hide_table_of_contents
  -TocMinHeadingLevel <int>       README toc_min_heading_level
  -TocMaxHeadingLevel <int>       README toc_max_heading_level
  -CustomEditUrl <url|null>       README custom_edit_url
  -Draft <true|false>             README draft
  -Unlisted <true|false>          README unlisted
  -ParseNumberPrefixes <true|false> README parse_number_prefixes
  -LastUpdateDate <YYYY-MM-DD>    README last_update.date
  -LastUpdateAuthor <text>        README last_update.author
  -DocField <key=value>           Any additional README front matter key
  -DocFieldJson <key=json>        Any additional README front matter JSON value

Category metadata (_category_.json):
  -Label <text>                   label, default: title
  -Position <number>              position
  -Collapsible <true|false>       collapsible
  -Collapsed <true|false>         collapsed
  -ClassName <text>               className
  -Key <text>                     key
  -CustomPropsJson <json>         customProps

Category link types:
  -LinkType <doc|generated-index|none>
                                  doc: link to an existing doc ID
                                  generated-index: auto-generate an index page
                                  none: write `"link": null`
  -LinkId <docId>                 link.id when LinkType=doc
  -GeneratedIndexTitle <text>     link.title when LinkType=generated-index
  -GeneratedIndexSlug <path>      link.slug when LinkType=generated-index
  -GeneratedIndexDescription <text> link.description
  -GeneratedIndexImage <path>     link.image
  -GeneratedIndexKeywords <a,b,c> link.keywords
  -CategoryField <key=value>      Any additional _category_.json key
  -CategoryJson <key=json>        Any additional _category_.json JSON value
                                  Use link={...} for full manual link control when needed

Scaffold:
  -Force                          Overwrite an existing directory
  -NoToc                          Skip optional VS Code TOC generation

Examples:
  ue-tools docs create-section DocsSite -Title "Docs Site" -Position 8
  ue-tools docs create-section DocsSite -LinkType generated-index -GeneratedIndexTitle "Docs Site" -GeneratedIndexSlug /docs-site
  ue-tools docs create-section Guides/API -LinkType none -CategoryJson customProps={\"badge\":\"internal\"}
"@
      return
    }
    "start" {
      @"
ue-tools docs start

Usage:
  ue-tools docs start [--background] [docusaurus start args]

Default behavior runs `npm run start -- <args...>` in website/ attached to the current terminal so stdout/stderr stream live.
The local editor API is started automatically so inline docs-page editing works while the docs runtime is active.

Options:
  --background                  Run detached and track docs + editor API for `status` and `stop`

Examples:
  ue-tools docs start
  ue-tools docs start --port 3001
  ue-tools docs start --background --port 3001
"@
      return
    }
    "reorder" {
      @"
ue-tools docs reorder

Usage:
  ue-tools docs reorder <TargetPath> <Position>

Required:
  <TargetPath>                  Docs-relative page or section path
                                Pages: Setup, Workflow/Daily-Flow
                                Sections: Workflow, DocsSite
                                `Docs\` prefixes and `.md` suffixes are accepted
  <Position>                    Target sidebar position number

Behavior:
  - Moves the target item to the requested position within its parent
  - Shifts sibling pages/sections in the same parent container to keep ordering stable
  - Updates `sidebar_position` for pages and `_category_.json` `position` for sections

Examples:
  ue-tools docs reorder Art-Source 4
  ue-tools docs reorder Workflow 3
  ue-tools docs reorder Workflow/Daily-Flow 2
"@
      return
    }
    "migrate-sections" {
      @"
ue-tools docs migrate-sections

Usage:
  ue-tools docs migrate-sections [--what-if]

Behavior:
  - Finds legacy docs directories that the editor/navigation model exposes as sections but that lack `_category_.json`
  - Plans deterministic `_category_.json` files with a stable `label` and preserved `position`
  - Writes only `_category_.json`
  - Preserves current visible navigation order
  - Never overwrites an existing `_category_.json`

Options:
  --what-if, -WhatIf            Plan the migration and report what would change without writing files

Examples:
  ue-tools docs migrate-sections
  ue-tools docs migrate-sections --what-if
"@
      return
    }
    "visibility" {
      @"
ue-tools docs visibility

Usage:
  ue-tools docs visibility <TargetPath> <show|hide>

Required:
  <TargetPath>                  Docs-relative page path or section/domain path with a landing doc
                                Examples: Setup, Workflow/Daily-Flow, Workflow, ProjectDocs
  <show|hide>                   show clears unlisted; hide sets unlisted: true

Behavior:
  - Keeps the file on disk
  - Uses Docusaurus-native unlisted front matter
  - Hidden pages stay directly routable but drop out of normal site navigation

Examples:
  ue-tools docs visibility Workflow/Daily-Flow hide
  ue-tools docs visibility Workflow show
"@
      return
    }
    "docusaurus" {
      @"
ue-tools docs docusaurus

Usage:
  ue-tools docs docusaurus <args...>

Passes all args and flags through to `npm run docusaurus -- <args...>`.
Example:
  ue-tools docs docusaurus docs:version 1.0.0 --skip-feedback
"@
      return
    }
    "check" {
      @"
ue-tools docs check

Validates docs metadata, catches common docs-site mistakes, and runs the Docusaurus production build.
"@
      return
    }
    "status" {
      @"
ue-tools docs status

Shows tracked docs runtime status:
  - Docusaurus server process state
  - Editor API process state
  - Docs URLs and log paths when available
"@
      return
    }
    "stop" {
      @"
ue-tools docs stop

Stops the tracked background docs runtime:
  - Docusaurus server process tree
  - Editor API process tree
and removes saved runtime state.
"@
      return
    }
    "doctor" {
      @"
ue-tools docs doctor

Checks common local docs prerequisites:
  - node / npm availability
  - website/node_modules presence
  - VS Code CLI availability
  - Markdown All in One installation
  - docs bridge installation
  - tracked docs dev server state
  - tracked editor API state
"@
      return
    }
    "install-bridge" {
      @"
ue-tools docs install-bridge

Installs the optional UE project VS Code bridge used for TOC generation. Markdown All in One still needs to be installed separately.
"@
      return
    }
    "theme" {
      @"
ue-tools docs theme

Usage:
  ue-tools docs theme list
  ue-tools docs theme apply <id> [-LogoPath <path>] [-FaviconPath <path>] [-SocialCardPath <path>] [--adopt-existing]

Commands:
  list                           Show available website theme presets from website/theme-presets/theme-catalog.json
  apply                          Apply a theme preset to website/theme-presets/active-theme.css and update branding fields in website/docusaurus.config.ts

Notes:
  - Theme apply is preserve-first: unmanaged websites are not overridden by default.
  - Use --adopt-existing to write the marker for an existing unmanaged website before applying.
  - LogoPath accepts .svg or .png files.
  - FaviconPath accepts .svg, .png, or .ico files.
  - SocialCardPath accepts .svg, .png, .jpg, .jpeg, or .webp files.
"@
      return
    }
    "site" {
      @"
ue-tools docs site

Usage:
  ue-tools docs site status
  ue-tools docs site override list
  ue-tools docs site override set -Path <relative> -Mode <suite|project>
  ue-tools docs site override clear -Path <relative>

Commands:
  status                         Show current website ownership, install mode, branding, and override summary
  override list                  Show persisted file override entries
  override set                   Persist a file override mode for a managed docs/site file
  override clear                 Remove a persisted file override entry
"@
      return
    }
    default {
      throw "Unknown ue-tools docs help topic '$CommandName'."
    }
  }
}

function ConvertTo-KebabCase {
  param([Parameter(Mandatory)][string]$Text)

  $value = $Text.Trim()
  $value = $value -creplace '([a-z0-9])([A-Z])', '$1-$2'
  $value = $value -replace '[^A-Za-z0-9]+', '-'
  $value = $value.Trim('-')

  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Could not convert '$Text' into a slug segment."
  }

  return $value.ToLowerInvariant()
}

function ConvertTo-TitleWords {
  param([Parameter(Mandatory)][string]$Text)

  $expanded = $Text.Trim()
  $expanded = $expanded -creplace '([a-z0-9])([A-Z])', '$1 $2'
  $expanded = $expanded -replace '[_\-]+', ' '
  $expanded = $expanded -replace '\s+', ' '
  $expanded = $expanded.Trim()

  if ([string]::IsNullOrWhiteSpace($expanded)) {
    throw "Could not convert '$Text' into a title."
  }

  $textInfo = [System.Globalization.CultureInfo]::InvariantCulture.TextInfo
  return $textInfo.ToTitleCase($expanded.ToLowerInvariant())
}

function ConvertTo-FileStem {
  param([Parameter(Mandatory)][string]$Text)

  $expanded = $Text.Trim()
  $expanded = $expanded -replace '\.md$', ''
  $expanded = $expanded -creplace '([a-z0-9])([A-Z])', '$1 $2'
  $expanded = $expanded -replace '[^A-Za-z0-9]+', ' '
  $expanded = $expanded -replace '\s+', ' '
  $expanded = $expanded.Trim()

  if ([string]::IsNullOrWhiteSpace($expanded)) {
    throw "Could not convert '$Text' into a file name."
  }

  $parts = @($expanded.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries))
  return ($parts | ForEach-Object {
      if ($_.Length -eq 1) { $_.ToUpperInvariant() }
      else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
    }) -join '-'
}

function Get-RelativeDocPath {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$FullPath
  )

  $relative = Get-UEToolSuiteRelativePath -BasePath $DocsRoot -TargetPath $FullPath
  return ($relative -replace '\\', '/')
}

function Get-UEToolSuiteRelativePath {
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

function Get-DocIdForPath {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$FullPath
  )

  $relative = Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $FullPath
  return ($relative -replace '\.md$', '')
}

function Get-SlugForSectionPath {
  param([Parameter(Mandatory)][string]$SectionPath)

  $segments = @($SectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($segments.Count -eq 0) {
    throw "Section path must not be empty."
  }

  $slugSegments = @($segments | ForEach-Object { ConvertTo-KebabCase $_ })
  return "/" + ($slugSegments -join '/')
}

function Get-SlugForPage {
  param(
    [AllowEmptyString()][string]$SectionPath,
    [Parameter(Mandatory)][string]$PageName
  )

  $pageSlug = ConvertTo-KebabCase $PageName
  if ([string]::IsNullOrWhiteSpace($SectionPath)) {
    return "/$pageSlug"
  }

  $sectionSlug = Get-SlugForSectionPath -SectionPath $SectionPath
  return "$sectionSlug/$pageSlug"
}

function Parse-SubcommandArguments {
  param(
    [AllowNull()][string[]]$CommandArguments = @(),
    [string[]]$SwitchNames = @(),
    [string[]]$ValueNames = @(),
    [string[]]$MultiValueNames = @()
  )

  $argumentList = @(Get-NormalizedArgumentList -Values $CommandArguments)
  $positionals = New-Object System.Collections.Generic.List[string]
  $values = @{}
  $multiValues = @{}
  $switches = @{}
  $switchSet = @($SwitchNames | ForEach-Object { $_.ToLowerInvariant() })
  $valueSet = @($ValueNames | ForEach-Object { $_.ToLowerInvariant() })
  $multiValueSet = @($MultiValueNames | ForEach-Object { $_.ToLowerInvariant() })

  for ($i = 0; $i -lt $argumentList.Count; $i++) {
    $token = [string]$argumentList[$i]
    if ($token.StartsWith('-')) {
      $name = $token.TrimStart('-').ToLowerInvariant()

      if ($switchSet -contains $name) {
        $switches[$name] = $true
        continue
      }

      if ($valueSet -contains $name) {
        if (($i + 1) -ge $argumentList.Count) {
          throw "Missing value for option '$token'."
        }

        $values[$name] = [string]$argumentList[$i + 1]
        $i++
        continue
      }

      if ($multiValueSet -contains $name) {
        if (($i + 1) -ge $argumentList.Count) {
          throw "Missing value for option '$token'."
        }

        if (-not $multiValues.ContainsKey($name)) {
          $multiValues[$name] = New-Object System.Collections.Generic.List[string]
        }

        $multiValues[$name].Add([string]$argumentList[$i + 1]) | Out-Null
        $i++
        continue
      }

      throw "Unknown option '$token'."
    }

    $positionals.Add($token) | Out-Null
  }

  return [pscustomobject]@{
    Positionals = $positionals.ToArray()
    Values      = $values
    MultiValues = $multiValues
    Switches    = $switches
  }
}

function Parse-KeyValueAssignment {
  param([Parameter(Mandatory)][string]$Assignment)

  $separatorIndex = $Assignment.IndexOf('=')
  if ($separatorIndex -lt 1) {
    throw "Expected key=value assignment but got '$Assignment'."
  }

  $key = $Assignment.Substring(0, $separatorIndex).Trim()
  $value = $Assignment.Substring($separatorIndex + 1)
  if ([string]::IsNullOrWhiteSpace($key)) {
    throw "Assignment key must not be empty: '$Assignment'."
  }

  return [pscustomobject]@{
    Key   = $key
    Value = $value
  }
}

function ConvertTo-BooleanValue {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  $normalized = $Value.Trim().ToLowerInvariant()
  switch ($normalized) {
    "true" { return $true }
    "false" { return $false }
    default { throw "Option '$OptionName' expects true or false." }
  }
}

function ConvertTo-NullableStringValue {
  param([Parameter(Mandatory)][string]$Value)

  if ($Value.Trim().ToLowerInvariant() -eq "null") {
    return $null
  }

  return $Value
}

function ConvertTo-CompactNumericValue {
  param([Parameter(Mandatory)][double]$Value)

  if ([Math]::Abs($Value % 1) -lt 0.0000001) {
    return [int64][Math]::Round($Value)
  }

  return $Value
}

function ConvertTo-NumericValue {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  $parsed = 0.0
  if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    throw "Option '$OptionName' expects a number."
  }

  return (ConvertTo-CompactNumericValue -Value $parsed)
}

function ConvertTo-IntegerValue {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  $parsed = 0
  if (-not [int]::TryParse($Value, [ref]$parsed)) {
    throw "Option '$OptionName' expects an integer."
  }

  return $parsed
}

function ConvertTo-StringList {
  param([AllowNull()][string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return @()
  }

  return @(
    $Value.Split(',') |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
}

function ConvertFrom-JsonArgument {
  param(
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$OptionName
  )

  try {
    return (ConvertFrom-Json -InputObject $Value -Depth 20)
  }
  catch {
    throw "Option '$OptionName' expects valid JSON."
  }
}

function Set-OrderedMapValue {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
    [Parameter(Mandatory)][string]$Key,
    $Value
  )

  if ($Map.Contains($Key)) {
    $Map[$Key] = $Value
  }
  else {
    $Map.Add($Key, $Value)
  }
}

function Apply-KeyValueAssignmentsToMap {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$Map,
    [string[]]$Assignments = @(),
    [string[]]$JsonAssignments = @()
  )

  foreach ($assignment in @(Get-NormalizedArgumentList -Values $Assignments)) {
    $entry = Parse-KeyValueAssignment -Assignment $assignment
    Set-OrderedMapValue -Map $Map -Key $entry.Key -Value $entry.Value
  }

  foreach ($assignment in @(Get-NormalizedArgumentList -Values $JsonAssignments)) {
    $entry = Parse-KeyValueAssignment -Assignment $assignment
    $jsonValue = ConvertFrom-JsonArgument -Value $entry.Value -OptionName $entry.Key
    Set-OrderedMapValue -Map $Map -Key $entry.Key -Value $jsonValue
  }
}

function Test-IsYamlScalar {
  param($Value)

  return (
    $null -eq $Value -or
    $Value -is [string] -or
    $Value -is [bool] -or
    $Value -is [byte] -or
    $Value -is [int16] -or
    $Value -is [int32] -or
    $Value -is [int64] -or
    $Value -is [single] -or
    $Value -is [double] -or
    $Value -is [decimal]
  )
}

function Format-YamlNumber {
  param([Parameter(Mandatory)]$Value)

  if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
    if ([Math]::Abs([double]$Value % 1) -lt 0.0000001) {
      return ([int64][Math]::Round([double]$Value)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
  }

  return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $Value))
}

function Format-YamlScalar {
  param($Value)

  if ($null -eq $Value) {
    return "null"
  }

  if ($Value -is [bool]) {
    return $Value.ToString().ToLowerInvariant()
  }

  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
    return (Format-YamlNumber -Value $Value)
  }

  $text = [string]$Value
  if ($text.Length -eq 0) {
    return "''"
  }

  $safePattern = '^[A-Za-z0-9_./:+@%-]+$'
  $reservedPattern = '^(true|false|null|yes|no|on|off|[-+]?\d+(\.\d+)?)$'
  if ($text -match $safePattern -and $text -notmatch $reservedPattern) {
    return $text
  }

  return "'" + ($text -replace "'", "''") + "'"
}

function Get-ObjectEntries {
  param($Value)

  if ($Value -is [System.Collections.IDictionary]) {
    return @($Value.GetEnumerator())
  }

  return @($Value.PSObject.Properties | ForEach-Object {
      [pscustomobject]@{
        Key   = $_.Name
        Value = $_.Value
      }
    })
}

function ConvertTo-YamlLines {
  param(
    $Value,
    [int]$Indent = 0
  )

  $indentText = (' ' * $Indent)

  if (Test-IsYamlScalar -Value $Value) {
    return @("$indentText$(Format-YamlScalar -Value $Value)")
  }

  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary]) -and -not ($Value.PSObject.Properties.Count -gt 0 -and -not ($Value -is [array]))) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Value)) {
      if (Test-IsYamlScalar -Value $item) {
        $lines.Add("$indentText- $(Format-YamlScalar -Value $item)") | Out-Null
      }
      else {
        $lines.Add("$indentText-") | Out-Null
        foreach ($nested in @(ConvertTo-YamlLines -Value $item -Indent ($Indent + 2))) {
          $lines.Add($nested) | Out-Null
        }
      }
    }
    return @($lines)
  }

  $objectLines = New-Object System.Collections.Generic.List[string]
  foreach ($entry in @(Get-ObjectEntries -Value $Value)) {
    $key = [string]$entry.Key
    $entryValue = $entry.Value
    if (Test-IsYamlScalar -Value $entryValue) {
      $objectLines.Add("${indentText}${key}: $(Format-YamlScalar -Value $entryValue)") | Out-Null
    }
    else {
      $objectLines.Add("${indentText}${key}:") | Out-Null
      foreach ($nested in @(ConvertTo-YamlLines -Value $entryValue -Indent ($Indent + 2))) {
        $objectLines.Add($nested) | Out-Null
      }
    }
  }

  return @($objectLines)
}

function ConvertTo-FrontMatterBlock {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$FrontMatter)

  $lines = @("---") + @(ConvertTo-YamlLines -Value $FrontMatter) + @("---")
  return ($lines -join "`r`n")
}

function Get-CodeCliPath {
  if ($script:CodeCliPath) {
    return $script:CodeCliPath
  }

  $command = Get-Command code.cmd -ErrorAction SilentlyContinue
  if ($command) {
    $script:CodeCliPath = $command.Source
    return $script:CodeCliPath
  }

  $defaultPath = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
  if (Test-Path -LiteralPath $defaultPath) {
    $script:CodeCliPath = $defaultPath
    return $script:CodeCliPath
  }

  return $null
}

function Get-InstalledVSCodeExtensions {
  $codeCliPath = Get-CodeCliPath
  if (-not $codeCliPath) {
    return @()
  }

  if ($null -ne $script:CodeExtensionList) {
    return $script:CodeExtensionList
  }

  $lines = @(& $codeCliPath --list-extensions 2>$null)
  $script:CodeExtensionList = @($lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  return $script:CodeExtensionList
}

function Test-VSCodeExtensionInstalled {
  param([Parameter(Mandatory)][string]$ExtensionId)
  return (Get-InstalledVSCodeExtensions) -contains $ExtensionId
}

function Get-BridgeStatus {
  [void](Import-UEToolSuiteCoreModule)
  $codeCliPath = Get-CodeCliPath
  $markdownInstalled = $false
  $bridgeInstalled = $false

  if ($codeCliPath) {
    $markdownInstalled = Test-VSCodeExtensionInstalled -ExtensionId $script:MarkdownAllInOneExtensionId
    $bridgeInstalled = Test-VSCodeExtensionInstalled -ExtensionId $script:DocsToolsBridgeExtensionId
  }

  $moduleFn = Get-Command -Name "New-UEToolSuiteDocsBridgeStatus" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (New-UEToolSuiteDocsBridgeStatus -CodeCliPath $codeCliPath -MarkdownAllInOneInstalled:$markdownInstalled -BridgeInstalled:$bridgeInstalled)
  }

  return [pscustomobject]@{ CodeCliPath = $codeCliPath; MarkdownAllInOneInstalled = $markdownInstalled; BridgeInstalled = $bridgeInstalled; TocReady = ($codeCliPath -and $markdownInstalled -and $bridgeInstalled) }
}

function Get-WorkspaceRequestKey {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsWorkspaceRequestKey" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsWorkspaceRequestKey -ResolvedRepoRoot $ResolvedRepoRoot)
  }

  $normalized = [System.IO.Path]::GetFullPath($ResolvedRepoRoot).ToLowerInvariant()
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = $sha1.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
  }
  finally {
    $sha1.Dispose()
  }
}

function Get-BridgeRequestDirectory {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsBridgeRequestDirectory" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsBridgeRequestDirectory -ResolvedRepoRoot $ResolvedRepoRoot)
  }

  $workspaceKey = Get-WorkspaceRequestKey -ResolvedRepoRoot $ResolvedRepoRoot
  return (Join-Path ([System.IO.Path]::GetTempPath()) "ueproject-ue-tools-docs\$workspaceKey")
}

function Queue-TocRequest {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$FilePath
  )

  $requestDir = Get-BridgeRequestDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $requestDir | Out-Null

  $requestObject = [ordered]@{
    version       = 1
    action        = "createToc"
    workspaceRoot = [System.IO.Path]::GetFullPath($ResolvedRepoRoot)
    filePath      = [System.IO.Path]::GetFullPath($FilePath)
    marker        = $script:TocMarker
    createdAt     = (Get-Date).ToString("o")
  }

  $requestId = "{0}-{1}" -f (Get-Date).ToString("yyyyMMddHHmmss"), ([Guid]::NewGuid().ToString("N"))
  $json = $requestObject | ConvertTo-Json -Depth 5
  $tempPath = Join-Path $requestDir "$requestId.tmp"
  $finalPath = Join-Path $requestDir "$requestId.json"

  Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $tempPath -Content $json
  Move-Item -LiteralPath $tempPath -Destination $finalPath -Force

  return $finalPath
}

function Open-PathInVSCode {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$FilePath
  )

  $codeCliPath = Get-CodeCliPath
  if (-not $codeCliPath) {
    return $false
  }

  & $codeCliPath --reuse-window -g "${FilePath}:1" | Out-Null
  return $true
}

function Build-ScaffoldDocContent {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$FrontMatter,
    [Parameter(Mandatory)][string]$HeadingTitle,
    [Parameter(Mandatory)][bool]$IncludeToc,
    [Parameter(Mandatory)][string]$OverviewNoun
  )

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($line in @((ConvertTo-FrontMatterBlock -FrontMatter $FrontMatter) -split "`r?`n")) {
    $lines.Add($line) | Out-Null
  }

  $lines.Add("") | Out-Null
  $lines.Add("# $HeadingTitle <!-- omit from toc -->") | Out-Null
  $lines.Add("") | Out-Null

  if ($IncludeToc) {
    $lines.Add("## Table of Contents <!-- omit from toc -->") | Out-Null
    $lines.Add("") | Out-Null
    $lines.Add($script:TocMarker) | Out-Null
    $lines.Add("") | Out-Null
  }

  $lines.Add("## Overview") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("Describe this $OverviewNoun.") | Out-Null
  $lines.Add("") | Out-Null

  return ($lines -join "`r`n")
}

function Build-CategoryMetadataContent {
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Metadata)
  return (($Metadata | ConvertTo-Json -Depth 10) + "`r`n")
}

function Test-DocsNavigableMarkdownFile {
  param([Parameter(Mandatory)][System.IO.FileSystemInfo]$FileInfo)

  return (
    $FileInfo.Extension.Equals(".md", [System.StringComparison]::OrdinalIgnoreCase) -or
    $FileInfo.Extension.Equals(".mdx", [System.StringComparison]::OrdinalIgnoreCase)
  )
}

function Test-DocsExcludedDirectoryName {
  param([Parameter(Mandatory)][string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    return $false
  }

  if ($Name.StartsWith(".")) {
    return $true
  }

  $excludedNames = @(
    "node_modules",
    "build",
    "build-debug",
    ".docusaurus",
    ".ue-tools",
    ".ue-tools-installer-updates",
    "Results",
    "TestResults",
    "Snapshots",
    "Templates",
    "bin",
    "obj"
  )

  return ($excludedNames -contains $Name)
}

function Get-DocsDomainsConfigPathForRoot {
  param([Parameter(Mandatory)][string]$DocsRoot)

  return (Join-Path $DocsRoot "_domains.json")
}

function Read-DocsDomainsConfigForRoot {
  param([Parameter(Mandatory)][string]$DocsRoot)

  $configPath = Get-DocsDomainsConfigPathForRoot -DocsRoot $DocsRoot
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    return $null
  }

  try {
    return (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

function Get-DocsConfiguredDomainRootSet {
  param([Parameter(Mandatory)][string]$DocsRoot)

  $roots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  $config = Read-DocsDomainsConfigForRoot -DocsRoot $DocsRoot
  if ($null -eq $config -or $null -eq $config.domains) {
    return , $roots
  }

  foreach ($entry in @($config.domains)) {
    if ($null -eq $entry) { continue }

    foreach ($candidate in @([string]$entry.dirName, [string]$entry.path)) {
      $normalizedCandidate = $candidate.Trim().Replace('\', '/').Trim('/')
      if ([string]::IsNullOrWhiteSpace($normalizedCandidate)) {
        continue
      }

      if ($normalizedCandidate -notmatch '/') {
        [void]$roots.Add($normalizedCandidate)
      }
    }

    foreach ($ownedRoot in @($entry.ownedRoots)) {
      $normalizedOwnedRoot = ([string]$ownedRoot).Trim().Replace('\', '/').Trim('/')
      if ([string]::IsNullOrWhiteSpace($normalizedOwnedRoot)) {
        continue
      }

      if ($normalizedOwnedRoot -notmatch '/') {
        [void]$roots.Add($normalizedOwnedRoot)
      }
    }
  }

  return , $roots
}

function Get-DocsSectionDisplayLabel {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
    try {
      $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
      $label = ([string]$categoryJson.label).Trim()
      if (-not [string]::IsNullOrWhiteSpace($label)) {
        return $label
      }
    }
    catch {
    }
  }

  foreach ($candidateName in @("README.md", "README.mdx", "index.md", "index.mdx")) {
    $candidatePath = Join-Path $DirectoryPath $candidateName
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
      continue
    }

    try {
      $content = Get-Content -LiteralPath $candidatePath -Raw
      $frontMatter = Get-FrontMatterBlock -Content $content
      $title = Get-FrontMatterValue -FrontMatter $frontMatter -Key "title"
      if (-not [string]::IsNullOrWhiteSpace($title)) {
        return [string]$title
      }

      $headingMatch = [regex]::Match($content, '(?m)^\#\s+(?<title>.+?)\s*$')
      if ($headingMatch.Success) {
        return $headingMatch.Groups['title'].Value.Trim()
      }
    }
    catch {
    }
  }

  return [System.IO.Path]::GetFileName($DirectoryPath)
}

function Get-DocsLegacySectionFinding {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$ConfiguredDomainRoots
  )

  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $DirectoryPath
  $fullDirectoryPath = [System.IO.Path]::GetFullPath($DirectoryPath)
  $relativePath = (Get-UEToolSuiteRelativePath -BasePath $DocsRoot -TargetPath $fullDirectoryPath) -replace '\\', '/'
  if ($relativePath -eq ".") {
    $relativePath = ""
  }

  $directoryName = [System.IO.Path]::GetFileName($fullDirectoryPath)
  $categoryPath = Join-Path $fullDirectoryPath "_category_.json"

  if (Test-DocsExcludedDirectoryName -Name $directoryName) {
    return [pscustomobject]@{
      Kind         = "excluded-directory"
      RelativePath = $relativePath
      FullPath     = $fullDirectoryPath
      Reason       = "Excluded/generated directory."
      Qualifies    = $false
    }
  }

  $ancestorPath = Split-Path -Parent $fullDirectoryPath
  while (
    -not [string]::IsNullOrWhiteSpace($ancestorPath) -and
    -not [System.IO.Path]::GetFullPath($ancestorPath).Equals([System.IO.Path]::GetFullPath($DocsRoot), [System.StringComparison]::OrdinalIgnoreCase)
  ) {
    if (Test-DocsExcludedDirectoryName -Name ([System.IO.Path]::GetFileName($ancestorPath))) {
      return [pscustomobject]@{
        Kind         = "excluded-directory"
        RelativePath = $relativePath
        FullPath     = $fullDirectoryPath
        Reason       = "Directory is inside an excluded/generated directory."
        Qualifies    = $false
      }
    }

    $nextAncestorPath = Split-Path -Parent $ancestorPath
    if ($nextAncestorPath -eq $ancestorPath) {
      break
    }
    $ancestorPath = $nextAncestorPath
  }

  if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
    try {
      $null = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
      return [pscustomobject]@{
        Kind         = "marked-section"
        RelativePath = $relativePath
        FullPath     = $fullDirectoryPath
        Reason       = "Section already has _category_.json."
        Qualifies    = $false
      }
    }
    catch {
      return [pscustomobject]@{
        Kind         = "malformed-category"
        RelativePath = $relativePath
        FullPath     = $fullDirectoryPath
        Reason       = "Existing _category_.json is malformed and will not be overwritten."
        Qualifies    = $false
      }
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($relativePath) -and $relativePath -notmatch '/' -and $ConfiguredDomainRoots.Contains($relativePath)) {
    return [pscustomobject]@{
      Kind         = "domain-root"
      RelativePath = $relativePath
      FullPath     = $fullDirectoryPath
      Reason       = "Configured domain-owned root is controlled by _domains.json."
      Qualifies    = $false
    }
  }

  $navigableFiles = @(
    Get-ChildItem -LiteralPath $fullDirectoryPath -File -ErrorAction SilentlyContinue |
    Where-Object { Test-DocsNavigableMarkdownFile -FileInfo $_ }
  )
  if ($navigableFiles.Count -gt 0) {
    return [pscustomobject]@{
      Kind         = "legacy-section"
      RelativePath = $relativePath
      FullPath     = $fullDirectoryPath
      Reason       = "Directory is exposed as a section by navigable Markdown/MDX descendants but has no _category_.json."
      Qualifies    = $true
    }
  }

  $allChildEntries = @(
    Get-ChildItem -LiteralPath $fullDirectoryPath -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "_category_.json" }
  )
  if ($allChildEntries.Count -eq 0) {
    return [pscustomobject]@{
      Kind         = "empty-directory"
      RelativePath = $relativePath
      FullPath     = $fullDirectoryPath
      Reason       = "Directory is empty."
      Qualifies    = $false
    }
  }

  return [pscustomobject]@{
    Kind         = "asset-only-directory"
    RelativePath = $relativePath
    FullPath     = $fullDirectoryPath
    Reason       = "Directory has no navigable Markdown/MDX content."
    Qualifies    = $false
  }
}

function Get-DocsSectionNormalizationAudit {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [string[]]$ScopeDirectories = @()
  )

  $configuredDomainRoots = Get-DocsConfiguredDomainRootSet -DocsRoot $DocsRoot
  $scanRoots = New-Object System.Collections.Generic.List[string]
  if (@($ScopeDirectories).Count -eq 0) {
    $scanRoots.Add([System.IO.Path]::GetFullPath($DocsRoot)) | Out-Null
  }
  else {
    $seenRoots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($scopeDirectory in @($ScopeDirectories)) {
      if ([string]::IsNullOrWhiteSpace([string]$scopeDirectory)) { continue }
      $resolvedScope = [System.IO.Path]::GetFullPath([string]$scopeDirectory)
      if (-not $resolvedScope.Equals([System.IO.Path]::GetFullPath($DocsRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
        Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $resolvedScope
      }
      if (-not (Test-Path -LiteralPath $resolvedScope -PathType Container)) {
        continue
      }
      if ($seenRoots.Add($resolvedScope)) {
        $scanRoots.Add($resolvedScope) | Out-Null
      }
    }
  }

  $findings = New-Object System.Collections.Generic.List[object]
  $seenDirectories = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

  foreach ($scanRoot in @($scanRoots.ToArray())) {
    if (-not (Test-Path -LiteralPath $scanRoot -PathType Container)) {
      continue
    }

    foreach ($directory in @(
        Get-ChildItem -LiteralPath $scanRoot -Directory -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName
      )) {
      $resolvedDirectory = [System.IO.Path]::GetFullPath($directory.FullName)
      if (-not $seenDirectories.Add($resolvedDirectory)) {
        continue
      }

      $finding = Get-DocsLegacySectionFinding `
        -DocsRoot $DocsRoot `
        -DirectoryPath $resolvedDirectory `
        -ConfiguredDomainRoots $configuredDomainRoots
      $findings.Add($finding) | Out-Null
    }
  }

  return [pscustomobject]@{
    DocsRoot             = $DocsRoot
    ScannedRoots         = @($scanRoots.ToArray() | ForEach-Object { (Get-UEToolSuiteRelativePath -BasePath $DocsRoot -TargetPath $_) -replace '\\', '/' })
    Findings             = @($findings.ToArray())
    DetectedLegacyFields = @($findings.ToArray() | Where-Object { $_.Qualifies })
  }
}

function New-DocsSectionNormalizationPlan {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [string[]]$ScopeDirectories = @()
  )

  $audit = Get-DocsSectionNormalizationAudit -DocsRoot $DocsRoot -ScopeDirectories $ScopeDirectories
  $legacySections = @($audit.Findings | Where-Object { $_.Qualifies })
  $plannedFiles = New-Object System.Collections.Generic.List[object]
  $affectedParents = New-Object System.Collections.Generic.List[object]

  foreach ($parentDir in @($legacySections | Group-Object { Split-Path -Path $_.FullPath -Parent })) {
    $resolvedParentDir = [System.IO.Path]::GetFullPath([string]$parentDir.Name)
    $siblingsBefore = @(Get-DocsNavigationSiblings -DocsRoot $DocsRoot -ParentDir $resolvedParentDir)
    $orderBefore = @($siblingsBefore | ForEach-Object { [string]$_.RelativePath })
    $plannedRelativePaths = @($parentDir.Group | ForEach-Object { [string]$_.RelativePath })
    $validatedOrderBefore = @(
      $siblingsBefore |
      Where-Object {
        if ([string]$_.ItemType -eq "page") {
          return $true
        }

        if ([string]$_.RelativePath -in $plannedRelativePaths) {
          return $true
        }

        return ($null -ne (Get-CategoryPositionForDirectory -DirectoryPath ([string]$_.FullPath)))
      } |
      ForEach-Object { [string]$_.RelativePath }
    )
    $affectedParents.Add([pscustomobject]@{
        ParentDir            = $resolvedParentDir
        RelativePath         = ((Get-UEToolSuiteRelativePath -BasePath $DocsRoot -TargetPath $resolvedParentDir) -replace '\\', '/')
        OrderBefore          = $orderBefore
        ValidatedOrderBefore = $validatedOrderBefore
      }) | Out-Null

    foreach ($legacySection in @($parentDir.Group | Sort-Object RelativePath)) {
      $matchingSibling = @($siblingsBefore | Where-Object {
          ([string]$_.ItemType) -eq "section" -and
          [System.IO.Path]::GetFullPath([string]$_.FullPath).Equals([System.IO.Path]::GetFullPath([string]$legacySection.FullPath), [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
      if ($null -eq $matchingSibling) {
        throw "Failed to plan legacy section normalization because the current navigation model does not expose '$($legacySection.RelativePath)' as a section."
      }

      $plannedPosition = ConvertTo-CompactNumericValue -Value ([double]$matchingSibling.Position)
      $metadata = [ordered]@{
        label    = (Get-DocsSectionDisplayLabel -DirectoryPath ([string]$legacySection.FullPath))
        position = $plannedPosition
      }

      $plannedFiles.Add([pscustomobject]@{
          RelativePath = [string]$legacySection.RelativePath
          FullPath     = [string]$legacySection.FullPath
          CategoryPath = (Join-Path ([string]$legacySection.FullPath) "_category_.json")
          Label        = [string]$metadata.label
          Position     = $plannedPosition
          Metadata     = $metadata
          Content      = (Build-CategoryMetadataContent -Metadata $metadata)
        }) | Out-Null
    }
  }

  return [pscustomobject]@{
    DocsRoot               = $DocsRoot
    ScannedRoots           = @($audit.ScannedRoots)
    Findings               = @($audit.Findings)
    DetectedLegacySections = @($legacySections)
    PlannedFiles           = @($plannedFiles.ToArray())
    AffectedParents        = @($affectedParents.ToArray())
    SkippedEntries         = @($audit.Findings | Where-Object { -not $_.Qualifies -and $_.Kind -ne "marked-section" })
    Warnings               = @($audit.Findings | Where-Object { $_.Kind -eq "malformed-category" })
  }
}

function Remove-DocsSectionNormalizationFiles {
  param([AllowEmptyCollection()][string[]]$Paths = @())

  foreach ($path in @($Paths | Sort-Object Length -Descending)) {
    if ([string]::IsNullOrWhiteSpace([string]$path)) {
      continue
    }

    if (Test-Path -LiteralPath $path -PathType Leaf) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-DocsSectionMigration {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [switch]$WhatIf,
    [string[]]$ScopeDirectories = @()
  )

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  if (-not (Test-Path -LiteralPath $docsRoot -PathType Container)) {
    throw "Docs root not found: $docsRoot"
  }

  $plan = New-DocsSectionNormalizationPlan -DocsRoot $docsRoot -ScopeDirectories $ScopeDirectories
  $createdFiles = New-Object System.Collections.Generic.List[string]

  if ($WhatIf -or $plan.PlannedFiles.Count -eq 0) {
    return [pscustomobject]@{
      Command                = "migrate-sections"
      RepoRoot               = $ResolvedRepoRoot
      DocsRoot               = $docsRoot
      WhatIf                 = [bool]$WhatIf
      Changed                = $false
      ScannedRoots           = @($plan.ScannedRoots)
      Findings               = @($plan.Findings)
      DetectedLegacySections = @($plan.DetectedLegacySections)
      PlannedFiles           = @($plan.PlannedFiles)
      CreatedFiles           = @()
      SkippedEntries         = @($plan.SkippedEntries)
      Warnings               = @($plan.Warnings)
    }
  }

  try {
    foreach ($plannedFile in @($plan.PlannedFiles)) {
      $categoryPath = [string]$plannedFile.CategoryPath
      if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
        throw "Refusing to overwrite existing section metadata: $categoryPath"
      }

      Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $categoryPath -Content ([string]$plannedFile.Content)
      $createdFiles.Add($categoryPath) | Out-Null
    }

    foreach ($affectedParent in @($plan.AffectedParents)) {
      $expectedOrder = @($affectedParent.ValidatedOrderBefore)
      $expectedOrderSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
      foreach ($expectedPath in $expectedOrder) {
        [void]$expectedOrderSet.Add([string]$expectedPath)
      }

      $currentOrder = @(
        Get-DocsNavigationSiblings -DocsRoot $docsRoot -ParentDir ([string]$affectedParent.ParentDir) |
        ForEach-Object { [string]$_.RelativePath } |
        Where-Object { $expectedOrderSet.Contains([string]$_) }
      )

      if ($currentOrder.Count -ne $expectedOrder.Count -or -not ([string]::Join("|", $currentOrder).Equals([string]::Join("|", $expectedOrder), [System.StringComparison]::Ordinal))) {
        throw "Section normalization changed navigation order under '$([string]$affectedParent.RelativePath)'."
      }
    }
  }
  catch {
    Remove-DocsSectionNormalizationFiles -Paths @($createdFiles.ToArray())
    throw
  }

  return [pscustomobject]@{
    Command                = "migrate-sections"
    RepoRoot               = $ResolvedRepoRoot
    DocsRoot               = $docsRoot
    WhatIf                 = $false
    Changed                = ($createdFiles.Count -gt 0)
    ScannedRoots           = @($plan.ScannedRoots)
    Findings               = @($plan.Findings)
    DetectedLegacySections = @($plan.DetectedLegacySections)
    PlannedFiles           = @($plan.PlannedFiles)
    CreatedFiles           = @($createdFiles.ToArray())
    SkippedEntries         = @($plan.SkippedEntries)
    Warnings               = @($plan.Warnings)
  }
}

function Assert-PathInsideRoot {
  param(
    [Parameter(Mandatory)][string]$RootPath,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
  $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
  if (-not $targetFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path '$TargetPath' resolves outside the intended root '$RootPath'."
  }
}

function Test-DocsSectionExists {
  param([Parameter(Mandatory)][string]$SectionDir)

  if (-not (Test-Path -LiteralPath $SectionDir -PathType Container)) {
    return $false
  }

  $categoryPath = Join-Path $SectionDir "_category_.json"
  return (Test-Path -LiteralPath $categoryPath -PathType Leaf)
}

function Test-DocsImplicitSectionExists {
  param([Parameter(Mandatory)][string]$SectionDir)

  if (-not (Test-Path -LiteralPath $SectionDir -PathType Container)) {
    return $false
  }

  $docsRoot = Split-Path -Parent $SectionDir
  while (-not [string]::IsNullOrWhiteSpace($docsRoot)) {
    if ([System.IO.Path]::GetFileName($docsRoot).Equals("Docs", [System.StringComparison]::OrdinalIgnoreCase)) {
      break
    }

    $nextParent = Split-Path -Parent $docsRoot
    if ($nextParent -eq $docsRoot) {
      break
    }
    $docsRoot = $nextParent
  }

  if ([string]::IsNullOrWhiteSpace($docsRoot) -or -not [System.IO.Path]::GetFileName($docsRoot).Equals("Docs", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $false
  }

  $finding = Get-DocsLegacySectionFinding `
    -DocsRoot $docsRoot `
    -DirectoryPath $SectionDir `
    -ConfiguredDomainRoots (Get-DocsConfiguredDomainRootSet -DocsRoot $docsRoot)
  return [bool]$finding.Qualifies
}

function Get-DocsImplicitSectionFallbackPosition {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$DirectoryPath
  )

  $parentDir = Split-Path -Parent $DirectoryPath
  if ([string]::IsNullOrWhiteSpace($parentDir) -or -not (Test-Path -LiteralPath $parentDir -PathType Container)) {
    return 100000.0
  }

  $positions = New-Object System.Collections.Generic.List[double]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $parentDir -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension.Equals(".md", [System.StringComparison]::OrdinalIgnoreCase) -or
        $_.Extension.Equals(".mdx", [System.StringComparison]::OrdinalIgnoreCase)
      })) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $parentDir -Directory -ErrorAction SilentlyContinue)) {
    if (-not (Test-DocsSectionExists -SectionDir $childDir.FullName)) {
      continue
    }

    $position = Get-CategoryPositionForDirectory -DirectoryPath $childDir.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  $fallbackPosition = 100000.0
  if ($positions.Count -gt 0) {
    $fallbackPosition = ((($positions.ToArray() | Measure-Object -Maximum).Maximum) + 1.0)
  }

  $fallbackIndex = 0.0
  foreach ($childDir in @(Get-ChildItem -LiteralPath $parentDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if (Test-DocsSectionExists -SectionDir $childDir.FullName) {
      continue
    }

    if (-not (Test-DocsImplicitSectionExists -SectionDir $childDir.FullName)) {
      continue
    }

    if ($childDir.FullName.Equals($DirectoryPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      return ($fallbackPosition + $fallbackIndex)
    }

    $fallbackIndex += 1.0
  }

  return ($fallbackPosition + $fallbackIndex)
}

function Get-CommonDocValueOptionNames {
  return @(
    "title",
    "slug",
    "position",
    "description",
    "image",
    "sidebarlabel",
    "sidebarclassname",
    "sidebarkey",
    "sidebarcustompropsjson",
    "displayedsidebar",
    "paginationlabel",
    "paginationnext",
    "paginationprev",
    "hidetitle",
    "hidetableofcontents",
    "tocminheadinglevel",
    "tocmaxheadinglevel",
    "customediturl",
    "draft",
    "unlisted",
    "parsenumberprefixes",
    "lastupdatedate",
    "lastupdateauthor",
    "tags",
    "tagsjson",
    "keywords"
  )
}

function New-DocFrontMatter {
  param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Slug,
    [AllowNull()]$SidebarPosition
  )

  $frontMatter = [ordered]@{
    title = $Title
    slug  = $Slug
  }

  if ($null -ne $SidebarPosition) {
    Set-OrderedMapValue -Map $frontMatter -Key "sidebar_position" -Value $SidebarPosition
  }

  return $frontMatter
}

function Apply-CommonDocOptionValues {
  param(
    [Parameter(Mandatory)][System.Collections.IDictionary]$FrontMatter,
    [Parameter(Mandatory)][hashtable]$Values
  )

  if ($Values.ContainsKey("description")) { Set-OrderedMapValue -Map $FrontMatter -Key "description" -Value $Values["description"] }
  if ($Values.ContainsKey("image")) { Set-OrderedMapValue -Map $FrontMatter -Key "image" -Value $Values["image"] }
  if ($Values.ContainsKey("keywords")) { Set-OrderedMapValue -Map $FrontMatter -Key "keywords" -Value @(ConvertTo-StringList -Value $Values["keywords"]) }
  if ($Values.ContainsKey("tags")) { Set-OrderedMapValue -Map $FrontMatter -Key "tags" -Value @(ConvertTo-StringList -Value $Values["tags"]) }
  if ($Values.ContainsKey("tagsjson")) { Set-OrderedMapValue -Map $FrontMatter -Key "tags" -Value (ConvertFrom-JsonArgument -Value $Values["tagsjson"] -OptionName "tagsjson") }
  if ($Values.ContainsKey("sidebarlabel")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_label" -Value $Values["sidebarlabel"] }
  if ($Values.ContainsKey("sidebarclassname")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_class_name" -Value $Values["sidebarclassname"] }
  if ($Values.ContainsKey("sidebarkey")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_key" -Value $Values["sidebarkey"] }
  if ($Values.ContainsKey("sidebarcustompropsjson")) { Set-OrderedMapValue -Map $FrontMatter -Key "sidebar_custom_props" -Value (ConvertFrom-JsonArgument -Value $Values["sidebarcustompropsjson"] -OptionName "sidebarcustompropsjson") }
  if ($Values.ContainsKey("displayedsidebar")) { Set-OrderedMapValue -Map $FrontMatter -Key "displayed_sidebar" -Value $Values["displayedsidebar"] }
  if ($Values.ContainsKey("paginationlabel")) { Set-OrderedMapValue -Map $FrontMatter -Key "pagination_label" -Value $Values["paginationlabel"] }
  if ($Values.ContainsKey("paginationnext")) { Set-OrderedMapValue -Map $FrontMatter -Key "pagination_next" -Value (ConvertTo-NullableStringValue -Value $Values["paginationnext"]) }
  if ($Values.ContainsKey("paginationprev")) { Set-OrderedMapValue -Map $FrontMatter -Key "pagination_prev" -Value (ConvertTo-NullableStringValue -Value $Values["paginationprev"]) }
  if ($Values.ContainsKey("hidetitle")) { Set-OrderedMapValue -Map $FrontMatter -Key "hide_title" -Value (ConvertTo-BooleanValue -Value $Values["hidetitle"] -OptionName "HideTitle") }
  if ($Values.ContainsKey("hidetableofcontents")) { Set-OrderedMapValue -Map $FrontMatter -Key "hide_table_of_contents" -Value (ConvertTo-BooleanValue -Value $Values["hidetableofcontents"] -OptionName "HideTableOfContents") }
  if ($Values.ContainsKey("tocminheadinglevel")) { Set-OrderedMapValue -Map $FrontMatter -Key "toc_min_heading_level" -Value (ConvertTo-IntegerValue -Value $Values["tocminheadinglevel"] -OptionName "TocMinHeadingLevel") }
  if ($Values.ContainsKey("tocmaxheadinglevel")) { Set-OrderedMapValue -Map $FrontMatter -Key "toc_max_heading_level" -Value (ConvertTo-IntegerValue -Value $Values["tocmaxheadinglevel"] -OptionName "TocMaxHeadingLevel") }
  if ($Values.ContainsKey("customediturl")) { Set-OrderedMapValue -Map $FrontMatter -Key "custom_edit_url" -Value (ConvertTo-NullableStringValue -Value $Values["customediturl"]) }
  if ($Values.ContainsKey("draft")) { Set-OrderedMapValue -Map $FrontMatter -Key "draft" -Value (ConvertTo-BooleanValue -Value $Values["draft"] -OptionName "Draft") }
  if ($Values.ContainsKey("unlisted")) { Set-OrderedMapValue -Map $FrontMatter -Key "unlisted" -Value (ConvertTo-BooleanValue -Value $Values["unlisted"] -OptionName "Unlisted") }
  if ($Values.ContainsKey("parsenumberprefixes")) { Set-OrderedMapValue -Map $FrontMatter -Key "parse_number_prefixes" -Value (ConvertTo-BooleanValue -Value $Values["parsenumberprefixes"] -OptionName "ParseNumberPrefixes") }

  $lastUpdate = [ordered]@{}
  if ($Values.ContainsKey("lastupdatedate")) { Set-OrderedMapValue -Map $lastUpdate -Key "date" -Value $Values["lastupdatedate"] }
  if ($Values.ContainsKey("lastupdateauthor")) { Set-OrderedMapValue -Map $lastUpdate -Key "author" -Value $Values["lastupdateauthor"] }
  if ($lastUpdate.Count -gt 0) {
    Set-OrderedMapValue -Map $FrontMatter -Key "last_update" -Value $lastUpdate
  }
}

function New-CategoryMetadata {
  param(
    [Parameter(Mandatory)][string]$Label,
    [AllowNull()]$Position,
    [AllowNull()][string]$LinkType,
    [string]$LinkDocId,
    [string]$GeneratedIndexTitle,
    [string]$GeneratedIndexSlug,
    [string]$GeneratedIndexDescription,
    [string]$GeneratedIndexImage,
    [string]$GeneratedIndexKeywords,
    [string]$ClassName,
    [string]$Key,
    [AllowNull()]$Collapsible,
    [AllowNull()]$Collapsed,
    [AllowNull()]$CustomProps,
    [string[]]$Assignments = @(),
    [string[]]$JsonAssignments = @()
  )

  $metadata = [ordered]@{
    label = $Label
  }

  if ($null -ne $Position) { Set-OrderedMapValue -Map $metadata -Key "position" -Value $Position }
  if (-not [string]::IsNullOrWhiteSpace($ClassName)) { Set-OrderedMapValue -Map $metadata -Key "className" -Value $ClassName }
  if (-not [string]::IsNullOrWhiteSpace($Key)) { Set-OrderedMapValue -Map $metadata -Key "key" -Value $Key }
  if ($null -ne $Collapsible) { Set-OrderedMapValue -Map $metadata -Key "collapsible" -Value $Collapsible }
  if ($null -ne $Collapsed) { Set-OrderedMapValue -Map $metadata -Key "collapsed" -Value $Collapsed }
  if ($null -ne $CustomProps) { Set-OrderedMapValue -Map $metadata -Key "customProps" -Value $CustomProps }

  $normalizedLinkType = if ([string]::IsNullOrWhiteSpace($LinkType)) { "doc" } else { $LinkType.Trim().ToLowerInvariant() }
  switch ($normalizedLinkType) {
    "doc" {
      $link = [ordered]@{
        type = "doc"
        id   = $LinkDocId
      }
      Set-OrderedMapValue -Map $metadata -Key "link" -Value $link
    }
    "generated-index" {
      $link = [ordered]@{
        type = "generated-index"
      }

      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexTitle)) { Set-OrderedMapValue -Map $link -Key "title" -Value $GeneratedIndexTitle }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexSlug)) { Set-OrderedMapValue -Map $link -Key "slug" -Value $GeneratedIndexSlug }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexDescription)) { Set-OrderedMapValue -Map $link -Key "description" -Value $GeneratedIndexDescription }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexImage)) { Set-OrderedMapValue -Map $link -Key "image" -Value $GeneratedIndexImage }
      if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexKeywords)) { Set-OrderedMapValue -Map $link -Key "keywords" -Value @(ConvertTo-StringList -Value $GeneratedIndexKeywords) }

      Set-OrderedMapValue -Map $metadata -Key "link" -Value $link
    }
    "none" {
      Set-OrderedMapValue -Map $metadata -Key "link" -Value $null
    }
    default {
      throw "LinkType expects one of: doc, generated-index, none."
    }
  }

  Apply-KeyValueAssignmentsToMap -Map $metadata -Assignments $Assignments -JsonAssignments $JsonAssignments
  return $metadata
}

function Invoke-NewSection {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $parsed = Parse-SubcommandArguments `
    -CommandArguments $CommandArguments `
    -SwitchNames @("force", "notoc") `
    -ValueNames @(
    "title", "label", "slug", "position", "docsidebarposition",
    "description", "image", "keywords", "tags", "tagsjson",
    "sidebarlabel", "sidebarclassname", "sidebarkey", "sidebarcustompropsjson",
    "displayedsidebar", "paginationlabel", "paginationnext", "paginationprev",
    "hidetitle", "hidetableofcontents", "tocminheadinglevel", "tocmaxheadinglevel",
    "customediturl", "draft", "unlisted", "parsenumberprefixes",
    "lastupdatedate", "lastupdateauthor",
    "collapsible", "collapsed", "classname", "key", "custompropsjson",
    "linktype", "linkid", "generatedindextitle", "generatedindexslug",
    "generatedindexdescription", "generatedindeximage", "generatedindexkeywords"
  ) `
    -MultiValueNames @("docfield", "docfieldjson", "categoryfield", "categoryjson")
  if ($parsed.Positionals.Count -eq 0) {
    throw "SectionPath is required. Usage: ue-tools docs new-section <SectionPath> [options]. Run 'ue-tools docs help new-section'."
  }

  if ($parsed.Positionals.Count -gt 1) {
    throw "Too many positional arguments for new-section. Usage: ue-tools docs new-section <SectionPath> [options]. Run 'ue-tools docs help new-section'."
  }

  $sectionPath = $parsed.Positionals[0]
  $title = if ($parsed.Values.ContainsKey("title")) { $parsed.Values["title"] } else { ConvertTo-TitleWords ($sectionPath -split '[\\/]' | Select-Object -Last 1) }
  $label = if ($parsed.Values.ContainsKey("label")) { $parsed.Values["label"] } else { $title }
  $force = $parsed.Switches.ContainsKey("force")
  $noToc = $parsed.Switches.ContainsKey("notoc")

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $sectionSegments = @($sectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($sectionSegments.Count -eq 0) {
    throw "Section path must not be empty."
  }

  if ($sectionSegments.Count -gt 1) {
    $parentSegments = @($sectionSegments[0..($sectionSegments.Count - 2)])
    $parentDir = Join-Path $docsRoot (($parentSegments -join [System.IO.Path]::DirectorySeparatorChar))
    Assert-PathInsideRoot -RootPath $docsRoot -TargetPath $parentDir

    if (-not (Test-DocsSectionExists -SectionDir $parentDir)) {
      throw "Parent section does not exist: $parentDir"
    }
  }

  $sectionDir = Join-Path $docsRoot (($sectionSegments -join [System.IO.Path]::DirectorySeparatorChar))
  Assert-PathInsideRoot -RootPath $docsRoot -TargetPath $sectionDir
  $position = if ($parsed.Values.ContainsKey("position")) { ConvertTo-NumericValue -Value $parsed.Values["position"] -OptionName "Position" } else { Get-NextSectionPosition -DocsRoot $docsRoot -SectionPath $sectionPath }

  $readmePath = Join-Path $sectionDir "README.md"
  $categoryPath = Join-Path $sectionDir "_category_.json"
  $docSlug = if ($parsed.Values.ContainsKey("slug")) { $parsed.Values["slug"] } else { Get-SlugForSectionPath -SectionPath $sectionPath }
  $bridgeStatus = Get-BridgeStatus
  $includeToc = (-not $noToc) -and $bridgeStatus.TocReady
  $linkType = if ($parsed.Values.ContainsKey("linktype")) { $parsed.Values["linktype"] } else { "doc" }
  $normalizedLinkType = [string]$linkType
  if (-not [string]::IsNullOrWhiteSpace($normalizedLinkType)) {
    $normalizedLinkType = $normalizedLinkType.Trim().ToLowerInvariant()
  }
  $createsReadme = ($normalizedLinkType -eq "doc")

  if ((Test-Path -LiteralPath $sectionDir) -and (-not $force)) {
    throw "Section directory already exists: $sectionDir"
  }

  New-Item -ItemType Directory -Force -Path $sectionDir | Out-Null

  $docId = ""
  $readmeContent = ""
  if ($createsReadme) {
    $docSidebarPosition = if ($parsed.Values.ContainsKey("docsidebarposition")) { ConvertTo-NumericValue -Value $parsed.Values["docsidebarposition"] -OptionName "DocSidebarPosition" } else { 1 }
    $readmeFrontMatter = New-DocFrontMatter -Title $title -Slug $docSlug -SidebarPosition $docSidebarPosition
    Apply-CommonDocOptionValues -FrontMatter $readmeFrontMatter -Values $parsed.Values
    Apply-KeyValueAssignmentsToMap `
      -Map $readmeFrontMatter `
      -Assignments @($parsed.MultiValues["docfield"]) `
      -JsonAssignments @($parsed.MultiValues["docfieldjson"])

    $readmeContent = Build-ScaffoldDocContent -FrontMatter $readmeFrontMatter -HeadingTitle $title -IncludeToc:$includeToc -OverviewNoun "section"
    $docId = Get-DocIdForPath -DocsRoot $docsRoot -FullPath $readmePath
  }

  $linkDocId = if ($parsed.Values.ContainsKey("linkid")) { $parsed.Values["linkid"] } else { $docId }
  $generatedIndexTitle = if ($parsed.Values.ContainsKey("generatedindextitle")) { $parsed.Values["generatedindextitle"] } else { $label }
  $generatedIndexSlug = if ($parsed.Values.ContainsKey("generatedindexslug")) { $parsed.Values["generatedindexslug"] } else { $docSlug }
  $categoryCustomProps = if ($parsed.Values.ContainsKey("custompropsjson")) { ConvertFrom-JsonArgument -Value $parsed.Values["custompropsjson"] -OptionName "CustomPropsJson" } else { $null }
  $categoryCollapsible = if ($parsed.Values.ContainsKey("collapsible")) { ConvertTo-BooleanValue -Value $parsed.Values["collapsible"] -OptionName "Collapsible" } else { $null }
  $categoryCollapsed = if ($parsed.Values.ContainsKey("collapsed")) { ConvertTo-BooleanValue -Value $parsed.Values["collapsed"] -OptionName "Collapsed" } else { $null }

  $categoryMetadata = New-CategoryMetadata `
    -Label $label `
    -Position $position `
    -LinkType $linkType `
    -LinkDocId $linkDocId `
    -GeneratedIndexTitle $generatedIndexTitle `
    -GeneratedIndexSlug $generatedIndexSlug `
    -GeneratedIndexDescription $parsed.Values["generatedindexdescription"] `
    -GeneratedIndexImage $parsed.Values["generatedindeximage"] `
    -GeneratedIndexKeywords $parsed.Values["generatedindexkeywords"] `
    -ClassName $parsed.Values["classname"] `
    -Key $parsed.Values["key"] `
    -Collapsible $categoryCollapsible `
    -Collapsed $categoryCollapsed `
    -CustomProps $categoryCustomProps `
    -Assignments @($parsed.MultiValues["categoryfield"]) `
    -JsonAssignments @($parsed.MultiValues["categoryjson"])
  $categoryContent = Build-CategoryMetadataContent -Metadata $categoryMetadata

  if ($createsReadme) {
    Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $readmePath -Content $readmeContent
  }
  Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $categoryPath -Content $categoryContent

  if ($createsReadme -and $includeToc) {
    $null = Queue-TocRequest -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $readmePath
    [void](Open-PathInVSCode -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $readmePath)
  }

  [pscustomobject]@{
    Command      = "new-section"
    Path         = $sectionDir
    ReadmePath   = $(if ($createsReadme) { $readmePath } else { "" })
    CategoryPath = $categoryPath
    TocQueued    = ($createsReadme -and $includeToc)
    BridgeStatus = $bridgeStatus
  }
}

function Invoke-NewPage {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $parsed = Parse-SubcommandArguments `
    -CommandArguments $CommandArguments `
    -SwitchNames @("force", "notoc") `
    -ValueNames (Get-CommonDocValueOptionNames) `
    -MultiValueNames @("field", "fieldjson")
  if ($parsed.Positionals.Count -eq 0) {
    throw "PageName is required. Usage: ue-tools docs new-page <PageName> [options] or ue-tools docs new-page <SectionPath> <PageName> [options]. Run 'ue-tools docs help new-page'."
  }

  if ($parsed.Positionals.Count -gt 2) {
    throw "Too many positional arguments for new-page. Usage: ue-tools docs new-page <PageName> [options] or ue-tools docs new-page <SectionPath> <PageName> [options]. Run 'ue-tools docs help new-page'."
  }

  $sectionPath = $null
  if ($parsed.Positionals.Count -eq 1) {
    $pageName = $parsed.Positionals[0]
  }
  else {
    $sectionPath = $parsed.Positionals[0]
    $pageName = $parsed.Positionals[1]
  }
  $title = if ($parsed.Values.ContainsKey("title")) { $parsed.Values["title"] } else { ConvertTo-TitleWords $pageName }
  $force = $parsed.Switches.ContainsKey("force")
  $noToc = $parsed.Switches.ContainsKey("notoc")

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $sectionDir = $docsRoot
  if (-not [string]::IsNullOrWhiteSpace($sectionPath)) {
    $sectionSegments = @($sectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($sectionSegments.Count -eq 0) {
      throw "Section path must not be empty."
    }

    $sectionDir = Join-Path $docsRoot (($sectionSegments -join [System.IO.Path]::DirectorySeparatorChar))
    Assert-PathInsideRoot -RootPath $docsRoot -TargetPath $sectionDir

    if (-not (Test-DocsSectionExists -SectionDir $sectionDir)) {
      throw "Section does not exist: $sectionDir"
    }
  }

  $fileStem = ConvertTo-FileStem $pageName
  $pagePath = Join-Path $sectionDir "$fileStem.md"
  $position = if ($parsed.Values.ContainsKey("position")) { ConvertTo-NumericValue -Value $parsed.Values["position"] -OptionName "Position" } else { Get-NextPagePosition -SectionDir $sectionDir }
  $docSlug = if ($parsed.Values.ContainsKey("slug")) { $parsed.Values["slug"] } else { Get-SlugForPage -SectionPath $sectionPath -PageName $pageName }
  $bridgeStatus = Get-BridgeStatus
  $includeToc = (-not $noToc) -and $bridgeStatus.TocReady

  if ((Test-Path -LiteralPath $pagePath) -and (-not $force)) {
    throw "Page already exists: $pagePath"
  }

  $pageFrontMatter = New-DocFrontMatter -Title $title -Slug $docSlug -SidebarPosition $position
  Apply-CommonDocOptionValues -FrontMatter $pageFrontMatter -Values $parsed.Values
  Apply-KeyValueAssignmentsToMap `
    -Map $pageFrontMatter `
    -Assignments @($parsed.MultiValues["field"]) `
    -JsonAssignments @($parsed.MultiValues["fieldjson"])

  $pageContent = Build-ScaffoldDocContent -FrontMatter $pageFrontMatter -HeadingTitle $title -IncludeToc:$includeToc -OverviewNoun "page"
  Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $pagePath -Content $pageContent

  if ($includeToc) {
    $null = Queue-TocRequest -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $pagePath
    [void](Open-PathInVSCode -ResolvedRepoRoot $ResolvedRepoRoot -FilePath $pagePath)
  }

  [pscustomobject]@{
    Command      = "new-page"
    Path         = $pagePath
    TocQueued    = $includeToc
    BridgeStatus = $bridgeStatus
  }
}

function Get-MarkdownDocFiles {
  param([Parameter(Mandatory)][string]$DocsRoot)

  $files = Get-ChildItem -LiteralPath $DocsRoot -Recurse -File -Filter *.md
  return @($files | Where-Object {
      $fullName = $_.FullName
      $fullName -notmatch '\\CodingStandards\\Snapshots\\' -and
      $fullName -notmatch '\\CodingStandards\\Templates\\'
    })
}

function Get-FrontMatterBlock {
  param([Parameter(Mandatory)][string]$Content)

  if ($Content -notmatch '(?s)\A---\s*\r?\n(.*?)\r?\n---\s*(?:\r?\n|$)') {
    return $null
  }

  return $Matches[1]
}

function Get-FrontMatterValue {
  param(
    [AllowNull()][string]$FrontMatter,
    [Parameter(Mandatory)][string]$Key
  )

  if ([string]::IsNullOrWhiteSpace($FrontMatter)) {
    return $null
  }

  $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$"
  if ($FrontMatter -notmatch $pattern) {
    return $null
  }

  $value = $Matches[1].Trim()
  if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
    $value = $value.Substring(1, $value.Length - 2)
  }

  return $value
}

function Get-SidebarPositionForMarkdownFile {
  param([Parameter(Mandatory)][string]$FilePath)

  if (-not (Test-Path -LiteralPath $FilePath)) {
    return $null
  }

  $content = Get-Content -LiteralPath $FilePath -Raw
  $frontMatter = Get-FrontMatterBlock -Content $content
  $value = Get-FrontMatterValue -FrontMatter $frontMatter -Key "sidebar_position"
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $null
  }

  $parsed = 0.0
  if ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Get-CategoryPositionForDirectory {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath)) {
    return $null
  }

  try {
    $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  }
  catch {
    return $null
  }

  if ($null -eq $categoryJson.position) {
    return $null
  }

  $parsed = 0.0
  if ([double]::TryParse("$($categoryJson.position)", [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Get-NextSectionPosition {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$SectionPath
  )

  $sectionSegments = @($SectionPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($sectionSegments.Count -le 1) {
    $parentDir = $DocsRoot
  }
  else {
    $parentSegments = @($sectionSegments[0..($sectionSegments.Count - 2)])
    $parentDir = Join-Path $DocsRoot (($parentSegments -join [System.IO.Path]::DirectorySeparatorChar))
  }

  $positions = New-Object System.Collections.Generic.List[double]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $parentDir -File -Filter *.md -ErrorAction SilentlyContinue)) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $parentDir -Directory -ErrorAction SilentlyContinue)) {
    $position = Get-CategoryPositionForDirectory -DirectoryPath $childDir.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  if ($positions.Count -eq 0) {
    return 1.0
  }

  return (ConvertTo-CompactNumericValue -Value ((($positions.ToArray() | Measure-Object -Maximum).Maximum) + 1))
}

function Get-NextPagePosition {
  param([Parameter(Mandatory)][string]$SectionDir)

  $positions = New-Object System.Collections.Generic.List[double]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $SectionDir -File -Filter *.md -ErrorAction SilentlyContinue)) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -ne $position) {
      $positions.Add($position) | Out-Null
    }
  }

  if ($positions.Count -eq 0) {
    return 1.0
  }

  return (ConvertTo-CompactNumericValue -Value ((($positions.ToArray() | Measure-Object -Maximum).Maximum) + 1))
}

function Normalize-DocsTargetPath {
  param([Parameter(Mandatory)][string]$TargetPath)

  $normalized = $TargetPath.Trim()
  $normalized = $normalized -replace '^[\\/]+', ''
  if ($normalized -match '^(?i:docs)[\\/](.+)$') {
    $normalized = $Matches[1]
  }

  $normalized = ($normalized -replace '/', '\').Trim('\')
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    throw "Target path must not be empty."
  }

  return $normalized
}

function Get-DocsItemRelativePath {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$ItemPath,
    [Parameter(Mandatory)][string]$ItemType
  )

  if ($ItemType -eq "page") {
    return (Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $ItemPath)
  }

  return ((Get-UEToolSuiteRelativePath -BasePath $DocsRoot -TargetPath $ItemPath) -replace '\\', '/')
}

function Resolve-DocsNavigationTarget {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $normalized = Normalize-DocsTargetPath -TargetPath $TargetPath

  $directoryCandidate = Join-Path $DocsRoot $normalized
  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $directoryCandidate
  if (Test-DocsSectionExists -SectionDir $directoryCandidate) {
    $position = Get-CategoryPositionForDirectory -DirectoryPath $directoryCandidate
    if ($null -eq $position) {
      throw "Target section does not have an explicit position: $(Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $directoryCandidate -ItemType 'section')"
    }

    return [pscustomobject]@{
      ItemType     = "section"
      FullPath     = $directoryCandidate
      ParentDir    = (Split-Path -Parent $directoryCandidate)
      RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $directoryCandidate -ItemType "section")
      Position     = $position
    }
  }

  if (Test-DocsImplicitSectionExists -SectionDir $directoryCandidate) {
    return [pscustomobject]@{
      ItemType     = "section"
      FullPath     = $directoryCandidate
      ParentDir    = (Split-Path -Parent $directoryCandidate)
      RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $directoryCandidate -ItemType "section")
      Position     = (Get-DocsImplicitSectionFallbackPosition -DocsRoot $DocsRoot -DirectoryPath $directoryCandidate)
    }
  }

  $fileRelativePath = $normalized
  if (-not $fileRelativePath.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
    $fileRelativePath = "$fileRelativePath.md"
  }

  $fileCandidate = Join-Path $DocsRoot $fileRelativePath
  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $fileCandidate
  if (-not (Test-Path -LiteralPath $fileCandidate -PathType Leaf)) {
    throw "Docs page or section not found: $TargetPath"
  }

  $pagePosition = Get-SidebarPositionForMarkdownFile -FilePath $fileCandidate
  if ($null -eq $pagePosition) {
    throw "Target page does not have an explicit sidebar_position: $(Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $fileCandidate -ItemType 'page')"
  }

  return [pscustomobject]@{
    ItemType     = "page"
    FullPath     = $fileCandidate
    ParentDir    = (Split-Path -Parent $fileCandidate)
    RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $fileCandidate -ItemType "page")
    Position     = $pagePosition
  }
}

function Get-DocsNavigationSiblings {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$ParentDir
  )

  $siblings = New-Object System.Collections.Generic.List[object]

  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $ParentDir -File -Filter *.md -ErrorAction SilentlyContinue)) {
    $position = Get-SidebarPositionForMarkdownFile -FilePath $markdownFile.FullName
    if ($null -eq $position) {
      continue
    }

    $siblings.Add([pscustomobject]@{
        ItemType     = "page"
        FullPath     = $markdownFile.FullName
        ParentDir    = $ParentDir
        RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $markdownFile.FullName -ItemType "page")
        Position     = $position
      }) | Out-Null
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue)) {
    if (-not (Test-DocsSectionExists -SectionDir $childDir.FullName)) {
      continue
    }

    $position = Get-CategoryPositionForDirectory -DirectoryPath $childDir.FullName
    if ($null -eq $position) {
      continue
    }

    $siblings.Add([pscustomobject]@{
        ItemType     = "section"
        FullPath     = $childDir.FullName
        ParentDir    = $ParentDir
        RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $childDir.FullName -ItemType "section")
        Position     = $position
      }) | Out-Null
  }

  $fallbackPosition = 100000.0
  if ($siblings.Count -gt 0) {
    $fallbackPosition = ((($siblings.ToArray() | Select-Object -ExpandProperty Position | Measure-Object -Maximum).Maximum) + 1.0)
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $hasMarkedSectionMetadata = Test-DocsSectionExists -SectionDir $childDir.FullName
    if ($hasMarkedSectionMetadata) {
      $position = Get-CategoryPositionForDirectory -DirectoryPath $childDir.FullName
      if ($null -ne $position) {
        continue
      }
    }
    elseif (-not (Test-DocsImplicitSectionExists -SectionDir $childDir.FullName)) {
      continue
    }

    $siblings.Add([pscustomobject]@{
        ItemType     = "section"
        FullPath     = $childDir.FullName
        ParentDir    = $ParentDir
        RelativePath = (Get-DocsItemRelativePath -DocsRoot $DocsRoot -ItemPath $childDir.FullName -ItemType "section")
        Position     = $fallbackPosition
      }) | Out-Null
    $fallbackPosition += 1.0
  }

  return @($siblings | Sort-Object Position, RelativePath)
}

function Set-SidebarPositionForMarkdownFile {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)]$Position
  )

  $content = Get-Content -LiteralPath $FilePath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $formattedPosition = Format-YamlNumber -Value (ConvertTo-CompactNumericValue -Value ([double]$Position))

  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')
  if (-not $match.Success) {
    $newContent = @(
      '---'
      "sidebar_position: $formattedPosition"
      '---'
      ''
      $content.TrimStart("`r", "`n")
    ) -join $newline
    Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $FilePath -Content $newContent
    return
  }

  $frontMatter = $match.Groups['frontMatter'].Value
  $rest = $match.Groups['rest'].Value

  if ($frontMatter -match '(?m)^\s*sidebar_position\s*:') {
    $updatedFrontMatter = [regex]::Replace($frontMatter, '(?m)^\s*sidebar_position\s*:\s*.+$', "sidebar_position: $formattedPosition", 1)
  }
  else {
    $updatedFrontMatter = $frontMatter.TrimEnd() + $newline + "sidebar_position: $formattedPosition"
  }

  $newContent = "---$newline$updatedFrontMatter$newline---$rest"
  Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $FilePath -Content $newContent
}

function Set-CategoryPositionForDirectory {
  param(
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)]$Position
  )

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    throw "Section category metadata not found: $categoryPath"
  }

  $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  $categoryJson.position = (ConvertTo-CompactNumericValue -Value ([double]$Position))
  $content = ($categoryJson | ConvertTo-Json -Depth 20) + "`r`n"
  Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $categoryPath -Content $content
}

function Set-DocsNavigationItemPosition {
  param(
    [Parameter(Mandatory)][pscustomobject]$Item,
    [Parameter(Mandatory)]$Position
  )

  if ($Item.ItemType -eq "page") {
    Set-SidebarPositionForMarkdownFile -FilePath $Item.FullPath -Position $Position
    return
  }

  Set-CategoryPositionForDirectory -DirectoryPath $Item.FullPath -Position $Position
}

function Invoke-DocsReorder {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $argumentList = @($CommandArguments)
  if ($argumentList.Count -eq 0) {
    throw "TargetPath is required. Usage: ue-tools docs reorder <TargetPath> <Position>. Run 'ue-tools docs help reorder'."
  }

  if ($argumentList.Count -eq 1) {
    throw "Position is required. Usage: ue-tools docs reorder <TargetPath> <Position>. Run 'ue-tools docs help reorder'."
  }

  if ($argumentList.Count -gt 2) {
    throw "Too many positional arguments for reorder. Usage: ue-tools docs reorder <TargetPath> <Position>. Run 'ue-tools docs help reorder'."
  }

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $target = Resolve-DocsNavigationTarget -DocsRoot $docsRoot -TargetPath $argumentList[0]
  $scopeDirectories = @([string]$target.ParentDir)
  if ([string]$target.ItemType -eq "section") {
    $scopeDirectories += [string]$target.FullPath
  }
  $null = Invoke-DocsSectionMigration -ResolvedRepoRoot $ResolvedRepoRoot -ScopeDirectories @($scopeDirectories)
  $target = Resolve-DocsNavigationTarget -DocsRoot $docsRoot -TargetPath $argumentList[0]
  $desiredPosition = ConvertTo-NumericValue -Value $argumentList[1] -OptionName "Position"
  if ([double]$desiredPosition -lt 1) {
    throw "Position must be 1 or greater."
  }

  $siblings = @(Get-DocsNavigationSiblings -DocsRoot $docsRoot -ParentDir $target.ParentDir)
  if ($siblings.Count -eq 0) {
    throw "No positioned sibling items were found under '$($target.ParentDir)'."
  }

  $maxPosition = [double](($siblings | Measure-Object -Property Position -Maximum).Maximum)
  if ([double]$desiredPosition -gt $maxPosition) {
    $desiredPosition = (ConvertTo-CompactNumericValue -Value $maxPosition)
  }

  $currentPosition = [double]$target.Position
  $desiredPositionNumber = [double]$desiredPosition
  if ([Math]::Abs($currentPosition - $desiredPositionNumber) -lt 0.0000001) {
    return [pscustomobject]@{
      Command      = "reorder"
      Target       = $target.RelativePath
      OldPosition  = $target.Position
      NewPosition  = $desiredPosition
      UpdatedCount = 0
    }
  }

  $changedItems = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in $siblings) {
    $siblingPath = [System.IO.Path]::GetFullPath($sibling.FullPath)
    $targetPath = [System.IO.Path]::GetFullPath($target.FullPath)
    if ($siblingPath.Equals($targetPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }

    $siblingPosition = [double]$sibling.Position
    $newSiblingPosition = $null
    if ($desiredPositionNumber -lt $currentPosition) {
      if ($siblingPosition -ge $desiredPositionNumber -and $siblingPosition -lt $currentPosition) {
        $newSiblingPosition = (ConvertTo-CompactNumericValue -Value ($siblingPosition + 1))
      }
    }
    else {
      if ($siblingPosition -le $desiredPositionNumber -and $siblingPosition -gt $currentPosition) {
        $newSiblingPosition = (ConvertTo-CompactNumericValue -Value ($siblingPosition - 1))
      }
    }

    if ($null -ne $newSiblingPosition) {
      Set-DocsNavigationItemPosition -Item $sibling -Position $newSiblingPosition
      $changedItems.Add([pscustomobject]@{
          RelativePath = $sibling.RelativePath
          Position     = $newSiblingPosition
        }) | Out-Null
    }
  }

  Set-DocsNavigationItemPosition -Item $target -Position $desiredPosition
  $changedItems.Add([pscustomobject]@{
      RelativePath = $target.RelativePath
      Position     = $desiredPosition
    }) | Out-Null

  return [pscustomobject]@{
    Command      = "reorder"
    Target       = $target.RelativePath
    OldPosition  = $target.Position
    NewPosition  = $desiredPosition
    UpdatedCount = $changedItems.Count
    UpdatedItems = @($changedItems | Sort-Object RelativePath)
  }
}

function Resolve-DocsVisibilityTarget {
  param(
    [Parameter(Mandatory)][string]$DocsRoot,
    [Parameter(Mandatory)][string]$TargetPath
  )

  $normalized = Normalize-DocsTargetPath -TargetPath $TargetPath

  $directoryCandidate = Join-Path $DocsRoot $normalized
  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $directoryCandidate
  if (Test-Path -LiteralPath $directoryCandidate -PathType Container) {
    foreach ($candidateName in @("README.md", "README.mdx", "index.md", "index.mdx")) {
      $candidatePath = Join-Path $directoryCandidate $candidateName
      if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        return [pscustomobject]@{
          FullPath     = $candidatePath
          RelativePath = (Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $candidatePath)
        }
      }
    }

    throw "No landing document exists for '$TargetPath'."
  }

  foreach ($extension in @(".md", ".mdx")) {
    $fileCandidate = Join-Path $DocsRoot ($normalized + $extension)
    Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $fileCandidate
    if (Test-Path -LiteralPath $fileCandidate -PathType Leaf) {
      return [pscustomobject]@{
        FullPath     = $fileCandidate
        RelativePath = (Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $fileCandidate)
      }
    }
  }

  $directCandidate = Join-Path $DocsRoot $normalized
  Assert-PathInsideRoot -RootPath $DocsRoot -TargetPath $directCandidate
  if (Test-Path -LiteralPath $directCandidate -PathType Leaf) {
    return [pscustomobject]@{
      FullPath     = $directCandidate
      RelativePath = (Get-RelativeDocPath -DocsRoot $DocsRoot -FullPath $directCandidate)
    }
  }

  throw "Docs page or landing document not found: $TargetPath"
}

function Invoke-DocsVisibility {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $argumentList = @($CommandArguments)
  if ($argumentList.Count -lt 2) {
    throw "Usage: ue-tools docs visibility <TargetPath> <show|hide>. Run 'ue-tools docs help visibility'."
  }
  if ($argumentList.Count -gt 2) {
    throw "Too many arguments for visibility. Usage: ue-tools docs visibility <TargetPath> <show|hide>."
  }

  $mode = ([string]$argumentList[1]).Trim().ToLowerInvariant()
  if ($mode -notin @("show", "hide")) {
    throw "Visibility mode must be 'show' or 'hide'."
  }

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $target = Resolve-DocsVisibilityTarget -DocsRoot $docsRoot -TargetPath $argumentList[0]
  $content = Get-Content -LiteralPath $target.FullPath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')
  $hide = $mode -eq "hide"

  if ($match.Success) {
    $frontMatter = $match.Groups['frontMatter'].Value
    $rest = $match.Groups['rest'].Value
    if ($hide) {
      if ($frontMatter -match '(?mi)^\s*unlisted\s*:') {
        $updatedFrontMatter = [regex]::Replace($frontMatter, '(?mi)^\s*unlisted\s*:\s*.+$', 'unlisted: true', 1)
      }
      else {
        $updatedFrontMatter = if ([string]::IsNullOrWhiteSpace($frontMatter.Trim())) {
          'unlisted: true'
        }
        else {
          $frontMatter.TrimEnd("`r", "`n") + $newline + 'unlisted: true'
        }
      }
    }
    else {
      $updatedFrontMatter = [regex]::Replace($frontMatter, '(?mi)^\s*unlisted\s*:\s*.+(?:\r?\n)?', '')
      $updatedFrontMatter = $updatedFrontMatter.TrimEnd("`r", "`n")
    }

    $updatedContent = if ([string]::IsNullOrWhiteSpace($updatedFrontMatter)) {
      $rest.TrimStart("`r", "`n")
    }
    else {
      "---$newline$updatedFrontMatter$newline---$rest"
    }
    Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $target.FullPath -Content $updatedContent
  }
  elseif ($hide) {
    $updatedContent = @(
      '---'
      'unlisted: true'
      '---'
      ''
      $content.TrimStart("`r", "`n")
    ) -join $newline
    Write-UEToolSuiteUtf8NoBomFile -EnsureParentDirectory -Path $target.FullPath -Content $updatedContent
  }

  return [pscustomobject]@{
    Command = "visibility"
    Target  = $target.RelativePath
    Hidden  = $hide
  }
}

function Invoke-DocsCheck {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $docsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $docFiles = @(Get-MarkdownDocFiles -DocsRoot $docsRoot)
  $slugToFiles = @{}
  $issues = New-Object System.Collections.Generic.List[string]

  foreach ($file in $docFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $frontMatter = Get-FrontMatterBlock -Content $content
    $slug = Get-FrontMatterValue -FrontMatter $frontMatter -Key "slug"

    if (-not [string]::IsNullOrWhiteSpace($slug)) {
      if ($slug.StartsWith("/docs/", [System.StringComparison]::OrdinalIgnoreCase)) {
        $issues.Add("Slug should not start with /docs/: $($file.FullName) -> $slug") | Out-Null
      }

      if (-not $slugToFiles.ContainsKey($slug)) {
        $slugToFiles[$slug] = New-Object System.Collections.Generic.List[string]
      }

      $slugToFiles[$slug].Add($file.FullName) | Out-Null
    }

    if ($content.Contains($script:TocMarker)) {
      $issues.Add("Unprocessed TOC marker remains in: $($file.FullName)") | Out-Null
    }
  }

  foreach ($entry in $slugToFiles.GetEnumerator()) {
    if ($entry.Value.Count -gt 1) {
      $issues.Add("Duplicate slug '$($entry.Key)' used by: $($entry.Value -join ', ')") | Out-Null
    }
  }

  if (-not (Test-Path -LiteralPath $websiteRoot)) {
    throw "website/ directory not found: $websiteRoot"
  }

  if ($issues.Count -gt 0) {
    $message = @("Docs validation failed:") + @($issues | ForEach-Object { " - $_" })
    throw ($message -join [Environment]::NewLine)
  }

  Push-Location $websiteRoot
  try {
    & npm run build
    if ($LASTEXITCODE -ne 0) {
      throw "npm run build failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }

  return [pscustomobject]@{
    Command      = "check"
    FilesChecked = $docFiles.Count
  }
}

function Invoke-WebsiteNpmScript {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [Parameter(Mandatory)][string]$ScriptName,
    [string[]]$ScriptArgs = @()
  )

  $normalizedScriptArgs = @(Get-NormalizedArgumentList -Values $ScriptArgs)
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  Push-Location $websiteRoot
  try {
    $npmArgs = @("run", $ScriptName)
    if ($normalizedScriptArgs.Count -gt 0) {
      $npmArgs += "--"
      $npmArgs += $normalizedScriptArgs
    }

    & npm @npmArgs
    if ($LASTEXITCODE -ne 0) {
      throw "npm run $ScriptName failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }
}

function Get-DocsStartUrl {
  param([string[]]$StartArgs = @())

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Get-UEToolSuiteDocsStartUrl" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Get-UEToolSuiteDocsStartUrl -StartArgs $StartArgs)
  }

  $normalizedStartArgs = @(Get-NormalizedArgumentList -Values $StartArgs)
  $port = 3000
  for ($i = 0; $i -lt $normalizedStartArgs.Count; $i++) {
    $token = [string]$normalizedStartArgs[$i]
    if ($token -match '^--port=(?<port>\d+)$') {
      $parsedEqualsPort = 0
      if ([int]::TryParse($Matches.port, [ref]$parsedEqualsPort)) {
        $port = $parsedEqualsPort
      }
      break
    }

    if ($token -eq "--port" -or $token -eq "-p") {
      if (($i + 1) -lt $normalizedStartArgs.Count) {
        $parsedPort = 0
        if ([int]::TryParse([string]$normalizedStartArgs[$i + 1], [ref]$parsedPort)) {
          $port = $parsedPort
        }
      }
      break
    }
  }

  return "http://localhost:$port/docs/"
}

function Split-DocsStartArguments {
  param([string[]]$StartArgsInput = @())

  [void](Import-UEToolSuiteCoreModule)
  $moduleFn = Get-Command -Name "Split-UEToolSuiteDocsStartArguments" -ErrorAction SilentlyContinue
  if ($moduleFn) {
    return (Split-UEToolSuiteDocsStartArguments -StartArgsInput $StartArgsInput)
  }

  $background = $false
  $passThroughArgs = New-Object System.Collections.Generic.List[string]
  foreach ($token in @(Get-NormalizedArgumentList -Values $StartArgsInput)) {
    $normalized = [string]$token
    if ($normalized -in @("--background", "-background")) {
      $background = $true
      continue
    }

    $passThroughArgs.Add($normalized) | Out-Null
  }

  return [pscustomobject]@{
    Background = $background
    StartArgs  = $passThroughArgs.ToArray()
  }
}

function Get-DocsEditorApiDefaultPort {
  return 38473
}

function Get-DocsEditorApiApplicationId {
  return "UEToolSuiteDocsEditorApi"
}

function Get-DocsEditorApiVersion {
  return 2
}

function Normalize-DocsComparisonPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }

  try {
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
  }
  catch {
    return ([string]$Path).TrimEnd('\', '/')
  }
}

function Get-DocsEditorApiBaseUrl {
  param([int]$Port = 0)

  $resolvedPort = if ($Port -gt 0) { $Port } else { Get-DocsEditorApiDefaultPort }
  return "http://127.0.0.1:$resolvedPort/"
}

function Get-DocsEditorApiPortFromUrl {
  param([string]$Url)

  if ([string]::IsNullOrWhiteSpace($Url)) {
    return 0
  }

  $uri = $null
  if ([System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
    return [int]$uri.Port
  }

  return 0
}

function Invoke-DocsEditorApiHealthProbe {
  param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [string]$ExpectedRepoRoot,
    [string]$ExpectedDocsRoot,
    [int[]]$AllowedProcessIds = @(),
    [int]$TimeoutSeconds = 2
  )

  $apiBaseUrl = if ($ApiUrl.EndsWith('/')) { $ApiUrl } else { "$ApiUrl/" }
  $healthUrl = "$apiBaseUrl" + "health"
  try {
    $payload = Invoke-RestMethod -Uri $healthUrl -Method Get -TimeoutSec $TimeoutSeconds
  }
  catch {
    return [pscustomobject]@{
      Reachable = $false
      Valid     = $false
      Url       = $apiBaseUrl
      HealthUrl = $healthUrl
      Reason    = $_.Exception.Message
    }
  }

  $actualRepoRoot = Normalize-DocsComparisonPath -Path ([string]$payload.repoRoot)
  $actualDocsRoot = Normalize-DocsComparisonPath -Path ([string]$payload.docsRoot)
  $expectedRepoRootNormalized = Normalize-DocsComparisonPath -Path $ExpectedRepoRoot
  $expectedDocsRootNormalized = Normalize-DocsComparisonPath -Path $ExpectedDocsRoot
  $processId = 0
  if ($null -ne $payload.processId) {
    [void][int]::TryParse([string]$payload.processId, [ref]$processId)
  }

  $result = [pscustomobject]@{
    Reachable      = $true
    Valid          = $false
    Url            = $apiBaseUrl
    HealthUrl      = $healthUrl
    ApplicationId  = [string]$payload.applicationId
    ApiVersion     = if ($null -ne $payload.apiVersion) { [int]$payload.apiVersion } else { 0 }
    ProcessId      = $processId
    RepoRoot       = [string]$payload.repoRoot
    DocsRoot       = [string]$payload.docsRoot
    StartedAt      = [string]$payload.startedAt
    ModulePath     = [string]$payload.modulePath
    ScriptPath     = [string]$payload.scriptPath
    Port           = Get-DocsEditorApiPortFromUrl -Url $apiBaseUrl
    Payload        = $payload
    Reason         = ""
  }

  if ($payload.ok -eq $false) {
    $result.Reason = "Health endpoint returned ok=false."
    return $result
  }

  if ($result.ApplicationId -ne (Get-DocsEditorApiApplicationId)) {
    $result.Reason = "Health endpoint did not report the expected application identity."
    return $result
  }

  if ($result.ApiVersion -ne (Get-DocsEditorApiVersion)) {
    $result.Reason = "Health endpoint reported API version $($result.ApiVersion), expected $(Get-DocsEditorApiVersion)."
    return $result
  }

  if ($payload.capabilities.authoringApiVersion -ne (Get-DocsEditorApiVersion)) {
    $result.Reason = "Health endpoint capabilities did not report the expected authoring API version."
    return $result
  }

  if (-not [string]::IsNullOrWhiteSpace($expectedRepoRootNormalized) -and $actualRepoRoot -ne $expectedRepoRootNormalized) {
    $result.Reason = "Health endpoint repo root '$($payload.repoRoot)' does not match '$ExpectedRepoRoot'."
    return $result
  }

  if (-not [string]::IsNullOrWhiteSpace($expectedDocsRootNormalized) -and $actualDocsRoot -ne $expectedDocsRootNormalized) {
    $result.Reason = "Health endpoint docs root '$($payload.docsRoot)' does not match '$ExpectedDocsRoot'."
    return $result
  }

  $expectedProcessIds = @($AllowedProcessIds | Where-Object { $_ -gt 0 } | Select-Object -Unique)
  if ($expectedProcessIds.Count -gt 0 -and ($processId -notin $expectedProcessIds)) {
    $result.Reason = "Health endpoint process ID $processId does not match the tracked runtime process IDs ($($expectedProcessIds -join ', '))."
    return $result
  }

  $result.Valid = $true
  return $result
}

function Wait-DocsEditorApiReady {
  param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [Parameter(Mandatory)][string]$ExpectedRepoRoot,
    [Parameter(Mandatory)][string]$ExpectedDocsRoot,
    [int[]]$AllowedProcessIds = @(),
    [int]$TimeoutMilliseconds = 8000
  )

  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  do {
    $probe = Invoke-DocsEditorApiHealthProbe `
      -ApiUrl $ApiUrl `
      -ExpectedRepoRoot $ExpectedRepoRoot `
      -ExpectedDocsRoot $ExpectedDocsRoot `
      -AllowedProcessIds $AllowedProcessIds
    if ($probe.Valid) {
      return $probe
    }

    Start-Sleep -Milliseconds 200
  }
  while ([DateTime]::UtcNow -lt $deadline)

  return $probe
}

function Test-DocsEditorApiRuntimeStillActive {
  param(
    [Parameter(Mandatory)][string]$ApiUrl,
    [Parameter(Mandatory)][string]$ExpectedRepoRoot,
    [Parameter(Mandatory)][string]$ExpectedDocsRoot,
    [int[]]$TrackedProcessIds = @(),
    [string]$TrackedStartedAt = ""
  )

  $probe = Invoke-DocsEditorApiHealthProbe `
    -ApiUrl $ApiUrl `
    -ExpectedRepoRoot $ExpectedRepoRoot `
    -ExpectedDocsRoot $ExpectedDocsRoot

  if (-not $probe.Valid) {
    return [pscustomobject]@{
      Active = $false
      Probe  = $probe
      Reason = [string]$probe.Reason
    }
  }

  $expectedProcessIds = @($TrackedProcessIds | Where-Object { $_ -gt 0 } | Select-Object -Unique)
  if ($expectedProcessIds.Count -gt 0 -and ($probe.ProcessId -in $expectedProcessIds)) {
    return [pscustomobject]@{
      Active = $true
      Probe  = $probe
      Reason = "Health endpoint still reports tracked runtime process ID $($probe.ProcessId)."
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($TrackedStartedAt) -and [string]$probe.StartedAt -eq $TrackedStartedAt) {
    return [pscustomobject]@{
      Active = $true
      Probe  = $probe
      Reason = "Health endpoint still reports tracked runtime startup time $TrackedStartedAt."
    }
  }

  return [pscustomobject]@{
    Active = $true
    Probe  = $probe
    Reason = "Health endpoint still reports a docs editor API for the same project and docs root."
  }
}

function Resolve-DocsEditorApiPort {
  param([int]$PreferredPort = 0)

  $candidatePorts = New-Object System.Collections.Generic.List[int]
  if ($PreferredPort -gt 0) {
    $candidatePorts.Add($PreferredPort) | Out-Null
  }

  $defaultPort = Get-DocsEditorApiDefaultPort
  if ($defaultPort -gt 0 -and -not $candidatePorts.Contains($defaultPort)) {
    $candidatePorts.Add($defaultPort) | Out-Null
  }

  foreach ($port in $candidatePorts) {
    if (-not (Test-DocsStartPortInUse -Port $port)) {
      return $port
    }
  }

  throw "Docs editor API port conflict: $($candidatePorts -join ', ') is already listening. Stop the existing process or free the configured port before starting docs authoring."
}

function Resolve-DocsPwshPath {
  [CmdletBinding()]
  param()

  $candidatePaths = New-Object System.Collections.Generic.List[string]

  try {
    $currentProcessPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    if (-not [string]::IsNullOrWhiteSpace($currentProcessPath)) {
      $candidatePaths.Add($currentProcessPath) | Out-Null
    }
  }
  catch {
    # no-op
  }

  $psHomePwsh = Join-Path $PSHOME "pwsh.exe"
  if (-not [string]::IsNullOrWhiteSpace($psHomePwsh)) {
    $candidatePaths.Add($psHomePwsh) | Out-Null
  }

  foreach ($commandName in @("pwsh", "powershell")) {
    $resolvedCommand = Get-Command -Name $commandName -ErrorAction SilentlyContinue
    if ($resolvedCommand -and -not [string]::IsNullOrWhiteSpace([string]$resolvedCommand.Source)) {
      $candidatePaths.Add([string]$resolvedCommand.Source) | Out-Null
    }
  }

  foreach ($candidate in @($candidatePaths | Select-Object -Unique)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return $candidate
    }
  }

  throw "Unable to resolve a PowerShell executable path for docs runtime startup."
}

function Get-DocsEditorApiStatus {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $expectedDocsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $entry = Get-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot
  $staleEntryStatus = $null
  $trackedConflictStatus = $null

  if ($null -ne $entry) {
    $processId = [int]$entry.processId
    $rootProcessId = if ($null -ne $entry.rootProcessId) { [int]$entry.rootProcessId } else { $processId }
    $isRunning = (Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)
    if (-not $isRunning) {
      $staleEntryStatus = [pscustomobject]@{
        Status        = "stale_state"
        ProcessId     = $processId
        RootProcessId = $rootProcessId
        Url           = [string]$entry.url
        LogPath       = [string]$entry.logPath
        ErrorLogPath  = [string]$entry.errorLogPath
      }
    }
    else {
      $entryUrl = [string]$entry.url
      $entryPort = if ($null -ne $entry.port) { [int]$entry.port } else { Get-DocsEditorApiPortFromUrl -Url $entryUrl }
      $health = Invoke-DocsEditorApiHealthProbe `
        -ApiUrl $entryUrl `
        -ExpectedRepoRoot $ResolvedRepoRoot `
        -ExpectedDocsRoot $expectedDocsRoot `
        -AllowedProcessIds @($processId, $rootProcessId)
      if ($health.Valid -and $entryPort -eq (Get-DocsEditorApiDefaultPort)) {
        return [pscustomobject]@{
          Status        = "running"
          ProcessId     = $health.ProcessId
          RootProcessId = $rootProcessId
          Url           = $entryUrl
          Port          = $entryPort
          LogPath       = [string]$entry.logPath
          ErrorLogPath  = [string]$entry.errorLogPath
          StartedAt     = [string]$health.StartedAt
          ApplicationId = [string]$health.ApplicationId
          ApiVersion    = [int]$health.ApiVersion
          RepoRoot      = [string]$health.RepoRoot
          DocsRoot      = [string]$health.DocsRoot
          ModulePath    = [string]$health.ModulePath
          ScriptPath    = [string]$health.ScriptPath
        }
      }

      $trackedConflictStatus = [pscustomobject]@{
        Status        = "conflict"
        ProcessId     = $processId
        RootProcessId = $rootProcessId
        Url           = $entryUrl
        Port          = $entryPort
        LogPath       = [string]$entry.logPath
        ErrorLogPath  = [string]$entry.errorLogPath
        StartedAt     = [string]$entry.startedAt
        HealthReason  = if ($health.Valid -and $entryPort -ne (Get-DocsEditorApiDefaultPort)) { "Tracked docs editor API is still running on unsupported port $entryPort." } else { [string]$health.Reason }
      }
    }
  }

  $defaultUrl = Get-DocsEditorApiBaseUrl
  $defaultHealth = Invoke-DocsEditorApiHealthProbe -ApiUrl $defaultUrl -ExpectedRepoRoot $ResolvedRepoRoot -ExpectedDocsRoot $expectedDocsRoot
  if ($defaultHealth.Valid) {
    return [pscustomobject]@{
      Status        = "running_untracked"
      ProcessId     = $defaultHealth.ProcessId
      RootProcessId = $defaultHealth.ProcessId
      Url           = $defaultUrl
      Port          = $defaultHealth.Port
      LogPath       = if ($null -ne $entry) { [string]$entry.logPath } else { "" }
      ErrorLogPath  = if ($null -ne $entry) { [string]$entry.errorLogPath } else { "" }
      StartedAt     = [string]$defaultHealth.StartedAt
      ApplicationId = [string]$defaultHealth.ApplicationId
      ApiVersion    = [int]$defaultHealth.ApiVersion
      RepoRoot      = [string]$defaultHealth.RepoRoot
      DocsRoot      = [string]$defaultHealth.DocsRoot
      ModulePath    = [string]$defaultHealth.ModulePath
      ScriptPath    = [string]$defaultHealth.ScriptPath
    }
  }

  if ($null -ne $trackedConflictStatus) {
    return $trackedConflictStatus
  }

  if ($null -ne $staleEntryStatus) {
    return $staleEntryStatus
  }

  return [pscustomobject]@{
    Status = "not_running"
  }
}

function Start-DocsEditorApiBackground {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [int]$PreferredPort = 0
  )

  $expectedDocsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $existingStatus = Get-DocsEditorApiStatus -ResolvedRepoRoot $ResolvedRepoRoot
  if ($existingStatus.Status -in @("running", "running_untracked")) {
    $entry = [ordered]@{
      version       = 1
      rootProcessId = $existingStatus.RootProcessId
      processId     = $existingStatus.ProcessId
      startedAt     = [string]$existingStatus.StartedAt
      url           = [string]$existingStatus.Url
      port          = if ($null -ne $existingStatus.Port) { [int]$existingStatus.Port } else { Get-DocsEditorApiPortFromUrl -Url ([string]$existingStatus.Url) }
      logPath       = [string]$existingStatus.LogPath
      errorLogPath  = [string]$existingStatus.ErrorLogPath
      scriptPath    = [string]$existingStatus.ScriptPath
      modulePath    = [string]$existingStatus.ModulePath
    }
    [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $entry)
    [void](Write-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot -ApiUrl $existingStatus.Url -Metadata $existingStatus)
    return [pscustomobject]@{
      AlreadyRunning = $true
      ProcessId      = $existingStatus.ProcessId
      RootProcessId  = $existingStatus.RootProcessId
      Url            = $existingStatus.Url
      LogPath        = $existingStatus.LogPath
      ErrorLogPath   = $existingStatus.ErrorLogPath
      StartedAt      = $existingStatus.StartedAt
    }
  }

  if ($existingStatus.Status -eq "stale_state") {
    [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $null)
  }

  if ($existingStatus.Status -eq "conflict") {
    throw ("Docs editor API startup refused because an incompatible tracked runtime is still active at {0}. {1}" -f $existingStatus.Url, $existingStatus.HealthReason)
  }

  $defaultPort = if ($PreferredPort -gt 0) { $PreferredPort } else { Get-DocsEditorApiDefaultPort }
  $defaultUrl = Get-DocsEditorApiBaseUrl -Port $defaultPort
  if (Test-DocsStartPortInUse -Port $defaultPort) {
    $portProbe = Invoke-DocsEditorApiHealthProbe -ApiUrl $defaultUrl -ExpectedRepoRoot $ResolvedRepoRoot -ExpectedDocsRoot $expectedDocsRoot
    if ($portProbe.Valid) {
      [void](Write-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot -ApiUrl $defaultUrl -Metadata $portProbe)
      return [pscustomobject]@{
        AlreadyRunning = $true
        ProcessId      = $portProbe.ProcessId
        RootProcessId  = $portProbe.ProcessId
        Url            = $defaultUrl
        LogPath        = ""
        ErrorLogPath   = ""
        StartedAt      = $portProbe.StartedAt
      }
    }

    throw ("Docs editor API port {0} is already in use by a different or unverified process. {1}" -f $defaultPort, $portProbe.Reason)
  }

  $resolvedPort = Resolve-DocsEditorApiPort -PreferredPort $PreferredPort
  $url = "http://127.0.0.1:$resolvedPort/"
  $runtimeDir = Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

  $scriptPath = Join-Path $PSScriptRoot "DocsEditorApiHost.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "Docs editor API host script not found: $scriptPath"
  }

  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $stdoutPath = Join-Path $runtimeDir "docs-editor-api-$stamp.stdout.log"
  $stderrPath = Join-Path $runtimeDir "docs-editor-api-$stamp.stderr.log"

  $pwshPath = Resolve-DocsPwshPath
  $modulePath = $MyInvocation.MyCommand.Module.Path
  if ([string]::IsNullOrWhiteSpace($modulePath)) {
    $modulePath = $PSCommandPath
  }
  if ([string]::IsNullOrWhiteSpace($modulePath)) {
    throw "Unable to resolve docs module path for editor API startup."
  }
  $commandParts = @(
    (ConvertTo-CmdArgument -Value "-NoLogo")
    (ConvertTo-CmdArgument -Value "-NoProfile")
    (ConvertTo-CmdArgument -Value "-ExecutionPolicy")
    (ConvertTo-CmdArgument -Value "Bypass")
    (ConvertTo-CmdArgument -Value "-File")
    (ConvertTo-CmdArgument -Value $scriptPath)
    (ConvertTo-CmdArgument -Value "-RepoRoot")
    (ConvertTo-CmdArgument -Value $ResolvedRepoRoot)
    (ConvertTo-CmdArgument -Value "-DocsModulePath")
    (ConvertTo-CmdArgument -Value $modulePath)
    (ConvertTo-CmdArgument -Value "-Port")
    (ConvertTo-CmdArgument -Value "$resolvedPort")
  )
  $commandLine = ($commandParts -join ' ')

  $process = Start-Process `
    -FilePath $pwshPath `
    -ArgumentList $commandLine `
    -WorkingDirectory $ResolvedRepoRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

  $trackedProcessId = $null
  $startupDeadline = [DateTime]::UtcNow.AddMilliseconds(8000)
  do {
    if (Test-ProcessRunning -ProcessId $process.Id) {
      $trackedProcessId = $process.Id
    }
    else {
      $trackedProcessId = Get-DescendantProcessId -RootProcessId $process.Id
    }

    if ($null -ne $trackedProcessId) {
      break
    }

    Start-Sleep -Milliseconds 200
  }
  while ([DateTime]::UtcNow -lt $startupDeadline)

  if ($null -eq $trackedProcessId) {
    $errorText = ""
    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
      $errorText = (Get-Content -LiteralPath $stderrPath -Raw).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($errorText) -and (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) {
      $errorText = (Get-Content -LiteralPath $stdoutPath -Raw).Trim()
    }
    $details = if ([string]::IsNullOrWhiteSpace($errorText)) { "Check $stdoutPath and $stderrPath." } else { $errorText }
    throw "Docs editor API exited immediately. $details"
  }

  $readyProbe = Wait-DocsEditorApiReady `
    -ApiUrl $url `
    -ExpectedRepoRoot $ResolvedRepoRoot `
    -ExpectedDocsRoot $expectedDocsRoot `
    -AllowedProcessIds @($trackedProcessId, $process.Id)
  if (-not $readyProbe.Valid) {
    $taskKillPath = Join-Path $env:SystemRoot "System32\taskkill.exe"
    if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
      & $taskKillPath /PID $process.Id /T /F | Out-Null
    }
    else {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }

    $errorText = ""
    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
      $errorText = (Get-Content -LiteralPath $stderrPath -Raw).Trim()
    }
    if ([string]::IsNullOrWhiteSpace($errorText) -and (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) {
      $errorText = (Get-Content -LiteralPath $stdoutPath -Raw).Trim()
    }
    $details = if ([string]::IsNullOrWhiteSpace($errorText)) { $readyProbe.Reason } else { $errorText }
    throw "Docs editor API did not become ready. $details"
  }

  $entry = [ordered]@{
    version       = 1
    rootProcessId = $process.Id
    processId     = $readyProbe.ProcessId
    startedAt     = [string]$readyProbe.StartedAt
    url           = $url
    port          = $resolvedPort
    logPath       = $stdoutPath
    errorLogPath  = $stderrPath
    scriptPath    = $scriptPath
    commandLine   = $commandLine
    modulePath    = [string]$readyProbe.ModulePath
  }
  [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $entry)
  [void](Write-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot -ApiUrl $url -Metadata $readyProbe)

  return [pscustomobject]@{
    AlreadyRunning = $false
    ProcessId      = $readyProbe.ProcessId
    RootProcessId  = $process.Id
    Url            = $url
    LogPath        = $stdoutPath
    ErrorLogPath   = $stderrPath
    StartedAt      = [string]$readyProbe.StartedAt
  }
}

function Stop-DocsEditorApiBackground {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $entry = Get-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot
  if ($null -eq $entry) {
    Remove-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot
    return [pscustomobject]@{
      Status = "not_running"
    }
  }

  $processId = [int]$entry.processId
  $rootProcessId = if ($null -ne $entry.rootProcessId) { [int]$entry.rootProcessId } else { $processId }
  $expectedDocsRoot = Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $entryUrl = [string]$entry.url
  $trackedStartedAt = [string]$entry.startedAt
  $trackedProcessIds = @($processId, $rootProcessId)
  $wasRunning = (Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)

  if ($wasRunning) {
    $targetPid = if (Test-ProcessRunning -ProcessId $rootProcessId) { $rootProcessId } else { $processId }
    $taskKillPath = Join-Path $env:SystemRoot "System32\taskkill.exe"
    if (Test-Path -LiteralPath $taskKillPath -PathType Leaf) {
      & $taskKillPath /PID $targetPid /T /F | Out-Null
    }
    else {
      Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
    }

    $shutdownDeadline = [DateTime]::UtcNow.AddMilliseconds(8000)
    $runtimeStillActive = $null
    do {
      $processStillRunning = (Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)
      $runtimeStillActive = [pscustomobject]@{
        Active = $false
        Reason = ""
      }
      if (-not [string]::IsNullOrWhiteSpace($entryUrl)) {
        $runtimeStillActive = Test-DocsEditorApiRuntimeStillActive `
          -ApiUrl $entryUrl `
          -ExpectedRepoRoot $ResolvedRepoRoot `
          -ExpectedDocsRoot $expectedDocsRoot `
          -TrackedProcessIds $trackedProcessIds `
          -TrackedStartedAt $trackedStartedAt
      }

      if (-not $processStillRunning -and -not $runtimeStillActive.Active) {
        break
      }

      Start-Sleep -Milliseconds 200
    }
    while ([DateTime]::UtcNow -lt $shutdownDeadline)

    $stillRunning = (Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)
    if ($null -eq $runtimeStillActive) {
      $runtimeStillActive = [pscustomobject]@{
        Active = $false
        Reason = ""
      }
    }
    if ($stillRunning -or $runtimeStillActive.Active) {
      $details = if ($runtimeStillActive.Active -and -not [string]::IsNullOrWhiteSpace([string]$runtimeStillActive.Reason)) {
        [string]$runtimeStillActive.Reason
      }
      else {
        "Tracked docs editor API process is still running."
      }

      throw ("Docs editor API shutdown did not complete cleanly for repo '$ResolvedRepoRoot'. Process running: $stillRunning. Runtime active: $($runtimeStillActive.Active). $details")
    }
  }

  [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $null)
  Remove-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot
  return [pscustomobject]@{
    Status        = if ($wasRunning) { "stopped" } else { "stale_state_removed" }
    ProcessId     = $processId
    RootProcessId = $rootProcessId
  }
}

function Invoke-DocsStartForeground {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$StartArgs = @()
  )

  $normalizedStartArgs = @(Get-NormalizedArgumentList -Values $StartArgs)
  $url = Get-DocsStartUrl -StartArgs $normalizedStartArgs
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $editorApi = Start-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot

  Write-Output "Starting docs dev server in the current terminal."
  Write-Output "URL: $url"
  Write-Output "Editor API: $($editorApi.Url)"

  Push-Location $websiteRoot
  try {
    $npmArgs = @("run", "start")
    if ($normalizedStartArgs.Count -gt 0) {
      $npmArgs += "--"
      $npmArgs += $normalizedStartArgs
    }

    & npm @npmArgs
    if ($LASTEXITCODE -ne 0) {
      throw "npm run start failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    if (-not $editorApi.AlreadyRunning) {
      [void](Stop-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot)
    }
    Pop-Location
  }
}

function Invoke-DocsStartBackground {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$StartArgs = @()
  )

  $normalizedStartArgs = @(Get-NormalizedArgumentList -Values $StartArgs)
  $editorApi = Start-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot
  $existingEntries = @(Get-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot)
  $runningEntries = New-Object System.Collections.Generic.List[object]
  foreach ($entry in $existingEntries) {
    $processId = [int]$entry.processId
    $rootProcessId = if ($null -ne $entry.rootProcessId) { [int]$entry.rootProcessId } else { $processId }
    if ((Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)) {
      [void]$runningEntries.Add($entry)
    }
  }

  if ($runningEntries.Count -ne $existingEntries.Count) {
    [void](Save-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot -Entries @($runningEntries.ToArray()))
  }

  $requestedPort = Get-DocsStartPort -StartArgs $normalizedStartArgs
  $requestedPortInUse = Test-DocsStartPortInUse -Port $requestedPort

  if ($runningEntries.Count -gt 0) {
    $existingPrimary = $runningEntries[0]
    return [pscustomobject]@{
      Command               = "start-background"
      AlreadyRunning        = $true
      ProcessId             = [int]$existingPrimary.processId
      RootProcessId         = if ($null -ne $existingPrimary.rootProcessId) { [int]$existingPrimary.rootProcessId } else { [int]$existingPrimary.processId }
      LogPath               = [string]$existingPrimary.logPath
      ErrorLogPath          = [string]$existingPrimary.errorLogPath
      StatePath             = Get-DocsServerStatePath -ResolvedRepoRoot $ResolvedRepoRoot
      Url                   = [string]$existingPrimary.url
      EditorApiUrl          = $editorApi.Url
      EditorApiLogPath      = $editorApi.LogPath
      EditorApiErrorLogPath = $editorApi.ErrorLogPath
      TrackedServerCount    = $runningEntries.Count
    }
  }

  if ($requestedPortInUse) {
    if ($runningEntries.Count -gt 0) {
      Write-Output "Warning: $($runningEntries.Count) tracked background docs server instance(s) are already running."
      foreach ($entry in @($runningEntries.ToArray())) {
        Write-Output ("  - PID {0} URL {1}" -f [int]$entry.processId, [string]$entry.url)
      }
    }
    if ($requestedPortInUse) {
      if (-not $editorApi.AlreadyRunning) {
        [void](Stop-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot)
      }
      throw "Docs start port $requestedPort is already in use. Stop the existing docs dev server or choose a different port."
    }
  }

  $runtimeDir = Get-DocsToolsRuntimeDirectory -ResolvedRepoRoot $ResolvedRepoRoot
  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $stdoutPath = Join-Path $runtimeDir "docs-start-$stamp.stdout.log"
  $stderrPath = Join-Path $runtimeDir "docs-start-$stamp.stderr.log"

  $npmCommandParts = @("npm", "run", "start")
  if ($normalizedStartArgs.Count -gt 0) {
    $npmCommandParts += "--"
    $npmCommandParts += $normalizedStartArgs
  }

  $commandLine = (@($npmCommandParts) | ForEach-Object { ConvertTo-CmdArgument "$_" }) -join ' '
  $pwshPath = Resolve-DocsPwshPath
  $process = Start-Process `
    -FilePath $pwshPath `
    -ArgumentList @("-NoLogo", "-NoProfile", "-Command", $commandLine) `
    -WorkingDirectory $websiteRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

  Start-Sleep -Seconds 2
  $trackedProcessId = if (Test-ProcessRunning -ProcessId $process.Id) { $process.Id } else { Get-DescendantProcessId -RootProcessId $process.Id }
  if ($null -eq $trackedProcessId) {
    $errorText = ""
    if (Test-Path -LiteralPath $stderrPath) {
      $errorText = (Get-Content -LiteralPath $stderrPath -Raw).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($errorText) -and (Test-Path -LiteralPath $stdoutPath)) {
      $errorText = (Get-Content -LiteralPath $stdoutPath -Raw).Trim()
    }

    $details = if ([string]::IsNullOrWhiteSpace($errorText)) { "Check $stdoutPath and $stderrPath." } else { $errorText }
    if (-not $editorApi.AlreadyRunning) {
      [void](Stop-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot)
    }
    throw "Docs dev server exited immediately. $details"
  }

  $url = Get-DocsStartUrl -StartArgs $normalizedStartArgs
  $entry = [ordered]@{
    version       = 1
    rootProcessId = $process.Id
    processId     = $trackedProcessId
    startedAt     = (Get-Date).ToString("o")
    websiteRoot   = $websiteRoot
    logPath       = $stdoutPath
    errorLogPath  = $stderrPath
    url           = $url
    commandLine   = $commandLine
    args          = $normalizedStartArgs
  }

  $updatedEntries = @($runningEntries.ToArray()) + @($entry)
  $statePath = Save-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot -Entries $updatedEntries

  return [pscustomobject]@{
    Command               = "start-background"
    AlreadyRunning        = $false
    ProcessId             = $trackedProcessId
    RootProcessId         = $process.Id
    LogPath               = $stdoutPath
    ErrorLogPath          = $stderrPath
    StatePath             = $statePath
    Url                   = $url
    EditorApiUrl          = $editorApi.Url
    EditorApiLogPath      = $editorApi.LogPath
    EditorApiErrorLogPath = $editorApi.ErrorLogPath
    NpmCommandLine        = $commandLine
    TrackedServerCount    = $updatedEntries.Count
  }
}

function Invoke-DocsStop {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $entries = @(Get-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot)
  $editorStopResult = $null

  if ($entries.Count -eq 0) {
    $editorStopResult = Stop-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot
    if ($editorStopResult.Status -ne "not_running") {
      return [pscustomobject]@{
        Command      = "stop"
        Status       = "editor_only_stopped"
        EditorStatus = $editorStopResult.Status
      }
    }
    return [pscustomobject]@{
      Command = "stop"
      Status  = "not_running"
    }
  }

  $stoppedCount = 0
  $staleCount = 0
  $firstProcessId = $null

  foreach ($entry in $entries) {
    $processId = [int]$entry.processId
    $rootProcessId = if ($null -ne $entry.rootProcessId) { [int]$entry.rootProcessId } else { $processId }
    if ($null -eq $firstProcessId) {
      $firstProcessId = $processId
    }

    if (-not (Test-ProcessRunning -ProcessId $processId) -and -not (Test-ProcessRunning -ProcessId $rootProcessId)) {
      $staleCount += 1
      continue
    }

    $targetPid = if (Test-ProcessRunning -ProcessId $rootProcessId) { $rootProcessId } else { $processId }
    $taskKillPath = Join-Path $env:SystemRoot "System32\taskkill.exe"
    if (Test-Path -LiteralPath $taskKillPath) {
      & $taskKillPath /PID $targetPid /T /F | Out-Null
    }
    else {
      Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Milliseconds 750
    if (Test-ProcessRunning -ProcessId $processId) {
      Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
    if (Test-ProcessRunning -ProcessId $rootProcessId) {
      Stop-Process -Id $rootProcessId -Force -ErrorAction SilentlyContinue
    }

    $stoppedCount += 1
  }

  $editorStopResult = Stop-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot
  [void](Save-DocsServerCompositeState -ResolvedRepoRoot $ResolvedRepoRoot -ServerEntries @() -EditorApiEntry $null)

  $status = if ($stoppedCount -gt 0) {
    if ($stoppedCount -gt 1) { "stopped_multiple" } else { "stopped" }
  }
  else {
    if ($staleCount -gt 1) { "stale_state_removed_multiple" } else { "stale_state_removed" }
  }

  return [pscustomobject]@{
    Command      = "stop"
    Status       = $status
    ProcessId    = $firstProcessId
    StoppedCount = $stoppedCount
    StaleCount   = $staleCount
    EditorStatus = if ($null -ne $editorStopResult) { $editorStopResult.Status } else { "not_running" }
  }
}

function Invoke-DocsStatus {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $editorStatus = Get-DocsEditorApiStatus -ResolvedRepoRoot $ResolvedRepoRoot
  $entries = @(Get-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot)
  if ($entries.Count -eq 0) {
    if ($editorStatus.Status -eq "stale_state") {
      [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $null)
      Remove-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot
      $editorStatus = Get-DocsEditorApiStatus -ResolvedRepoRoot $ResolvedRepoRoot
    }

    if ($editorStatus.Status -in @("running", "running_untracked")) {
      [void](Write-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot -ApiUrl $editorStatus.Url -Metadata $editorStatus)
    }

    return [pscustomobject]@{
      Command            = "status"
      Status             = if ($editorStatus.Status -in @("running", "running_untracked")) { "editor_running_only" } elseif ($editorStatus.Status -eq "conflict") { "editor_conflict_only" } else { "not_running" }
      EditorStatus       = $editorStatus.Status
      EditorUrl          = $editorStatus.Url
      EditorLogPath      = $editorStatus.LogPath
      EditorErrorLogPath = $editorStatus.ErrorLogPath
      EditorHealthReason = $editorStatus.HealthReason
    }
  }

  $runningEntries = New-Object System.Collections.Generic.List[object]
  $staleEntries = New-Object System.Collections.Generic.List[object]
  foreach ($entry in $entries) {
    $processId = [int]$entry.processId
    $rootProcessId = if ($null -ne $entry.rootProcessId) { [int]$entry.rootProcessId } else { $processId }
    $isRunning = (Test-ProcessRunning -ProcessId $processId) -or (Test-ProcessRunning -ProcessId $rootProcessId)
    if ($isRunning) {
      [void]$runningEntries.Add($entry)
    }
    else {
      [void]$staleEntries.Add($entry)
    }
  }

  if ($staleEntries.Count -gt 0 -and $runningEntries.Count -gt 0) {
    [void](Save-DocsServerEntries -ResolvedRepoRoot $ResolvedRepoRoot -Entries @($runningEntries.ToArray()))
  }

  if ($runningEntries.Count -eq 0) {
    $firstStale = $staleEntries[0]
    $processId = [int]$firstStale.processId
    $rootProcessId = if ($null -ne $firstStale.rootProcessId) { [int]$firstStale.rootProcessId } else { $processId }
    if ($editorStatus.Status -eq "stale_state") {
      [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $null)
      Remove-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot
      $editorStatus = Get-DocsEditorApiStatus -ResolvedRepoRoot $ResolvedRepoRoot
    }
    if ($editorStatus.Status -in @("running", "running_untracked")) {
      [void](Write-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot -ApiUrl $editorStatus.Url -Metadata $editorStatus)
    }
    return [pscustomobject]@{
      Command            = "status"
      Status             = if ($staleEntries.Count -gt 1) { "stale_state_multiple" } else { "stale_state" }
      ProcessId          = $processId
      RootProcessId      = $rootProcessId
      LogPath            = [string]$firstStale.logPath
      ErrorLogPath       = [string]$firstStale.errorLogPath
      Url                = [string]$firstStale.url
      StaleCount         = $staleEntries.Count
      EditorStatus       = $editorStatus.Status
      EditorUrl          = $editorStatus.Url
      EditorLogPath      = $editorStatus.LogPath
      EditorErrorLogPath = $editorStatus.ErrorLogPath
    }
  }

  $firstRunning = $runningEntries[0]
  $processId = [int]$firstRunning.processId
  $rootProcessId = if ($null -ne $firstRunning.rootProcessId) { [int]$firstRunning.rootProcessId } else { $processId }
  if ($editorStatus.Status -eq "stale_state") {
    [void](Save-DocsEditorApiEntry -ResolvedRepoRoot $ResolvedRepoRoot -Entry $null)
    $editorStatus = Start-DocsEditorApiBackground -ResolvedRepoRoot $ResolvedRepoRoot
    $editorStatus = Get-DocsEditorApiStatus -ResolvedRepoRoot $ResolvedRepoRoot
  }
  if ($editorStatus.Status -in @("running", "running_untracked")) {
    [void](Write-DocsEditorRuntimeConfig -ResolvedRepoRoot $ResolvedRepoRoot -ApiUrl $editorStatus.Url -Metadata $editorStatus)
  }

  return [pscustomobject]@{
    Command            = "status"
    Status             = if ($runningEntries.Count -gt 1) { "running_multiple" } else { "running" }
    ProcessId          = $processId
    RootProcessId      = $rootProcessId
    LogPath            = [string]$firstRunning.logPath
    ErrorLogPath       = [string]$firstRunning.errorLogPath
    Url                = [string]$firstRunning.url
    StartedAt          = [string]$firstRunning.startedAt
    Args               = @($firstRunning.args)
    RunningCount       = $runningEntries.Count
    StaleCount         = $staleEntries.Count
    RunningEntries     = @($runningEntries.ToArray())
    EditorStatus       = $editorStatus.Status
    EditorUrl          = $editorStatus.Url
    EditorLogPath      = $editorStatus.LogPath
    EditorErrorLogPath = $editorStatus.ErrorLogPath
  }
}

function Invoke-DocsDoctor {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $websiteRoot = Get-WebsiteRoot -ResolvedRepoRoot $ResolvedRepoRoot
  $bridgeStatus = Get-BridgeStatus
  $status = Invoke-DocsStatus -ResolvedRepoRoot $ResolvedRepoRoot
  $migrationPlan = Invoke-DocsSectionMigration -ResolvedRepoRoot $ResolvedRepoRoot -WhatIf

  return [pscustomobject]@{
    Command                   = "doctor"
    RepoRoot                  = $ResolvedRepoRoot
    WebsiteRoot               = $websiteRoot
    DocsRoot                  = (Get-DocsRoot -ResolvedRepoRoot $ResolvedRepoRoot)
    NodeInstalled             = (Test-CommandAvailable -Name "node")
    NpmInstalled              = (Test-CommandAvailable -Name "npm")
    NodeModulesPresent        = (Test-Path -LiteralPath (Join-Path $websiteRoot "node_modules"))
    CodeCliFound              = (-not [string]::IsNullOrWhiteSpace($bridgeStatus.CodeCliPath))
    CodeCliPath               = $bridgeStatus.CodeCliPath
    MarkdownAllInOneInstalled = $bridgeStatus.MarkdownAllInOneInstalled
    BridgeInstalled           = $bridgeStatus.BridgeInstalled
    TocReady                  = $bridgeStatus.TocReady
    ServerStatus              = $status.Status
    ServerUrl                 = $status.Url
    ServerLogPath             = $status.LogPath
    ServerErrorLogPath        = $status.ErrorLogPath
    EditorStatus              = $status.EditorStatus
    EditorApiUrl              = $status.EditorUrl
    EditorApiLogPath          = $status.EditorLogPath
    EditorApiErrorLogPath     = $status.EditorErrorLogPath
    SectionMigration          = $migrationPlan
  }
}

function Invoke-DocsMigrateSections {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments = @()
  )

  $parsed = Parse-SubcommandArguments `
    -CommandArguments $CommandArguments `
    -SwitchNames @("whatif", "what-if")

  if ($parsed.Positionals.Count -gt 0) {
    throw "migrate-sections does not accept positional arguments. Usage: ue-tools docs migrate-sections [--what-if]."
  }

  $whatIf = ($parsed.Switches.ContainsKey("whatif") -or $parsed.Switches.ContainsKey("what-if"))
  return (Invoke-DocsSectionMigration -ResolvedRepoRoot $ResolvedRepoRoot -WhatIf:$whatIf)
}

function Write-DocsToolsError {
  param([Parameter(Mandatory)][string]$Message)

  $formatted = "Error: $Message"
  Write-Host $formatted -ForegroundColor Red
}

function Invoke-InstallBridge {
  param([Parameter(Mandatory)][string]$ResolvedRepoRoot)

  $bridgeSource = Join-Path $script:DocsToolsScriptsRoot "Docs\\VSCodeBridge"
  $packagePath = Join-Path $bridgeSource "package.json"
  if (-not (Test-Path -LiteralPath $packagePath)) {
    throw "VS Code bridge package.json not found: $packagePath"
  }

  $packageJson = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
  $publisher = [string]$packageJson.publisher
  $name = [string]$packageJson.name
  $version = [string]$packageJson.version
  if ([string]::IsNullOrWhiteSpace($publisher) -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) {
    throw "Bridge package.json is missing publisher, name, or version."
  }

  $extensionsRoot = Join-Path $env:USERPROFILE ".vscode\extensions"
  New-Item -ItemType Directory -Force -Path $extensionsRoot | Out-Null

  $prefix = "$publisher.$name-"
  Get-ChildItem -LiteralPath $extensionsRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "$prefix*" } |
  ForEach-Object {
    $resolved = $_.FullName
    if ($resolved.StartsWith($extensionsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolved -Recurse -Force
    }
  }

  $destination = Join-Path $extensionsRoot "$publisher.$name-$version"
  Copy-Item -LiteralPath $bridgeSource -Destination $destination -Recurse -Force

  return [pscustomobject]@{
    Command                   = "install-bridge"
    Destination               = $destination
    MarkdownAllInOneInstalled = (Test-VSCodeExtensionInstalled -ExtensionId $script:MarkdownAllInOneExtensionId)
  }
}

function Invoke-DocsToolsMain {
  param(
    [Parameter(Mandatory)][string]$ResolvedRepoRoot,
    [string[]]$CommandArguments
  )

  $allArgs = @(Get-NormalizedArgumentList -Values $CommandArguments)
  if ($allArgs.Count -eq 0) {
    Write-Output (Get-DocsToolsRootHelp)
    return
  }

  if (Test-DocsToolsHelpToken -Token ([string]$allArgs[0])) {
    if ($allArgs.Count -gt 1) {
      Write-Output (Get-DocsToolsCommandHelp -CommandName $allArgs[1])
    }
    else {
      Write-Output (Get-DocsToolsRootHelp)
    }
    return
  }

  $command = Resolve-DocsToolsCommandAlias -CommandName ([string]$allArgs[0])

  $remaining = if ($allArgs.Count -gt 1) { @(Get-NormalizedArgumentTail -Values $allArgs -Skip 1) } else { @() }
  if ($remaining.Count -gt 0 -and (Test-DocsToolsHelpToken -Token ([string]$remaining[0]))) {
    Write-Output (Get-DocsToolsCommandHelp -CommandName $command)
    return
  }

  switch ($command) {
    "new-section" {
      $newSectionParameters = @{ ResolvedRepoRoot = $ResolvedRepoRoot }
      if ($remaining.Count -gt 0) {
        $newSectionParameters.CommandArguments = @($remaining)
      }

      $result = Invoke-NewSection @newSectionParameters
      Write-Output "Created section: $($result.Path)"
      Write-Output "Category metadata: $($result.CategoryPath)"
      if ($result.TocQueued) { Write-Output "TOC request queued through the VS Code bridge." }
      else { Write-Output "TOC generation skipped." }
      return
    }
    "new-page" {
      $newPageParameters = @{ ResolvedRepoRoot = $ResolvedRepoRoot }
      if ($remaining.Count -gt 0) {
        $newPageParameters.CommandArguments = @($remaining)
      }

      $result = Invoke-NewPage @newPageParameters
      Write-Output "Created page: $($result.Path)"
      if ($result.TocQueued) { Write-Output "TOC request queued through the VS Code bridge." }
      else { Write-Output "TOC generation skipped." }
      return
    }
    "reorder" {
      $reorderParameters = @{ ResolvedRepoRoot = $ResolvedRepoRoot }
      if ($remaining.Count -gt 0) {
        $reorderParameters.CommandArguments = @($remaining)
      }

      $result = Invoke-DocsReorder @reorderParameters
      if ($result.UpdatedCount -eq 0) {
        Write-Output "No reorder needed. '$($result.Target)' is already at position $($result.NewPosition)."
      }
      else {
        Write-Output "Reordered '$($result.Target)' from $($result.OldPosition) to $($result.NewPosition)."
        Write-Output "Updated items: $($result.UpdatedCount)"
      }
      return
    }
    "migrate-sections" {
      $result = Invoke-DocsMigrateSections -ResolvedRepoRoot $ResolvedRepoRoot -CommandArguments $remaining
      if ($result.WhatIf) {
        if ($result.PlannedFiles.Count -eq 0) {
          Write-Output "No legacy docs sections require migration."
        }
        else {
          foreach ($plannedFile in @($result.PlannedFiles)) {
            Write-Output ("Would normalize '{0}' -> label='{1}', position={2}" -f [string]$plannedFile.RelativePath, [string]$plannedFile.Label, [string]$plannedFile.Position)
          }
        }
        return
      }

      if ($result.CreatedFiles.Count -eq 0) {
        Write-Output "No legacy docs sections require migration."
      }
      else {
        foreach ($plannedFile in @($result.PlannedFiles)) {
          Write-Output ("Normalized '{0}' -> label='{1}', position={2}" -f [string]$plannedFile.RelativePath, [string]$plannedFile.Label, [string]$plannedFile.Position)
        }
        Write-Output "Created metadata files: $($result.CreatedFiles.Count)"
      }
      return
    }
    "visibility" {
      $result = Invoke-DocsVisibility -ResolvedRepoRoot $ResolvedRepoRoot -CommandArguments $remaining
      if ($result.Hidden) {
        Write-Output "Hidden '$($result.Target)' from site navigation."
      }
      else {
        Write-Output "Showed '$($result.Target)' in site navigation."
      }
      return
    }
    "theme" {
      Invoke-DocsThemeCommand -ResolvedRepoRoot $ResolvedRepoRoot -CommandArguments $remaining
      return
    }
    "site" {
      Invoke-DocsSiteCommand -ResolvedRepoRoot $ResolvedRepoRoot -CommandArguments $remaining
      return
    }
    "preview" {
      Write-Output "preview is deprecated. Use 'ue-tools docs start' or 'ue-tools docs start --background'."
      if ($remaining.Count -gt 0) {
        $previewMode = Split-DocsStartArguments -StartArgsInput $remaining
      }
      else {
        $previewMode = Split-DocsStartArguments
      }
      $result = Invoke-DocsStartBackground -ResolvedRepoRoot $ResolvedRepoRoot -StartArgs $previewMode.StartArgs
      if ($result.AlreadyRunning) {
        Write-Output "Docs dev server is already running (PID $($result.ProcessId))."
      }
      else {
        Write-Output "Started docs dev server in the background (PID $($result.ProcessId))."
      }
      Write-Output "URL: $($result.Url)"
      if (-not [string]::IsNullOrWhiteSpace([string]$result.NpmCommandLine)) {
        Write-Output "Command: $($result.NpmCommandLine)"
      }
      Write-Output "Stdout log: $($result.LogPath)"
      Write-Output "Stderr log: $($result.ErrorLogPath)"
      if ($result.EditorApiUrl) {
        Write-Output "Editor API: $($result.EditorApiUrl)"
        Write-Output "Inline editing is available directly on docs pages."
      }
      return
    }
    "start" {
      if ($remaining.Count -gt 0) {
        $startMode = Split-DocsStartArguments -StartArgsInput $remaining
      }
      else {
        $startMode = Split-DocsStartArguments
      }
      if ($startMode.Background) {
        $result = Invoke-DocsStartBackground -ResolvedRepoRoot $ResolvedRepoRoot -StartArgs $startMode.StartArgs
        if ($result.Aborted) {
          Write-Output "Docs dev server start aborted."
          if ($result.ExistingCount -gt 0) {
            Write-Output "Tracked running docs server count: $($result.ExistingCount)"
          }
          return
        }
        elseif ($result.AlreadyRunning) {
          Write-Output "Docs dev server is already running (PID $($result.ProcessId))."
        }
        else {
          Write-Output "Started docs dev server in the background (PID $($result.ProcessId))."
        }
        Write-Output "URL: $($result.Url)"
        if (-not [string]::IsNullOrWhiteSpace([string]$result.NpmCommandLine)) {
          Write-Output "Command: $($result.NpmCommandLine)"
        }
        Write-Output "Stdout log: $($result.LogPath)"
        Write-Output "Stderr log: $($result.ErrorLogPath)"
        if ($result.EditorApiUrl) {
          Write-Output "Editor API: $($result.EditorApiUrl)"
          Write-Output "Inline editing is available directly on docs pages."
          if (-not [string]::IsNullOrWhiteSpace([string]$result.EditorApiLogPath)) {
            Write-Output "Editor stdout log: $($result.EditorApiLogPath)"
          }
          if (-not [string]::IsNullOrWhiteSpace([string]$result.EditorApiErrorLogPath)) {
            Write-Output "Editor stderr log: $($result.EditorApiErrorLogPath)"
          }
        }
        return
      }

      Invoke-DocsStartForeground -ResolvedRepoRoot $ResolvedRepoRoot -StartArgs $startMode.StartArgs
      return
    }
    "stop" {
      $result = Invoke-DocsStop -ResolvedRepoRoot $ResolvedRepoRoot
      switch ($result.Status) {
        "not_running" { Write-Output "Tracked background docs dev server is not running." }
        "editor_only_stopped" { Write-Output "Stopped docs editor API runtime." }
        "stale_state_removed" { Write-Output "Removed stale background docs dev server state for PID $($result.ProcessId)." }
        "stale_state_removed_multiple" { Write-Output "Removed stale background docs dev server state entries ($($result.StaleCount))." }
        "stopped_multiple" { Write-Output "Stopped background docs dev servers ($($result.StoppedCount))." }
        default { Write-Output "Stopped background docs dev server (PID $($result.ProcessId))." }
      }
      if ($result.EditorStatus) {
        Write-Output "Editor API status: $($result.EditorStatus)"
      }
      return
    }
    "status" {
      $result = Invoke-DocsStatus -ResolvedRepoRoot $ResolvedRepoRoot
      switch ($result.Status) {
        "not_running" { Write-Output "Tracked background docs dev server is not running." }
        "editor_running_only" {
          Write-Output "Docs server is not running, but editor API is active."
          if ($result.EditorUrl) {
            Write-Output "Editor API: $($result.EditorUrl)"
          }
          if ($result.EditorLogPath) {
            Write-Output "Editor stdout log: $($result.EditorLogPath)"
          }
          if ($result.EditorErrorLogPath) {
            Write-Output "Editor stderr log: $($result.EditorErrorLogPath)"
          }
        }
        "editor_conflict_only" {
          Write-Output "Docs server is not running, but a conflicting tracked editor API runtime still exists."
          if ($result.EditorUrl) {
            Write-Output "Editor API: $($result.EditorUrl)"
          }
          if ($result.EditorHealthReason) {
            Write-Output "Editor API issue: $($result.EditorHealthReason)"
          }
          if ($result.EditorLogPath) {
            Write-Output "Editor stdout log: $($result.EditorLogPath)"
          }
          if ($result.EditorErrorLogPath) {
            Write-Output "Editor stderr log: $($result.EditorErrorLogPath)"
          }
        }
        "stale_state" {
          Write-Output "Background docs dev server is not running, but stale state still exists for PID $($result.ProcessId)."
          Write-Output "URL: $($result.Url)"
          Write-Output "Stdout log: $($result.LogPath)"
          Write-Output "Stderr log: $($result.ErrorLogPath)"
        }
        "stale_state_multiple" {
          Write-Output "Background docs dev servers are not running, but stale state entries still exist ($($result.StaleCount))."
          Write-Output "Example URL: $($result.Url)"
          Write-Output "Example stdout log: $($result.LogPath)"
          Write-Output "Example stderr log: $($result.ErrorLogPath)"
        }
        "running_multiple" {
          Write-Output "Background docs dev servers are running ($($result.RunningCount) tracked instances)."
          Write-Output "Primary PID: $($result.ProcessId)"
          Write-Output "URL: $($result.Url)"
          Write-Output "Started: $($result.StartedAt)"
          Write-Output "Stdout log: $($result.LogPath)"
          Write-Output "Stderr log: $($result.ErrorLogPath)"
        }
        default {
          Write-Output "Background docs dev server is running (PID $($result.ProcessId))."
          Write-Output "URL: $($result.Url)"
          Write-Output "Started: $($result.StartedAt)"
          Write-Output "Stdout log: $($result.LogPath)"
          Write-Output "Stderr log: $($result.ErrorLogPath)"
        }
      }
      if ($result.EditorStatus) {
        Write-Output "Editor API status: $($result.EditorStatus)"
        if ($result.EditorUrl) {
          Write-Output "Editor API: $($result.EditorUrl)"
        }
        if ($result.EditorLogPath) {
          Write-Output "Editor stdout log: $($result.EditorLogPath)"
        }
        if ($result.EditorErrorLogPath) {
          Write-Output "Editor stderr log: $($result.EditorErrorLogPath)"
        }
      }
      return
    }
    "check" {
      $result = Invoke-DocsCheck -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output "Docs check passed. Files checked: $($result.FilesChecked)"
      return
    }
    "doctor" {
      $result = Invoke-DocsDoctor -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output "Repo root: $($result.RepoRoot)"
      Write-Output "Website root: $($result.WebsiteRoot)"
      Write-Output "Node installed: $($result.NodeInstalled)"
      Write-Output "npm installed: $($result.NpmInstalled)"
      Write-Output "website/node_modules present: $($result.NodeModulesPresent)"
      Write-Output "VS Code CLI found: $($result.CodeCliFound)"
      if ($result.CodeCliFound) {
        Write-Output "VS Code CLI path: $($result.CodeCliPath)"
      }
      Write-Output "Markdown All in One installed: $($result.MarkdownAllInOneInstalled)"
      Write-Output "Docs bridge installed: $($result.BridgeInstalled)"
      Write-Output "TOC automation ready: $($result.TocReady)"
      Write-Output "Background docs dev server status: $($result.ServerStatus)"
      if ($result.ServerUrl) {
        Write-Output "Background docs dev server URL: $($result.ServerUrl)"
      }
      if ($result.ServerLogPath) {
        Write-Output "Background docs dev server stdout log: $($result.ServerLogPath)"
      }
      if ($result.ServerErrorLogPath) {
        Write-Output "Background docs dev server stderr log: $($result.ServerErrorLogPath)"
      }
      Write-Output "Editor API status: $($result.EditorStatus)"
      if ($result.EditorApiUrl) {
        Write-Output "Editor API URL: $($result.EditorApiUrl)"
      }
      if ($result.EditorApiLogPath) {
        Write-Output "Editor API stdout log: $($result.EditorApiLogPath)"
      }
      if ($result.EditorApiErrorLogPath) {
        Write-Output "Editor API stderr log: $($result.EditorApiErrorLogPath)"
      }
      $migrationPlan = $result.SectionMigration
      Write-Output "Legacy docs sections requiring migration: $(@($migrationPlan.DetectedLegacySections).Count)"
      foreach ($legacySection in @($migrationPlan.DetectedLegacySections)) {
        $planned = @($migrationPlan.PlannedFiles | Where-Object { ([string]$_.RelativePath).Equals([string]$legacySection.RelativePath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($null -ne $planned) {
          Write-Output ("WARN legacy section: {0} -> planned label='{1}', position={2}" -f [string]$legacySection.RelativePath, [string]$planned.Label, [string]$planned.Position)
        }
        else {
          Write-Output ("WARN legacy section: {0}" -f [string]$legacySection.RelativePath)
        }
      }
      foreach ($skippedEntry in @($migrationPlan.SkippedEntries)) {
        Write-Output ("INFO {0}: {1} ({2})" -f [string]$skippedEntry.Kind, [string]$skippedEntry.RelativePath, [string]$skippedEntry.Reason)
      }
      if (@($migrationPlan.DetectedLegacySections).Count -gt 0) {
        Write-Output "Remediation: ue-tools docs migrate-sections"
      }
      return
    }
    "install-bridge" {
      $result = Invoke-InstallBridge -ResolvedRepoRoot $ResolvedRepoRoot
      Write-Output "Installed VS Code bridge to: $($result.Destination)"
      if ($result.MarkdownAllInOneInstalled) {
        Write-Output "Markdown All in One is already installed."
      }
      else {
        Write-Output "Markdown All in One is not installed. TOC generation will still be skipped until it is present."
      }
      Write-Output "Reload VS Code windows to activate the bridge."
      return
    }
    default {
      $packageScripts = @(Get-WebsitePackageScriptNames -ResolvedRepoRoot $ResolvedRepoRoot)
      if ($packageScripts -contains $command) {
        if ($remaining.Count -gt 0) {
          Invoke-WebsiteNpmScript -ResolvedRepoRoot $ResolvedRepoRoot -ScriptName $command -ScriptArgs $remaining
        }
        else {
          Invoke-WebsiteNpmScript -ResolvedRepoRoot $ResolvedRepoRoot -ScriptName $command
        }
        return
      }

      throw "Unknown ue-tools docs command '$command'. Run 'ue-tools docs help'."
    }
  }
}

Export-ModuleMember -Function Get-DocsToolsRepoRoot, Invoke-DocsToolsMain, Invoke-DocsSectionMigration
