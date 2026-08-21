[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreTransitionEvidencePath = 'tools/legado-compat/evidence/r3-image-012-to-rule-232-pre-transition-20260808/transition-consistency.json',
  [string]$PostTransitionEvidencePath = 'tools/legado-compat/evidence/r3-image-012-to-rule-232-post-transition-20260808/transition-consistency.json',
  [string]$NextIssueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictJson {
  param([string]$Path)
  $fullPath = Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "required JSON is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($fullPath)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) } catch { throw "invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) { if ([string]$issue.id -eq $Id) { return $issue } }
  return $null
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "012 to 232 registration blocked: $Message" }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
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
Assert-Transition ([string]$preEvidence.status -eq 'passed' -and [string]$preEvidence.transition.fromIssue -eq 'ISSUE-COMPAT-012' -and [string]$preEvidence.transition.toIssue -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -and -not [bool]$preEvidence.semanticMatchAllowed -and @($preEvidence.runtimeActionsPerformed).Count -eq 0) 'pre-transition gate is not a passed static-only 012 to 232 gate.'

$issues = @($state.governance.issues)
$issue012 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-012'
$issue232 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
Assert-Transition ($null -ne $issue012 -and [string]$issue012.status -eq 'verifying') '012 must remain verifying.'
Assert-Transition ($null -ne $issue232 -and [string]$issue232.status -eq 'verifying') '232 must remain verifying.'
$beforeRegistration = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-012'
$afterRegistration = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
Assert-Transition ($beforeRegistration -or $afterRegistration) 'machine queue is neither the expected pre- nor post-transition state.'
if ($beforeRegistration) {
  Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-012' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-012') 'objective is not on 012 before registration.'
  Assert-Transition (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') '232 is not the pre-transition candidate.'
} else {
  Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'objective is not on 232 after partial registration.'
}

if ($beforeRegistration) {
  $objective.authority | Add-Member -NotePropertyName 'activeIssueId' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -Force
  $objective.authority | Add-Member -NotePropertyName 'activeIssueSelection' -NotePropertyValue 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR is now the sole active source-closure issue after the passed 012 to 232 static transition gate. ISSUE-COMPAT-012 remains verifying for deferred R4. ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.' -Force
  $objective.objective | Add-Member -NotePropertyName 'activeIssue' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -Force
  $objective.objective | Add-Member -NotePropertyName 'activeIssueRule' -NotePropertyValue 'R2/R3 源码队列已从 ISSUE-COMPAT-012 原子切换到 ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR。当前治理首个顶层组合符语义：固定 V2 HEAD 的 %%,||,&& 优先级失败合同已保留；Analyzer、标准/Native JSVM 与 ArkWeb runtime 的 current-head 静态审计和 10+12 项合同通过，但 R4 运行时与 Legado 差分仍延期。' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'currentAnchor' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectedIssue' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateIssues' -NotePropertyValue @($NextIssueId) -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'postTransitionEvidencePath' -NotePropertyValue $PostTransitionEvidencePath -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectionRule' -NotePropertyValue 'Prior verifying issues remain deferred to R4. 232 is selected only because its historical failure contract, source fix, 10+12 static contracts, current-head audit, frozen impact claim and 012→232 transition gate are registered. ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION is the next candidate and must be selected through its own failure-contract gate. No second root cause is activated in parallel.' -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'currentIssue' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'nextIssues' -NotePropertyValue @($NextIssueId) -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'statement' -NotePropertyValue '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。232 已通过 012→232 静态队列转移门禁，现为唯一活动源码议题；233 是下一候选。所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。' -Force
  $objective.continuationTarget | Add-Member -NotePropertyName 'activeBoundary' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR 保持 verifying：固定 V2 HEAD 的五个组合符失败反例、源码修复、10+12 项静态合同、40 项 current-head 审计和 012→232 转移证据均已登记；012 与 232 的静态证据均不代表运行时兼容，R4 仍延期。' -Force
  $objective.continuationTarget | Add-Member -NotePropertyName 'nextTransition' -NotePropertyValue '012→232 队列转移一致性门禁已通过并将 post transition path 绑定到 232；下一候选为 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION。新议题必须先固定失败合同，再跨 Analyzer、Rule IR/Matcher、ArkWeb、JSVM 和输出路径修复。' -Force
  $objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR 已通过 012→232 静态转移前置门禁；注册活动锚点并原子绑定 post-transition evidence。随后以 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION 为下一候选，先做事实核对和失败合同，不启动 R4。' -Force
  Write-AtomicJson -Path $objectivePath -Value $objective
  $setObjectiveScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
  & $setObjectiveScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' | Out-Null
  if (-not $?) { throw 'Set-LegadoRefactorObjective failed.' }
}

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$evidence = @(
  $PreTransitionEvidencePath,
  $PostTransitionEvidencePath,
  'tools/legado-compat/evidence/contract-legado-rule-composition-pre-fix-20260808.json',
  'tools/legado-compat/evidence/v2-rule-composition-first-operator-source-fix-20260807.json',
  'tools/legado-compat/evidence/v2-rule-composition-current-head-audit-20260808-r1.json',
  'tools/legado-compat/evidence/contract-legado-rule-composition-mixed.json',
  'tools/legado-compat/evidence/legado-rule-composition-embedded-runtime-contract-20260807.json'
)
$evidenceArgument = ($evidence -join ',')
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '232 已通过 012→232 专用静态转移门禁接管为唯一活动源码议题；固定 V2 HEAD 五个失败反例、10+12 项静态合同、40 项 current-head 审计和源码哈希均已登记。233 为下一候选，R4 运行时与 Legado 差分延期。' -EvidencePath $evidenceArgument -IncrementAttempt | Out-Null
if (-not $?) { throw 'Update-LegadoGovernanceState failed.' }

[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_rule_232_transition_registration'
  status = 'registered'
  issueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
  previousIssueId = 'ISSUE-COMPAT-012'
  nextIssueId = $NextIssueId
  preTransitionEvidencePath = $PreTransitionEvidencePath
  postTransitionEvidencePath = $PostTransitionEvidencePath
  baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
} | ConvertTo-Json -Depth 12
