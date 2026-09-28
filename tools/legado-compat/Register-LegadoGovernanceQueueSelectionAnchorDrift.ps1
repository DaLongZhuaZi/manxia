[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-AUTO-048-GOVERNANCE-QUEUE-SELECTION-ANCHOR-DRIFT'
$taskId = 'COMPAT-006'
$failureRelative = 'tools/legado-compat/evidence/contract-legado-governance-queue-selection-anchor-drift-pre-fix-20260809.json'
$contractRelative = 'tools/legado-compat/evidence/contract-legado-governance-queue-selection-anchor-20260809.json'
$sourceFixRelative = 'tools/legado-compat/evidence/v2-governance-queue-selection-anchor-source-fix-20260809.json'
$registrationRelative = 'tools/legado-compat/evidence/r3-governance-queue-selection-anchor-registration-20260809/registration.json'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-governance-queue-selection-anchor-drift.json'
$contractScriptRelative = 'tools/legado-compat/Test-LegadoGovernanceQueueSelectionAnchorContract.ps1'

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}
function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
}
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}
function Invoke-Script([string]$RelativePath, [string[]]$Arguments) {
  & pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepoPath $RelativePath) @Arguments | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Script failed: $RelativePath" }
}

$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) { throw 'Machine baseline drifted.' }
if ([int]$objective.baseline.sourceCount -ne $sourceCount -or [string]$objective.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$objective.baseline.legadoCommit -ne $legadoCommit) { throw 'Objective baseline drifted.' }
$activeIssueId = [string]$state.governance.activeIssueId
if ($activeIssueId -ne 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION') { throw 'The 242 source issue must remain the active queue anchor.' }

# Preserve the stale projection before replacing it so historical evidence is
# still inspectable without allowing it to participate in current selection.
$selectionGate = $objective.objective.queueSelectionGate
$queueAudit = $objective.continuationTarget.queueAudit
if ($null -eq $objective.PSObject.Properties['historicalQueueSelectionProjection']) {
  $historicalProjection = [ordered]@{
    capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
    source = 'pre-fix objective queue projection'
    queueSelectionGate = [ordered]@{
      status = [string]$selectionGate.status
      currentAnchor = [string]$selectionGate.currentAnchor
      selectedIssue = [string]$selectionGate.selectedIssue
      evidencePath = [string]$selectionGate.evidencePath
      candidateEvidencePath = [string]$selectionGate.candidateEvidencePath
      candidateCurrentHeadAuditEvidencePath = [string]$selectionGate.candidateCurrentHeadAuditEvidencePath
      selectionRule = [string]$selectionGate.selectionRule
    }
    queueAudit = [ordered]@{
      currentAnchor = [string]$queueAudit.currentAnchor
      selectedIssue = [string]$queueAudit.selectedIssue
      candidateIssueId = [string]$queueAudit.candidateIssueId
      candidateTargetEvidencePath = [string]$queueAudit.candidateTargetEvidencePath
      candidateFailureWitnessPath = [string]$queueAudit.candidateFailureWitnessPath
      candidateCurrentHeadAuditEvidencePath = [string]$queueAudit.candidateCurrentHeadAuditEvidencePath
      candidateSourceFixEvidencePath = [string]$queueAudit.candidateSourceFixEvidencePath
    }
  }
  Set-PropertyValue $objective 'historicalQueueSelectionProjection' $historicalProjection
}

$latestGateRelative = 'tools/legado-compat/evidence/r3-source-queue-preflight-20260809-r4/current-static-candidate-preflight.json'
$selectionGate.status = 'source_fix_static_closed_wait_r4'
$selectionGate.currentAnchor = $activeIssueId
$selectionGate.selectedIssue = $activeIssueId
$selectionGate.candidateIssues = @()
$selectionGate.evidencePath = $latestGateRelative
$selectionGate.previousEvidencePath = $latestGateRelative
$selectionGate.candidateEvidencePath = ''
$selectionGate.candidateCurrentHeadAuditEvidencePath = ''
$selectionGate.candidateAuditStatus = 'active_242_source_fix_static_closed_wait_r4'
$selectionGate.selectionRule = 'The queue is selected only from full-source-validation-state.json. ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION is the sole active source-closure anchor while its static trace-fix waits for R4; no runtime result, old executor fallback or historical issue status may select a second root cause.'
$selectionGate.candidateStatus = 'source_fix_static_closed'
$selectionGate.candidateGateStatus = 'source_fix_static_closed_wait_r4'

$queueAudit.currentAnchor = $activeIssueId
$queueAudit.selectedIssue = $activeIssueId
$queueAudit.candidateIssueId = $activeIssueId
$queueAudit.candidateIssues = @()
$queueAudit.candidateTargetEvidencePath = ''
$queueAudit.candidateFailureWitnessPath = ''
$queueAudit.candidateCurrentHeadAuditEvidencePath = ''
$queueAudit.candidateSourceFixEvidencePath = 'tools/legado-compat/evidence/v2-trace-mutation-bridge-preservation-source-fix-20260809.json'
$queueAudit.candidateStatus = 'source_fix_static_closed'
$queueAudit.candidateGateStatus = 'source_fix_static_closed_wait_r4'
$queueAudit.auditEvidencePath = $latestGateRelative
$queueAudit.postFixContractEvidencePath = 'tools/legado-compat/evidence/contract-legado-trace-mutation-bridge-preservation-20260809.json'

$now = [DateTimeOffset]::UtcNow.ToString('o')
$objective.lastReviewedAt = $now
$objective.nextAction = '242 的共享 Trace replacement helper 已完成静态修复；保持 verifying，继续只读审计队列和证据投影，R4 运行时、构建、安装、设备和 Legado 差分延期。'
$objective.continuationTarget.activeBoundary = 'ISSUE-COMPAT-242 保持 verifying：共享 replaceTrace helper 统一复制 bridgeTraces；R4 deferred。'
$objective.continuationTarget.nextTransition = '继续只读核对下一个五项证据候选；不得在 R4 前宣称语义通过。'
Write-AtomicJson $objectiveRelative $objective

# Record the repaired projection contract after the objective update.
Invoke-Script $contractScriptRelative @('-RepositoryRoot', $RepositoryRoot, '-OutputPath', $contractRelative)
$contract = Read-StrictJson $contractRelative
$runtimePath = Get-RepoPath 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_selection_anchor_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failureRelative
  contractEvidencePath = $contractRelative
  changedFiles = @('tools/legado-compat/state/refactor-objective.json', $contractScriptRelative, $fixtureRelative)
  activeIssueIdAfterFix = $activeIssueId
  primaryCause = 'The objective projection was updated by historical registration scripts without atomically rebasing both queue-selection views to the machine active issue.'
  preservedHistoryField = 'historicalQueueSelectionProjection'
  sourceSha256 = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToUpperInvariant()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_document_contract_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'Contract, failure witness, source-fix evidence, machine state and all derived documents stay aligned; this governance fix does not establish book-source semantic compatibility.'
}
Write-AtomicJson $sourceFixRelative $sourceFix

