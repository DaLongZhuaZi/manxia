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

$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$activeIssue = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$sourceCount = 458
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing JSON file: $RelativePath"
  }
  $text = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path))
  if ($text.IndexOf([char]0) -ge 0 -or $text.IndexOf([char]9) -ge 0 -or $text.IndexOf([char]11) -ge 0) {
    throw "Control character found in JSON: $RelativePath"
  }
  return $text | ConvertFrom-Json
}

function Set-PropertyValue {
  param(
    [object]$Object,
    [string]$Name,
    [object]$Value
  )
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $property.Value = $Value
  }
}

function Write-AtomicJson {
  param(
    [string]$RelativePath,
    [object]$Value
  )
  $path = Get-RepoPath $RelativePath
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    $json = $Value | ConvertTo-Json -Depth 60
    [System.IO.File]::WriteAllText($temporaryPath, $json, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Write-AtomicText {
  param(
    [string]$RelativePath,
    [string]$Value
  )
  $path = Get-RepoPath $RelativePath
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Replace-Section {
  param(
    [string]$Text,
    [string]$StartMarker,
    [string]$EndMarker,
    [string]$Replacement
  )
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if (-not [regex]::IsMatch($Text, $pattern)) {
    throw "Document section marker missing: $StartMarker"
  }
  return [regex]::Replace($Text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
}

$state = Read-StrictJson -RelativePath $stateRelative
$objective = Read-StrictJson -RelativePath $objectiveRelative
$baseline = $state.baseline
$objectiveBaseline = $objective.baseline
if ([int]$baseline.sourceCount -ne $sourceCount -or
    [string]$baseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$baseline.legadoCommit -ne $legadoCommit -or
    [int]$objectiveBaseline.sourceCount -ne $sourceCount -or
    [string]$objectiveBaseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$objectiveBaseline.legadoCommit -ne $legadoCommit) {
  throw 'Frozen source or Legado baseline drifted; target selection is blocked.'
}

$governance = $state.governance
if ([string]$governance.activeTaskId -ne 'COMPAT-006' -or
    [string]$governance.activeIssueId -ne $activeIssue -or
    [string]$governance.status -ne 'running') {
  throw 'Machine governance is not running on the required S2T issue.'
}
$issue = @($governance.issues | Where-Object { [string]$_.id -eq $activeIssue }) | Select-Object -First 1
if ($null -eq $issue -or [string]$issue.status -ne 'in_progress') {
  throw 'S2T issue is missing or is not in_progress.'
}

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'targetRevision' $targetRevision
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'continuationMode' 'R3_JS_API_S2T_DEFAULT_RUNTIME_SOURCE_FIX'
Set-PropertyValue $objective.authority 'activeIssueId' $activeIssue
Set-PropertyValue $objective.authority 'activeIssueSelection' 'The machine fact queue selects exactly one source-closure issue. S2T is the only in-progress issue; 037 and earlier static closures remain verifying for R4 and cannot be reopened in parallel.'

Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-JS-API-S2T-DEFAULT-RUNTIME'
Set-PropertyValue $objective.objective 'activeIssue' $activeIssue
Set-PropertyValue $objective.objective 'statement' '在固定 458 条书源、源包哈希和 Legado 提交下，持续完成 V2 兼容层的源码级根因治理。当前只推进 java.s2t 默认 ArkWeb runtime 缺口：保留失败见证，完成默认 runtime 与 capability registry 的语义修复，随后生成静态 post-fix/source-fix/current-head/文档一致性证据。静态闭合只允许保持 verifying；R4 运行时、458 条 Harness、Legado 差分、构建、安装和真机验证仍由用户单独开启。'
Set-PropertyValue $objective.objective 'activeIssueRule' 'S2T is the sole active root-cause issue. Do not add a second issue until the post-fix static contract, current-head audit, evidence binding and document consistency checks are complete.'

$queueGate = $objective.objective.queueSelectionGate
Set-PropertyValue $queueGate 'status' 'issue_selected_r3_jsapi_s2t_default_runtime_source_fix'
Set-PropertyValue $queueGate 'currentAnchor' $activeIssue
Set-PropertyValue $queueGate 'selectedIssue' $activeIssue
Set-PropertyValue $queueGate 'candidateStatus' 'active_in_progress'
Set-PropertyValue $queueGate 'selectionRule' 'The queue is selected only from full-source-validation-state.json. S2T remains the sole active source-closure issue until its static source-fix contract and consistency audit pass; all prior static closures remain verifying for R4. No runtime result, old executor fallback or issue status name may select a second root cause.'
Set-PropertyValue $queueGate 'evidencePath' 'tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json'

$execution = $objective.executionTarget
Set-PropertyValue $execution 'currentIssue' $activeIssue
Set-PropertyValue $execution 'nextIssues' @()
Set-PropertyValue $execution 'statement' '在固定基线下完成默认 ArkWeb java.s2t 的源码修复和静态证据闭环；静态证据不得写成 passed 或 semantic_match，R4 运行时、原版差分、构建、安装和真机验证保持延期。'
Set-PropertyValue $execution 'allowedActions' @(
  '读取固定 Legado JsExtensions.kt、受影响书源规则和 V2 Analyzer/Rule IR/JSVM/ArkWeb/工作流/输出消费者',
  '保留并检查 java.s2t 失败 fixture/失败前合同',
  '修改默认 legado_runtime.html 的 java.s2t 和 LegadoJsApiContractRegistry.ets 的能力登记',
  '执行静态 post-fix contract、PowerShell 语法、JSON/UTF-8、源码哈希和证据隔离检查',
  '生成脱敏 source-fix evidence 并原子刷新治理状态和全部文档'
)
Set-PropertyValue $execution 'forbiddenActions' @(
  '运行 458 条运行时批次、真实网络端点或 Legado 运行时差分',
  '构建、签名、安装、控制 Android/HarmonyOS 设备或启动 R4 回归',
  '通过 Native JSVM shim、NovelSourceExecutor、缓存、空结果或未执行流程掩盖默认 ArkWeb 差异',
  '将静态合同通过写成 passed 或 semantic_match'
)
Set-PropertyValue $execution 'issueProtocol' @(
  '先读取固定 Legado 实现、4 条受影响 Search 书源和六层 V2 消费者路径',
  '保留失败前证据；修复必须覆盖默认 runtime 与 capability registry，不能只改调用方',
  '静态合同失败或发现第二主因时立即停止，保留现场并登记唯一新治理议题',
  '静态闭合后原子登记 source-fix、post-fix contract、current-head 和文档一致性；队列转移必须另有独立五项门禁',
  '任何新证据绑定同一 frozen baseline 和 run scope，不覆盖 canonical baseline evidence'
)
Set-PropertyValue $execution 'exitCriteria' @(
  '默认 legado_runtime.html 的 java.s2t 按冻结 Legado ChineseUtils.s2t 边界可静态定位，且 registry 状态与默认路径一致',
  '失败前证据保持 status=failed；post-fix contract、source-fix evidence、current-head 哈希和证据隔离均通过',
  '目标、机器队列、治理镜像、推进台账、证据索引、差分摘要和调查报告执行区块一致',
  'S2T 仍保持 verifying/in_progress，semanticMatchAllowed=false，并明确保留 R4 统一验证入口'
)

$continuation = $objective.continuationTarget
Set-PropertyValue $continuation 'activeBoundary' 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME 保持 in_progress：默认 ArkWeb legado_runtime.html 缺少 java.s2t；当前目标是完成默认 runtime 与 registry 的源码修复及静态证据闭环，037 与其它静态议题保持 verifying 等待 R4。'
Set-PropertyValue $continuation 'nextTransition' 'S2T-04：完成默认 ArkWeb runtime 与 registry 源码修复；S2T-05：运行 post-fix static contract、current-head 哈希和文档一致性检查；通过后保持 verifying，R4 deferred。'
$queueAudit = $continuation.queueAudit
Set-PropertyValue $queueAudit 'candidateIssueId' $activeIssue
Set-PropertyValue $queueAudit 'candidateGateStatus' 'activated_in_progress'
Set-PropertyValue $queueAudit 'nextRequired' '完成 S2T-04 默认 ArkWeb runtime/registry 源码修复和 S2T-05 静态 post-fix contract；完成前不得叠加第二根因。'
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json'
Set-PropertyValue $queueAudit 'failureWitnessPath' 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
Set-PropertyValue $queueAudit 'currentHeadEvidencePath' 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809.json'
Set-PropertyValue $queueAudit 'priorActiveIssueId' 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
Set-PropertyValue $queueAudit 'priorTransitionEvidencePath' 'tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/transition-consistency.json'

Set-PropertyValue $objective 'nextAction' '执行 S2T-04：保留失败见证后完成默认 ArkWeb legado_runtime.html 的 java.s2t 与 capability registry 源码修复；随后执行 S2T-05 静态 post-fix contract，R4 仍 deferred。'
$completionGate = @($objective.completionGate | ForEach-Object {
  $value = [string]$_
  if ($value.Contains('COMPAT-006 的父任务、R3-QUEUE-PREFLIGHT、当前 activeIssue 锚点')) {
    'COMPAT-006 父任务、当前 S2T activeIssue、候选队列、阶段状态和证据索引在同一次原子刷新后保持一致。'
  } elseif ($value.Contains('active 037 锚点')) {
    'S2T activeIssue、JS API 44/140 静态结算、失败见证和目标合同必须绑定同一固定基线；未完成前不得选择第二根因。'
  } else {
    $value
  }
})
Set-PropertyValue $objective 'completionGate' $completionGate

Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

$setScript = Get-RepoPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript `
  -StatePath (Get-RepoPath $stateRelative) `
  -ObjectivePath (Get-RepoPath $objectiveRelative) `
  -ActiveIssueId $activeIssue | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Set-LegadoRefactorObjective.ps1 failed.'
}

$refreshCompatibility = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshCompatibility -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Compatibility document refresh failed.'
}

$documentPaths = @(
  'docs/analysis/Legado书源V2源码重构持续目标.md',
  'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
)
foreach ($relativePath in $documentPaths) {
  $path = Get-RepoPath $relativePath
  $text = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path))
  # A failed earlier interpolation could turn `f, `t or `v into control bytes.
  $normalized = $text.Replace(([string][char]12), 'f').Replace(([string][char]9), 't').Replace(([string][char]11), 'v')
  if ($normalized -ne $text) {
    Write-AtomicText -RelativePath $relativePath -Value $normalized
  }
}

$refreshS2t = Get-RepoPath 'tools/legado-compat/Refresh-LegadoJsApiS2tObjectiveDocuments.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refreshS2t -RepositoryRoot $RepositoryRoot | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'S2T objective document refresh failed.'
}

$objectiveDocRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocPath = Get-RepoPath $objectiveDocRelative
$objectiveDoc = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($objectiveDocPath))
$currentObjectiveSection = @"
## 当前修订

目标 ID：LEGADO-V2-SOURCE-CLOSURE-R3-20260808  
当前修订：$targetRevision  
父任务：COMPAT-006  
工作流：R3-JS-API-S2T-DEFAULT-RUNTIME-SOURCE-FIX

当前唯一活动源码议题为 $activeIssue，状态为 in_progress。037、238、237、236、235 及其它历史源码闭合议题均保持 verifying，只等待 R4，不重新打开或并行打补丁。

## 下一持续执行目标

在不改变固定基线的前提下完成 S2T-04 和 S2T-05：保留 java.s2t 失败见证，确认默认 ArkWeb legado_runtime.html 的 java.s2t 与 LegadoJsApiContractRegistry.ets 登记一致，生成 source-fix、post-fix static contract、current-head 哈希和文档一致性证据。源码闭合后只能保持 verifying；不得启动 458 条运行时批次、真实网络、Legado 差分、构建、安装或设备验证，R4 仍由用户单独开启。

"@
$objectiveDoc = Replace-Section -Text $objectiveDoc -StartMarker '## 当前修订' -EndMarker '## 持续目标' -Replacement $currentObjectiveSection
Write-AtomicText -RelativePath $objectiveDocRelative -Value $objectiveDoc

$governanceDocRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$governanceDocPath = Get-RepoPath $governanceDocRelative
$governanceDoc = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($governanceDocPath))
$currentGovernanceSection = @"
## 当前执行目标（2026-08-09）

