[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors-pre-fix-20260809.json',
  [string]$CurrentHeadEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-current-head-audit-20260809.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-source-fix-20260809.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-index-pseudo-selectors.json',
  [string]$Target236Path = 'tools/legado-compat/evidence/r3-jsoup-has-236-target-20260809/target.json',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-has-236-to-index-237-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-has-236-to-index-237-transition-20260809/registration.json',
  [string]$Target237Path = 'tools/legado-compat/evidence/r3-jsoup-index-237-target-20260809/target.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

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
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) { if ([string]$issue.id -eq $Id) { return $issue } }
  return $null
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "236 to 237 transition blocked: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
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
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Invoke-GovernanceUpdate {
  param([string]$IssueId, [string]$Summary, [string[]]$Evidence)
  $updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
  & pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') -IssueId $IssueId -IssueStatus verifying -TaskId 'COMPAT-006' -Summary $Summary -EvidencePath ($Evidence -join ',') | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "governance update failed for $IssueId" }
}

$issue236 = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
$issue237 = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
$issue238 = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
$revisionBefore = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-has-pseudo-236-033'
$revision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-index-237-034'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'

$state = Read-StrictJson -RelativePath $statePath
$objective = Read-StrictJson -RelativePath $objectivePath
$registrationAbsolutePath = Get-RepoPath -RelativePath $RegistrationEvidencePath

if ([string]$state.governance.activeIssueId -eq $issue237 -and [string]$objective.targetRevision -eq $revision -and (Test-Path -LiteralPath $registrationAbsolutePath -PathType Leaf)) {
  [pscustomobject][ordered]@{ status = 'already_registered'; idempotent = $true; issueId = $issue237; nextIssueId = $issue238; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'static_registration_recovery_only;R4_runtime_build_device_and_legado_diff_deferred' } | ConvertTo-Json -Depth 20
  return
}

$target236 = Read-StrictJson -RelativePath $Target236Path
$preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
$currentHead = Read-StrictJson -RelativePath $CurrentHeadEvidencePath
$staticContract = Read-StrictJson -RelativePath $StaticContractPath
$sourceFix = Read-StrictJson -RelativePath $SourceFixPath
$fixture = Read-StrictJson -RelativePath $FixturePath

Assert-Transition ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issue236 -and [string]$state.governance.status -eq 'running') '236 is not the sole active queue anchor before transition.'
Assert-Transition ([string]$objective.targetRevision -eq $revisionBefore -and [string]$objective.authority.activeIssueId -eq $issue236 -and [string]$objective.executionTarget.currentIssue -eq $issue236) 'objective is not at the 236 transition boundary.'
Assert-Transition ([string]$target236.issueId -eq $issue236 -and [string]$target236.currentStatus -eq 'source_closed_static_only') '236 target is not static-closed.'
$issues = @($state.governance.issues)
$record236 = Get-Issue -Issues $issues -Id $issue236
$record237 = Get-Issue -Issues $issues -Id $issue237
Assert-Transition ($null -ne $record236 -and [string]$record236.status -eq 'verifying' -and $null -ne $record237 -and [string]$record237.status -eq 'verifying') '236/237 statuses are not verifying-only.'
Assert-Transition ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq $issue237 -and -not [bool]$preFix.semanticMatchAllowed) '237 failure witness is invalid.'
Assert-Transition ([string]$currentHead.status -eq 'passed' -and [int]$currentHead.assertions -eq 16 -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) '237 current-head audit is invalid.'
Assert-Transition ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 20) '237 static contract is invalid.'
Assert-Transition ([string]$sourceFix.status -eq 'source_closed_static_only' -and [string]$sourceFix.issueId -eq $issue237 -and -not [bool]$sourceFix.semanticMatchAllowed) '237 source-fix evidence is invalid.'
Assert-Transition (@($fixture.cases).Count -eq 6 -and [int]$sourceFix.staticImpact.ruleStringCount -eq 16 -and [int]$sourceFix.staticImpact.affectedSourceCount -eq 9) '237 fixture or impact set drifted.'
$legadoHead = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Transition ($legadoHead -eq $legadoCommit) 'Legado checkout is not pinned.'

$gateEvidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_has_236_to_index_237_transition_consistency'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fromIssue = $issue236
  toIssue = $issue237
  nextCandidateAfterRegistration = $issue238
  objectiveId = [string]$objective.objectiveId
  fromRevision = [string]$objective.targetRevision
  toRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  assertions = $script:assertions
  consumerMatrix = $currentHead.consumerMatrix
  evidencePaths = @($Target236Path, $PreFixEvidencePath, $StaticContractPath, $SourceFixPath, $CurrentHeadEvidencePath, $FixturePath)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_transition_only;237_becomes_verifying_source_anchor;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = '237 nth-of-type, eq and lt semantics match fixed Legado in six cases, affected sources, 458-source harness, differential, build and device R4.'
}
Write-AtomicJson -RelativePath $GateEvidencePath -Value $gateEvidence

