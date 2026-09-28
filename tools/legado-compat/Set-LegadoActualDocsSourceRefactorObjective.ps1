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
$objectiveDocumentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$targetRevision = '2026-08-09-actual-docs-source-refactor-url-attribute-011-source-fix-static-closed'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return $strictUtf8.GetString($bytes) | ConvertFrom-Json } catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing document: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
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
$baseline = $state.baseline
$objectiveBaseline = $objective.baseline
if ([int]$baseline.sourceCount -ne 458 -or [string]$baseline.sourcePackageSha256 -ne $sourceHash -or [string]$baseline.legadoCommit -ne $legadoCommit) { throw 'Machine baseline drifted.' }
if ([int]$objectiveBaseline.sourceCount -ne 458 -or [string]$objectiveBaseline.sourcePackageSha256 -ne $sourceHash -or [string]$objectiveBaseline.legadoCommit -ne $legadoCommit) { throw 'Objective baseline drifted.' }
if ([string]$state.governance.activeTaskId -ne 'COMPAT-006' -or [string]$state.governance.activeIssueId -ne 'ISSUE-COMPAT-011' -or [string]$state.governance.status -ne 'running') { throw 'Machine queue is not anchored to COMPAT-006 / ISSUE-COMPAT-011.' }
$queue = $state.governance.queuePreflight
if ([int]$queue.evaluatedCount -ne 226 -or [int]$queue.candidateCount -ne 0 -or [string]$queue.activeIssueId -ne 'ISSUE-COMPAT-011' -or [string]$queue.candidateGateStatus -ne 'no_candidate_satisfies_evidence_gate') { throw 'Queue preflight is not the current 226/0 no-candidate fact.' }
$auto044 = @($state.governance.issues | Where-Object { [string]$_.id -eq 'ISSUE-AUTO-044-EVIDENCE-READER-UTF8' }) | Select-Object -First 1
if ($null -eq $auto044 -or [string]$auto044.status -ne 'passed') { throw 'AUTO-044 static evidence-reader issue is not passed.' }

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $targetRevision
Set-PropertyValue $objective 'nextAction' '当前队列无合格候选；继续为一个下一候选补齐五项静态证据，保持 ISSUE-COMPAT-011 verifying，不启动 R4。'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-STATIC-SOURCE-REFACTOR-QUEUE-GATE-044-WAIT-R4'
Set-PropertyValue $objective.objective 'statement' '在固定 458 条书源、源包哈希和 Legado 提交下持续完成 V2 源码级语义闭环。当前唯一活动源码议题为 ISSUE-COMPAT-011，属性列表投影源码修复已静态闭合；静态候选门禁已评估 226 个 P0/P1 条目且无合格候选，AUTO-044 证据读取器静态合同已通过。下一步只允许补齐下一候选的五项证据并原子选择，不重新打开历史议题，不把静态证据写成运行时兼容。'
Set-PropertyValue $objective.objective 'activeIssueRule' 'ISSUE-COMPAT-011 保持 verifying；没有候选同时满足固定 Legado 语义、458 条影响集合、失败见证、V2 全部消费者矩阵和关闭条件时，不得选择第二根因。'
Set-PropertyValue $objective.executionTarget 'statement' '在固定基线下维护 ISSUE-COMPAT-011 的静态闭合结果，并继续执行单议题证据门禁与 Harness 证据治理；AUTO-044 已解决 BOM/二进制证据读取误报。R4 运行时、Legado 差分、构建、安装和设备验证保持延期。'
Set-PropertyValue $objective.executionTarget 'currentIssue' 'ISSUE-COMPAT-011'
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.executionTarget 'allowedActions' @(
  '读取固定 Legado 实现、冻结书源规则和 V2 Analyzer/Rule IR/Matcher/ArkWeb/JSVM/工作流/输出路径',
  '运行 current-static-source-candidate gate、AUTO-044 evidence-reader static contract 和 ISSUE-COMPAT-011 document-consistency contract',
  '为下一候选补齐固定语义位置、受影响集合、失败见证、V2 消费者矩阵和关闭条件，未通过五项门禁不得选择',
  '执行 PowerShell 语法、JSON/UTF-8/哈希和证据写出隔离检查，并原子刷新机器状态与全部派生文档'
)
Set-PropertyValue $objective.executionTarget 'forbiddenActions' @(
  '运行 458 条运行时批次、真实网络端点或 Legado 运行时差分',
  '构建、签名、安装、控制 Android/HarmonyOS 设备或启动 R4 回归',
  '通过旧 NovelSourceExecutor、缓存、空结果或未执行流程掩盖 V2 差异',
  '把静态证据写成 passed 或 semantic_match，或在无合格候选时选择第二根因'
)
Set-PropertyValue $objective.executionTarget 'exitCriteria' @(
  'full-source-validation-state.json 的 queuePreflight 与最新 current-static-source-candidate evidence 一致，且绑定 458 条、源包 SHA-256 和 Legado commit',
  'AUTO-044 evidence-reader static contract 通过；BOM 文本和二进制证据不再被错误记录为 unreadable_evidence_file',
  'ISSUE-COMPAT-011 保持 verifying，semanticMatchAllowed=false；没有合格候选时不得改变 activeIssueId',
  '目标、治理镜像、推进台账、证据索引、差分摘要和调查报告执行区块一致',
  'R4 运行时、458 条 Harness、Legado 差分、构建、安装和真机验证入口明确保留但继续延期'
)
Set-PropertyValue $objective.executionTarget 'evidenceReader' ([ordered]@{
  issueId = 'ISSUE-AUTO-044-EVIDENCE-READER-UTF8'
  status = 'passed_static_only'
  evidencePath = 'tools/legado-compat/evidence/contract-legado-current-static-candidate-evidence-reader-20260809.json'
  failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-current-static-candidate-evidence-reader-pre-fix-20260809.json'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
})
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-011 保持 verifying；属性列表值级去重源码修复已静态闭合，当前队列 226 个 P0/P1 条目无合格候选；AUTO-044 证据读取器已静态修复并登记。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '先为一个下一候选补齐五项静态证据并通过 current-static-source-candidate 门禁；通过后原子选择一个议题，否则保持 011 verifying。R4 继续 deferred。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'evidenceReaderIssueId' 'ISSUE-AUTO-044-EVIDENCE-READER-UTF8'
Set-PropertyValue $queueAudit 'evidenceReaderEvidencePath' 'tools/legado-compat/evidence/contract-legado-current-static-candidate-evidence-reader-20260809.json'
Set-PropertyValue $queueAudit 'candidateGateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $queueAudit 'candidateIssues' @()
Write-AtomicJson $objectiveRelative $objective

