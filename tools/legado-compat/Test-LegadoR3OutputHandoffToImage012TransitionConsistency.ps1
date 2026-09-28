[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-output-handoff-005-to-image-012-pre-transition-20260808',
  [string]$OutputPath = '',
  [switch]$RequireRegistration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $runDirectory 'transition-consistency.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw '005 to 012 transition evidence must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [void][System.IO.Directory]::CreateDirectory($runDirectory)
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path) | ConvertFrom-Json } catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{
    id = $Id
    status = 'passed'
    detail = $Detail
    evidencePaths = @($Evidence)
  })
}

function Get-Sha256 {
  param([string]$Path)
  Assert-Gate (Test-Path -LiteralPath $Path -PathType Leaf) "missing file for hash: $Path"
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Test-ContainsPath {
  param([object]$Collection, [string]$Expected)
  foreach ($value in @($Collection)) {
    if ([string]$value -eq $Expected) { return $true }
  }
  return $false
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$sourceFix005Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-output-handoff-source-fix-20260808.json'
$audit005Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-output-handoff-current-head-hash-audit-20260808-r1\current-head-hash-audit.json'
$contract005Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-output-handoff-20260808-r4.json'
$sourceFix012Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-012-fallback-header-source-fix-20260808-r1.json'
$drift012Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-012-current-head-drift-audit-20260808\current-head-hash-audit.json'
$audit012Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-012-current-head-audit-20260808-r1\current-head-hash-audit.json'
$contract012Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-image-request-header-fallback-carrier-20260808-r1.json'
$carrierContract012Path = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-image-request-header-carrier-20260808-r3.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/transition-consistency.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $sourceFix005 = Read-StrictJson -Path $sourceFix005Path
  $audit005 = Read-StrictJson -Path $audit005Path
  $contract005 = Read-StrictJson -Path $contract005Path
  $sourceFix012 = Read-StrictJson -Path $sourceFix012Path
  $drift012 = Read-StrictJson -Path $drift012Path
  $audit012 = Read-StrictJson -Path $audit012Path
  $contract012 = Read-StrictJson -Path $contract012Path
  $carrierContract012 = Read-StrictJson -Path $carrierContract012Path
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ((Get-Sha256 -Path 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json') -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  Assert-Gate ((& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail '005 to 012 transition remains bound to the frozen source package and Legado checkout.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  $issue005 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-005'
  $issue012 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-012'
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006' -and [string]$governance.status -eq 'running') 'active governance task is not COMPAT-006/running.'
  if ($RequireRegistration) {
    Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-012') 'post-transition active issue is not ISSUE-COMPAT-012.'
  } else {
    Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-005') 'pre-transition active issue must remain ISSUE-COMPAT-005.'
  }
  Assert-Gate ($null -ne $issue005 -and [string]$issue005.status -eq 'verifying') '005 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $issue012 -and [string]$issue012.status -eq 'verifying') '012 must remain verifying for deferred R4.'
  foreach ($path in @(
      'tools/legado-compat/evidence/v2-image-012-current-head-drift-audit-20260808/current-head-hash-audit.json',
      'tools/legado-compat/evidence/contract-legado-image-request-header-fallback-carrier-pre-fix-20260808.json',
      'tools/legado-compat/evidence/v2-image-012-fallback-header-source-fix-20260808-r1.json',
      'tools/legado-compat/evidence/contract-legado-image-request-header-fallback-carrier-20260808-r1.json',
      'tools/legado-compat/evidence/v2-image-012-current-head-audit-20260808-r1/current-head-hash-audit.json')) {
    Assert-Gate (Test-ContainsPath -Collection $issue012.evidencePaths -Expected $path) ("012 evidence is not registered: {0}" -f $path)
  }
  Add-Check -Id 'machine_queue' -Detail 'Exactly one active source issue is selected; 005 and 012 remain static-only verifying.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$sourceFix005.status -eq 'source_fix_applied_pending_verification' -and [string]$audit005.status -in @('current_head_bound_static_closure','passed') -and [string]$contract005.status -eq 'passed' -and [int]$contract005.assertions -eq 43) '005 evidence is not static-only and complete.'
  Assert-Gate ([string]$sourceFix012.status -eq 'source_fix_applied_pending_verification' -and [string]$drift012.status -eq 'failed' -and [string]$audit012.status -eq 'passed' -and [int]$contract012.assertions -eq 33 -and [int]$carrierContract012.assertions -eq 30) '012 evidence chain is not the expected failed-before/fixed/current-head shape.'
  Assert-Gate (-not [bool](Get-PropertyValue -Object $sourceFix012 -Name 'semanticMatchAllowed' -Default $false) -and -not [bool](Get-PropertyValue -Object $audit012 -Name 'semanticMatchAllowed' -Default $false)) '012 evidence contains a semantic-match claim.'
  Assert-Gate (@($sourceFix012.runtimeActionsPerformed).Count -eq 0 -and @($audit012.runtimeActionsPerformed).Count -eq 0) 'transition evidence cannot contain runtime actions.'
  Add-Check -Id 'evidence_chain' -Detail '005 and 012 each retain failure, source-fix, static-contract and current-head evidence; all remain pending R4.' -Evidence @('tools/legado-compat/evidence/v2-image-012-current-head-drift-audit-20260808/current-head-hash-audit.json','tools/legado-compat/evidence/v2-image-012-fallback-header-source-fix-20260808-r1.json','tools/legado-compat/evidence/v2-image-012-current-head-audit-20260808-r1/current-head-hash-audit.json')

  $objectiveAuthority = $objective.authority
  $objectiveBody = $objective.objective
  if ($RequireRegistration) {
    Assert-Gate ([string]$objectiveAuthority.activeIssueId -eq 'ISSUE-COMPAT-012' -and [string]$objectiveBody.activeIssue -eq 'ISSUE-COMPAT-012') 'post-transition objective does not select 012.'
  } else {
    Assert-Gate ([string]$objectiveAuthority.activeIssueId -eq 'ISSUE-COMPAT-005' -and [string]$objectiveBody.activeIssue -eq 'ISSUE-COMPAT-005') 'pre-transition objective must remain on 005.'
  }
  $expectedAnchor = 'ISSUE-COMPAT-005'
  if ($RequireRegistration) { $expectedAnchor = 'ISSUE-COMPAT-012' }
  Assert-Gate ([string]$objectiveBody.queueSelectionGate.currentAnchor -eq $expectedAnchor) 'objective queue anchor does not match transition mode.'
  if ($RequireRegistration) {
    Assert-Gate (@($objectiveBody.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'post-transition next candidate must be rule composition 232.'
  } else {
    Assert-Gate (@($objectiveBody.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-012') 'pre-transition candidate must be 012.'
  }
  Add-Check -Id 'objective_queue' -Detail 'Objective active anchor and next candidate agree with the requested transition mode.' -Evidence @('tools/legado-compat/state/refactor-objective.json')

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('ISSUE-COMPAT-005') -and $objectiveDocument.Contains('ISSUE-COMPAT-012')) 'objective document does not retain the 005/012 boundary.'
  if ($RequireRegistration) {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-012`')) 'post-transition governance mirror does not select 012.'
  } else {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-005`')) 'pre-transition governance mirror does not select 005.'
  }
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument.Contains('v2-image-012-fallback-header-source-fix-20260808-r1.json') -and $diffDocument.Contains('v2-image-012-fallback-header-source-fix-20260808-r1.json')) 'generated documents do not retain 012 source-fix evidence.'
  if ($RequireRegistration) {
    Assert-Gate ($indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) 'post-transition evidence is not mirrored in generated documents.'
  }
  Add-Check -Id 'document_mirror' -Detail 'Objective, governance mirror, ledger, evidence index and diff summary retain one active issue and the 012 static evidence boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md','tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md','docs/analysis/Legado书源引擎兼容推进台账.md','docs/analysis/Legado书源引擎证据索引.md','docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_output_handoff_005_to_image_012_transition_consistency'
    status = 'passed'
    issueId = 'ISSUE-COMPAT-012'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-005'
      fromStatus = 'verifying'
      toIssue = 'ISSUE-COMPAT-012'
      toStatus = 'verifying'
      nextCandidate = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/state/refactor-objective.json','tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/evidence/v2-image-012-fallback-header-source-fix-20260808-r1.json','tools/legado-compat/evidence/v2-image-012-current-head-audit-20260808-r1/current-head-hash-audit.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_output_handoff_005_to_image_012_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_output_handoff_005_to_image_012_transition_consistency'
    status = 'failed'
    issueId = 'ISSUE-COMPAT-012'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_output_handoff_005_to_image_012_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