$target237 = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_index_pseudo_selector_target'
  status = 'active'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  issueId = $issue237
  taskId = 'COMPAT-006'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  reasonForTarget = '236 静态闭合及注册后一致性已完成；237 的独立失败见证、六案例 fixture、16 条规则/9 条书源影响集合、三类消费者矩阵和 current-head/source-fix 证据已固定。'
  plan = @(
    [pscustomobject][ordered]@{ id = '237-IP-01'; status = 'completed'; action = '固定 Legado Jsoup 1.16.2 的 nth-of-type、eq、lt 语义和项目 HEAD 三路径缺失见证。'; completedEvidence = $PreFixEvidencePath },
    [pscustomobject][ordered]@{ id = '237-IP-02'; status = 'completed'; action = '登记 DOM Matcher、超大文档字符串回退、ArkWeb 和固定 Legado 的消费者矩阵。'; completedEvidence = $CurrentHeadEvidencePath },
    [pscustomobject][ordered]@{ id = '237-IP-03'; status = 'completed'; action = '执行 20 项静态合同、current-head 哈希审计并生成当前 source-fix evidence。'; completedEvidence = $SourceFixPath },
    [pscustomobject][ordered]@{ id = '237-IP-04'; status = 'completed'; action = '完成 236→237 专用静态转移登记，237 成为唯一活动源码议题。'; completedEvidence = $RegistrationEvidencePath },
    [pscustomobject][ordered]@{ id = '237-IP-05'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' }
  )
  currentSubstage = '237-IP-05'
  currentStatus = 'source_closed_static_only'
  sourceFixEvidencePath = $SourceFixPath
  currentHeadAuditEvidencePath = $CurrentHeadEvidencePath
  transitionEvidencePath = $GateEvidencePath
  constraints = [pscustomobject][ordered]@{ runtimeActionsPerformed = @(); semanticMatchAllowed = $false; forbidden = @('458 条运行时批次', '真实网络', '构建、安装、设备和 Legado 运行时差分') }
  nextAction = '237 源码静态闭合保持 verifying；R4 deferred。下一候选 238 必须先固定独立失败合同。'
}
Write-AtomicJson -RelativePath $Target237Path -Value $target237

$objective.targetRevision = $revision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '237 源码静态闭合、失败见证、current-head/source-fix 和 236→237 静态转移已登记并保持 verifying；R4 deferred。下一候选为 ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD，先固定独立失败合同和消费者矩阵，不启动 R4。'
Set-PropertyValue -Object $objective.authority -Name 'activeIssueId' -Value $issue237
Set-PropertyValue -Object $objective.authority -Name 'activeIssueSelection' -Value 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS is now the sole active source-closure issue after the passed 236→237 static transition gate. ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR remains verifying for deferred R4. ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.'
Set-PropertyValue -Object $objective.objective -Name 'activeIssue' -Value $issue237
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value '当前唯一活动源码议题为 ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS；已登记索引伪类失败见证、六案例/16 规则/9 书源影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、20 项静态合同、current-head 和 source-fix evidence，R4 仍延期。'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'status' -Value 'issue_selected_r3_index_pseudo_237'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'currentAnchor' -Value $issue237
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'selectedIssue' -Value $issue237
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateIssues' -Value @($issue238)
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'evidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'previousEvidencePath' -Value 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-to-has-236-transition-20260809/transition-consistency.json'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateEvidencePath' -Value $SourceFixPath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateCurrentHeadAuditEvidencePath' -Value $CurrentHeadEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateAuditStatus' -Value 'ready_237_static_closed_r4_deferred'
Set-PropertyValue -Object $objective.executionTarget -Name 'currentIssue' -Value $issue237
Set-PropertyValue -Object $objective.executionTarget -Name 'nextIssues' -Value @($issue238)
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。237 已通过 236→237 静态转移门禁，现为唯一活动源码议题；所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'activeBoundary' -Value 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS 保持 verifying：索引伪类失败见证、六案例/16 规则/9 书源影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、20 项静态合同、current-head 和 source-fix evidence 已登记；236 等旧议题仅等待 R4。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value '236→237 静态转移已通过并登记；下一候选为 ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD，必须先固定失败合同和消费者矩阵。'
$plan = @($objective.continuationPlan)
if (@($plan | Where-Object { [string]$_.id -eq '237-IP-01' }).Count -eq 0) {
  $plan += @(
    [pscustomobject][ordered]@{ id = '237-IP-01'; status = 'completed'; action = '固定 Legado Jsoup index pseudo 失败见证和六案例/16 规则/9 书源影响集合。'; evidence = $PreFixEvidencePath },
    [pscustomobject][ordered]@{ id = '237-IP-02'; status = 'completed'; action = '完成 DOM、字符串回退、ArkWeb、Legado 消费矩阵与 current-head 审计。'; evidence = $CurrentHeadEvidencePath },
    [pscustomobject][ordered]@{ id = '237-IP-03'; status = 'completed'; action = '生成当前 source-fix evidence 并通过 20 项静态合同。'; evidence = $SourceFixPath },
    [pscustomobject][ordered]@{ id = '237-IP-04'; status = 'completed'; action = '完成 236→237 专用静态转移登记，237 保持 verifying。'; evidence = $RegistrationEvidencePath },
    [pscustomobject][ordered]@{ id = '237-IP-05'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' }
  )
}
Set-PropertyValue -Object $objective -Name 'continuationPlan' -Value $plan
Write-AtomicJson -RelativePath $objectivePath -Value $objective

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript -StatePath (Get-RepoPath $statePath) -ObjectivePath (Get-RepoPath $objectivePath) -ActiveIssueId $issue237 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'refactor objective attachment failed.' }

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_has_236_to_index_237_transition_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  previousIssueId = $issue236
  issueId = $issue237
  nextIssueId = $issue238
  gateEvidencePath = $GateEvidencePath
  targetEvidencePath = $Target237Path
  failureWitnessPath = $PreFixEvidencePath
  currentHeadEvidencePath = $CurrentHeadEvidencePath
  currentSourceFixEvidencePath = $SourceFixPath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;237_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  idempotent = $true
}
Write-AtomicJson -RelativePath $RegistrationEvidencePath -Value $registration