Invoke-Script 'tools/legado-compat/Update-LegadoGovernanceState.ps1' @(
  '-StatePath', (Get-RepoPath $stateRelative),
  '-IssueId', $issueId,
  '-IssueStatus', 'passed',
  '-TaskId', $taskId,
  '-TaskStatus', 'running',
  '-Severity', 'P1',
  '-Summary', 'refactor-objective.json 曾将 queueSelectionGate 和 queueAudit 的当前锚点残留为 ISSUE-COMPAT-009；已保留历史投影并原子改为机器事实活动议题 242。',
  '-CloseCondition', '静态合同、失败见证、source-fix 证据、机器事实和全部派生文档保持一致；不得据此宣称书源语义兼容。',
  '-EvidencePath', "$failureRelative,$contractRelative,$sourceFixRelative,$fixtureRelative,$contractScriptRelative",
  '-CreateIfMissing'
)

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
Set-PropertyValue $objective 'governanceSync' ([ordered]@{
  activeIssueId = [string]$state.governance.activeIssueId
  queueSelectionCurrentAnchor = [string]$objective.objective.queueSelectionGate.currentAnchor
  queueAuditCurrentAnchor = [string]$objective.continuationTarget.queueAudit.currentAnchor
  evidencePath = $contractRelative
  updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
})
Write-AtomicJson $objectiveRelative $objective
Invoke-Script 'tools/legado-compat/Set-LegadoRefactorObjective.ps1' @(
  '-StatePath', (Get-RepoPath $stateRelative),
  '-ObjectivePath', (Get-RepoPath $objectiveRelative),
  '-ActiveIssueId', $activeIssueId
)
Invoke-Script 'tools/legado-compat/Invoke-LegadoCompatibility.ps1' @('-RefreshDocumentsOnly')

$registration = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_selection_anchor_registration'
  status = 'registered_passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = $issueId
  taskId = $taskId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failureRelative
  contractEvidencePath = $contractRelative
  sourceFixEvidencePath = $sourceFixRelative
  activeIssueId = $activeIssueId
  historicalProjectionField = 'historicalQueueSelectionProjection'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $registrationRelative $registration
$registration | ConvertTo-Json -Depth 30
