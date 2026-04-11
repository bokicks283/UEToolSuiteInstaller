# Scripts/git-hooks/Test-Hooks.ps1
# Sanity checks for our hook + helper plumbing (PowerShell 7+)
# Uses Git Bash (bash.exe shipped with Git for Windows) to validate sourcing hook-common.sh.

$ErrorActionPreference = "Stop"

function Info($m) { Write-Host "[HookTest] $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[HookTest] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[HookTest] $m" -ForegroundColor Yellow }
function Err($m)  { Write-Host "[HookTest] $m" -ForegroundColor Red }

function Get-GitExePath {
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { throw "git not found on PATH." }
  return $git.Source
}

function Get-GitInstallRootFromGitExe([string]$gitExe) {
  # Common layouts:
  #   <root>\cmd\git.exe
  #   <root>\bin\git.exe
  $dir = Split-Path $gitExe -Parent
  $leaf = (Split-Path $dir -Leaf).ToLowerInvariant()

  if ($leaf -eq "cmd" -or $leaf -eq "bin") {
    return (Split-Path $dir -Parent)
  }

  # Fallback: try git --exec-path and walk upward (best-effort)
  $execPath = (& git --exec-path 2>$null).Trim()
  if ($execPath) {
    # exec-path is typically: <root>\mingw64\libexec\git-core
    # Walk up a few levels and try to find usr\bin\bash.exe
    $p = $execPath
    for ($i = 0; $i -lt 5; $i++) {
      $candidate = Join-Path $p "usr\bin\bash.exe"
      if (Test-Path $candidate) { return $p }
      $p = Split-Path $p -Parent
      if (-not $p) { break }
    }
  }

  throw "Could not determine Git install root from: $gitExe"
}

function Find-GitBash([string]$gitRoot) {
  # Prefer usr\bin\bash.exe (Git Bash)
  $candidates = @(
    (Join-Path $gitRoot "usr\bin\bash.exe"),
    (Join-Path $gitRoot "bin\bash.exe")
  )

  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }

  # Fallback: try where bash (only if user has something installed)
  $where = & where.exe bash 2>$null
  if ($where) {
    $first = ($where -split "`r?`n" | Where-Object { $_ } | Select-Object -First 1)
    if ($first -and (Test-Path $first)) { return $first }
  }

  throw "bash.exe not found under Git root '$gitRoot'. Expected usr\bin\bash.exe."
}

# Must be in repo root
$repoRoot = (git rev-parse --show-toplevel 2>$null).Trim()
if (-not $repoRoot) { throw "Not inside a git repo." }
Set-Location $repoRoot

Info "Repo root: $repoRoot"

# Check hooksPath
$hooksPath = (git config --local --get core.hooksPath 2>$null).Trim()
if ($hooksPath -ne ".githooks") {
  Err "core.hooksPath is '$hooksPath' (expected '.githooks')"
  throw "Hooks not configured."
}
Ok "core.hooksPath = .githooks"

# Check required hook files
$hooks = @(
  ".githooks/pre-commit",
  ".githooks/pre-push",
  ".githooks/post-checkout",
  ".githooks/post-merge",
  ".githooks/post-commit",
  ".githooks/post-rewrite"
)
foreach ($h in $hooks) {
  $p = Join-Path $repoRoot $h
  if (-not (Test-Path $p)) { throw "Missing hook: $h" }
}
Ok "Hook files present."

# Check shared hook files
$shared = @(
  "Scripts/git-hooks/colors.sh",
  "Scripts/git-hooks/hook-common.sh"
)
foreach ($s in $shared) {
  $p = Join-Path $repoRoot $s
  if (-not (Test-Path $p)) { throw "Missing shared hook file: $s" }
}
Ok "Shared hook files present."

# Check conflict helper aliases exist
$ours = (git config --local --get alias.ours 2>$null).Trim()
$theirs = (git config --local --get alias.theirs 2>$null).Trim()
$conflicts = (git config --local --get alias.conflicts 2>$null).Trim()

if (-not $ours) { throw "Missing alias.ours" }
if (-not $theirs) { throw "Missing alias.theirs" }
if (-not $conflicts) { throw "Missing alias.conflicts" }

Ok "Conflict helper aliases present."
Info "alias.ours      = $ours"
Info "alias.theirs    = $theirs"
Info "alias.conflicts = $conflicts"

# Validate: Git Bash can source hook-common.sh
$gitExe = Get-GitExePath
$gitRoot = Get-GitInstallRootFromGitExe $gitExe
$bash = Find-GitBash $gitRoot