$refresh = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $refresh -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Derived document refresh failed.' }

$objectiveDocument = Read-StrictText $objectiveDocumentRelative
$currentSection = @"
## 当前修订

目标 ID：LEGADO-V2-SOURCE-CLOSURE-R3-20260808  
当前修订：$targetRevision  
父任务：COMPAT-006  
工作流：R3-STATIC-SOURCE-REFACTOR-QUEUE-GATE-044-WAIT-R4

当前唯一活动源码议题为 ISSUE-COMPAT-011，状态为 verifying。011 的属性列表投影源码修复、失败前见证、post-fix contract、source-fix、9 个消费者 current-head 审计和文档一致性证据均已登记。静态候选门禁评估 226 个 P0/P1 条目，合格候选为 0；AUTO-044 已修复门禁对 UTF-8 BOM 文本和二进制证据的误报。历史源码议题保持 verifying，只等待 R4。

## 下一持续执行目标

在固定基线不变的前提下，持续执行单议题源码重构和证据治理：先为下一候选补齐固定 Legado 语义、458 条影响集合、可复现失败合同、V2 全部消费者矩阵和关闭条件五项证据，再原子选择一个议题；没有合格候选时保持 ISSUE-COMPAT-011 verifying，不叠加补丁。只进行源码阅读/修改、确定性 fixture、静态合同、UTF-8/JSON/哈希和文档刷新；R4 的运行时 Harness、Legado 差分、构建、安装和真机验证继续延期。

"@
$objectiveDocument = Replace-Section $objectiveDocument '## 当前修订' '## 持续目标' $currentSection
Write-AtomicText $objectiveDocumentRelative $objectiveDocument

$governanceDocumentRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$governanceDocument = Read-StrictText $governanceDocumentRelative
$governanceSection = @'
## 当前执行目标（2026-08-09）

机器事实 `full-source-validation-state.json` 的固定基线未漂移：458 条书源、SHA-256 `__SOURCE_HASH__`、Legado `__LEGADO_COMMIT__`。当前唯一活动源码议题为 ISSUE-COMPAT-011（verifying）；011 属性列表投影源码闭合已登记，AUTO-044 证据读取器静态合同已通过。

当前静态队列门禁评估 226 个 P0/P1 条目，合格候选为 0；在下一候选补齐固定 Legado 语义、受影响集合、失败见证、V2 全部消费者矩阵和关闭条件前，不选择第二根因。只允许源码阅读/修改、确定性 fixture、静态合同、UTF-8/JSON/哈希检查和原子文档刷新；R4 运行时、458 条 Harness、Legado 差分、构建、安装和设备验证继续延期。

'@
$governanceSection = $governanceSection.Replace('__SOURCE_HASH__', $sourceHash).Replace('__LEGADO_COMMIT__', $legadoCommit)
$governanceDocument = Replace-Section $governanceDocument '## 当前执行目标（2026-08-09）' '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->' $governanceSection
Write-AtomicText $governanceDocumentRelative $governanceDocument
Write-Output ('ACTUAL_DOCS_REFACTOR_OBJECTIVE_SET activeIssue=ISSUE-COMPAT-011 queue=226/0 evidenceReader=ISSUE-AUTO-044-EVIDENCE-READER-UTF8')
