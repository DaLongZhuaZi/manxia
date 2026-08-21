[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$previousIssue = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
$issueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$revision = '2026-08-09-actual-docs-source-refactor-continuation-capability-settlement-037'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$sourceFixPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-source-fix-20260809.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037.json'
$auditPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-current-head-audit-20260809.json'
$failurePath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037-pre-fix.json'
$fixturePath = 'tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json'
$queueAuditPath = 'tools/legado-compat/evidence/r3-source-queue-continuation-037/queue-audit.json'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([string]$RelativePath, [string]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "037 workflow capability transition blocked: $Message" }
}

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
$sourceFix = Read-StrictJson $sourceFixPath
$contract = Read-StrictJson $contractPath
$audit = Read-StrictJson $auditPath
$failure = Read-StrictJson $failurePath
$fixture = Read-StrictJson $fixturePath
$queueAudit = Read-StrictJson $queueAuditPath
$registrationAbsolutePath = Get-RepoPath $RegistrationEvidencePath

$alreadyRegistered = [string]$state.governance.activeIssueId -eq $issueId -and [string]$objective.authority.activeIssueId -eq $issueId -and (Test-Path -LiteralPath $registrationAbsolutePath -PathType Leaf)
if ($alreadyRegistered) {
  [pscustomobject][ordered]@{ status = 'already_registered'; idempotent = $true; previousIssueId = $previousIssue; issueId = $issueId; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_static_registration_recovery_only;R4_runtime_build_device_and_legado_diff_deferred' } | ConvertTo-Json -Depth 20
  return
}

Assert-Transition ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $previousIssue) '238 is not the sole active issue before transition.'
Assert-Transition ([string]$objective.authority.activeIssueId -eq $previousIssue -and [string]$objective.executionTarget.currentIssue -eq $previousIssue) 'objective is not at the 238 queue boundary.'
Assert-Transition ([string]$objective.continuationTarget.queueAudit.candidateIssueId -eq $issueId -and [string]$objective.continuationTarget.queueAudit.candidateGateStatus -eq 'pending_failure_contract') '037 candidate gate is not pending at the expected boundary.'
Assert-Transition ([string]$queueAudit.selectedCandidate.rootCauseId -eq $issueId -and [string]$queueAudit.candidateGateStatus -eq 'pending_failure_contract') '037 queue audit evidence does not select this root cause.'
Assert-Transition ([string]$sourceFix.status -eq 'source_closed_static_only' -and [string]$sourceFix.issueId -eq $issueId -and -not [bool]$sourceFix.semanticMatchAllowed -and @($sourceFix.runtimeActionsPerformed).Count -eq 0) 'source-fix evidence is not static-only.'
Assert-Transition ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 29 -and -not [bool]$contract.semanticMatchAllowed) 'static contract is invalid.'
Assert-Transition ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 27 -and -not [bool]$audit.semanticMatchAllowed) 'current-head audit is invalid.'
Assert-Transition ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed) 'failure witness is missing.'
Assert-Transition (@($fixture.cases).Count -eq 6) 'fixture case count drifted.'
$issues = @($state.governance.issues)
$previousRecord = $issues | Where-Object { [string]$_.id -eq $previousIssue } | Select-Object -First 1
$candidateRecord = $issues | Where-Object { [string]$_.id -eq $issueId } | Select-Object -First 1
Assert-Transition ($null -ne $previousRecord -and [string]$previousRecord.status -eq 'verifying') '238 must remain verifying.'
Assert-Transition ($null -ne $candidateRecord -and [string]$candidateRecord.status -eq 'planned') '037 candidate must be planned before activation.'

$gate = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_workflow_capability_dispatch_037_transition_consistency'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fromIssue = $previousIssue
  toIssue = $issueId
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  evidencePaths = @($queueAuditPath, $failurePath, $fixturePath, $contractPath, $auditPath, $sourceFixPath)
  transitionAssertions = 10
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_queue_transition_only;new_issue_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = '037 remains verifying until R4 fresh full_workflow/safe_read traces, same-input fixed-Legado differential, affected-source regression, build and device gates pass. Static source closure never becomes semantic_match.'
}
Write-AtomicJson $GateEvidencePath $gate

$candidateSummary = '037 源码闭合保持 verifying：safe_read Search/Explore 独立派发、Explore-only 完整读能力门控和按实际调度结算已完成；6 案例 fixture、29 项静态合同、27 项 current-head 审计、失败见证与 source-fix 哈希证据均绑定固定 458 条基线。R4 运行时、原版差分、构建和真机验证仍延期。'
Set-PropertyValue $candidateRecord 'status' 'verifying'
Set-PropertyValue $candidateRecord 'severity' 'P1'
Set-PropertyValue $candidateRecord 'summary' $candidateSummary
Set-PropertyValue $candidateRecord 'rootCauseId' $issueId
Set-PropertyValue $candidateRecord 'closeCondition' ([string]$gate.closeCondition)
Set-PropertyValue $candidateRecord 'evidencePaths' @($queueAuditPath, $failurePath, $fixturePath, $contractPath, $auditPath, $sourceFixPath)
Set-PropertyValue $candidateRecord 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $candidateRecord 'transitionEvidencePath' $GateEvidencePath
Set-PropertyValue $previousRecord 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
$state.governance.activeIssueId = $issueId
Set-PropertyValue $state 'revision' $revision

