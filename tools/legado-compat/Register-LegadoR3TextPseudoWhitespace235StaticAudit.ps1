[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$AuditEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-text-whitespace-235-static-audit-20260809/static-audit.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-text-whitespace-235-static-audit-20260809/registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Assert-Registration {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "235-WS-04 registration blocked: $Message" }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$targetPath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json'
$issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
$expectedRevision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-whitespace-235-032'
$target = Read-StrictJson -RelativePath $targetPath
$audit = Read-StrictJson -RelativePath $AuditEvidencePath
$state = Read-StrictJson -RelativePath $statePath
$objective = Read-StrictJson -RelativePath $objectivePath

Assert-Registration ([string]$audit.status -eq 'passed' -and [string]$audit.targetRevision -eq $expectedRevision -and -not [bool]$audit.semanticMatchAllowed -and @($audit.runtimeActionsPerformed).Count -eq 0) 'static audit is not a static-only pass for revision 032.'
Assert-Registration ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') 'machine queue is not active on issue 235.'
 $targetAlreadyAdvanced = [string]$target.currentSubstage -eq '235-TRANSITION-PRECHECK' -and [string]$target.staticAuditEvidencePath -eq $AuditEvidencePath
Assert-Registration (([string]$target.currentSubstage -eq '235-WS-04') -or $targetAlreadyAdvanced) 'target is neither the WS-04 stage nor its recoverable partial-registration state.'
Assert-Registration ([string]$objective.targetRevision -eq $expectedRevision) 'objective revision drifted.'

$targetPlan = @($target.plan)
$targetWs04 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-04' } | Select-Object -First 1
Assert-Registration ($null -ne $targetWs04 -and (([string]$targetWs04.status -eq 'in_progress') -or ($targetAlreadyAdvanced -and [string]$targetWs04.status -eq 'completed'))) 'target WS-04 is not in progress or a recoverable completed state.'
$objectivePlan = @($objective.continuationPlan)
$objectiveWs04 = $objectivePlan | Where-Object { [string]$_.id -eq '235-WS-04' } | Select-Object -First 1
$objectiveAlreadyAdvanced = $null -ne $objectiveWs04 -and [string]$objectiveWs04.status -eq 'completed' -and [string]$objective.nextAction -like '审核 235→236*'
Assert-Registration ($null -ne $objectiveWs04 -and (([string]$objectiveWs04.status -eq 'in_progress') -or $objectiveAlreadyAdvanced)) 'objective WS-04 is not in progress or a recoverable completed state.'

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_text_whitespace_235_ws04_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $expectedRevision
  issueId = $issueId
  previousSubstage = '235-WS-04'
  nextSubstage = '235-TRANSITION-PRECHECK'
  auditEvidencePath = $AuditEvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_235_ws04_registration_only;issue_remains_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  nextAction = '审核 235→236 静态转移前置条件：236 独立失败合同、影响集合和 current-head 静态审计；通过前不得激活 236。'
}
Write-AtomicJson -RelativePath $RegistrationEvidencePath -Value $registration

Set-PropertyValue -Object $target -Name 'lastUpdatedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue -Object $target -Name 'currentSubstage' -Value '235-TRANSITION-PRECHECK'
Set-PropertyValue -Object $target -Name 'staticAuditEvidencePath' -Value $AuditEvidencePath
Set-PropertyValue -Object $target -Name 'staticAuditStatus' -Value 'passed_static_only'
Set-PropertyValue -Object $target -Name 'nextGate' -Value '235→236 静态转移前置门禁'
Set-PropertyValue -Object $targetWs04 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $targetWs04 -Name 'completedEvidence' -Value $AuditEvidencePath
Write-AtomicJson -RelativePath $targetPath -Value $target

