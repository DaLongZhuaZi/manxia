[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-url-option-request-carrier.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-url-option-request-carrier.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "LEGADO_URL_OPTION_REQUEST_CARRIER_CONTRACT_FAILED:$Message" }
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Write-Result {
  param([object]$Value)
  $directory = Split-Path -Parent $ResultPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = $ResultPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText(
      $temporaryPath,
      [string]($Value | ConvertTo-Json -Depth 12),
      [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::Move($temporaryPath, $ResultPath, $true)
  } finally {
    if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$assertions = 0
try {
  $typesPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceTypes.ets'
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
  $managerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets'
  $urlAnalyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoUrlAnalyzer.ets'
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  $types = Read-Utf8Text -Path $typesPath
  $orchestrator = Read-Utf8Text -Path $analyzerPath
  $manager = Read-Utf8Text -Path $managerPath
  $urlAnalyzer = Read-Utf8Text -Path $urlAnalyzerPath

  Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'; $assertions++
  Assert-Contract ([string]$fixture.contract -eq 'legado_url_option_request_carrier') 'fixture contract is wrong'; $assertions++
  Assert-Contract (@($fixture.cases).Count -eq 4) 'fixture must cover POST/body, WebView/cookie, same-identity collision and opaque data URLs'; $assertions++
  Assert-Contract ($types.Contains('export class LegadoRequestCarrier')) 'source types must define a typed request carrier'; $assertions++
  Assert-Contract ($types.Contains('readonly identityUrl: string') -and $types.Contains('readonly requestUrlTemplate: string')) 'carrier must separate identity URL from deferred request expression'; $assertions++
  Assert-Contract ($types.Contains('requestCarrier?: LegadoRequestCarrier')) 'book, chapter and search records must expose only an in-memory carrier'; $assertions++
  Assert-Contract ($orchestrator.Contains('requestCarrier: new LegadoRequestCarrier')) 'Search/Explore must create the carrier before options are consumed'; $assertions++
  Assert-Contract ($orchestrator.Contains('resolveRequestUrlTemplate(bookUrl, response.finalUrl)')) 'workflow must retain the completed request expression'; $assertions++
  Assert-Contract ($orchestrator.Contains('resolveUrlWithoutOptions')) 'identity URL resolution must not execute URL-option JSON early'; $assertions++
  Assert-Contract ($manager.Contains('Map<string, LegadoRequestCarrier>')) 'manager must store typed carriers rather than template-only strings'; $assertions++
  Assert-Contract ($manager.Contains('REQUEST_CARRIER_UNAVAILABLE:identity_mismatch') -and $manager.Contains('REQUEST_CARRIER_UNAVAILABLE:ambiguous_identity')) 'carrier identity failures must be explicit'; $assertions++
  Assert-Contract ($manager.Contains('requestCarrierKey') -and $manager.Contains('registerV2RequestCarrier')) 'navigation may carry only an opaque carrier token'; $assertions++
  Assert-Contract ($urlAnalyzer.Contains('findOptionSeparator')) 'option boundary must be identified without parsing options during identity resolution'; $assertions++

  $invalidCases = @($fixture.cases | Where-Object { [string]$_.kind -ne 'data_url' -and [string]$_.identityUrl -match ',\s*\{' })
  Assert-Contract ($invalidCases.Count -eq 0) 'identityUrl fixture values must not retain option JSON'; $assertions++
  $dataCases = @($fixture.cases | Where-Object { [string]$_.kind -eq 'data_url' })
  Assert-Contract ($dataCases.Count -eq 1 -and [string]$dataCases[0].identityUrl -like 'data:*{*') 'data URLs must remain opaque identity values'; $assertions++
  $deferredOptionCases = @($fixture.cases | Where-Object { @($_.deferredOptions).Count -gt 0 })
  Assert-Contract ($deferredOptionCases.Count -eq 3) 'all fixture cases must retain deferred options'; $assertions++

  $result = [ordered]@{
    status = 'passed'
    contract = 'legado_url_option_request_carrier'
    assertions = $assertions
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    baseline = $fixture.baseline
  }
} catch {
  $result = [ordered]@{
    status = 'failed'
    contract = 'legado_url_option_request_carrier'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
  }
}

Write-Result -Value $result
$result | ConvertTo-Json -Depth 12
if ($result.status -ne 'passed') { exit 1 }