$objective.targetRevision = $revision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '037 源码静态闭合保持 verifying；下一步保留统一 R4 入口，等待用户开启运行时、原版差分、构建和真机验证。'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH is now the sole active source-closure issue after the passed 238-to-037 static transition gate. ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD and earlier issues remain verifying for deferred R4; static verification never becomes semantic_match.'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '当前唯一活动源码议题为 ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH；safe_read 的 Search/Explore 独立入口、Explore-only 完整读能力门控、缺失/依赖能力结构化结算和导航证据投影已完成静态闭合，R4 仍延期。'
$queueGate = $objective.objective.queueSelectionGate
Set-PropertyValue $queueGate 'status' 'issue_selected_r3_workflow_capability_dispatch_037'
Set-PropertyValue $queueGate 'currentAnchor' $issueId
Set-PropertyValue $queueGate 'selectedIssue' $issueId
Set-PropertyValue $queueGate 'candidateIssues' @()
Set-PropertyValue $queueGate 'evidencePath' $GateEvidencePath
Set-PropertyValue $queueGate 'candidateEvidencePath' $sourceFixPath
Set-PropertyValue $queueGate 'candidateCurrentHeadAuditEvidencePath' $auditPath
Set-PropertyValue $queueGate 'candidateAuditStatus' 'active_037_static_closed_r4_deferred'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.executionTarget 'statement' '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构。037 已通过 238→037 静态转移门禁，现为唯一活动源码议题；静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH 保持 verifying：Search/Explore 独立派发、Explore-only BookInfo/Toc/Content 完整能力门控、缺失/依赖结算和非 profile-wide 导航投影已通过静态证据；238 及旧议题仅等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '037 静态转移已完成；下一步只保留统一 R4 验证入口，不启动运行时、构建、安装或设备操作。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'status' 'candidate_activated_verifying'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'activated_verifying'
Set-PropertyValue $queueAudit 'candidateIssueId' $issueId
Set-PropertyValue $queueAudit 'candidateIssues' @()
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' $sourceFixPath
Set-PropertyValue $queueAudit 'transitionEvidencePath' $GateEvidencePath
Set-PropertyValue $queueAudit 'nextRequired' '保留 R4 统一验证入口；静态闭合不得升级为 passed 或 semantic_match。'
$plan = @($objective.continuationPlan)
$plan += @(
  [pscustomobject][ordered]@{ id = '037-CAP-01'; status = 'completed'; action = '固定 safe_read Search/Explore 独立派发与 Explore-only capability dependency 的 6 案例失败/修复 fixture。'; evidence = $fixturePath },
  [pscustomobject][ordered]@{ id = '037-CAP-02'; status = 'completed'; action = '完成 runner、Hypium navigation 和 settlement 的跨路径源码修复与 29 项合同、27 项 current-head 审计。'; evidence = $sourceFixPath },
  [pscustomobject][ordered]@{ id = '037-CAP-03'; status = 'deferred'; action = 'R4 fresh full_workflow/safe_read、Legado differential、构建、安装和真机验证由用户单独开启。' }
)
Set-PropertyValue $objective 'continuationPlan' $plan
Write-AtomicJson $objectiveRelative $objective

Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelative) -State $state -Depth 40

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'refactor objective attachment failed.' }

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_workflow_capability_dispatch_037_transition_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  previousIssueId = $previousIssue
  issueId = $issueId
  nextIssueId = ''
  gateEvidencePath = $GateEvidencePath
  sourceFixEvidencePath = $sourceFixPath
  failureWitnessPath = $failurePath
  currentHeadEvidencePath = $auditPath
  contractEvidencePath = $contractPath
  fixturePath = $fixturePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;037_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  idempotent = $true
}
Write-AtomicJson $RegistrationEvidencePath $registration

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$evidence = @($queueAuditPath, $failurePath, $fixturePath, $contractPath, $auditPath, $sourceFixPath, $GateEvidencePath, $RegistrationEvidencePath)
& $updateScript -StatePath (Get-RepoPath $stateRelative) -IssueId $issueId -IssueStatus verifying -TaskId 'COMPAT-006' -Summary $candidateSummary -EvidencePath ($evidence -join ',') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'governance state refresh failed.' }

$objectiveDocumentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText $objectiveDocumentRelative
$startMarker = '## R3-SOURCE-QUEUE-CONTINUATION-037 队列审计'
$endMarker = '## 单议题执行规则'
$section = @"
$startMarker

037 源码队列转移已完成：当前唯一活动源码锚点为 ``$issueId``，状态为 ``verifying``；``$previousIssue`` 保持 ``verifying`` 等待 R4，不重新打开或并行打补丁。037 合并并修复了 safe_read 的 Search/Explore 独立派发、Explore-only 完整读能力门控、缺失/依赖能力结构化结算和导航层非 profile-wide 证据投影。

固定包静态统计为 Search URL 447 条、Explore URL 362 条、双入口 351 条、Explore-only 11 条；6 案例 fixture、29 项静态合同、27 项 current-head 审计及 source-fix 哈希证据全部绑定固定 458 条基线。静态证据只证明源码闭合，不产生运行时兼容结论。

证据：``$GateEvidencePath``、``$RegistrationEvidencePath``、``$sourceFixPath``。R4 的 fresh ``full_workflow``/``safe_read``、真实端点、Legado 差分、构建、安装、设备和 458 条批次继续延期。

"@
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if (-not [regex]::IsMatch($objectiveDocument, $pattern)) { throw 'objective document queue section marker missing.' }
$objectiveDocument = [regex]::Replace($objectiveDocument, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $section })
Write-AtomicText $objectiveDocumentRelative $objectiveDocument

[pscustomobject][ordered]@{ status = 'registered'; previousIssueId = $previousIssue; issueId = $issueId; gateEvidencePath = $GateEvidencePath; registrationEvidencePath = $RegistrationEvidencePath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_static_transition_only;R4_deferred' } | ConvertTo-Json -Depth 20
