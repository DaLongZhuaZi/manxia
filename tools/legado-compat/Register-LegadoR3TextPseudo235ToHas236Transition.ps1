[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector-pre-fix-20260809-r2.json',
  [string]$CurrentHeadEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-current-head-audit-20260809-r2.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector.json',
  [string]$HistoricalSourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-source-fix-20260807.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-pseudo-selector.json',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-to-has-236-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-to-has-236-transition-20260809/registration.json',
  [string]$Target236Path = 'tools/legado-compat/evidence/r3-jsoup-has-236-target-20260809/target.json',
  [string]$CurrentSourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-source-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
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
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) } catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
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

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "235→236 static transition blocked: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $utf8NoBom)
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

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$target235Path = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json'
$issue235 = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
$issue236 = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
$issue237 = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
$revision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-has-pseudo-236-033'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

$state = Read-StrictJson -RelativePath $statePath
$objective = Read-StrictJson -RelativePath $objectivePath
$target235 = Read-StrictJson -RelativePath $target235Path
$preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
$currentHead = Read-StrictJson -RelativePath $CurrentHeadEvidencePath
$staticContract = Read-StrictJson -RelativePath $StaticContractPath
$historicalSourceFix = Read-StrictJson -RelativePath $HistoricalSourceFixPath
$fixture = Read-StrictJson -RelativePath $FixturePath

$registrationAbsolutePath = Get-RepoPath -RelativePath $RegistrationEvidencePath
$alreadyRegistered = [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and
  [string]$state.governance.activeIssueId -eq $issue236 -and
  [string]$objective.targetRevision -eq $revision -and
  [string]$objective.authority.activeIssueId -eq $issue236 -and
  (Test-Path -LiteralPath $registrationAbsolutePath -PathType Leaf)
if ($alreadyRegistered) {
  $auditScript = Join-Path $PSScriptRoot 'Test-LegadoR3TextPseudo235ToHas236PostRegistrationConsistency.ps1'
  if (-not (Test-Path -LiteralPath $auditScript -PathType Leaf)) {
    throw 'post-registration consistency audit script is missing.'
  }
  $auditOutput = & $auditScript -RepositoryRoot $RepositoryRoot -RunId 'r3-jsoup-text-pseudo-235-to-has-236-transition-replay-20260809'
  $auditSucceeded = $?
  if (-not $auditSucceeded) { throw 'post-registration consistency audit failed during idempotent replay.' }
  [pscustomobject][ordered]@{
    status = 'already_registered'
    idempotent = $true
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    previousIssueId = $issue235
    issueId = $issue236
    nextIssueId = $issue237
    postRegistrationAuditRunId = 'r3-jsoup-text-pseudo-235-to-has-236-transition-replay-20260809'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_registration_recovery_only;R4_runtime_build_device_and_legado_diff_deferred'
  } | ConvertTo-Json -Depth 20
  return
}

Assert-Transition ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issue235 -and [string]$state.governance.status -eq 'running') '235 is not the sole active queue anchor before transition.'
Assert-Transition ([string]$target235.currentSubstage -eq '235-TRANSITION-PRECHECK' -and [string]$target235.staticAuditStatus -eq 'passed_static_only') '235 WS-04 static closure is not registered.'
Assert-Transition ([string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-whitespace-235-032' -and [string]$objective.nextAction -like '审核 235→236*') 'objective is not at the 235 transition precheck.'

$issues = @($state.governance.issues)
$issue235Record = $issues | Where-Object { [string]$_.id -eq $issue235 } | Select-Object -First 1
$issue236Record = $issues | Where-Object { [string]$_.id -eq $issue236 } | Select-Object -First 1
Assert-Transition ($null -ne $issue235Record -and [string]$issue235Record.status -eq 'verifying' -and $null -ne $issue236Record -and [string]$issue236Record.status -eq 'verifying') '235/236 issue statuses are not both verifying.'
Assert-Transition ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq $issue236 -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) '236 failed-before witness is not static-only.'
Assert-Transition ([string]$currentHead.status -eq 'passed' -and [int]$currentHead.assertions -eq 10 -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) '236 current-head audit is not the expected static-only pass.'
Assert-Transition ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 15) '236 static contract is not the expected 15-assertion pass.'
Assert-Transition ([string]$historicalSourceFix.issueId -eq $issue236 -and -not [bool]$historicalSourceFix.semanticMatchAllowed) 'historical 236 source-fix evidence is not bound to issue 236.'
Assert-Transition ([int]$fixture.cases.Count -eq 5 -and [int]$historicalSourceFix.staticImpact.hasRuleStringCount -eq 70 -and [int]$historicalSourceFix.staticImpact.affectedSourceCount -eq 5) '236 fixture and affected set drifted.'

