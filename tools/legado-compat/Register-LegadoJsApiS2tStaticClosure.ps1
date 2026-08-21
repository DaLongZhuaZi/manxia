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
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$contractRelative = 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-20260809.json'
$sourceFixRelative = 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json'
$currentHeadRelative = 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809-r1/current-head-hash-audit.json'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
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
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Replace-Section {
  param([string]$Text, [string]$StartMarker, [string]$EndMarker, [string]$Replacement)
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if (-not [regex]::IsMatch($Text, $pattern)) { throw "Document section marker missing: $StartMarker" }
  return [regex]::Replace($Text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
}

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
$contract = Read-StrictJson $contractRelative
$sourceFix = Read-StrictJson $sourceFixRelative
$currentHead = Read-StrictJson $currentHeadRelative

if ([string]$state.governance.activeTaskId -ne 'COMPAT-006' -or
    [string]$state.governance.activeIssueId -ne $issueId -or
    [string]$state.governance.status -ne 'running') {
  throw 'S2T is not the sole active machine issue.'
}
if ([string]$objective.authority.activeIssueId -ne $issueId -or [string]$objective.executionTarget.currentIssue -ne $issueId) {
  throw 'Objective is not bound to S2T.'
}
foreach ($evidence in @($contract, $sourceFix, $currentHead)) {
  if ([string]$evidence.status -ne 'passed_static_only' -or [bool]$evidence.semanticMatchAllowed -or @($evidence.runtimeActionsPerformed).Count -ne 0) {
    throw 'S2T post-fix evidence is not a static-only pass.'
  }
  if ([string]$evidence.targetRevision -ne $targetRevision) { throw 'S2T evidence target revision drifted.' }
  if ([int]$evidence.baseline.sourceCount -ne 458 -or [string]$evidence.baseline.sourcePackageSha256 -ne '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -or [string]$evidence.baseline.legadoCommit -ne '95973d186b147fb9ab43a9240021d688e4304fbd') {
    throw 'S2T evidence baseline drifted.'
  }
}
$failureWitness = Read-StrictJson 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
if ([string]$failureWitness.status -ne 'failed' -or [bool]$failureWitness.semanticMatchAllowed -or @($failureWitness.runtimeActionsPerformed).Count -ne 0) {
  throw 'Pre-fix failure witness was overwritten or is no longer static-only.'
}

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'continuationMode' 'R3_JS_API_S2T_DEFAULT_RUNTIME_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective 'nextAction' 'S2T 静态源码闭合已登记，保持 verifying；下一源码议题必须重新通过五项证据门禁，R4 运行时、458 条 Harness、Legado 差分、构建、安装和真机验证仍 deferred。'
Set-PropertyValue $objective.objective 'statement' '在固定 458 条书源与 Legado 提交下维护 V2 源码级语义闭环。S2T 的默认 ArkWeb java.s2t 源码修复、registry 登记、失败前证据保留、post-fix contract、source-fix 和 current-head 静态审计均已完成；该议题保持 verifying，不能写成 passed 或 semantic_match。下一源码议题只能经独立五项证据门禁选择，R4 统一运行时验证仍由用户单独开启。'
Set-PropertyValue $objective.objective 'activeIssueRule' 'S2T static closure is complete and remains verifying. Do not reopen it or select a second root cause until the next candidate independently passes the five-item evidence gate; R4 is the only runtime closure gate.'
Set-PropertyValue $objective.executionTarget 'statement' 'S2T 源码静态闭合已完成并已登记 source-fix、post-fix contract、current-head 和文档一致性证据；保持 verifying，禁止把静态证据提升为 passed 或 semantic_match。下一源码议题必须重新通过五项证据门禁，R4 运行时、Legado 差分、构建、安装和真机继续延期。'
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.executionTarget 'allowedActions' @(
  '读取 full-source-validation-state.json、固定 Legado 实现、历史失败证据和当前队列候选',
  '对下一候选执行固定 Legado 语义、影响集合、失败见证、V2 消费者矩阵和关闭条件五项静态门禁',
  '生成脱敏静态证据并原子刷新治理状态、推进台账、证据索引、差分摘要和调查报告执行区块'
)
Set-PropertyValue $objective.executionTarget 'issueProtocol' @(
  'S2T 失败见证、源码修复和静态证据保持不可覆盖；当前议题只等待 R4，不再追加补丁',
  '下一源码议题必须先有固定 Legado 实现、受影响集合、可复现失败合同、V2 全部消费者和关闭条件',
  '证据不足、状态漂移或发现第二主因时保持当前队列并登记阻断，不凭状态名称选题',
  '所有静态证据绑定 frozen baseline；不得启动运行时、网络、构建、安装、设备或 Legado 差分'
)
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME 的源码静态闭合已完成，状态保持 verifying；失败见证、post-fix contract、source-fix、current-head 和文档证据均已绑定固定基线，037 与其它静态议题继续等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' 'S2T-05 已完成；下一动作只能做下一候选的五项静态证据门禁或由用户开启 R4，不能在未选题前追加源码补丁。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'candidateGateStatus' 'static_closed_verifying'
Set-PropertyValue $queueAudit 'nextRequired' '只读核对下一候选；候选必须具备固定 Legado 语义、影响集合、失败见证、V2 消费者矩阵和关闭条件，R4 仍 deferred。'
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' $sourceFixRelative
Set-PropertyValue $queueAudit 'postFixContractEvidencePath' $contractRelative
Set-PropertyValue $queueAudit 'currentHeadEvidencePath' $currentHeadRelative

foreach ($planId in @('JSAPI-SETTLE-05', 'S2T-04', 'S2T-05')) {
  $planItem = @($objective.continuationPlan | Where-Object { [string]$_.id -eq $planId }) | Select-Object -First 1
  if ($null -eq $planItem) { throw "Missing objective plan item: $planId" }
  Set-PropertyValue $planItem 'status' 'completed'
  Set-PropertyValue $planItem 'completedEvidence' $sourceFixRelative
}
$s2t06 = @($objective.continuationPlan | Where-Object { [string]$_.id -eq 'S2T-06' }) | Select-Object -First 1
if ($null -ne $s2t06) { Set-PropertyValue $s2t06 'status' 'deferred' }
Set-PropertyValue $objective.objective 'latestStaticClosure' 'java.s2t 默认 ArkWeb runtime 缺口已完成源码修复、registry 登记、29 项静态 post-fix contract、source-fix 和 current-head 哈希审计；失败前 evidence 保持 failed，S2T 保持 verifying，R4 运行时与 Legado 差分仍延期。'

Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

$setScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Refactor objective attachment failed.' }

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = 'java.s2t 默认 ArkWeb 源码闭合：默认 runtime 与 registry 已静态一致，29 项 post-fix contract、source-fix、current-head 哈希和失败证据保留通过；议题保持 verifying，R4 运行时/Legado 差分/构建/设备延期。'
$closeCondition = 'R4 must still execute the affected four sources and the agreed runtime/Legado differential before this issue can be passed or semantic_match.'
$evidencePaths = @(
  'tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json',
  'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json',
  $contractRelative,
  $sourceFixRelative,
  $currentHeadRelative
)
$evidenceArgument = $evidencePaths -join ','
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $stateRelative) -IssueId $issueId -IssueStatus verifying -TaskId 'COMPAT-006' -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidenceArgument | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state refresh failed.' }

