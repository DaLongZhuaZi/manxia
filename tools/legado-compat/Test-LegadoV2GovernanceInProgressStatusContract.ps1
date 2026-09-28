[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-governance-in-progress-status.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-harness-023-governance-in-progress-status-contract-20260808.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Hypium governance in-progress status contract failed: $Message" }
  $script:assertions++
}

function Write-ContractResult {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = $Path + '.tmp-' + $PID
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
try {
  $fixture = Get-Content -LiteralPath $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $scriptPath = Join-Path $RepoRoot 'tools\legado-compat\Update-LegadoGovernanceState.ps1'
  $scriptText = [System.IO.File]::ReadAllText($scriptPath, [System.Text.UTF8Encoding]::new($false, $true))

  Assert-Contract ([string]$fixture.contract -eq 'hypium_governance_in_progress_status') 'fixture contract must identify the status compatibility boundary'
  Assert-Contract ([string]$fixture.requiredStatus -eq 'in_progress') 'fixture must require in_progress'
  foreach ($parameterName in @($fixture.parameterNames)) {
    $parameterToken = '[string]$' + [string]$parameterName
    $pattern = "ValidateSet\([^)]*'in_progress'[^)]*\).*" + [regex]::Escape($parameterToken)
    Assert-Contract ([regex]::IsMatch($scriptText, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) ("{0} must accept in_progress" -f $parameterName)
  }
  Assert-Contract ($scriptText.Contains("'in_progress'")) 'updater must preserve the machine state status token'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertions
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'hypium_governance_in_progress_status'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

Write-ContractResult -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
