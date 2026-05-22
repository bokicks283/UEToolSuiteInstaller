function Test-UEToolSuiteDispatcherHelpToken {
  [CmdletBinding()]
  param([string]$Token)

  if ([string]::IsNullOrWhiteSpace($Token)) {
    return $false
  }

  $normalized = $Token.Trim().ToLowerInvariant()
  return ($normalized -in @("help", "--help", "-help", "-h", "/?", "-?"))
}

function Get-UEToolSuiteDispatcherDomainStatus {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $moduleRoot = Join-Path $RepoRoot "Scripts\UETools"
  return [ordered]@{
    docs = (Test-Path -LiteralPath (Join-Path $moduleRoot "UEToolSuite.Docs.psm1") -PathType Leaf)
    ai   = (Test-Path -LiteralPath (Join-Path $moduleRoot "UEToolSuite.AI.psm1") -PathType Leaf)
    art  = (Test-Path -LiteralPath (Join-Path $moduleRoot "UEToolSuite.Art.psm1") -PathType Leaf)
    init = (Test-Path -LiteralPath (Join-Path $moduleRoot "UEToolSuite.Init.psm1") -PathType Leaf)
    git  = (Test-Path -LiteralPath (Join-Path $moduleRoot "UEToolSuite.Git.psm1") -PathType Leaf)
  }
}

function Get-UEToolSuiteDispatcherRootHelpText {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$RepoRoot)

  $status = Get-UEToolSuiteDispatcherDomainStatus -RepoRoot $RepoRoot
  $domainStateLines = @(
    "  docs     {0}" -f $(if ($status.docs) { "[installed]" } else { "[not installed]" })
    "  ai       {0}" -f $(if ($status.ai) { "[installed]" } else { "[not installed]" })
    "  art      {0}" -f $(if ($status.art) { "[installed]" } else { "[not installed]" })
    "  init     {0}" -f $(if ($status.init) { "[installed]" } else { "[not installed]" })
    "  git      {0}" -f $(if ($status.git) { "[installed]" } else { "[not installed]" })
  )

  return @(
    "UE Tool Suite dispatcher."
    "Usage:"
    "  ue-tools <command> [options]"
    "  ue <command> [options]"
    ""
    "Root commands:"
    "  help                    Show this help text."
    "  build [sync options]    Run Unreal build/sync flow."
    ""
    "Domain commands:"
    "  docs <args...>          Route to docs tooling."
    "  ai prompt <args...>     Build AI startup prompts."
    "  art <args...>           Run ArtSource tools."
    "  init <args...>          Run repo initialization."
    "  git <args...>           Run binary conflict helper tooling."
    ""
    "Installed domain status:"
  ) + $domainStateLines + @(
    ""
    "Examples:"
    "  ue-tools help"
    "  ue-tools build -DryRun"
    "  ue-tools docs help"
    "  ue-tools ai prompt -Task `"Investigate UnrealSync failures`" -IncludePrivate"
    "  ue-tools git status"
    ""
    "Notes:"
    "  - If the first token starts with '-' or '/', 'build' is assumed."
    "  - Optional domains stay discoverable and return install guidance when missing."
  )
}

function Get-UEToolSuiteDispatcherDomainHelpText {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$DomainName)

  switch ($DomainName.ToLowerInvariant()) {
    "build" {
      return @(
        "Usage: ue-tools build [UnrealSync options]"
        "Examples:"
        "  ue-tools build -DryRun"
        "  ue-tools build -NoBuild -NoRegen"
        "  ue-tools build -Config Debug -Platform Win64"
        "Notes:"
        "  - Dispatcher always passes -Force to Unreal sync."
      )
    }
    "docs" {
      return @(
        "UE project docs automation."
        "Usage: ue-tools docs <docs command> [options]"
        "Examples:"
        "  ue-tools docs help"
        "  ue-tools docs new-page Workflow Daily-Flow -Title `"Daily Flow`""
      )
    }
    "ai" {
      return @(
        "AI startup prompt builder."
        "Usage: ue-tools ai prompt [options]"
        "Examples:"
        "  ue-tools ai prompt -Task `"Review coding standards docs`""
        "  ue-tools ai prompt -IncludePrivate -CopyToClipboard"
      )
    }
    "art" {
      return @(
        "Usage: ue-tools art [options]"
        "Examples:"
        "  ue-tools art"
        "  ue-tools art -RepoRoot C:\Path\To\Repo"
      )
    }
    "init" {
      return @(
        "Usage: ue-tools init [init options]"
        "Examples:"
        "  ue-tools init -SkipUnrealSync -SkipOptionalToolSetup"
      )
    }
    "git" {
      return @(
        "Usage: ue-tools git <ours|theirs|status|sync|continue|abort|restart|help> [options]"
        "Examples:"
        "  ue-tools git status"
        "  ue-tools git ours `"**/*.uasset`""
      )
    }
    default {
      return @("Unknown help topic '$DomainName'. Run 'ue-tools help'.")
    }
  }
}

function Get-UEToolSuiteDispatcherDomainMissingMessage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][string]$RequiredPath
  )

  return ("The '{0}' domain is not installed for this repo. Missing required path: {1}. Re-run the installer with this domain included." -f $Domain, $RequiredPath)
}

function Get-UEToolSuiteDispatcherTailArguments {
  [CmdletBinding()]
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

  [string[]]$tail = @($Values | Select-Object -Skip $Skip)
  return $tail
}