$allEvidence = @($PreFixEvidencePath, $StaticContractPath, $FixturePath, $SourceFixPath, $CurrentHeadEvidencePath, $GateEvidencePath, $RegistrationEvidencePath, $Target237Path)
Invoke-GovernanceUpdate -IssueId $issue236 -Summary '236 源码静态闭合已完成并通过 236→237 静态转移；236 保持 verifying 等待 R4，237 已成为唯一活动源码议题。' -Evidence @($GateEvidencePath, $RegistrationEvidencePath)
Invoke-GovernanceUpdate -IssueId $issue237 -Summary '237 已通过 236→237 静态转移：失败见证、六案例/16 条规则/9 条书源影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、20 项静态合同、current-head/source-fix evidence 均已登记；R4 deferred。' -Evidence $allEvidence

$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
$objectiveDocument = $objectiveDocument.Replace('当前修订：`' + $revisionBefore + '`', '当前修订：`' + $revision + '`')
$objectiveDocument = $objectiveDocument.Replace('当前唯一活动源码锚点为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`，状态为 `verifying`；235 的文本伪类与空白规范化源码阶段保持 `verifying` 并等待 R4；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`、`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 和其它已闭合议题均不重新打开，237 尚未激活。', '当前唯一活动源码锚点为 `ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS`，状态为 `verifying`；236 的 `:has` 源码阶段保持 `verifying` 并等待 R4；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`、`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 和其它已闭合议题均不重新打开，238 尚未激活。')
$objectiveDocument = $objectiveDocument.Replace('236 的 `:has` 伪类失败合同、受影响规则集合、V2 全部消费者、current-head 静态审计和 235→236 转移门禁均已完成；236 保持 `verifying` 等待 R4，237 是下一候选且尚未激活。', '236 的 `:has` 伪类失败合同、受影响规则集合、V2 全部消费者、current-head 静态审计和 235→236 转移门禁均已完成；236 保持 `verifying` 等待 R4。237 的索引伪类失败见证、消费者矩阵、current-head/source-fix 和 236→237 转移已完成，237 成为当前唯一活动源码议题，238 是下一候选且尚未激活。')
$objectiveDocument = $objectiveDocument.Replace('当前子阶段：`236-HP-01` 至 `236-HP-05` 已完成失败见证、消费者矩阵、current-head/source-fix 审计、235→236 静态转移、注册后一致性和重启幂等审计；236 保持 `verifying`，R4 deferred，下一候选为 237。', '当前子阶段：`237-IP-01` 至 `237-IP-04` 已完成失败见证、消费者矩阵、current-head/source-fix 审计和 236→237 静态转移；237 保持 `verifying`，R4 deferred，下一候选为 238。')
$objectiveDocument = $objectiveDocument.Replace('236 的静态转移已完成：失败前见证基于项目 HEAD，当前消费者矩阵覆盖 DOM Matcher、字符串回退、ArkWeb 和固定 Legado；15 项静态合同与 current-head/source-fix evidence 已绑定 458 条基线。236 仍不得写成 passed 或 semantic_match，R4 运行时、构建、安装、设备和 Legado 差分延期。下一候选 237 必须先固定独立失败合同。', '236 的静态转移已完成并进入 R4 等待：失败前见证、消费者矩阵、15 项静态合同和 source-fix evidence 均不得写成 passed 或 semantic_match。')
$objectiveDocument += "`r`n`r`n### 237-IP-01 至 237-IP-05：Jsoup 索引伪类边界`r`n`r`n237 固定 Legado Jsoup 1.16.2 的 `:nth-of-type`、`:eq`、`:lt` 语义：同标签 1-based `an+b`、全元素兄弟 0-based index 和非法数字 fail-closed。六案例 fixture、16 条规则/9 条书源影响集合、DOM Matcher、超大文档字符串回退、ArkWeb 与 Legado 消费矩阵均已登记；当前 source-fix 与 236→237 转移只证明源码闭合，237 保持 `verifying`，R4 的运行时、458 条 Harness、Legado 差分、构建和真机验证延期。下一候选 238 必须先固定独立失败合同。"
Write-AtomicText -RelativePath $objectiveDocumentPath -Value $objectiveDocument

