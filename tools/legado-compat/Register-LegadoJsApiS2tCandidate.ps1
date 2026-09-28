[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$previousIssueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$candidateTargetRelative = 'tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json'
$failureRelative = 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json'
$currentHeadRelative = 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809.json'
$settlementRelative = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json'
$semanticContractRelative = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json'
$mappingRelative = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
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
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Assert-Registration {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "S2T candidate registration blocked: $Message" }
}

function Add-EvidenceUnique {
  param([object]$Issue, [string[]]$Paths)
  $existing = New-Object 'System.Collections.Generic.List[string]'
  $property = $Issue.PSObject.Properties['evidencePaths']
  if ($null -ne $property -and $null -ne $property.Value) {
    foreach ($value in @($property.Value)) {
      if (-not $existing.Contains([string]$value)) { [void]$existing.Add([string]$value) }
    }
  }
  foreach ($path in $Paths) {
    if (-not $existing.Contains($path)) { [void]$existing.Add($path) }
  }
  Set-PropertyValue -Object $Issue -Name 'evidencePaths' -Value @($existing.ToArray())
}

function Set-PlanItem {
  param([System.Collections.Generic.List[object]]$Plan, [string]$Id, [string]$Status, [string]$Action, [string]$Evidence = '')
  $item = @($Plan | Where-Object { [string]$_.id -eq $Id }) | Select-Object -First 1
  if ($null -eq $item) {
    $item = [pscustomobject][ordered]@{ id = $Id; status = $Status; action = $Action }
    if ($Evidence.Length -gt 0) { $item | Add-Member -NotePropertyName 'evidence' -NotePropertyValue $Evidence }
    [void]$Plan.Add($item)
    return
  }
  Set-PropertyValue $item 'status' $Status
  Set-PropertyValue $item 'action' $Action
  if ($Evidence.Length -gt 0) { Set-PropertyValue $item 'evidence' $Evidence }
}

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
$target = Read-StrictJson $candidateTargetRelative
$failure = Read-StrictJson $failureRelative
$fixture = Read-StrictJson $fixtureRelative
$audit = Read-StrictJson $currentHeadRelative
$settlement = Read-StrictJson $settlementRelative
$semanticContract = Read-StrictJson $semanticContractRelative
$mapping = Read-StrictJson $mappingRelative

Assert-Registration ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Registration ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $previousIssueId) '037 must be the sole active issue before handoff.'
Assert-Registration ([string]$objective.authority.activeIssueId -eq $previousIssueId -and [string]$objective.objective.activeIssue -eq $previousIssueId) 'objective is not at the 037 boundary.'
Assert-Registration ([string]$target.status -eq 'candidate_gate_ready' -and [string]$target.candidateIssueId -eq $issueId -and -not [bool]$target.semanticMatchAllowed) 'candidate target gate is incomplete.'
Assert-Registration ([string]$failure.status -eq 'failed' -and [string]$audit.status -eq 'passed_static_only') 'failure witness/current-head audit are not static-only.'
Assert-Registration ([string]$settlement.status -eq 'passed_static_only' -and [string]$semanticContract.status -eq 'passed' -and [string]$mapping.status -eq 'passed') 'JS API settlement evidence is incomplete.'

$evidencePaths = @($candidateTargetRelative, $settlementRelative, $semanticContractRelative, $mappingRelative, $fixtureRelative, $failureRelative, $currentHeadRelative)
$closeCondition = [string]$fixture.closeCondition
$summary = 'java.s2t 真实调用缺口已通过静态候选门禁：固定 Legado JsExtensions.kt:551-552、4 条冻结书源调用、默认 ArkWeb 缺成员、Native shim 非默认、Analyzer/Rule/JSVM/ArkWeb/工作流/输出六层消费者矩阵均已绑定。当前进入源码修复，R4 运行时差分、构建、安装和设备验证仍延期。'

