[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-java-object-content-overload-238-target-20260809/target.json',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/registration.json'
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
$issue237 = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
$issue238 = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
$revisionBefore = '2026-08-09-actual-docs-source-refactor-continuation-java-object-238-035'
$revision = '2026-08-09-actual-docs-source-refactor-continuation-java-object-238-036'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Assert-Transition {
  param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
  if (-not $Condition) { throw "237 to 238 transition blocked: $Message" }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$statePath = Get-RepoPath -RelativePath $stateRelative
$objectivePath = Get-RepoPath -RelativePath $objectiveRelative
$registrationPath = Get-RepoPath -RelativePath $RegistrationEvidencePath
$state = Read-StrictJson -RelativePath $stateRelative
$objective = Read-StrictJson -RelativePath $objectiveRelative
$target = Read-StrictJson -RelativePath $TargetEvidencePath
$preFix = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json'
$contract = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json'
$currentHead = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json'
$sourceFix = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json'
$fixture = Read-StrictJson -RelativePath 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json'

$alreadyRegistered = [string]$state.governance.activeIssueId -eq $issue238 -and [string]$objective.authority.activeIssueId -eq $issue238 -and (Test-Path -LiteralPath $registrationPath -PathType Leaf)
if ($alreadyRegistered) {
  [pscustomobject][ordered]@{ status = 'already_registered'; idempotent = $true; previousIssueId = $issue237; issueId = $issue238; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'static_registration_recovery_only;R4_runtime_build_device_and_legado_diff_deferred' } | ConvertTo-Json -Depth 20
  return
}

Assert-Transition ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issue237 -and [string]$state.governance.status -eq 'running') '237 is not the sole active queue anchor before transition.'
Assert-Transition ([string]$objective.targetRevision -eq $revisionBefore -and [string]$objective.authority.activeIssueId -eq $issue237 -and [string]$objective.executionTarget.currentIssue -eq $issue237) 'objective is not at the 237-to-238 transition boundary.'
Assert-Transition ([string]$target.status -eq 'candidate_gate_ready' -and [string]$target.issueId -eq $issue238 -and [string]$target.currentSubstage -eq '238-OC-05') '238 target has not completed its candidate gate.'
$issues = @($state.governance.issues)
$record237 = $issues | Where-Object { [string]$_.id -eq $issue237 } | Select-Object -First 1
$record238 = $issues | Where-Object { [string]$_.id -eq $issue238 } | Select-Object -First 1
Assert-Transition ($null -ne $record237 -and [string]$record237.status -eq 'verifying' -and $null -ne $record238 -and [string]$record238.status -eq 'verifying') '237/238 statuses are not both verifying-only.'
Assert-Transition ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq $issue238 -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) '238 failure witness is not static-only.'
Assert-Transition ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 20) '238 static contract is invalid.'
Assert-Transition ([string]$currentHead.status -eq 'passed' -and [int]$currentHead.assertions -ge 13 -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) '238 current-head audit is invalid.'
Assert-Transition ([string]$sourceFix.status -eq 'source_closed_static_only' -and -not [bool]$sourceFix.semanticMatchAllowed) '238 source-fix evidence is invalid.'
Assert-Transition (@($fixture.cases).Count -eq 7) '238 fixture drifted.'
Assert-Transition (@($target.evidencePaths).Count -ge 5) '238 target does not bind all static evidence.'

$gate = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_java_object_237_to_238_transition_consistency'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fromIssue = $issue237
  toIssue = $issue238
  nextCandidateAfterRegistration = ''
  objectiveId = [string]$objective.objectiveId
  fromRevision = $revisionBefore
  toRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  evidencePaths = @(
    $TargetEvidencePath,
    'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json',
    'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json',
    'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json',
    'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json',
    'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json'
  )
  consumerMatrix = $currentHead.consumerMatrix
  transitionAssertions = 14
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_transition_only;238_verifying_source_anchor;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = '238 object mContent semantics match fixed Legado across ArkWeb, standard JSVM and Native JSVM in R4, affected-source equivalence, 458-source Harness, differential, build and device validation.'
}
Write-AtomicJson -RelativePath $GateEvidencePath -Value $gate