$legadoPath = Get-RepoPath -RelativePath 'legado'
$legadoHead = (& git -C $legadoPath rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Transition ($legadoHead -eq $legadoCommit) 'Legado checkout is not at the pinned commit.'
$legadoSource = Read-StrictText -RelativePath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
Assert-Transition ($legadoSource.Contains('temp.select(ruleStr)') -and $legadoSource.Contains('element.text()') -and $legadoSource.Contains('element.ownText()')) 'fixed Legado selector/text handoff is not present.'

$consumerMatrix = @(
  [pscustomobject][ordered]@{ id = 'dom_matcher'; path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; semantics = @(':has(descendant)', ':has(>direct-child)', 'nested pseudo', 'wildcard'); evidence = 'pseudo.name === has;querySelectorAll;argument.startsWith(>)' },
  [pscustomobject][ordered]@{ id = 'string_fallback'; path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; semantics = @(':has(descendant)', ':has(>direct-child)', 'nested pseudo', 'wildcard'); evidence = 'matchesStringHasPseudo;findDirectChildren(innerHtml)' },
  [pscustomobject][ordered]@{ id = 'arkweb'; path = 'entry/src/main/resources/rawfile/legado_runtime.html'; semantics = @(':has(descendant)', ':has(>direct-child)', 'nested pseudo', 'wildcard'); evidence = 'name === has;relativeSelector;legadoSelectWithJsoupRegex(node)' },
  [pscustomobject][ordered]@{ id = 'legado_reference'; path = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'; semantics = @('Jsoup Element.select', 'Element.text', 'Element.ownText'); evidence = 'temp.select(ruleStr);element.text();element.ownText()' }
)
Assert-Transition ($consumerMatrix.Count -eq 4) 'consumer matrix is incomplete.'
Assert-Transition (@($consumerMatrix | Where-Object { $_.id -eq 'dom_matcher' }).Count -eq 1 -and @($consumerMatrix | Where-Object { $_.id -eq 'string_fallback' }).Count -eq 1 -and @($consumerMatrix | Where-Object { $_.id -eq 'arkweb' }).Count -eq 1 -and @($consumerMatrix | Where-Object { $_.id -eq 'legado_reference' }).Count -eq 1) 'consumer matrix does not cover DOM, string, ArkWeb and Legado.'

$sourceHashes = [ordered]@{}
foreach ($path in @($currentHead.changedPaths)) {
  $sourceHashes[[string]$path] = [string](Get-PropertyValue -Object $currentHead.currentHeadHashes -Name ([string]$path) -Default '')
  Assert-Transition ($sourceHashes[[string]$path].Length -eq 64) ('current-head hash missing for ' + [string]$path)
}

$currentSourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_has_pseudo_selector_source_fix'
  issueId = $issue236
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  staticImpact = [pscustomobject][ordered]@{ hasRuleStringCount = 70; affectedSourceCount = 5 }
  failureEvidence = @($PreFixEvidencePath)
  staticContract = $StaticContractPath
  currentHeadAudit = $CurrentHeadEvidencePath
  changedPaths = @($currentHead.changedPaths)
  currentHeadHashes = $sourceHashes
  consumerMatrix = $consumerMatrix
  rootCause = 'Legado delegates :has(selector) to Jsoup Element.select. V2 now projects the same descendant/direct-child/nested/wildcard predicate through DOM Matcher, complete-element string fallback and ArkWeb bridge; all static consumers are explicitly registered.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_236_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  followUp = 'R4 must compare all five fixture cases and affected source set against Legado before semantic_match or passed.'
}
Write-AtomicJson -RelativePath $CurrentSourceFixPath -Value $currentSourceFix

$gate = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_text_pseudo_235_to_has_236_transition_consistency'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fromIssue = $issue235
  toIssue = $issue236
  nextCandidateAfterRegistration = $issue237
  objectiveId = [string]$objective.objectiveId
  fromRevision = [string]$objective.targetRevision
  toRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  assertions = $script:assertions
  consumerMatrix = $consumerMatrix
  evidencePaths = @($target235Path, $PreFixEvidencePath, $StaticContractPath, $HistoricalSourceFixPath, $CurrentSourceFixPath, $CurrentHeadEvidencePath, $FixturePath)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_transition_only;236_becomes_verifying_source_anchor;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = '236 :has descendant/direct-child/nested/wildcard semantics match fixed Legado in affected sources, 458-source harness, differential, build and device R4.'
}
Write-AtomicJson -RelativePath $GateEvidencePath -Value $gate