$issues = New-Object 'System.Collections.Generic.List[object]'
foreach ($issue in @($state.governance.issues)) { [void]$issues.Add($issue) }
$previousIssue = @($issues | Where-Object { [string]$_.id -eq $previousIssueId }) | Select-Object -First 1
Assert-Registration ($null -ne $previousIssue -and [string]$previousIssue.status -eq 'verifying') '037 must remain verifying.'
$candidateIssue = @($issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $candidateIssue) {
  $candidateIssue = [pscustomobject][ordered]@{
    id = $issueId
    taskId = 'COMPAT-006'
    status = 'in_progress'
    severity = 'P1'
    attempts = 0
    rootCauseId = $issueId
    summary = $summary
    closeCondition = $closeCondition
    evidencePaths = $evidencePaths
    classification = 'unsupported_api'
    affectedSourceOrdinals = @($fixture.api.affectedSourceOrdinals)
    affectedSourceHashPrefixes = @($fixture.api.affectedSourceHashPrefixes)
    lastUpdatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
  [void]$issues.Add($candidateIssue)
} else {
  Set-PropertyValue $candidateIssue 'status' 'in_progress'
  Set-PropertyValue $candidateIssue 'severity' 'P1'
  Set-PropertyValue $candidateIssue 'rootCauseId' $issueId
  Set-PropertyValue $candidateIssue 'summary' $summary
  Set-PropertyValue $candidateIssue 'closeCondition' $closeCondition
  Set-PropertyValue $candidateIssue 'classification' 'unsupported_api'
  Set-PropertyValue $candidateIssue 'affectedSourceOrdinals' @($fixture.api.affectedSourceOrdinals)
  Set-PropertyValue $candidateIssue 'affectedSourceHashPrefixes' @($fixture.api.affectedSourceHashPrefixes)
  Add-EvidenceUnique -Issue $candidateIssue -Paths $evidencePaths
  Set-PropertyValue $candidateIssue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
}
$state.governance.issues = @($issues.ToArray())
$state.governance.activeIssueId = $issueId
$state.revision = $targetRevision

$objective.targetRevision = $targetRevision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.continuationMode = 'R3_JS_API_S2T_DEFAULT_RUNTIME_SOURCE_FIX'
$objective.nextAction = '执行 S2T-04：在失败见证之后修复默认 ArkWeb legado_runtime.html 的 java.s2t，并先完成静态 post-fix contract；R4 仍 deferred。'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME is now the sole active source-closure issue after the completed JS API settlement and five-item candidate gate. ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH and earlier static closures remain verifying for deferred R4.'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-JS-API-S2T-DEFAULT-RUNTIME'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '当前唯一活动源码议题为 ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME；固定 Legado JsExtensions.s2t 已确认，4 条 Search 书源调用绑定到默认 ArkWeb runtime 缺成员，Native JSVM shim 不得掩盖默认路径缺口。先保留 unsupported_api 失败见证，再修复默认 runtime 与 registry；037 和历史议题保持 verifying，仅等待 R4。'
$queueGate = $objective.objective.queueSelectionGate
Set-PropertyValue $queueGate 'status' 'issue_selected_r3_jsapi_s2t_default_runtime'
Set-PropertyValue $queueGate 'currentAnchor' $issueId
Set-PropertyValue $queueGate 'selectedIssue' $issueId
Set-PropertyValue $queueGate 'candidateIssues' @()
Set-PropertyValue $queueGate 'evidencePath' $candidateTargetRelative
Set-PropertyValue $queueGate 'candidateEvidencePath' $failureRelative
Set-PropertyValue $queueGate 'candidateCurrentHeadAuditEvidencePath' $currentHeadRelative
Set-PropertyValue $queueGate 'candidateAuditStatus' 'active_s2t_pre_fix_static'
Set-PropertyValue $queueGate 'nextCandidateTargetEvidencePath' ''
Set-PropertyValue $queueGate 'nextCandidateFailureWitnessPath' ''
Set-PropertyValue $queueGate 'nextCandidateCurrentHeadAuditEvidencePath' ''
Set-PropertyValue $queueGate 'nextCandidateSourceFixEvidencePath' ''
$apiSettlement = $objective.objective.apiCapabilitySettlement
Set-PropertyValue $apiSettlement 'status' 'completed_static_only'
Set-PropertyValue $apiSettlement 'settlementEvidencePath' $settlementRelative
Set-PropertyValue $apiSettlement 'semanticContractEvidencePath' $semanticContractRelative
Set-PropertyValue $apiSettlement 'candidateTargetEvidencePath' $candidateTargetRelative
Set-PropertyValue $apiSettlement 'candidateIssueId' $issueId
Set-PropertyValue $apiSettlement 'candidateStatus' 'active_in_progress'
Set-PropertyValue $apiSettlement 'semanticMatchAllowed' $false
Set-PropertyValue $apiSettlement 'runtimeActionsPerformed' @()
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.executionTarget 'statement' '在固定 458 条书源与 Legado 提交基线下继续 R3 源码重构。JS API 静态结算已完成；当前只治理默认 ArkWeb java.s2t 缺口，先保留失败见证并跨 runtime/registry/工作流消费者修复。静态证据不得写成 passed 或 semantic_match；R4 运行时、原版差分、构建、安装和真机门禁仍延期。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME 保持 in_progress：默认 ArkWeb legado_runtime.html 缺少 java.s2t；先修复默认 runtime 和 registry，037 及其它静态议题保持 verifying 等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' 'S2T-04：在失败见证之后修改默认 ArkWeb runtime；S2T-05：运行静态 post-fix contract、current-head 哈希和文档一致性检查；R4 deferred。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'status' 'candidate_activated_in_progress'
Set-PropertyValue $queueAudit 'candidateIssueId' $issueId
Set-PropertyValue $queueAudit 'candidateIssues' @()
Set-PropertyValue $queueAudit 'candidateGateStatus' 'activated_in_progress'
Set-PropertyValue $queueAudit 'auditEvidencePath' $candidateTargetRelative
Set-PropertyValue $queueAudit 'failureWitnessPath' $failureRelative
Set-PropertyValue $queueAudit 'currentHeadEvidencePath' $currentHeadRelative
Set-PropertyValue $queueAudit 'nextRequired' '先完成 S2T-04 默认 ArkWeb runtime 源码修复和 S2T-05 静态 post-fix contract；修复前不得叠加第二根因。'

$plan = New-Object 'System.Collections.Generic.List[object]'
foreach ($item in @($objective.continuationPlan)) { [void]$plan.Add($item) }
Set-PlanItem -Plan $plan -Id 'JSAPI-SETTLE-01' -Status 'completed' -Action '冻结并核对 118/74/44 矩阵事实，禁止把静态未注册直接当作运行时失败。' -Evidence 'tools/legado-compat/evidence/legado-js-api-usage-matrix.json'
Set-PlanItem -Plan $plan -Id 'JSAPI-SETTLE-02' -Status 'completed' -Action '44 个 token 的 140 次出现已绑定冻结源序号、字段、规则族、脱敏指纹和调用形状。' -Evidence $mappingRelative
Set-PlanItem -Plan $plan -Id 'JSAPI-SETTLE-03' -Status 'completed' -Action '逐项对照固定 Legado 实现完成 44 个引用分类：SUPPORTED=6、UNSUPPORTED_API=24、NEEDS_INTERACTION=1、NAMESPACE_OR_IMPORT=7、STATIC_MEMBER_REFERENCE=6；静态结算不等于运行时兼容。' -Evidence $settlementRelative
Set-PlanItem -Plan $plan -Id 'JSAPI-SETTLE-04' -Status 'completed' -Action 'java.s2t 候选已通过五项证据门禁并原子登记为唯一活动源码议题；失败 fixture、current-head 审计、V2 六层消费者矩阵和关闭条件已绑定。' -Evidence $candidateTargetRelative
Set-PlanItem -Plan $plan -Id 'JSAPI-SETTLE-05' -Status 'in_progress' -Action '在失败见证之后修复默认 ArkWeb java.s2t，运行静态 post-fix contract、JSON/UTF-8/哈希和证据写出隔离检查，再刷新所有文档。' -Evidence $failureRelative
Set-PlanItem -Plan $plan -Id 'JSAPI-SETTLE-06' -Status 'deferred' -Action 'R4 运行时 fixture、458 条 Harness、Legado 同输入差分、构建、安装和真机验证由用户单独开启。'
Set-PlanItem -Plan $plan -Id 'S2T-01' -Status 'completed' -Action '固定 Legado JsExtensions.s2t、4 条受影响书源和 4 个确定性转换案例，生成失败见证。' -Evidence $failureRelative
Set-PlanItem -Plan $plan -Id 'S2T-02' -Status 'completed' -Action '完成 Analyzer/compiler、默认 ArkWeb、Native JSVM、脚本作用域、工作流/输出和 registry 六层消费者审计。' -Evidence $currentHeadRelative
Set-PlanItem -Plan $plan -Id 'S2T-03' -Status 'completed' -Action '五项候选证据门禁通过并原子登记 S2T 为唯一活动源码议题。' -Evidence $candidateTargetRelative
Set-PlanItem -Plan $plan -Id 'S2T-04' -Status 'in_progress' -Action '只修改默认 ArkWeb runtime 与 capability registry；不得依赖 Native shim 或旧执行器回退。'
Set-PlanItem -Plan $plan -Id 'S2T-05' -Status 'planned' -Action '生成 source-fix、post-fix static contract、current-head 哈希和文档一致性证据；保持 verifying。'
Set-PlanItem -Plan $plan -Id 'S2T-06' -Status 'deferred' -Action 'R4 运行时、Legado 差分、构建、安装、设备和 458 条回归由用户单独开启。'
Set-PropertyValue $objective 'continuationPlan' @($plan.ToArray())
Set-PropertyValue $objective 'completionGate' @($objective.completionGate + @('JS API 结算静态证据必须保留 44/140 分类结果；S2T 源码修复前后不得覆盖失败见证，且 R4 仍是唯一运行时关闭门禁。'))

Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelative) -State $state -Depth 70

$setObjectiveScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setObjectiveScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'refactor objective attachment failed.' }

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath (Get-RepoPath $stateRelative) -IssueId $issueId -IssueStatus in_progress -TaskId 'COMPAT-006' -Summary $summary -CloseCondition $closeCondition -EvidencePath ($evidencePaths -join ',') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'governance state refresh failed.' }

$objectiveDocRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocPath = Get-RepoPath $objectiveDocRelative
$objectiveDoc = [System.IO.File]::ReadAllText($objectiveDocPath, $strictUtf8)
$objectiveStart = '## R3-JS-API-CAPABILITY-SETTLEMENT-PREFLIGHT'
$objectiveEnd = '## 单议题执行规则'
$objectiveSection = @"
## R3-JS-API-CAPABILITY-SETTLEMENT-PREFLIGHT

当前目标修订为 ``$targetRevision``。静态 JS API 结算已完成：118 个 API token 中 44 个未注册命中已逐个绑定到固定 458 条书源的 140 次出现，并完成固定 Legado 实现、V2 默认 runtime/Native JSVM/工作流消费者分类。结算结果为 `SUPPORTED=6`、`UNSUPPORTED_API=24`、`NEEDS_INTERACTION=1`、`NAMESPACE_OR_IMPORT=7`、`STATIC_MEMBER_REFERENCE=6`；这些数字只表示静态证据，不表示运行时兼容。

