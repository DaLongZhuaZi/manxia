[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ContractPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-resolution-011-20260809.json',
  [string]$AffectedSetPath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/affected-source-set.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-pre-fix-20260809.json',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/target.json'
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
$activeIssueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$candidateIssueId = 'ISSUE-COMPAT-011'
$candidateRevision = '2026-08-09-actual-docs-source-refactor-url-attribute-011-gate-ready'
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'

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
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Preflight([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE011_PREFLIGHT_FAILED:$Message" }
}

function Set-PlanItem([System.Collections.Generic.List[object]]$Plan, [string]$Id, [string]$Status, [string]$Action, [string[]]$Evidence = @()) {
  $item = @($Plan | Where-Object { [string]$_.id -eq $Id }) | Select-Object -First 1
  if ($null -eq $item) {
    $item = [pscustomobject][ordered]@{ id = $Id; status = $Status; action = $Action }
    [void]$Plan.Add($item)
  } else {
    Set-PropertyValue $item 'status' $Status
    Set-PropertyValue $item 'action' $Action
  }
  if ($Evidence.Count -gt 0) { Set-PropertyValue $item 'evidence' @($Evidence) }
}

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
$stateBaseline = $state.baseline
$objectiveBaseline = $objective.baseline
Assert-Preflight ([int]$stateBaseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Preflight ([string]$stateBaseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Preflight ([string]$stateBaseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Preflight ([int]$objectiveBaseline.sourceCount -eq $sourceCount) 'objective source count drifted'
Assert-Preflight ([string]$objectiveBaseline.sourcePackageSha256 -eq $sourceHash) 'objective source hash drifted'
Assert-Preflight ([string]$objectiveBaseline.legadoCommit -eq $legadoCommit) 'objective Legado commit drifted'

$governance = $state.governance
Assert-Preflight ([string]$governance.activeTaskId -eq 'COMPAT-006') 'COMPAT-006 is not the active task'
Assert-Preflight ([string]$governance.activeIssueId -eq $activeIssueId) 'S2T is not the current active issue'
$activeIssue = @($governance.issues | Where-Object { [string]$_.id -eq $activeIssueId }) | Select-Object -First 1
Assert-Preflight ($null -ne $activeIssue -and [string]$activeIssue.status -eq 'verifying') 'S2T must remain verifying'

$contract = Read-StrictJson $ContractPath
$affected = Read-StrictJson $AffectedSetPath
$failureWitness = Read-StrictJson $FailureWitnessPath
$currentHeadAudit = Read-StrictJson $CurrentHeadAuditPath
Assert-Preflight ([string]$contract.issueId -eq $candidateIssueId) '011 contract issue mismatch'
Assert-Preflight ([string]$contract.status -eq 'passed_static_only') '011 static contract is not passed_static_only'
Assert-Preflight (-not [bool]$contract.semanticMatchAllowed) '011 static contract cannot enable semantic match'
Assert-Preflight (@($contract.runtimeActionsPerformed).Count -eq 0) '011 contract performed runtime actions'
Assert-Preflight ([string]$affected.issueId -eq $candidateIssueId) '011 affected set issue mismatch'
Assert-Preflight ([string]$affected.status -eq 'passed_static_only') '011 affected set is not passed_static_only'
Assert-Preflight ([int]$affected.baseline.sourceCount -eq $sourceCount) '011 affected set source count drifted'
Assert-Preflight ([string]$affected.baseline.sourcePackageSha256 -eq $sourceHash) '011 affected set hash drifted'
Assert-Preflight ([int]$affected.affectedSourceCount -gt 0) '011 affected set is empty'
Assert-Preflight ([int]$affected.affectedRuleOccurrenceCount -gt 0) '011 affected rule set is empty'
Assert-Preflight (@($contract.consumerMatrix).Count -ge 5) '011 V2 consumer matrix is incomplete'
Assert-Preflight ([string]$failureWitness.issueId -eq $candidateIssueId) '011 failure witness issue mismatch'
Assert-Preflight ([string]$failureWitness.status -eq 'failed_static_only') '011 failure witness is not failed_static_only'
Assert-Preflight ([string]$failureWitness.failureClass -eq 'selector_attribute_value_deduplication_mismatch') '011 failure witness class drifted'
Assert-Preflight ([int]$failureWitness.baseline.sourceCount -eq $sourceCount) '011 failure witness source count drifted'
Assert-Preflight ([string]$failureWitness.baseline.sourcePackageSha256 -eq $sourceHash) '011 failure witness hash drifted'
Assert-Preflight (@($failureWitness.runtimeActionsPerformed).Count -eq 0) '011 failure witness performed runtime actions'
Assert-Preflight (-not [bool]$failureWitness.semanticMatchAllowed) '011 failure witness cannot enable semantic match'
Assert-Preflight ([string]$currentHeadAudit.issueId -eq $candidateIssueId) '011 current-head audit issue mismatch'
Assert-Preflight ([string]$currentHeadAudit.status -eq 'failed_static_only') '011 current-head audit must remain failed_static_only until source fix'
Assert-Preflight ([string]$currentHeadAudit.inventoryStatus -eq 'complete_static_inventory') '011 current-head consumer inventory is incomplete'
Assert-Preflight ([int]$currentHeadAudit.unresolvedGapCount -gt 0) '011 current-head audit must retain unresolved pre-fix gaps'
Assert-Preflight ([int](@($currentHeadAudit.consumerMatrix)).Count -ge 9) '011 current-head consumer matrix is incomplete'
Assert-Preflight ([string]$currentHeadAudit.primaryCause.classification -eq 'selector_extraction_vs_url_resolution_boundary') '011 current-head primary cause drifted'
Assert-Preflight (@($currentHeadAudit.runtimeActionsPerformed).Count -eq 0) '011 current-head audit performed runtime actions'
Assert-Preflight (-not [bool]$currentHeadAudit.semanticMatchAllowed) '011 current-head audit cannot enable semantic match'

$targetEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_preflight_target'
  status = 'candidate_gate_ready'
  issueId = $candidateIssueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  currentObjectiveRevision = $candidateRevision
  candidateRevision = $candidateRevision
  activeIssueId = $activeIssueId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  rootCause = [ordered]@{
    classification = 'selector_extraction_vs_url_resolution_boundary'
    statement = 'Legado AnalyzeByJSoup returns Element.attr raw values; URL normalization belongs to AnalyzeRule isUrl/request consumers. V2 must preserve this boundary across Analyzer, Rule IR, ArkWeb/JSVM and workflow carriers.'
    legadoLocations = @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt:48-80,272-276', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt:230-240,263-319')
  }
  evidenceGate = @(
    [ordered]@{ id = 'fixed_legado_semantics'; status = 'passed'; evidencePaths = @($ContractPath) },
    [ordered]@{ id = 'affected_source_set'; status = 'passed'; evidencePaths = @($AffectedSetPath); affectedSourceCount = [int]$affected.affectedSourceCount; affectedRuleOccurrenceCount = [int]$affected.affectedRuleOccurrenceCount },
    [ordered]@{ id = 'reproducible_failure_witness'; status = 'passed_static_only'; evidencePaths = @($FailureWitnessPath); mode = 'deterministic_static_projection'; runtimeActionsPerformed = @() },
    [ordered]@{ id = 'v2_consumer_matrix'; status = 'completed_static_only'; evidencePaths = @($CurrentHeadAuditPath); consumerCount = @($currentHeadAudit.consumerMatrix).Count; unresolvedGapCount = [int]$currentHeadAudit.unresolvedGapCount; nextAction = '在已登记的 7 个消费者缺口上建立统一属性值去重修复，并生成 post-fix/current-head 证据。' },
    [ordered]@{ id = 'close_condition'; status = 'passed'; evidencePaths = @($ContractPath) }
  )
  candidateGateStatus = 'candidate_gate_ready_selection_required'
  preparedCandidate = [ordered]@{ issueId = $candidateIssueId; status = 'candidate_gate_ready'; activeIssueUnchanged = $true; activationAllowed = $true }
  plan = @(
    [ordered]@{ id = '011-URL-01'; status = 'completed'; action = '固定 Legado AnalyzeByJSoup/AnalyzeRule 语义并通过 011 静态合同。'; evidence = @($ContractPath) },
    [ordered]@{ id = '011-URL-02'; status = 'completed'; action = '扫描固定 458 条书源 URL 属性节点，生成脱敏影响集合。'; evidence = @($AffectedSetPath) },
    [ordered]@{ id = '011-URL-03'; status = 'completed'; action = '完成重复属性值的确定性静态失败前见证；运行时执行仍延期。'; evidence = @($FailureWitnessPath) },
    [ordered]@{ id = '011-URL-04'; status = 'completed'; action = '完成 Analyzer、Rule IR、Matcher、ArkWeb、JSVM、工作流和 requestCarrier 的 current-head 消费者闭合审计。'; evidence = @($CurrentHeadAuditPath) },
    [ordered]@{ id = '011-URL-05'; status = 'planned'; action = '五项静态证据门禁已齐全；激活 011 后修复统一属性值去重根因，生成 source-fix、post-fix contract 和 current-head evidence。' },
    [ordered]@{ id = '011-URL-06'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' }
  )
  evidencePaths = @($ContractPath, $AffectedSetPath, $FailureWitnessPath, $CurrentHeadAuditPath)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  closeCondition = 'After atomic activation, unify value-level deduplication at the shared V2 selector-list projection boundary, prove all listed consumers use it, then generate post-fix/current-head evidence; only R4 may establish runtime or semantic_match closure.'
  verificationPolicy = 'r3_candidate_gate_ready_static_only;active_s2t_verifying_until_atomic_activation;R4_runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -RelativePath $TargetEvidencePath -Value $targetEvidence

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $candidateRevision
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_011_URL_ATTRIBUTE_CANDIDATE_GATE_READY'
Set-PropertyValue $objective 'nextAction' '011 五项静态证据门禁已齐全；下一步按既有队列转移协议原子激活 ISSUE-COMPAT-011，然后仅治理共享属性列表投影的重复值语义。'
Set-PropertyValue $objective.objective 'statement' '在固定 458 条书源、源包哈希和 Legado 提交下维护 V2 源码级语义闭环。S2T 静态闭合保持 verifying；ISSUE-COMPAT-011 的固定语义、影响集合、失败见证和 V2 current-head 消费者审计已齐全，下一步是原子激活 011 并修复统一属性值去重根因。'
Set-PropertyValue $objective.objective 'preparedCandidateIssue' $candidateIssueId
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-011-URL-ATTRIBUTE'
Set-PropertyValue $objective.executionTarget 'nextIssues' @($candidateIssueId)
Set-PropertyValue $objective.executionTarget 'statement' 'S2T 保持 verifying；011 五项静态证据门禁已齐全，下一步原子激活 011，建立/保持重复属性值失败合同，跨 Analyzer、Rule IR、Matcher、标准/Native/Rhino JSVM、ArkWeb runtime 和工作流消费者完成统一源码修复。运行时、网络、Legado 差分、构建、安装和设备操作继续 deferred。'
Set-PropertyValue $objective.executionTarget 'allowedActions' @(
  '读取固定 Legado AnalyzeByJSoup/AnalyzeRule、冻结书源规则和 V2 Analyzer/Rule IR/Matcher/ArkWeb/JSVM/工作流路径',
  '执行 011 确定性 fixture、静态合同、脱敏影响集合、失败见证和 current-head 审计',
  '在失败见证存在且五项证据齐全后按队列协议激活 011，再修改真实源码并登记 source-fix',
  '原子刷新机器状态、治理台账、证据索引、差分摘要和调查报告执行区块'
)
Set-PropertyValue $objective.executionTarget 'forbiddenActions' @(
  '运行 458 条运行时批次、真实网络端点或 Legado 运行时差分',
  '构建、签名、安装、控制 Android/HarmonyOS 设备或启动 R4 回归',
  '通过旧 NovelSourceExecutor、缓存、空结果或未执行流程掩盖 URL 语义差异',
  '把 011 静态证据写成 passed 或 semantic_match'
)
Set-PropertyValue $objective.executionTarget 'issueProtocol' @(
  'S2T 失败见证和静态证据保持不可覆盖；当前活动 issue 不变',
  '011 五项静态证据已齐全；激活后必须以共享属性值去重边界作为唯一主因，不叠加无关补丁',
  '发现第二主因或状态漂移时停止并登记唯一新议题，不叠加补丁',
  '所有证据绑定同一 frozen baseline，原始书源、Cookie、账号和正文不进入证据'
)
Set-PropertyValue $objective.executionTarget 'exitCriteria' @(
  '011 失败前静态见证真实存在且可重现，不能由摘要或推断替代',
  '011 五项静态证据齐全，下一步只允许一次原子激活；激活前 activeIssueId 仍为 S2T、S2T 状态仍为 verifying',
  '激活和源码修复期间 semanticMatchAllowed=false，静态闭合仍只能是 verifying',
  'R4 运行时、Legado 差分、构建、安装和真机验证入口保持明确延期'
)
$continuation = $objective.continuationTarget
Set-PropertyValue $continuation 'activeBoundary' 'S2T 是当前唯一活动源码议题并保持 verifying；011 五项静态证据已齐全，尚未激活，下一步原子转移到 011。'
Set-PropertyValue $continuation 'nextTransition' '011-URL-04 current-head 消费者审计已完成；执行一次原子候选转移激活 011，随后只修复属性列表投影重复值根因，R4 继续延期。'
Set-PropertyValue $continuation 'preparedCandidate' $targetEvidence
$queueAudit = $continuation.queueAudit
Set-PropertyValue $queueAudit 'candidateIssueId' $candidateIssueId
Set-PropertyValue $queueAudit 'status' 'candidate_gate_ready_selection_required'
Set-PropertyValue $queueAudit 'auditEvidencePath' $TargetEvidencePath
Set-PropertyValue $queueAudit 'failureWitnessPath' $FailureWitnessPath
Set-PropertyValue $queueAudit 'currentHeadEvidencePath' $CurrentHeadAuditPath
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' ''
Set-PropertyValue $queueAudit 'transitionEvidencePath' ''
Set-PropertyValue $queueAudit 'postRegistrationEvidencePath' ''
Set-PropertyValue $queueAudit 'priorActiveIssueId' $activeIssueId
Set-PropertyValue $queueAudit 'nextRequired' '011 五项静态证据已齐全；按既有队列转移协议原子激活 011，激活后先建立统一属性列表投影修复。'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'candidate_gate_ready_selection_required'
Set-PropertyValue $queueAudit 'candidateIssues' @($candidateIssueId)
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateTargetEvidencePath' $TargetEvidencePath
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateFailureWitnessPath' $FailureWitnessPath
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateCurrentHeadAuditEvidencePath' $CurrentHeadAuditPath
Set-PropertyValue $objective.objective.queueSelectionGate 'nextCandidateSourceFixEvidencePath' ''
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateIssues' @($candidateIssueId)
Set-PropertyValue $objective.objective.queueSelectionGate 'candidateStatus' 'candidate_gate_ready_selection_required'

$plan = [System.Collections.Generic.List[object]]::new()
foreach ($item in @($objective.continuationPlan)) { [void]$plan.Add($item) }
Set-PlanItem -Plan $plan -Id '011-URL-01' -Status 'completed' -Action '固定 Legado URL 属性原始值与请求边界语义，静态合同通过。' -Evidence @($ContractPath)
Set-PlanItem -Plan $plan -Id '011-URL-02' -Status 'completed' -Action '完成固定 458 条书源 URL 属性节点的脱敏影响集合扫描。' -Evidence @($AffectedSetPath)
Set-PlanItem -Plan $plan -Id '011-URL-03' -Status 'completed' -Action '完成重复属性值的确定性静态失败前见证；运行时执行仍延期。' -Evidence @($FailureWitnessPath)
Set-PlanItem -Plan $plan -Id '011-URL-04' -Status 'completed' -Action '完成 V2 Analyzer、Rule IR、Matcher、ArkWeb、JSVM、工作流和 requestCarrier 消费者闭合审计。' -Evidence @($CurrentHeadAuditPath)
Set-PlanItem -Plan $plan -Id '011-URL-05' -Status 'in_progress' -Action '五项静态证据已齐全；原子激活 011 后修复统一属性值去重根因，并登记 source-fix/post-fix/current-head。'
Set-PlanItem -Plan $plan -Id '011-URL-06' -Status 'deferred' -Action 'R4 运行时、Legado 差分、构建、安装和真机验证由用户单独开启。'
Set-PropertyValue $objective 'continuationPlan' @($plan.ToArray())
Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

$setObjectiveScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setObjectiveScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $activeIssueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Refactor objective mirror update failed.' }

$updateStateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = '011 五项静态证据门禁已齐全：313 条书源/1262 个 URL 属性节点、14 项静态合同、重复属性值 failed_static_only 见证和 9 个消费者 current-head 审计均已绑定；候选等待一次原子激活，不启动 R4。'
$closeCondition = 'After atomic activation, unify value-level deduplication at the shared V2 selector-list projection boundary, prove all listed consumers use it, then generate post-fix/current-head evidence; R4 runtime, build, device and Legado differential remain deferred.'
$registrationEvidence = [string[]]@($TargetEvidencePath, $ContractPath, $AffectedSetPath, $FailureWitnessPath, $CurrentHeadAuditPath)
& $updateStateScript -StatePath (Get-RepoPath $stateRelative) -IssueId $candidateIssueId -IssueStatus planned -TaskId 'COMPAT-006' -Summary $summary -CloseCondition $closeCondition -EvidencePath $registrationEvidence | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update for 011 failed.' }

$refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Derived governance document refresh failed.' }

[pscustomobject][ordered]@{
  status = 'candidate_gate_ready'
  activeIssueId = $activeIssueId
  preparedCandidateIssueId = $candidateIssueId
  targetEvidencePath = $TargetEvidencePath
  affectedSourceCount = [int]$affected.affectedSourceCount
  affectedRuleOccurrenceCount = [int]$affected.affectedRuleOccurrenceCount
  missingEvidence = @()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