Info "Using Git Bash: $bash"

# Pass repo root via env var, convert safely in bash using cygpath
$env:REPO_ROOT = $repoRoot

$bashScript = @'
set -eu
if command -v cygpath >/dev/null 2>&1; then
  cd "$(cygpath -u "$REPO_ROOT")"
else
  cd "$REPO_ROOT"
fi
. "Scripts/git-hooks/hook-common.sh"
echo "CTX=$(hook_context)"
echo "CONTEXT_FILE=$(hook_context_file)"
echo "RESOLVED_FILE=$(hook_resolved_file)"
echo "AUDIT_FILE=$(hook_audit_file)"
echo "GIT_DIR=$(hook_git_dir)"
if type hook_has_user_tty >/dev/null 2>&1; then
  echo "HAS_USER_TTY_FN=1"
else
  echo "HAS_USER_TTY_FN=0"
fi

if type hook_seed_root_interactivity >/dev/null 2>&1; then
  echo "SEED_ROOT_INTERACTIVE_FN=1"
else
  echo "SEED_ROOT_INTERACTIVE_FN=0"
fi

unset UE_SYNC_ROOT_INTERACTIVE || true
hook_seed_root_interactivity
echo "ROOT_INTERACTIVE_SEEDED=${UE_SYNC_ROOT_INTERACTIVE:-<unset>}"

def_ni="$(hook_noninteractive_flag || true)"
echo "NONINTERACTIVE_DEFAULT=${def_ni:-<empty>}"

fni="$(UE_SYNC_FORCE_NONINTERACTIVE=1 hook_noninteractive_flag || true)"
echo "NONINTERACTIVE_FORCE_NONINTERACTIVE=${fni:-<empty>}"

fint="$(UE_SYNC_FORCE_INTERACTIVE=1 CI=1 hook_noninteractive_flag || true)"
echo "NONINTERACTIVE_FORCE_INTERACTIVE=${fint:-<empty>}"

r1="$(UE_SYNC_ROOT_INTERACTIVE=1 hook_noninteractive_flag || true)"
echo "NONINTERACTIVE_ROOT_INTERACTIVE_1=${r1:-<empty>}"

r0="$(UE_SYNC_ROOT_INTERACTIVE=0 hook_noninteractive_flag || true)"
echo "NONINTERACTIVE_ROOT_INTERACTIVE_0=${r0:-<empty>}"

gtp0="$(UE_SYNC_ROOT_INTERACTIVE= GIT_TERMINAL_PROMPT=0 hook_noninteractive_flag || true)"
echo "NONINTERACTIVE_GIT_TERMINAL_PROMPT_0=${gtp0:-<empty>}"

child_r1="$(UE_SYNC_ROOT_INTERACTIVE=1 sh -c '. "Scripts/git-hooks/hook-common.sh"; v="$(hook_noninteractive_flag || true)"; printf "%s" "${v:-<empty>}"')"
echo "NONINTERACTIVE_CHILD_ROOT_1=${child_r1:-<empty>}"

child_r0="$(UE_SYNC_ROOT_INTERACTIVE=0 sh -c '. "Scripts/git-hooks/hook-common.sh"; v="$(hook_noninteractive_flag || true)"; printf "%s" "${v:-<empty>}"')"
echo "NONINTERACTIVE_CHILD_ROOT_0=${child_r0:-<empty>}"

child_r1_gtp0="$(UE_SYNC_ROOT_INTERACTIVE=1 GIT_TERMINAL_PROMPT=0 sh -c '. "Scripts/git-hooks/hook-common.sh"; v="$(hook_noninteractive_flag || true)"; printf "%s" "${v:-<empty>}"')"
echo "NONINTERACTIVE_CHILD_ROOT_1_GTP0=${child_r1_gtp0:-<empty>}"
'@


Info "Validating: Git Bash can source hook-common.sh..."
$out = & $bash -lc $bashScript 2>&1
if ($LASTEXITCODE -ne 0) {
  Err "Failed to source hook-common.sh via Git Bash."
  $out | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  throw "hook-common sourcing failed."
}

Ok "hook-common.sh sourced successfully via Git Bash."
$out | ForEach-Object { Write-Host "  $($_)" -ForegroundColor DarkGray }

if (-not ($out -match '^HAS_USER_TTY_FN=1$')) {
  throw "hook_has_user_tty() missing in hook-common.sh"
}
Ok "hook_has_user_tty() present."

if (-not ($out -match '^SEED_ROOT_INTERACTIVE_FN=1$')) {
  throw "hook_seed_root_interactivity() missing in hook-common.sh"
}
Ok "hook_seed_root_interactivity() present."

