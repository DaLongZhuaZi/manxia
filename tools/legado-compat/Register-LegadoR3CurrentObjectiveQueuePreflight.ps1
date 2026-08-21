[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r3-source-queue-preflight-20260809/current-objective-preflight.json'
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
$objectiveDocumentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$governanceDocumentRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$preflightScriptRelative = 'tools/legado-compat/Test-LegadoR3CurrentObjectiveQueuePreflight.ps1'
$activeIssueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $utf8Strict.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  try { return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-TextValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  $value = Get-PropertyValue -Object $Object -Name $Name
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Value)
  $path = Get-RepoPath $RelativePath
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
}

function Get-Issue {
  param([object[]]$Issues, [Parameter(Mandatory = $true)][string]$Id)
  foreach ($issue in @($Issues)) {
    if ((Get-TextValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Replace-MarkedSection {
  param([string]$Document, [string]$StartMarker, [string]$EndMarker, [string]$Replacement)
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if ([regex]::IsMatch($Document, $pattern)) {
    return [regex]::Replace($Document, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
  }
  $index = $Document.IndexOf($EndMarker, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { throw "document insertion marker missing: $EndMarker" }
  return $Document.Insert($index, $Replacement)
}

$evidence = Read-StrictJson -RelativePath $EvidencePath
if ((Get-TextValue -Object $evidence -Name 'status') -ne 'passed' -or
    (Get-TextValue -Object $evidence -Name 'candidateGateStatus') -ne 'no_candidate_satisfies_evidence_gate' -or
    [int](Get-PropertyValue -Object $evidence -Name 'candidateCount') -ne 0 -or
    [bool](Get-PropertyValue -Object $evidence -Name 'semanticMatchAllowed') -or
    @((Get-PropertyValue -Object $evidence -Name 'runtimeActionsPerformed')).Count -ne 0) {
  throw 'queue preflight evidence is not a static no-candidate result.'
}
$state = Read-StrictJson -RelativePath $stateRelative
$objective = Read-StrictJson -RelativePath $objectiveRelative
$evaluatedCount = [int](Get-PropertyValue -Object $evidence -Name 'evaluatedCount')
$evidenceMarkdown = '`' + $EvidencePath + '`'
$baseline = Get-PropertyValue -Object $state -Name 'baseline'
if ([int](Get-PropertyValue -Object $baseline -Name 'sourceCount') -ne 458 -or
    (Get-TextValue -Object $baseline -Name 'sourcePackageSha256') -ne $baselineHash -or
    (Get-TextValue -Object $baseline -Name 'legadoCommit') -ne $legadoCommit) { throw 'machine baseline drifted.' }
$governance = Get-PropertyValue -Object $state -Name 'governance'
if ((Get-TextValue -Object $governance -Name 'activeIssueId') -ne $activeIssueId) { throw '037 is not the machine active issue.' }
$issues = @((Get-PropertyValue -Object $governance -Name 'issues'))
$activeIssue = Get-Issue -Issues $issues -Id $activeIssueId
if ($null -eq $activeIssue -or (Get-TextValue -Object $activeIssue -Name 'status') -ne 'verifying') { throw '037 must remain verifying.' }

$existingEvidence = @((Get-PropertyValue -Object $activeIssue -Name 'evidencePaths')) | ForEach-Object { [string]$_ } | Where-Object { $_.Length -gt 0 }
if (@($existingEvidence) -notcontains $EvidencePath) {
  $existingEvidence = @($existingEvidence) + @($EvidencePath)
}
if (@($existingEvidence) -notcontains $preflightScriptRelative) {
  $existingEvidence = @($existingEvidence) + @($preflightScriptRelative)
}
if (@($existingEvidence).Count -gt 0) {
  Set-PropertyValue -Object $activeIssue -Name 'evidencePaths' -Value $existingEvidence
}
$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue -Object $activeIssue -Name 'lastQueuePreflightAt' -Value $now
Set-PropertyValue -Object $activeIssue -Name 'queuePreflightStatus' -Value 'passed_no_candidate'
Set-PropertyValue -Object $activeIssue -Name 'summary' -Value ('037 源码静态闭合保持 verifying；注册后一致性审计 21 项通过，当前文档队列前置审计评估 {0} 个未通过 P0/P1 条目且 0 个满足五项证据门禁；R4 运行时、原版差分、构建和真机验证继续延期。' -f $evaluatedCount)
Set-PropertyValue -Object $governance -Name 'queuePreflight' -Value ([pscustomobject][ordered]@{
    status = 'passed_no_candidate'
    evidencePath = $EvidencePath
    reproductionCommand = [string](Get-PropertyValue -Object $evidence -Name 'reproductionCommand')
    evaluatedCount = $evaluatedCount
    candidateCount = 0
    activeIssueId = $activeIssueId
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    updatedAt = $now
  })
$state.governance = $governance
Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelative) -State $state -Depth 40

$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue -Object $queueAudit -Name 'status' -Value 'preflight_passed_no_candidate'
Set-PropertyValue -Object $queueAudit -Name 'auditEvidencePath' -Value $EvidencePath
Set-PropertyValue -Object $queueAudit -Name 'candidateIssueId' -Value $activeIssueId
Set-PropertyValue -Object $queueAudit -Name 'candidateIssues' -Value @()
Set-PropertyValue -Object $queueAudit -Name 'candidateGateStatus' -Value 'no_candidate_satisfies_evidence_gate'
Set-PropertyValue -Object $queueAudit -Name 'nextRequired' -Value '补齐下一候选的固定 Legado 语义位置、失败见证、受影响集合、V2 全部消费者矩阵和关闭条件后，才允许原子选择；否则保持 037 verifying。'
$objective.targetRevision = '2026-08-09-actual-docs-source-refactor-queue-preflight-037'
$objective.lastReviewedAt = $now
$objective.nextAction = ('当前文档队列前置审计已完成：{0} 个未通过 P0/P1 条目中没有候选同时满足五项证据门禁；保持 ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH verifying，补齐证据后再选择下一议题，R4 deferred。' -f $evaluatedCount)
$objective.continuationTarget.nextTransition = '当前队列前置审计无合格候选；037 保持唯一活动源码锚点和 verifying，任何新议题必须先通过五项证据门禁。'
Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

$attachScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $attachScript -StatePath (Get-RepoPath $stateRelative) -ObjectivePath (Get-RepoPath $objectiveRelative) -ActiveIssueId $activeIssueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'updated objective attachment failed.' }

$objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentRelative
$objectiveSection = @(
  '## R3-SOURCE-QUEUE-CONTINUATION-037 队列前置审计',
  '',
  ('037 注册后一致性审计已通过 21 项静态断言；随后对当前机器事实中的 {0} 个未通过 P0/P1 条目进行只读前置核对，0 个候选同时具备固定 Legado 语义位置、受影响书源/规则节点集合、可复现失败见证、V2 全部消费者矩阵和明确关闭条件。因此 `ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH` 继续作为唯一活动源码锚点并保持 `verifying`，没有臆选第二议题。' -f $evaluatedCount),
  '',
  ('审计证据：`{0}`；重现脚本：`{1}`。该审计只读取状态、固定 Legado HEAD、证据元数据和 UTF-8/哈希，不执行运行时、网络、构建、安装、Android/HarmonyOS 设备或 Legado 差分；R4 继续延期。下一动作是为下一个真实根因补齐五项证据门禁，之后才允许一次选择一个活动议题。' -f $EvidencePath, $preflightScriptRelative),
  ''
) -join "`r`n"
$objectiveDocument = Replace-MarkedSection -Document $objectiveDocument -StartMarker '## R3-SOURCE-QUEUE-CONTINUATION-037 队列前置审计' -EndMarker '## 单议题执行规则' -Replacement $objectiveSection
Write-AtomicText -RelativePath $objectiveDocumentRelative -Value $objectiveDocument

$governanceDocument = Read-StrictText -RelativePath $governanceDocumentRelative
$governanceSection = @(
  '## R3 当前目标队列前置审计（2026-08-09）',
  '',
  ('机器事实 `full-source-validation-state.json` 的固定基线未漂移；当前唯一活动源码议题仍为 `{0}` (`verifying`)。本次只读审计评估 {1} 个未通过 P0/P1 条目，合格候选为 `0`：其余条目缺少至少一项固定 Legado 位置、失败见证、受影响集合、V2 消费者矩阵或关闭条件，或明确属于 R4 延后验证。静态结果不产生 `passed`/`semantic_match`，运行时、构建、安装、设备和真实网络继续禁止。' -f $activeIssueId, $evaluatedCount),
  '',
  ('证据：`{0}`；重现脚本：`{1}`。下一步只能为一个候选补齐证据门禁并登记后再修复，不得并行打补丁或凭状态名称选题。' -f $EvidencePath, $preflightScriptRelative),
  ''
) -join "`r`n"
$governanceDocument = Replace-MarkedSection -Document $governanceDocument -StartMarker '## R3 当前目标队列前置审计（2026-08-09）' -EndMarker '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->' -Replacement $governanceSection
Write-AtomicText -RelativePath $governanceDocumentRelative -Value $governanceDocument

$compatibilityScript = Join-Path $PSScriptRoot 'Invoke-LegadoCompatibility.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $compatibilityScript -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'derived governance document refresh failed.' }

[pscustomobject][ordered]@{
  status = 'registered'
  activeIssueId = $activeIssueId
  candidateCount = 0
  evaluatedCount = $evaluatedCount
  evidencePath = $EvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