$refreshS2t = Get-RepoPath 'tools/legado-compat/Refresh-LegadoJsApiS2tObjectiveDocuments.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshS2t -RepositoryRoot $RepositoryRoot | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'S2T objective document refresh failed.' }

$objectiveDocumentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocumentPath = Get-RepoPath $objectiveDocumentRelative
$objectiveDocument = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($objectiveDocumentPath))
$objectiveCurrentSection = @"
## 当前修订

目标 ID：LEGADO-V2-SOURCE-CLOSURE-R3-20260808  
当前修订：$targetRevision  
父任务：COMPAT-006  
工作流：R3-JS-API-S2T-DEFAULT-RUNTIME-STATIC-CLOSED-WAIT-R4

当前唯一活动源码议题为 $issueId，状态为 verifying。S2T 默认 ArkWeb runtime、registry 和静态证据链已闭合；037、238、237、236、235 及其它历史源码闭合议题均保持 verifying，只等待 R4，不重新打开或并行打补丁。

本文件后续保留的 037、238、237、236、235 等队列段落是历史证据记录，不代表当前活动队列；当前活动议题和状态只以 full-source-validation-state.json 为准。

## 下一持续执行目标

保持 S2T 的失败前证据、post-fix contract、source-fix、current-head 哈希和文档一致性绑定；下一源码议题只能重新通过固定 Legado 语义、影响集合、失败见证、V2 消费者矩阵和关闭条件五项门禁。不得启动 458 条运行时批次、真实网络、Legado 差分、构建、安装或设备验证，R4 仍由用户单独开启。

