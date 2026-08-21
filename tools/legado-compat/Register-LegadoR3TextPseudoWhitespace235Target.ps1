[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetRevision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-whitespace-235-032',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json'
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
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required JSON is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  try {
    return $strictUtf8.GetString($bytes) | ConvertFrom-Json
  } catch {
    throw "invalid JSON: $RelativePath; $($_.Exception.Message)"
  }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required text is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Update-ObjectiveMarkdown {
  param([Parameter(Mandatory = $true)][string]$Revision)
  $relativePath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $path = Get-RepoPath -RelativePath $relativePath
  $document = Read-StrictText -RelativePath $relativePath
  $oldRevision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-pseudo-235-031'
  $oldLine = '当前修订：`' + $oldRevision + '`'
  $newLine = '当前修订：`' + $Revision + '`'
  if ($document.Contains($oldLine)) {
    $document = $document.Replace($oldLine, $newLine)
  } elseif (-not $document.Contains($newLine)) {
    throw 'objective Markdown does not contain the expected current revision.'
  }

  $activePrefix = '当前唯一活动源码锚点为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`'
  $lines = @($document -split '\r?\n')
  $activeIndexes = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith($activePrefix)) { $activeIndexes += $i }
  }
  if ($activeIndexes.Count -ne 1) { throw 'objective Markdown active-anchor count is not one.' }
  $lines[$activeIndexes[0]] = '当前唯一活动源码锚点为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`，状态为 `verifying`；当前 235-TP-03 细化为 Jsoup `text()`/`ownText()` 空白规范化源码目标，统一 DOM、字符串回退和 ArkWeb；`ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR` 与 `ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION` 保持 `verifying` 并等待 R4，236 仍未激活。'

  $marker = '### 235-TP-03 细化目标：Jsoup 空白规范化'
  if (-not $document.Contains($marker)) {
    $insertIndexes = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -eq '## 单议题执行规则') { $insertIndexes += $i }
    }
    if ($insertIndexes.Count -ne 1) { throw 'objective Markdown single-issue section anchor is not one.' }
    $section = @(
      '### 235-TP-03 细化目标：Jsoup 空白规范化',
      '',
      '本目标只处理 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS` 的文本投影空白语义，目标证据为 `tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json`：',
      '',
      '1. 先固定 Legado Jsoup 1.16.2 `text()`/`ownText()` 的连续空白、换行、制表、NBSP、相邻文本节点和 preserve-whitespace 边界，形成可重复失败合同。',
      '2. 将失败合同映射到 `HTMLElement`/`Matcher`、超大文档字符串回退、ArkWeb `legadoOwnText` 和四类文本伪类消费者；若出现第二主因，先登记新议题，不叠加修复。',
      '3. 失败合同固定后，使用共享的类型化空白规范化语义跨三条路径修复；静态合同通过仍只保持 `verifying`，不得写成 `passed` 或 `semantic_match`。',
      '4. 本目标禁止运行时批次、真实网络、构建、安装、设备和 Legado 差分；这些动作保留到用户单独开启的 R4。',
      ''
    )
    $insertAt = $insertIndexes[0]
    $before = if ($insertAt -gt 0) { @($lines[0..($insertAt - 1)]) } else { @() }
    $after = @($lines[$insertAt..($lines.Count - 1)])
    $lines = @($before + $section + $after)
  }
  $newline = if ($document.Contains("`r`n")) { "`r`n" } else { "`n" }
  Write-AtomicText -Path $path -Value ([string]::Join($newline, $lines))
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  } else {
    $Object.$Name = $Value
  }
}

