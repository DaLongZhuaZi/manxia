[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-source-queue-continuation-037/queue-audit.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$activeIssue = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
$candidateIssue = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$queueId = 'R3-SOURCE-QUEUE-CONTINUATION-037'
$revision = '2026-08-09-actual-docs-source-refactor-continuation-queue-audit-037'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json'
$contractRelative = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037.json'
$runnerRelative = 'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$oldSafeReadEvidence = @(
  'tools/legado-compat/evidence/full-source-v2-hypium-device/source-14DFBA9D67698EA1CD853B1F5DD7D03E544234BE8EB93692DF96E05E86AE8AFC.json',
  'tools/legado-compat/evidence/full-source-v2-hypium-device/source-2B3E18BAFE29D57B9B8B0A88D2753F8530B95875F47F851CFAF47C6B3765C781.json',
  'tools/legado-compat/evidence/v2-hypium-full-source-runner-contract-stage4.json'
)
$oldExploreEvidence = @(
  'tools/legado-compat/evidence/full-source-v2-hypium-device/manual-84-explore-attempt-1/result.json',
  $runnerRelative,
  $fixtureRelative
)

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Get-Sha256 {
  param([string]$Path)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($algorithm.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '') }
  finally { $algorithm.Dispose() }
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Get-OptionalText {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function Get-OptionalValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([string]$RelativePath, [string]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Assert-Audit {
  param([bool]$Condition, [string]$Detail)
  if (-not $Condition) { throw "R3 queue continuation 037 blocked: $Detail" }
}

$state = Read-StrictJson $stateRelative
$objective = Read-StrictJson $objectiveRelative
$fixture = Read-StrictJson $fixtureRelative
$runner = Read-StrictText $runnerRelative
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Audit ((Get-Sha256 $sourcePackagePath) -eq $baselineHash) 'frozen source package hash drifted.'
$legadoHead = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Audit ($legadoHead -eq $legadoCommit) 'Legado checkout is not at the fixed commit.'
Assert-Audit ([string]$state.governance.activeIssueId -eq $activeIssue -and [string]$objective.authority.activeIssueId -eq $activeIssue) '238 must remain the only active issue during read-only queue audit.'
Assert-Audit (@($objective.executionTarget.nextIssues).Count -eq 0) 'no parallel source issue may be active before candidate activation.'
Assert-Audit ($runner.Contains('Set-HypiumExploreWorkflowsRunning') -and $runner.Contains('Set-HypiumSafeReadWorkflowsRunning') -and $runner.Contains('Test-HypiumSafety')) 'runner dispatch evidence is missing.'

$rawBytes = [System.IO.File]::ReadAllBytes($sourcePackagePath)
$rawText = $strictUtf8.GetString($rawBytes).TrimStart([char]0xFEFF)
$sources = @($rawText | ConvertFrom-Json)
Assert-Audit ($sources.Count -eq 458) 'source package count is not 458.'
$exploreCount = @($sources | Where-Object { (Get-OptionalText -Object $_ -Name 'exploreUrl').Trim().Length -gt 0 }).Count
$searchCount = @($sources | Where-Object { (Get-OptionalText -Object $_ -Name 'searchUrl').Trim().Length -gt 0 }).Count
$exploreOnlyCount = @($sources | Where-Object { (Get-OptionalText -Object $_ -Name 'exploreUrl').Trim().Length -gt 0 -and (Get-OptionalText -Object $_ -Name 'searchUrl').Trim().Length -eq 0 }).Count
$dualEntryCount = @($sources | Where-Object { (Get-OptionalText -Object $_ -Name 'exploreUrl').Trim().Length -gt 0 -and (Get-OptionalText -Object $_ -Name 'searchUrl').Trim().Length -gt 0 }).Count

$issues = @($state.governance.issues)
$p0p1Candidates = @($issues | Where-Object { [string](Get-OptionalValue -Object $_ -Name 'severity') -in @('P0', 'P1') -and [string](Get-OptionalValue -Object $_ -Name 'status') -ne 'passed' } | ForEach-Object {
  $attemptValue = Get-OptionalValue -Object $_ -Name 'attempts'
  $evidenceValue = Get-OptionalValue -Object $_ -Name 'evidencePaths'
  [pscustomobject][ordered]@{ id = [string](Get-OptionalValue -Object $_ -Name 'id'); status = [string](Get-OptionalValue -Object $_ -Name 'status'); severity = [string](Get-OptionalValue -Object $_ -Name 'severity'); attempts = if ($null -eq $attemptValue) { 0 } else { [int]$attemptValue }; evidenceCount = if ($null -eq $evidenceValue) { 0 } else { @($evidenceValue).Count } }
})
$safeIssue = $issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-HYPIUM-SAFE-READ-EXPLORE-PRIORITY' } | Select-Object -First 1
$exploreOnlyIssue = $issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-HYPIUM-EXPLORE-ONLY-DISPATCH' } | Select-Object -First 1
Assert-Audit ($null -ne $safeIssue -and $null -ne $exploreOnlyIssue) 'both observed P1 workflow issues must be present.'
$safeEvidence = Read-StrictJson $oldSafeReadEvidence[0]
$exploreOnlyEvidence = Read-StrictJson $oldSafeReadEvidence[1]
Assert-Audit ([string]$safeEvidence.executionProfile -eq 'safe_read_path' -and [string]$safeEvidence.workflowResults.bookInfo -like 'policy_blocked:profile_explore_only') 'safe-read evidence does not show the early Explore-only projection.'
Assert-Audit ([string]$exploreOnlyEvidence.executionProfile -eq 'safe_read_path' -and [string]$exploreOnlyEvidence.workflowResults.search -like 'policy_blocked:profile_explore_only') 'Explore-only evidence does not show the missing-Search projection.'

$merge = [pscustomobject][ordered]@{
  rootCauseId = $candidateIssue
  primaryCause = 'workflow_capability_planning_and_dispatch_coupled'
  issueIds = @([string]$safeIssue.id, [string]$exploreOnlyIssue.id)
  relation = 'Both issues are produced by the same safe_read_path capability/early-return branch; one affects sources with both entry URLs, the other affects Explore-only sources.'
  fixedLegadoSemantic = 'Legado treats Search, Explore, BookInfo, Toc, Content, File and Review as independently declared workflow capabilities. Missing searchUrl cannot disable exploreUrl, and a terminal entry workflow must settle only workflows that were actually scheduled.'
  affectedSourcePackage = [pscustomobject][ordered]@{ sourceCount = 458; searchUrlCount = $searchCount; exploreUrlCount = $exploreCount; dualEntryCount = $dualEntryCount; exploreOnlyCount = $exploreOnlyCount }
  affectedWorkflowNames = @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')
  evidencePaths = @($oldSafeReadEvidence + $oldExploreEvidence + $fixtureRelative + $contractRelative + $runnerRelative)
  closeCondition = 'A deterministic failure contract passes after the runner plans and dispatches entry workflows independently, Explore-only continues through the guarded read chain when a result is selected, terminal settlement reflects only scheduled workflows, and static state/document evidence is refreshed. R4 runtime and device validation remain separate.'
}

$audit = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_source_queue_continuation_037'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  queueId = $queueId
  activeIssueId = $activeIssue
  candidateIssueId = $candidateIssue
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  candidateSet = $p0p1Candidates
  candidateCount = $p0p1Candidates.Count
  selectedCandidate = $merge
  candidateGateStatus = 'pending_failure_contract'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_audit_static_only;candidate_not_active;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'Candidate failure contract and current-head source audit must pass before activating the merged root cause; otherwise record a structured blocked reason and keep 238 as the sole active issue.'
}
Write-AtomicJson -RelativePath $OutputPath -Value $audit

$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'status' 'audited_candidate_pending_failure_contract'
Set-PropertyValue $queueAudit 'auditEvidencePath' $OutputPath
Set-PropertyValue $queueAudit 'candidateIssueId' $candidateIssue
Set-PropertyValue $queueAudit 'candidateIssues' @($candidateIssue)
Set-PropertyValue $queueAudit 'candidateGateStatus' 'pending_failure_contract'
Set-PropertyValue $queueAudit 'nextRequired' '先记录 safe_read Search/Explore 独立派发的失败合同，再修改 runner；失败合同通过后才能激活该唯一 P1 根因。'
$objective.targetRevision = $revision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '执行 037 后置步骤：建立并运行 workflow capability dispatch 失败合同；238 保持 verifying，候选未激活，R4 deferred。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '037 只读审计已完成；下一步建立 safe_read Search/Explore 独立派发失败合同，候选通过后才原子激活。'
Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

$stateIssues = @($state.governance.issues)
$rootIssue = $stateIssues | Where-Object { [string]$_.id -eq $candidateIssue } | Select-Object -First 1
if ($null -eq $rootIssue) {
  $rootIssue = [pscustomobject][ordered]@{ id = $candidateIssue; taskId = 'COMPAT-006'; status = 'planned'; severity = 'P1'; attempts = 0; summary = '037 合并根因：safe_read 能力规划把 Search/Explore 存在性、执行策略和终态结算耦合；Explore-only 与双入口书源均可能被错误早退。候选尚未激活。'; closeCondition = [string]$merge.closeCondition; evidencePaths = @($OutputPath, $fixtureRelative, $contractRelative, $runnerRelative) ; rootCauseId = $candidateIssue; mergedIssueIds = @($safeIssue.id, $exploreOnlyIssue.id); lastUpdatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  $state.governance.issues = @($stateIssues) + @($rootIssue)
} else {
  Set-PropertyValue $rootIssue 'status' 'planned'
  Set-PropertyValue $rootIssue 'severity' 'P1'
  Set-PropertyValue $rootIssue 'summary' '037 合并根因：safe_read 能力规划把 Search/Explore 存在性、执行策略和终态结算耦合；Explore-only 与双入口书源均可能被错误早退。候选尚未激活。'
  Set-PropertyValue $rootIssue 'closeCondition' ([string]$merge.closeCondition)
  Set-PropertyValue $rootIssue 'rootCauseId' $candidateIssue
  Set-PropertyValue $rootIssue 'mergedIssueIds' @($safeIssue.id, $exploreOnlyIssue.id)
  Set-PropertyValue $rootIssue 'evidencePaths' @($OutputPath, $fixtureRelative, $contractRelative, $runnerRelative)
  Set-PropertyValue $rootIssue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
}
foreach ($oldIssue in @($safeIssue, $exploreOnlyIssue)) {
  Set-PropertyValue $oldIssue 'rootCauseId' $candidateIssue
  Set-PropertyValue $oldIssue 'mergedInto' $candidateIssue
  Set-PropertyValue $oldIssue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
}
$state.governance.activeIssueId = $activeIssue
Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelative) -State $state -Depth 40

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $activeIssue | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'objective attachment failed.' }