"@
$objectiveDocument = Replace-Section -Text $objectiveDocument -StartMarker '## 当前修订' -EndMarker '## 持续目标' -Replacement $objectiveCurrentSection
Write-AtomicText -RelativePath $objectiveDocumentRelative -Value $objectiveDocument

$governanceDocumentRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$governanceDocumentPath = Get-RepoPath $governanceDocumentRelative
$governanceDocument = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($governanceDocumentPath))
$governanceCurrentSection = @"
## 当前执行目标（2026-08-09）

机器事实 full-source-validation-state.json 的固定基线未漂移：458 条书源、SHA-256 473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67、Legado 95973d186b147fb9ab43a9240021d688e4304fbd。当前唯一活动源码议题为 $issueId（verifying）；S2T 静态源码闭合已登记，037 及其它静态闭合议题继续等待 R4。

本文件后续保留的历史队列段落只用于追溯证据，不代表当前活动队列；当前活动议题和状态只以 full-source-validation-state.json 为准。

当前只允许保留失败证据、静态 source-fix/post-fix/current-head 证据和队列门禁；禁止 Native shim、旧执行器、空结果伪通过、458 条运行时批次、真实网络、构建、安装和设备操作。下一议题必须独立通过五项证据门禁。

"@
$governanceStartMarker = if ($governanceDocument.Contains('## 当前执行目标（2026-08-09）')) { '## 当前执行目标（2026-08-09）' } else { '## R3 当前目标队列前置审计（2026-08-09）' }
$governanceDocument = Replace-Section -Text $governanceDocument -StartMarker $governanceStartMarker -EndMarker '## R3 JS API 能力结算与 S2T 源码修复目标（2026-08-09）' -Replacement $governanceCurrentSection
Write-AtomicText -RelativePath $governanceDocumentRelative -Value $governanceDocument

$refreshedState = Read-StrictJson $stateRelative
$refreshedObjective = Read-StrictJson $objectiveRelative
$refreshedIssue = @($refreshedState.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ([string]$refreshedState.governance.activeIssueId -ne $issueId -or [string]$refreshedIssue.status -ne 'verifying') { throw 'S2T did not remain the active verifying issue.' }
if ([string]$refreshedObjective.continuationMode -ne 'R3_JS_API_S2T_DEFAULT_RUNTIME_STATIC_CLOSED_WAIT_R4') { throw 'Objective did not enter static-closed mode.' }
if (-not [bool](@($refreshedIssue.evidencePaths) -contains $sourceFixRelative)) { throw 'Source-fix evidence was not registered.' }

[pscustomobject][ordered]@{
  status = 'static_closure_registered'
  issueId = $issueId
  issueStatus = [string]$refreshedIssue.status
  targetRevision = $targetRevision
  nextAction = [string]$refreshedObjective.nextAction
  evidence = @($contractRelative, $sourceFixRelative, $currentHeadRelative)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
