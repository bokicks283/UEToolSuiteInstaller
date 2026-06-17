[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RepoRoot,
  [Parameter(Mandatory)][string]$DocsModulePath,
  [int]$Port = 38473
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DocsModulePath -PathType Leaf)) {
  throw "Docs module path not found: $DocsModulePath"
}

$script:DocsModule = Import-Module -Name $DocsModulePath -Force -DisableNameChecking -PassThru
$coreModulePath = Join-Path (Split-Path -Parent $DocsModulePath) "UEToolSuite.Core.psm1"
if (Test-Path -LiteralPath $coreModulePath -PathType Leaf) {
  Import-Module -Name $coreModulePath -Force -DisableNameChecking | Out-Null
  if (Get-Command -Name "Set-UEToolSuiteRuntimeContext" -CommandType Function -ErrorAction SilentlyContinue) {
    $scriptsRoot = Split-Path -Parent (Split-Path -Parent $DocsModulePath)
    Set-UEToolSuiteRuntimeContext -ScriptsRoot $scriptsRoot -StateKey "docs-editor-api" -LogPrefix "[Docs]"
  }
}
$script:RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$script:DocsRoot = (& $script:DocsModule { param($resolvedRepoRoot) Get-DocsRoot -ResolvedRepoRoot $resolvedRepoRoot } $script:RepoRoot)

if (-not (Test-Path -LiteralPath $script:DocsRoot -PathType Container)) {
  throw "Docs root not found: $($script:DocsRoot)"
}

function Invoke-DocsModuleInternal {
  param(
    [Parameter(Mandatory)][scriptblock]$ScriptBlock,
    [AllowEmptyCollection()][object[]]$Arguments = @()
  )

  return (& $script:DocsModule $ScriptBlock @Arguments)
}

function Get-JsonHash {
  param([AllowEmptyString()][string]$Value)

  if ($null -eq $Value) {
    $Value = ""
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
  }
  finally {
    $sha.Dispose()
  }
}

function Write-DocsEditorUtf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $parent = Split-Path -Path $Path -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-JsonResponse {
  param(
    [Parameter(Mandatory)][System.Net.HttpListenerContext]$Context,
    [Parameter(Mandatory)]$Payload,
    [int]$StatusCode = 200
  )

  $response = $Context.Response
  $response.StatusCode = $StatusCode
  $response.ContentType = "application/json; charset=utf-8"
  $response.Headers["Access-Control-Allow-Origin"] = "*"
  $response.Headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
  $response.Headers["Access-Control-Allow-Headers"] = "Content-Type"

  $json = ($Payload | ConvertTo-Json -Depth 20)
  $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
  $response.OutputStream.Write($buffer, 0, $buffer.Length)
  $response.OutputStream.Flush()
  $response.Close()
}

function Write-PlainResponse {
  param(
    [Parameter(Mandatory)][System.Net.HttpListenerContext]$Context,
    [string]$Text,
    [int]$StatusCode = 200
  )

  $response = $Context.Response
  $response.StatusCode = $StatusCode
  $response.ContentType = "text/plain; charset=utf-8"
  $response.Headers["Access-Control-Allow-Origin"] = "*"
  $response.Headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
  $response.Headers["Access-Control-Allow-Headers"] = "Content-Type"

  $buffer = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
  $response.OutputStream.Write($buffer, 0, $buffer.Length)
  $response.OutputStream.Flush()
  $response.Close()
}

function Write-ErrorResponse {
  param(
    [Parameter(Mandatory)][System.Net.HttpListenerContext]$Context,
    [Parameter(Mandatory)][string]$Message,
    [int]$StatusCode = 400
  )

  Write-JsonResponse -Context $Context -StatusCode $StatusCode -Payload ([ordered]@{
      ok = $false
      error = $Message
    })
}

function Read-JsonBody {
  param([Parameter(Mandatory)][System.Net.HttpListenerRequest]$Request)

  $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
  try {
    $bodyText = $reader.ReadToEnd()
  }
  finally {
    $reader.Dispose()
  }

  if ([string]::IsNullOrWhiteSpace($bodyText)) {
    return [ordered]@{}
  }

  return ($bodyText | ConvertFrom-Json)
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

function Get-RelativePathFromDocsRoot {
  param([Parameter(Mandatory)][string]$FullPath)
  return ((Get-UEToolSuiteRelativePath -BasePath $script:DocsRoot -TargetPath $FullPath) -replace '\\', '/')
}

function Resolve-DocsPathFromToken {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [switch]$RequireExisting
  )

  $rawToken = $PathToken.Trim()
  if ([string]::IsNullOrWhiteSpace($rawToken)) {
    throw "Path token is required."
  }

  if ($rawToken -match '^[A-Za-z]:') {
    throw "Absolute paths are not allowed. Use a path relative to Docs/."
  }

  $normalizedToken = ($rawToken -replace '/', '\').Trim('\')
  if ([string]::IsNullOrWhiteSpace($normalizedToken)) {
    throw "Path token must not be empty."
  }

  $candidate = Join-Path $script:DocsRoot $normalizedToken
  $resolvedCandidate = [System.IO.Path]::GetFullPath($candidate)
  $docsRootWithSlash = [System.IO.Path]::GetFullPath($script:DocsRoot).TrimEnd('\') + '\'
  if (-not $resolvedCandidate.StartsWith($docsRootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path '$PathToken' resolves outside Docs/."
  }

  if ($RequireExisting -and -not (Test-Path -LiteralPath $resolvedCandidate)) {
    throw "Path not found under Docs/: $PathToken"
  }

  return $resolvedCandidate
}

function Resolve-PagePathFromToken {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [switch]$RequireExisting
  )

  $normalizedToken = $PathToken.Trim()
  if (-not $normalizedToken.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
    $normalizedToken = "$normalizedToken.md"
  }

  return (Resolve-DocsPathFromToken -PathToken $normalizedToken -RequireExisting:$RequireExisting)
}

function Resolve-DocsEditorNavigationTarget {
  param([Parameter(Mandatory)][string]$PathToken)

  try {
    return (Invoke-DocsModuleInternal -ScriptBlock {
        param($docsRootPath, $token)
        Resolve-DocsNavigationTarget -DocsRoot $docsRootPath -TargetPath $token
      } -Arguments @($script:DocsRoot, $PathToken))
  }
  catch {
    $message = [string]$_.Exception.Message
    if (($message -notmatch 'explicit sidebar_position') -and ($message -notmatch 'explicit position')) {
      throw
    }

    $resolvedPath = Resolve-DocsPathFromToken -PathToken $PathToken -RequireExisting
    $parentDir = Split-Path -Path $resolvedPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and (Test-Path -LiteralPath $parentDir -PathType Container)) {
      Normalize-DocsEditorSiblingPositions -ParentDir $parentDir
    }

    return (Invoke-DocsModuleInternal -ScriptBlock {
        param($docsRootPath, $token)
        Resolve-DocsNavigationTarget -DocsRoot $docsRootPath -TargetPath $token
      } -Arguments @($script:DocsRoot, $PathToken))
  }
}

function Remove-SlugFrontMatterKey {
  param([Parameter(Mandatory)][string]$FilePath)

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    return
  }

  $content = Get-Content -LiteralPath $FilePath -Raw
  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')
  if (-not $match.Success) {
    return
  }

  $frontMatter = $match.Groups['frontMatter'].Value
  if ($frontMatter -notmatch '(?m)^\s*slug\s*:') {
    return
  }

  $updatedFrontMatter = [regex]::Replace($frontMatter, '(?m)^\s*slug\s*:.*(?:\r?\n)?', '')
  $updatedFrontMatter = $updatedFrontMatter.TrimEnd("`r", "`n")
  $rest = $match.Groups['rest'].Value

  $newContent = if ([string]::IsNullOrWhiteSpace($updatedFrontMatter)) {
    $rest.TrimStart("`r", "`n")
  }
  else {
    "---`r`n$updatedFrontMatter`r`n---$rest"
  }

  Write-DocsEditorUtf8NoBomFile -Path $FilePath -Content $newContent
}

function Get-DocsEditorExpectedSlugForMarkdownPath {
  param([Parameter(Mandatory)][string]$MarkdownPath)

  $relative = Get-RelativePathFromDocsRoot -FullPath ([System.IO.Path]::GetFullPath($MarkdownPath))
  $normalized = ($relative -replace '\\', '/').Trim('/')
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return ""
  }

  $leafName = [System.IO.Path]::GetFileName($normalized)
  $directoryName = [System.IO.Path]::GetDirectoryName($normalized)
  $sectionPath = if ([string]::IsNullOrWhiteSpace($directoryName)) {
    ""
  }
  else {
    ($directoryName -replace '\\', '/')
  }

  if ($leafName.Equals("README.md", [System.StringComparison]::OrdinalIgnoreCase)) {
    if ([string]::IsNullOrWhiteSpace($sectionPath)) {
      return ""
    }

    return [string](Invoke-DocsModuleInternal -ScriptBlock {
        param($path)
        Get-SlugForSectionPath -SectionPath $path
      } -Arguments @($sectionPath))
  }

  $pageName = [System.IO.Path]::GetFileNameWithoutExtension($leafName)
  return [string](Invoke-DocsModuleInternal -ScriptBlock {
      param($path, $name)
      Get-SlugForPage -SectionPath $path -PageName $name
    } -Arguments @($sectionPath, $pageName))
}

function Ensure-DocsEditorSlugFrontMatter {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$Slug
  )

  if ([string]::IsNullOrWhiteSpace($Slug)) {
    return
  }

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    return
  }

  $content = Get-Content -LiteralPath $FilePath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')

  if (-not $match.Success) {
    $trimmedBody = $content.TrimStart("`r", "`n")
    $newContent = @(
      '---'
      "slug: $Slug"
      '---'
      ''
      $trimmedBody
    ) -join $newline
    Write-DocsEditorUtf8NoBomFile -Path $FilePath -Content $newContent
    return
  }

  $frontMatter = $match.Groups['frontMatter'].Value
  if ($frontMatter -match '(?m)^\s*slug\s*:') {
    return
  }

  $rest = $match.Groups['rest'].Value
  $updatedFrontMatter = if ([string]::IsNullOrWhiteSpace($frontMatter.Trim())) {
    "slug: $Slug"
  }
  else {
    $frontMatter.TrimEnd("`r", "`n") + $newline + "slug: $Slug"
  }

  $newContent = "---$newline$updatedFrontMatter$newline---$rest"
  Write-DocsEditorUtf8NoBomFile -Path $FilePath -Content $newContent
}

function Ensure-DocsEditorMovedPageSlugsRemainStable {
  param([Parameter(Mandatory)][hashtable]$MovedMarkdownPathMap)

  if ($MovedMarkdownPathMap.Count -eq 0) {
    return
  }

  foreach ($entry in $MovedMarkdownPathMap.GetEnumerator()) {
    $fromFullPath = [System.IO.Path]::GetFullPath([string]$entry.Key)
    $toFullPath = [System.IO.Path]::GetFullPath([string]$entry.Value)
    if ($fromFullPath.Equals($toFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if (-not (Test-Path -LiteralPath $toFullPath -PathType Leaf)) {
      continue
    }

    $expectedSlug = Get-DocsEditorExpectedSlugForMarkdownPath -MarkdownPath $fromFullPath
    if ([string]::IsNullOrWhiteSpace($expectedSlug)) {
      continue
    }

    Ensure-DocsEditorSlugFrontMatter -FilePath $toFullPath -Slug $expectedSlug
  }
}

function Update-SectionCategoryDocLinkId {
  param([Parameter(Mandatory)][string]$SectionDirectoryPath)

  $categoryPath = Join-Path $SectionDirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    return
  }

  $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  if (-not $categoryJson.link) {
    return
  }

  $linkType = [string]$categoryJson.link.type
  if ($linkType.Trim().ToLowerInvariant() -ne "doc") {
    return
  }

  $readmePath = Join-Path $SectionDirectoryPath "README.md"
  if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
    return
  }

  $newDocId = Invoke-DocsModuleInternal -ScriptBlock {
    param($docsRootPath, $filePath)
    Get-DocIdForPath -DocsRoot $docsRootPath -FullPath $filePath
  } -Arguments @($script:DocsRoot, $readmePath)
  $categoryJson.link.id = $newDocId
  $updatedJson = ($categoryJson | ConvertTo-Json -Depth 10) + "`r`n"

  Write-DocsEditorUtf8NoBomFile -Path $categoryPath -Content $updatedJson
}

function Get-DocsEditorCategoryLinkInfo {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    return $null
  }

  try {
    $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  }
  catch {
    return $null
  }

  if (-not $categoryJson.link) {
    return $null
  }

  $linkType = ([string]$categoryJson.link.type).Trim()
  if ([string]::IsNullOrWhiteSpace($linkType)) {
    return $null
  }

  return [pscustomobject]@{
    CategoryPath = $categoryPath
    CategoryJson = $categoryJson
    LinkType = $linkType
    LinkId = ([string]$categoryJson.link.id).Trim().Replace('\', '/')
  }
}