本轮唯一活动源码议题改为 ``$issueId`` (`in_progress`)。候选 ``java.s2t`` 的五项门禁已通过：Legado `JsExtensions.kt:551-552` 的 `ChineseUtils.s2t(text)` 语义、4 条受影响 Search 书源、失败见证、V2 六层消费者矩阵以及结构化关闭条件均已登记。037 与所有历史源码议题保持 `verifying`，只等待 R4。

### S2T 源码修复目标

1. 保留 `tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json` 的失败状态；不得用 Native JSVM 的已有 shim、旧执行器或空结果掩盖默认 ArkWeb 缺口。
2. 只在 `legado_runtime.html` 的默认 `java` 对象补齐 `s2t`，复用现有 `t2s` 的映射边界，并在 `LegadoJsApiContractRegistry.ets` 完成能力登记；Analyzer、Rule IR、脚本作用域、工作流和输出消费者保持同一结构化错误契约。
3. 修复后只执行静态 post-fix contract、UTF-8/JSON/哈希和证据隔离检查，状态最多为 `verifying`；不启动 458 条批次、网络、构建、安装、设备或 Legado 运行时差分。
4. R4 统一入口保留为唯一关闭条件：定向/全量 Harness、同输入 Legado 差分、构建和真机证据完成后，才允许改变 `passed` 或 `semantic_match`。