function Assert-Target {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "235 whitespace target registration blocked: $Message" }
}

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$baseline = $state.baseline
Assert-Target ([int]$baseline.sourceCount -eq 458 -and
  [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and
  [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'canonical baseline changed.'
Assert-Target ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') '235 is not the active machine issue.'
Assert-Target ([string]$state.governance.activeTaskId -eq 'COMPAT-006') 'COMPAT-006 is not the active task.'
Assert-Target ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and
  [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'objective and machine queue disagree.'
Assert-Target ([string]$objective.status -eq 'active') 'refactor objective is not active.'

$targetEvidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_text_pseudo_whitespace_target'
  status = 'active'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = $TargetRevision
  issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  taskId = 'COMPAT-006'
  baseline = [pscustomobject][ordered]@{
    sourceCount = [int]$baseline.sourceCount
    sourcePackageSha256 = [string]$baseline.sourcePackageSha256
    legadoCommit = [string]$baseline.legadoCommit
  }
  basis = [pscustomobject][ordered]@{
    documents = @(
      'docs/analysis/Legado书源V2源码重构持续目标.md',
      'docs/analysis/Legado书源引擎差分摘要.md',
      'docs/analysis/Legado书源引擎证据索引.md',
      'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md',
      'tools/legado-compat/state/full-source-validation-state.json',
      'tools/legado-compat/state/refactor-objective.json'
    )
    legadoImplementation = @(
      'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt',
      'legado/app/src/main/java/io/legado/app/utils/JsoupExtensions.kt',
      'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt'
    )
    v2Consumers = @(
      'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
      'entry/src/main/ets/libs/htmlparser/Matcher.ets',
      'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
      'entry/src/main/resources/rawfile/legado_runtime.html'
    )
  }
  reasonForTarget = '固定 Legado Jsoup 的 text/ownText 会通过 appendNormalisedText 合并连续空白后再 trim；V2 DOM、字符串回退和 ArkWeb 路径目前只拼接并 trim，无法证明相同的空白投影。'
  observedSemanticBoundary = [pscustomobject][ordered]@{
    legadoText = 'Element.text() 规范化后代文本空白并 trim。'
    legadoOwnText = 'Element.ownText() 仅投影直接文本，但连续空白按 Jsoup 规则合并并 trim。'
    v2DomOwnText = 'HTMLElement.ownText 当前拼接直接文本节点后 trim，未统一合并连续空白。'
    v2StringFallback = 'extractDirectTextNodes 逐节点裁剪后以换行拼接，和 Jsoup ownText 的投影边界不同。'
    v2ArkWeb = 'legadoOwnText 当前拼接结果后 trim，未统一执行 Jsoup 空白规范化。'
  }
  plan = @(
    [pscustomobject][ordered]@{ id = '235-WS-01'; status = 'in_progress'; action = '固定 Jsoup 1.16.2 text/ownText 空白规范化失败 fixture，覆盖空格、制表、换行、NBSP、相邻文本节点和 preserve-whitespace 节点；生成失败前合同。'; evidence = $TargetEvidencePath },
    [pscustomobject][ordered]@{ id = '235-WS-02'; status = 'planned'; action = '把失败合同映射到 HTMLElement/Matcher、超大文档字符串回退、ArkWeb legadoOwnText 和所有文本伪类消费者，确认唯一主因与不应规范化的节点边界。'; evidence = $TargetEvidencePath },
    [pscustomobject][ordered]@{ id = '235-WS-03'; status = 'planned'; action = '在失败合同之后实现共享空白规范化 helper，并跨 DOM、字符串回退、ArkWeb 保持 text/ownText 和 :contains/:matches 输入一致；未知语法继续 fail-closed。'; evidence = $TargetEvidencePath },
    [pscustomobject][ordered]@{ id = '235-WS-04'; status = 'planned'; action = '执行静态合同、UTF-8/JSON、current-head 哈希和证据写出隔离检查；仅源码闭合后再保留 235 verifying 并准备 235→236 门禁。'; evidence = $TargetEvidencePath },
    [pscustomobject][ordered]@{ id = '235-WS-05'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建、安装和真机验证由用户单独开启。' }
  )
  constraints = [pscustomobject][ordered]@{
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    forbidden = @('458 条运行时批次', '真实网络端点', 'Android/HarmonyOS 设备', '构建、签名、安装', 'Legado 运行时差分', '旧 NovelSourceExecutor 回退')
    allowed = @('固定源码阅读', '确定性 fixture', '静态失败合同', '跨路径源码修复', 'PowerShell/JSON/UTF-8/哈希检查', '脱敏证据与文档刷新')
  }
  exitCriteria = @(
    '失败前 fixture 能稳定区分 Jsoup text/ownText 的连续空白规范化与 V2 当前投影。',
    'DOM、字符串回退和 ArkWeb 的所有实际消费者都有同一套可追踪规范化语义，或有结构化拒绝。',
    '静态合同、源码哈希、证据索引和机器状态绑定同一目标修订；状态仍为 verifying，不能写成 passed/semantic_match。',
    '没有新增未登记主因；完成后才允许 235→236 静态转移门禁。'
  )
}

$evidencePath = Get-RepoPath -RelativePath $TargetEvidencePath
Write-AtomicJson -Path $evidencePath -Value $targetEvidence

$objective.targetRevision = $TargetRevision
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue -Object $objective.objective -Name 'latestStaticClosure' -Value '235 的四类文本伪类基础路径已有静态闭合证据；当前子目标转为 Jsoup text/ownText 空白规范化，尚未形成运行时兼容结论。'
Set-PropertyValue -Object $objective.objective -Name 'activeIssueRule' -Value '当前唯一活动源码议题仍为 ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS；在 235-TP-03 下先闭合 Jsoup text/ownText 空白规范化，统一 DOM、字符串回退和 ArkWeb 的文本投影，再允许 235→236 静态转移。'
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构与证据闭环；当前只推进 235-TP-03 的 Jsoup text/ownText 空白规范化子目标。静态证据只能保持 verifying，R4 运行时、构建、安装、设备和 Legado 差分仍延期。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'activeBoundary' -Value 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS 保持 verifying；当前先处理 Jsoup text/ownText 空白规范化在 DOM、字符串回退和 ArkWeb 的语义差异。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value '完成 235-WS-01 至 235-WS-04 的失败合同、跨路径源码闭合和静态审计后，才可登记 235→236 静态转移；未完成前不激活 236。'

$plan = @($objective.continuationPlan)
$tp03 = $plan | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'id') -eq '235-TP-03' } | Select-Object -First 1
Assert-Target ($null -ne $tp03) '235-TP-03 is missing from the objective plan.'
Set-PropertyValue -Object $tp03 -Name 'action' -Value '当前细化为 235-WS-01 至 235-WS-04：先固定 Jsoup text/ownText 空白规范化失败合同，再跨 DOM、字符串回退和 ArkWeb 修复与静态审计；没有新主因后才允许 235→236 转移。'
Set-PropertyValue -Object $tp03 -Name 'evidence' -Value $TargetEvidencePath
foreach ($step in @($targetEvidence.plan)) {
  $existing = $plan | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'id') -eq [string]$step.id } | Select-Object -First 1
  if ($null -eq $existing) { $plan += $step }
}
Set-PropertyValue -Object $objective -Name 'continuationPlan' -Value $plan
Set-PropertyValue -Object $objective -Name 'nextAction' -Value '执行 235-WS-01：固定 Legado Jsoup text/ownText 空白规范化的可重复失败 fixture 和失败前合同，随后才允许继续源码修改；R4 运行时、构建、安装、设备和 Legado 差分仍不启动。'

