[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/target.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-pre-fix-20260809.json',
  [string]$TransitionEvidencePath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$sourceCount = 458
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$previousIssueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$issueId = 'ISSUE-COMPAT-011'
$revision = '2026-08-09-actual-docs-source-refactor-url-attribute-011-source-fix'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$objectiveDocRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON evidence: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return $utf8Strict.GetString($bytes) | ConvertFrom-Json }
  catch { throw "Invalid JSON evidence: $RelativePath; $($_.Exception.Message)" }
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Write-AtomicText([string]$RelativePath, [string]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Activation([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE011_ACTIVATION_BLOCKED:$Message" }
}

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
$target = Read-StrictJson $TargetEvidencePath
$failure = Read-StrictJson $FailureWitnessPath
$audit = Read-StrictJson $CurrentHeadAuditPath

$existingCandidate = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ([string]$state.governance.activeIssueId -eq $issueId -and $null -ne $existingCandidate -and [string]$existingCandidate.status -eq 'in_progress' -and (Test-Path -LiteralPath (Get-RepoPath $RegistrationEvidencePath) -PathType Leaf)) {
  $queueAudit = $objective.continuationTarget.queueAudit
  Set-PropertyValue $queueAudit 'status' 'candidate_activated_in_progress'
  Set-PropertyValue $queueAudit 'candidateIssueId' $issueId
  Set-PropertyValue $queueAudit 'candidateIssues' @()
  Set-PropertyValue $queueAudit 'candidateGateStatus' 'activated_in_progress'
  Set-PropertyValue $queueAudit 'auditEvidencePath' $TargetEvidencePath
  Set-PropertyValue $queueAudit 'failureWitnessPath' $FailureWitnessPath
  Set-PropertyValue $queueAudit 'currentHeadEvidencePath' $CurrentHeadAuditPath
  Set-PropertyValue $queueAudit 'transitionEvidencePath' $TransitionEvidencePath
  Set-PropertyValue $queueAudit 'sourceFixEvidencePath' ''
  Set-PropertyValue $queueAudit 'postRegistrationEvidencePath' ''
  Set-PropertyValue $queueAudit 'priorActiveIssueId' $previousIssueId
  Set-PropertyValue $queueAudit 'priorTransitionEvidencePath' ''
  Set-PropertyValue $queueAudit 'postFixContractEvidencePath' ''
  Set-PropertyValue $objective 'targetRevision' $revision
  Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_011_URL_ATTRIBUTE_SOURCE_FIX'
  Write-AtomicJson -RelativePath $objectiveRelative -Value $objective
  Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
  Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelative) -State $state -Depth 80
  $setObjectiveScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
  & pwsh -NoLogo -NoProfile -NonInteractive -File $setObjectiveScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $issueId | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Refactor objective attachment failed during idempotent repair.' }
  $refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
  & pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Derived governance document refresh failed during idempotent repair.' }
  $objectiveDocPath = Get-RepoPath $objectiveDocRelative
  $objectiveDoc = [System.IO.File]::ReadAllText($objectiveDocPath, $utf8Strict)
  $objectiveDoc = $objectiveDoc.Replace([string][char]0x0b, 'v')
  $objectiveDoc = $objectiveDoc.Replace('verifyingerifying', 'verifying')
  $objectiveDoc = $objectiveDoc.Replace('vverifying', 'verifying')
  $objectiveDoc = $objectiveDoc.Replace(([string][char]0x09) + 'ools/legado-compat/state', 'tools/legado-compat/state')
  Write-AtomicText -RelativePath $objectiveDocRelative -Value $objectiveDoc
  [pscustomobject][ordered]@{
    status = 'already_registered'
    activeIssueId = $issueId
    previousIssueId = $previousIssueId
    transitionEvidencePath = $TransitionEvidencePath
    registrationEvidencePath = $RegistrationEvidencePath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    idempotent = $true
  } | ConvertTo-Json -Depth 20
  return
}

Assert-Activation ([int]$state.baseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Activation ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Activation ([string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Activation ([int]$objective.baseline.sourceCount -eq $sourceCount) 'objective source count drifted'
Assert-Activation ([string]$objective.baseline.sourcePackageSha256 -eq $sourceHash) 'objective source hash drifted'
Assert-Activation ([string]$objective.baseline.legadoCommit -eq $legadoCommit) 'objective Legado commit drifted'
Assert-Activation ([string]$state.governance.activeTaskId -eq 'COMPAT-006') 'COMPAT-006 is not active'
Assert-Activation ([string]$state.governance.activeIssueId -eq $previousIssueId) 'S2T is not the sole active issue before activation'
Assert-Activation ([string]$objective.authority.activeIssueId -eq $previousIssueId) 'objective is not at the S2T boundary'

$candidate = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
$previous = @($state.governance.issues | Where-Object { [string]$_.id -eq $previousIssueId }) | Select-Object -First 1
Assert-Activation ($null -ne $candidate -and [string]$candidate.status -eq 'planned') '011 must be planned before activation'
Assert-Activation ($null -ne $previous -and [string]$previous.status -eq 'verifying') 'S2T must remain verifying'
Assert-Activation ([string]$target.status -eq 'candidate_gate_ready') '011 target is not candidate_gate_ready'
Assert-Activation ([string]$target.candidateGateStatus -eq 'candidate_gate_ready_selection_required') '011 candidate gate is incomplete'
Assert-Activation ([string]$target.activeIssueId -eq $previousIssueId) '011 target active issue drifted'
Assert-Activation ([bool]$target.preparedCandidate.activationAllowed) '011 activation is not allowed by target evidence'
Assert-Activation ([string]$failure.status -eq 'failed_static_only') '011 failure witness must remain failed_static_only'
Assert-Activation (-not [bool]$failure.semanticMatchAllowed) '011 failure witness cannot enable semantic match'
Assert-Activation ([string]$audit.status -eq 'failed_static_only') '011 consumer audit must remain failed_static_only before source fix'
Assert-Activation ([string]$audit.inventoryStatus -eq 'complete_static_inventory') '011 consumer audit inventory is incomplete'
Assert-Activation ([int]$audit.unresolvedGapCount -gt 0) '011 consumer audit has no retained pre-fix gap'
Assert-Activation (@($audit.consumerMatrix).Count -ge 9) '011 consumer matrix is incomplete'
Assert-Activation (@($audit.runtimeActionsPerformed).Count -eq 0) 'activation cannot follow runtime actions'

$evidencePaths = @($TargetEvidencePath, $FailureWitnessPath, $CurrentHeadAuditPath, $TransitionEvidencePath, $RegistrationEvidencePath)
$closeCondition = 'Unify value-level deduplication at the shared V2 selector-list projection boundary across all listed consumers, prove the pre-fix failure is removed without changing URL resolution boundaries, then generate post-fix/current-head static evidence; R4 runtime, build, device and Legado differential remain deferred.'
$summary = '011 已通过五项静态证据门禁并原子激活为唯一源码修复议题：固定 Legado URL 属性边界、313 条书源/1262 个规则节点、重复值 failed_static_only 见证及 9 个 current-head 消费者均已绑定。当前只修复共享属性列表投影去重根因，R4 deferred。'

$transition = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_source_fix_transition'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  fromIssue = $previousIssueId
  toIssue = $issueId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  evidencePaths = @($TargetEvidencePath, $FailureWitnessPath, $CurrentHeadAuditPath)
  transitionAssertions = @(
    'fixed baseline is unchanged',
    'S2T remains verifying before activation',
    '011 target gate is candidate_gate_ready',
    'failure witness remains failed_static_only',
    'current-head audit enumerates all 9 consumers and retains 7 gaps',
    'no runtime actions were performed',
    'semanticMatchAllowed remains false'
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_issue_activation_only;011_in_progress;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = $closeCondition
}
Write-AtomicJson -RelativePath $TransitionEvidencePath -Value $transition

Set-PropertyValue $candidate 'status' 'in_progress'
Set-PropertyValue $candidate 'severity' 'P0'
Set-PropertyValue $candidate 'rootCauseId' $issueId
Set-PropertyValue $candidate 'classification' 'selector_extraction_vs_url_resolution_boundary'
Set-PropertyValue $candidate 'summary' $summary
Set-PropertyValue $candidate 'closeCondition' $closeCondition
Set-PropertyValue $candidate 'evidencePaths' $evidencePaths
Set-PropertyValue $candidate 'transitionEvidencePath' $TransitionEvidencePath
Set-PropertyValue $candidate 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $previous 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
$state.governance.activeIssueId = $issueId
$state.revision = $revision

Set-PropertyValue $objective 'targetRevision' $revision
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_011_URL_ATTRIBUTE_SOURCE_FIX'
Set-PropertyValue $objective 'nextAction' '执行 011-URL-05：保持重复属性值失败合同，跨所有已登记消费者建立共享值级去重边界并生成静态 source-fix/post-fix/current-head 证据。'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-011 is now the sole active source-closure issue after a passed static five-item gate. S2T and earlier closures remain verifying for deferred R4.'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-011-URL-ATTRIBUTE'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '当前唯一活动源码议题为 ISSUE-COMPAT-011；根因为 Legado 属性列表值级去重缺失，必须跨 Analyzer、Rule IR/Matcher、标准/Native/Rhino JSVM、ArkWeb runtime 和工作流消费者统一修复。不得用 URL 解析回退、旧执行器或空结果掩盖差异。'
$queueGate = $objective.objective.queueSelectionGate
Set-PropertyValue $queueGate 'status' 'issue_selected_r3_issue_011_url_attribute'
Set-PropertyValue $queueGate 'currentAnchor' $issueId
Set-PropertyValue $queueGate 'selectedIssue' $issueId
Set-PropertyValue $queueGate 'candidateIssues' @()
Set-PropertyValue $queueGate 'evidencePath' $TransitionEvidencePath
Set-PropertyValue $queueGate 'candidateEvidencePath' $FailureWitnessPath
Set-PropertyValue $queueGate 'candidateCurrentHeadAuditEvidencePath' $CurrentHeadAuditPath
Set-PropertyValue $queueGate 'candidateAuditStatus' 'active_011_pre_fix_static'
Set-PropertyValue $queueGate 'nextCandidateTargetEvidencePath' ''
Set-PropertyValue $queueGate 'nextCandidateFailureWitnessPath' ''
Set-PropertyValue $queueGate 'nextCandidateCurrentHeadAuditEvidencePath' ''
Set-PropertyValue $queueGate 'nextCandidateSourceFixEvidencePath' ''
Set-PropertyValue $queueGate 'candidateStatus' 'activated_in_progress'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.executionTarget 'statement' '在固定 458 条书源与 Legado 提交基线下继续 R3 源码重构。011 已原子激活为唯一源码议题；先保持失败合同，再跨所有实际消费者修复属性列表值级去重。静态证据不得写成 passed 或 semantic_match；R4 运行时、原版差分、构建、安装和真机门禁仍延期。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-011 保持 in_progress：统一属性列表投影值级去重是唯一当前主因；S2T、037 和历史议题保持 verifying，仅等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '011-URL-05：先以失败见证为回归锚点，完成跨 Analyzer/JSVM/ArkWeb/工作流消费者的共享去重修复，再登记 source-fix 和 post-fix/current-head 静态证据。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'status' 'candidate_activated_in_progress'
Set-PropertyValue $queueAudit 'candidateIssueId' $issueId
Set-PropertyValue $queueAudit 'candidateIssues' @()
Set-PropertyValue $queueAudit 'candidateGateStatus' 'activated_in_progress'
Set-PropertyValue $queueAudit 'auditEvidencePath' $TargetEvidencePath
Set-PropertyValue $queueAudit 'failureWitnessPath' $FailureWitnessPath
Set-PropertyValue $queueAudit 'currentHeadEvidencePath' $CurrentHeadAuditPath
Set-PropertyValue $queueAudit 'transitionEvidencePath' $TransitionEvidencePath
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' ''
Set-PropertyValue $queueAudit 'nextRequired' '先修复共享属性列表投影的值级去重根因并生成 source-fix/post-fix/current-head 静态证据；R4 deferred。'

$plan = [System.Collections.Generic.List[object]]::new()
foreach ($item in @($objective.continuationPlan)) { [void]$plan.Add($item) }
$item = @($plan | Where-Object { [string]$_.id -eq '011-URL-05' }) | Select-Object -First 1
if ($null -eq $item) {
  $item = [pscustomobject][ordered]@{ id = '011-URL-05'; status = 'in_progress'; action = '保持失败见证，跨所有已登记消费者修复统一属性值去重根因，并登记 source-fix/post-fix/current-head。' }
  [void]$plan.Add($item)
} else {
  Set-PropertyValue $item 'status' 'in_progress'
  Set-PropertyValue $item 'action' '保持失败见证，跨所有已登记消费者修复统一属性值去重根因，并登记 source-fix/post-fix/current-head。'
}
Set-PropertyValue $objective 'continuationPlan' @($plan.ToArray())
Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelative) -State $state -Depth 80

$setObjectiveScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setObjectiveScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Refactor objective attachment failed.' }

$updateStateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
& $updateStateScript -StatePath (Get-RepoPath $stateRelative) -IssueId $issueId -IssueStatus in_progress -TaskId 'COMPAT-006' -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidencePaths | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update for 011 activation failed.' }

$refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Derived governance document refresh failed.' }

$registration = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_source_fix_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  previousIssueId = $previousIssueId
  issueId = $issueId
  transitionEvidencePath = $TransitionEvidencePath
  targetEvidencePath = $TargetEvidencePath
  failureWitnessPath = $FailureWitnessPath
  currentHeadAuditPath = $CurrentHeadAuditPath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_source_fix_only;011_in_progress;R4_runtime_build_device_and_legado_diff_deferred'
  idempotent = $true
}
Write-AtomicJson -RelativePath $RegistrationEvidencePath -Value $registration

$objectiveDocPath = Get-RepoPath $objectiveDocRelative
$objectiveDoc = [System.IO.File]::ReadAllText($objectiveDocPath, $utf8Strict)
$startMarker = '## 下一持续执行目标'
$endMarker = '## 持续目标'
$section = @"
## 下一持续执行目标

当前目标修订为 ``$revision``，执行游标为 ``R3_ISSUE_011_URL_ATTRIBUTE_SOURCE_FIX``。`ISSUE-COMPAT-011` 已按五项静态证据门禁原子激活为唯一活动源码议题（in_progress），S2T 保持 verifying 等待 R4。

当前唯一源码任务是修复 Legado `AnalyzeByJSoup` 属性列表的值级去重语义：

1. 保留失败前见证 ``$FailureWitnessPath``，其确定性投影显示 Legado `/a\\n/b`、V2 修复前 `/a\\n/a\\n/b`；不得用空结果、缓存或旧执行器掩盖差异。
2. 按 current-head 审计的 9 个消费者统一修复 Analyzer 主投影、CSS 列表投影、标准/Native/Rhino JSVM、ArkWeb runtime 和工作流继承边界；requestCarrier 与 typed handoff 的 URL 解析边界不得被去重修复污染。
3. 修复前先保持失败合同；修复后只生成 source-fix、post-fix contract、current-head hash 和文档一致性静态证据，状态最多为 verifying，不产生 passed 或 semantic_match。
4. 运行时批次、真实网络、Legado 运行时差分、构建、签名、安装和 Android/HarmonyOS 设备验证全部属于 R4，由用户单独开启。

机器证据：``$TransitionEvidencePath``、``$TargetEvidencePath``、``$FailureWitnessPath``、``$CurrentHeadAuditPath``；唯一事实源：tools/legado-compat/state/full-source-validation-state.json 和 tools/legado-compat/state/refactor-objective.json。

"@
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if (-not [regex]::IsMatch($objectiveDoc, $pattern)) { throw 'objective document target section marker missing.' }
$objectiveDoc = [regex]::Replace($objectiveDoc, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $section })
$temporaryDoc = "$objectiveDocPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
  [System.IO.File]::WriteAllText($temporaryDoc, $objectiveDoc, $utf8NoBom)
  Move-Item -LiteralPath $temporaryDoc -Destination $objectiveDocPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryDoc) { [System.IO.File]::Delete($temporaryDoc) }
}

[pscustomobject][ordered]@{
  status = 'registered'
  activeIssueId = $issueId
  previousIssueId = $previousIssueId
  transitionEvidencePath = $TransitionEvidencePath
  registrationEvidencePath = $RegistrationEvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
