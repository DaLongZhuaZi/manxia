[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'v2-output-handoff-current-head-hash-audit-20260808-r1',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'current-head-hash-audit.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Output handoff current-head evidence must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json) } catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RepositoryPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot ($RelativePath -replace '/', '\'))).Path
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-output-handoff-source-fix-20260808.json'
$staticContractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-output-handoff-20260808-r4.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-output-handoff.json'
$contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2OutputHandoffContract.ps1'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $staticContract = Read-StrictJson -Path $staticContractPath
  $fixture = Read-StrictJson -Path $fixturePath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  $legadoHead = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoHead -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail 'State, source package and Legado checkout remain bound to the frozen baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-005' -and [string]$sourceFix.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$sourceFix.semanticMatchAllowed) 'output handoff source-fix evidence is not static-only.'
  Assert-Gate ([string]$staticContract.status -eq 'passed' -and [string]$staticContract.contract -eq 'legado_v2_output_handoff' -and [int]$staticContract.assertions -eq 43) 'output handoff static contract is missing or incomplete.'
  Assert-Gate ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.legadoCommit -eq [string]$baseline.legadoCommit -and [string]$fixture.contract -eq 'legado_v2_output_handoff') 'output handoff fixture is not bound to the frozen baseline.'
  Add-Check -Id 'static_closure_binding' -Detail 'Output handoff failure fixture, source-fix evidence and 43-assertion static contract are present without a semantic-match claim.' -Evidence @('tools/legado-compat/evidence/contract-legado-output-handoff-pre-fix-20260808.json', 'tools/legado-compat/evidence/v2-output-handoff-source-fix-20260808.json', 'tools/legado-compat/evidence/contract-legado-output-handoff-20260808-r4.json')

  $hashes = New-Object 'System.Collections.Generic.List[object]'
  foreach ($property in $sourceFix.sourceHashes.PSObject.Properties) {
    $relativePath = [string]$property.Name
    $actualHash = Get-Sha256 -Path (Get-RepositoryPath -RelativePath $relativePath)
    Assert-Gate ($actualHash -eq ([string]$property.Value).ToUpperInvariant()) ("source hash drifted: {0}" -f $relativePath)
    [void]$hashes.Add([pscustomobject][ordered]@{ path = $relativePath; sha256 = $actualHash })
  }
  Assert-Gate ((Get-Sha256 -Path $fixturePath) -eq ([string]$sourceFix.fixtureSha256).ToUpperInvariant()) 'output handoff fixture hash drifted.'
  Assert-Gate ((Get-Sha256 -Path $contractPath) -eq ([string]$sourceFix.contractSha256).ToUpperInvariant()) 'output handoff contract hash drifted.'
  Add-Check -Id 'current_head_hashes' -Detail 'All typed handoff implementation paths, fixture and contract remain byte-bound to the source-fix evidence.' -Evidence @('tools/legado-compat/evidence/v2-output-handoff-source-fix-20260808.json')

  Assert-Gate (@($sourceFix.implementationPaths).Count -eq 8) 'output handoff implementation scope is incomplete.'
  Add-Check -Id 'implementation_scope' -Detail 'Models, orchestrator, manager, image bridge, text reader and audio consumers are included in the source closure scope.' -Evidence @($sourceFix.implementationPaths | ForEach-Object { [string]$_ })

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_output_handoff_current_head_hash_audit'
    issueId = 'ISSUE-COMPAT-005'
    status = 'current_head_bound_static_closure'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    implementationHashes = $hashes.ToArray()
    fixtureSha256 = Get-Sha256 -Path $fixturePath
    contractSha256 = Get-Sha256 -Path $contractPath
    staticContractAssertions = [int]$staticContract.assertions
    evidencePaths = @('tools/legado-compat/evidence/contract-legado-output-handoff-pre-fix-20260808.json', 'tools/legado-compat/evidence/v2-output-handoff-source-fix-20260808.json', 'tools/legado-compat/evidence/contract-legado-output-handoff-20260808-r4.json', 'tools/legado-compat/fixtures/legado-output-handoff.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_output_handoff_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_output_handoff_current_head_hash_audit'; issueId = 'ISSUE-COMPAT-005'; status = 'failed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_output_handoff_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred' }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
