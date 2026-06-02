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

function Get-RelativePathFromDocsRoot {
  param([Parameter(Mandatory)][string]$FullPath)
  return ([System.IO.Path]::GetRelativePath($script:DocsRoot, $FullPath) -replace '\\', '/')
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

function Get-DocsEditorPathKey {
  param([Parameter(Mandatory)][string]$Path)

  return ([System.IO.Path]::GetFullPath($Path).TrimEnd('\')).ToLowerInvariant()
}

function Test-DocsEditorLocalMarkdownLink {
  param([Parameter(Mandatory)][string]$Target)

  $trimmed = $Target.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }
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
  param([Parameter(Mandatory)][string]$Slug)

  $trimmed = [string]$Slug
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return ""
  }

  $trimmed = $trimmed.Trim()
  if (-not $trimmed.StartsWith("/")) {
    $trimmed = "/$trimmed"
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

  $route = Convert-DocsEditorSlugToDocsRoute -Slug $slug
  if ([string]::IsNullOrWhiteSpace($route)) {
    return ""
  }

  return $route + [string]$Tail
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
    $relative = [System.IO.Path]::GetRelativePath($sourceFull, $file.FullName)
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

  $docsRootFull = [System.IO.Path]::GetFullPath($script:DocsRoot).TrimEnd('\') + '\'
  $markdownFiles = @(Get-ChildItem -LiteralPath $script:DocsRoot -Recurse -File -Filter *.md -ErrorAction SilentlyContinue)
  $linkPattern = '(!?\[[^\]]*\]\()(?<target><[^>]+>|[^)\r\n]*?\.md(?:[?#][^)\s]*)?)(?<suffix>(?:\s+(?:"[^"]*"|''[^'']*''|\([^)]+\)))?\))'

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

        $relative = [System.IO.Path]::GetRelativePath($currentDir, $newTargetFull)
        $newTarget = Format-DocsEditorRelativeMarkdownTarget -RelativePath $relative -Tail $splitTarget.Tail
        if ($newTarget -match '\s') {
          $routeTarget = Get-DocsEditorMarkdownRouteTarget -MarkdownPath $newTargetFull -Tail $splitTarget.Tail
          if (-not [string]::IsNullOrWhiteSpace($routeTarget)) {
            $newTarget = $routeTarget
          }
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

function Get-DocsTree {
  $rootChildren = Get-DocsTreeChildren -ParentDir $script:DocsRoot
  return [ordered]@{
    root = "Docs"
    children = $rootChildren
  }
}

function Test-DocsEditorCategoryUsesReadmeLink {
  param([Parameter(Mandatory)][string]$DirectoryPath)

  $categoryPath = Join-Path $DirectoryPath "_category_.json"
  if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
    return $false
  }

  try {
    $categoryJson = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
  }
  catch {
    return $false
  }

  if (-not $categoryJson.link) {
    return $false
  }

  $linkType = ([string]$categoryJson.link.type).Trim().ToLowerInvariant()
  if ($linkType -ne "doc") {
    return $false
  }

  $linkId = ([string]$categoryJson.link.id).Trim().Replace('\', '/')
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
    $categoryPath = Join-Path $childDir.FullName "_category_.json"
    if (-not (Test-Path -LiteralPath $categoryPath -PathType Leaf)) {
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

function Get-DocsTreeChildren {
  param([Parameter(Mandatory)][string]$ParentDir)

  $siblings = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in @(Invoke-DocsModuleInternal -ScriptBlock {
      param($docsRootPath, $parentDirectory)
      Get-DocsNavigationSiblings -DocsRoot $docsRootPath -ParentDir $parentDirectory
    } -Arguments @($script:DocsRoot, $ParentDir))) {
    $siblings.Add($sibling) | Out-Null
  }
  Add-DocsEditorFallbackTreeSiblings -Siblings $siblings -ParentDir $ParentDir

  $nodes = New-Object System.Collections.Generic.List[object]
  foreach ($sibling in @($siblings.ToArray() | Sort-Object Position, RelativePath)) {
    $itemType = [string]$sibling.ItemType
    $fullPath = [string]$sibling.FullPath
    $relativePath = [string]$sibling.RelativePath
    $position = [double]$sibling.Position
    $displayName = ""

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

function Create-DocsPage {
  param(
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
  return [ordered]@{
    path = $relativePath
  }
}

function Create-DocsSection {
  param(
    [string]$ParentPath,
    [Parameter(Mandatory)][string]$SectionName,
    [string]$Title
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

  $result = Invoke-DocsModuleInternal -ScriptBlock {
    param($resolvedRepoRoot, $cliArgs)
    Invoke-NewSection -ResolvedRepoRoot $resolvedRepoRoot -CommandArguments $cliArgs
  } -Arguments @($script:RepoRoot, @($args.ToArray()))

  $readmePath = [string]$result.Path
  $sectionDir = Split-Path -Path $readmePath -Parent
  $relativeSectionPath = Get-RelativePathFromDocsRoot -FullPath $sectionDir
  return [ordered]@{
    path = $relativeSectionPath
  }
}

function Remove-DocsNode {
  param(
    [Parameter(Mandatory)][string]$PathToken,
    [AllowEmptyString()][string]$PreferredSiteOrigin
  )

  $target = Invoke-DocsModuleInternal -ScriptBlock {
    param($docsRootPath, $token)
    Resolve-DocsNavigationTarget -DocsRoot $docsRootPath -TargetPath $token
  } -Arguments @($script:DocsRoot, $PathToken)

  $fullPath = [string]$target.FullPath
  $itemType = [string]$target.ItemType
  $parentDir = [string]$target.ParentDir
  $deletedMarkdownPathMap = Get-DocsEditorDeletedMarkdownMap -TargetPath $fullPath -ItemType $itemType
  if ($itemType -eq "section") {
    Remove-Item -LiteralPath $fullPath -Recurse -Force
  }
  else {
    Remove-Item -LiteralPath $fullPath -Force
  }

  $siblingsAfterDelete = @(Invoke-DocsModuleInternal -ScriptBlock {
      param($docsRootPath, $parentDirectory)
      Get-DocsNavigationSiblings -DocsRoot $docsRootPath -ParentDir $parentDirectory
    } -Arguments @($script:DocsRoot, $parentDir))
  $positionCounter = 1
  foreach ($sibling in $siblingsAfterDelete) {
    Set-DocsNavigationItemPositionLocal -Item $sibling -Position ([double]$positionCounter)
    $positionCounter += 1
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
    [AllowEmptyString()][string]$DestinationParentPath,
    [int]$InsertIndex = 0,
    [string]$NewName,
    [AllowEmptyString()][string]$PreferredSiteOrigin
  )

  $source = Invoke-DocsModuleInternal -ScriptBlock {
    param($docsRootPath, $token)
    Resolve-DocsNavigationTarget -DocsRoot $docsRootPath -TargetPath $token
  } -Arguments @($script:DocsRoot, $SourcePath)

  $destinationParentDir = if ([string]::IsNullOrWhiteSpace($DestinationParentPath)) {
    $script:DocsRoot
  }
  else {
    $section = Invoke-DocsModuleInternal -ScriptBlock {
      param($docsRootPath, $token)
      Resolve-DocsNavigationTarget -DocsRoot $docsRootPath -TargetPath $token
    } -Arguments @($script:DocsRoot, $DestinationParentPath)
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
        Start-Sleep -Milliseconds 450
      }

      $staleImports = @(Get-DocsEditorStaleRegistryImports -MovedMarkdownPathMap $movedMarkdownPathMap)
      if ($staleImports.Count -gt 0) {
        $preview = @($staleImports | Select-Object -First 6) -join ", "
        throw ("Move would leave stale docs dev-server imports after reordering: " + $preview)
      }
    }

    $parentsToNormalize = New-Object System.Collections.Generic.List[string]
    $parentsToNormalize.Add($oldParentDir) | Out-Null
    if (-not ([System.IO.Path]::GetFullPath($oldParentDir).Equals([System.IO.Path]::GetFullPath($destinationParentDir), [System.StringComparison]::OrdinalIgnoreCase))) {
      $parentsToNormalize.Add($destinationParentDir) | Out-Null
    }

    foreach ($parent in $parentsToNormalize) {
      $siblings = @(Invoke-DocsModuleInternal -ScriptBlock {
          param($docsRootPath, $parentDirectory)
          Get-DocsNavigationSiblings -DocsRoot $docsRootPath -ParentDir $parentDirectory
        } -Arguments @($script:DocsRoot, $parent))
      $ordered = @($siblings | Sort-Object Position, RelativePath)
      $counter = 1
      foreach ($item in $ordered) {
        Set-DocsNavigationItemPositionLocal -Item $item -Position ([double]$counter)
        $counter += 1
      }
    }

    $destinationSiblings = @(Invoke-DocsModuleInternal -ScriptBlock {
        param($docsRootPath, $parentDirectory)
        Get-DocsNavigationSiblings -DocsRoot $docsRootPath -ParentDir $parentDirectory
      } -Arguments @($script:DocsRoot, $destinationParentDir))

    $sortedDestination = @($destinationSiblings | Sort-Object Position, RelativePath)
    $normalizedInsertIndex = if ($InsertIndex -lt 0) { 0 } else { $InsertIndex }
    if ($normalizedInsertIndex -gt $sortedDestination.Count) {
      $normalizedInsertIndex = $sortedDestination.Count
    }

    $sourceResolved = [pscustomobject]@{
      ItemType = [string]$source.ItemType
      FullPath = [System.IO.Path]::GetFullPath([string]$source.FullPath)
    }

    $orderedAfterInsert = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $sortedDestination.Count; $i++) {
      if ($i -eq $normalizedInsertIndex) {
        $orderedAfterInsert.Add($sourceResolved) | Out-Null
      }
      $currentItem = $sortedDestination[$i]
      $currentPath = [System.IO.Path]::GetFullPath([string]$currentItem.FullPath)
      $sourcePathFull = [System.IO.Path]::GetFullPath([string]$sourceResolved.FullPath)
      if (-not $currentPath.Equals($sourcePathFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $orderedAfterInsert.Add($currentItem) | Out-Null
      }
    }
    if ($normalizedInsertIndex -ge $sortedDestination.Count) {
      $orderedAfterInsert.Add($sourceResolved) | Out-Null
    }

    $positionValue = 1
    foreach ($item in @($orderedAfterInsert.ToArray())) {
      Set-DocsNavigationItemPositionLocal -Item $item -Position ([double]$positionValue)
      $positionValue += 1
    }

    $newRelativePath = Get-RelativePathFromDocsRoot -FullPath ([string]$sourceResolved.FullPath)
    if ([string]$sourceResolved.ItemType -eq "page") {
      $newRelativePath = $newRelativePath -replace '\.md$', ''
    }

    return [ordered]@{
      path = $newRelativePath
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

  $source = Invoke-DocsModuleInternal -ScriptBlock {
    param($docsRootPath, $token)
    Resolve-DocsNavigationTarget -DocsRoot $docsRootPath -TargetPath $token
  } -Arguments @($script:DocsRoot, $SourcePath)

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
      })
    return
  }

  if ($path -eq "/api/tree" -and $request.HttpMethod -eq "GET") {
    Write-JsonResponse -Context $Context -Payload ([ordered]@{
        ok = $true
        tree = (Get-DocsTree)
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
      $result = Create-DocsPage -SectionPath ([string]$body.sectionPath) -PageName ([string]$body.pageName) -Title ([string]$body.title)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/create/section" {
      $result = Create-DocsSection -ParentPath ([string]$body.parentPath) -SectionName ([string]$body.sectionName) -Title ([string]$body.title)
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/move" {
      $indexValue = 0
      if ($null -ne $body.insertIndex) {
        $indexValue = [int]$body.insertIndex
      }
      $siteOrigin = Get-DocsEditorSiteOriginFromRequest -Request $request
      $result = Move-DocsNode -SourcePath ([string]$body.sourcePath) -DestinationParentPath ([string]$body.destinationParentPath) -InsertIndex $indexValue -NewName ([string]$body.newName) -PreferredSiteOrigin $siteOrigin
      Write-JsonResponse -Context $Context -Payload ([ordered]@{ ok = $true; result = $result })
      return
    }
    "/api/rename" {
      $siteOrigin = Get-DocsEditorSiteOriginFromRequest -Request $request
      $result = Rename-DocsNode -SourcePath ([string]$body.sourcePath) -NewName ([string]$body.newName) -PreferredSiteOrigin $siteOrigin
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