$refreshScript = Join-Path $PSScriptRoot 'Invoke-LegadoCompatibility.ps1'
& $refreshScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'document refresh failed.' }

$objectiveDocumentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText $objectiveDocumentRelative
$startMarker = '## R3-SOURCE-QUEUE-CONTINUATION-037 队列审计'
$endMarker = '## 单议题执行规则'
$section = @"
$startMarker

037 只读队列审计已完成，当前唯一活动源码锚点仍为 ``$activeIssue``，候选根因为 ``$candidateIssue``，状态为 `planned`，尚未与 238 并行激活。审计将 `ISSUE-COMPAT-HYPIUM-SAFE-READ-EXPLORE-PRIORITY` 与 `ISSUE-COMPAT-HYPIUM-EXPLORE-ONLY-DISPATCH` 合并为同一源码/编排主因：能力存在性、入口选择和终态结算被 safe_read 早退分支耦合。

固定包静态统计为 Search URL `$searchCount` 条、Explore URL `$exploreCount` 条、双入口 `$dualEntryCount` 条、Explore-only `$exploreOnlyCount` 条；证据只绑定原始字段和脱敏工作流状态，不产生运行时兼容结论。下一动作是建立失败合同并验证 Search/Explore 独立派发、Explore-only 读链继续和按实际调度结算；合同通过后才允许原子激活候选。

证据：``$OutputPath``。运行时批次、真实网络、构建、安装、设备和 Legado 差分继续延期到 R4。

"@
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if ([regex]::IsMatch($objectiveDocument, $pattern)) { $objectiveDocument = [regex]::Replace($objectiveDocument, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $section }) }
else {
  $index = $objectiveDocument.IndexOf($endMarker)
  if ($index -lt 0) { throw 'objective document insertion marker missing.' }
  $objectiveDocument = $objectiveDocument.Insert($index, $section)
}
Write-AtomicText -RelativePath $objectiveDocumentRelative -Value $objectiveDocument

[pscustomobject][ordered]@{ status = 'passed'; queueId = $queueId; candidateIssueId = $candidateIssue; activeIssueId = $activeIssue; candidateGateStatus = 'pending_failure_contract'; candidateCount = $p0p1Candidates.Count; evidencePath = $OutputPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 20
