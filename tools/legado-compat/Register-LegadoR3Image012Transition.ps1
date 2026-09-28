[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreTransitionEvidencePath = '',
  [string]$PostTransitionEvidencePath = '',
  [string]$NextIssueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($PreTransitionEvidencePath)) {
  $PreTransitionEvidencePath = 'tools/legado-compat/evidence/r3-output-handoff-005-to-image-012-pre-transition-20260808/transition-consistency.json'
}
if ([string]::IsNullOrWhiteSpace($PostTransitionEvidencePath)) {
  $PostTransitionEvidencePath = 'tools/legado-compat/evidence/r3-output-handoff-005-to-image-012-post-transition-20260808/transition-consistency.json'
}

function Read-StrictJson {
  param([string]$Path)
  $fullPath = Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Required JSON is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($fullPath)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  try { return ([System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json) } catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string]$issue.id -eq $Id) { return $issue }
  }
  return $null
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "005 to 012 registration blocked: $Message" }
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
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$preEvidence = Read-StrictJson -Path $PreTransitionEvidencePath
$state = Read-StrictJson -Path 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -Path 'tools/legado-compat/state/refactor-objective.json'

$baseline = $state.baseline
Assert-Transition ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006') 'machine queue is not on COMPAT-006.'
$beforeRegistration = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-005'
$afterRegistration = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-012'
Assert-Transition ($beforeRegistration -or $afterRegistration) 'machine queue is neither the expected pre- nor post-transition state.'
if ($beforeRegistration) {
  Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-005' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-005') 'objective is not on 005 before registration.'
} else {
  Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-012' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-012') 'objective is not on 012 after partial registration.'
}
Assert-Transition ([string]$preEvidence.status -eq 'passed' -and [string]$preEvidence.transition.fromIssue -eq 'ISSUE-COMPAT-005' -and [string]$preEvidence.transition.toIssue -eq 'ISSUE-COMPAT-012' -and -not [bool]$preEvidence.semanticMatchAllowed -and @($preEvidence.runtimeActionsPerformed).Count -eq 0) 'pre-transition gate is not a passed static-only 005 to 012 gate.'

$issues = @($state.governance.issues)
$issue005 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-005'
$issue012 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-012'
Assert-Transition ($null -ne $issue005 -and [string]$issue005.status -eq 'verifying') '005 must remain verifying.'
Assert-Transition ($null -ne $issue012 -and [string]$issue012.status -eq 'verifying') '012 must remain verifying.'
$candidateIssues = @($objective.objective.queueSelectionGate.candidateIssues)
if ($beforeRegistration) {
  Assert-Transition ($candidateIssues -contains 'ISSUE-COMPAT-012') '012 is not registered as the pre-transition candidate.'
} else {
  Assert-Transition ($candidateIssues.Count -eq 1 -and $candidateIssues[0] -eq $NextIssueId) ('post-transition candidate is not the expected next issue: {0}' -f $NextIssueId)
}

