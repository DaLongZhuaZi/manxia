[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ColdStartResultPath = 'tmp/hypium-driver-r4-cold-start-20260809-unlocked/result.json',
  [string]$ManagementResultPath = 'tmp/book-source-management-r4-20260809-unlocked/result.json',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r4-build-device-20260809-r3/issue-241-device-verification.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-241-ARKTS-INLINE-OBJECT-TYPES'
$taskId = 'COMPAT-241'
$nextIssueId = 'ISSUE-COMPAT-009'
$nextTaskId = 'COMPAT-009'
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$stateRelativePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelativePath = 'tools/legado-compat/state/refactor-objective.json'
$candidateGateEvidencePath = 'tools/legado-compat/evidence/r4-build-device-20260809-r3/current-static-candidate-preflight.json'
$modulePath = Join-Path $RepositoryRoot 'tools\legado-compat\LegadoFullSourceState.psm1'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "ISSUE241_DEVICE_VERIFY_BLOCKED: missing JSON evidence: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  return ($utf8.GetString($bytes) | ConvertFrom-Json)
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $property.Value = $Value
  }
}

function Add-UniqueEvidence([object]$Issue, [string[]]$Paths) {
  $existing = New-Object 'System.Collections.Generic.List[string]'
  $property = $Issue.PSObject.Properties['evidencePaths']
  if ($null -ne $property -and $null -ne $property.Value) {
    foreach ($value in @($property.Value)) {
      $normalized = ([string]$value).Replace('/', '\')
      if ($normalized.Length -gt 0 -and -not $existing.Contains($normalized)) {
        [void]$existing.Add($normalized)
      }
    }
  }
  foreach ($value in $Paths) {
    $normalized = ([string]$value).Replace('/', '\')
    if ($normalized.Length -gt 0 -and -not $existing.Contains($normalized)) {
      [void]$existing.Add($normalized)
    }
  }
  Set-PropertyValue $Issue 'evidencePaths' @($existing.ToArray())
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) {
      [System.IO.File]::Delete($temporary)
    }
  }
}

function Require-PassedDriverResult([object]$Result, [string]$Label) {
  if ([string]$Result.status -ne 'passed') {
    throw "ISSUE241_DEVICE_VERIFY_BLOCKED: $Label status is not passed."
  }
  if (-not [bool]$Result.driver_closed) {
    throw "ISSUE241_DEVICE_VERIFY_BLOCKED: $Label did not close its driver."
  }
}

$state = Read-StrictJson $stateRelativePath
$objective = Read-StrictJson $objectiveRelativePath
$cold = Read-StrictJson $ColdStartResultPath
$management = Read-StrictJson $ManagementResultPath
$candidateGate = Read-StrictJson $candidateGateEvidencePath
$now = [DateTimeOffset]::UtcNow.ToString('o')

if ([int]$state.baseline.sourceCount -ne $sourceCount -or
    [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: frozen baseline drifted.'
}
Require-PassedDriverResult -Result $cold -Label 'cold-start smoke'
Require-PassedDriverResult -Result $management -Label 'book-source management probe'
if ([string]$cold.package -ne 'com.dlzz.manxia' -or [string]$management.package -ne 'com.dlzz.manxia') {
  throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: evidence package does not match Manxia.'
}
if ([string]$cold.device_sn -ne [string]$management.device_sn) {
  throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: evidence came from different devices.'
}
if ([string]$management.total_count_text -ne [string]$sourceCount -or
    [string]$management.verified_count_text -ne "0/$sourceCount" -or
    [string]$management.policy_summary_text -notmatch '0/458') {
  throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: management aggregate does not match frozen 458/0 baseline.'
}
if ([string]$candidateGate.status -ne 'passed' -or
    [string]$candidateGate.candidateGateStatus -ne 'no_candidate_satisfies_evidence_gate' -or
    [int]$candidateGate.candidateCount -ne 0) {
  throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: candidate gate evidence is not the expected no-candidate result.'
}

$buildEvidence = 'tools/legado-compat/evidence/r4-build-device-20260809-r2/issue-241-build-post-fix.json'
$hapPath = 'entry/build/default/outputs/default/entry-default-signed.hap'
if (-not (Test-Path -LiteralPath (Get-RepositoryPath $buildEvidence) -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Get-RepositoryPath $hapPath) -PathType Leaf)) {
  throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: build post-fix evidence or signed HAP is missing.'
}