$target235.status = 'completed_static_only'
Set-PropertyValue -Object $target235 -Name 'transitionEvidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $target235 -Name 'nextIssueId' -Value $issue236
Set-PropertyValue -Object $target235 -Name 'lastUpdatedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Write-AtomicJson -RelativePath $target235Path -Value $target235

$target236 = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_has_pseudo_selector_target'
  status = 'active'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  issueId = $issue236
  taskId = 'COMPAT-006'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  basis = [pscustomobject][ordered]@{
    documents = @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')
    legadoImplementation = @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
    v2Consumers = @($currentHead.changedPaths)
  }
  reasonForTarget = '235→236 静态转移前置条件已满足：236 独立失败见证、5 条书源/70 条规则影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵和 current-head 哈希均已登记。'
  plan = @(
    [pscustomobject][ordered]@{ id = '236-WS-01'; status = 'completed'; action = '固定项目 HEAD 缺失 :has 的失败前见证和 Legado Jsoup selector/text handoff。'; completedEvidence = $PreFixEvidencePath },
    [pscustomobject][ordered]@{ id = '236-WS-02'; status = 'completed'; action = '登记 DOM、字符串回退、ArkWeb 和 Legado 四类消费者矩阵。'; completedEvidence = $GateEvidencePath },
    [pscustomobject][ordered]@{ id = '236-WS-03'; status = 'completed'; action = '完成 15 项静态合同和 current-head 哈希审计，生成当前 source-fix evidence。'; completedEvidence = $CurrentSourceFixPath },
    [pscustomobject][ordered]@{ id = '236-WS-04'; status = 'completed'; action = '完成 235→236 专用静态转移登记，236 成为唯一活动源码议题。'; completedEvidence = $RegistrationEvidencePath },
    [pscustomobject][ordered]@{ id = '236-WS-05'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' }
  )
  currentSubstage = '236-WS-05'
  currentStatus = 'source_closed_static_only'
  sourceFixEvidencePath = $CurrentSourceFixPath
  currentHeadAuditEvidencePath = $CurrentHeadEvidencePath
  transitionEvidencePath = $GateEvidencePath
  constraints = [pscustomobject][ordered]@{ runtimeActionsPerformed = @(); semanticMatchAllowed = $false; forbidden = @('458 条运行时批次', '真实网络', '构建、安装、设备和 Legado 运行时差分') }
  nextAction = '236 源码静态闭合保持 verifying；R4 deferred。下一候选 237 只有在 236 的静态证据链稳定后才可固定独立失败合同。'
}
Write-AtomicJson -RelativePath $Target236Path -Value $target236

