[CmdletBinding()]
param(
  [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [string]$FixturePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FixturePath.Trim().Length -eq 0) {
  $FixturePath = Join-Path $PSScriptRoot 'fixtures\book-source-selection-race.json'
}
$fixture = Get-Content -LiteralPath $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$implementationPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Components\BookSourceTabContent.ets'
$implementation = Get-Content -LiteralPath $implementationPath -Raw -Encoding UTF8

function Assert-RaceContract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "BOOK_SOURCE_SELECTION_RACE_CONTRACT_FAILED:$Message" }
}

Assert-RaceContract ($fixture.expected.staleResultAccepted -eq $false) 'fixture must require stale result rejection'
Assert-RaceContract ($fixture.expected.detailRouteAllowed -eq $false) 'fixture must require route rejection'
Assert-RaceContract ($fixture.selectedSourceIdAtOpen -ne $fixture.staleResultSourceId) 'fixture must contain distinct current and stale identities'

# This is the deterministic identity witness. The stale result does not belong
# to the selected source; the product must enforce the same predicate before
# mutating the list or opening detail.
$guardedAccepted = $fixture.staleResultSourceId -eq $fixture.selectedSourceIdAtOpen
Assert-RaceContract (-not $guardedAccepted) 'fixture identity predicate unexpectedly accepts stale result'

# Keep the expected implementation contract explicit. This assertion is
# intentionally run before the fix so the evidence records a real failure.
Assert-RaceContract ($implementation.Contains('bookSourceSelectionGeneration')) 'selection generation guard is missing'
Assert-RaceContract ($implementation.Contains('isBookSourceSelectionCurrent')) 'current-selection guard is missing'
Assert-RaceContract ($implementation.Contains('book.sourceId !== this.selectedBookSourceId')) 'detail route identity guard is missing'

$result = [ordered]@{
  status = 'passed'
  contract = [string]$fixture.case
  fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\', '/')
  assertions = 7
  generatedAt = [DateTime]::UtcNow.ToString('o')
}
$result | ConvertTo-Json -Depth 8