$managementSha256 = (Get-FileHash -LiteralPath (Get-RepositoryPath $ManagementResultPath) -Algorithm SHA256).Hash.ToUpperInvariant()
$evidence = [ordered]@{
  schemaVersion = 2
  kind = 'legado_issue_241_arkts_inline_object_types_device_verification'
  status = 'passed'
  issueId = $issueId
  taskId = $taskId
  generatedAt = $now
  baseline = [ordered]@{
    sourceCount = $sourceCount
    sourcePackageSha256 = $sourceHash
    legadoCommit = $legadoCommit
  }
  device = [ordered]@{
    deviceSn = [string]$cold.device_sn
    package = [string]$cold.package
    ability = [string]$cold.ability
  }
  checks = [ordered]@{
    signedBuild = [ordered]@{ status = 'passed'; evidencePath = $buildEvidence; hapPath = $hapPath }
    coldStart = [ordered]@{ status = 'passed'; resultPath = $ColdStartResultPath; bundle = [string]$cold.window.bundle_name; driverClosed = [bool]$cold.driver_closed }
    bookSourceManagement = [ordered]@{ status = 'passed'; resultPath = $ManagementResultPath; total = [string]$management.total_count_text; completeVerification = [string]$management.verified_count_text; policy = [string]$management.policy_summary_text; evidenceSha256 = $managementSha256 }
  }
  semanticMatchAllowed = $false
  statement = '241 的 ArkTS 命名结果合同、JDK21 debug 构建、signed HAP 安装、真机冷启动和书源管理页可达性已完成；管理页仍明确显示 V2 完整验证 0/458，因此本证据不改变任何书源的语义资格。'
  nextAction = '回到 ISSUE-COMPAT-009 的源码治理与迁移证据队列；保持 R4 全量 Harness、Legado 差分和 458 条语义验收未完成。'
}