$objective.targetRevision = $revision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '236 源码静态闭合已登记并保持 verifying；R4 deferred。下一候选为 ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS，先固定独立失败合同和消费者矩阵，不启动 R4。'
Set-PropertyValue -Object $objective.authority -Name 'activeIssueId' -Value $issue236
Set-PropertyValue -Object $objective.authority -Name 'activeIssueSelection' -Value 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR is now the sole active source-closure issue after the passed 235→236 static transition gate. ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS remains verifying for deferred R4. ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.'
Set-PropertyValue -Object $objective.objective -Name 'activeIssue' -Value $issue236
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value '当前唯一活动源码议题为 ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR；已登记 :has 的失败前、DOM/字符串回退/ArkWeb/Legado 消费者矩阵、15 项静态合同、current-head 和 source-fix evidence，R4 仍延期。'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'status' -Value 'issue_selected_r3_has_pseudo_236'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'currentAnchor' -Value $issue236
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'selectedIssue' -Value $issue236
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateIssues' -Value @($issue237)
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'evidencePath' -Value $GateEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateEvidencePath' -Value $CurrentSourceFixPath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateCurrentHeadAuditEvidencePath' -Value $CurrentHeadEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'candidateAuditStatus' -Value 'ready_236_static_closed_r4_deferred'
Set-PropertyValue -Object $objective.executionTarget -Name 'currentIssue' -Value $issue236
Set-PropertyValue -Object $objective.executionTarget -Name 'nextIssues' -Value @($issue237)
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。236 已通过 235→236 静态转移门禁，现为唯一活动源码议题；所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'activeBoundary' -Value 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR 保持 verifying：:has 的失败前见证、DOM/字符串回退/ArkWeb/Legado 消费矩阵、15 项静态合同、current-head 和 source-fix evidence 已登记；235 等旧议题仅等待 R4。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value '235→236 静态转移已通过并登记；下一候选为 ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS，必须先固定失败合同和 current-head 审计。'
$plan = @($objective.continuationPlan)
$plan += @(
  [pscustomobject][ordered]@{ id = '236-HP-01'; status = 'completed'; action = '固定项目 HEAD 缺失 :has 的失败前见证、Legado Jsoup selector/text handoff 和 5 案例/70 规则影响集合。'; evidence = $PreFixEvidencePath },
  [pscustomobject][ordered]@{ id = '236-HP-02'; status = 'completed'; action = '完成 DOM、字符串回退、ArkWeb 和 Legado 消费矩阵与 current-head 哈希审计。'; evidence = $CurrentHeadEvidencePath },
  [pscustomobject][ordered]@{ id = '236-HP-03'; status = 'completed'; action = '生成当前 source-fix evidence 并通过 235→236 静态转移门禁；236 保持 verifying。'; evidence = $GateEvidencePath },
  [pscustomobject][ordered]@{ id = '236-HP-04'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' }
)
Set-PropertyValue -Object $objective -Name 'continuationPlan' -Value $plan
Write-AtomicJson -RelativePath $objectivePath -Value $objective

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath (Get-RepoPath -RelativePath $statePath) -ObjectivePath (Get-RepoPath -RelativePath $objectivePath) -ActiveIssueId $issue236 | Out-Null
if (-not $?) { throw 'refactor objective attachment failed.' }

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_text_pseudo_235_to_has_236_transition_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $revision
  previousIssueId = $issue235
  issueId = $issue236
  nextIssueId = $issue237
  gateEvidencePath = $GateEvidencePath
  targetEvidencePath = $Target236Path
  currentSourceFixEvidencePath = $CurrentSourceFixPath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;236_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  idempotent = $true
}
Write-AtomicJson -RelativePath $RegistrationEvidencePath -Value $registration

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
$evidence = @($PreFixEvidencePath, $StaticContractPath, $FixturePath, $HistoricalSourceFixPath, $CurrentHeadEvidencePath, $CurrentSourceFixPath, $GateEvidencePath, $RegistrationEvidencePath, $Target236Path)
& $updateScript -StatePath (Get-RepoPath -RelativePath $statePath) -IssueId $issue236 -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '236 已通过 235→236 静态转移：项目 HEAD 缺失 :has 的失败前见证、5 条书源/70 条规则影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、15 项静态合同和 current-head/source-fix 证据均已登记；R4 延期。' -EvidencePath ($evidence -join ',') | Out-Null
if (-not $?) { throw 'governance state refresh failed.' }

$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
$objectiveDocument = $objectiveDocument.Replace('当前修订：`2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-whitespace-235-032`', '当前修订：`' + $revision + '`')
$oldActiveLine = '当前唯一活动源码锚点为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，状态为 `verifying`；当前 235-TP-03 细化为 Jsoup `text()`/`ownText()` 空白规范化源码目标，统一 DOM、字符串回退和 ArkWeb；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR` 与 `ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 保持 `verifying` 并等待 R4，236 仍未激活。'
$newActiveLine = '当前唯一活动源码锚点为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`，状态为 `verifying`；235 的文本伪类与空白规范化源码阶段保持 `verifying` 并等待 R4；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`、`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 和其它已闭合议题均不重新打开，237 尚未激活。'
$objectiveDocument = $objectiveDocument.Replace($oldActiveLine, $newActiveLine)
$oldSubstage = '`235-WS-04` 静态证据与文档审计已完成；唯一下一步为 235→236 静态转移前置门禁，236 尚未激活。'
$newSubstage = '`236-HP-01` 至 `236-HP-03` 已完成失败见证、消费者矩阵、current-head/source-fix 审计与 235→236 静态转移；236 保持 `verifying`，R4 deferred，下一候选为 237。'
$objectiveDocument = $objectiveDocument.Replace($oldSubstage, $newSubstage)
$insertMarker = '## 单议题执行规则'
if (-not $objectiveDocument.Contains('### 236-HP-01 细化目标：Jsoup :has 伪类')) {
  $section = "### 236-HP-01 细化目标：Jsoup :has 伪类`r`n`r`n236 的静态转移已完成：失败前见证基于项目 HEAD，当前消费者矩阵覆盖 DOM Matcher、字符串回退、ArkWeb 和固定 Legado；15 项静态合同与 current-head/source-fix evidence 已绑定 458 条基线。236 仍不得写成 `passed` 或 `semantic_match`，R4 运行时、构建、安装、设备和 Legado 差分延期。下一候选 237 必须先固定独立失败合同。`r`n`r`n"
  $objectiveDocument = $objectiveDocument.Replace($insertMarker, $section + $insertMarker)
}
Write-AtomicText -RelativePath $objectiveDocumentPath -Value $objectiveDocument

