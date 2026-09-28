[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/registration.json',
  [string]$TargetRevision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-pseudo-235-031',
  [switch]$SkipPostRefreshAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
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
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Assert-Transition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "234 to 235 registration blocked: $Message" }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, $Value, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Contains-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @((Get-PropertyValue -Object $Issue -Name 'evidencePaths' -Default @()))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Update-ObjectiveDocument {
  param([Parameter(Mandatory = $true)][string]$Revision)
  $relativePath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $path = Get-RepoPath -RelativePath $relativePath
  $document = Read-StrictText -RelativePath $relativePath
  $oldRevision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-regex-234-nested-predicate-030'
  $oldRevisionLine = '当前修订：`' + $oldRevision + '`'
  $newRevisionLine = '当前修订：`' + $Revision + '`'
  if ($document.Contains($oldRevisionLine)) {
    $document = $document.Replace($oldRevisionLine, $newRevisionLine)
  } else {
    Assert-Transition ($document.Contains($newRevisionLine)) 'objective Markdown is neither the 234 nor 235 revision.'
  }
  $newline = if ($document.Contains("`r`n")) { "`r`n" } else { "`n" }
  if ($document.Contains('## 本轮目标：235 文本伪类边界')) {
    $postLines = @($document -split '\r?\n')
    for ($i = 0; $i -lt $postLines.Count; $i++) {
      if ($postLines[$i].StartsWith('012 的当前源码证据已经完成登记；')) {
        $postLines[$i] = '012 的当前源码证据已经完成登记；233 的 CSS/List 组合与替换顺序、234 的嵌套属性正则和 235 的文本伪类证据链均已保留。234→235 静态转移门禁已通过并完成登记，235 当前保持 `verifying`；所有证据均绑定固定 458 条基线，只证明源码闭合，不能提升为 `passed` 或 `semantic_match`，R4 运行时与 Legado 差分仍延期。'
      }
      if ($postLines[$i].StartsWith('4. 234 的失败合同、V2 消费者映射、唯一主因和关闭条件')) {
        $postLines[$i] = '4. 234 的失败合同、V2 消费者映射、唯一主因和关闭条件已经齐全并保持 `verifying` 等待 R4；235 已通过独立失败合同、源码修复、静态合同和 234→235 转移门禁成为唯一活动议题，236 仍未激活，也不启动 R4。'
      }
      if ($postLines[$i].StartsWith('4. 发现第二主因、状态与证据不一致或修复引入新差异时')) {
        $postLines[$i] = '4. 发现第二主因、状态与证据不一致或修复引入新差异时，立即停止当前议题，登记新治理任务后再继续；235→236 转移前必须保留 235 的 verifying 状态和全部证据绑定。'
      }
    }
    Write-AtomicText -Path $path -Value ([string]::Join($newline, $postLines))
    return
  }
  $lines = @($document -split '\r?\n')

  $activeIndexes = @()
  $candidateIndexes = @()
  $headingIndexes = @()
  $nextHeadingIndexes = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith('当前唯一活动源码锚点为 ')) { $activeIndexes += $i }
    if ($lines[$i].StartsWith('235 作为下一候选尚未激活；')) { $candidateIndexes += $i }
    if ($lines[$i] -eq '## 本轮目标：234 嵌套谓词边界') { $headingIndexes += $i }
    if ($i -gt 0 -and $lines[$i] -eq '## 单议题执行规则') { $nextHeadingIndexes += $i }
  }
  Assert-Transition ($activeIndexes.Count -eq 1 -and $candidateIndexes.Count -eq 1 -and $headingIndexes.Count -eq 1 -and $nextHeadingIndexes.Count -eq 1) 'objective Markdown section anchors are not unique.'

  $lines[$activeIndexes[0]] = '当前唯一活动源码锚点为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，状态为 `verifying`；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR` 与 `ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 保持 `verifying` 并等待 R4，232、012、005 及既有 Harness/治理议题不重新打开。234→235 专用静态转移门禁已通过 26 项断言，证据为 `tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json`；下一候选唯一为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`。'
  $lines[$candidateIndexes[0]] = '236 作为下一候选尚未激活；它必须先固定 `:has` 伪类的失败合同、受影响规则集合、V2 全部消费者和 current-head 静态审计，再通过专用静态转移门禁。'

  $historyIndexes = @()
  $protocolIndexes = @()
  $singleRuleIndexes = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith('012 的当前源码证据已经完成登记；')) { $historyIndexes += $i }
    if ($lines[$i].StartsWith('4. 234 的失败合同、V2 消费者映射、唯一主因和关闭条件')) { $protocolIndexes += $i }
    if ($lines[$i].StartsWith('4. 发现第二主因、状态与证据不一致或修复引入新差异时')) { $singleRuleIndexes += $i }
  }
  Assert-Transition ($historyIndexes.Count -eq 1 -and $protocolIndexes.Count -eq 1 -and $singleRuleIndexes.Count -eq 1) 'objective Markdown historical protocol anchors are not unique.'
  $lines[$historyIndexes[0]] = '012 的当前源码证据已经完成登记；233 的 CSS/List 组合与替换顺序、234 的嵌套属性正则和 235 的文本伪类证据链均已保留。234→235 静态转移门禁已通过并完成登记，235 当前保持 `verifying`；所有证据均绑定固定 458 条基线，只证明源码闭合，不能提升为 `passed` 或 `semantic_match`，R4 运行时与 Legado 差分仍延期。'
  $lines[$protocolIndexes[0]] = '4. 234 的失败合同、V2 消费者映射、唯一主因和关闭条件已经齐全并保持 `verifying` 等待 R4；235 已通过独立失败合同、源码修复、静态合同和 234→235 转移门禁成为唯一活动议题，236 仍未激活，也不启动 R4。'
  $lines[$singleRuleIndexes[0]] = '4. 发现第二主因、状态与证据不一致或修复引入新差异时，立即停止当前议题，登记新治理任务后再继续；235→236 转移前必须保留 235 的 verifying 状态和全部证据绑定。'

  $replacement = @(
    '## 本轮目标：235 文本伪类边界',
    '',
    '本轮只推进 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，目标证据为 `tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json`：',
    '',
    '1. 固定 Legado Jsoup 的 `:contains`、`:containsOwn`、`:matches`、`:matchesOwn` 真实语义和文本投影边界，并绑定冻结 458 条书源的脱敏规则节点。',
    '2. 以 8 案例 fixture 覆盖后代文本、直接文本、Java 正则、内联标志、逗号分组和未知伪类失败闭合；网络不可达不得改变静态集合。',
    '3. 对 DOM Matcher/HTMLElement、大文档字符串回退、ArkWeb `select`/`java.getString`/`java.getStringList` 和固定 Legado handoff 建立统一消费者映射，禁止静默放宽或空值。',
    '4. 19 项静态合同、source-fix evidence 和 current-head 哈希审计已通过；本轮只登记源码闭合，R4 运行时、原版差分、构建、安装和真机验证仍延期。',
    '5. 修复或发现第二主因时，先保存失败前证据并登记唯一治理议题；235 完成后才允许执行 235→236 静态转移门禁。',
    ''
  )
  $before = if ($headingIndexes[0] -gt 0) { @($lines[0..($headingIndexes[0] - 1)]) } else { @() }
  $after = @($lines[$nextHeadingIndexes[0]..($lines.Count - 1)])
  $updated = [string]::Join($newline, @($before + $replacement + $after))
  Write-AtomicText -Path $path -Value $updated
}