function Resolve-DocsEditorMarkdownPathFromDocId {
  param([Parameter(Mandatory)][string]$DocId)

  $normalizedDocId = ([string]$DocId).Trim().Replace('\', '/').Trim('/')
  if ([string]::IsNullOrWhiteSpace($normalizedDocId)) {
    return $null
  }

  $pageCandidate = Join-Path $script:DocsRoot (($normalizedDocId -replace '/', '\') + ".md")
  if (Test-Path -LiteralPath $pageCandidate -PathType Leaf) {
    return [System.IO.Path]::GetFullPath($pageCandidate)
  }

  $sectionReadmeCandidate = Join-Path $script:DocsRoot (($normalizedDocId -replace '/', '\') + "\README.md")
  if (Test-Path -LiteralPath $sectionReadmeCandidate -PathType Leaf) {
    return [System.IO.Path]::GetFullPath($sectionReadmeCandidate)
  }

  return $null
}

function Get-DocsEditorCategoryLinkedMarkdownPath {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $linkInfo = Get-DocsEditorCategoryLinkInfo -DirectoryPath $DirectoryPath
  if ($null -eq $linkInfo) {
    return $null
  }

  if (-not ([string]$linkInfo.LinkType).Equals("doc", [System.StringComparison]::OrdinalIgnoreCase)) {
    return $null
  }

  return (Resolve-DocsEditorMarkdownPathFromDocId -DocId $linkInfo.LinkId)
}

function Test-DocsEditorCategoryLinksToPage {
  param(
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)][string]$PagePath
  )

  $linkedPath = Get-DocsEditorCategoryLinkedMarkdownPath -DirectoryPath $DirectoryPath
  if ([string]::IsNullOrWhiteSpace([string]$linkedPath)) {
    return $false
  }

  $linkedFullPath = [System.IO.Path]::GetFullPath([string]$linkedPath)
  $pageFullPath = [System.IO.Path]::GetFullPath($PagePath)
  return $linkedFullPath.Equals($pageFullPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Clear-DocsEditorCategoryLink {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $linkInfo = Get-DocsEditorCategoryLinkInfo -DirectoryPath $DirectoryPath
  if ($null -eq $linkInfo) {
    return $false
  }

  $linkType = ([string]$linkInfo.LinkType).Trim().ToLowerInvariant()
  if ($linkType -eq "generated-index" -or $linkType -eq "none") {
    return $false
  }

  $linkInfo.CategoryJson.link = $null
  $updatedJson = ($linkInfo.CategoryJson | ConvertTo-Json -Depth 10) + "`r`n"
  Write-DocsEditorUtf8NoBomFile -Path $linkInfo.CategoryPath -Content $updatedJson
  return $true
}

function Clear-DocsDomainLandingReferenceForPage {
  param([Parameter(Mandatory)][string]$PagePath)

  $relativePagePath = Get-RelativePathFromDocsRoot -FullPath $PagePath
  if ([string]::IsNullOrWhiteSpace($relativePagePath)) {
    return $false
  }

  $normalizedRelativePath = $relativePagePath.Replace('\', '/')
  $definitions = Get-DocsDomainDefinitions
  $domains = @($definitions.domains)
  $changed = $false

  foreach ($domain in $domains) {
    $readmePath = ([string]$domain.readmePath).Trim().Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($readmePath)) {
      continue
    }

    if ($readmePath.Equals($normalizedRelativePath, [System.StringComparison]::OrdinalIgnoreCase)) {
      $domain.readmePath = ""
      $changed = $true
    }
  }

  if ($changed) {
    Write-DocsDomainsConfig -Domains $domains
  }

  return $changed
}

function ConvertTo-DocsEditorCompactPositionValue {
  param([Parameter(Mandatory)][double]$Value)

  $rounded = [Math]::Round($Value, 6)
  $whole = [Math]::Round($rounded)
  if ([Math]::Abs($rounded - $whole) -lt 0.0000001) {
    return [int]$whole
  }
  return $rounded
}

function Format-DocsEditorYamlNumber {
  param([Parameter(Mandatory)][double]$Value)

  $normalized = ConvertTo-DocsEditorCompactPositionValue -Value $Value
  if ($normalized -is [int]) {
    return ([int]$normalized).ToString([System.Globalization.CultureInfo]::InvariantCulture)
  }
  return ([double]$normalized).ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function Set-DocsSidebarPositionLocal {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][double]$Position
  )

  $content = Get-Content -LiteralPath $FilePath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $formattedPosition = Format-DocsEditorYamlNumber -Value $Position

  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')
  if (-not $match.Success) {
    $newContent = @(
      '---'
      "sidebar_position: $formattedPosition"
      '---'
      ''
      $content.TrimStart("`r", "`n")
    ) -join $newline
    Write-DocsEditorUtf8NoBomFile -Path $FilePath -Content $newContent
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
  Write-DocsEditorUtf8NoBomFile -Path $FilePath -Content $newContent
}

function Set-DocsCategoryPositionLocal {
  param(
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)][double]$Position
  )

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    throw "Section category metadata not found: $categoryPath"
  }

  $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  $categoryJson.position = ConvertTo-DocsEditorCompactPositionValue -Value $Position
  $categoryContent = ($categoryJson | ConvertTo-Json -Depth 20) + "`r`n"
  Write-DocsEditorUtf8NoBomFile -Path $categoryPath -Content $categoryContent
}

function Set-DocsNavigationItemPositionLocal {
  param(
    [Parameter(Mandatory)][object]$Item,
    [Parameter(Mandatory)][double]$Position
  )

  $itemType = [string]$Item.ItemType
  $fullPath = [string]$Item.FullPath
  if ([string]::IsNullOrWhiteSpace($fullPath)) {
    throw "Navigation item is missing FullPath."
  }

  if ($itemType -eq "section") {
    Set-DocsCategoryPositionLocal -DirectoryPath $fullPath -Position $Position
    return
  }

  Set-DocsSidebarPositionLocal -FilePath $fullPath -Position $Position
}

function Get-DocsEditorNavigationSiblingGroups {
  param([Parameter(Mandatory)][string]$ParentDir)

  $siblings = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in @(Invoke-DocsModuleInternal -ScriptBlock {
      param($docsRootPath, $parentDirectory)
      Get-DocsNavigationSiblings -DocsRoot $docsRootPath -ParentDir $parentDirectory
    } -Arguments @($script:DocsRoot, $ParentDir))) {
    $siblings.Add($sibling) | Out-Null
  }
  Add-DocsEditorFallbackTreeSiblings -Siblings $siblings -ParentDir $ParentDir

  $linkedMarkdownPath = Get-DocsEditorCategoryLinkedMarkdownPath -DirectoryPath $ParentDir
  $linkedMarkdownFullPath = ""
  if (-not [string]::IsNullOrWhiteSpace([string]$linkedMarkdownPath)) {
    $candidateFullPath = [System.IO.Path]::GetFullPath([string]$linkedMarkdownPath)
    $candidateParentDir = Split-Path -Path $candidateFullPath -Parent
    if ($candidateParentDir.Equals([System.IO.Path]::GetFullPath($ParentDir), [System.StringComparison]::OrdinalIgnoreCase)) {
      $linkedMarkdownFullPath = $candidateFullPath
    }
  }

  $pinned = New-Object System.Collections.Generic.List[object]
  $visible = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in @($siblings.ToArray() | Sort-Object Position, RelativePath)) {
    $siblingFullPath = [System.IO.Path]::GetFullPath([string]$sibling.FullPath)
    if (
      -not [string]::IsNullOrWhiteSpace($linkedMarkdownFullPath) -and
      ([string]$sibling.ItemType) -eq "page" -and
      $siblingFullPath.Equals($linkedMarkdownFullPath, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
      $pinned.Add($sibling) | Out-Null
      continue
    }

    $visible.Add($sibling) | Out-Null
  }

  return [pscustomobject]@{
    Pinned = @($pinned.ToArray())
    Visible = @($visible.ToArray())
  }
}

function Normalize-DocsEditorSiblingPositions {
  param(
    [Parameter(Mandatory)][string]$ParentDir,
    [AllowEmptyCollection()][object[]]$VisibleSiblings
  )

  $groups = Get-DocsEditorNavigationSiblingGroups -ParentDir $ParentDir
  $orderedVisible = if ($PSBoundParameters.ContainsKey("VisibleSiblings")) {
    @($VisibleSiblings)
  }
  else {
    @($groups.Visible | Sort-Object Position, RelativePath)
  }

  $positionCounter = 1
  foreach ($item in @($groups.Pinned | Sort-Object Position, RelativePath)) {
    Set-DocsNavigationItemPositionLocal -Item $item -Position ([double]$positionCounter)
    $positionCounter += 1
  }

  foreach ($item in $orderedVisible) {
    Set-DocsNavigationItemPositionLocal -Item $item -Position ([double]$positionCounter)
    $positionCounter += 1
  }
}

function Get-DocsEditorPathKey {
  param([Parameter(Mandatory)][string]$Path)

  return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\')).ToLowerInvariant()
}

function Test-DocsEditorLocalMarkdownLink {
  param([Parameter(Mandatory)][string]$Target)

  $trimmed = $Target.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }
  if ($trimmed.StartsWith("pathname://", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
  if ($trimmed.StartsWith("#") -or $trimmed.StartsWith("/")) { return $false }
  if ($trimmed -match '^[A-Za-z][A-Za-z0-9+.-]*:') { return $false }
  if ($trimmed -notmatch '\.md(?:[?#].*)?$') { return $false }
  return $true
}

function Split-DocsEditorMarkdownTarget {
  param([Parameter(Mandatory)][string]$Target)

  $path = $Target
  $tail = ""
  $hashIndex = $path.IndexOf("#")
  $queryIndex = $path.IndexOf("?")
  $splitIndex = -1
  if ($hashIndex -ge 0 -and $queryIndex -ge 0) {
    $splitIndex = [Math]::Min($hashIndex, $queryIndex)
  }
  elseif ($hashIndex -ge 0) {
    $splitIndex = $hashIndex
  }
  elseif ($queryIndex -ge 0) {
    $splitIndex = $queryIndex
  }

  if ($splitIndex -ge 0) {
    $tail = $path.Substring($splitIndex)
    $path = $path.Substring(0, $splitIndex)
  }

  return [pscustomobject]@{
    Path = $path
    Tail = $tail
  }
}

function Decode-DocsEditorMarkdownPathForFilesystem {
  param([Parameter(Mandatory)][string]$Path)

  try {
    return [System.Uri]::UnescapeDataString($Path)
  }
  catch {
    return $Path
  }
}

function Format-DocsEditorRelativeMarkdownTarget {
  param(
    [Parameter(Mandatory)][string]$RelativePath,
    [AllowEmptyString()][string]$Tail = ""
  )

  $normalized = $RelativePath -replace '\\', '/'
  if (-not ($normalized.StartsWith(".") -or $normalized.StartsWith("/"))) {
    $normalized = "./$normalized"
  }

  return $normalized + $Tail
}

function Get-DocsEditorFrontMatterSlug {
  param([Parameter(Mandatory)][string]$FilePath)

  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    return ""
  }

  $content = Get-Content -LiteralPath $FilePath -Raw
  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?:\r?\n|$)')
  if (-not $match.Success) {
    return ""
  }

  $frontMatter = $match.Groups['frontMatter'].Value
  $slugMatch = [regex]::Match($frontMatter, '(?m)^\s*slug\s*:\s*(?<value>.+?)\s*$')
  if (-not $slugMatch.Success) {
    return ""
  }

  $slug = [string]$slugMatch.Groups['value'].Value
  $slug = $slug.Trim()
  if (($slug.StartsWith("'") -and $slug.EndsWith("'")) -or ($slug.StartsWith('"') -and $slug.EndsWith('"'))) {
    if ($slug.Length -ge 2) {
      $slug = $slug.Substring(1, $slug.Length - 2)
    }
  }

  return $slug.Trim()
}

function Convert-DocsEditorSlugToDocsRoute {
  param(
    [Parameter(Mandatory)][string]$Slug,
    [AllowEmptyString()][string]$MarkdownPath = ""
  )

  $trimmed = [string]$Slug
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return ""
  }

  $trimmed = $trimmed.Trim()
  if (-not $trimmed.StartsWith("/")) {
    $relativePrefix = ""
    if (-not [string]::IsNullOrWhiteSpace($MarkdownPath)) {
      $fullPath = [System.IO.Path]::GetFullPath($MarkdownPath)
      $relativePath = Get-RelativePathFromDocsRoot -FullPath $fullPath
      $relativeDirectory = [System.IO.Path]::GetDirectoryName($relativePath)
      if (-not [string]::IsNullOrWhiteSpace($relativeDirectory)) {
        $relativePrefix = "/" + (($relativeDirectory -replace '\\', '/').Trim('/'))
      }
    }

    if ([string]::IsNullOrWhiteSpace($relativePrefix)) {
      $trimmed = "/$trimmed"
    }
    else {
      $trimmed = "$relativePrefix/$($trimmed.TrimStart('/'))"
    }
  }

  if ($trimmed -eq "/") {
    return "/docs/"
  }

  return "/docs$trimmed"
}

function Get-DocsEditorMarkdownRouteTarget {
  param(
    [Parameter(Mandatory)][string]$MarkdownPath,
    [AllowEmptyString()][string]$Tail = ""
  )

  $fullPath = [System.IO.Path]::GetFullPath($MarkdownPath)
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    return ""
  }

  $slug = Get-DocsEditorFrontMatterSlug -FilePath $fullPath
  if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = Get-DocsEditorExpectedSlugForMarkdownPath -MarkdownPath $fullPath
  }

  $route = Convert-DocsEditorSlugToDocsRoute -Slug $slug -MarkdownPath $fullPath
  if ([string]::IsNullOrWhiteSpace($route)) {
    return ""
  }

  return $route + [string]$Tail
}

function Get-DocsEditorMovedMarkdownRouteMap {
  param([Parameter(Mandatory)][hashtable]$MovedMarkdownPathMap)

  $routeMap = @{}
  foreach ($entry in $MovedMarkdownPathMap.GetEnumerator()) {
    $fromFullPath = [System.IO.Path]::GetFullPath([string]$entry.Key)
    $toFullPath = [System.IO.Path]::GetFullPath([string]$entry.Value)

    $oldRoute = Get-DocsEditorMarkdownRouteTarget -MarkdownPath $fromFullPath
    $newRoute = Get-DocsEditorMarkdownRouteTarget -MarkdownPath $toFullPath
    if ([string]::IsNullOrWhiteSpace($oldRoute) -or [string]::IsNullOrWhiteSpace($newRoute)) {
      continue
    }

    $routeMap[$oldRoute] = $newRoute
  }

  return $routeMap
}

function Get-DocsEditorMovedMarkdownMap {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$DestinationPath,
    [Parameter(Mandatory)][string]$ItemType
  )

  $map = @{}
  if ($ItemType -eq "page") {
    $map[(Get-DocsEditorPathKey -Path $SourcePath)] = [System.IO.Path]::GetFullPath($DestinationPath)
    return $map
  }

  $sourceFull = [System.IO.Path]::GetFullPath($SourcePath)
  $destinationFull = [System.IO.Path]::GetFullPath($DestinationPath)
  $files = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
  foreach ($file in $files) {
    $relative = Get-UEToolSuiteRelativePath -BasePath $sourceFull -TargetPath $file.FullName
    $newPath = Join-Path $destinationFull $relative
    $map[(Get-DocsEditorPathKey -Path $file.FullName)] = [System.IO.Path]::GetFullPath($newPath)
  }
  return $map
}

function Get-DocsEditorDeletedMarkdownMap {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [Parameter(Mandatory)][string]$ItemType
  )

  $map = @{}
  $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
  if ($ItemType -eq "page") {
    $map[(Get-DocsEditorPathKey -Path $targetFull)] = $targetFull
    return $map
  }

  $files = @(Get-ChildItem -LiteralPath $targetFull -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
  foreach ($file in $files) {
    $fileFull = [System.IO.Path]::GetFullPath($file.FullName)
    $map[(Get-DocsEditorPathKey -Path $fileFull)] = $fileFull
  }
  return $map
}

