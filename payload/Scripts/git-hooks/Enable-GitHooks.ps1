$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) {
  throw "Not inside a git repository."
}

$gitModulePath = Join-Path $repoRoot "Scripts\UETools\UEToolSuite.Git.psm1"
$facadeManifestPath = Join-Path $repoRoot "Scripts\UETools\UETools.psd1"
if (Test-Path -LiteralPath $gitModulePath -PathType Leaf) {
  Import-Module -Name $gitModulePath -Force
}
elseif (Test-Path -LiteralPath $facadeManifestPath -PathType Leaf) {
  Import-Module -Name $facadeManifestPath -Force
}

if (Get-Command -Name "Enable-UEToolSuiteGitHooks" -ErrorAction SilentlyContinue) {
  Enable-UEToolSuiteGitHooks -RepoRoot $repoRoot -HooksPath ".githooks"
}
else {
  git config --local core.hooksPath .githooks

  # Optional: ensure the hook exists
  if (-not (Test-Path ".githooks/post-checkout")) {
    Write-Warning "Missing .githooks/post-checkout. Did you pull the repo changes?"
  }
}

Write-Host "Set local core.hooksPath to .githooks"
Write-Host "Done. Git Hooks are now enabled."
