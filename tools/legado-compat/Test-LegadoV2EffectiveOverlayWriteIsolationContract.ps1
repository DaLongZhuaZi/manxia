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
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-effective-overlay-write-isolation.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-harness-023-effective-overlay-write-isolation-contract-20260808.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Hypium effective overlay write isolation contract failed: $Message" }
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
$temporaryRoot = ''
try {
  $modulePath = Join-Path $RepoRoot 'tools\legado-compat\LegadoHypiumEvidencePaths.psm1'
  $auditPath = Join-Path $RepoRoot 'tools\legado-compat\Test-LegadoV2HypiumFullSourceEvidence.ps1'
  $fixture = Get-Content -LiteralPath $FixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $moduleText = [System.IO.File]::ReadAllText($modulePath, [System.Text.UTF8Encoding]::new($false, $true))
  $auditText = [System.IO.File]::ReadAllText($auditPath, [System.Text.UTF8Encoding]::new($false, $true))

  Assert-Contract ([string]$fixture.contract -eq 'hypium_effective_overlay_write_isolation') 'fixture contract must identify effective overlay write isolation'
  Assert-Contract ($moduleText.Contains('function Assert-LegadoHypiumEffectiveEvidenceDirectory')) 'path module must expose an effective directory guard'
  Assert-Contract ($auditText.Contains('Assert-LegadoHypiumEffectiveEvidenceDirectory')) 'evidence audit must invoke the effective directory guard'

  Import-Module -Name $modulePath -Force -ErrorAction Stop
  Assert-Contract ($null -ne (Get-Command Assert-LegadoHypiumEffectiveEvidenceDirectory -ErrorAction SilentlyContinue)) 'effective directory guard must be exported'

  $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legado-v2-effective-overlay-' + [Guid]::NewGuid().ToString('N'))
  $evidenceRoot = Join-Path $temporaryRoot 'evidence'
  $canonical = Join-Path $evidenceRoot ([string]$fixture.canonicalDirectoryName)
  $effective = Join-Path $evidenceRoot ([string]$fixture.effectiveDirectoryName)
  $nested = Join-Path $canonical 'nested'
  $outside = Join-Path $temporaryRoot 'outside'

  $sameRejected = $false
  try {
    Assert-LegadoHypiumEffectiveEvidenceDirectory -EvidenceRoot $evidenceRoot -BaselineEvidenceDirectory $canonical -EffectiveEvidenceDirectory $canonical | Out-Null
  } catch {
    $sameRejected = $_.Exception.Message.Contains([string]$fixture.expectedErrors.sameAsBaseline)
  }
  Assert-Contract $sameRejected 'effective directory equal to canonical baseline must be rejected'

  $nestedRejected = $false
  try {
    Assert-LegadoHypiumEffectiveEvidenceDirectory -EvidenceRoot $evidenceRoot -BaselineEvidenceDirectory $canonical -EffectiveEvidenceDirectory $nested | Out-Null
  } catch {
    $nestedRejected = $_.Exception.Message.Contains([string]$fixture.expectedErrors.nestedUnderBaseline)
  }
  Assert-Contract $nestedRejected 'effective directory below canonical baseline must be rejected'

  $outsideRejected = $false
  try {
    Assert-LegadoHypiumEffectiveEvidenceDirectory -EvidenceRoot $evidenceRoot -BaselineEvidenceDirectory $canonical -EffectiveEvidenceDirectory $outside | Out-Null
  } catch {
    $outsideRejected = $_.Exception.Message.Contains([string]$fixture.expectedErrors.outsideEvidenceRoot)
  }
  Assert-Contract $outsideRejected 'effective directory outside evidence root must be rejected'

  $resolvedEffective = Assert-LegadoHypiumEffectiveEvidenceDirectory -EvidenceRoot $evidenceRoot -BaselineEvidenceDirectory $canonical -EffectiveEvidenceDirectory $effective
  Assert-Contract ([System.IO.Path]::GetFullPath($resolvedEffective) -eq [System.IO.Path]::GetFullPath($effective)) 'sibling effective directory must be accepted'
  Assert-Contract ([bool]$fixture.siblingDirectoryAllowed) 'fixture must allow a sibling effective directory'

  $invalidAuditResultPath = Join-Path $temporaryRoot 'invalid-audit-result.json'
  $invalidAuditOutput = @(& pwsh -NoLogo -NoProfile -File $auditPath `
    -EvidenceDirectory $canonical `
    -OverlayRoot $evidenceRoot `
    -EffectiveEvidenceDirectory $canonical `
    -ExpectedSourceCount 0 `
    -ResultPath $invalidAuditResultPath 2>&1)
  $invalidAuditExitCode = $LASTEXITCODE
  Assert-Contract ($invalidAuditExitCode -ne 0) 'audit must reject a baseline-colliding effective directory'
  Assert-Contract ((($invalidAuditOutput | Out-String).Contains([string]$fixture.expectedErrors.sameAsBaseline))) 'audit must expose the collision classification'
  Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $canonical 'source-map.json'))) 'audit must not write source-map before rejecting the collision'

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
    contract = 'hypium_effective_overlay_write_isolation'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} finally {
  if ($temporaryRoot.Length -gt 0 -and (Test-Path -LiteralPath $temporaryRoot)) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}

Write-ContractResult -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