机器事实 full-source-validation-state.json 的固定基线未漂移：458 条书源、SHA-256 $sourceHash、Legado $legadoCommit。当前唯一活动源码议题为 $activeIssue（in_progress）；037 及其它静态闭合议题保持 verifying，R4 运行时、原版差分、构建、安装和设备继续延期。

当前只允许：保留失败见证 -> 修复默认 ArkWeb java.s2t -> 保持 registry 与默认 runtime 一致 -> 运行静态 post-fix contract、current-head 哈希和证据隔离检查 -> 原子刷新台账。不得使用 Native shim、旧执行器、缓存、空结果或未执行流程掩盖差异，也不得并行选择第二根因。

前置队列审计 tools/legado-compat/evidence/r3-source-queue-preflight-20260809/current-objective-preflight.json 作为历史候选筛选证据保留；它不能覆盖当前 S2T 活动锚点。

"@
$governanceStartMarker = if ($governanceDoc.Contains('## 当前执行目标（2026-08-09）')) {
  '## 当前执行目标（2026-08-09）'
} else {
  '## R3 当前目标队列前置审计（2026-08-09）'
}
$governanceDoc = Replace-Section -Text $governanceDoc -StartMarker $governanceStartMarker -EndMarker '## R3 JS API 能力结算与 S2T 源码修复目标（2026-08-09）' -Replacement $currentGovernanceSection
Write-AtomicText -RelativePath $governanceDocRelative -Value $governanceDoc

foreach ($relativePath in @($objectiveDocRelative, $governanceDocRelative)) {
  $text = $utf8Strict.GetString([System.IO.File]::ReadAllBytes((Get-RepoPath $relativePath)))
  if ($text.IndexOf([char]0) -ge 0 -or $text.IndexOf([char]9) -ge 0 -or $text.IndexOf([char]11) -ge 0) {
    throw "Control character found after target refresh: $relativePath"
  }
}

Write-Output (ConvertTo-Json -Depth 12 -InputObject ([pscustomobject][ordered]@{
  status = 'target_set'
  objectiveId = [string]$objective.objectiveId
  targetRevision = $targetRevision
  activeIssueId = $activeIssue
  nextAction = [string]$objective.nextAction
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  documents = @(
    $objectiveRelative,
    'tools/legado-compat/state/full-source-validation-state.json',
    'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md',
    $objectiveDocRelative,
    'docs/analysis/Legado书源引擎兼容推进台账.md',
    'docs/analysis/Legado书源引擎证据索引.md',
    'docs/analysis/Legado书源引擎差分摘要.md'
  )
}))
