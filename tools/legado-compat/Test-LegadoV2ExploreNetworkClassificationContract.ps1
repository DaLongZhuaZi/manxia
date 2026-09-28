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
    throw "Legado V2 Explore network classification contract failed: $Message"
  }
}

$componentPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Components\BookSourceTabContent.ets'
$driverPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py'
$runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$component = Read-Utf8Text -Path $componentPath
$driver = Read-Utf8Text -Path $driverPath
$runner = Read-Utf8Text -Path $runnerPath

# This is intentionally a pre-fix regression contract.  A dynamic Explore
# failure has no card to host the trace, so the UI must refresh and expose the
# persisted trace in the error state before the device harness can classify it.
Assert-Contract ($component.Contains('await this.refreshBookSourceExploreTrace(getNovelSourceManager())')) 'Explore error handling must refresh the persisted trace after script/transport failure.'
Assert-Contract ($component.Contains(".id('novel_book_source_explore_v2_trace')")) 'Explore error state must expose the same stable trace id used by the successful result state.'
Assert-Contract ($driver.Contains('observe_explore_trace_on_error')) 'Hypium must retain a redacted Explore trace when no kind/result card exists.'
Assert-Contract ($driver.Contains('observe_explore_trace_on_empty')) 'Hypium must retain a redacted Explore trace when a valid kind returns an empty result list.'
Assert-Contract ($driver.Contains('parse_explore_trace_text')) 'Hypium must parse the persisted Explore trace through a single typed helper.'
Assert-Contract ($runner.Contains('Test-HypiumExploreExternalBoundary')) 'The full-source runner must classify Explore transport evidence through an explicit boundary predicate.'
$emptyOutcomeIndex = $runner.IndexOf("Outcome 'explore_empty_without_reference'")
$exploreBoundaryIndex = $runner.IndexOf('Test-HypiumExploreExternalBoundary -Attempt $attempt')
Assert-Contract ($emptyOutcomeIndex -ge 0 -and $exploreBoundaryIndex -gt $emptyOutcomeIndex) 'A trace-backed Explore empty result must be blocked before external-network classification.'
$failureIndex = $runner.IndexOf("Outcome 'explore_harness_or_engine_failure'")
Assert-Contract ($exploreBoundaryIndex -ge 0 -and $failureIndex -gt $exploreBoundaryIndex) 'Explore network classification must run before generic harness failure classification.'
Assert-Contract ($runner.Contains('$findingAttempts = 0') -and $runner.Contains('$Record.workflows.PSObject.Properties') -and $runner.Contains('attempts = $findingAttempts')) 'Governance findings must use the maximum executed workflow attempt, including Explore-only runs.'

[pscustomobject]@{
  status = 'passed'
  contract = 'persisted_explore_network_trace_to_blocked_state'
} | ConvertTo-Json -Compress