证据：``$candidateTargetRelative``、``$failureRelative``、``$currentHeadRelative``、``$settlementRelative``、``$semanticContractRelative``、``$mappingRelative``。

"@
$objectivePattern = '(?s)' + [regex]::Escape($objectiveStart) + '.*?(?=' + [regex]::Escape($objectiveEnd) + ')'
if (-not [regex]::IsMatch($objectiveDoc, $objectivePattern)) { throw 'objective JS API section marker missing.' }
$objectiveDoc = [regex]::Replace($objectiveDoc, $objectivePattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $objectiveSection })
Write-AtomicText -RelativePath $objectiveDocRelative -Value $objectiveDoc

$governanceRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$governancePath = Get-RepoPath $governanceRelative
$governanceDoc = [System.IO.File]::ReadAllText($governancePath, $strictUtf8)
$governanceStart = '## R3 JS API 能力结算前置目标（2026-08-09）'
$governanceEnd = '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->'
$governanceSection = @"
## R3 JS API 能力结算与 S2T 源码修复目标（2026-08-09）

当前目标修订为 ``$targetRevision``。静态结算已完成并绑定固定 458 条书源、源包 SHA-256 和 Legado 提交：118 个 API token、44 个未注册 token、140 次出现；分类为 `SUPPORTED=6`、`UNSUPPORTED_API=24`、`NEEDS_INTERACTION=1`、`NAMESPACE_OR_IMPORT=7`、`STATIC_MEMBER_REFERENCE=6`。证据：``$settlementRelative``、``$semanticContractRelative``、``$mappingRelative``。

候选 ``java.s2t`` 已通过五项证据门禁并成为当前唯一活动源码议题 ``$issueId`` (`in_progress`)：固定 Legado `JsExtensions.kt:551-552`、4 条 Search 书源、默认 ArkWeb 缺失成员的失败见证、V2 六层消费者矩阵和关闭条件均已登记。037 及旧议题保持 `verifying`，R4 运行时/原版差分/构建/安装/设备继续延期。

当前只允许：保留失败证据 -> 修复默认 `legado_runtime.html` 的 `java.s2t` -> 更新 capability registry -> 运行静态 post-fix contract -> 原子刷新台账。禁止 Native shim 回退、空结果伪通过、458 条运行时批次和真实网络。

候选证据：``$candidateTargetRelative``、``$failureRelative``、``$fixtureRelative``、``$currentHeadRelative``。

"@
$governancePattern = '(?s)' + [regex]::Escape($governanceStart) + '.*?(?=' + [regex]::Escape($governanceEnd) + ')'
if (-not [regex]::IsMatch($governanceDoc, $governancePattern)) { throw 'governance JS API section marker missing.' }
$governanceDoc = [regex]::Replace($governanceDoc, $governancePattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $governanceSection })
Write-AtomicText -RelativePath $governanceRelative -Value $governanceDoc

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  previousIssueId = $previousIssueId
  targetRevision = $targetRevision
  activeIssueId = $issueId
  candidateEvidencePath = $candidateTargetRelative
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_source_fix_only;R4_runtime_build_device_and_legado_diff_deferred'
} | ConvertTo-Json -Depth 20