$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $issue) { throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: issue missing from machine state.' }
Set-PropertyValue $issue 'status' 'passed'
Set-PropertyValue $issue 'summary' 'ArkTS 命名结果合同、JDK21 debug 构建、signed HAP 安装、真机冷启动和书源管理页均已通过；管理页明确为 V2 完整验证 0/458，241 设备门禁关闭但不产生书源语义通过。'
Set-PropertyValue $issue 'lastUpdatedAt' $now
Add-UniqueEvidence -Issue $issue -Paths @($EvidencePath, $ColdStartResultPath, $ManagementResultPath, $buildEvidence, $hapPath)

$task = @($state.governance.tasks | Where-Object { [string]$_.id -eq $taskId }) | Select-Object -First 1
if ($null -ne $task) {
  Set-PropertyValue $task 'status' 'passed'
  Set-PropertyValue $task 'lastUpdatedAt' $now
}
$nextIssue = @($state.governance.issues | Where-Object { [string]$_.id -eq $nextIssueId }) | Select-Object -First 1
if ($null -ne $nextIssue) {
  Add-UniqueEvidence -Issue $nextIssue -Paths @($candidateGateEvidencePath)
  Set-PropertyValue $nextIssue 'lastUpdatedAt' $now
}
Set-PropertyValue $state.governance 'activeIssueId' $nextIssueId
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $nextIssueId
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state.governance 'lastDeviceGateIssueId' $issueId
Set-PropertyValue $state.governance 'lastDeviceGateEvidencePath' $EvidencePath

$device = $state.devicePersistedQualification
Set-PropertyValue $device 'observationStatus' 'observed_incomplete'
Set-PropertyValue $device 'observationKind' 'management_summary_aggregate'
Set-PropertyValue $device 'totalSourceCount' $sourceCount
Set-PropertyValue $device 'verificationRows' 0
Set-PropertyValue $device 'completeVerificationCount' 0
Set-PropertyValue $device 'verificationDenominator' $sourceCount
Set-PropertyValue $device 'executionPolicy' 'v2_full_cutover'
Set-PropertyValue $device 'sourceIdentityCoverage' 'aggregate_only'
Set-PropertyValue $device 'evidencePath' $ManagementResultPath
Set-PropertyValue $device 'evidenceSha256' $managementSha256
Set-PropertyValue $device 'observedAtUtc' $now
Set-PropertyValue $state 'updatedAt' $now

$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $objective 'targetRevision' '2026-08-09-r4-device-241-verified-return-issue009'
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'nextAction' '继续 ISSUE-COMPAT-009 的数据库迁移真机证据与源码治理；不得把冷启动或管理页聚合结果扩展为 458 条语义兼容通过。'
Set-PropertyValue $objective.authority 'activeIssueId' $nextIssueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json 已完成 241 的设备门禁；ISSUE-COMPAT-009 恢复为唯一活动源码议题并保持 verifying，011 作为下一静态候选，历史闭合仅等待 R4。'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R4-ISSUE-009-DATABASE-MIGRATION-EVIDENCE'
Set-PropertyValue $objective.objective 'activeIssue' $nextIssueId
Set-PropertyValue $objective.objective.queueSelectionGate 'currentAnchor' $nextIssueId
Set-PropertyValue $objective.objective.queueSelectionGate 'selectedIssue' $nextIssueId
Set-PropertyValue $objective.objective.queueSelectionGate 'status' 'issue_selected_r4_device_241_passed_return_009'
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $objective.objective.queueSelectionGate 'selectionRule' 'The queue is selected only from full-source-validation-state.json. ISSUE-COMPAT-009 is the sole active source-closure anchor after the 241 device gate; the current candidate preflight found no eligible next issue. No runtime result, old executor fallback or issue status name may select a second root cause before a new five-item evidence gate passes.'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-009 状态为 verifying：静态迁移修复已登记，需保留 R4 迁移异常证据后再决定下一源码候选。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '补齐 ISSUE-COMPAT-009 的迁移日志/失败传播证据；证据不足时保持 verifying。'
Set-PropertyValue $queueAudit 'status' 'r4_device_241_passed_source_queue_resumed'
Set-PropertyValue $queueAudit 'currentAnchor' $nextIssueId
Set-PropertyValue $queueAudit 'selectedIssue' $nextIssueId
Set-PropertyValue $queueAudit 'candidateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $queueAudit 'candidateIssueId' ''
Set-PropertyValue $queueAudit 'candidateIssues' @()
Set-PropertyValue $queueAudit 'auditEvidencePath' $candidateGateEvidencePath
Set-PropertyValue $queueAudit 'nextRequired' '保持 ISSUE-COMPAT-009 verifying；补齐下一个根因的五项证据后才允许原子选择，不启动 R4 全量验证。'
Set-PropertyValue $queueAudit 'candidateTargetEvidencePath' 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/target.json'
Set-PropertyValue $queueAudit 'candidateFailureWitnessPath' 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json'
Set-PropertyValue $queueAudit 'candidateCurrentHeadAuditEvidencePath' 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-post-fix-20260809.json'
Set-PropertyValue $queueAudit 'candidateSourceFixEvidencePath' 'tools/legado-compat/evidence/v2-issue-011-url-attribute-source-fix-20260809.json'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'no_candidate_satisfies_evidence_gate'
if ($null -ne $objective.continuationTarget.preparedCandidate) {
  Set-PropertyValue $objective.continuationTarget.preparedCandidate 'status' 'historical_candidate_not_eligible'
  Set-PropertyValue $objective.continuationTarget.preparedCandidate 'candidateGateStatus' 'no_candidate_satisfies_evidence_gate'
  Set-PropertyValue $objective.continuationTarget.preparedCandidate 'candidateIssueId' 'ISSUE-COMPAT-011'
  Set-PropertyValue $objective.continuationTarget.preparedCandidate 'evidencePath' $candidateGateEvidencePath
}
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateGateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateIssues' @()
Set-PropertyValue $objective.objective.queueSelectionGate 'currentAnchor' $nextIssueId
Set-PropertyValue $objective.objective.queueSelectionGate 'selectedIssue' $nextIssueId
Set-PropertyValue $objective.objective.queueSelectionGate 'evidencePath' $candidateGateEvidencePath
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateTargetEvidencePath' ''
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateFailureWitnessPath' ''
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateCurrentHeadAuditEvidencePath' ''
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateSourceFixEvidencePath' ''
Set-PropertyValue $objective 'lastDeviceVerificationEvidencePath' $EvidencePath
Set-PropertyValue $objective 'lastDeviceVerificationAt' $now

Import-Module -Name $modulePath -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path (Get-RepositoryPath $stateRelativePath) -State $state -Depth 80
Write-AtomicJson -RelativePath $EvidencePath -Value $evidence
Write-AtomicJson -RelativePath $objectiveRelativePath -Value $objective

$refreshScript = Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ISSUE241_DEVICE_VERIFY_BLOCKED: document refresh failed.' }

$evidence | ConvertTo-Json -Depth 20