$governancePath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$governanceDocument = Read-StrictText -RelativePath $governancePath
$oldNarrative = '`COMPAT-006` 当前唯一活动根因议题为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，以 `full-source-validation-state.json` 的机器事实为准；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`、`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION`、`ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR`、`ISSUE-COMPAT-012`、`ISSUE-COMPAT-005`、`V2-HARNESS-023`、`ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`、`ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT` 和 `V2-GOV-004-DOCUMENT-TASK-MIRROR` 均保持 `verifying`，仅等待 R4，不重新打开或并行打补丁。234 的嵌套属性正则边界与 235 的文本伪类 8 案例/19 项静态合同、source-fix、WS-04 静态审计和 current-head 证据均绑定固定 458 条基线，但仍不得写成 `passed` 或 `semantic_match`。234→235 静态转移门禁已通过 26 项断言并登记；235-WS-01 至 235-WS-04 已静态闭合，下一步只审核 235→236 静态转移前置条件，236 尚未激活，也不启动 R4。R4 的 fresh `full_workflow`、458 条批次、Legado 差分、构建和真机验证仍未开启。'
$newNarrative = '`COMPAT-006` 当前唯一活动根因议题为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`，以 `full-source-validation-state.json` 的机器事实为准；235 的文本伪类与空白规范化、234、233、232、012、005 及既有 Harness/治理议题均保持 `verifying`，仅等待 R4，不重新打开或并行打补丁。236 的项目 HEAD 失败前见证、5 条书源/70 条规则影响集合、DOM/字符串回退/ArkWeb/Legado 消费矩阵、15 项静态合同和 current-head/source-fix 证据已绑定固定 458 条基线，但仍不得写成 `passed` 或 `semantic_match`。235→236 静态转移门禁已通过并登记；下一步只保留 236 的 R4 交接，237 尚未激活，也不启动 R4。R4 的 fresh `full_workflow`、458 条批次、Legado 差分、构建和真机验证仍未开启。'
$governanceDocument = $governanceDocument.Replace($oldNarrative, $newNarrative)
Write-AtomicText -RelativePath $governancePath -Value $governanceDocument

$refreshedState = Read-StrictJson -RelativePath $statePath
$refreshedObjective = Read-StrictJson -RelativePath $objectivePath
$refreshedTarget = Read-StrictJson -RelativePath $Target236Path
$refreshedIssue = @($refreshedState.governance.issues | Where-Object { [string]$_.id -eq $issue236 }) | Select-Object -First 1
Assert-Transition ([string]$refreshedState.governance.activeIssueId -eq $issue236 -and [string]$refreshedIssue.status -eq 'verifying' -and @($refreshedIssue.evidencePaths) -contains $RegistrationEvidencePath) 'machine queue did not atomically switch to 236.'
Assert-Transition ([string]$refreshedObjective.authority.activeIssueId -eq $issue236 -and [string]$refreshedObjective.executionTarget.currentIssue -eq $issue236 -and [string]$refreshedObjective.targetRevision -eq $revision) 'objective did not switch to revision 033/236.'
Assert-Transition ([string]$refreshedTarget.status -eq 'active' -and [string]$refreshedTarget.issueId -eq $issue236 -and [string]$refreshedTarget.currentSubstage -eq '236-WS-05') '236 target is not active with R4 deferred.'
Assert-Transition ((Read-StrictText -RelativePath $objectiveDocumentPath).Contains($revision) -and (Read-StrictText -RelativePath $objectiveDocumentPath).Contains('ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR')) 'objective document did not refresh to 236.'
Assert-Transition ((Read-StrictText -RelativePath $governancePath).Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`')) 'governance narrative did not refresh to 236.'
Write-Output ('TRANSITION_REGISTERED from={0} to={1} next={2} gate={3} target={4}' -f $issue235, $issue236, $issue237, $GateEvidencePath, $Target236Path)
