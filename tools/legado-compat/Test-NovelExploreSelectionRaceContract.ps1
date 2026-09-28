[CmdletBinding()]
param(
  [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$implementationPath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\NovelExplorePage.ets'
$implementation = Get-Content -LiteralPath $implementationPath -Raw -Encoding UTF8

function Assert-ExploreRaceContract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw ('NOVEL_EXPLORE_SELECTION_RACE_CONTRACT_FAILED: ' + $Message)
  }
}

Assert-ExploreRaceContract ($implementation.Contains('exploreSelectionGeneration')) 'selection generation is missing'
Assert-ExploreRaceContract ($implementation.Contains('isExploreSelectionCurrent')) 'current-selection guard is missing'
Assert-ExploreRaceContract ($implementation.Contains('void this.loadExploreKinds(source.id, generation)')) 'source switch does not bind kind request to its generation'
Assert-ExploreRaceContract ($implementation.Contains('result.sourceId !== requestSourceId')) 'explore result source identity guard is missing'
Assert-ExploreRaceContract ($implementation.Contains('book.sourceId !== this.selectedSourceId')) 'detail route identity guard is missing'

$result = [ordered]@{
  status = 'passed'
  contract = 'novel_explore_selection_race'
  implementation = 'entry/src/main/ets/pages/NovelExplorePage.ets'
  assertions = 5
  generatedAt = [DateTime]::UtcNow.ToString('o')
}
$result | ConvertTo-Json -Depth 8