if ($beforeRegistration) {
  $objective.authority | Add-Member -NotePropertyName 'activeIssueId' -NotePropertyValue 'ISSUE-COMPAT-012' -Force
  $objective.authority | Add-Member -NotePropertyName 'activeIssueSelection' -NotePropertyValue 'full-source-validation-state.json governance.issues remains the only queue; ISSUE-COMPAT-012 is now the sole active source-closure issue after the passed 005 to 012 static transition gate. ISSUE-COMPAT-005 remains verifying for deferred R4. ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.' -Force
  $objective.objective | Add-Member -NotePropertyName 'activeIssue' -NotePropertyValue 'ISSUE-COMPAT-012' -Force
  $objective.objective | Add-Member -NotePropertyName 'activeIssueRule' -NotePropertyValue 'R2/R3 源码队列已从 ISSUE-COMPAT-005 原子切换到 ISSUE-COMPAT-012。当前只处理 IMAGE Header carrier 的 fallback 语义：历史 OnlineImageLoader.ets 漂移已保留失败审计；403 fallback 现在保留 Origin、Cache-Control、Pragma、Sec-Fetch-Dest/Mode/Site、extraHeaders、forceRefresh、skipFailureTtl 和 legadoImageTrace。33 项 fallback 合同、30 项原有 carrier 合同和 7 文件 current-head 审计均通过，但仍只证明源码闭合，R4 前不得写成 passed/semantic_match。' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'currentAnchor' -NotePropertyValue 'ISSUE-COMPAT-012' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectedIssue' -NotePropertyValue 'ISSUE-COMPAT-012' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateIssues' -NotePropertyValue @($NextIssueId) -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'postTransitionEvidencePath' -NotePropertyValue $PostTransitionEvidencePath -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectionRule' -NotePropertyValue 'Prior verifying issues remain deferred to R4. ISSUE-COMPAT-012 is selected only because the 005 to 012 transition gate passed with fixed baselines, preserved historical drift, fallback failure/source-fix contracts and clean current-head audit. ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR is the next candidate and must be selected through its own failure-contract gate. No second root cause is activated in parallel.' -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'currentIssue' -NotePropertyValue 'ISSUE-COMPAT-012' -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'nextIssues' -NotePropertyValue @($NextIssueId) -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'statement' -NotePropertyValue '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。ISSUE-COMPAT-012 已通过 005→012 静态队列转移门禁，现为唯一活动源码议题；ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR 是下一候选。所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。' -Force
  $objective.continuationTarget | Add-Member -NotePropertyName 'activeBoundary' -NotePropertyValue 'ISSUE-COMPAT-012 保持 verifying：403 fallback Header carrier 的失败前/源码修复/33 项静态合同/30 项原有合同/历史漂移失败/current-head 通过证据均已登记；005 和 012 的静态证据均不代表运行时兼容，R4 仍延期。' -Force
  $objective.continuationTarget | Add-Member -NotePropertyName 'nextTransition' -NotePropertyValue '005→012 队列转移一致性门禁已通过并将 post transition path 绑定到 012；下一候选为 ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR。新议题必须先固定失败合同，再跨 Analyzer、Rule IR/Matcher、ArkWeb、JSVM 和输出路径修复。' -Force
  $objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue 'ISSUE-COMPAT-012 已通过 005→012 静态转移前置门禁；注册活动锚点并原子绑定 post-transition evidence。随后以 ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR 为下一候选，先做事实核对和失败合同，不启动 R4。' -Force
  Write-AtomicJson -Path $objectivePath -Value $objective
  $setObjectiveScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
  & $setObjectiveScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-012' | Out-Null
  if (-not $?) { throw 'Set-LegadoRefactorObjective failed.' }
}

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$evidence = @(
  $PreTransitionEvidencePath,
  $PostTransitionEvidencePath,
  'tools/legado-compat/evidence/v2-image-012-current-head-drift-audit-20260808/current-head-hash-audit.json',
  'tools/legado-compat/evidence/v2-image-012-fallback-header-source-fix-20260808-r1.json',
  'tools/legado-compat/evidence/v2-image-012-current-head-audit-20260808-r1/current-head-hash-audit.json'
)
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-012' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '012 已由 005→012 专用静态转移门禁接管为唯一活动源码议题；403 fallback Header carrier 修复及全部静态证据链保持 pending R4。下一候选为 ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR。' -EvidencePath $evidence -IncrementAttempt | Out-Null
if (-not $?) { throw 'Update-LegadoGovernanceState failed.' }

[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_image_012_transition_registration'
  status = 'registered'
  issueId = 'ISSUE-COMPAT-012'
  previousIssueId = 'ISSUE-COMPAT-005'
  nextIssueId = $NextIssueId
  preTransitionEvidencePath = $PreTransitionEvidencePath
  postTransitionEvidencePath = $PostTransitionEvidencePath
  baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
} | ConvertTo-Json -Depth 12
