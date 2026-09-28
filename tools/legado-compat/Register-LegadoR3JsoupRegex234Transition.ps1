[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreTransitionEvidencePath = 'tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-pre-transition-20260808/transition-consistency.json',
  [string]$PostTransitionEvidencePath = 'tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-post-transition-20260808/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-post-transition-20260808/registration.json',
  [string]$NextIssueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS',
  [string]$TargetRevision = '2026-08-08-actual-docs-source-refactor-continuation-jsoup-regex-234-029'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue $issue 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "233 to 234 registration blocked: $Message" }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Write-ObjectiveDocument {
  param([string]$Revision)
  $relativePath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $path = Get-RepoPath -RelativePath $relativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'Objective Markdown contains a UTF-8 BOM.' }
  $document = $strictUtf8.GetString($bytes)
  $oldRevision = '2026-08-08-actual-docs-source-refactor-continuation-java-233-028'
  $oldRevisionLine = '当前修订：`' + $oldRevision + '`  '
  Assert-Transition ($document.Contains($oldRevisionLine)) 'objective Markdown does not contain the expected 028 revision.'
  $document = $document.Replace($oldRevisionLine, "当前修订：`$Revision`  ")

  $newline = if ($document.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = $document -split "`r?`n", -1
  $activeIndexes = @()
  $historyIndexes = @()
  $candidateIndexes = @()
  foreach ($index in 0..($lines.Count - 1)) {
    if ($lines[$index].StartsWith('当前唯一活动源码锚点为 ')) { $activeIndexes += $index }
    if ($lines[$index].StartsWith('012 的当前源码证据已经完成登记。')) { $historyIndexes += $index }
    if ($lines[$index].StartsWith('234 作为下一候选尚未激活；')) { $candidateIndexes += $index }
  }
  Assert-Transition ($activeIndexes.Count -eq 1) 'objective Markdown active-issue line is not unique.'
  Assert-Transition ($historyIndexes.Count -eq 1) 'objective Markdown evidence-boundary line is missing.'
  Assert-Transition ($candidateIndexes.Count -eq 1) 'objective Markdown 234 candidate line is missing.'

  $lines[$activeIndexes[0]] = '当前唯一活动源码锚点为 `ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`，状态为 `verifying`；`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 保持 `verifying` 并等待 R4，232、012、005 及既有 Harness/治理议题不重新打开。233→234 专用静态转移门禁已通过 25 项断言，证据为 `tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-post-transition-20260808/transition-consistency.json`；下一候选唯一为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`。'
  $lines[$historyIndexes[0]] = '012 的当前源码证据已经完成登记；233 的 CSS/List 组合与替换顺序证据链已保留，234 的 ~= 属性正则选择器失败前合同、源码修复、13 项静态合同和 current-head 审计也已登记。上述证据均绑定固定 458 条基线，只证明源码闭合，不能提升为 `passed` 或 `semantic_match`；R4 运行时与 Legado 差分仍延期。'
  $lines[$candidateIndexes[0]] = '235 作为下一候选尚未激活；它必须先固定文本伪类的失败合同、受影响规则集合、V2 全部消费者和 current-head 静态审计，再通过专用静态转移门禁。'
  $insertAfter = $candidateIndexes[0]
  $lines = @($lines[0..$insertAfter] + @('234 的源码边界是固定 Legado Jsoup `[attr~=regex]` 语义在 Matcher、超大文档字符串回退、ArkWeb `java.getString/getStringList` 和 Java 内联正则标志之间的一致实现；冻结包影响为 139 个属性正则字符串、至少 51 条书源、4 个内联标志值/2 条书源。当前 234 仅有失败前、源码、13 项静态合同和 current-head 证据，仍不得进入 R4。') + $lines[($insertAfter + 1)..($lines.Count - 1)])
  $updated = [string]::Join($newline, $lines)
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, $updated, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $path -Force
}

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$preEvidence = Read-StrictJson -RelativePath $PreTransitionEvidencePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$baseline = $state.baseline
Assert-Transition ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'

