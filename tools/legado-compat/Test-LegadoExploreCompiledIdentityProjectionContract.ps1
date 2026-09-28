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
  $FixturePath = Join-Path $RepositoryRoot 'tools\\legado-compat\\fixtures\\legado-explore-compiled-identity-projection.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\\legado-compat\\evidence\\contract-legado-explore-compiled-identity-projection.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "LEGADO_EXPLORE_COMPILED_IDENTITY_PROJECTION_CONTRACT_FAILED:$Message" }
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
  $implementationPath = Join-Path $RepositoryRoot 'entry\\src\\main\\ets\\Framework\\Novel\\LegadoWorkflowOrchestrator.ets'
  Assert-Contract (Test-Path -LiteralPath $FixturePath -PathType Leaf) 'fixture is missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $implementationPath -PathType Leaf) 'orchestrator is missing'; $assertions++
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $implementation = [System.IO.File]::ReadAllText($implementationPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ([string]$fixture.contract -eq 'legado_explore_compiled_identity_projection') 'fixture contract is wrong'; $assertions++
  Assert-Contract ($implementation.Contains('V2_EXPLORE_KINDS_PROJECTION')) 'Explore compiled identity projection is missing'; $assertions++
  foreach ($field in @($fixture.requiredFields)) {
    Assert-Contract ($implementation.Contains([string]$field)) "projection field is missing: $field"; $assertions++
  }
  foreach ($forbidden in @($fixture.forbiddenFields)) {
    Assert-Contract (-not $implementation.Contains("${forbidden}=")) "projection must not emit field value: $forbidden"; $assertions++
  }
  Assert-Contract ($implementation.Contains('compiled.raw.sha256.substring(0, 16)')) 'projection must bind to the compiled raw document'; $assertions++

  $managerPath = Join-Path $RepositoryRoot 'entry\\src\\main\\ets\\Framework\\Novel\\NovelSourceManager.ets'
  $manager = [System.IO.File]::ReadAllText($managerPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ($manager.Contains('V2_EXPLORE_EXECUTOR_MISSING')) 'missing V2 Explore executor must be structured, not a silent empty result'; $assertions++
  Assert-Contract ($manager.Contains("throw new Error('V2_EXPLORE_EXECUTOR_MISSING')")) 'missing V2 Explore executor must throw a classified error'; $assertions++

  $result = [ordered]@{ status = 'passed'; contract = [string]$fixture.contract; assertions = $assertions; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
} catch {
  $result = [ordered]@{ status = 'failed'; contract = 'legado_explore_compiled_identity_projection'; assertions = $assertions; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
  exit 1
}