$governancePath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$governanceDocument = Read-StrictText -RelativePath $governancePath
$governanceDocument = $governanceDocument.Replace('`COMPAT-006` 当前唯一活动根因议题为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`，以 `full-source-validation-state.json` 的机器事实为准；235 的文本伪类与空白规范化、234、233、232、012、005 及既有 Harness/治理议题均保持 `verifying`，仅等待 R4，不重新打开或并行打补丁。236 的项目 HEAD 失败前见证、5 条书源/70 条规则影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、15 项静态合同和 current-head/source-fix 证据已绑定固定 458 条基线，但仍不得写成 `passed` 或 `semantic_match`。235→236 静态转移门禁已通过并登记；下一步只保留 236 的 R4 交接，237 尚未激活，也不启动 R4。R4 的 fresh `full_workflow`、458 条批次、Legado 差分、构建和真机验证仍未开启。', '`COMPAT-006` 当前唯一活动根因议题为 `ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS`，以 `full-source-validation-state.json` 的机器事实为准；236 的 `:has`、235 的文本伪类与空白规范化、234、233、232、012、005 及既有 Harness/治理议题均保持 `verifying`，仅等待 R4，不重新打开或并行打补丁。237 的项目 HEAD 失败见证、六案例/16 条规则/9 条书源影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、20 项静态合同和 current-head/source-fix 证据已绑定固定 458 条基线，但仍不得写成 `passed` 或 `semantic_match`。236→237 静态转移门禁已通过并登记；238 尚未激活，也不启动 R4。R4 的 fresh `full_workflow`、458 条批次、Legado 差分、构建和真机验证仍未开启。')
$governanceDocument = $governanceDocument.Replace('236 的注册脚本具备重启后幂等恢复：235 保持 `verifying` 等待 R4，236 原子保持唯一活动源码议题，237 保持下一候选；重放不会改变状态哈希或尝试次数，R4 运行时与 Legado 差分仍延期。注册后一致性审计 25 项断言和幂等合同 8 项断言均已登记。', '236→237 的注册脚本具备重启后幂等恢复：236 保持 `verifying` 等待 R4，237 原子保持唯一活动源码议题，238 保持下一候选；重放不会改变状态哈希或尝试次数，R4 运行时与 Legado 差分仍延期。237 的失败见证、current-head/source-fix 和静态转移证据均已登记。')
Write-AtomicText -RelativePath $governancePath -Value $governanceDocument

$registration = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_jsoup_has_236_to_index_237_transition_registration'; status = 'registered'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); objectiveId = [string]$objective.objectiveId; targetRevision = $revision; previousIssueId = $issue236; issueId = $issue237; nextIssueId = $issue238; gateEvidencePath = $GateEvidencePath; targetEvidencePath = $Target237Path; failureWitnessPath = $PreFixEvidencePath; currentHeadEvidencePath = $CurrentHeadEvidencePath; currentSourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_queue_transition_static_only;237_verifying;R4_runtime_build_device_and_legado_diff_deferred'; idempotent = $true }
Write-AtomicJson -RelativePath $RegistrationEvidencePath -Value $registration

[pscustomobject][ordered]@{ status = 'registered'; assertions = $script:assertions; previousIssueId = $issue236; issueId = $issue237; nextIssueId = $issue238; targetRevision = $revision; runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 20
