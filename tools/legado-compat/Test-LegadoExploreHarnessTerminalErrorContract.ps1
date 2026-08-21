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
  $FixturePath = Join-Path $RepositoryRoot 'tools\\legado-compat\\fixtures\\legado-explore-harness-terminal-error.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\\legado-compat\\evidence\\contract-legado-explore-harness-terminal-error.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "LEGADO_EXPLORE_HARNESS_TERMINAL_ERROR_CONTRACT_FAILED:$Message" }
}

function Write-Result {
  param([object]$Value)
  $directory = Split-Path -Parent $ResultPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($directory) }
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
  $driverPath = Join-Path $RepositoryRoot 'tools\\legado-compat\\Invoke-LegadoV2HypiumNavigation.py'
  Assert-Contract (Test-Path -LiteralPath $FixturePath -PathType Leaf) 'fixture is missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $driverPath -PathType Leaf) 'navigation driver is missing'; $assertions++
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $driver = [System.IO.File]::ReadAllText($driverPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ([string]$fixture.contract -eq 'legado_explore_harness_observes_terminal_error_without_serial_timeout') 'fixture contract is wrong'; $assertions++
  Assert-Contract ($driver.Contains('wait_for_explore_kind_or_error')) 'driver must poll kind and terminal error together'; $assertions++
  Assert-Contract ($driver.Contains('evidence["explore_outcome"] = "no_executable_kind"')) 'terminal empty-kind outcome must be explicit'; $assertions++
  Assert-Contract (-not $driver.Contains('kind = driver.wait_for_component(by.id(explore_kind_id(0)), timeout=timeout)')) 'driver must not serially wait the full timeout for a kind before checking error'; $assertions++
  Assert-Contract ($driver.Contains('find_component(by.id(BOOK_SOURCE_EXPLORE_ERROR_ID))')) 'driver must inspect the stable explore error control'; $assertions++
  Assert-Contract ($driver.Contains('driver.wait(0.4)')) 'terminal poll must remain bounded'; $assertions++

  $result = [ordered]@{ status = 'passed'; contract = [string]$fixture.contract; assertions = $assertions; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
} catch {
  $result = [ordered]@{ status = 'failed'; contract = 'legado_explore_harness_observes_terminal_error_without_serial_timeout'; assertions = $assertions; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
  exit 1
}