$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '审核 235→236 静态转移前置条件：先验证 ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR 的独立失败合同、影响书源集合、V2 消费者和 current-head 静态审计；通过前保持 235 verifying，不启动 R4。'
Set-PropertyValue -Object $objective.objective -Name 'latestStaticClosure' -Value '235 文本伪类及 text/ownText 空白规范化已完成失败证据、消费者映射、跨 DOM/字符串回退/ArkWeb 源码闭合、16 项静态合同和 WS-04 文档/证据审计；仍不得提升为 passed 或 semantic_match。'
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value '当前唯一活动源码议题仍为 ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS；235-WS-01 至 235-WS-04 已静态闭合，下一步只做 235→236 静态转移前置门禁，236 未激活，R4 仍延期。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value '235-WS-04 静态审计已完成；下一步审核 235→236 静态转移前置条件，必须先补齐 236 独立失败合同、影响集合和 current-head 审计。'
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环；235-WS-01 至 235-WS-04 已完成静态源码闭合，当前只推进 235→236 静态转移前置门禁。R4 运行时、构建、安装、设备和 Legado 差分仍延期。'
$objectiveWs04.status = 'completed'
Set-PropertyValue -Object $objectiveWs04 -Name 'completedEvidence' -Value $AuditEvidencePath
$objectiveTp03 = $objectivePlan | Where-Object { [string]$_.id -eq '235-TP-03' } | Select-Object -First 1
Assert-Registration ($null -ne $objectiveTp03) 'objective 235-TP-03 is missing.'
$objectiveTp03.status = 'completed'
Set-PropertyValue -Object $objectiveTp03 -Name 'completedEvidence' -Value $RegistrationEvidencePath
Write-AtomicJson -RelativePath $objectivePath -Value $objective

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath (Get-RepoPath -RelativePath $statePath) -ObjectivePath (Get-RepoPath -RelativePath $objectivePath) -ActiveIssueId $issueId | Out-Null
if (-not $?) { throw 'refactor objective attachment failed.' }

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$summary = '235-WS-04 静态审计完成：PowerShell AST、JSON/UTF-8/BOM、源码 current-head 哈希、失败证据保留和 run-scoped 证据隔离均通过；235 仍为 verifying，235→236 前置门禁待执行，R4 延期。'
$evidence = @($targetPath, $AuditEvidencePath, $RegistrationEvidencePath, 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-20260809.json', 'tools/legado-compat/evidence/v2-jsoup-text-whitespace-source-fix-20260809.json')
& $updateScript -StatePath (Get-RepoPath -RelativePath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId 'COMPAT-006' -Summary $summary -EvidencePath $evidence | Out-Null
if (-not $?) { throw 'governance state refresh failed.' }

$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
$oldStageText = '当前子阶段：`235-WS-01`/`235-WS-02` 失败证据与消费者矩阵已登记，`235-WS-03` 源码闭合；唯一下一步为 `235-WS-04` 静态证据与文档审计。'
$newStageText = '`235-WS-04` 静态证据与文档审计已完成；唯一下一步为 235→236 静态转移前置门禁，236 尚未激活。'
Assert-Registration ($objectiveDocument.Contains($oldStageText)) 'objective document stage marker is not at the expected WS-04 pre-registration state.'
$objectiveDocument = $objectiveDocument.Replace($oldStageText, '当前子阶段：' + $newStageText)
$objectiveDocument = $objectiveDocument.Replace('3. `235-WS-03` 已使用共享的类型化空白规范化语义跨三条路径修复；静态合同仍只保持 `verifying`，不得写成 `passed` 或 `semantic_match`。', '3. `235-WS-03` 已使用共享的类型化空白规范化语义跨三条路径修复；`235-WS-04` 的静态证据与文档审计也已完成，仍只保持 `verifying`，不得写成 `passed` 或 `semantic_match`。')
Write-AtomicText -RelativePath $objectiveDocumentPath -Value $objectiveDocument

$refreshedTarget = Read-StrictJson -RelativePath $targetPath
$refreshedObjective = Read-StrictJson -RelativePath $objectivePath
$refreshedState = Read-StrictJson -RelativePath $statePath
$refreshedIssue = @($refreshedState.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
Assert-Registration ([string]$refreshedTarget.currentSubstage -eq '235-TRANSITION-PRECHECK' -and [string](@($refreshedTarget.plan | Where-Object { [string]$_.id -eq '235-WS-04' })[0].status) -eq 'completed') 'target did not close WS-04.'
Assert-Registration ([string](@($refreshedObjective.continuationPlan | Where-Object { [string]$_.id -eq '235-WS-04' })[0].status) -eq 'completed' -and [string](@($refreshedObjective.continuationPlan | Where-Object { [string]$_.id -eq '235-TP-03' })[0].status) -eq 'completed') 'objective did not close WS-04 and TP-03.'
Assert-Registration ([string]$refreshedIssue.status -eq 'verifying' -and [string]$refreshedState.governance.activeIssueId -eq $issueId -and @($refreshedIssue.evidencePaths) -contains $RegistrationEvidencePath) 'machine state did not preserve issue 235 verifying with registration evidence.'
Assert-Registration ((Read-StrictText -RelativePath $objectiveDocumentPath).Contains($newStageText)) 'objective document was not refreshed to the transition precheck.'
Write-Output ('WS04_REGISTERED issue={0} next=235-TRANSITION-PRECHECK audit={1} registration={2}' -f $issueId, $AuditEvidencePath, $RegistrationEvidencePath)
