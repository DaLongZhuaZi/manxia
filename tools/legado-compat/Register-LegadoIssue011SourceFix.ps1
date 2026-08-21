[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-post-fix-011-20260809.json',
  [string]$PostFixAuditPath = 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-post-fix-20260809.json',
  [string]$SourceFixEvidencePath = 'tools/legado-compat/evidence/v2-issue-011-url-attribute-source-fix-20260809.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-source-fix-registration-20260809/registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-011'
$taskId = 'COMPAT-006'
$revision = '2026-08-09-actual-docs-source-refactor-url-attribute-011-source-fix-static-closed'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return (Read-StrictText $RelativePath | ConvertFrom-Json)
}

function Get-FileSha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepositoryPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Write-AtomicText([string]$RelativePath, [string]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, $Value, $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Registration([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE011_SOURCE_FIX_REGISTRATION_BLOCKED:$Message" }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$failurePath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json'
$preFixAuditPath = 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-pre-fix-20260809.json'
$transitionPath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/transition-consistency.json'

$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$failure = Read-StrictJson $failurePath
$preFixAudit = Read-StrictJson $preFixAuditPath
$postFix = Read-StrictJson $PostFixContractPath
$postFixAudit = Read-StrictJson $PostFixAuditPath

Assert-Registration ([int]$state.baseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Registration ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Registration ([string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Registration ([string]$objective.baseline.sourceCount -eq $sourceCount) 'objective source count drifted'
Assert-Registration ([string]$objective.baseline.sourcePackageSha256 -eq $sourceHash) 'objective source hash drifted'
Assert-Registration ([string]$objective.baseline.legadoCommit -eq $legadoCommit) 'objective Legado commit drifted'
Assert-Registration ([string]$state.governance.activeIssueId -eq $issueId) '011 is not the active machine issue'
Assert-Registration ([string]$objective.authority.activeIssueId -eq $issueId) '011 is not the active objective issue'
Assert-Registration ([string]$failure.status -eq 'failed_static_only') 'pre-fix witness was overwritten'
Assert-Registration ([string]$preFixAudit.status -eq 'failed_static_only') 'pre-fix current-head audit was overwritten'
Assert-Registration ([string]$postFix.status -eq 'passed_static_only') 'post-fix contract is not static-passed'
Assert-Registration ([string]$postFixAudit.status -eq 'passed_static_only') 'post-fix current-head audit is not static-passed'
Assert-Registration ([int]$postFixAudit.unresolvedGapCount -eq 0) 'post-fix current-head audit retains unresolved gaps'
Assert-Registration (-not [bool]$postFix.semanticMatchAllowed -and -not [bool]$postFixAudit.semanticMatchAllowed) 'static evidence cannot enable semantic match'
Assert-Registration (@($postFix.runtimeActionsPerformed).Count -eq 0 -and @($postFixAudit.runtimeActionsPerformed).Count -eq 0) 'runtime actions were performed before R4'

$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failurePath
  preFixCurrentHeadAuditPath = $preFixAuditPath
  postFixContractPath = $PostFixContractPath
  postFixCurrentHeadAuditPath = $PostFixAuditPath
  transitionEvidencePath = $transitionPath
  primaryCause = [ordered]@{
    classification = 'selector_attribute_projection_value_deduplication'
    statement = 'Legado AnalyzeByJSoup removes blank and repeated terminal Element.attr values before getString joins them. V2 now applies the same nonblank first-value projection in Analyzer CSS terminal/list paths, standard and Native JSVM java.getStringList CSS paths, and ArkWeb legadoGetStringListSingle.'
  }
  semanticBoundary = [ordered]@{
    directEachAttr = 'preserve order, duplicates and present empty attributes according to Jsoup 1.16.2'
    selectorListProjection = 'remove blanks and later duplicate exact values, preserving first occurrence order'
    urlResolution = 'unchanged; request carrier/workflow resolves URL only at request-owning boundary'
  }
  changedFiles = @(
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html'
  )
  sourceFixHashes = $postFix.sourceFix
  currentHeadHashes = $postFixAudit.currentHeadHashes
  affectedConsumerCount = @($postFixAudit.consumerMatrix).Count
  unresolvedGapCount = [int]$postFixAudit.unresolvedGapCount
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;011_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  reproductionCommands = @(
    'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011PostFixContract.ps1',
    'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011CurrentHeadPostFixAudit.ps1'
  )
  closeCondition = 'R4 must execute affected source equivalence classes, deterministic full Harness, same-input Legado differential, build and device gates; only then may 011 become passed or semantic_match.'
}
Write-AtomicJson $SourceFixEvidencePath $sourceFix

$objective.targetRevision = $revision
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_011_URL_ATTRIBUTE_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective 'nextAction' '011 源码静态闭合已完成并保持 verifying；下一步由用户单独开启 R4，执行受影响等价类、全量 Harness、Legado 差分、构建和设备验证。'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-011-URL-ATTRIBUTE-STATIC-CLOSED'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' 'ISSUE-COMPAT-011 的属性列表值级去重源码修复已静态闭合；保持 direct eachAttr、URL resolution 和 request carrier 边界不变，R4 才能验证运行时语义。'
Set-PropertyValue $objective.executionTarget 'statement' '在固定 458 条书源与 Legado 提交基线下，011 的源码修复、静态 post-fix contract 和 9 消费者 current-head 审计已闭合；状态保持 verifying，R4 运行时、Legado 差分、构建和设备验证延期。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-011 保持 verifying：共享属性列表投影的非空首值去重已完成静态闭合；S2T、037 和历史议题继续等待 R4。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' 'R4-011：执行受影响等价类和统一 Harness/Legado 差分；未完成前不得写成 passed 或 semantic_match。'
$queueAudit = $objective.continuationTarget.queueAudit
Set-PropertyValue $queueAudit 'status' 'source_fix_static_closed_wait_r4'
Set-PropertyValue $queueAudit 'candidateStatus' 'source_fix_static_closed'
Set-PropertyValue $queueAudit 'nextRequired' 'R4 定向/全量运行时 Harness、Legado 同输入差分、构建和设备验证；静态阶段不得提升语义状态。'
Set-PropertyValue $queueAudit 'sourceFixEvidencePath' $SourceFixEvidencePath
Set-PropertyValue $queueAudit 'postFixContractEvidencePath' $PostFixContractPath
Set-PropertyValue $queueAudit 'postRegistrationEvidencePath' $RegistrationEvidencePath
Set-PropertyValue $queueAudit 'currentHeadEvidencePath' $PostFixAuditPath
foreach ($item in @($objective.continuationPlan)) {
  if ([string]$item.id -eq '011-URL-05') {
    Set-PropertyValue $item 'status' 'completed_static_only'
    Set-PropertyValue $item 'action' '完成共享属性列表值级去重源码修复、post-fix contract、9 消费者 current-head 审计；保持 verifying，R4 deferred。'
    Set-PropertyValue $item 'evidence' @($SourceFixEvidencePath, $PostFixContractPath, $PostFixAuditPath)
  }
}
Write-AtomicJson $objectivePath $objective

$setObjectiveScript = Get-RepositoryPath 'tools/legado-compat/Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setObjectiveScript -StatePath (Get-RepositoryPath $statePath) -ObjectivePath (Get-RepositoryPath $objectivePath) -ActiveIssueId $issueId | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Refactor objective attachment failed.' }

$updateScript = Get-RepositoryPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = '011 源码静态闭合：共享属性列表投影已按 Legado nonblank first-value 语义修复，9 个 current-head 消费者无未解释静态缺口；状态保持 verifying，R4 deferred。'
$closeCondition = 'R4 完成受影响等价类、全量确定性 Harness、Legado 同输入差分、构建和设备门禁后，才允许 011 进入 passed 或 semantic_match。'
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -StatePath (Get-RepositoryPath $statePath) `
  -IssueId $issueId `
  -IssueStatus verifying `
  -TaskId $taskId `
  -TaskStatus running `
  -Severity P0 `
  -Summary $summary `
  -CloseCondition $closeCondition `
  -EvidencePath "$SourceFixEvidencePath,$PostFixContractPath,$PostFixAuditPath" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

$registration = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_source_fix_registration'
  status = 'registered_verifying'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveRevision = $revision
  issueId = $issueId
  taskId = $taskId
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  sourceFixEvidencePath = $SourceFixEvidencePath
  postFixContractPath = $PostFixContractPath
  postFixAuditPath = $PostFixAuditPath
  preFixWitnessPreserved = $true
  machineIssueStatus = 'verifying'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextGate = 'R4_runtime_equivalence_harness_legado_diff_build_device'
}
Write-AtomicJson $RegistrationEvidencePath $registration

# Derived governance documents are refreshed by Update-LegadoGovernanceState.
# Replace only the execution-target section afterwards so the objective doc
# states the static closure and the deferred R4 handoff explicitly.
$objectiveDocPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDoc = Read-StrictText $objectiveDocPath
$startMarker = '## 下一持续执行目标'
$endMarker = '## 持续目标'
$section = @"
## 下一持续执行目标

当前目标修订为 ``$revision``，执行游标为 ``R3_ISSUE_011_URL_ATTRIBUTE_STATIC_CLOSED_WAIT_R4``。``ISSUE-COMPAT-011`` 的源码修复已完成静态闭合，状态保持 ``verifying``，S2T 与历史源码议题继续等待 R4。

本轮已完成固定 Legado Jsoup 1.16.2 ``Elements.eachAttr()`` 语义核验，以及 Analyzer、标准/Native JSVM、ArkWeb ``java.getStringList`` 属性列表投影的非空首值去重修复。直接 ``eachAttr`` 仍保留重复值，URL resolution 与 request carrier 边界未被修改。

静态证据：``$SourceFixEvidencePath``、``$PostFixContractPath``、``$PostFixAuditPath``、``$RegistrationEvidencePath``；失败前见证 ``$failurePath`` 保持不可覆盖。

下一步只允许进入 R4：受影响等价类运行时 fixture、全量确定性 Harness、同输入 Legado 差分、构建和 Android/HarmonyOS 设备门禁。静态证据不得写成 ``passed`` 或 ``semantic_match``。

"@
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if (-not [regex]::IsMatch($objectiveDoc, $pattern)) { throw 'objective document target section marker missing.' }
$objectiveDoc = [regex]::Replace($objectiveDoc, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $section })
Write-AtomicText $objectiveDocPath $objectiveDoc

[pscustomobject][ordered]@{
  status = 'registered_verifying'
  issueId = $issueId
  sourceFixEvidencePath = $SourceFixEvidencePath
  postFixContractPath = $PostFixContractPath
  postFixAuditPath = $PostFixAuditPath
  registrationEvidencePath = $RegistrationEvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextGate = 'R4_runtime_equivalence_harness_legado_diff_build_device'
} | ConvertTo-Json -Depth 20