function Update-GovernanceNarrative {
  $relativePath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  $path = Get-RepoPath -RelativePath $relativePath
  $document = Read-StrictText -RelativePath $relativePath
  $newline = if ($document.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = @($document -split '\r?\n')
  $activeIndexes = @()
  $registrationIndexes = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith('`COMPAT-006` 当前唯一活动根因议题为 ')) { $activeIndexes += $i }
    if ($lines[$i].StartsWith('234 的注册脚本已具备重启后幂等恢复：')) { $registrationIndexes += $i }
  }
  Assert-Transition ($activeIndexes.Count -eq 1 -and $registrationIndexes.Count -eq 1) 'governance narrative anchors are not unique.'
  $lines[$activeIndexes[0]] = '`COMPAT-006` 当前唯一活动根因议题为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，以 `full-source-validation-state.json` 的机器事实为准；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`、`ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION`、`ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR`、`ISSUE-COMPAT-012`、`ISSUE-COMPAT-005`、`V2-HARNESS-023`、`ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`、`ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT` 和 `V2-GOV-004-DOCUMENT-TASK-MIRROR` 均保持 `verifying`，仅等待 R4，不重新打开或并行打补丁。234 的嵌套属性正则边界与 235 的文本伪类 8 案例/19 项静态合同、source-fix 和 current-head 审计均绑定固定 458 条基线，但仍不得写成 `passed` 或 `semantic_match`。234→235 静态转移门禁已通过 26 项断言并登记；下一步只推进 235 的源码闭合，完成后才允许转移到 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`，也不启动 R4。R4 的 fresh `full_workflow`、458 条批次、Legado 差分、构建和真机验证仍未开启。'
  $lines[$registrationIndexes[0]] = '235 的注册脚本具备重启后幂等恢复：234 保持 `verifying`，235 原子成为唯一活动源码议题，236 保持下一候选；重放不会改变状态哈希或尝试次数，R4 运行时与 Legado 差分仍延期。'
  Write-AtomicText -Path $path -Value ([string]::Join($newline, $lines))
}

