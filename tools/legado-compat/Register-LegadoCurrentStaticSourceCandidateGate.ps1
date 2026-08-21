[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r3-source-queue-preflight-20260809-r2/current-static-candidate-preflight.json'
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
$governanceDocumentRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-TextValue {
  param([object]$Object, [string]$Name)
  $value = Get-PropertyValue -Object $Object -Name $Name
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$RelativePath)
  try { return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
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

function Replace-MarkedSection {
  param([string]$Document, [string]$StartMarker, [string]$EndMarker, [string]$Replacement)
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if ([regex]::IsMatch($Document, $pattern)) {
    return [regex]::Replace($Document, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
  }
  $index = $Document.IndexOf($EndMarker, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { throw "Document insertion marker missing: $EndMarker" }
  return $Document.Insert($index, $Replacement)
}

$evidence = Read-StrictJson -RelativePath $EvidencePath
$state = Read-StrictJson -RelativePath $stateRelative
$objective = Read-StrictJson -RelativePath $objectiveRelative
$baseline = Get-PropertyValue $state 'baseline'
$objectiveBaseline = Get-PropertyValue $objective 'baseline'
if ([string](Get-PropertyValue $evidence 'status') -ne 'passed' -or
    [string](Get-PropertyValue $evidence 'candidateGateStatus') -ne 'no_candidate_satisfies_evidence_gate' -or
    [int](Get-PropertyValue $evidence 'candidateCount') -ne 0 -or
    [bool](Get-PropertyValue $evidence 'semanticMatchAllowed') -or
    @((Get-PropertyValue $evidence 'runtimeActionsPerformed')).Count -ne 0) { throw 'Candidate gate is not a static no-candidate result.' }
if ([int](Get-PropertyValue $baseline 'sourceCount') -ne 458 -or [string](Get-PropertyValue $baseline 'sourcePackageSha256') -ne $sourceHash -or [string](Get-PropertyValue $baseline 'legadoCommit') -ne $legadoCommit -or
    [int](Get-PropertyValue $objectiveBaseline 'sourceCount') -ne 458 -or [string](Get-PropertyValue $objectiveBaseline 'sourcePackageSha256') -ne $sourceHash -or [string](Get-PropertyValue $objectiveBaseline 'legadoCommit') -ne $legadoCommit) { throw 'Machine or objective baseline drifted.' }
$governance = Get-PropertyValue $state 'governance'
$activeIssueId = Get-TextValue $governance 'activeIssueId'
if ((Get-TextValue $evidence 'activeIssueId') -ne $activeIssueId -or (Get-TextValue $objective.authority 'activeIssueId') -ne $activeIssueId) { throw 'Candidate evidence and objective are not bound to the active issue.' }
$activeIssue = @((Get-PropertyValue $governance 'issues') | Where-Object { (Get-TextValue $_ 'id') -eq $activeIssueId }) | Select-Object -First 1
if ($null -eq $activeIssue -or (Get-TextValue $activeIssue 'status') -ne 'verifying') { throw 'The active source issue must remain verifying.' }
if ((Get-TextValue $evidence 'targetRevision') -ne (Get-TextValue $objective 'targetRevision')) { throw 'Candidate evidence target revision drifted.' }

$evaluatedCount = [int](Get-PropertyValue $evidence 'evaluatedCount')
$now = [DateTimeOffset]::UtcNow.ToString('o')
$queuePreflight = [pscustomobject][ordered]@{
  status = 'passed_no_candidate'
  evidencePath = $EvidencePath
  reproductionCommand = [string](Get-PropertyValue $evidence 'reproductionCommand')
  evaluatedCount = $evaluatedCount
  candidateCount = 0
  activeIssueId = $activeIssueId
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  candidateGateStatus = 'no_candidate_satisfies_evidence_gate'
  updatedAt = $now
}
Set-PropertyValue $governance 'queuePreflight' $queuePreflight
Write-AtomicJson -RelativePath $stateRelative -Value $state
$queueAudit = Get-PropertyValue (Get-PropertyValue $objective 'continuationTarget') 'queueAudit'
$queueAuditEvidenceFields = @(
  'sourceFixEvidencePath',
  'transitionEvidencePath',
  'postRegistrationEvidencePath',
  'failureWitnessPath',
  'currentHeadEvidencePath',
  'postFixContractEvidencePath',
  'documentConsistencyEvidencePath',
  'candidateSourceFixEvidencePath',
  'candidateTargetEvidencePath',
  'candidateFailureWitnessPath',
  'candidateCurrentHeadAuditEvidencePath'
)
$historicalProjection = Get-PropertyValue $queueAudit 'historicalQueueEvidenceProjection'
if ($null -eq $historicalProjection) {
  $historicalProjection = [pscustomobject][ordered]@{
    schemaVersion = 1
    capturedAt = $now
    reason = 'no_candidate_queue_cleared_candidate_evidence_fields'
    fields = [pscustomobject][ordered]@{}
  }
  Set-PropertyValue $queueAudit 'historicalQueueEvidenceProjection' $historicalProjection
}
$historicalFields = Get-PropertyValue $historicalProjection 'fields'
if ($null -eq $historicalFields) {
  $historicalFields = [pscustomobject][ordered]@{}
  Set-PropertyValue $historicalProjection 'fields' $historicalFields
}
foreach ($field in $queueAuditEvidenceFields) {
  $currentValue = Get-PropertyValue $queueAudit $field
  $currentText = if ($null -eq $currentValue) { '' } else { [string]$currentValue }
  $historicalValue = Get-PropertyValue $historicalFields $field
  if ($currentText.Length -gt 0 -and ($null -eq $historicalValue -or [string]$historicalValue.Length -eq 0)) {
    Set-PropertyValue $historicalFields $field $currentText
  }
  Set-PropertyValue $queueAudit $field ''
}
Set-PropertyValue $queueAudit 'status' 'preflight_passed_no_candidate'
Set-PropertyValue $queueAudit 'auditEvidencePath' $EvidencePath
Set-PropertyValue $queueAudit 'candidateIssueId' $activeIssueId
Set-PropertyValue $queueAudit 'candidateIssues' @()
Set-PropertyValue $queueAudit 'candidateGateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $queueAudit 'candidateStatus' 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue $queueAudit 'nextRequired' '补齐下一候选的固定 Legado 语义位置、失败见证、受影响集合、V2 全部消费者矩阵和关闭条件后，才允许原子选择；否则保持当前 verifying。'
$objectiveMetadata = Get-PropertyValue $objective 'objective'
$selectionGate = Get-PropertyValue $objectiveMetadata 'queueSelectionGate'
if ($null -ne $selectionGate) {
  Set-PropertyValue $selectionGate 'currentAnchor' $activeIssueId
  Set-PropertyValue $selectionGate 'selectedIssue' $activeIssueId
  Set-PropertyValue $selectionGate 'candidateIssues' @()
  Set-PropertyValue $selectionGate 'status' 'issue_selected_r3_standard_css_pseudo_243'
  Set-PropertyValue $selectionGate 'candidateAuditStatus' 'active_243_source_fix_static_closed_wait_r4'
  Set-PropertyValue $selectionGate 'candidateStatus' 'source_fix_static_closed'
  Set-PropertyValue $selectionGate 'candidateGateStatus' 'source_fix_static_closed_wait_r4'
  Set-PropertyValue $selectionGate 'evidencePath' $EvidencePath
  Set-PropertyValue $selectionGate 'selectionRule' 'The queue is selected only from full-source-validation-state.json. ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS is the sole active source-closure anchor while its static selector closure waits for R4; no runtime result, old executor fallback or historical issue status may select a second root cause.'
}
$governanceSync = Get-PropertyValue $objective 'governanceSync'
if ($null -ne $governanceSync) {
  Set-PropertyValue $governanceSync 'activeIssueId' $activeIssueId
  Set-PropertyValue $governanceSync 'queueSelectionCurrentAnchor' $activeIssueId
  Set-PropertyValue $governanceSync 'queueAuditCurrentAnchor' $activeIssueId
  Set-PropertyValue $governanceSync 'evidencePath' $EvidencePath
  Set-PropertyValue $governanceSync 'updatedAt' $now
}
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'nextAction' "当前静态队列门禁评估 $evaluatedCount 个 P0/P1 条目，0 个满足五项证据；保持 $activeIssueId verifying，补齐证据后再选择下一议题，R4 deferred。"
Set-PropertyValue (Get-PropertyValue $objective 'executionTarget') 'nextIssues' @()
Set-PropertyValue (Get-PropertyValue $objective 'continuationTarget') 'nextTransition' '当前队列无合格候选；保持活动议题 verifying，下一议题必须先通过五项静态证据门禁。'
Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = "当前静态队列门禁评估 $evaluatedCount 个 P0/P1 条目，0 个满足固定 Legado 语义、影响集合、失败见证、V2 消费者矩阵和关闭条件五项证据；保持 $activeIssueId verifying，R4 deferred。"
$closeCondition = 'A next source-closure issue must first satisfy all five static evidence requirements; R4 runtime, build, device and Legado differential remain deferred.'
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $stateRelative) -IssueId $activeIssueId -IssueStatus verifying -TaskId 'COMPAT-006' -Summary $summary -CloseCondition $closeCondition -EvidencePath $EvidencePath | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

$objectiveSection = @'
## R3-SOURCE-QUEUE-CONTINUATION-NEXT-CANDIDATE

当前机器事实的活动源码议题为 `__ACTIVE_ISSUE_ID__`（`verifying`）。本次只读静态队列门禁评估 `__EVALUATED_COUNT__` 个 P0/P1 条目，0 个同时具备固定 Legado 语义位置、受影响书源/规则集合、可复现失败见证、V2 Analyzer/Rule IR/Matcher/ArkWeb/JSVM/工作流/输出消费者矩阵和关闭条件。

因此不选择第二根因，不追加源码补丁；下一议题必须先补齐五项证据并原子登记。证据：`__EVIDENCE_PATH__`；重现脚本：`tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1`。本门禁未执行运行时、网络、构建、安装、设备或 Legado 差分，R4 继续 deferred。

'@
$objectiveSection = $objectiveSection.Replace('__ACTIVE_ISSUE_ID__', $activeIssueId).Replace('__EVALUATED_COUNT__', [string]$evaluatedCount).Replace('__EVIDENCE_PATH__', $EvidencePath)
$objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentRelative
$objectiveDocument = Replace-MarkedSection -Document $objectiveDocument -StartMarker '## R3-SOURCE-QUEUE-CONTINUATION-NEXT-CANDIDATE' -EndMarker '## 治理修订号漂移修复（ISSUE-AUTO-051）' -Replacement $objectiveSection
Write-AtomicText -RelativePath $objectiveDocumentRelative -Value $objectiveDocument

$governanceSection = @'
## R3 当前目标队列前置审计（当前活动议题）

机器事实 `full-source-validation-state.json` 的固定基线未漂移；当前活动源码议题为 `__ACTIVE_ISSUE_ID__`（`verifying`）。静态门禁评估 `__EVALUATED_COUNT__` 个 P0/P1 条目，合格候选为 `0`；缺失项已逐条登记在 `__EVIDENCE_PATH__`，不得凭状态名称选择第二议题。

重现脚本：`tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1`。该审计只读取固定 Legado HEAD、状态、证据元数据和 UTF-8/哈希，不执行运行时、网络、构建、安装、Android/HarmonyOS 设备或 Legado 差分；R4 继续延期。

'@
$governanceSection = $governanceSection.Replace('__ACTIVE_ISSUE_ID__', $activeIssueId).Replace('__EVALUATED_COUNT__', [string]$evaluatedCount).Replace('__EVIDENCE_PATH__', $EvidencePath)
$governanceDocument = Read-StrictText -RelativePath $governanceDocumentRelative
$governanceDocument = Replace-MarkedSection -Document $governanceDocument -StartMarker '## R3 当前目标队列前置审计（当前活动议题）' -EndMarker '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->' -Replacement $governanceSection
Write-AtomicText -RelativePath $governanceDocumentRelative -Value $governanceDocument

$compatibilityScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $compatibilityScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Derived document refresh failed.' }

[pscustomobject][ordered]@{
  status = 'registered'
  activeIssueId = $activeIssueId
  candidateCount = 0
  evaluatedCount = $evaluatedCount
  evidencePath = $EvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
