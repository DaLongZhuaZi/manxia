[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Legado V2 full workflow dispatch contract failed: $Message"
  }
}

$runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$runner = Read-Utf8Text -Path $runnerPath
$profileStart = $runner.IndexOf("[ValidateSet('safe_search_only', 'safe_read_path'")
Assert-Contract ($profileStart -ge 0) 'execution profile declaration must remain discoverable.'
Assert-Contract ($runner.Contains("'full_workflow'")) 'the runner must expose a full_workflow execution profile.'
Assert-Contract ($runner.Contains('function Set-HypiumFullWorkflow') -or $runner.Contains('full_workflow_requested')) 'full workflow dispatch must have an explicit orchestration branch, not an implicit safe-read alias.'
Assert-Contract ($runner.Contains('$ExecutionProfile -eq ''full_workflow''')) 'the full workflow profile must be selected by the dispatcher.'
Assert-Contract ($runner.Contains('Invoke-HypiumSourceExplore') -and $runner.Contains('Invoke-HypiumSourceSearch')) 'full workflow dispatch must be able to execute Explore and Search independently.'
Assert-Contract ($runner.Contains('search_workflow_missing')) 'an Explore-only source must settle Search as missing capability rather than profile_explore_only.'
Assert-Contract ($runner.Contains('exploreAttempt') -or $runner.Contains('additionalWorkflowEvidence')) 'source evidence must preserve Explore evidence when Search/read workflows run afterward.'
Assert-Contract (-not $runner.Contains('$ExecutionProfile -eq ''full_workflow'' -and $exploreCapability') -or $runner.Contains('full_workflow_requested')) 'full workflow must not reuse the early-return Explore-only branch without an explicit continuation marker.'

[pscustomobject]@{
  status = 'passed'
  contract = 'full_workflow_explore_search_independent_dispatch'
  assertions = 8
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
} | ConvertTo-Json -Compress