$gateEvidence = Read-StrictJson -RelativePath $GateEvidencePath
$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$baseline = $state.baseline
Assert-Transition ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
Assert-Transition ([string]$gateEvidence.status -eq 'passed' -and [string]$gateEvidence.transition.fromIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and [string]$gateEvidence.transition.toIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$gateEvidence.transition.nextCandidateAfterRegistration -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and -not [bool]$gateEvidence.semanticMatchAllowed -and @($gateEvidence.runtimeActionsPerformed).Count -eq 0) '234→235 gate is not a passed static-only transition.'

$issues = @($state.governance.issues)
$issue234 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
$issue235 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
$issue236 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'

$alreadyRegistered = [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and
  [string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and
  [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
if ($alreadyRegistered) {
  Assert-Transition ($null -ne $issue234 -and [string]$issue234.status -eq 'verifying' -and
    $null -ne $issue235 -and [string]$issue235.status -eq 'verifying' -and
    $null -ne $issue236 -and [string]$issue236.status -eq 'verifying') 'existing 234/235/236 queue statuses are inconsistent.'
  $evidence = @(
    $GateEvidencePath,
    'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json',
    'tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json',
    'tools/legado-compat/fixtures/legado-jsoup-text-pseudo-selectors.json',
    'entry/src/main/ets/libs/htmlparser/Matcher.ets',
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html',
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  )
  $registrationPath = Get-RepoPath -RelativePath $RegistrationEvidencePath
  $registration = $null
  if (Test-Path -LiteralPath $registrationPath -PathType Leaf) {
    $registration = Read-StrictJson -RelativePath $RegistrationEvidencePath
    Assert-Transition ([string]$registration.status -eq 'registered' -and
      [string]$registration.previousIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and
      [string]$registration.issueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and
      [string]$registration.nextIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and
      -not [bool]$registration.semanticMatchAllowed -and @($registration.runtimeActionsPerformed).Count -eq 0) 'existing 234→235 registration evidence is incomplete.'
  } else {
    $registration = [pscustomobject][ordered]@{
      schemaVersion = 1
      kind = 'legado_r3_jsoup_regex_234_to_text_pseudo_235_transition_registration'
      status = 'registered'
      generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
      objectiveId = [string]$objective.objectiveId
      targetRevision = [string]$objective.targetRevision
      previousIssueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
      issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
      nextIssueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
      baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
      gateEvidencePath = $GateEvidencePath
      runtimeActionsPerformed = @()
      semanticMatchAllowed = $false
      verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
      idempotent = $true
    }
    Write-AtomicJson -Path $registrationPath -Value $registration
  }
  $plan = @($objective.continuationPlan)
  $planIds = @($plan | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'id') })
  if ($planIds -notcontains '235-TP-01') { $plan += [pscustomobject][ordered]@{ id = '235-TP-01'; status = 'completed'; action = '固定 Legado 四类文本伪类的 8 案例失败 fixture、受影响规则节点和 19 项静态合同；不执行网络、设备或运行时对照。'; evidence = $GateEvidencePath } }
  if ($planIds -notcontains '235-TP-02') { $plan += [pscustomobject][ordered]@{ id = '235-TP-02'; status = 'completed'; action = '完成 DOM Matcher/HTMLElement、LegadoRuleAnalyzer 字符串回退、ArkWeb runtime 和固定 Legado selector handoff 的 current-head/source-fix 静态审计。'; evidence = 'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json' } }
  if ($planIds -notcontains '235-TP-03') { $plan += [pscustomobject][ordered]@{ id = '235-TP-03'; status = 'in_progress'; action = '继续审计 235 的实际消费者和规则边界，发现第二主因时先登记唯一失败合同；源码闭合后再执行 235→236 静态转移门禁。'; evidence = $GateEvidencePath } }
  if ($planIds -notcontains '235-TP-04') { $plan += [pscustomobject][ordered]@{ id = '235-TP-04'; status = 'deferred'; action = 'R4 的定向回归、458 条批次、Legado 运行时差分、构建、安装和真机验证由用户单独开启，静态证据不得替代。' } }
  $objective | Add-Member -NotePropertyName 'continuationPlan' -NotePropertyValue $plan -Force
  $objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue '继续执行 235-TP-03：联合核对四类文本伪类在固定 Legado、DOM Matcher、字符串回退和 ArkWeb 的规则边界与实际消费者；仅在源码证据闭合且没有新主因后，登记 235→236 静态转移门禁。R4 运行时、构建、安装、设备和 Legado 差分仍不启动。' -Force
  $completionGate = @($objective.completionGate)
  if ($completionGate.Count -gt 0) { $completionGate[0] = 'R3-ACTUAL-DOCS-CONSISTENCY-AUDIT 的历史证据已保留；当前 232→233、233→234 与 234→235 转移后一致性门禁均以机器事实为输入完成并登记，目标、状态、治理镜像、台账、证据索引和差分摘要的基线与当前队列锚点一致.' }
  $objective | Add-Member -NotePropertyName 'completionGate' -NotePropertyValue $completionGate -Force
  Write-AtomicJson -Path $objectivePath -Value $objective
  $setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
  & $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' | Out-Null
  if (-not $?) { throw 'Idempotent objective refresh failed.' }
  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  if ($objectiveDocument.Contains('当前修订：`2026-08-09-actual-docs-source-refactor-continuation-jsoup-regex-234-nested-predicate-030`') -or
    $objectiveDocument.Contains('下一步只允许先执行 234→235 专用静态转移门禁') -or
    $objectiveDocument.Contains('234 保持唯一活动议题和 `verifying`，在 234→235 专用静态转移门禁通过前不激活 235')) {
    Update-ObjectiveDocument -Revision $TargetRevision
  } else {
    Assert-Transition ($objectiveDocument.Contains(('当前修订：`' + $TargetRevision + '`')) -and $objectiveDocument.Contains('ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS')) 'objective document is neither pre- nor post-transition.'
  }
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  if ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR`')) {
    Update-GovernanceNarrative
  } else {
    Assert-Transition ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`')) 'governance narrative is neither pre- nor post-transition.'
  }
  $updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
  $finalEvidence = @($evidence + @($RegistrationEvidencePath))
  & $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235 已通过 234→235 专用静态转移门禁接管为唯一活动源码议题；四类文本伪类的失败合同、源码修复、8 案例/19 项静态合同和 current-head 审计均已登记。236 为下一候选，R4 运行时与 Legado 差分延期。' -EvidencePath ($finalEvidence -join ',') | Out-Null
  if (-not $?) { throw 'Idempotent governance evidence refresh failed.' }
  if (-not $SkipPostRefreshAudit) {
    $refreshedState = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
    Assert-Transition ([string]$refreshedState.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'idempotent refresh lost active issue 235.'
  }
  $registration | Add-Member -NotePropertyName 'idempotentRecovery' -NotePropertyValue $true -Force
  $registration | ConvertTo-Json -Depth 20
  return
}

Assert-Transition ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') 'machine queue is not pre-transition 234.'
Assert-Transition ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') 'objective is not pre-transition 234.'
Assert-Transition ($null -ne $issue234 -and [string]$issue234.status -eq 'verifying' -and $null -ne $issue235 -and [string]$issue235.status -eq 'verifying' -and $null -ne $issue236 -and [string]$issue236.status -eq 'verifying') 'queue statuses are not the expected verifying chain.'
Assert-Transition ([string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-jsoup-regex-234-nested-predicate-030') 'objective target revision is not the 234 closure revision.'

$objective.targetRevision = $TargetRevision
$objective.authority | Add-Member -NotePropertyName 'activeIssueId' -NotePropertyValue 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -Force
$objective.authority | Add-Member -NotePropertyName 'activeIssueSelection' -NotePropertyValue 'full-source-validation-state.json remains the only queue; ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS is now the sole active source-closure issue after the passed 234→235 static transition gate. ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR and ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION remain verifying for deferred R4. ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR is the next candidate; no runtime issue is reopened and static verification never becomes semantic_match.' -Force
$objective.objective | Add-Member -NotePropertyName 'latestStaticClosure' -NotePropertyValue 'ISSUE-COMPAT-235 的文本伪类边界已登记 8 案例 fixture、19 项静态合同、DOM/字符串回退/ArkWeb 消费者哈希和 source-fix evidence；这些证据只证明源码闭合，不能提升为 semantic_match。' -Force
$objective.objective | Add-Member -NotePropertyName 'activeIssue' -NotePropertyValue 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -Force
$objective.objective | Add-Member -NotePropertyName 'activeIssueRule' -NotePropertyValue 'R2/R3 源码队列已从 ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR 原子切换到 ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS。当前治理 DOM Matcher、HTMLElement、超大文档字符串回退和 ArkWeb runtime 的 :contains/:containsOwn/:matches/:matchesOwn 文本伪类、Java 正则与未知伪类失败闭合；235 的失败合同、源码修复、19 项静态合同和 current-head 审计已登记，但 R4 运行时与 Legado 差分仍延期。' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'status' -NotePropertyValue 'issue_selected_r3_text_pseudo_235' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'currentAnchor' -NotePropertyValue 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectedIssue' -NotePropertyValue 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateIssues' -NotePropertyValue @('ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'evidencePath' -NotePropertyValue $GateEvidencePath -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'previousEvidencePath' -NotePropertyValue 'tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-post-transition-20260808/transition-consistency.json' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateEvidencePath' -NotePropertyValue 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-source-fix-20260807.json' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateAuditStatus' -NotePropertyValue 'needs_failure_contract_and_current_head_static_audit' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'candidateCurrentHeadAuditEvidencePath' -NotePropertyValue '' -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'postTransitionEvidencePath' -NotePropertyValue $GateEvidencePath -Force
$objective.objective.queueSelectionGate | Add-Member -NotePropertyName 'selectionRule' -NotePropertyValue 'Prior verifying issues remain deferred to R4. 235 is selected only because its independent text-pseudo fixture, 19-assertion contract, source fix, affected consumer paths and current-head audit are registered, and the 234→235 transition gate passed. ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR is the next candidate and must pass its own failure-contract gate. No second root cause is activated in parallel.' -Force
$sourceOrder = @($objective.objective.sourceClosureOrder)
if ($sourceOrder -notcontains 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') { $sourceOrder += 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' }
$objective.objective | Add-Member -NotePropertyName 'sourceClosureOrder' -NotePropertyValue $sourceOrder -Force

$objective.executionTarget | Add-Member -NotePropertyName 'currentIssue' -NotePropertyValue 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -Force
$objective.executionTarget | Add-Member -NotePropertyName 'nextIssues' -NotePropertyValue @('ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') -Force
$objective.executionTarget | Add-Member -NotePropertyName 'statement' -NotePropertyValue '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环。235 已通过 234→235 静态队列转移门禁，现为唯一活动源码议题；236 是下一候选。所有静态证据只证明源码闭合，不能写成 passed/semantic_match；R4 的 fresh full_workflow、设备回归、Legado 差分、构建和真机门禁仍延期。' -Force
$protocol = @($objective.executionTarget.issueProtocol)
if ($protocol.Count -ge 4) { $protocol[3] = '队列核对完成后才可原子选择下一个 planned P0/P1 源码议题；014、015、V2-HARNESS-023、228、230、V2-GOV-004、ISSUE-COMPAT-CRYPTO-002、ISSUE-COMPAT-005、ISSUE-COMPAT-012、ISSUE-COMPAT-231、ISSUE-COMPAT-232、ISSUE-COMPAT-233 和 ISSUE-COMPAT-234 的源码证据已登记并保持 verifying 仅等待 R4；当前唯一活动源码议题为 ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS，ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR 只作为下一候选，必须先通过独立失败合同和 235→236 静态转移门禁。源码静态通过不得写成 passed 或 semantic_match；所有 runtime-verification-pending 项保持原状态，直到 R4 的 fresh full_workflow 和后置回归满足其关闭条件' }
$objective.executionTarget | Add-Member -NotePropertyName 'issueProtocol' -NotePropertyValue $protocol -Force
$criteria = @($objective.executionTarget.exitCriteria)
if ($criteria.Count -ge 4) {
  $criteria[1] = 'ISSUE-COMPAT-235 完成文本伪类的失败前、源码和静态证据：固定 Legado Jsoup 的 contains/containsOwn/matches/matchesOwn、8 案例 fixture、DOM/字符串回退/ArkWeb 的消费者路径、Java 正则标志与未知伪类失败闭合均有可追踪结果，禁止静默空值'
  $criteria[2] = '完成 ISSUE-COMPAT-235 的 source-closure 证据与 235→236 静态转移一致性门禁；236 只有在 :has 伪类的失败合同、受影响集合、V2 消费者和 current-head 审计齐全后才能成为唯一活动议题。所有已闭合源码议题保持 verifying 仅等待 R4，新的主因不得与当前议题并行'
  $criteria[3] = '当前源码队列中的每个议题均有失败前证据、源码证据和静态证据，或有结构化拒绝；235 与 236 的选择器证据、full-source-validation-state.json 的活动锚点和候选队列保持一致'
}
$objective.executionTarget | Add-Member -NotePropertyName 'exitCriteria' -NotePropertyValue $criteria -Force
$objective.continuationTarget | Add-Member -NotePropertyName 'activeBoundary' -NotePropertyValue 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS 保持 verifying：冻结 HEAD 的文本伪类失败合同、源码修复、8 案例/19 项静态合同和消费者 current-head 审计均已登记；234、233 的静态证据均不代表运行时兼容，R4 仍延期。' -Force
$objective.continuationTarget | Add-Member -NotePropertyName 'nextTransition' -NotePropertyValue '234→235 队列转移一致性门禁已通过并将 post transition path 绑定到 235；下一候选为 ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR。新议题必须先固定失败合同，再跨 Matcher、Rule Analyzer、ArkWeb、JSVM 和输出路径修复。' -Force
$objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue '以 ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS 为唯一活动源码议题：核对固定 Legado 的四类文本伪类语义、8 案例 fixture、受影响规则集合和 V2 全部消费者，先维护失败合同，再完成 DOM Matcher、字符串回退、ArkWeb 和 Java 正则的源码闭合；随后登记静态 source-fix evidence。ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR 仅作为下一候选；不启动 R4。' -Force
$plan = @($objective.continuationPlan)
$planIds = @($plan | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'id') })
if ($planIds -notcontains '235-TP-01') {
  $plan += [pscustomobject][ordered]@{ id = '235-TP-01'; status = 'completed'; action = '固定 Legado 四类文本伪类的 8 案例失败 fixture、受影响规则节点和 19 项静态合同；不执行网络、设备或运行时对照。'; evidence = $GateEvidencePath }
}
if ($planIds -notcontains '235-TP-02') {
  $plan += [pscustomobject][ordered]@{ id = '235-TP-02'; status = 'completed'; action = '完成 DOM Matcher/HTMLElement、LegadoRuleAnalyzer 字符串回退、ArkWeb runtime 和固定 Legado selector handoff 的 current-head/source-fix 静态审计。'; evidence = 'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json' }
}
if ($planIds -notcontains '235-TP-03') {
  $plan += [pscustomobject][ordered]@{ id = '235-TP-03'; status = 'in_progress'; action = '继续审计 235 的实际消费者和规则边界，发现第二主因时先登记唯一失败合同；源码闭合后再执行 235→236 静态转移门禁。'; evidence = $GateEvidencePath }
}
if ($planIds -notcontains '235-TP-04') {
  $plan += [pscustomobject][ordered]@{ id = '235-TP-04'; status = 'deferred'; action = 'R4 的定向回归、458 条批次、Legado 运行时差分、构建、安装和真机验证由用户单独开启，静态证据不得替代。' }
}
$objective | Add-Member -NotePropertyName 'continuationPlan' -NotePropertyValue $plan -Force
$objective | Add-Member -NotePropertyName 'nextAction' -NotePropertyValue '继续执行 235-TP-03：联合核对四类文本伪类在固定 Legado、DOM Matcher、字符串回退和 ArkWeb 的规则边界与实际消费者；仅在源码证据闭合且没有新主因后，登记 235→236 静态转移门禁。R4 运行时、构建、安装、设备和 Legado 差分仍不启动。' -Force
$completionGate = @($objective.completionGate)
if ($completionGate.Count -gt 0) { $completionGate[0] = 'R3-ACTUAL-DOCS-CONSISTENCY-AUDIT 的历史证据已保留；当前 232→233、233→234 与 234→235 转移后一致性门禁均以机器事实为输入完成并登记，目标、状态、治理镜像、台账、证据索引和差分摘要的基线与当前队列锚点一致.' }
$objective | Add-Member -NotePropertyName 'completionGate' -NotePropertyValue $completionGate -Force

Write-AtomicJson -Path $objectivePath -Value $objective
$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' | Out-Null
if (-not $?) { throw 'Set-LegadoRefactorObjective failed.' }

$evidence = @(
  $GateEvidencePath,
  'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json',
  'tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json',
  'tools/legado-compat/fixtures/legado-jsoup-text-pseudo-selectors.json',
  'entry/src/main/ets/libs/htmlparser/Matcher.ets',
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
)
$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235 已通过 234→235 专用静态转移门禁接管为唯一活动源码议题；四类文本伪类的失败合同、源码修复、8 案例/19 项静态合同和 current-head 审计均已登记。236 为下一候选，R4 运行时与 Legado 差分延期。' -CloseCondition 'CSS/链式规则中的 :contains/:containsOwn/:matches/:matchesOwn 在 V2 DOM Matcher、字符串回退、ArkWeb select/java.getString/getStringList 与固定 Legado 输入下逐例等价；完成受影响书源、458 条 Harness、原版差分、构建和真机验证后才能关闭。' -EvidencePath ($evidence -join ',') -IncrementAttempt | Out-Null
if (-not $?) { throw 'Update-LegadoGovernanceState failed.' }

Update-ObjectiveDocument -Revision $TargetRevision
Update-GovernanceNarrative

$registration = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_jsoup_regex_234_to_text_pseudo_235_transition_registration'
  status = 'registered'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $TargetRevision
  previousIssueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  nextIssueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
  gateEvidencePath = $GateEvidencePath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_queue_transition_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  idempotent = $true
}
Write-AtomicJson -Path (Get-RepoPath -RelativePath $RegistrationEvidencePath) -Value $registration

$finalEvidence = @($evidence + @($RegistrationEvidencePath))
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235 已通过 234→235 专用静态转移门禁接管为唯一活动源码议题；四类文本伪类的失败合同、源码修复、8 案例/19 项静态合同和 current-head 审计均已登记。236 为下一候选，R4 运行时与 Legado 差分延期。' -EvidencePath ($finalEvidence -join ',') | Out-Null
if (-not $?) { throw 'Final governance evidence refresh failed.' }

if (-not $SkipPostRefreshAudit) {
  $refreshedState = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $refreshedObjective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  Assert-Transition ([string]$refreshedState.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$refreshedObjective.authority.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$refreshedObjective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'post-refresh active issue is not 235.'
  $refreshedIssues = @($refreshedState.governance.issues)
  Assert-Transition ([string](Get-PropertyValue -Object (Get-Issue -Issues $refreshedIssues -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') -Name 'status') -eq 'verifying' -and [string](Get-PropertyValue -Object (Get-Issue -Issues $refreshedIssues -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') -Name 'status') -eq 'verifying') '234/236 queue status drifted.'
  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $targetRevisionLine = '当前修订：`' + $TargetRevision + '`'
  Assert-Transition ($objectiveDocument.Contains($targetRevisionLine) -and $objectiveDocument.Contains('ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') -and $objectiveDocument.Contains('ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR')) 'objective document was not refreshed for 235.'
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Transition ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`') -and $governanceDocument.Contains('235 的注册脚本具备重启后幂等恢复')) 'governance narrative was not refreshed for 235.'
}

$registration | ConvertTo-Json -Depth 20
