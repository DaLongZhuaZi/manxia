[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreTransitionEvidencePath = 'tools/legado-compat/evidence/r3-rule-232-to-java-233-pre-transition-20260808/transition-consistency.json',
  [string]$PostTransitionEvidencePath = 'tools/legado-compat/evidence/r3-rule-232-to-java-233-post-transition-20260808/transition-consistency.json',
  [string]$NextIssueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) } catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) { if ([string]$issue.id -eq $Id) { return $issue } }
  return $null
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "232 to 233 registration blocked: $Message" }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$preEvidence = Read-StrictJson -RelativePath $PreTransitionEvidencePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$baseline = $state.baseline
Assert-Transition ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006') 'machine queue is not on COMPAT-006.'
Assert-Transition ([string]$preEvidence.status -eq 'passed' -and [string]$preEvidence.transition.fromIssue -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -and [string]$preEvidence.transition.toIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and -not [bool]$preEvidence.semanticMatchAllowed -and @($preEvidence.runtimeActionsPerformed).Count -eq 0) 'pre-transition gate is not a passed static-only 232→233 gate.'

$issues = @($state.governance.issues)
$issue232 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
$issue233 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
Assert-Transition ($null -ne $issue232 -and [string]$issue232.status -eq 'verifying') '232 must remain verifying.'
Assert-Transition ($null -ne $issue233 -and [string]$issue233.status -eq 'verifying') '233 must remain verifying.'

$beforeRegistration = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
$afterRegistration = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
Assert-Transition ($beforeRegistration -or $afterRegistration) 'machine queue is neither the expected pre- nor post-transition state.'
if ($beforeRegistration) {
  Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'objective is not on 232 before registration.'
  Assert-Transition (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') '233 is not the pre-transition candidate.'
} else {
  Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'objective is not on 233 after registration.'
}

if ($beforeRegistration) {
  $revision = '2026-08-08-actual-docs-source-refactor-continuation-java-233-026'
  $objective | Add-Member -NotePropertyName 'targetRevision' -NotePropertyValue $revision -Force
  $objective.authority | Add-Member -NotePropertyName 'activeIssueId' -NotePropertyValue 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -Force
  $objective.authority | Add-Member -NotePropertyName 'activeIssueSelection' -NotePropertyValue 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION is now the sole active source-closure issue after the passed 232 to 233 static transition gate. ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR remains verifying for deferred R4. ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.' -Force
  $objective.objective | Add-Member -NotePropertyName 'activeIssue' -NotePropertyValue 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -Force
  $objective.objective | Add-Member -NotePropertyName 'activeIssueRule' -NotePropertyValue 'R2/R3 源码队列已从 ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR 原子切换到 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION。当前治理 ArkWeb、标准 JSVM 和 Native JSVM 的 CSS &&/||/%%、@CSS、## replacement 与 Java List 形状；233 的失败前合同、源码修复和 12+19 静态合同已登记，但 R4 运行时与 Legado 差分仍延期。' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'currentAnchor' -NotePropertyValue 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectedIssue' -NotePropertyValue 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateIssues' -NotePropertyValue @($NextIssueId) -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'postTransitionEvidencePath' -NotePropertyValue $PostTransitionEvidencePath -Force
  $objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectionRule' -NotePropertyValue 'Prior verifying issues remain deferred to R4. 233 is selected only because its independent failed-before contract, source fix, 12+19 static contracts, frozen 10-source impact claim and 232→233 transition gate are registered. ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR is the next candidate and must be selected through its own failure-contract gate. No second root cause is activated in parallel.' -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'currentIssue' -NotePropertyValue 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'nextIssues' -NotePropertyValue @($NextIssueId) -Force
  $objective.executionTarget | Add-Member -NotePropertyName 'statement' -NotePropertyValue '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。233 已通过 232→233 静态队列转移门禁，现为唯一活动源码议题；234 是下一候选。所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。' -Force
  $objective.continuationTarget | Add-Member -NotePropertyName 'activeBoundary' -NotePropertyValue 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION 保持 verifying：冻结 HEAD 的 CSS/List 失败前合同、源码修复、12+19 静态合同和 232→233 转移证据均已登记；232 与 233 的静态证据均不代表运行时兼容，R4 仍延期。' -Force
  $objective.continuationTarget | Add-Member -NotePropertyName 'nextTransition' -NotePropertyValue '232→233 队列转移一致性门禁已通过并将 post transition path 绑定到 233；下一候选为 ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR。新议题必须先固定失败合同，再跨 Matcher、Rule Analyzer、ArkWeb、JSVM 和输出路径修复。' -Force
  $objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue '以 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION 为唯一活动源码议题：核对固定 Legado AnalyzeByJSoup 的 CSS/List 合同、冻结 10-source 影响集合和 V2 全部消费者，先维护失败合同，再跨 ArkWeb、标准 JSVM 与 Native JSVM 修复组合、替换和 List 投影；随后登记静态 source-fix evidence。ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR 仅作为下一候选；不启动 R4。' -Force
  Write-AtomicJson -Path $objectivePath -Value $objective
  & (Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1') -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' | Out-Null
  if (-not $?) { throw 'Set-LegadoRefactorObjective failed.' }
}

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$evidence = @(
  $PreTransitionEvidencePath,
  $PostTransitionEvidencePath,
  'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json',
  'tools/legado-compat/evidence/v2-java-string-list-css-composition-source-fix-20260807.json',
  'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition.json',
  'tools/legado-compat/evidence/legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json'
)
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '233 已通过 232→233 专用静态转移门禁接管为唯一活动源码议题；冻结 CSS/List 失败前合同、源码修复和 12+19 静态合同均已登记。234 为下一候选，R4 运行时与 Legado 差分延期。' -EvidencePath ($evidence -join ',') -IncrementAttempt | Out-Null
if (-not $?) { throw 'Update-LegadoGovernanceState failed.' }

& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '232 的首个组合符源码证据链已闭合，保持 verifying 仅等待 R4；当前唯一活动源码议题已原子转移到 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION，232 不再追加补丁或作为活动锚点。' | Out-Null
if (-not $?) { throw 'Update-LegadoGovernanceState for 232 failed.' }

[pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_java_string_list_233_transition_registration'
  status = 'registered'
  issueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  previousIssueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
  nextIssueId = $NextIssueId
  preTransitionEvidencePath = $PreTransitionEvidencePath
  postTransitionEvidencePath = $PostTransitionEvidencePath
  baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
} | ConvertTo-Json -Depth 12