$completionGate = @($objective.completionGate)
$whitespaceGate = '235-TP-03 的空白规范化子目标必须有失败前 fixture、DOM/字符串回退/ArkWeb 消费者映射、跨路径源码证据和 current-head 静态审计；静态闭合仍保持 verifying。'
if (@($completionGate | Where-Object { [string]$_ -eq $whitespaceGate }).Count -eq 0) { $completionGate += $whitespaceGate }
Set-PropertyValue -Object $objective -Name 'completionGate' -Value $completionGate
Write-AtomicJson -Path $objectivePath -Value $objective
Update-ObjectiveMarkdown -Revision $TargetRevision

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' | Out-Null
if (-not $?) { throw 'refactor objective attachment failed.' }

$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235-TP-03 已细化为 Jsoup text/ownText 空白规范化源码目标；先固定失败合同，再统一 DOM、字符串回退和 ArkWeb 文本投影。R4、运行时、构建和设备验证仍延期。' -EvidencePath $TargetEvidencePath | Out-Null
if (-not $?) { throw 'governance state refresh failed.' }

$refreshedObjective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$refreshedState = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
Assert-Target ([string]$refreshedObjective.targetRevision -eq $TargetRevision) 'target revision was not persisted.'
Assert-Target ([string]$refreshedObjective.nextAction -like '执行 235-WS-01*') 'next action was not persisted.'
Assert-Target ([string]$refreshedState.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'active issue changed during target registration.'
Write-Output ("TARGET_REGISTERED revision={0} issue={1} evidence={2} runtimeActions=0 semanticMatchAllowed=false" -f $TargetRevision, $refreshedState.governance.activeIssueId, $TargetEvidencePath)