$rootSeeded = ($out | Where-Object { $_ -like "ROOT_INTERACTIVE_SEEDED=*" } | Select-Object -First 1)
if ($rootSeeded -notmatch '^ROOT_INTERACTIVE_SEEDED=[01]$') {
  throw "ROOT_INTERACTIVE_SEEDED was not normalized to 0/1. Got: $rootSeeded"
}
Ok "ROOT_INTERACTIVE_SEEDED is normalized."

$forcedNonInteractive = ($out | Where-Object { $_ -like "NONINTERACTIVE_FORCE_NONINTERACTIVE=*" } | Select-Object -First 1)
if ($forcedNonInteractive -ne "NONINTERACTIVE_FORCE_NONINTERACTIVE=-NonInteractive") {
  throw "UE_SYNC_FORCE_NONINTERACTIVE override failed. Got: $forcedNonInteractive"
}
Ok "UE_SYNC_FORCE_NONINTERACTIVE override works."

$forcedInteractive = ($out | Where-Object { $_ -like "NONINTERACTIVE_FORCE_INTERACTIVE=*" } | Select-Object -First 1)
if ($forcedInteractive -ne "NONINTERACTIVE_FORCE_INTERACTIVE=<empty>") {
  throw "UE_SYNC_FORCE_INTERACTIVE override failed. Got: $forcedInteractive"
}
Ok "UE_SYNC_FORCE_INTERACTIVE override works."

$rootInteractive = ($out | Where-Object { $_ -like "NONINTERACTIVE_ROOT_INTERACTIVE_1=*" } | Select-Object -First 1)
if ($rootInteractive -ne "NONINTERACTIVE_ROOT_INTERACTIVE_1=<empty>") {
  throw "UE_SYNC_ROOT_INTERACTIVE=1 did not force interactive mode. Got: $rootInteractive"
}
Ok "UE_SYNC_ROOT_INTERACTIVE=1 forces interactive mode."

$rootNonInteractive = ($out | Where-Object { $_ -like "NONINTERACTIVE_ROOT_INTERACTIVE_0=*" } | Select-Object -First 1)
if ($rootNonInteractive -ne "NONINTERACTIVE_ROOT_INTERACTIVE_0=-NonInteractive") {
  throw "UE_SYNC_ROOT_INTERACTIVE=0 did not force non-interactive mode. Got: $rootNonInteractive"
}
Ok "UE_SYNC_ROOT_INTERACTIVE=0 forces non-interactive mode."

$gitTerminalPrompt0 = ($out | Where-Object { $_ -like "NONINTERACTIVE_GIT_TERMINAL_PROMPT_0=*" } | Select-Object -First 1)
if ($gitTerminalPrompt0 -ne "NONINTERACTIVE_GIT_TERMINAL_PROMPT_0=-NonInteractive") {
  throw "GIT_TERMINAL_PROMPT=0 did not force non-interactive mode. Got: $gitTerminalPrompt0"
}
Ok "GIT_TERMINAL_PROMPT=0 forces non-interactive mode."

$childRoot1 = ($out | Where-Object { $_ -like "NONINTERACTIVE_CHILD_ROOT_1=*" } | Select-Object -First 1)
if ($childRoot1 -ne "NONINTERACTIVE_CHILD_ROOT_1=<empty>") {
  throw "Child process did not inherit interactive root context. Got: $childRoot1"
}
Ok "Child process inherits UE_SYNC_ROOT_INTERACTIVE=1."

$childRoot0 = ($out | Where-Object { $_ -like "NONINTERACTIVE_CHILD_ROOT_0=*" } | Select-Object -First 1)
if ($childRoot0 -ne "NONINTERACTIVE_CHILD_ROOT_0=-NonInteractive") {
  throw "Child process did not inherit non-interactive root context. Got: $childRoot0"
}
Ok "Child process inherits UE_SYNC_ROOT_INTERACTIVE=0."

$childRoot1Gtp0 = ($out | Where-Object { $_ -like "NONINTERACTIVE_CHILD_ROOT_1_GTP0=*" } | Select-Object -First 1)
if ($childRoot1Gtp0 -ne "NONINTERACTIVE_CHILD_ROOT_1_GTP0=<empty>") {
  throw "Child process root interactive context was incorrectly overridden by GIT_TERMINAL_PROMPT=0. Got: $childRoot1Gtp0"
}
Ok "Child process root context beats child GIT_TERMINAL_PROMPT=0."

Ok "All hook plumbing checks passed."
