[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ([string]::IsNullOrWhiteSpace($FixturePath)) { $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-evidence-run-isolation.json' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-harness-023-evidence-run-isolation-contract-20260808.json' }

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Hypium evidence run isolation contract failed: $Message" }
  $script:assertions++
}

try {
  $runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  $wrapperPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2FullSourceDeviceRunner.ps1'
  $startPath = Join-Path $RepoRoot 'tools\legado-compat\Start-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  $getPath = Join-Path $RepoRoot 'tools\legado-compat\Get-LegadoV2HypiumFullSourceDeviceRun.ps1'
  $pathsModulePath = Join-Path $RepoRoot 'tools\legado-compat\LegadoHypiumEvidencePaths.psm1'
  $auditPath = Join-Path $RepoRoot 'tools\legado-compat\Test-LegadoV2HypiumFullSourceEvidence.ps1'
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $wrapperText = [System.IO.File]::ReadAllText($wrapperPath, [System.Text.UTF8Encoding]::new($false, $true))
  $startText = [System.IO.File]::ReadAllText($startPath, [System.Text.UTF8Encoding]::new($false, $true))
  $getText = [System.IO.File]::ReadAllText($getPath, [System.Text.UTF8Encoding]::new($false, $true))
  $pathsModuleText = [System.IO.File]::ReadAllText($pathsModulePath, [System.Text.UTF8Encoding]::new($false, $true))
  $auditText = [System.IO.File]::ReadAllText($auditPath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json

  Assert-Contract (Test-Path -LiteralPath $pathsModulePath) 'path module must exist'
  Assert-Contract ($runnerText.Contains('LegadoHypiumEvidencePaths.psm1')) 'V2 runner must load the evidence path module'
  Assert-Contract ($runnerText.Contains('New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot')) 'default runner output must be run-scoped'
  Assert-Contract ($runnerText.Contains('Assert-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot')) 'explicit runner output must reject the canonical baseline'
  Assert-Contract ($runnerText.Contains('Assert-LegadoHypiumRunActivityPath -EvidenceDirectory $EvidenceDirectory')) 'run activity must remain inside the run directory'
  Assert-Contract ($pathsModuleText.Contains("throw 'BASELINE_EVIDENCE_WRITE_FORBIDDEN'")) 'baseline write rejection must be reachable through the path contract'
  Assert-Contract ($pathsModuleText.Contains("throw 'RUN_ACTIVITY_PATH_OUTSIDE_RUN_DIRECTORY'")) 'run activity escape must be rejected by the path contract'
  Assert-Contract ($runnerText.Contains('Write-HypiumJsonAtomically -Path $path -Value $evidence')) 'source evidence must be atomically written'
  Assert-Contract (-not $runnerText.Contains('$EvidenceDirectory = Join-Path $PSScriptRoot ''evidence\full-source-v2-hypium-device''')) 'runner must not default writes to the canonical baseline directory'
  Assert-Contract ($wrapperText.Contains('[string]$RunActivityPath =') -and $wrapperText.Contains('RunActivityPath = $RunActivityPath')) 'wrapper must forward the run activity path'
  Assert-Contract ($startText.Contains('New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot')) 'detached launcher must allocate a new run directory'
  Assert-Contract ($startText.Contains('@(''-EvidenceDirectory'', $evidenceDirectory)')) 'detached launcher must pass the run directory to the child runner'
  Assert-Contract ($startText.Contains('runEvidenceDirectory = (ConvertTo-LegadoHypiumEvidenceRelativePath')) 'manifest must bind the child run directory'
  Assert-Contract ($startText.Contains('$manifestPath = Join-Path $controlDirectory ''detached-run.json''')) 'control manifest must be outside the canonical baseline'
  Assert-Contract ($startText.Contains('controlDirectory = (ConvertTo-LegadoHypiumEvidenceRelativePath')) 'manifest must identify its independent control directory'
  Assert-Contract ($getText.Contains('[string]$ControlDirectory =') -and $getText.Contains('legacyManifestPath')) 'run monitor must support the new control directory and read-only legacy fallback'
  Assert-Contract ($getText.Contains('runEvidenceDirectory') -and $getText.Contains('Join-Path $runEvidenceDirectory')) 'run monitor must follow the manifest to run-scoped activity and logs'
  Assert-Contract ($auditText.Contains('Get-ChildItem -LiteralPath $OverlayRoot -Directory')) 'overlay audit must discover run-scoped sibling directories'
  Assert-Contract ([string]$fixture.canonicalDirectoryName -eq 'full-source-v2-hypium-device') 'fixture canonical directory must be explicit'
  Assert-Contract ([string]$fixture.controlDirectoryName -eq 'full-source-v2-hypium-device-control') 'fixture control directory must be separate'
  Assert-Contract ([string]$fixture.runDirectoryPrefix -eq 'full-source-v2-hypium-device-run-') 'fixture run directory prefix must be explicit'
  Assert-Contract ([string]$fixture.baselineWritePolicy -eq 'forbidden') 'fixture must forbid baseline writes'
  Assert-Contract (@($fixture.runDirectoryScenarios).Count -eq 2) 'fixture must cover two independent runs'
  $runGuardStart = $pathsModuleText.IndexOf('function Assert-LegadoHypiumRunEvidenceDirectory', [System.StringComparison]::Ordinal)
  $runGuardEnd = $pathsModuleText.IndexOf("`n}`n`nfunction Assert-LegadoHypiumEffectiveEvidenceDirectory", $runGuardStart, [System.StringComparison]::Ordinal)
  $runGuardText = if ($runGuardStart -ge 0 -and $runGuardEnd -gt $runGuardStart) { $pathsModuleText.Substring($runGuardStart, $runGuardEnd - $runGuardStart) } else { '' }
  Assert-Contract ($runGuardText.Contains('StartsWith($canonical')) 'run evidence guard must reject canonical descendants'

  Import-Module -Name $pathsModulePath -Force -ErrorAction Stop
  $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legado-v2-evidence-path-contract-' + [Guid]::NewGuid().ToString('N'))
  $scriptRoot = Join-Path $temporaryRoot 'compat'
  [void][System.IO.Directory]::CreateDirectory($scriptRoot)
  try {
    $canonical = Get-LegadoHypiumCanonicalEvidenceDirectory -ScriptRoot $scriptRoot
    $runA = New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $scriptRoot -RunToken 'fixture-run-a'
    $runB = New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $scriptRoot -RunToken 'fixture-run-b'
    Assert-Contract (-not $runA.Equals($canonical, [System.StringComparison]::OrdinalIgnoreCase)) 'run A must not equal canonical baseline'
    Assert-Contract (-not $runB.Equals($canonical, [System.StringComparison]::OrdinalIgnoreCase)) 'run B must not equal canonical baseline'
    Assert-Contract (-not $runA.Equals($runB, [System.StringComparison]::OrdinalIgnoreCase)) 'two run tokens must produce distinct paths'
    Assert-Contract ([System.IO.Path]::GetFileName($runA) -eq [string]$fixture.runDirectoryScenarios[0].expectedDirectory) 'run A directory naming must match fixture'
    Assert-Contract ([System.IO.Path]::GetFileName($runB) -eq [string]$fixture.runDirectoryScenarios[1].expectedDirectory) 'run B directory naming must match fixture'
    Assert-Contract ([System.IO.Path]::GetDirectoryName($runA).Equals((Get-LegadoHypiumEvidenceRoot -ScriptRoot $scriptRoot), [System.StringComparison]::OrdinalIgnoreCase)) 'run A must be a sibling of baseline'
    Assert-Contract ([System.IO.Path]::GetDirectoryName($runB).Equals((Get-LegadoHypiumEvidenceRoot -ScriptRoot $scriptRoot), [System.StringComparison]::OrdinalIgnoreCase)) 'run B must be a sibling of baseline'

    $baselineSourcePath = Join-Path $canonical 'source-fixture.json'
    $runSourcePath = Join-Path $runA 'source-fixture.json'
    [void][System.IO.Directory]::CreateDirectory($canonical)
    [void][System.IO.Directory]::CreateDirectory($runA)
    [System.IO.File]::WriteAllText($baselineSourcePath, 'baseline-evidence', [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($runSourcePath, 'run-evidence', [System.Text.UTF8Encoding]::new($false))
    Assert-Contract ([System.IO.File]::ReadAllText($baselineSourcePath, [System.Text.UTF8Encoding]::new($false, $true)) -eq 'baseline-evidence') 'run output must not overwrite baseline bytes'
    Assert-Contract ((ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $scriptRoot -Path $runSourcePath) -like 'full-source-v2-hypium-device-run-*/*') 'run source path must be relative to a run directory'
    $canonicalRejected = $false
    try { Assert-LegadoHypiumRunEvidenceDirectory -ScriptRoot $scriptRoot -EvidenceDirectory $canonical | Out-Null } catch { $canonicalRejected = $_.Exception.Message.Contains('BASELINE_EVIDENCE_WRITE_FORBIDDEN') }
    Assert-Contract $canonicalRejected 'canonical baseline must be rejected by the path guard'
    $canonicalDescendantRejected = $false
    try { Assert-LegadoHypiumRunEvidenceDirectory -ScriptRoot $scriptRoot -EvidenceDirectory (Join-Path $canonical 'nested-run') | Out-Null } catch { $canonicalDescendantRejected = $_.Exception.Message.Contains('BASELINE_EVIDENCE_WRITE_FORBIDDEN') }
    Assert-Contract $canonicalDescendantRejected 'canonical descendants must be rejected by the path guard'
    $activityEscapeRejected = $false
    try { Assert-LegadoHypiumRunActivityPath -EvidenceDirectory $runA -RunActivityPath $canonical | Out-Null } catch { $activityEscapeRejected = $_.Exception.Message.Contains('RUN_ACTIVITY_PATH_OUTSIDE_RUN_DIRECTORY') }
    Assert-Contract $activityEscapeRejected 'activity path outside the run directory must be rejected'
    $invalidTokenRejected = $false
    try { New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $scriptRoot -RunToken '../escape' | Out-Null } catch { $invalidTokenRejected = $_.Exception.Message.Contains('HYPIUM_EVIDENCE_RUN_TOKEN_INVALID') }
    Assert-Contract $invalidTokenRejected 'path traversal run token must be rejected'
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = 'hypium_evidence_run_isolation'
    assertions = $assertions
    baselineWritePolicy = [string]$fixture.baselineWritePolicy
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'hypium_evidence_run_isolation'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}
$resultDirectory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $resultDirectory)) { [void][System.IO.Directory]::CreateDirectory($resultDirectory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
