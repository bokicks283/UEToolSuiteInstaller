[CmdletBinding()]
param(
  [Alias("SnapshotPath")]
  [string]$CurrentPath,
  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Normalize-Whitespace {
  param([string]$Text)

  $out = $Text -replace "`r", ""
  $out = $out -replace "[ \t]+`n", "`n"
  $out = $out -replace "`n{3,}", "`n`n"
  return $out.Trim() + "`n"
}

function Decode-Html {
  param([string]$Text)
  return [System.Net.WebUtility]::HtmlDecode($Text)
}

function Convert-InlineHtmlToMarkdown {
  param([string]$HtmlFragment)

  $text = $HtmlFragment

  # Links first to preserve target URLs.
  $text = [regex]::Replace(
    $text,
    '(?is)<a\b[^>]*href="(?<href>[^"]+)"[^>]*>(?<txt>.*?)</a>',
    {
      param($m)
      $href = $m.Groups['href'].Value
      if ($href.StartsWith("/")) {
        $href = "https://dev.epicgames.com$href"
      }

      $txt = $m.Groups['txt'].Value
      $txt = [regex]::Replace($txt, '(?is)<[^>]+>', '')
      $txt = Decode-Html $txt
      $txt = $txt.Trim()
      if ([string]::IsNullOrWhiteSpace($txt)) { $txt = $href }
      return "[$txt]($href)"
    }
  )

  # Inline code / emphasis / strong.
  $text = [regex]::Replace($text, '(?is)<code\b[^>]*>(?<c>.*?)</code>', { param($m) '`' + (Decode-Html $m.Groups['c'].Value).Trim() + '`' })
  $text = [regex]::Replace($text, '(?is)<strong\b[^>]*>(?<s>.*?)</strong>', { param($m) '**' + (Decode-Html ([regex]::Replace($m.Groups['s'].Value,'(?is)<[^>]+>',''))).Trim() + '**' })
  $text = [regex]::Replace($text, '(?is)<em\b[^>]*>(?<e>.*?)</em>', { param($m) '*' + (Decode-Html ([regex]::Replace($m.Groups['e'].Value,'(?is)<[^>]+>',''))).Trim() + '*' })
  $text = [regex]::Replace($text, '(?is)<br\s*/?>', "`n")

  # Strip any remaining tags.
  $text = [regex]::Replace($text, '(?is)<[^>]+>', '')
  $text = Decode-Html $text
  $text = $text -replace "\u00A0", " "
  $text = [regex]::Replace($text, '[ \t]+', ' ')
  $text = [regex]::Replace($text, " *`n *", "`n")
  return $text.Trim()
}

function Convert-TableHtmlToMarkdown {
  param([string]$TableHtml)

  $rows = [regex]::Matches($TableHtml, '(?is)<tr\b[^>]*>(?<row>.*?)</tr>')
  if ($rows.Count -eq 0) { return "" }

  $tableRows = @()
  foreach ($r in $rows) {
    $cells = [regex]::Matches($r.Groups['row'].Value, '(?is)<t[hd]\b[^>]*>(?<cell>.*?)</t[hd]>')
    if ($cells.Count -eq 0) { continue }
    $row = @()
    foreach ($c in $cells) {
      $row += (Convert-InlineHtmlToMarkdown $c.Groups['cell'].Value)
    }
    $tableRows += ,$row
  }

  if ($tableRows.Count -eq 0) { return "" }

  $maxCols = ($tableRows | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
  for ($i = 0; $i -lt $tableRows.Count; $i++) {
    while ($tableRows[$i].Count -lt $maxCols) {
      $tableRows[$i] += ""
    }
  }

  $header = $tableRows[0]
  $separator = @()
  for ($i = 0; $i -lt $maxCols; $i++) { $separator += "---" }

  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("| " + ($header -join " | ") + " |")
  [void]$sb.AppendLine("| " + ($separator -join " | ") + " |")

  for ($i = 1; $i -lt $tableRows.Count; $i++) {
    [void]$sb.AppendLine("| " + ($tableRows[$i] -join " | ") + " |")
  }

  return $sb.ToString().TrimEnd()
}

function Convert-ContentHtmlToMarkdown {
  param([string]$ContentHtml)

  $text = $ContentHtml

  # Remove copy buttons from code blocks.
  $text = [regex]::Replace($text, '(?is)<button\b[^>]*>.*?</button>', '')

  # Extract <pre><code> blocks and replace with placeholders.
  $codeMap = @{}
  $text = [regex]::Replace(
    $text,
    '(?is)<pre\b[^>]*>\s*<code\b[^>]*>(?<code>.*?)</code>\s*</pre>',
    {
      param($m)
      $id = "@@CODEBLOCK_$([Guid]::NewGuid().ToString('N'))@@"

      $code = Decode-Html $m.Groups['code'].Value
      $code = $code -replace "`r", ""
      $code = $code.TrimEnd()
      $codeMap[$id] = '```cpp' + "`n" + $code + "`n" + '```'
      return "`n`n$id`n`n"
    }
  )

  # Extract tables and replace with placeholders.
  $tableMap = @{}
  $text = [regex]::Replace(
    $text,
    '(?is)<table\b[^>]*>.*?</table>',
    {
      param($m)
      $id = "@@TABLE_$([Guid]::NewGuid().ToString('N'))@@"
      $tableMap[$id] = Convert-TableHtmlToMarkdown $m.Value
      return "`n`n$id`n`n"
    }
  )

  # Headings.
  $text = [regex]::Replace($text, '(?is)<h2\b[^>]*>(?<h>.*?)</h2>', { param($m) "`n`n## " + (Convert-InlineHtmlToMarkdown $m.Groups['h'].Value) + "`n`n" })
  $text = [regex]::Replace($text, '(?is)<h3\b[^>]*>(?<h>.*?)</h3>', { param($m) "`n`n### " + (Convert-InlineHtmlToMarkdown $m.Groups['h'].Value) + "`n`n" })
  $text = [regex]::Replace($text, '(?is)<h4\b[^>]*>(?<h>.*?)</h4>', { param($m) "`n`n#### " + (Convert-InlineHtmlToMarkdown $m.Groups['h'].Value) + "`n`n" })

  # Lists.
  $text = [regex]::Replace($text, '(?is)<ul\b[^>]*>', "`n")
  $text = [regex]::Replace($text, '(?is)</ul>', "`n")
  $text = [regex]::Replace($text, '(?is)<li\b[^>]*>', "`n- ")
  $text = [regex]::Replace($text, '(?is)</li>', "")

  # Paragraphs / line breaks.
  $text = [regex]::Replace($text, '(?is)<p\b[^>]*>', '')
  $text = [regex]::Replace($text, '(?is)</p>', "`n`n")
  $text = [regex]::Replace($text, '(?is)<br\s*/?>', "`n")

  # Inline conversion for remaining content.
  $text = Convert-InlineHtmlToMarkdown $text

  # Re-expand placeholders with exact token matches to avoid key collision issues.
  $text = [regex]::Replace(
    $text,
    '@@TABLE_[0-9a-fA-F]{32}@@',
    {
      param($m)
      if ($tableMap.ContainsKey($m.Value)) { return $tableMap[$m.Value] }
      return $m.Value
    }
  )

  $text = [regex]::Replace(
    $text,
    '@@CODEBLOCK_[0-9a-fA-F]{32}@@',
    {
      param($m)
      if ($codeMap.ContainsKey($m.Value)) { return $codeMap[$m.Value] }
      return $m.Value
    }
  )

  # Ensure headings and fenced blocks have clean spacing.
  $text = [regex]::Replace($text, '(?m)^(##+ .+)$', "`n`$1")
  $text = [regex]::Replace($text, '(?m)^-\s*\n\s*', '- ')
  $text = Normalize-Whitespace $text
  return $text
}

function Get-SourceMetadataValue {
  param(
    [Parameter(Mandatory)][string]$SourceText,
    [Parameter(Mandatory)][string]$Label
  )

  $pattern = "(?m)^\s*-\s*$([regex]::Escape($Label))\s*:\s*(.+?)\s*$"
  if ($SourceText -notmatch $pattern) {
    return $null
  }

  return $Matches[1].Trim()
}

$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) { throw "Not inside a git repository." }

$codingRoot = Join-Path $repoRoot "Docs/CodingStandards"
$defaultCurrentPath = Join-Path $codingRoot "Current"

if (-not $CurrentPath) {
  $CurrentPath = $defaultCurrentPath
}

if (-not (Test-Path $CurrentPath)) { throw "Current snapshot path not found: $CurrentPath" }

$pagePath = Join-Path $CurrentPath "page.html"
if (-not (Test-Path $pagePath)) { throw "Current snapshot page.html not found: $pagePath" }

if (-not $OutputPath) {
  $OutputPath = Join-Path $codingRoot "UnrealCppStandard.md"
}

$rawPage = Get-Content $pagePath -Raw
$contentMatch = [regex]::Match($rawPage, '(?s)"content_html":"(?<content>.*?)","settings"\s*:\s*\{')
if (-not $contentMatch.Success) {
  throw "Could not locate content_html payload in snapshot page."
}

$encoded = $contentMatch.Groups["content"].Value
$contentHtml = ConvertFrom-Json ('"' + $encoded + '"')
$bodyMd = Convert-ContentHtmlToMarkdown $contentHtml

$sourceMdPath = Join-Path $CurrentPath "SOURCE.md"
if (-not (Test-Path $sourceMdPath)) {
  throw "Current snapshot metadata file not found: $sourceMdPath"
}

$sourceText = (Get-Content $sourceMdPath -Raw).Trim()
$engineVersion = Get-SourceMetadataValue -SourceText $sourceText -Label "Engine version context"
if ([string]::IsNullOrWhiteSpace($engineVersion)) {
  throw "Engine version context is missing from $sourceMdPath"
}

$title = "Unreal C++ Coding Standard ($engineVersion)"
$frontMatter = @(
  "---"
  "title: $title"
  "slug: /coding-standards/unreal-cpp-standard"
  "sidebar_position: 1"
  "---"
  ""
)

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine(($frontMatter -join "`n"))
[void]$sb.AppendLine($bodyMd)

Set-Content -Path $OutputPath -Value $sb.ToString() -Encoding UTF8

$h2Count = ([regex]::Matches($contentHtml, '(?is)<h2\b')).Count
$h3Count = ([regex]::Matches($contentHtml, '(?is)<h3\b')).Count
$preCount = ([regex]::Matches($contentHtml, '(?is)<pre\b')).Count

Write-Host "[CodingStandards] Parsed current snapshot -> docs page:"
Write-Host "  $OutputPath"
Write-Host "[CodingStandards] Source blocks: h2=$h2Count h3=$h3Count pre=$preCount"
