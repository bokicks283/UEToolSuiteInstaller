[CmdletBinding()]
param()

function Write-TestUtf8NoBomFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyString()][string]$Content
  )

  $parent = Split-Path -Path $Path -Parent
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function New-TestScratchRoot {
  param([string]$Prefix = "ue tool suite test")

  $root = Join-Path ([System.IO.Path]::GetTempPath()) ($Prefix + " " + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  return $root
}

function New-TestUEProjectRepo {
  param(
    [Parameter(Mandatory)][string]$Root,
    [string]$Name = "PortableSample",
    [switch]$WithGit,
    [switch]$WithDocsSite,
    [switch]$WithArtSource,
    [switch]$WithSourceModule
  )

  $repoRoot = Join-Path $Root $Name
  New-Item -ItemType Directory -Force -Path $repoRoot | Out-Null

  if ($WithGit) {
    & git -C $repoRoot init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed for fixture repo: $repoRoot" }
    & git -C $repoRoot config user.email "ue-tool-suite-test@example.invalid" | Out-Null
    & git -C $repoRoot config user.name "UE Tool Suite Test" | Out-Null
  }

  Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "$Name.uproject") -Content @"
{
  "FileVersion": 3,
  "EngineAssociation": "5.4",
  "Category": "",
  "Description": "",
  "Modules": [
    {
      "Name": "$Name",
      "Type": "Runtime",
      "LoadingPhase": "Default"
    }
  ]
}
"@

  if ($WithSourceModule) {
    Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "Source\$Name\$Name.Build.cs") -Content @"
using UnrealBuildTool;

public class $Name : ModuleRules
{
  public $Name(ReadOnlyTargetRules Target) : base(Target)
  {
    PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
  }
}
"@
    Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "Source\$Name\Private\$Name.cpp") -Content "// Fixture source module.`n"
    Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "Source\$Name\Public\$Name.h") -Content "// Fixture source module header.`n"
  }

  if ($WithDocsSite) {
    Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "website\package.json") -Content @'
{
  "scripts": {
    "start": "docusaurus start",
    "build": "docusaurus build",
    "clear": "docusaurus clear"
  },
  "dependencies": {
    "@docusaurus/core": "3.7.0",
    "@docusaurus/preset-classic": "3.7.0"
  },
  "devDependencies": {}
}
'@
    Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "website\docusaurus.config.ts") -Content @'
const config = {
  title: 'Fixture',
  organizationName: 'FixtureOrg',
  projectName: 'FixtureProject',
};

export default config;
'@
    Write-TestUtf8NoBomFile -Path (Join-Path $repoRoot "Docs\README.md") -Content "# Fixture Docs`n"
  }

  if ($WithArtSource) {
    foreach ($relativePath in @("ArtSource\_Template\Source", "ArtSource\_Template\Textures", "ArtSource\_Template\Exports")) {
      New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot $relativePath) | Out-Null
    }
  }

  return $repoRoot
}