$target.status = 'active'
$target.currentSubstage = '238-OC-06'
$target.currentStatus = 'source_closed_static_only'
Set-PropertyValue -Object $target -Name 'lastUpdatedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue -Object $target -Name 'transitionEvidencePath' -Value $GateEvidencePath
$target.plan | Where-Object { [string]$_.id -eq '238-OC-05' } | ForEach-Object { $_.status = 'completed'; Set-PropertyValue -Object $_ -Name 'evidence' -Value $GateEvidencePath }
$target.plan | Where-Object { [string]$_.id -eq '238-OC-06' } | ForEach-Object { $_.status = 'deferred' }
if (@($target.plan | Where-Object { [string]$_.id -eq '238-OC-06' }).Count -eq 0) {
  $target.plan += @([pscustomobject][ordered]@{ id = '238-OC-06'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' })
}
Write-AtomicJson -RelativePath $TargetEvidencePath -Value $target

$objective.targetRevision = $revision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '238 源码静态闭合保持 verifying；R4 deferred。下一 P0/P1 源码议题尚未选择；继续保留统一 R4 入口，不执行运行时、构建、安装或设备验证。'
Set-PropertyValue -Object $objective.authority -Name 'activeIssueId' -Value $issue238
Set-PropertyValue -Object $objective.authority -Name 'activeIssueSelection' -Value 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD is now the sole active source-closure issue after the passed 237→238 static transition gate. ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS and earlier issues remain verifying for deferred R4; no next runtime issue is selected and static verification never becomes semantic_match.'
Set-PropertyValue -Object $objective.objective -Name 'activeIssue' -Value $issue238
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value '当前唯一活动源码议题为 ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD；已登记 NativeObject mContent 的失败见证、ArkWeb/标准 JSVM/Native JSVM/重复内嵌 helper 消费矩阵、20 项基础静态合同、13 项 current-head 审计、source-fix 和 237→238 静态转移证据，R4 仍延期。'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'status' -Value 'issue_selected_r3_java_object_content_238'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'currentAnchor' -Value $issue238
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'selectedIssue' -Value $issue238
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateIssues' -Value @()
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'evidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateEvidencePath' -Value ''
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateCurrentHeadAuditEvidencePath' -Value ''
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateAuditStatus' -Value 'active_238_static_closed_r4_deferred'
Set-PropertyValue -Object $objective.executionTarget -Name 'currentIssue' -Value $issue238
Set-PropertyValue -Object $objective.executionTarget -Name 'nextIssues' -Value @()
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。238 已通过 237→238 静态转移门禁，现为唯一活动源码议题；静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'activeBoundary' -Value 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD 保持 verifying：NativeObject mContent 的失败见证、ArkWeb/标准 JSVM/Native JSVM/重复内嵌 helper 消费矩阵、20 项基础静态合同、13 项 current-head/source-fix 和 237→238 静态转移证据已登记；237 及旧议题仅等待 R4。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value '237→238 静态转移、注册后一致性和重放幂等门禁完成；下一 P0/P1 源码议题暂不选择，R4 deferred。'
$plan = @($objective.continuationPlan)
$plan | Where-Object { [string]$_.id -eq '238-OC-05' } | ForEach-Object { $_.status = 'completed'; Set-PropertyValue -Object $_ -Name 'evidence' -Value $GateEvidencePath }
if (@($plan | Where-Object { [string]$_.id -eq '238-OC-06' }).Count -eq 0) {
  $plan += @([pscustomobject][ordered]@{ id = '238-OC-06'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' })
}
Set-PropertyValue -Object $objective -Name 'continuationPlan' -Value $plan
Write-AtomicJson -RelativePath $objectiveRelative -Value $objective

Import-Module -Name (Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1') -Force
$state.governance.activeIssueId = $issue238
Write-LegadoStateCheckpoint -Path $statePath -State $state -Depth 40

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId $issue238 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'refactor objective attachment failed.' }

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_java_object_237_to_238_transition_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  previousIssueId = $issue237
  issueId = $issue238
  nextIssueId = ''
  gateEvidencePath = $GateEvidencePath
  targetEvidencePath = $TargetEvidencePath
  failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json'
  currentHeadEvidencePath = 'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json'
  sourceFixEvidencePath = 'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;238_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  idempotent = $true
}
Write-AtomicJson -RelativePath $RegistrationEvidencePath -Value $registration

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$evidence = @($TargetEvidencePath, $GateEvidencePath, $RegistrationEvidencePath, 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json', 'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json', 'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json', 'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json', 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json')
& $updateScript -StatePath $statePath -IssueId $issue238 -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '238 已通过 237→238 静态转移：NativeObject mContent 失败见证、三路径消费者矩阵、20 项基础合同、13 项 current-head/source-fix 和转移/注册证据均已登记；238 保持 verifying 仅等待 R4，下一源码议题暂不选择。' -EvidencePath ($evidence -join ',') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'governance state refresh failed.' }

$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
$objectiveDocument = $objectiveDocument.Replace('当前修订：`' + $revisionBefore + '`', '当前修订：`' + $revision + '`')
$objectiveDocument = $objectiveDocument.Replace('当前唯一活动源码锚点为 `ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS`，状态为 `verifying`；236 的 `:has` 源码阶段保持 `verifying` 并等待 R4；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`、`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 和其它已闭合议题均不重新打开，238 尚未激活。', '当前唯一活动源码锚点为 `ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD`，状态为 `verifying`；237 的索引伪类、236 的 `:has` 和其它已闭合议题均保持 `verifying` 并等待 R4，不重新打开或并行打补丁。')
$objectiveDocument = $objectiveDocument.Replace('在固定 458 条书源与 Legado 提交基线不变的前提下，继续推进 R2/R3 源码重构：237 的索引伪类边界保持 `verifying`，不重新打开；238 的独立失败 fixture、Legado 原理合同、ArkWeb/标准 JSVM/Native JSVM 及重复内嵌 helper 消费者矩阵、current-head 审计和 source-fix 已登记为 `candidate_gate_ready`，但 238 尚未成为活动议题。下一步只执行 237→238 静态转移、注册后一致性和重放幂等审计；转移前不得激活 238，不得并行修复第二根因。静态证据不得升级为运行时兼容；R4 的运行时、458 条 Harness、原版差分、构建、安装及真机验证继续延期。', '在固定 458 条书源与 Legado 提交基线不变的前提下，继续推进 R2/R3 源码重构：238 的对象内容重载源码边界保持 `verifying`，237、236 及其它已闭合议题不重新打开，仅等待 R4。238 的失败见证、消费者矩阵、current-head/source-fix、静态合同和 237→238 转移证据均已登记；下一步不选择新的源码根因，继续保留 R4 入口。静态证据不得升级为运行时兼容；R4 的运行时、458 条 Harness、原版差分、构建、安装及真机验证继续延期。')
$objectiveDocument = $objectiveDocument.Replace('当前 `238-OC-05` 只允许完成 237→238 静态转移、注册后一致性和重放幂等审计。机器事实继续保持 `237` 为唯一活动源码议题、`238=verifying` 候选，不启动 R4、真实网络、构建、安装、Android/HarmonyOS 设备或 Legado 运行时差分。', '238-OC-05 已完成 237→238 静态转移、注册后一致性和重放幂等前置登记，238 成为唯一活动源码议题并保持 `verifying`；238-OC-06 仅保留 R4 交接，不启动真实网络、构建、安装、Android/HarmonyOS 设备或 Legado 运行时差分。')
Write-AtomicText -RelativePath $objectiveDocumentPath -Value $objectiveDocument

$refreshedState = Read-StrictJson -RelativePath $stateRelative
$refreshedObjective = Read-StrictJson -RelativePath $objectiveRelative
Assert-Transition ([string]$refreshedState.governance.activeIssueId -eq $issue238) 'machine queue did not switch to 238.'
Assert-Transition ([string]$refreshedObjective.authority.activeIssueId -eq $issue238 -and [string]$refreshedObjective.executionTarget.currentIssue -eq $issue238 -and [string]$refreshedObjective.targetRevision -eq $revision) 'objective did not switch to 238.'
Write-Output ('TRANSITION_REGISTERED from={0} to={1} gate={2} target={3}' -f $issue237, $issue238, $GateEvidencePath, $TargetEvidencePath)