function Update-DocsMarkdownLinksForMove {
  param([Parameter(Mandatory)][hashtable]$MovedMarkdownPathMap)

  if ($MovedMarkdownPathMap.Count -eq 0) {
    return
  }

  $reverseMovedMap = @{}
  foreach ($entry in $MovedMarkdownPathMap.GetEnumerator()) {
    $reverseMovedMap[(Get-DocsEditorPathKey -Path ([string]$entry.Value))] = [string]$entry.Key
  }
  $movedMarkdownRouteMap = Get-DocsEditorMovedMarkdownRouteMap -MovedMarkdownPathMap $MovedMarkdownPathMap

  $docsRootFull = [System.IO.Path]::GetFullPath($script:DocsRoot).TrimEnd('\') + '\'
  $markdownFiles = @(Get-ChildItem -LiteralPath $script:DocsRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
  $linkPattern = '(!?\[[^\]]*\]\()(?<target><[^>]+>|pathname://[^)\r\n]+|[^)\r\n]*?\.md(?:[?#][^)\s]*)?)(?<suffix>(?:\s+(?:"[^"]*"|''[^'']*''|\([^)]+\)))?\))'

  foreach ($file in $markdownFiles) {
    $currentPath = [System.IO.Path]::GetFullPath($file.FullName)
    $currentKey = Get-DocsEditorPathKey -Path $currentPath
    $oldContainingPath = if ($reverseMovedMap.ContainsKey($currentKey)) { [string]$reverseMovedMap[$currentKey] } else { $currentPath }
    $containingFileMoved = -not $oldContainingPath.Equals($currentPath, [System.StringComparison]::OrdinalIgnoreCase)
    $currentDir = Split-Path -Path $currentPath -Parent
    $oldContainingDir = Split-Path -Path $oldContainingPath -Parent

    $content = Get-Content -LiteralPath $currentPath -Raw
    $changed = $false
    $script:DocsEditorLinkRewriteChanged = $false
    $updated = [regex]::Replace($content, $linkPattern, [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)

        $rawTarget = $match.Groups['target'].Value
        $wrappedInAngles = $rawTarget.StartsWith("<") -and $rawTarget.EndsWith(">")
        $target = if ($wrappedInAngles) { $rawTarget.Substring(1, $rawTarget.Length - 2) } else { $rawTarget }
        if (-not (Test-DocsEditorLocalMarkdownLink -Target $target)) {
          return $match.Value
        }

        if ($target.StartsWith("pathname://", [System.StringComparison]::OrdinalIgnoreCase)) {
          $routeTarget = $target.Substring("pathname://".Length)
          if (-not $movedMarkdownRouteMap.ContainsKey($routeTarget)) {
            return $match.Value
          }

          $newPathnameTarget = "pathname://$([string]$movedMarkdownRouteMap[$routeTarget])"
          if ($rawTarget -eq $newPathnameTarget) {
            return $match.Value
          }

          $script:DocsEditorLinkRewriteChanged = $true
          return $match.Groups[1].Value + $newPathnameTarget + $match.Groups['suffix'].Value
        }

        $splitTarget = Split-DocsEditorMarkdownTarget -Target $target
        $targetPathForFilesystem = Decode-DocsEditorMarkdownPathForFilesystem -Path $splitTarget.Path
        $resolvedOldTarget = [System.IO.Path]::GetFullPath((Join-Path $oldContainingDir $targetPathForFilesystem))
        $resolvedOldTargetKey = Get-DocsEditorPathKey -Path $resolvedOldTarget

        $newTargetPath = $null
        if ($MovedMarkdownPathMap.ContainsKey($resolvedOldTargetKey)) {
          $newTargetPath = [System.IO.Path]::GetFullPath([string]$MovedMarkdownPathMap[$resolvedOldTargetKey])
        }
        elseif ($containingFileMoved) {
          $newTargetPath = $resolvedOldTarget
        }
        else {
          return $match.Value
        }

        $newTargetFull = [System.IO.Path]::GetFullPath($newTargetPath)
        if (-not (($newTargetFull + '\').StartsWith($docsRootFull, [System.StringComparison]::OrdinalIgnoreCase))) {
          return $match.Value
        }

        $routeTarget = Get-DocsEditorMarkdownRouteTarget -MarkdownPath $newTargetFull -Tail $splitTarget.Tail
        if (-not [string]::IsNullOrWhiteSpace($routeTarget)) {
          $newTarget = "pathname://$routeTarget"
        }
        else {
          $relative = Get-UEToolSuiteRelativePath -BasePath $currentDir -TargetPath $newTargetFull
          $newTarget = Format-DocsEditorRelativeMarkdownTarget -RelativePath $relative -Tail $splitTarget.Tail
        }

        $shouldWrapInAngles = $newTarget -match '\s'
        if (-not $shouldWrapInAngles -and $wrappedInAngles -and $newTarget -match '\.md(?:[?#].*)?$') {
          $shouldWrapInAngles = $true
        }
        if ($shouldWrapInAngles) {
          $newTarget = "<$newTarget>"
        }

        if ($rawTarget -eq $newTarget) {
          return $match.Value
        }

        $script:DocsEditorLinkRewriteChanged = $true
        return $match.Groups[1].Value + $newTarget + $match.Groups['suffix'].Value
      })

    if ($script:DocsEditorLinkRewriteChanged) {
      $changed = $true
      $script:DocsEditorLinkRewriteChanged = $false
    }

    if ($changed) {
      Write-DocsEditorUtf8NoBomFile -Path $currentPath -Content $updated
    }
  }
}

function Get-DocsEditorDocIdFromMarkdownPath {
  param([Parameter(Mandatory)][string]$Path)

  $relative = Get-RelativePathFromDocsRoot -FullPath ([System.IO.Path]::GetFullPath($Path))
  return ($relative -replace '\\', '/' -replace '\.md$', '')
}

function Get-DocsEditorReversedPathMap {
  param([Parameter(Mandatory)][hashtable]$PathMap)

  $reversed = @{}
  foreach ($entry in $PathMap.GetEnumerator()) {
    $fromPath = [System.IO.Path]::GetFullPath([string]$entry.Key)
    $toPath = [System.IO.Path]::GetFullPath([string]$entry.Value)
    $reversed[(Get-DocsEditorPathKey -Path $toPath)] = $fromPath
  }
  return $reversed
}

function Normalize-DocsEditorSiteOrigin {
  param([AllowEmptyString()][string]$Value)

  $raw = [string]$Value
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return ""
  }

  try {
    $uri = [System.Uri]::new($raw)
    if (-not $uri.IsAbsoluteUri) {
      return ""
    }
    if ($uri.Scheme -ne "http" -and $uri.Scheme -ne "https") {
      return ""
    }
    return $uri.GetLeftPart([System.UriPartial]::Authority).TrimEnd('/')
  }
  catch {
    return ""
  }
}

function Get-DocsEditorSiteOriginFromRequest {
  param([Parameter(Mandatory)][System.Net.HttpListenerRequest]$Request)

  $candidates = @()
  $originHeader = [string]$Request.Headers["Origin"]
  if (-not [string]::IsNullOrWhiteSpace($originHeader)) {
    $candidates += $originHeader
  }

  $refererHeader = [string]$Request.Headers["Referer"]
  if (-not [string]::IsNullOrWhiteSpace($refererHeader)) {
    $candidates += $refererHeader
  }

  if ($Request.UrlReferrer) {
    $candidates += [string]$Request.UrlReferrer.AbsoluteUri
  }

  foreach ($candidate in $candidates) {
    $normalized = Normalize-DocsEditorSiteOrigin -Value $candidate
    if (-not [string]::IsNullOrWhiteSpace($normalized)) {
      return $normalized
    }
  }

  return ""
}

function Get-DocsEditorDevServerOrigins {
  param([AllowEmptyString()][string]$PreferredSiteOrigin)

  $origins = New-Object System.Collections.Generic.List[string]
  $seen = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

  $preferred = Normalize-DocsEditorSiteOrigin -Value $PreferredSiteOrigin
  if (-not [string]::IsNullOrWhiteSpace($preferred) -and $seen.Add($preferred)) {
    $origins.Add($preferred) | Out-Null
  }

  try {
    $serverEntries = @(Invoke-DocsModuleInternal -ScriptBlock {
        param($resolvedRepoRoot)
        Get-DocsServerEntries -ResolvedRepoRoot $resolvedRepoRoot
      } -Arguments @($script:RepoRoot))

    foreach ($entry in $serverEntries) {
      if ($null -eq $entry -or -not $entry.PSObject.Properties["url"]) {
        continue
      }

      $candidateOrigin = Normalize-DocsEditorSiteOrigin -Value ([string]$entry.url)
      if (-not [string]::IsNullOrWhiteSpace($candidateOrigin) -and $seen.Add($candidateOrigin)) {
        $origins.Add($candidateOrigin) | Out-Null
      }
    }
  }
  catch {
    # Best-effort only. Move safety checks still run without dev-server origins.
  }

  return @($origins.ToArray())
}

function Invoke-DocsEditorDevServerInvalidate {
  param([AllowEmptyString()][string]$PreferredSiteOrigin)

  $origins = @(Get-DocsEditorDevServerOrigins -PreferredSiteOrigin $PreferredSiteOrigin)
  if ($origins.Count -eq 0) {
    return $false
  }

  $paths = @("/webpack-dev-server/invalidate", "/invalidate")

  foreach ($origin in $origins) {
    foreach ($path in $paths) {
      $url = "$origin$path"
      try {
        $request = [System.Net.HttpWebRequest]::Create($url)
        $request.Method = "GET"
        $request.Timeout = 1800
        $request.ReadWriteTimeout = 1800
        $request.AllowAutoRedirect = $false
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        try {
          $statusCode = [int]$response.StatusCode
          if ($statusCode -ge 200 -and $statusCode -lt 400) {
            return $true
          }
        }
        finally {
          $response.Close()
        }
      }
      catch [System.Net.WebException] {
        $webResponse = $_.Exception.Response
        if ($webResponse -is [System.Net.HttpWebResponse]) {
          $statusCode = [int]$webResponse.StatusCode
          $webResponse.Close()
          if ($statusCode -eq 404 -or $statusCode -eq 405) {
            continue
          }
        }
      }
      catch {
      }
    }
  }

  return $false
}

function Get-DocsEditorStaleRegistryImports {
  param([Parameter(Mandatory)][hashtable]$MovedMarkdownPathMap)

  if ($MovedMarkdownPathMap.Count -eq 0) {
    return @()
  }

  $websiteRoot = Join-Path $script:RepoRoot "website"
  if (-not (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    return @()
  }

  $registryPath = Join-Path $websiteRoot ".docusaurus\registry.js"
  if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    return @()
  }

  $content = Get-Content -LiteralPath $registryPath -Raw
  if ([string]::IsNullOrEmpty($content)) {
    return @()
  }

  $staleImports = New-Object System.Collections.Generic.List[string]
  $seen = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($entry in $MovedMarkdownPathMap.GetEnumerator()) {
    $oldPath = [System.IO.Path]::GetFullPath([string]$entry.Key)
    if (Test-Path -LiteralPath $oldPath -PathType Leaf) {
      continue
    }

    $relative = (Get-RelativePathFromDocsRoot -FullPath $oldPath) -replace '\\', '/'
    if ([string]::IsNullOrWhiteSpace($relative)) {
      continue
    }

    $importPath = "@site/../Docs/$relative"
    if ($content.IndexOf($importPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -and $seen.Add($importPath)) {
      $staleImports.Add($importPath) | Out-Null
    }
  }

  return @($staleImports.ToArray())
}

function Update-DocsEditorDocIdReferencesForMove {
  param([Parameter(Mandatory)][hashtable]$MovedMarkdownPathMap)

  if ($MovedMarkdownPathMap.Count -eq 0) {
    return
  }

  $websiteRoot = Join-Path $script:RepoRoot "website"
  if (-not (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    return
  }

  $candidateFiles = New-Object System.Collections.Generic.List[string]
  foreach ($filePath in @(
      (Join-Path $websiteRoot "docusaurus.config.ts")
      (Join-Path $websiteRoot "sidebars.ts")
    )) {
    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
      $candidateFiles.Add([string]$filePath) | Out-Null
    }
  }

  foreach ($categoryFile in @(Get-ChildItem -LiteralPath $script:DocsRoot -Filter "_category_.json" -File -Recurse -ErrorAction SilentlyContinue)) {
    $candidateFiles.Add([string]$categoryFile.FullName) | Out-Null
  }

  $candidateFiles = @($candidateFiles.ToArray() | Sort-Object -Unique)

  if ($candidateFiles.Count -eq 0) {
    return
  }

  foreach ($filePath in $candidateFiles) {
    $content = Get-Content -LiteralPath $filePath -Raw
    $updated = $content
    $changed = $false

    foreach ($entry in $MovedMarkdownPathMap.GetEnumerator()) {
      $fromFullPath = [System.IO.Path]::GetFullPath([string]$entry.Key)
      $toFullPath = [System.IO.Path]::GetFullPath([string]$entry.Value)
      $oldDocId = Get-DocsEditorDocIdFromMarkdownPath -Path $fromFullPath
      $newDocId = Get-DocsEditorDocIdFromMarkdownPath -Path $toFullPath
      if ([string]::IsNullOrWhiteSpace($oldDocId) -or $oldDocId -eq $newDocId) {
        continue
      }

      $escapedOldDocId = [regex]::Escape($oldDocId)
      $next = [regex]::Replace($updated, "(?im)(\bdocId\s*:\s*['""])$escapedOldDocId(['""])", ('$1{0}$2' -f $newDocId))
      if ($next -ne $updated) {
        $updated = $next
        $changed = $true
      }

      $next = [regex]::Replace($updated, "(?im)(\bid\s*:\s*['""])$escapedOldDocId(['""])", ('$1{0}$2' -f $newDocId))
      if ($next -ne $updated) {
        $updated = $next
        $changed = $true
      }

      $next = [regex]::Replace($updated, "(?im)(`"docId`"\s*:\s*`")$escapedOldDocId(`")", ('$1{0}$2' -f $newDocId))
      if ($next -ne $updated) {
        $updated = $next
        $changed = $true
      }

      $next = [regex]::Replace($updated, "(?im)(`"id`"\s*:\s*`")$escapedOldDocId(`")", ('$1{0}$2' -f $newDocId))
      if ($next -ne $updated) {
        $updated = $next
        $changed = $true
      }

      $next = [regex]::Replace($updated, "(?im)(\[\s*['""])$escapedOldDocId(['""])", ('$1{0}$2' -f $newDocId))
      if ($next -ne $updated) {
        $updated = $next
        $changed = $true
      }

      $next = [regex]::Replace($updated, "(?im)(,\s*['""])$escapedOldDocId(['""])", ('$1{0}$2' -f $newDocId))
      if ($next -ne $updated) {
        $updated = $next
        $changed = $true
      }
    }

    if ($changed -and $updated -ne $content) {
      Write-DocsEditorUtf8NoBomFile -Path $filePath -Content $updated
    }
  }
}

function Assert-DocsEditorMarkdownLinksResolvable {
  $docsRootFull = [System.IO.Path]::GetFullPath($script:DocsRoot).TrimEnd('\') + '\'
  $markdownFiles = @(Get-ChildItem -LiteralPath $script:DocsRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
  $linkPattern = '(!?\[[^\]]*\]\()(?<target><[^>]+>|[^)\r\n]*?\.md(?:[?#][^)\s]*)?)(?<suffix>(?:\s+(?:"[^"]*"|''[^'']*''|\([^)]+\)))?\))'
  $broken = New-Object System.Collections.Generic.List[string]

  foreach ($file in $markdownFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $containingDir = Split-Path -Path $file.FullName -Parent
    foreach ($match in [regex]::Matches($content, $linkPattern)) {
      $rawTarget = [string]$match.Groups['target'].Value
      $target = if ($rawTarget.StartsWith("<") -and $rawTarget.EndsWith(">")) {
        $rawTarget.Substring(1, $rawTarget.Length - 2)
      }
      else {
        $rawTarget
      }

      if (-not (Test-DocsEditorLocalMarkdownLink -Target $target)) {
        continue
      }

      $splitTarget = Split-DocsEditorMarkdownTarget -Target $target
      $targetPathForFilesystem = Decode-DocsEditorMarkdownPathForFilesystem -Path $splitTarget.Path
      $resolvedTarget = [System.IO.Path]::GetFullPath((Join-Path $containingDir $targetPathForFilesystem))
      if (-not $resolvedTarget.StartsWith($docsRootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativeSource = Get-RelativePathFromDocsRoot -FullPath $file.FullName
        $broken.Add(("{0} -> {1} (outside Docs/)" -f $relativeSource, $target)) | Out-Null
        continue
      }

      if (-not (Test-Path -LiteralPath $resolvedTarget -PathType Leaf)) {
        $relativeSource = Get-RelativePathFromDocsRoot -FullPath $file.FullName
        $broken.Add(("{0} -> {1}" -f $relativeSource, $target)) | Out-Null
      }
    }
  }

  if ($broken.Count -gt 0) {
    $preview = @($broken | Select-Object -First 12) -join ", "
    throw ("Move would break markdown links. Missing local markdown target(s): " + $preview)
  }
}

function Assert-DocsEditorDocIdReferencesResolvable {
  $websiteRoot = Join-Path $script:RepoRoot "website"
  if (-not (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    return
  }

  $docIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

  $configPath = Join-Path $websiteRoot "docusaurus.config.ts"
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configContent = Get-Content -LiteralPath $configPath -Raw
    foreach ($match in [regex]::Matches($configContent, "(?m)\bdocId\s*:\s*['""](?<id>[^'""]+)['""]")) {
      $docId = [string]$match.Groups['id'].Value
      if (-not [string]::IsNullOrWhiteSpace($docId)) {
        $docIds.Add($docId) | Out-Null
      }
    }
  }

  $sidebarsPath = Join-Path $websiteRoot "sidebars.ts"
  if (Test-Path -LiteralPath $sidebarsPath -PathType Leaf) {
    $sidebarsContent = Get-Content -LiteralPath $sidebarsPath -Raw

    foreach ($match in [regex]::Matches($sidebarsContent, "(?m)\bdocId\s*:\s*['""](?<id>[^'""]+)['""]")) {
      $docId = [string]$match.Groups['id'].Value
      if (-not [string]::IsNullOrWhiteSpace($docId)) {
        $docIds.Add($docId) | Out-Null
      }
    }
  }

  foreach ($categoryFile in @(Get-ChildItem -LiteralPath $script:DocsRoot -Filter "_category_.json" -File -Recurse -ErrorAction SilentlyContinue)) {
    try {
      $categoryJson = Get-Content -LiteralPath $categoryFile.FullName -Raw | ConvertFrom-Json
      if ($categoryJson -and $categoryJson.link -and ([string]$categoryJson.link.type).Trim().ToLowerInvariant() -eq "doc") {
        $docId = [string]$categoryJson.link.id
        if (-not [string]::IsNullOrWhiteSpace($docId)) {
          $docIds.Add($docId) | Out-Null
        }
      }
    }
    catch {
      throw "Failed to parse category metadata: $($categoryFile.FullName). $($_.Exception.Message)"
    }
  }

  if ($docIds.Count -eq 0) {
    return
  }

  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($docId in $docIds) {
    $pageCandidate = Join-Path $script:DocsRoot (($docId -replace '/', '\') + ".md")
    $sectionReadmeCandidate = Join-Path $script:DocsRoot (($docId -replace '/', '\') + "\README.md")
    if ((Test-Path -LiteralPath $pageCandidate -PathType Leaf) -or (Test-Path -LiteralPath $sectionReadmeCandidate -PathType Leaf)) {
      continue
    }

    $missing.Add($docId) | Out-Null
  }

  if ($missing.Count -gt 0) {
    throw ("Move would break docs references. Missing docId target(s): " + ($missing -join ", "))
  }
}

function Assert-DocsEditorMovedDocIdReferencesResolvable {
  param([Parameter(Mandatory)][hashtable]$MovedMarkdownPathMap)

  if ($MovedMarkdownPathMap.Count -eq 0) {
    return
  }

  $websiteRoot = Join-Path $script:RepoRoot "website"
  if (-not (Test-Path -LiteralPath $websiteRoot -PathType Container)) {
    return
  }

  $referencedDocIds = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  $configPath = Join-Path $websiteRoot "docusaurus.config.ts"
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configContent = Get-Content -LiteralPath $configPath -Raw
    foreach ($match in [regex]::Matches($configContent, "(?m)\bdocId\s*:\s*['""](?<id>[^'""]+)['""]")) {
      $docId = [string]$match.Groups['id'].Value
      if (-not [string]::IsNullOrWhiteSpace($docId)) {
        $referencedDocIds.Add($docId) | Out-Null
      }
    }
  }

  $sidebarsPath = Join-Path $websiteRoot "sidebars.ts"
  if (Test-Path -LiteralPath $sidebarsPath -PathType Leaf) {
    $sidebarsContent = Get-Content -LiteralPath $sidebarsPath -Raw
    foreach ($match in [regex]::Matches($sidebarsContent, "(?m)\bdocId\s*:\s*['""](?<id>[^'""]+)['""]")) {
      $docId = [string]$match.Groups['id'].Value
      if (-not [string]::IsNullOrWhiteSpace($docId)) {
        $referencedDocIds.Add($docId) | Out-Null
      }
    }
  }

  foreach ($categoryFile in @(Get-ChildItem -LiteralPath $script:DocsRoot -Filter "_category_.json" -File -Recurse -ErrorAction SilentlyContinue)) {
    try {
      $categoryJson = Get-Content -LiteralPath $categoryFile.FullName -Raw | ConvertFrom-Json
      if ($categoryJson -and $categoryJson.link -and ([string]$categoryJson.link.type).Trim().ToLowerInvariant() -eq "doc") {
        $docId = [string]$categoryJson.link.id
        if (-not [string]::IsNullOrWhiteSpace($docId)) {
          $referencedDocIds.Add($docId) | Out-Null
        }
      }
    }
    catch {
      throw "Failed to parse category metadata: $($categoryFile.FullName). $($_.Exception.Message)"
    }
  }

  foreach ($entry in $MovedMarkdownPathMap.GetEnumerator()) {
    $fromFullPath = [System.IO.Path]::GetFullPath([string]$entry.Key)
    $toFullPath = [System.IO.Path]::GetFullPath([string]$entry.Value)
    $oldDocId = Get-DocsEditorDocIdFromMarkdownPath -Path $fromFullPath
    $newDocId = Get-DocsEditorDocIdFromMarkdownPath -Path $toFullPath

    if ($referencedDocIds.Contains($oldDocId)) {
      throw ("Move would leave stale docs reference(s) pointing at moved docId: " + $oldDocId)
    }

    if ($referencedDocIds.Contains($newDocId)) {
      $pageCandidate = Join-Path $script:DocsRoot (($newDocId -replace '/', '\') + ".md")
      $sectionReadmeCandidate = Join-Path $script:DocsRoot (($newDocId -replace '/', '\') + "\README.md")
      if (-not (Test-Path -LiteralPath $pageCandidate -PathType Leaf) -and -not (Test-Path -LiteralPath $sectionReadmeCandidate -PathType Leaf)) {
        throw ("Move would break docs references. Missing moved docId target: " + $newDocId)
      }
    }
  }
}

function Normalize-SlugsForMovedItem {
  param(
    [Parameter(Mandatory)][string]$ItemPath,
    [Parameter(Mandatory)][string]$ItemType
  )

  if ($ItemType -eq "page") {
    return
  }

  Update-SectionCategoryDocLinkId -SectionDirectoryPath $ItemPath
}

function Get-DocsDomainSidebarId {
  param([AllowEmptyString()][string]$DomainPath)

  $normalized = ([string]$DomainPath).Trim().Replace('\', '/').Trim('/')
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return "general-sidebar"
  }

  $slug = [regex]::Replace($normalized, '([a-z0-9])([A-Z])', '$1-$2')
  $slug = [regex]::Replace($slug, '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($slug)) {
    return "docs-sidebar"
  }
  return "$slug-sidebar"
}

function Get-DocsDomainReadmePath {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  foreach ($candidateName in @("README.md", "README.mdx", "index.md", "index.mdx")) {
    $candidatePath = Join-Path $DirectoryPath $candidateName
    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
      return $candidatePath
    }
  }

  return $null
}

function Get-DocsDomainDisplayLabel {
  param(
    [Parameter(Mandatory)][string]$DirectoryPath,
    [Parameter(Mandatory)][string]$FallbackName
  )

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

  $readmePath = Get-DocsDomainReadmePath -DirectoryPath $DirectoryPath
  if ($readmePath) {
    try {
      $readmeText = Get-Content -LiteralPath $readmePath -Raw
      $title = Invoke-DocsModuleInternal -ScriptBlock {
        param($text)
        $frontMatter = Get-FrontMatterBlock -Content $text
        $resolvedTitle = Get-FrontMatterValue -FrontMatter $frontMatter -Key "title"
        if (-not [string]::IsNullOrWhiteSpace($resolvedTitle)) {
          return $resolvedTitle
        }
        $headingMatch = [regex]::Match($text, '(?m)^\#\s+(?<title>.+?)\s*$')
        if ($headingMatch.Success) {
          return $headingMatch.Groups['title'].Value.Trim()
        }
        return ""
      } -Arguments @($readmeText)

      if (-not [string]::IsNullOrWhiteSpace([string]$title)) {
        return [string]$title
      }
    }
    catch {
    }
  }

  return (ConvertTo-TitleWords $FallbackName)
}

function Get-DocsDomainDescription {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $readmePath = Get-DocsDomainReadmePath -DirectoryPath $DirectoryPath
  if (-not $readmePath) {
    return ""
  }

  try {
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    $description = Invoke-DocsModuleInternal -ScriptBlock {
      param($text)
      $frontMatter = Get-FrontMatterBlock -Content $text
      $value = Get-FrontMatterValue -FrontMatter $frontMatter -Key "description"
      return [string]$value
    } -Arguments @($readmeText)
    return [string]$description
  }
  catch {
    return ""
  }
}

function Get-DocsDomainPosition {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    return [double]::PositiveInfinity
  }

  try {
    $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
    if ($null -ne $categoryJson.position) {
      return [double]$categoryJson.position
    }
  }
  catch {
  }

  return [double]::PositiveInfinity
}

function Get-DocsDomainsConfigPath {
  return (Join-Path $script:DocsRoot "_domains.json")
}

function Get-DocsTopLevelDomainCandidateDirectories {
  return @(
    Get-ChildItem -LiteralPath $script:DocsRoot -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name |
      Where-Object { Test-DocsEditorFallbackSectionExists -DirectoryPath $_.FullName } |
      ForEach-Object { $_.Name }
  )
}

function Get-DocsTopLevelStandaloneDocIds {
  $files = @(
    Get-ChildItem -LiteralPath $script:DocsRoot -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Extension -in @(".md", ".mdx") -and
        -not $_.Name.Equals("README.md", [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $_.Name.Equals("README.mdx", [System.StringComparison]::OrdinalIgnoreCase)
      } |
      Sort-Object Name
  )

  return @(
    $files | ForEach-Object {
      $relative = Get-RelativePathFromDocsRoot -FullPath $_.FullName
      (($relative -replace '\.(md|mdx)$', '') -replace '\\', '/')
    }
  )
}

function Get-DefaultDocsDomainDefinitions {
  $topLevelDirectories = @(Get-DocsTopLevelDomainCandidateDirectories)
  $topLevelDocIds = @(Get-DocsTopLevelStandaloneDocIds)
  $standardNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($name in @("WorkflowStandards", "Workflow", "CodingStandards", "DocsSite", "AI", "AIContext", "Testing", "Pipeline", "Setup", "GitStandards", "UnrealStandards")) {
    $standardNames.Add($name) | Out-Null
  }

  $standardRoots = @($topLevelDirectories | Where-Object { $standardNames.Contains($_) })
  $projectRoots = @($topLevelDirectories | Where-Object { -not $standardNames.Contains($_) })
  $standardDocs = @($topLevelDocIds | Where-Object { $_ -in @("Setup", "Testing") })
  $projectDocs = @($topLevelDocIds | Where-Object { $_ -notin @("Setup", "Testing") })

  return @(
    [pscustomobject]@{
      key = "workflow-standards"
      path = "WorkflowStandards"
      label = "Workflow & Standards"
      sidebarId = "workflow-standards-sidebar"
      readmePath = "WorkflowStandards/README.md"
      description = "Best practices, setup guidance, and technical standards for the project."
      showLandingInSidebar = $false
      position = 10
      ownedRoots = @(@("WorkflowStandards") + $standardRoots | Select-Object -Unique)
      ownedDocs = $standardDocs
      catchAll = $false
    }
    [pscustomobject]@{
      key = "project-docs"
      path = "ProjectDocs"
      label = "Project Docs"
      sidebarId = "project-docs-sidebar"
      readmePath = "ProjectDocs/README.md"
      description = "Project-specific design, gameplay, and implementation documentation."
      showLandingInSidebar = $false
      position = 20
      ownedRoots = @(@("ProjectDocs") + $projectRoots | Select-Object -Unique)
      ownedDocs = $projectDocs
      catchAll = $true
    }
  )
}

function Read-DocsDomainsConfig {
  $configPath = Get-DocsDomainsConfigPath
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

function Get-DocsDomainDefinitions {
  $topLevelDirectories = @(Get-DocsTopLevelDomainCandidateDirectories)
  $topLevelDocIds = @(Get-DocsTopLevelStandaloneDocIds)
  $config = Read-DocsDomainsConfig
  $configuredDomains = @()
  if ($config -and $config.domains) {
    $configuredDomains = @($config.domains)
  }

  if ($configuredDomains.Count -eq 0) {
    $orderedDomains = @(Get-DefaultDocsDomainDefinitions)
  }
  else {
    $claimedRoots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $claimedDocs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $normalizedDomains = New-Object System.Collections.Generic.List[object]
    $standardNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @("WorkflowStandards", "Workflow", "CodingStandards", "DocsSite", "AI", "AIContext", "Testing", "Pipeline", "Setup", "GitStandards", "UnrealStandards")) {
      $standardNames.Add($name) | Out-Null
    }
    $index = 0
    foreach ($entry in $configuredDomains) {
      $index += 1
      $key = ([string]$entry.key).Trim()
      $pathValue = ([string]$entry.dirName).Trim()
      if ([string]::IsNullOrWhiteSpace($pathValue)) {
        $pathValue = ([string]$entry.path).Trim()
      }
      if ([string]::IsNullOrWhiteSpace($pathValue)) {
        $pathValue = "Domain$index"
      }

      if ([string]::IsNullOrWhiteSpace($key)) {
        $key = $pathValue
      }

      $ownedRoots = New-Object System.Collections.Generic.List[string]
      foreach ($root in @($entry.ownedRoots)) {
        $normalizedRoot = ([string]$root).Trim().Replace('\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($normalizedRoot)) {
          continue
        }
        if ($topLevelDirectories -contains $normalizedRoot) {
          $ownedRoots.Add($normalizedRoot) | Out-Null
          $claimedRoots.Add($normalizedRoot) | Out-Null
        }
      }

      $ownedDocs = New-Object System.Collections.Generic.List[string]
      foreach ($docId in @($entry.ownedDocs)) {
        $normalizedDocId = ([string]$docId).Trim().Replace('\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($normalizedDocId)) {
          continue
        }
        if ($topLevelDocIds -contains $normalizedDocId) {
          $ownedDocs.Add($normalizedDocId) | Out-Null
          $claimedDocs.Add($normalizedDocId) | Out-Null
        }
      }

      $landingDoc = ([string]$entry.landingDoc).Trim().Replace('\', '/').Trim('/')

      $normalizedDomains.Add([pscustomobject]@{
          key = $key
          path = $pathValue
          label = $(if ([string]::IsNullOrWhiteSpace([string]$entry.label)) { Get-DocsDomainDisplayLabel -DirectoryPath (Join-Path $script:DocsRoot $pathValue) -FallbackName $pathValue } else { [string]$entry.label })
          sidebarId = $(if ([string]::IsNullOrWhiteSpace([string]$entry.sidebarId)) { Get-DocsDomainSidebarId -DomainPath $key } else { [string]$entry.sidebarId })
          readmePath = $(if ([string]::IsNullOrWhiteSpace($landingDoc)) { "" } else { "$landingDoc.md" })
          description = [string]$entry.description
          showLandingInSidebar = [bool]$entry.showLandingInSidebar
          position = $(if ($null -ne $entry.position) { [double]$entry.position } else { [double]($index * 10) })
          ownedRoots = @($ownedRoots.ToArray())
          ownedDocs = @($ownedDocs.ToArray())
          catchAll = [bool]$entry.catchAll
        }) | Out-Null
    }

    $workflowDomain = $normalizedDomains.ToArray() | Where-Object { ([string]$_.key).Equals("workflow-standards", [System.StringComparison]::OrdinalIgnoreCase) -or ([string]$_.path).Equals("WorkflowStandards", [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($workflowDomain) {
      foreach ($root in $topLevelDirectories) {
        if ($standardNames.Contains($root) -and -not $claimedRoots.Contains($root) -and @($workflowDomain.ownedRoots) -notcontains $root) {
          $workflowDomain.ownedRoots = @(@($workflowDomain.ownedRoots) + $root)
          $claimedRoots.Add($root) | Out-Null
        }
      }
      foreach ($docId in $topLevelDocIds) {
        if (($docId -in @("Setup", "Testing")) -and -not $claimedDocs.Contains($docId) -and @($workflowDomain.ownedDocs) -notcontains $docId) {
          $workflowDomain.ownedDocs = @(@($workflowDomain.ownedDocs) + $docId)
          $claimedDocs.Add($docId) | Out-Null
        }
      }
    }

    $catchAllDomain = $normalizedDomains.ToArray() | Where-Object { $_.catchAll } | Select-Object -First 1
    if ($catchAllDomain) {
      foreach ($root in $topLevelDirectories) {
        if (-not $claimedRoots.Contains($root) -and @($catchAllDomain.ownedRoots) -notcontains $root) {
          $catchAllDomain.ownedRoots = @(@($catchAllDomain.ownedRoots) + $root)
        }
      }
      foreach ($docId in $topLevelDocIds) {
        if (-not $claimedDocs.Contains($docId) -and @($catchAllDomain.ownedDocs) -notcontains $docId) {
          $catchAllDomain.ownedDocs = @(@($catchAllDomain.ownedDocs) + $docId)
        }
      }
    }

    $orderedDomains = @($normalizedDomains.ToArray() | Sort-Object position, label)
  }

  return [ordered]@{
    domains = @($orderedDomains | ForEach-Object {
        [ordered]@{
          key = [string]$_.key
          path = [string]$_.path
          label = [string]$_.label
          sidebarId = [string]$_.sidebarId
          readmePath = [string]$_.readmePath
          description = [string]$_.description
          showLandingInSidebar = [bool]$_.showLandingInSidebar
          position = [double]$_.position
          ownedRoots = @($_.ownedRoots)
          ownedDocs = @($_.ownedDocs)
          catchAll = [bool]$_.catchAll
        }
      })
    generalDomain = $null
  }
}

function Get-DocsTree {
  param(
    [AllowEmptyString()][string]$RootPath,
    [switch]$GeneralOnly,
    [AllowEmptyString()][string]$SidebarId
  )

  if ($GeneralOnly) {
    return [ordered]@{
      root = "General"
      sidebarId = "general-sidebar"
      children = @(Get-DocsTreeChildren -ParentDir $script:DocsRoot -PagesOnly:$true)
    }
  }

  if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if (-not [string]::IsNullOrWhiteSpace($SidebarId)) {
      $definitions = Get-DocsDomainDefinitions
      $domain = @($definitions.domains | Where-Object { ([string]$_.sidebarId).Equals($SidebarId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
      if (-not $domain) {
        throw "Unknown docs domain sidebar: $SidebarId"
      }

      $children = New-Object System.Collections.Generic.List[object]
      $ownedRoots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
      foreach ($root in @($domain.ownedRoots)) {
        $normalizedRoot = ([string]$root).Trim().Replace('\', '/').Trim('/')
        if (-not [string]::IsNullOrWhiteSpace($normalizedRoot)) {
          $ownedRoots.Add($normalizedRoot) | Out-Null
        }
      }

      $ownedDocs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
      foreach ($docId in @($domain.ownedDocs)) {
        $normalizedDocId = ([string]$docId).Trim().Replace('\', '/').Trim('/')
        if (-not [string]::IsNullOrWhiteSpace($normalizedDocId)) {
          $ownedDocs.Add($normalizedDocId) | Out-Null
        }
      }

      $normalizedDomainPath = ([string]$domain.path).Trim().Replace('\', '/').Trim('/')
      foreach ($topLevelNode in @(Get-DocsTreeChildren -ParentDir $script:DocsRoot)) {
        if ([string]$topLevelNode.type -eq "page") {
          $docToken = ([string]$topLevelNode.path).Trim().Replace('\', '/').Trim('/')
          if ($docToken.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
            $docToken = $docToken.Substring(0, $docToken.Length - 3)
          }
          if ($ownedDocs.Contains($docToken)) {
            $children.Add($topLevelNode) | Out-Null
          }
          continue
        }

        $rootToken = ([string]$topLevelNode.path).Trim().Replace('\', '/').Trim('/')
        if (-not $ownedRoots.Contains($rootToken)) {
          continue
        }

        if ($rootToken.Equals($normalizedDomainPath, [System.StringComparison]::OrdinalIgnoreCase)) {
          if ([bool]$domain.showLandingInSidebar -and -not [string]::IsNullOrWhiteSpace([string]$domain.readmePath)) {
            $landingPath = ([string]$domain.readmePath).Trim().Replace('\', '/')
            if ($landingPath.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
              $landingPath = $landingPath.Substring(0, $landingPath.Length - 3)
            }
            $children.Add([ordered]@{
                type = "page"
                path = $landingPath
                name = [string]$domain.label
                position = [double]$topLevelNode.position
                unlisted = (Test-DocsFrontMatterUnlisted -Content (Get-Content -LiteralPath (Get-DocsVisibilityTargetPagePath -PathToken $landingPath) -Raw))
              }) | Out-Null
          }
          foreach ($childNode in @($topLevelNode.children)) {
            $children.Add($childNode) | Out-Null
          }
          continue
        }

        $children.Add($topLevelNode) | Out-Null
      }

      return [ordered]@{
        root = [string]$domain.label
        domainPath = [string]$domain.path
        sidebarId = [string]$domain.sidebarId
        children = @($children.ToArray())
      }
    }

    return [ordered]@{
      root = "Docs"
      children = @(Get-DocsTreeChildren -ParentDir $script:DocsRoot)
    }
  }

  $fullRootPath = Resolve-DocsPathFromToken -PathToken $RootPath -RequireExisting
  if (-not (Test-Path -LiteralPath $fullRootPath -PathType Container)) {
    throw "Unknown docs domain root: $RootPath"
  }

  return [ordered]@{
    root = $RootPath
    domainPath = $RootPath
    sidebarId = (Get-DocsDomainSidebarId -DomainPath $RootPath)
    children = @(Get-DocsTreeChildren -ParentDir $fullRootPath)
  }
}

function Test-DocsEditorCategoryUsesReadmeLink {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $linkInfo = Get-DocsEditorCategoryLinkInfo -DirectoryPath $DirectoryPath
  if ($null -eq $linkInfo) {
    return $false
  }

  $linkType = ([string]$linkInfo.LinkType).Trim().ToLowerInvariant()
  if ($linkType -ne "doc") {
    return $false
  }

  $linkId = ([string]$linkInfo.LinkId).Trim().Replace('\', '/')
  return $linkId.EndsWith("/README", [System.StringComparison]::OrdinalIgnoreCase) -or $linkId.Equals("README", [System.StringComparison]::OrdinalIgnoreCase)
}

function Add-DocsEditorFallbackTreeSiblings {
  param(
    [System.Collections.Generic.List[object]]$Siblings,
    [Parameter(Mandatory)][string]$ParentDir
  )

  $seenPaths = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($sibling in $Siblings) {
    [void]$seenPaths.Add((Get-DocsEditorPathKey -Path ([string]$sibling.FullPath)))
  }

  $fallbackPosition = 100000.0
  $readmeIsCategoryLink = Test-DocsEditorCategoryUsesReadmeLink -DirectoryPath $ParentDir
  foreach ($markdownFile in @(Get-ChildItem -LiteralPath $ParentDir -File -Filter *.md -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if ($readmeIsCategoryLink -and $markdownFile.Name.Equals("README.md", [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }

    $pathKey = Get-DocsEditorPathKey -Path $markdownFile.FullName
    if ($seenPaths.Contains($pathKey)) {
      continue
    }

    $Siblings.Add([pscustomobject]@{
        ItemType = "page"
        FullPath = $markdownFile.FullName
        ParentDir = $ParentDir
        RelativePath = (Get-RelativePathFromDocsRoot -FullPath $markdownFile.FullName)
        Position = $fallbackPosition
      }) | Out-Null
    $fallbackPosition += 1.0
  }

  foreach ($childDir in @(Get-ChildItem -LiteralPath $ParentDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if (-not (Test-DocsEditorFallbackSectionExists -DirectoryPath $childDir.FullName)) {
      continue
    }

    $pathKey = Get-DocsEditorPathKey -Path $childDir.FullName
    if ($seenPaths.Contains($pathKey)) {
      continue
    }

    $Siblings.Add([pscustomobject]@{
        ItemType = "section"
        FullPath = $childDir.FullName
        ParentDir = $ParentDir
        RelativePath = (Get-RelativePathFromDocsRoot -FullPath $childDir.FullName)
        Position = $fallbackPosition
      }) | Out-Null
    $fallbackPosition += 1.0
  }
}

function Test-DocsEditorFallbackSectionExists {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
    return $true
  }

  $directMarkdown = @(Get-ChildItem -LiteralPath $DirectoryPath -File -Filter *.md -ErrorAction SilentlyContinue)
  if ($directMarkdown.Count -gt 0) {
    return $true
  }

  $nestedMarkdown = Get-ChildItem -LiteralPath $DirectoryPath -Recurse -File -Filter *.md -ErrorAction SilentlyContinue | Select-Object -First 1
  return $null -ne $nestedMarkdown
}

function Get-DocsTreeChildren {
  param(
    [Parameter(Mandatory)][string]$ParentDir,
    [switch]$PagesOnly
  )

  $categoryLinkedMarkdownPath = Get-DocsEditorCategoryLinkedMarkdownPath -DirectoryPath $ParentDir
  $categoryLinkedMarkdownFullPath = if ([string]::IsNullOrWhiteSpace([string]$categoryLinkedMarkdownPath)) {
    ""
  }
  else {
    [System.IO.Path]::GetFullPath([string]$categoryLinkedMarkdownPath)
  }

  $siblings = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in @(Invoke-DocsModuleInternal -ScriptBlock {
      param($docsRootPath, $parentDirectory)
      Get-DocsNavigationSiblings -DocsRoot $docsRootPath -ParentDir $parentDirectory
    } -Arguments @($script:DocsRoot, $ParentDir))) {
    $siblings.Add($sibling) | Out-Null
  }
  Add-DocsEditorFallbackTreeSiblings -Siblings $siblings -ParentDir $ParentDir

  $sortedSiblings = if ($PagesOnly) {
    @($siblings.ToArray() | Where-Object { ([string]$_.ItemType) -eq "page" } | Sort-Object Position, RelativePath)
  }
  else {
    @($siblings.ToArray() | Sort-Object Position, RelativePath)
  }

  $nodes = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in $sortedSiblings) {
    $itemType = [string]$sibling.ItemType
    $fullPath = [string]$sibling.FullPath
    $relativePath = [string]$sibling.RelativePath
    $position = [double]$sibling.Position
    $displayName = ""

    if ($itemType -eq "page" -and -not [string]::IsNullOrWhiteSpace($categoryLinkedMarkdownFullPath)) {
      $pageFullPath = [System.IO.Path]::GetFullPath($fullPath)
      if ($pageFullPath.Equals($categoryLinkedMarkdownFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
      }
    }

    if ($itemType -eq "section") {
      $categoryPath = Join-Path $fullPath "_category_.json"
      if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
        try {
          $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
          $displayName = [string]$categoryJson.label
        }
        catch {
          $displayName = [System.IO.Path]::GetFileName($fullPath)
        }
      }
      elseif (Test-Path -LiteralPath (Join-Path $fullPath "README.md") -PathType Leaf) {
        try {
          $readmeText = Get-Content -LiteralPath (Join-Path $fullPath "README.md") -Raw
          $displayName = Invoke-DocsModuleInternal -ScriptBlock {
            param($text, $fallbackPath)
            $frontMatter = Get-FrontMatterBlock -Content $text
            $title = Get-FrontMatterValue -FrontMatter $frontMatter -Key "title"
            if ([string]::IsNullOrWhiteSpace($title)) {
              $headingMatch = [regex]::Match($text, '(?m)^\#\s+(?<title>.+?)\s*$')
              if ($headingMatch.Success) {
                return $headingMatch.Groups['title'].Value.Trim()
              }
              return [System.IO.Path]::GetFileName($fallbackPath)
            }
            return $title
          } -Arguments @($readmeText, $fullPath)
        }
        catch {
          $displayName = [System.IO.Path]::GetFileName($fullPath)
        }
      }
      if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = [System.IO.Path]::GetFileName($fullPath)
      }

      $nodes.Add([ordered]@{
          type = "section"
          path = $relativePath
          name = $displayName
          position = $position
          children = @(Get-DocsTreeChildren -ParentDir $fullPath)
        }) | Out-Null
      continue
    }

    $pageText = Get-Content -LiteralPath $fullPath -Raw
    $displayName = Invoke-DocsModuleInternal -ScriptBlock {
      param($text, $fallbackPath)
      $frontMatter = Get-FrontMatterBlock -Content $text
      $title = Get-FrontMatterValue -FrontMatter $frontMatter -Key "title"
      if ([string]::IsNullOrWhiteSpace($title)) {
        return [System.IO.Path]::GetFileNameWithoutExtension($fallbackPath)
      }
      return $title
    } -Arguments @($pageText, $fullPath)

    $nodes.Add([ordered]@{
        type = "page"
        path = $relativePath
        name = [string]$displayName
        position = $position
        unlisted = (Test-DocsFrontMatterUnlisted -Content $pageText)
      }) | Out-Null
  }

  return @($nodes.ToArray())
}

function Get-DocsContent {
  param([Parameter(Mandatory)][string]$PathToken)

  $pagePath = Resolve-PagePathFromToken -PathToken $PathToken -RequireExisting
  $content = Get-Content -LiteralPath $pagePath -Raw
  $mtime = (Get-Item -LiteralPath $pagePath).LastWriteTimeUtc.ToString("o")
  return [ordered]@{
    path = (Get-RelativePathFromDocsRoot -FullPath $pagePath)
    content = $content
    hash = (Get-JsonHash -Value $content)
    modifiedUtc = $mtime
  }
}

function Test-UnsupportedMdx {
  param([AllowEmptyString()][string]$Content)

  if ($null -eq $Content) {
    return $false
  }

  if ($Content -match '(?m)^\s*(import|export)\s+') {
    return $true
  }

  return $false
}

function Save-DocsContent {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
    [string]$ExpectedHash
  )

  $pagePath = Resolve-PagePathFromToken -PathToken $PathToken -RequireExisting
  $current = Get-Content -LiteralPath $pagePath -Raw
  $currentHash = Get-JsonHash -Value $current

  if (-not [string]::IsNullOrWhiteSpace($ExpectedHash) -and $ExpectedHash -ne $currentHash) {
    throw [System.InvalidOperationException]::new("Content conflict detected. File was changed by another process.")
  }

  if (Test-UnsupportedMdx -Content $Content) {
    throw [System.InvalidOperationException]::new("Save blocked: import/export statements are not supported by the in-browser editor. Edit this file in your code editor.")
  }

  Write-DocsEditorUtf8NoBomFile -Path $pagePath -Content $Content

  $updated = Get-Content -LiteralPath $pagePath -Raw
  return [ordered]@{
    path = (Get-RelativePathFromDocsRoot -FullPath $pagePath)
    hash = (Get-JsonHash -Value $updated)
    modifiedUtc = (Get-Item -LiteralPath $pagePath).LastWriteTimeUtc.ToString("o")
  }
}

function Get-DocsVisibilityTargetPagePath {
  param([Parameter(Mandatory)][string]$PathToken)

  $resolvedPath = Resolve-DocsPathFromToken -PathToken $PathToken -RequireExisting:$false
  if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
    foreach ($candidateName in @("README.md", "README.mdx", "index.md", "index.mdx")) {
      $candidatePath = Join-Path $resolvedPath $candidateName
      if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        return $candidatePath
      }
    }

    throw "No landing document exists for '$PathToken'."
  }

  if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
    return $resolvedPath
  }

  foreach ($extension in @(".md", ".mdx")) {
    $candidatePath = Resolve-DocsPathFromToken -PathToken ($PathToken.TrimEnd("/") + $extension) -RequireExisting:$false
    if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
      return $candidatePath
    }
  }

  throw "Docs page or landing document not found: $PathToken"
}

function Test-DocsFrontMatterUnlisted {
  param([AllowEmptyString()][string]$Content)

  if ([string]::IsNullOrWhiteSpace($Content)) {
    return $false
  }

  $match = [regex]::Match($Content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---')
  if (-not $match.Success) {
    return $false
  }

  $frontMatter = $match.Groups['frontMatter'].Value
  $valueMatch = [regex]::Match($frontMatter, '(?mi)^\s*unlisted\s*:\s*(?<value>.+?)\s*$')
  if (-not $valueMatch.Success) {
    return $false
  }

  $value = $valueMatch.Groups['value'].Value.Trim().Trim("'`"")
  return $value.Equals("true", [System.StringComparison]::OrdinalIgnoreCase)
}

function Set-DocsPageVisibility {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [Parameter(Mandatory)][bool]$Hidden
  )

  $pagePath = Get-DocsVisibilityTargetPagePath -PathToken $PathToken
  $content = Get-Content -LiteralPath $pagePath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')

  if ($match.Success) {
    $frontMatter = $match.Groups['frontMatter'].Value
    $rest = $match.Groups['rest'].Value

    if ($Hidden) {
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

    Write-DocsEditorUtf8NoBomFile -Path $pagePath -Content $updatedContent
  }
  else {
    if ($Hidden) {
      $trimmedBody = $content.TrimStart("`r", "`n")
      $updatedContent = @(
        '---'
        'unlisted: true'
        '---'
        ''
        $trimmedBody
      ) -join $newline
      Write-DocsEditorUtf8NoBomFile -Path $pagePath -Content $updatedContent
    }
  }

  $updated = Get-Content -LiteralPath $pagePath -Raw
  return [ordered]@{
    path = (Get-RelativePathFromDocsRoot -FullPath $pagePath)
    hidden = (Test-DocsFrontMatterUnlisted -Content $updated)
    hash = (Get-JsonHash -Value $updated)
    modifiedUtc = (Get-Item -LiteralPath $pagePath).LastWriteTimeUtc.ToString("o")
  }
}

function Set-DocsEditorFrontMatterValue {
  param(
    [Parameter(Mandatory)][string]$PagePath,
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$Value
  )

  $content = Get-Content -LiteralPath $PagePath -Raw
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  $match = [regex]::Match($content, '(?s)\A---\s*\r?\n(?<frontMatter>.*?)\r?\n---(?<rest>(?:\r?\n|$).*)\z')
  $escapedValue = $Value.Replace("`r", " ").Replace("`n", " ").Trim()

  if ($match.Success) {
    $frontMatter = $match.Groups['frontMatter'].Value
    $rest = $match.Groups['rest'].Value
    $updatedFrontMatter = if ($frontMatter -match "(?mi)^\s*$Key\s*:") {
      [regex]::Replace($frontMatter, "(?mi)^\s*$Key\s*:\s*.+$", "${Key}: $escapedValue", 1)
    }
    else {
      if ([string]::IsNullOrWhiteSpace($frontMatter.Trim())) {
        "${Key}: $escapedValue"
      }
      else {
        $frontMatter.TrimEnd("`r", "`n") + $newline + "${Key}: $escapedValue"
      }
    }

    $updatedContent = "---$newline$updatedFrontMatter$newline---$rest"
    Write-DocsEditorUtf8NoBomFile -Path $PagePath -Content $updatedContent
    return
  }

  $trimmedBody = $content.TrimStart("`r", "`n")
  $updatedContent = @(
    '---'
    "${Key}: $escapedValue"
    '---'
    ''
    $trimmedBody
  ) -join $newline
  Write-DocsEditorUtf8NoBomFile -Path $PagePath -Content $updatedContent
}

function Update-DocsNodeMetadata {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [AllowEmptyString()][string]$Title,
    [AllowEmptyString()][string]$Label
  )

  $target = Resolve-DocsEditorNavigationTarget -PathToken $PathToken

  $itemType = [string]$target.ItemType
  if ($itemType -eq "page") {
    if ([string]::IsNullOrWhiteSpace($Title)) {
      throw "A page title is required."
    }

    Set-DocsEditorFrontMatterValue -PagePath ([string]$target.FullPath) -Key "title" -Value $Title
    $updated = Get-Content -LiteralPath ([string]$target.FullPath) -Raw
    return [ordered]@{
      path = (Get-RelativePathFromDocsRoot -FullPath ([string]$target.FullPath))
      type = "page"
      name = [string]$Title
      hidden = (Test-DocsFrontMatterUnlisted -Content $updated)
      hash = (Get-JsonHash -Value $updated)
      modifiedUtc = (Get-Item -LiteralPath ([string]$target.FullPath)).LastWriteTimeUtc.ToString("o")
    }
  }

  if ($itemType -ne "section") {
    throw "Unsupported navigation target: $itemType"
  }

  $nextLabel = if ([string]::IsNullOrWhiteSpace($Label)) { $Title } else { $Label }
  if ([string]::IsNullOrWhiteSpace($nextLabel)) {
    throw "A section label is required."
  }

  $sectionDir = [string]$target.FullPath
  $categoryPath = Join-Path $sectionDir "_category_.json"
  $category = [ordered]@{}
  if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
    try {
      $category = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
      $category = [ordered]@{}
    }
  }

  $category["label"] = $nextLabel
  Write-DocsEditorUtf8NoBomFile -Path $categoryPath -Content (($category | ConvertTo-Json -Depth 20) + "`r`n")

  $readmePath = Get-DocsDomainReadmePath -DirectoryPath $sectionDir
  if ($readmePath) {
    Set-DocsEditorFrontMatterValue -PagePath $readmePath -Key "title" -Value $nextLabel
  }

  return [ordered]@{
    path = (Get-RelativePathFromDocsRoot -FullPath $sectionDir)
    type = "section"
    name = [string]$nextLabel
    modifiedUtc = (Get-Item -LiteralPath $categoryPath).LastWriteTimeUtc.ToString("o")
  }
}

function Create-DocsPage {
  param(
    [string]$DomainPath,
    [string]$SectionPath,
    [Parameter(Mandatory)][string]$PageName,
    [string]$Title
  )

  $args = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($SectionPath)) {
    $args.Add($SectionPath) | Out-Null
  }
  $args.Add($PageName) | Out-Null
  $args.Add("-NoToc") | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $args.Add("-Title") | Out-Null
    $args.Add($Title) | Out-Null
  }

  $result = Invoke-DocsModuleInternal -ScriptBlock {
    param($resolvedRepoRoot, $cliArgs)
    Invoke-NewPage -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $cliArgs
  } -Arguments @($script:RepoRoot, @($args.ToArray()))

  $relativePath = Get-RelativePathFromDocsRoot -FullPath ([string]$result.Path)
  Set-DocsDomainOwnerForTopLevelItem -DomainPath $DomainPath -PathToken $relativePath -ItemType "page" | Out-Null
  return [ordered]@{
    path = $relativePath
  }
}

function Create-DocsSection {
  param(
    [string]$DomainPath,
    [string]$ParentPath,
    [Parameter(Mandatory)][string]$SectionName,
    [string]$Title,
    [string]$LinkType,
    [string]$GeneratedIndexTitle,
    [string]$GeneratedIndexSlug,
    [string]$GeneratedIndexDescription,
    [string]$DisplayedSidebar
  )

  $sectionPath = if ([string]::IsNullOrWhiteSpace($ParentPath)) {
    $SectionName
  }
  else {
    ((($ParentPath.Trim().Trim('/')) + "/" + $SectionName).Trim('/'))
  }

  $args = New-Object System.Collections.Generic.List[string]
  $args.Add($sectionPath) | Out-Null
  $args.Add("-NoToc") | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $args.Add("-Title") | Out-Null
    $args.Add($Title) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($LinkType)) {
    $args.Add("-LinkType") | Out-Null
    $args.Add($LinkType) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexTitle)) {
    $args.Add("-GeneratedIndexTitle") | Out-Null
    $args.Add($GeneratedIndexTitle) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexSlug)) {
    $args.Add("-GeneratedIndexSlug") | Out-Null
    $args.Add($GeneratedIndexSlug) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($GeneratedIndexDescription)) {
    $args.Add("-GeneratedIndexDescription") | Out-Null
    $args.Add($GeneratedIndexDescription) | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($DisplayedSidebar)) {
    $args.Add("-DisplayedSidebar") | Out-Null
    $args.Add($DisplayedSidebar) | Out-Null
  }

  $result = Invoke-DocsModuleInternal -ScriptBlock {
    param($resolvedRepoRoot, $cliArgs)
    Invoke-NewSection -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $cliArgs
  } -Arguments @($script:RepoRoot, @($args.ToArray()))

  $sectionDir = [string]$result.Path
  $relativeSectionPath = Get-RelativePathFromDocsRoot -FullPath $sectionDir
  Set-DocsDomainOwnerForTopLevelItem -DomainPath $DomainPath -PathToken $relativeSectionPath -ItemType "section" | Out-Null
  return [ordered]@{
    path = $relativeSectionPath
  }
}

function Touch-DocsWebsiteNavigationFiles {
  $websiteRoot = Join-Path $script:RepoRoot "website"
  foreach ($relativePath in @("domainCatalog.ts", "sidebars.ts", "docusaurus.config.ts")) {
    $fullPath = Join-Path $websiteRoot $relativePath
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
      [System.IO.File]::SetLastWriteTimeUtc($fullPath, [DateTime]::UtcNow)
    }
  }
}

function Write-DocsDomainsConfig {
  param([Parameter(Mandatory)][object[]]$Domains)

  $configPath = Get-DocsDomainsConfigPath
  $document = [ordered]@{
    schemaVersion = 1
    domains = @($Domains | ForEach-Object {
        $landingDoc = ([string]$_.readmePath).Replace('\', '/')
        if ($landingDoc.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
          $landingDoc = $landingDoc.Substring(0, $landingDoc.Length - 3)
        }

        [ordered]@{
          key = [string]$_.key
          dirName = [string]$_.path
          sidebarId = [string]$_.sidebarId
          label = [string]$_.label
          position = [double]$_.position
          landingDoc = $landingDoc
          description = [string]$_.description
          showLandingInSidebar = [bool]$_.showLandingInSidebar
          ownedRoots = @($_.ownedRoots)
          ownedDocs = @($_.ownedDocs)
          catchAll = [bool]$_.catchAll
        }
      })
  }

  $json = ($document | ConvertTo-Json -Depth 20) + "`r`n"
  Write-DocsEditorUtf8NoBomFile -Path $configPath -Content $json
}

function Get-DocsTopLevelOwnershipBinding {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [Parameter(Mandatory)][string]$ItemType
  )

  $normalizedPath = ([string]$PathToken).Trim().Replace('\', '/').Trim('/')
  if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
    return $null
  }

  $segments = @($normalizedPath -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($segments.Count -ne 1) {
    return $null
  }

  if ($ItemType -eq "section") {
    return [ordered]@{
      kind = "root"
      token = $segments[0]
    }
  }

  if ($ItemType -eq "page") {
    $docToken = $segments[0]
    if ($docToken.EndsWith(".mdx", [System.StringComparison]::OrdinalIgnoreCase)) {
      $docToken = $docToken.Substring(0, $docToken.Length - 4)
    }
    elseif ($docToken.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
      $docToken = $docToken.Substring(0, $docToken.Length - 3)
    }

    if ([string]::IsNullOrWhiteSpace($docToken)) {
      return $null
    }

    return [ordered]@{
      kind = "doc"
      token = $docToken
    }
  }

  return $null
}

function Set-DocsDomainOwnerForTopLevelItem {
  param(
    [string]$DomainPath,
    [Parameter(Mandatory)][string]$PathToken,
    [Parameter(Mandatory)][string]$ItemType
  )

  $normalizedDomainPath = ([string]$DomainPath).Trim().Replace('\', '/').Trim('/')
  if ([string]::IsNullOrWhiteSpace($normalizedDomainPath)) {
    return $false
  }

  $binding = Get-DocsTopLevelOwnershipBinding -PathToken $PathToken -ItemType $ItemType
  if ($null -eq $binding) {
    return $false
  }

  $definitions = Get-DocsDomainDefinitions
  $domains = @($definitions.domains | Sort-Object position, label)
  $domainFound = $false
  $nextDomains = New-Object System.Collections.Generic.List[object]

  foreach ($domain in $domains) {
    $currentDomainPath = ([string]$domain.path).Trim().Replace('\', '/').Trim('/')
    $ownedRoots = @(
      @($domain.ownedRoots) |
        ForEach-Object { ([string]$_).Trim().Replace('\', '/').Trim('/') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )
    $ownedDocs = @(
      @($domain.ownedDocs) |
        ForEach-Object { ([string]$_).Trim().Replace('\', '/').Trim('/') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    )

    if ($binding.kind -eq "root") {
      $ownedRoots = @($ownedRoots | Where-Object { -not ([string]$_).Equals([string]$binding.token, [System.StringComparison]::OrdinalIgnoreCase) })
    }
    else {
      $ownedDocs = @($ownedDocs | Where-Object { -not ([string]$_).Equals([string]$binding.token, [System.StringComparison]::OrdinalIgnoreCase) })
    }

    if ($currentDomainPath.Equals($normalizedDomainPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      $domainFound = $true
      if ($binding.kind -eq "root") {
        if (@($ownedRoots) -notcontains [string]$binding.token) {
          $ownedRoots = @($ownedRoots + [string]$binding.token)
        }
      }
      else {
        if (@($ownedDocs) -notcontains [string]$binding.token) {
          $ownedDocs = @($ownedDocs + [string]$binding.token)
        }
      }
    }

    $nextDomains.Add([pscustomobject]@{
        key = [string]$domain.key
        path = [string]$domain.path
        label = [string]$domain.label
        sidebarId = [string]$domain.sidebarId
        readmePath = [string]$domain.readmePath
        description = [string]$domain.description
        showLandingInSidebar = [bool]$domain.showLandingInSidebar
        position = [double]$domain.position
        ownedRoots = @($ownedRoots)
        ownedDocs = @($ownedDocs)
        catchAll = [bool]$domain.catchAll
      }) | Out-Null
  }

  if (-not $domainFound) {
    throw "Domain not found: $DomainPath"
  }

  Write-DocsDomainsConfig -Domains @($nextDomains.ToArray())
  Touch-DocsWebsiteNavigationFiles
  return $true
}

function Create-DocsDomain {
  param(
    [Parameter(Mandatory)][string]$DomainName,
    [string]$Title,
    [string]$Description,
    [bool]$CreateLandingPage = $true
  )

  $sidebarId = Get-DocsDomainSidebarId -DomainPath $DomainName
  $created = Create-DocsSection `
    -ParentPath "" `
    -SectionName $DomainName `
    -Title $(if ([string]::IsNullOrWhiteSpace($Title)) { $DomainName } else { $Title }) `
    -LinkType $(if ($CreateLandingPage) { "doc" } else { "none" }) `
    -DisplayedSidebar $sidebarId

  if ($CreateLandingPage -and -not [string]::IsNullOrWhiteSpace($Description)) {
    $readmePath = Join-Path $script:DocsRoot ($created.path.Replace('/', '\'))
    $readmePath = Join-Path $readmePath "README.md"
    if (Test-Path -LiteralPath $readmePath -PathType Leaf) {
      $content = Get-Content -LiteralPath $readmePath -Raw
      $updated = Invoke-DocsModuleInternal -ScriptBlock {
        param($text, $description)
        $frontMatter = Get-FrontMatterBlock -Content $text
        if ([string]::IsNullOrWhiteSpace($frontMatter)) {
          return $text
        }

        $newline = if ($frontMatter.Contains("`r`n")) { "`r`n" } else { "`n" }
        $updatedFrontMatter = $frontMatter
        if ($frontMatter -match '(?m)^\s*description\s*:') {
          $updatedFrontMatter = [regex]::Replace($frontMatter, '(?m)^\s*description\s*:\s*.+$', "description: $description", 1)
        }
        else {
          $updatedFrontMatter = $frontMatter.TrimEnd() + $newline + "description: $description"
        }
        return $text.Replace($frontMatter, $updatedFrontMatter)
      } -Arguments @($content, $Description)
      Write-DocsEditorUtf8NoBomFile -Path $readmePath -Content $updated
    }
  }

  $existingDefinitions = Get-DocsDomainDefinitions
  $nextDomains = New-Object System.Collections.Generic.List[object]
  foreach ($domain in @($existingDefinitions.domains)) {
    $ownedRoots = @($domain.ownedRoots | Where-Object {
        -not ([string]$_).Equals($DomainName, [System.StringComparison]::OrdinalIgnoreCase)
      })
    $nextDomains.Add([pscustomobject]@{
        key = [string]$domain.key
        path = [string]$domain.path
        label = [string]$domain.label
        sidebarId = [string]$domain.sidebarId
        readmePath = [string]$domain.readmePath
        description = [string]$domain.description
        showLandingInSidebar = [bool]$domain.showLandingInSidebar
        position = [double]$domain.position
        ownedRoots = @($ownedRoots)
        ownedDocs = @($domain.ownedDocs)
        catchAll = [bool]$domain.catchAll
      }) | Out-Null
  }

  if (-not @($nextDomains.ToArray() | Where-Object { ([string]$_.sidebarId).Equals($sidebarId, [System.StringComparison]::OrdinalIgnoreCase) }).Count) {
    $nextDomains.Add([pscustomobject]@{
        key = $DomainName
        path = $DomainName
        label = $(if ([string]::IsNullOrWhiteSpace($Title)) { $DomainName } else { $Title })
        sidebarId = $sidebarId
        readmePath = $(if ($CreateLandingPage) { "$DomainName/README.md" } else { "" })
        description = [string]$Description
        showLandingInSidebar = $false
        position = [double](10 * ($nextDomains.Count + 1))
        ownedRoots = @($DomainName)
        ownedDocs = @()
        catchAll = $false
      }) | Out-Null
  }

  Write-DocsDomainsConfig -Domains @($nextDomains.ToArray())
  Touch-DocsWebsiteNavigationFiles
  return [ordered]@{
    path = [string]$created.path
    sidebarId = $sidebarId
  }
}

function Move-DocsDomain {
  param(
    [Parameter(Mandatory)][string]$DomainPath,
    [Parameter(Mandatory)][ValidateSet("up", "down")][string]$Direction
  )

  $definitions = Get-DocsDomainDefinitions
  $orderedDomains = New-Object System.Collections.Generic.List[object]
  foreach ($domain in @($definitions.domains | Sort-Object position, label)) {
    $orderedDomains.Add([pscustomobject]@{
        key = [string]$domain.key
        path = [string]$domain.path
        label = [string]$domain.label
        sidebarId = [string]$domain.sidebarId
        readmePath = [string]$domain.readmePath
        description = [string]$domain.description
        showLandingInSidebar = [bool]$domain.showLandingInSidebar
        position = [double]$domain.position
        ownedRoots = @($domain.ownedRoots)
        ownedDocs = @($domain.ownedDocs)
        catchAll = [bool]$domain.catchAll
      }) | Out-Null
  }

  $items = @($orderedDomains.ToArray())
  $currentIndex = -1
  for ($i = 0; $i -lt $items.Count; $i++) {
    if (([string]$items[$i].path).Equals($DomainPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      $currentIndex = $i
      break
    }
  }

  if ($currentIndex -lt 0) {
    throw "Domain not found: $DomainPath"
  }

  $swapIndex = if ($Direction -eq "up") { $currentIndex - 1 } else { $currentIndex + 1 }
  if ($swapIndex -lt 0 -or $swapIndex -ge $items.Count) {
    return [ordered]@{
      domains = @($items)
    }
  }

  $temp = $items[$currentIndex]
  $items[$currentIndex] = $items[$swapIndex]
  $items[$swapIndex] = $temp

  $position = 10
  foreach ($domain in $items) {
    $domain.position = [double]$position
    $position += 10
  }

  Write-DocsDomainsConfig -Domains $items
  Touch-DocsWebsiteNavigationFiles
  return [ordered]@{
    domains = @($items)
  }
}

function Update-DocsDomain {
  param(
    [Parameter(Mandatory)][string]$DomainPath,
    [AllowEmptyString()][string]$Label,
    [AllowEmptyString()][string]$NewPath,
    [AllowNull()][object]$ShowLandingInSidebar
  )

  $definitions = Get-DocsDomainDefinitions
  $domains = New-Object System.Collections.Generic.List[object]
  $target = $null
  foreach ($domain in @($definitions.domains | Sort-Object position, label)) {
    $domainCopy = [pscustomobject]@{
      key = [string]$domain.key
      path = [string]$domain.path
      label = [string]$domain.label
      sidebarId = [string]$domain.sidebarId
      readmePath = [string]$domain.readmePath
      description = [string]$domain.description
      showLandingInSidebar = [bool]$domain.showLandingInSidebar
      position = [double]$domain.position
      ownedRoots = @($domain.ownedRoots)
      ownedDocs = @($domain.ownedDocs)
      catchAll = [bool]$domain.catchAll
    }
    if (([string]$domainCopy.path).Equals($DomainPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      $target = $domainCopy
    }
    $domains.Add($domainCopy) | Out-Null
  }

  if ($null -eq $target) {
    throw "Domain not found: $DomainPath"
  }

  $oldPath = ([string]$target.path).Trim().Replace('\', '/').Trim('/')
  $nextPath = ([string]$NewPath).Trim().Replace('\', '/').Trim('/')
  if ([string]::IsNullOrWhiteSpace($nextPath)) {
    $nextPath = $oldPath
  }

  if (-not $nextPath.Equals($oldPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    $moveResult = Move-DocsNode -SourcePath $oldPath -DestinationParentPath "" -InsertIndex ([int][Math]::Max(0, [double]$target.position - 1)) -NewName $nextPath
    $nextPath = ([string]$moveResult.path).Trim().Replace('\', '/').Trim('/')
    $target.path = $nextPath
    $target.sidebarId = Get-DocsDomainSidebarId -DomainPath $nextPath
    $target.ownedRoots = @(@($target.ownedRoots) | ForEach-Object {
        $root = ([string]$_).Trim().Replace('\', '/').Trim('/')
        if ($root.Equals($oldPath, [System.StringComparison]::OrdinalIgnoreCase)) { $nextPath } else { $root }
      })
    if (-not (@($target.ownedRoots) -contains $nextPath)) {
      $target.ownedRoots = @(@($target.ownedRoots) + $nextPath)
    }
    $readmePath = ([string]$target.readmePath).Trim().Replace('\', '/')
    if ($readmePath.StartsWith("$oldPath/", [System.StringComparison]::OrdinalIgnoreCase)) {
      $target.readmePath = $nextPath + $readmePath.Substring($oldPath.Length)
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($Label)) {
    $target.label = [string]$Label
    $domainDir = Join-Path $script:DocsRoot (($target.path).Replace('/', '\'))
    $categoryPath = Join-Path $domainDir "_category_.json"
    if (Test-Path -LiteralPath $categoryPath -PathType Leaf) {
      try {
        $category = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
        if ($category.PSObject.Properties.Name -contains "label") {
          $category.label = [string]$Label
        }
        else {
          $category | Add-Member -NotePropertyName "label" -NotePropertyValue ([string]$Label)
        }
        Write-DocsEditorUtf8NoBomFile -Path $categoryPath -Content (($category | ConvertTo-Json -Depth 20) + "`r`n")
      }
      catch {
      }
    }
  }

  if ($null -ne $ShowLandingInSidebar) {
    $target.showLandingInSidebar = [bool]$ShowLandingInSidebar
  }

  Write-DocsDomainsConfig -Domains @($domains.ToArray())
  Touch-DocsWebsiteNavigationFiles
  return [ordered]@{
    domain = $target
    domains = @($domains.ToArray())
  }
}

function Remove-DocsDomain {
  param([Parameter(Mandatory)][string]$DomainPath)

  $definitions = Get-DocsDomainDefinitions
  $domains = @($definitions.domains | Sort-Object position, label)
  $target = @($domains | Where-Object { ([string]$_.path).Equals($DomainPath, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
  if (-not $target) {
    throw "Domain not found: $DomainPath"
  }

  $docsRootFullPath = [System.IO.Path]::GetFullPath($script:DocsRoot)
  $deleted = New-Object System.Collections.Generic.List[string]
  foreach ($root in @($target.ownedRoots)) {
    $normalizedRoot = ([string]$root).Trim().Replace('\', '/').Trim('/')
    if ([string]::IsNullOrWhiteSpace($normalizedRoot)) {
      continue
    }

    $fullRootPath = Resolve-DocsPathFromToken -PathToken $normalizedRoot
    $rootFullPath = [System.IO.Path]::GetFullPath($fullRootPath)
    if ($rootFullPath.Equals($docsRootFullPath, [System.StringComparison]::OrdinalIgnoreCase) -or -not $rootFullPath.StartsWith($docsRootFullPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to delete unsafe domain root: $normalizedRoot"
    }

    if (Test-Path -LiteralPath $rootFullPath -PathType Container) {
      Remove-Item -LiteralPath $rootFullPath -Recurse -Force
      $deleted.Add($normalizedRoot) | Out-Null
    }
  }

  foreach ($docId in @($target.ownedDocs)) {
    $normalizedDocId = ([string]$docId).Trim().Replace('\', '/').Trim('/')
    if ([string]::IsNullOrWhiteSpace($normalizedDocId)) {
      continue
    }

    $pagePath = Resolve-PagePathFromToken -PathToken $normalizedDocId
    $pageFullPath = [System.IO.Path]::GetFullPath($pagePath)
    if (-not $pageFullPath.StartsWith($docsRootFullPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to delete unsafe domain page: $normalizedDocId"
    }

    if (Test-Path -LiteralPath $pageFullPath -PathType Leaf) {
      Remove-Item -LiteralPath $pageFullPath -Force
      $deleted.Add($normalizedDocId) | Out-Null
    }
  }

  $deletedRoots = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($root in @($target.ownedRoots)) {
    $normalizedRoot = ([string]$root).Trim().Replace('\', '/').Trim('/')
    if (-not [string]::IsNullOrWhiteSpace($normalizedRoot)) {
      $deletedRoots.Add($normalizedRoot) | Out-Null
    }
  }
  $deletedDocs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($docId in @($target.ownedDocs)) {
    $normalizedDocId = ([string]$docId).Trim().Replace('\', '/').Trim('/')
    if (-not [string]::IsNullOrWhiteSpace($normalizedDocId)) {
      $deletedDocs.Add($normalizedDocId) | Out-Null
    }
  }

  $remaining = @($domains | Where-Object { -not ([string]$_.path).Equals($DomainPath, [System.StringComparison]::OrdinalIgnoreCase) })
  $position = 10
  foreach ($domain in $remaining) {
    $domain.ownedRoots = @($domain.ownedRoots | Where-Object {
        -not $deletedRoots.Contains(([string]$_).Trim().Replace('\', '/').Trim('/'))
      })
    $domain.ownedDocs = @($domain.ownedDocs | Where-Object {
        -not $deletedDocs.Contains(([string]$_).Trim().Replace('\', '/').Trim('/'))
      })
    $domain.position = [double]$position
    $position += 10
  }

  Write-DocsDomainsConfig -Domains $remaining
  Touch-DocsWebsiteNavigationFiles
  Invoke-DocsEditorDevServerInvalidate | Out-Null
  return [ordered]@{
    deleted = [string]$DomainPath
    deletedItems = @($deleted.ToArray())
    domains = @($remaining)
  }
}

function Remove-DocsNode {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [AllowEmptyString()][string]$PreferredSiteOrigin
  )

  $target = Resolve-DocsEditorNavigationTarget -PathToken $PathToken

  $fullPath = [string]$target.FullPath
  $itemType = [string]$target.ItemType
  $parentDir = [string]$target.ParentDir
  $deletedMarkdownPathMap = Get-DocsEditorDeletedMarkdownMap -TargetPath $fullPath -ItemType $itemType
  $navigationChanged = $false

  if ($itemType -eq "page") {
    $parentCategoryUsesDeletedPage = $false
    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and (Test-DocsEditorCategoryLinksToPage -DirectoryPath $parentDir -PagePath $fullPath)) {
      $parentCategoryUsesDeletedPage = $true
    }
    elseif (
      -not [string]::IsNullOrWhiteSpace($parentDir) -and
      ([System.IO.Path]::GetFileName($fullPath)).Equals("README.md", [System.StringComparison]::OrdinalIgnoreCase) -and
      (Test-DocsEditorCategoryUsesReadmeLink -DirectoryPath $parentDir)
    ) {
      $parentCategoryUsesDeletedPage = $true
    }

    if ($parentCategoryUsesDeletedPage) {
      if (Clear-DocsEditorCategoryLink -DirectoryPath $parentDir) {
        $navigationChanged = $true
      }
    }

    if (Clear-DocsDomainLandingReferenceForPage -PagePath $fullPath) {
      $navigationChanged = $true
    }
  }

  if ($navigationChanged) {
    Touch-DocsWebsiteNavigationFiles
  }

  if ($itemType -eq "section") {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
  else {
    Remove-Item -LiteralPath $fullPath -Force
  }

  if (-not [string]::IsNullOrWhiteSpace($parentDir) -and (Test-Path -LiteralPath $parentDir -PathType Container)) {
    Normalize-DocsEditorSiblingPositions -ParentDir $parentDir
  }

  $devServerInvalidated = $false
  $warning = ""
  if ($deletedMarkdownPathMap.Count -gt 0) {
    $devServerInvalidated = Invoke-DocsEditorDevServerInvalidate -PreferredSiteOrigin $PreferredSiteOrigin
    if ($devServerInvalidated) {
      Start-Sleep -Milliseconds 450
    }

    $staleImports = @(Get-DocsEditorStaleRegistryImports -MovedMarkdownPathMap $deletedMarkdownPathMap)
    if ($staleImports.Count -gt 0) {
      $preview = @($staleImports | Select-Object -First 6) -join ", "
      $warning = "Deleted docs item, but the docs dev server still has stale imports. Restart the docs dev server if the site reports a missing module: $preview"
    }
  }

  return [ordered]@{
    deleted = $PathToken
    devServerInvalidated = $devServerInvalidated
    warning = $warning
  }
}

function Move-DocsNode {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [string]$OwnerDomainPath,
    [AllowEmptyString()][string]$DestinationParentPath,
    [int]$InsertIndex = 0,
    [string]$NewName,
    [AllowEmptyString()][string]$PreferredSiteOrigin
  )

  $source = Resolve-DocsEditorNavigationTarget -PathToken $SourcePath

  $destinationParentDir = if ([string]::IsNullOrWhiteSpace($DestinationParentPath)) {
    $script:DocsRoot
  }
  else {
    $section = Resolve-DocsEditorNavigationTarget -PathToken $DestinationParentPath
    if ([string]$section.ItemType -ne "section") {
      throw "Destination parent must be a section or Docs root."
    }
    [string]$section.FullPath
  }

  $sourceFullPath = [System.IO.Path]::GetFullPath([string]$source.FullPath)
  $destinationParentFullPath = [System.IO.Path]::GetFullPath($destinationParentDir)
  if ($destinationParentFullPath.StartsWith($sourceFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Cannot move a section into itself or one of its descendants."
  }

  $oldParentDir = [string]$source.ParentDir
  $originalSourceFullPath = [System.IO.Path]::GetFullPath([string]$source.FullPath)
  $leafName = if ([string]$source.ItemType -eq "section") {
    [System.IO.Path]::GetFileName([string]$source.FullPath)
  }
  else {
    [System.IO.Path]::GetFileName([string]$source.FullPath)
  }

  if (-not [string]::IsNullOrWhiteSpace($NewName)) {
    if ([string]$source.ItemType -eq "section") {
      $leafName = (($NewName -replace '/', '\').Trim('\'))
    }
    else {
      $normalizedStem = (($NewName -replace '/', '\').Trim('\'))
      if ($normalizedStem.EndsWith(".md", [System.StringComparison]::OrdinalIgnoreCase)) {
        $leafName = $normalizedStem
      }
      else {
        $leafName = "$normalizedStem.md"
      }
    }
  }

  $destinationFullPath = Join-Path $destinationParentDir $leafName
  $movedMarkdownPathMap = @{}
  $didMovePath = $false
  $didRewriteLinks = $false
  $didRewriteDocIds = $false
  $devServerInvalidated = $false
  $warning = ""

  try {
    if ([System.IO.Path]::GetFullPath($destinationFullPath).Equals($sourceFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      # position-only move within same parent
    }
    else {
      $movedMarkdownPathMap = Get-DocsEditorMovedMarkdownMap `
        -SourcePath ([string]$source.FullPath) `
        -DestinationPath $destinationFullPath `
        -ItemType ([string]$source.ItemType)
      if (Test-Path -LiteralPath $destinationFullPath) {
        throw "Destination already exists: $(Get-RelativePathFromDocsRoot -FullPath $destinationFullPath)"
      }
      Move-Item -LiteralPath ([string]$source.FullPath) -Destination $destinationFullPath
      $didMovePath = $true
      $source.FullPath = $destinationFullPath
      $source.ParentDir = $destinationParentDir
    }

    Normalize-SlugsForMovedItem -ItemPath ([string]$source.FullPath) -ItemType ([string]$source.ItemType)
    if ($movedMarkdownPathMap.Count -gt 0) {
      Ensure-DocsEditorMovedPageSlugsRemainStable -MovedMarkdownPathMap $movedMarkdownPathMap
      Update-DocsMarkdownLinksForMove -MovedMarkdownPathMap $movedMarkdownPathMap
      $didRewriteLinks = $true
      Update-DocsEditorDocIdReferencesForMove -MovedMarkdownPathMap $movedMarkdownPathMap
      $didRewriteDocIds = $true
    }
    if ($didMovePath -or $didRewriteLinks -or $didRewriteDocIds) {
      Assert-DocsEditorMarkdownLinksResolvable
      Assert-DocsEditorMovedDocIdReferencesResolvable -MovedMarkdownPathMap $movedMarkdownPathMap
    }

    if ($didMovePath -and $movedMarkdownPathMap.Count -gt 0) {
      if (Invoke-DocsEditorDevServerInvalidate -PreferredSiteOrigin $PreferredSiteOrigin) {
        $devServerInvalidated = $true
        Start-Sleep -Milliseconds 450
      }

      $staleImports = @()
      for ($attempt = 0; $attempt -lt 8; $attempt += 1) {
        $staleImports = @(Get-DocsEditorStaleRegistryImports -MovedMarkdownPathMap $movedMarkdownPathMap)
        if ($staleImports.Count -eq 0) {
          break
        }
        Start-Sleep -Milliseconds 300
      }
      if ($staleImports.Count -gt 0) {
        $preview = @($staleImports | Select-Object -First 6) -join ", "
        $warning = "Moved docs item, but the docs dev server still has stale imports. Reload or restart the docs dev server if the site reports a missing module: $preview"
      }
    }

    $parentsToNormalize = New-Object System.Collections.Generic.List[string]
    $parentsToNormalize.Add($oldParentDir) | Out-Null
    if (-not ([System.IO.Path]::GetFullPath($oldParentDir).Equals([System.IO.Path]::GetFullPath($destinationParentDir), [System.StringComparison]::OrdinalIgnoreCase))) {
      $parentsToNormalize.Add($destinationParentDir) | Out-Null
    }

    foreach ($parent in $parentsToNormalize) {
      Normalize-DocsEditorSiblingPositions -ParentDir $parent
    }

    $destinationGroups = Get-DocsEditorNavigationSiblingGroups -ParentDir $destinationParentDir
    $sortedDestination = @($destinationGroups.Visible | Sort-Object Position, RelativePath)
    $normalizedInsertIndex = if ($InsertIndex -lt 0) { 0 } else { $InsertIndex }
    if ($normalizedInsertIndex -gt $sortedDestination.Count) {
      $normalizedInsertIndex = $sortedDestination.Count
    }

    $sourceResolved = [pscustomobject]@{
      ItemType = [string]$source.ItemType
      FullPath = [System.IO.Path]::GetFullPath([string]$source.FullPath)
    }

    $sourcePathFull = [System.IO.Path]::GetFullPath([string]$sourceResolved.FullPath)
    $destinationWithoutSource = @(
      $sortedDestination | Where-Object {
        $currentPath = [System.IO.Path]::GetFullPath([string]$_.FullPath)
        -not $currentPath.Equals($sourcePathFull, [System.StringComparison]::OrdinalIgnoreCase)
      }
    )

    if ($normalizedInsertIndex -gt $destinationWithoutSource.Count) {
      $normalizedInsertIndex = $destinationWithoutSource.Count
    }

    $orderedAfterInsert = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $destinationWithoutSource.Count; $i++) {
      if ($i -eq $normalizedInsertIndex) {
        $orderedAfterInsert.Add($sourceResolved) | Out-Null
      }
      $orderedAfterInsert.Add($destinationWithoutSource[$i]) | Out-Null
    }
    if ($normalizedInsertIndex -ge $destinationWithoutSource.Count) {
      $orderedAfterInsert.Add($sourceResolved) | Out-Null
    }

    Normalize-DocsEditorSiblingPositions -ParentDir $destinationParentDir -VisibleSiblings @($orderedAfterInsert.ToArray())

    $newRelativePath = Get-RelativePathFromDocsRoot -FullPath ([string]$sourceResolved.FullPath)
    Set-DocsDomainOwnerForTopLevelItem -DomainPath $OwnerDomainPath -PathToken $newRelativePath -ItemType ([string]$sourceResolved.ItemType) | Out-Null
    if ([string]$sourceResolved.ItemType -eq "page") {
      $newRelativePath = $newRelativePath -replace '\.md$', ''
    }

    return [ordered]@{
      path = $newRelativePath
      devServerInvalidated = $devServerInvalidated
      warning = $warning
    }
  }
  catch {
    $originalErrorMessage = $_.Exception.Message
    $rollbackNotes = New-Object System.Collections.Generic.List[string]

    if ($didRewriteDocIds -and $movedMarkdownPathMap.Count -gt 0) {
      try {
        Update-DocsEditorDocIdReferencesForMove -MovedMarkdownPathMap (Get-DocsEditorReversedPathMap -PathMap $movedMarkdownPathMap)
      }
      catch {
        $rollbackNotes.Add("docId references rollback failed: $($_.Exception.Message)") | Out-Null
      }
    }

    if ($didRewriteLinks -and $movedMarkdownPathMap.Count -gt 0) {
      try {
        Update-DocsMarkdownLinksForMove -MovedMarkdownPathMap (Get-DocsEditorReversedPathMap -PathMap $movedMarkdownPathMap)
      }
      catch {
        $rollbackNotes.Add("markdown links rollback failed: $($_.Exception.Message)") | Out-Null
      }
    }

    if ($didMovePath) {
      try {
        $currentMovedPath = [System.IO.Path]::GetFullPath([string]$source.FullPath)
        if (Test-Path -LiteralPath $currentMovedPath) {
          Move-Item -LiteralPath $currentMovedPath -Destination $originalSourceFullPath -Force
          $source.FullPath = $originalSourceFullPath
          $source.ParentDir = $oldParentDir
        }
      }
      catch {
        $rollbackNotes.Add("path rollback failed: $($_.Exception.Message)") | Out-Null
      }
    }

    if ($rollbackNotes.Count -gt 0) {
      throw ("Move failed and rollback was only partial. Error: {0}. Rollback issues: {1}" -f $originalErrorMessage, ($rollbackNotes -join " | "))
    }

    throw ("Move was reverted. " + $originalErrorMessage)
  }
}

function Rename-DocsNode {
  param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$NewName,
    [AllowEmptyString()][string]$PreferredSiteOrigin
  )

  $source = Resolve-DocsEditorNavigationTarget -PathToken $SourcePath

  $parentPathToken = ""
  $parentFullPath = [System.IO.Path]::GetFullPath([string]$source.ParentDir)
  $docsRootFullPath = [System.IO.Path]::GetFullPath($script:DocsRoot)
  if (-not $parentFullPath.Equals($docsRootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    $parentPathToken = Get-RelativePathFromDocsRoot -FullPath $parentFullPath
  }

  $currentPosition = [int][Math]::Max(1, [double]$source.Position)
  $insertIndex = $currentPosition - 1
  return (Move-DocsNode -SourcePath $SourcePath -DestinationParentPath $parentPathToken -InsertIndex $insertIndex -NewName $NewName -PreferredSiteOrigin $PreferredSiteOrigin)
}

function Reorder-DocsNode {
  param(
    [Parameter(Mandatory)][string]$TargetPath,
    [Parameter(Mandatory)]$Position
  )

  $result = Invoke-DocsModuleInternal -ScriptBlock {
    param($resolvedRepoRoot, $target, $newPosition)
    Invoke-DocsReorder -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments @($target, "$newPosition")
  } -Arguments @($script:RepoRoot, $TargetPath, $Position)

  return [ordered]@{
    target = [string]$result.Target
    newPosition = [double]$result.NewPosition
    updatedCount = [int]$result.UpdatedCount
  }
}

function Get-SiteThemeCatalogPayload {
  return (Invoke-DocsModuleInternal -ScriptBlock {
      param($resolvedRepoRoot)
      $catalog = Read-DocsThemeCatalog -ResolvedRepoRoot $resolvedRepoRoot
      return [ordered]@{
        defaultTheme = [string]$catalog.DefaultTheme
        themes = @($catalog.Themes)
      }
    } -Arguments @($script:RepoRoot))
}

function Get-SiteConfigPayload {
  return (Invoke-DocsModuleInternal -ScriptBlock {
      param($resolvedRepoRoot)
      $ownership = Read-DocsWebsiteOwnershipMarker -ResolvedRepoRoot $resolvedRepoRoot
      $overrides = Read-DocsWebsiteOverrides -ResolvedRepoRoot $resolvedRepoRoot
      $themeId = [string]$overrides.Document.theme.themeId
      if ([string]::IsNullOrWhiteSpace($themeId) -and $ownership -and $ownership.theme.themeId) {
        $themeId = [string]$ownership.theme.themeId
      }

      return [ordered]@{
        ownership = $ownership
        overrides = $overrides.Document
        overridesPath = $overrides.Path
        knownOverridablePaths = @(Get-DocsWebsiteOverrideCandidatePaths)
        theme = [ordered]@{
          themeId = $themeId
          logoPath = [string]$overrides.Document.theme.logoPath
          faviconPath = [string]$overrides.Document.theme.faviconPath
          socialCardPath = [string]$overrides.Document.theme.socialCardPath
        }
      }
    } -Arguments @($script:RepoRoot))
}

function Apply-SiteThemeFromApiBody {
  param([Parameter(Mandatory)]$Body)

  $themeId = [string]$Body.themeId
  $logoPath = [string]$Body.logoPath
  $faviconPath = [string]$Body.faviconPath
  $socialCardPath = [string]$Body.socialCardPath
  return (Invoke-DocsModuleInternal -ScriptBlock {
      param($resolvedRepoRoot, $themeIdArg, $logoPathArg, $faviconPathArg, $socialCardPathArg)
      Invoke-DocsThemeApply `
        -ResolvedRepoRoot $resolvedRepoRoot `
        -ThemeId $themeIdArg `
        -LogoPath $logoPathArg `
        -FaviconPath $faviconPathArg `
        -SocialCardPath $socialCardPathArg `
        -AdoptExisting:$true
      $config = Invoke-DocsSiteStatus -ResolvedRepoRoot $resolvedRepoRoot
      return $config
    } -Arguments @($script:RepoRoot, $themeId, $logoPath, $faviconPath, $socialCardPath))
}

function Apply-SiteBrandingFromApiBody {
  param([Parameter(Mandatory)]$Body)

  $config = Get-SiteConfigPayload
  $themeId = [string]$config.theme.themeId
  if ([string]::IsNullOrWhiteSpace($themeId)) {
    $themeId = "neutral"
  }

  return (Invoke-DocsModuleInternal -ScriptBlock {
      param($resolvedRepoRoot, $themeIdArg, $logoPathArg, $faviconPathArg, $socialCardPathArg)
      Invoke-DocsThemeApply `
        -ResolvedRepoRoot $resolvedRepoRoot `
        -ThemeId $themeIdArg `
        -LogoPath ([string]$logoPathArg) `
        -FaviconPath ([string]$faviconPathArg) `
        -SocialCardPath ([string]$socialCardPathArg) `
        -AdoptExisting:$true
      $status = Invoke-DocsSiteStatus -ResolvedRepoRoot $resolvedRepoRoot
      return $status
    } -Arguments @($script:RepoRoot, $themeId, [string]$Body.logoPath, [string]$Body.faviconPath, [string]$Body.socialCardPath))
}

function Apply-SiteOverridesFromApiBody {
  param([Parameter(Mandatory)]$Body)

  return (Invoke-DocsModuleInternal -ScriptBlock {
      param($resolvedRepoRoot, $payload)
      if ($null -ne $payload.entries) {
        $overrides = Read-DocsWebsiteOverrides -ResolvedRepoRoot $resolvedRepoRoot
        $entries = New-Object System.Collections.Generic.List[object]
        foreach ($entry in @($payload.entries)) {
          if ($null -eq $entry) { continue }
          $relativePath = [string]$entry.path
          $mode = ([string]$entry.mode).Trim().ToLowerInvariant()
          if ([string]::IsNullOrWhiteSpace($relativePath) -or $mode -notin @("suite", "project")) {
            continue
          }
          $entries.Add([ordered]@{
            path = $relativePath.Replace("\", "/").TrimStart("/")
            mode = $mode
          }) | Out-Null
        }
        $overrides.Document.fileOverrides = @($entries.ToArray() | Sort-Object path)
        Write-DocsWebsiteOverrides -ResolvedRepoRoot $resolvedRepoRoot -Document $overrides.Document
      }
      elseif (-not [string]::IsNullOrWhiteSpace([string]$payload.path) -and -not [string]::IsNullOrWhiteSpace([string]$payload.mode)) {
        Invoke-DocsSiteOverrideSet -ResolvedRepoRoot $resolvedRepoRoot -RelativePath ([string]$payload.path) -Mode ([string]$payload.mode) | Out-Null
      }
      elseif (-not [string]::IsNullOrWhiteSpace([string]$payload.path)) {
        Invoke-DocsSiteOverrideClear -ResolvedRepoRoot $resolvedRepoRoot -RelativePath ([string]$payload.path) | Out-Null
      }

      return [ordered]@{
        overrides = (Read-DocsWebsiteOverrides -ResolvedRepoRoot $resolvedRepoRoot).Document
      }
    } -Arguments @($script:RepoRoot, $Body))
}

function Invoke-EditorApiRequest {
  param([Parameter(Mandatory)][System.Net.HttpListenerContext]$Context)

  $request = $Context.Request
  $path = $request.Url.AbsolutePath.TrimEnd('/')
  if ([string]::IsNullOrWhiteSpace($path)) {
    $path = "/"
  }

  if ($request.HttpMethod -eq "OPTIONS") {
    Write-PlainResponse -Context $Context -StatusCode 200 -Text ""
    return
  }

  if ($path -eq "/health" -and $request.HttpMethod -eq "GET") {
    Write-JsonResponse -Context $Context -Payload ([ordered]@{
        ok = $true
        repoRoot = $script:RepoRoot
        docsRoot = $script:DocsRoot
        capabilities = [ordered]@{
          authoringApiVersion = 2
          siteConfig = $true
          domains = $true
          tree = $true
          visibility = $true
        }
      })
    return
  }

  if ($path -eq "/api/tree" -and $request.HttpMethod -eq "GET") {
    $rootToken = [string]$request.QueryString["root"]
    $sidebarId = [string]$request.QueryString["sidebarId"]
    $generalOnly = ([string]$request.QueryString["general"]).Equals("1")
    Write-JsonResponse -Context $Context -Payload ([ordered]@{
        ok = $true
        tree = (Get-DocsTree -RootPath $rootToken -SidebarId $sidebarId -GeneralOnly:$generalOnly)
      })
    return
  }

  if ($path -eq "/api/domains" -and $request.HttpMethod -eq "GET") {
    Write-JsonResponse -Context $Context -Payload ([ordered]@{
        ok = $true
        domains = (Get-DocsDomainDefinitions)
      })
    return
  }

  if ($path -eq "/api/content" -and $request.HttpMethod -eq "GET") {
    $token = [string]$request.QueryString["path"]
    if ([string]::IsNullOrWhiteSpace($token)) {
      throw "Query parameter 'path' is required."
    }
    $content = Get-DocsContent -PathToken $token
    Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; content = $content })
    return
  }

  if ($path -eq "/api/site/config" -and $request.HttpMethod -eq "GET") {
    Write-JsonResponse -Context $Context -Payload ([ordered]@{
        ok = $true
        config = (Get-SiteConfigPayload)
      })
    return
  }

  if ($path -eq "/api/site/theme-catalog" -and $request.HttpMethod -eq "GET") {
    Write-JsonResponse -Context $Context -Payload ([ordered]@{
        ok = $true
        catalog = (Get-SiteThemeCatalogPayload)
      })
    return
  }

  if ($request.HttpMethod -ne "POST") {
    throw "Unsupported method: $($request.HttpMethod)"
  }

  $body = Read-JsonBody -Request $request
  switch ($path) {
    "/api/content" {
      $saveResult = Save-DocsContent `
        -PathToken ([string]$body.path) `
        -Content ([string]$body.content) `
        -ExpectedHash ([string]$body.expectedHash)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $saveResult })
      return
    }
    "/api/create/page" {
      $result = Create-DocsPage -DomainPath ([string]$body.domainPath) -SectionPath ([string]$body.sectionPath) -PageName ([string]$body.pageName) -Title ([string]$body.title)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/create/section" {
      $result = Create-DocsSection `
        -DomainPath ([string]$body.domainPath) `
        -ParentPath ([string]$body.parentPath) `
        -SectionName ([string]$body.sectionName) `
        -Title ([string]$body.title) `
        -LinkType ([string]$body.linkType) `
        -GeneratedIndexTitle ([string]$body.generatedIndexTitle) `
        -GeneratedIndexSlug ([string]$body.generatedIndexSlug) `
        -GeneratedIndexDescription ([string]$body.generatedIndexDescription) `
        -DisplayedSidebar ([string]$body.displayedSidebar)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/create/domain" {
      $result = Create-DocsDomain -DomainName ([string]$body.domainName) -Title ([string]$body.title) -Description ([string]$body.description) -CreateLandingPage ([bool]$body.createLandingPage)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/move" {
      $indexValue = 0
      if ($null -ne $body.insertIndex) {
        $indexValue = [int]$body.insertIndex
      }
      $siteOrigin = Get-DocsEditorSiteOriginFromRequest -Request $request
      $result = Move-DocsNode -SourcePath ([string]$body.sourcePath) -OwnerDomainPath ([string]$body.destinationDomainPath) -DestinationParentPath ([string]$body.destinationParentPath) -InsertIndex $indexValue -NewName ([string]$body.newName) -PreferredSiteOrigin $siteOrigin
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/rename" {
      $siteOrigin = Get-DocsEditorSiteOriginFromRequest -Request $request
      $result = Rename-DocsNode -SourcePath ([string]$body.sourcePath) -NewName ([string]$body.newName) -PreferredSiteOrigin $siteOrigin
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/node/metadata" {
      $result = Update-DocsNodeMetadata -PathToken ([string]$body.path) -Title ([string]$body.title) -Label ([string]$body.label)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/reorder" {
      $result = Reorder-DocsNode -TargetPath ([string]$body.targetPath) -Position ([double]$body.position)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/delete" {
      $siteOrigin = Get-DocsEditorSiteOriginFromRequest -Request $request
      $result = Remove-DocsNode -PathToken ([string]$body.path) -PreferredSiteOrigin $siteOrigin
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/visibility" {
      $result = Set-DocsPageVisibility -PathToken ([string]$body.path) -Hidden ([bool]$body.hidden)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/domains/reorder" {
      $result = Move-DocsDomain -DomainPath ([string]$body.domainPath) -Direction ([string]$body.direction).Trim().ToLowerInvariant()
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/domains/update" {
      $result = Update-DocsDomain -DomainPath ([string]$body.domainPath) -Label ([string]$body.label) -NewPath ([string]$body.newPath) -ShowLandingInSidebar $body.showLandingInSidebar
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/domains/delete" {
      $result = Remove-DocsDomain -DomainPath ([string]$body.domainPath)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/site/theme" {
      $result = Apply-SiteThemeFromApiBody -Body $body
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/site/branding" {
      $result = Apply-SiteBrandingFromApiBody -Body $body
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/site/overrides" {
      $result = Apply-SiteOverridesFromApiBody -Body $body
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    default {
      throw "Unknown endpoint: $path"
    }
  }
}

$listener = [System.Net.HttpListener]::new()
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)
$listener.Start()

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
      Invoke-EditorApiRequest -Context $context
    }
    catch {
      $message = $_.Exception.Message
      if ($env:UE_TOOLS_DOCS_EDITOR_DEBUG -eq "1" -and $_.ScriptStackTrace) {
        $message = "$message`n$($_.ScriptStackTrace)"
      }
      $statusCode = if ($message -like "*conflict*") { 409 } else { 400 }
      Write-ErrorResponse -Context $context -Message $message -StatusCode $statusCode
    }
  }
}
finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  $listener.Close()
}
