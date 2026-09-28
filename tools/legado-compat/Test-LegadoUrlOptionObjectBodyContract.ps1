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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-url-option-object-body.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-url-option-object-body.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "LEGADO_URL_OPTION_OBJECT_BODY_CONTRACT_FAILED:$Message" }
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
  $typesPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceTypes.ets'
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoUrlAnalyzer.ets'
  $orchestratorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
  Assert-Contract (Test-Path -LiteralPath $FixturePath -PathType Leaf) 'fixture is missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $typesPath -PathType Leaf) 'types are missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $analyzerPath -PathType Leaf) 'URL analyzer is missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $orchestratorPath -PathType Leaf) 'workflow orchestrator is missing'; $assertions++
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $types = [System.IO.File]::ReadAllText($typesPath, [System.Text.UTF8Encoding]::new($false, $true))
  $analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $orchestrator = [System.IO.File]::ReadAllText($orchestratorPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'; $assertions++
  Assert-Contract ([string]$fixture.contract -eq 'legado_url_option_object_body') 'fixture contract is wrong'; $assertions++
  Assert-Contract ($types.Contains('export type LegadoUrlOptionBody = string | Object;')) 'option body type must preserve objects'; $assertions++
  Assert-Contract ($analyzer.Contains('normalizeUrlOptionBody')) 'URL analyzer must normalize object request bodies'; $assertions++
  Assert-Contract ($analyzer.Contains('SafeUtils.stringifyJson(value')) 'object body must use JSON serialization'; $assertions++
  Assert-Contract ($orchestrator.Contains('planning_failed:${this.toTraceDiagnosticToken(message)}')) 'planning failures must retain a redacted diagnostic token'; $assertions++
  $body = [string]($fixture.option.body | ConvertTo-Json -Compress -Depth 8)
  Assert-Contract ($body -eq [string]$fixture.expected.body) 'fixture body serialization differs from Legado GSON compact semantics'; $assertions++
  Assert-Contract (([string]$fixture.option.method).ToUpperInvariant() -eq [string]$fixture.expected.method) 'POST method was not retained'; $assertions++
  $result = [ordered]@{ status = 'passed'; contract = [string]$fixture.contract; assertions = $assertions; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
} catch {
  $result = [ordered]@{ status = 'failed'; contract = 'legado_url_option_object_body'; assertions = $assertions; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
  exit 1
}