function Assert-UEToolSuiteDispatcherDomainInstalled {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][string]$RequiredRelativePath
  )

  $requiredPath = Join-Path $RepoRoot $RequiredRelativePath
  if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
    throw (Get-UEToolSuiteDispatcherDomainMissingMessage -Domain $Domain -RequiredPath $requiredPath)
  }

  return $requiredPath
}

function Invoke-UEToolSuiteDispatcher {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [AllowNull()][string[]]$CommandArguments = @()
  )

  $normalizedArgs = New-Object System.Collections.Generic.List[string]
  foreach ($arg in @($CommandArguments)) {
    if ($null -eq $arg) { continue }
    $stringValue = [string]$arg
    if ([string]::IsNullOrWhiteSpace($stringValue)) { continue }
    $normalizedArgs.Add($stringValue) | Out-Null
  }
  $argsList = @($normalizedArgs.ToArray())

  if ($argsList.Count -eq 0) {
    @(Get-UEToolSuiteDispatcherRootHelpText -RepoRoot $RepoRoot) | Write-Output
    return
  }

  $command = [string]$argsList[0]
  [string[]]$remaining = if ($argsList.Count -gt 1) {
    [string[]](Get-UEToolSuiteDispatcherTailArguments -Values $argsList -Skip 1)
  }
  else {
    @()
  }

  if (Test-UEToolSuiteDispatcherHelpToken -Token $command) {
    if ($remaining.Count -gt 0) {
      @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName ([string]$remaining[0])) | Write-Output
      return
    }

    @(Get-UEToolSuiteDispatcherRootHelpText -RepoRoot $RepoRoot) | Write-Output
    return
  }

  if ($command.StartsWith("-") -or $command.StartsWith("/")) {
    Invoke-UEToolSuiteUnrealBuild -RepoRoot $RepoRoot -CommandArguments $argsList
    return
  }

  switch ($command.Trim().ToLowerInvariant()) {
    "help" {
      if ($remaining.Count -gt 0) {
        @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName ([string]$remaining[0])) | Write-Output
      }
      else {
        @(Get-UEToolSuiteDispatcherRootHelpText -RepoRoot $RepoRoot) | Write-Output
      }
      return
    }
    "build" {
      foreach ($arg in @($remaining)) {
        if (Test-UEToolSuiteDispatcherHelpToken -Token $arg) {
          @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "build") | Write-Output
          return
        }
      }

      Invoke-UEToolSuiteUnrealBuild -RepoRoot $RepoRoot -CommandArguments $remaining
      return
    }
    "docs" {
      Invoke-UEToolSuiteDocsCommand -RepoRoot $RepoRoot -CommandArguments $remaining
      return
    }
    "ai" {
      if ($remaining.Count -eq 0) {
        @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "ai") | Write-Output
        return
      }

      $aiSubcommand = [string]$remaining[0]
      [string[]]$aiRemaining = if ($remaining.Count -gt 1) {
        [string[]](Get-UEToolSuiteDispatcherTailArguments -Values $remaining -Skip 1)
      }
      else {
        @()
      }

      if (Test-UEToolSuiteDispatcherHelpToken -Token $aiSubcommand) {
        @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "ai") | Write-Output
        return
      }

      if ($aiSubcommand.StartsWith("-") -or $aiSubcommand.StartsWith("/")) {
        Invoke-UEToolSuiteAIPromptCommand -RepoRoot $RepoRoot -CommandArguments $remaining
        return
      }

      switch ($aiSubcommand.Trim().ToLowerInvariant()) {
        "prompt" {
          foreach ($arg in @($aiRemaining)) {
            if (Test-UEToolSuiteDispatcherHelpToken -Token $arg) {
              @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "ai") | Write-Output
              return
            }
          }

          Invoke-UEToolSuiteAIPromptCommand -RepoRoot $RepoRoot -CommandArguments $aiRemaining
          return
        }
        default {
          throw "Unknown ai subcommand '$aiSubcommand'. Run 'ue-tools help ai'."
        }
      }
    }
    "art" {
      foreach ($arg in @($remaining)) {
        if (Test-UEToolSuiteDispatcherHelpToken -Token $arg) {
          @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "art") | Write-Output
          return
        }
      }

      Invoke-UEToolSuiteArtCommand -RepoRoot $RepoRoot -CommandArguments $remaining
      return
    }
    "init" {
      foreach ($arg in @($remaining)) {
        if (Test-UEToolSuiteDispatcherHelpToken -Token $arg) {
          @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "init") | Write-Output
          return
        }
      }

      Invoke-UEToolSuiteInitCommand -RepoRoot $RepoRoot -CommandArguments $remaining
      return
    }
    "git" {
      foreach ($arg in @($remaining)) {
        if (Test-UEToolSuiteDispatcherHelpToken -Token $arg) {
          @(Get-UEToolSuiteDispatcherDomainHelpText -DomainName "git") | Write-Output
          return
        }
      }

      Invoke-UEToolSuiteGitCommand -RepoRoot $RepoRoot -CommandArguments $remaining
      return
    }
    default {
      throw "Unknown ue-tools command '$command'. Run 'ue-tools help'."
    }
  }
}

Export-ModuleMember -Function `
  Test-UEToolSuiteDispatcherHelpToken, `
  Get-UEToolSuiteDispatcherDomainStatus, `
  Get-UEToolSuiteDispatcherRootHelpText, `
  Get-UEToolSuiteDispatcherDomainHelpText, `
  Get-UEToolSuiteDispatcherDomainMissingMessage, `
  Get-UEToolSuiteDispatcherTailArguments, `
  Assert-UEToolSuiteDispatcherDomainInstalled, `
  Invoke-UEToolSuiteDispatcher