# A transition script can be resumed after a process or machine restart. If
# the post-transition state is already authoritative, validate the existing
# evidence and return without incrementing attempts or rewriting the queue.
$alreadyRegistered = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
  [string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
  [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
if ($alreadyRegistered) {
  $existingPostEvidence = Read-StrictJson -RelativePath $PostTransitionEvidencePath
  $existingRegistration = Read-StrictJson -RelativePath $RegistrationEvidencePath
  Assert-Transition ([string]$existingPostEvidence.status -eq 'passed' -and
    [string]$existingPostEvidence.transition.fromIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and
    [string]$existingPostEvidence.transition.toIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
    [string]$existingPostEvidence.transition.nextCandidate -eq $NextIssueId -and
    -not [bool]$existingPostEvidence.semanticMatchAllowed -and
    @($existingPostEvidence.runtimeActionsPerformed).Count -eq 0) 'existing post-transition evidence is not a static-only 233→234 pass.'
  Assert-Transition ([string]$existingRegistration.status -eq 'registered' -and
    [string]$existingRegistration.previousIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and
    [string]$existingRegistration.issueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
    [string]$existingRegistration.nextIssueId -eq $NextIssueId -and
    -not [bool]$existingRegistration.semanticMatchAllowed -and
    @($existingRegistration.runtimeActionsPerformed).Count -eq 0) 'existing registration evidence is incomplete.'
  $existingIssues = @($state.governance.issues)
  $existing233 = Get-Issue -Issues $existingIssues -Id 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  $existing234 = Get-Issue -Issues $existingIssues -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  $existing235 = Get-Issue -Issues $existingIssues -Id $NextIssueId
  Assert-Transition ($null -ne $existing233 -and [string]$existing233.status -eq 'verifying' -and
    $null -ne $existing234 -and [string]$existing234.status -eq 'verifying' -and
    $null -ne $existing235 -and [string]$existing235.status -eq 'verifying') 'existing queue statuses are inconsistent.'
  [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_string_list_233_to_jsoup_regex_234_transition_registration'
    status = 'already_registered'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    previousIssueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    nextIssueId = $NextIssueId
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    postTransitionEvidencePath = $PostTransitionEvidencePath
    registrationEvidencePath = $RegistrationEvidencePath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
    idempotent = $true
  } | ConvertTo-Json -Depth 20
  return
}

Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'machine queue is not pre-transition 233.'
Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') 'objective is not pre-transition 233.'
Assert-Transition ([string]$preEvidence.status -eq 'passed' -and [string]$preEvidence.transition.fromIssue -eq 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION' -and [string]$preEvidence.transition.toIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and [string]$preEvidence.transition.nextCandidate -eq $NextIssueId -and -not [bool]$preEvidence.semanticMatchAllowed -and @($preEvidence.runtimeActionsPerformed).Count -eq 0) '233→234 pre-transition gate is not a passed static-only gate.'

$issues = @($state.governance.issues)
$issue233 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
$issue234 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
$issue235 = Get-Issue -Issues $issues -Id $NextIssueId
Assert-Transition ($null -ne $issue233 -and [string]$issue233.status -eq 'verifying') '233 must remain verifying.'
Assert-Transition ($null -ne $issue234 -and [string]$issue234.status -eq 'verifying') '234 must remain verifying.'
Assert-Transition ($null -ne $issue235 -and [string]$issue235.status -eq 'verifying') '235 must be an existing verifying candidate.'

$objective.targetRevision = $TargetRevision
$objective.authority | Add-Member -NotePropertyName 'activeIssueId' -NotePropertyValue 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -Force
$objective.authority | Add-Member -NotePropertyName 'activeIssueSelection' -NotePropertyValue 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR is now the sole active source-closure issue after the passed 233→234 static transition gate. ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION remains verifying for deferred R4. ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.' -Force
$objective.objective | Add-Member -NotePropertyName 'latestStaticClosure' -NotePropertyValue 'ISSUE-COMPAT-234 的 ~= 属性正则选择器边界已补齐失败前见证、源码修复、13 项静态合同和 current-head 哈希审计；影响为 139 个属性正则字符串、至少 51 条书源和 4 个 Java 内联标志值。全部证据仍是源码静态证据，不能提升为 semantic_match。' -Force
$objective.objective | Add-Member -NotePropertyName 'activeIssue' -NotePropertyValue 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -Force
$objective.objective | Add-Member -NotePropertyName 'activeIssueRule' -NotePropertyValue 'R2/R3 源码队列已从 ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION 原子切换到 ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR。当前治理 Matcher、字符串回退和 ArkWeb runtime 的 Jsoup ~= 属性正则、嵌套字符类、Java 内联标志和多属性谓词；234 的失败前合同、源码修复、13 项静态合同和 current-head 审计已登记，但 R4 运行时与 Legado 差分仍延期。' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'currentAnchor' -NotePropertyValue 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectedIssue' -NotePropertyValue 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateIssues' -NotePropertyValue @($NextIssueId) -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'evidencePath' -NotePropertyValue $PostTransitionEvidencePath -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'previousEvidencePath' -NotePropertyValue $PreTransitionEvidencePath -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateEvidencePath' -NotePropertyValue 'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateAuditStatus' -NotePropertyValue 'needs_failure_contract_and_current_head_static_audit' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateCurrentHeadAuditEvidencePath' -NotePropertyValue '' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateHistoricalDriftEvidencePath' -NotePropertyValue '' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'postTransitionEvidencePath' -NotePropertyValue $PostTransitionEvidencePath -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectionRule' -NotePropertyValue 'Prior verifying issues remain deferred to R4. 234 is selected only because its failed-before ~= witness, source fix, 13-assertion contract, 139/51/4/2 frozen impact and current-head audit are registered, and the 233→234 transition gate passed. ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS is the next candidate and must pass its own failure-contract gate. No second root cause is activated in parallel.' -Force
$sourceOrder = @($objective.objective.sourceClosureOrder)
if ($sourceOrder -notcontains $NextIssueId) { $sourceOrder += $NextIssueId }
$objective.objective | Add-Member -NotePropertyName 'sourceClosureOrder' -NotePropertyValue $sourceOrder -Force

$objective.executionTarget | Add-Member -NotePropertyName 'currentIssue' -NotePropertyValue 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -Force
$objective.executionTarget | Add-Member -NotePropertyName 'nextIssues' -NotePropertyValue @($NextIssueId) -Force
$objective.executionTarget | Add-Member -NotePropertyName 'statement' -NotePropertyValue '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。234 已通过 233→234 静态队列转移门禁，现为唯一活动源码议题；235 是下一候选。所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。' -Force
$protocol = @($objective.executionTarget.issueProtocol)
if ($protocol.Count -ge 4) { $protocol[3] = '队列核对完成后才可原子选择下一个 planned P0/P1 源码议题；014、015、V2-HARNESS-023、228、230、V2-GOV-004、ISSUE-COMPAT-CRYPTO-002、ISSUE-COMPAT-005、ISSUE-COMPAT-012、ISSUE-COMPAT-231、ISSUE-COMPAT-232 和 ISSUE-COMPAT-233 的源码证据已登记并保持 verifying 仅等待 R4；当前唯一活动源码议题为 ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR，ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS 只作为下一候选，必须先通过独立失败合同和 234→235 静态转移门禁。源码静态通过不得写成 passed 或 semantic_match；所有 runtime-verification-pending 项保持原状态，直到 R4 的 fresh full_workflow 和后置回归满足其关闭条件' }
$objective.executionTarget | Add-Member -NotePropertyName 'issueProtocol' -NotePropertyValue $protocol -Force
$criteria = @($objective.executionTarget.exitCriteria)
if ($criteria.Count -ge 4) {
  $criteria[1] = 'ISSUE-COMPAT-234 完成 ~= 属性正则选择器的失败前、源码和静态证据：固定 Legado AnalyzeByJSoup 语义、139 个规则字符串/至少 51 条书源、Matcher/字符串回退/ArkWeb 的调用路径、嵌套字符类、Java 内联标志和多属性谓词均有可追踪结果，禁止静默空值'
  $criteria[2] = '完成 ISSUE-COMPAT-234 的 source-closure 证据与 234→235 静态转移一致性门禁；235 只有在文本伪类的失败合同、受影响集合、V2 消费者和 current-head 审计齐全后才能成为唯一活动议题。所有已闭合源码议题保持 verifying 仅等待 R4，每个选中议题均有失败前、源码修复、静态契约和结构化拒绝证据，新的主因不得与当前议题并行'
  $criteria[3] = '当前源码队列中的每个议题均有失败前证据、源码证据和静态证据，或有结构化拒绝；234 与 235 的选择器证据、full-source-validation-state.json 的活动锚点和候选队列保持一致'
}
$objective.executionTarget | Add-Member -NotePropertyName 'exitCriteria' -NotePropertyValue $criteria -Force
$objective.continuationTarget | Add-Member -NotePropertyName 'activeBoundary' -NotePropertyValue 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR 保持 verifying：冻结 HEAD 的 ~= 属性正则失败前合同、源码修复、13 项静态合同、139/51/4/2 影响矩阵和 current-head 审计均已登记；233 与 234 的静态证据均不代表运行时兼容，R4 仍延期。' -Force
$objective.continuationTarget | Add-Member -NotePropertyName 'nextTransition' -NotePropertyValue '233→234 队列转移一致性门禁已通过并将 post transition path 绑定到 234；下一候选为 ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS。新议题必须先固定失败合同，再跨 Matcher、Rule Analyzer、ArkWeb、JSVM 和输出路径修复。' -Force
$objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue '以 ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR 为唯一活动源码议题：核对固定 Legado Jsoup ~= 属性正则语义、139 个规则字符串/至少 51 条书源影响集合和 V2 全部消费者，先维护失败合同，再完成 Matcher、字符串回退、ArkWeb 和 Java 内联标志的源码闭合；随后登记静态 source-fix evidence。ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS 仅作为下一候选；不启动 R4。' -Force
$completionGate = @($objective.completionGate)
if ($completionGate.Count -gt 0) { $completionGate[0] = 'R3-ACTUAL-DOCS-CONSISTENCY-AUDIT 的历史证据已保留；当前 232→233 与 233→234 转移后一致性门禁均以机器事实为输入完成并登记，目标、状态、治理镜像、台账、证据索引和差分摘要的基线与当前队列锚点一致.' }
$objective | Add-Member -NotePropertyName 'completionGate' -NotePropertyValue $completionGate -Force

Write-AtomicJson -Path $objectivePath -Value $objective
$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' | Out-Null
if (-not $?) { throw 'Set-LegadoRefactorObjective failed.' }

$evidence = @(
  $PreTransitionEvidencePath,
  'tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector-pre-fix-20260808.json',
  'tools/legado-compat/Test-LegadoJsoupRegexAttributeSelectorPreFixContract.ps1',
  'tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-source-fix-20260807.json',
  'tools/legado-compat/evidence/contract-legado-jsoup-regex-attribute-selector.json',
  'tools/legado-compat/Test-LegadoJsoupRegexAttributeSelectorContract.ps1',
  'tools/legado-compat/evidence/v2-jsoup-regex-attribute-selector-current-head-audit-20260808.json',
  'tools/legado-compat/Test-LegadoJsoupRegexAttributeSelectorCurrentHeadAudit.ps1',
  'tools/legado-compat/fixtures/legado-jsoup-regex-attribute-selector.json',
  'entry/src/main/ets/libs/htmlparser/Matcher.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html'
)
$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '234 已通过 233→234 专用静态转移门禁接管为唯一活动源码议题；~= 属性正则失败前合同、源码修复、13 项静态合同、139/51/4/2 影响矩阵和 current-head 审计均已登记。235 为下一候选，R4 运行时与 Legado 差分延期。' -CloseCondition 'CSS/链式规则中的 [attr~=regex] 在 V2 Matcher、字符串回退、ArkWeb java.getString/getStringList 与固定 Legado 输入下逐例等价；完成受影响书源、458 条 Harness、原版差分、构建和真机验证后才能关闭。' -EvidencePath ($evidence -join ',') -IncrementAttempt | Out-Null
if (-not $?) { throw 'Update-LegadoGovernanceState failed.' }

Write-ObjectiveDocument -Revision $TargetRevision

$postGateScript = Join-Path $PSScriptRoot 'Test-LegadoR3JavaStringList233ToJsoupRegex234TransitionConsistency.ps1'
& $postGateScript -RepositoryRoot $RepositoryRoot -RunId ([System.IO.Path]::GetFileNameWithoutExtension($PostTransitionEvidencePath) -replace '\\transition-consistency$','') -OutputPath (Get-RepoPath -RelativePath $PostTransitionEvidencePath) -RequireRegistration | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'post-transition static gate failed.' }

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_java_string_list_233_to_jsoup_regex_234_transition_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $TargetRevision
  previousIssueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  nextIssueId = $NextIssueId
  baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
  preTransitionEvidencePath = $PreTransitionEvidencePath
  postTransitionEvidencePath = $PostTransitionEvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path (Get-RepoPath -RelativePath $RegistrationEvidencePath) -Value $registration

$finalEvidence = @($evidence + @($PostTransitionEvidencePath, $RegistrationEvidencePath))
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '234 已通过 233→234 专用静态转移门禁接管为唯一活动源码议题；~= 属性正则失败前合同、源码修复、13 项静态合同、139/51/4/2 影响矩阵和 current-head 审计均已登记。235 为下一候选，R4 运行时与 Legado 差分延期。' -EvidencePath ($finalEvidence -join ',') | Out-Null
if (-not $?) { throw 'Final governance evidence refresh failed.' }

$registration | ConvertTo-Json -Depth 20
