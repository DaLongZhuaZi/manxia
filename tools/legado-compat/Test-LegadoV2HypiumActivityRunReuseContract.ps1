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
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-activity-run-reuse.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-harness-023-activity-run-reuse-contract-20260808.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Hypium activity run reuse contract failed: $Message" }
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

function Invoke-ActivityFixture {
  param(
    [Parameter(Mandatory = $true)][string]$FunctionText,
    [Parameter(Mandatory = $true)][object]$Fixture
  )
  $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legado-v2-activity-reuse-' + [Guid]::NewGuid().ToString('N'))
  [void][System.IO.Directory]::CreateDirectory($temporaryRoot)
  try {
    $RunActivityPath = Join-Path $temporaryRoot 'run-activity.json'
    $ExecutionProfile = 'full_workflow'
    $script:RunId = [string]$Fixture.currentRunId

    function Get-HypiumNow { return '2026-08-08T00:00:00.0000000Z' }
    function Get-HypiumSafeToken {
      param([string]$Value, [string]$Fallback = 'unclassified')
      $candidate = if ($null -eq $Value) { '' } else { $Value.Trim().ToLowerInvariant() }
      if ($candidate -match '^[a-z0-9_:-]{1,80}$') { return $candidate }
      return $Fallback
    }
    function Write-HypiumJsonAtomically {
      param([string]$Path, [object]$Value)
      [System.IO.File]::WriteAllText($Path, [string]($Value | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
    }

    [System.IO.File]::WriteAllText($RunActivityPath, (@{
      runId = [string]$Fixture.previousRunId
      evidencePath = [string]$Fixture.previousEvidencePath
    } | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    Invoke-Expression $FunctionText
    Write-HypiumRunActivity -Status 'running' -Phase 'preflight'
    $differentRun = Get-Content -LiteralPath $RunActivityPath -Raw -Encoding UTF8 | ConvertFrom-Json

    [System.IO.File]::WriteAllText($RunActivityPath, (@{
      runId = [string]$Fixture.currentRunId
      evidencePath = [string]$Fixture.sameRunEvidencePath
    } | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    Write-HypiumRunActivity -Status 'running' -Phase 'source_settled'
    $sameRun = Get-Content -LiteralPath $RunActivityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject][ordered]@{
      differentRunEvidencePath = [string]$differentRun.evidencePath
      sameRunEvidencePath = [string]$sameRun.evidencePath
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
  }
}

$result = $null
try {
  $fixture = Get-Content -LiteralPath $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $tokens = $null
  $parseErrors = $null
  $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
  $activityFunctions = @($runnerAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-HypiumRunActivity' }, $true))
  $functionText = if ($activityFunctions.Count -eq 1) { [string]$activityFunctions[0].Extent.Text } else { '' }

  Assert-Contract ([string]$fixture.contract -eq 'hypium_activity_run_reuse') 'fixture contract must identify activity run reuse'
  Assert-Contract ([bool]$fixture.differentRunMustClear) 'fixture must require stale path clearing'
  Assert-Contract ([bool]$fixture.sameRunMustPreserve) 'fixture must require same-run path preservation'
  Assert-Contract ($runnerText.Contains('$previousRunId') -and $runnerText.Contains('$script:RunId')) 'activity writer must compare the previous and current run ids'
  Assert-Contract (@($parseErrors).Count -eq 0) 'runner must remain syntactically valid'
  Assert-Contract ($activityFunctions.Count -eq 1) 'activity writer function must be discoverable'
  Assert-Contract ($functionText.Length -gt 0) 'activity writer function must be extractable'

  $projection = Invoke-ActivityFixture -FunctionText $functionText -Fixture $fixture
  Assert-Contract ([string]::IsNullOrWhiteSpace($projection.differentRunEvidencePath)) 'a different run must not inherit the previous evidence path'
  Assert-Contract ([string]$projection.sameRunEvidencePath -eq [string]$fixture.sameRunEvidencePath) 'the same run must preserve its evidence path'

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
    contract = 'hypium_activity_run_reuse'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

Write-ContractResult -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
