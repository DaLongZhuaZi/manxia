[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\\legado-compat\\fixtures\\legado-explore-selection-identity.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\\legado-compat\\evidence\\contract-legado-explore-selection-identity.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "LEGADO_EXPLORE_SELECTION_IDENTITY_CONTRACT_FAILED:$Message" }
}

function Write-Result {
  param([object]$Value)
  $directory = Split-Path -Parent $ResultPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = $ResultPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $ResultPath, $true)
  } finally {
    if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$assertions = 0
try {
  $implementationPath = Join-Path $RepositoryRoot 'entry\\src\\main\\ets\\Framework\\Components\\BookSourceTabContent.ets'
  Assert-Contract (Test-Path -LiteralPath $FixturePath -PathType Leaf) 'fixture is missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $implementationPath -PathType Leaf) 'implementation is missing'; $assertions++
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $implementation = [System.IO.File]::ReadAllText($implementationPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'; $assertions++
  Assert-Contract ([string]$fixture.contract -eq 'legado_explore_selection_preserves_source_identity') 'fixture contract is wrong'; $assertions++
  Assert-Contract ($fixture.cases.Count -eq 2) 'fixture must contain the no-fallback and decorative-kind cases'; $assertions++
  Assert-Contract ($fixture.cases[0].selectedSourceId -ne $fixture.cases[0].neighborSourceId) 'identity fixture must contain distinct sources'; $assertions++
  Assert-Contract ($implementation.Contains('findFirstExecutableExploreKindIndex')) 'default executable kind resolver is missing'; $assertions++
  Assert-Contract ($implementation.Contains('this.selectedBookSourceKindIndex = defaultKindIndex')) 'default kind index must use executable resolver'; $assertions++
  Assert-Contract ($implementation.Contains("'该书源没有可执行的发现分类'")) 'empty kinds must remain visible on the selected source'; $assertions++
  Assert-Contract (-not $implementation.Contains('findNextBookSourceWithExploreKinds')) 'selected source must never silently switch to a neighboring source'; $assertions++
  Assert-Contract (-not $implementation.Contains('自动切换到下一个可用书源')) 'cross-source discovery fallback log must be absent'; $assertions++
  Assert-Contract ($implementation.Contains('kind.url.trim().length === 0')) 'empty URL decorative kinds must not execute'; $assertions++

  $result = [ordered]@{ status = 'passed'; contract = $fixture.contract; assertions = $assertions; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
} catch {
  $result = [ordered]@{ status = 'failed'; contract = 'legado_explore_selection_preserves_source_identity'; assertions = $assertions; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
  exit 1
}
