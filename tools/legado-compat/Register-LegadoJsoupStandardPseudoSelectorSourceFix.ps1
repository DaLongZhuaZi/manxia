[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issue242 = 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'
$issue243 = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$revision = '2026-08-09-actual-docs-source-refactor-jsoup-standard-pseudo-243-static-closure'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$fixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json'
$preFixPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-pre-fix-20260809.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-post-fix-20260809.json'
$currentHeadPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-current-head-audit-20260809.json'
$sourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-source-fix-20260809.json'
$evidenceDirectory = 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-243-transition-20260809'
$transitionPath = "$evidenceDirectory/transition-consistency.json"
$registrationPath = "$evidenceDirectory/registration.json"
$targetPath = "$evidenceDirectory/target.json"
$postRegistrationPath = "$evidenceDirectory/post-registration-consistency.json"
$failurePath = "$evidenceDirectory/registration-failure.json"
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
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
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporaryPath, $Value, $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
}

function Add-EvidencePath {
  param([Parameter(Mandatory = $true)][object]$Issue, [Parameter(Mandatory = $true)][string[]]$Paths)
  $values = New-Object 'System.Collections.Generic.List[string]'
  foreach ($existing in @((Get-PropertyValue $Issue 'evidencePaths' @()))) { if (-not [string]::IsNullOrWhiteSpace([string]$existing)) { [void]$values.Add([string]$existing) } }
  foreach ($path in $Paths) { if (-not [string]::IsNullOrWhiteSpace($path) -and -not $values.Contains($path)) { [void]$values.Add($path) } }
  Set-PropertyValue $Issue 'evidencePaths' $values.ToArray()
}

function Find-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) { if ([string](Get-PropertyValue $issue 'id' '') -eq $Id) { return $issue } }
  return $null
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 registration blocked: $Message" }
  $script:assertions++
}

function Replace-MarkedSection {
  param([string]$Document, [string]$StartMarker, [string]$EndMarker, [string]$Replacement)
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if ([regex]::IsMatch($Document, $pattern)) { return [regex]::Replace($Document, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement }) }
  $index = $Document.IndexOf($EndMarker, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { throw "document marker missing: $EndMarker" }
  return $Document.Insert($index, $Replacement)
}

function Normalize-GeneratedDocument {
  param([Parameter(Mandatory = $true)][string]$Value)
  $replacementByCode = @{ 7 = 'a'; 8 = 'b'; 9 = 't'; 11 = 'v'; 12 = 'f' }
  foreach ($code in $replacementByCode.Keys) {
    $Value = $Value.Replace([string][char]$code, ([string][char]96 + [string]$replacementByCode[$code]))
  }
  return $Value
}

function Invoke-StaticScript {
  param([Parameter(Mandatory = $true)][string]$RelativeScript)
  $path = Get-RepoPath $RelativeScript
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $path -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "static script failed: $RelativeScript`n$output" }
  return $output
}

function Update-ObjectiveDocument {
  $path = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $document = Read-StrictText $path
  $document = $document.Replace('当前修订：`2026-08-09-actual-docs-source-refactor-trace-bridge-preservation-242-result-boundary`', ('当前修订：`' + $revision + '`'))
  $document = $document.Replace('工作流：R3-ISSUE-242-TRACE-MUTATION-BRIDGE-PRESERVATION', '工作流：R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS')
  $document = $document.Replace('当前修订：2026-08-09-actual-docs-source-refactor-trace-bridge-preservation-242-result-boundary', ('当前修订：' + $revision))
  $activePattern = '(?s)当前唯一活动源码议题为 ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION，状态为 verifying。.*?(?=\r?\n\r?\n## 下一持续执行目标)'
  $activeText = '当前唯一活动源码议题为 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS，状态为 verifying。固定书源包扫描发现 52 个标准 CSS 伪类规则字符串涉及 21 条书源；`LegadoRuleAnalyzer` 的大文档字符串回退现已补齐 `:first-child`、`:last-child`、`:nth-child`、`:only-child`，并使用元素兄弟上下文执行 Jsoup 兼容的 1-based `an+b` 语义。DOM Matcher、ArkWeb 原生 CSS 路径和固定 Legado Jsoup `Element.select` 的消费者矩阵已绑定。该修复只完成源码静态闭合，R4 运行时、458 条 Harness、Legado 差分、构建和真机验证仍延期。'
  if ([regex]::IsMatch($document, $activePattern)) { $document = [regex]::Replace($document, $activePattern, $activeText, 1) }
  $document = $document.Replace('当前修订已完成 242 的源码修复', '前一轮已完成 242 的源码修复')
  $document = $document.Replace('242 必须保持 verifying，不能报告为语义兼容完成。', '242 与 243 均保持 verifying，不能报告为语义兼容完成。')
  $queueSection = @"
## R3-SOURCE-QUEUE-CONTINUATION-NEXT-CANDIDATE

当前机器事实的活动源码议题为 ``$issue243``（``verifying``）。243 已通过固定 Legado 语义、52 个规则字符串/21 条书源影响集合、失败见证、V2 三路径消费者矩阵、post-fix 静态合同和 current-head 哈希审计；本次登记将其原子设为唯一活动源码议题，242 保持 ``verifying`` 等待 R4。

证据：``$transitionPath``、``$registrationPath``、``$targetPath``、``$contractPath``、``$currentHeadPath``、``$sourceFixPath``；重现脚本：`tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorPostFixContract.ps1`、`tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorCurrentHeadAudit.ps1`、`tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorSourceFix.ps1`。本轮仅执行源码、固定包、UTF-8/JSON/哈希和文档检查，没有执行运行时、网络、构建、安装、设备或 Legado 差分，R4 继续 deferred。

## R3-ISSUE-243-STANDARD-CSS-PSEUDO-SELECTORS

243 的静态修复闭合范围：大文档字符串回退在保留未知伪类 fail-closed 的同时，消费标准 child pseudo；`first-child`、`last-child`、`only-child` 使用元素兄弟计数，`nth-child` 使用 1-based `an+b`；上下文来自直接元素子节点，不把文本节点计入序号。ArkWeb 保留标准 CSS 伪类给浏览器 `querySelectorAll`，仅对 Jsoup 专用伪类走自定义投影；固定 Legado 仍以 `Element.select` 为语义基准。

影响：52 个规则字符串、21 条书源（序号 `26, 70, 97, 144, 145, 147, 158, 195, 201, 223, 228, 231, 251, 255, 278, 283, 284, 357, 402, 408, 452`）。243 保持 `verifying`，静态证据不得提升为 `passed` 或 `semantic_match`；关闭条件是 R4 定向六案例、受影响集合、458 条确定性 Harness、固定 Legado 差分、构建和真机门禁全部通过。

"@
  $nl = [Environment]::NewLine
  $code = [string][char]96
  $queueSection = [string]::Join($nl, @(
    '## R3-SOURCE-QUEUE-CONTINUATION-NEXT-CANDIDATE',
    '',
    ('当前机器事实的活动源码议题为 ' + $code + $issue243 + $code + '（' + $code + 'verifying' + $code + '）。243 已通过固定 Legado 语义、52 个规则字符串/21 条书源影响集合、失败见证、V2 三路径消费者矩阵、post-fix 静态合同和 current-head 哈希审计；本次登记将其原子设为唯一活动源码议题，242 保持 ' + $code + 'verifying' + $code + ' 等待 R4。'),
    '',
    ('证据：' + $code + $transitionPath + $code + '、' + $code + $registrationPath + $code + '、' + $code + $targetPath + $code + '、' + $code + $contractPath + $code + '、' + $code + $currentHeadPath + $code + '、' + $code + $sourceFixPath + $code + '；重现脚本：' + $code + 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorPostFixContract.ps1' + $code + '、' + $code + 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorCurrentHeadAudit.ps1' + $code + '、' + $code + 'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorSourceFix.ps1' + $code + '。本轮仅执行源码、固定包、UTF-8/JSON/哈希和文档检查，没有执行运行时、网络、构建、安装、设备或 Legado 差分，R4 继续 deferred。'),
    '',
    '## R3-ISSUE-243-STANDARD-CSS-PSEUDO-SELECTORS',
    '',
    ('243 的静态修复闭合范围：大文档字符串回退在保留未知伪类 fail-closed 的同时，消费标准 child pseudo；' + $code + 'first-child' + $code + '、' + $code + 'last-child' + $code + '、' + $code + 'only-child' + $code + ' 使用元素兄弟计数，' + $code + 'nth-child' + $code + ' 使用 1-based ' + $code + 'an+b' + $code + '；上下文来自直接元素子节点，不把文本节点计入序号。ArkWeb 保留标准 CSS 伪类给浏览器 ' + $code + 'querySelectorAll' + $code + '，仅对 Jsoup 专用伪类走自定义投影；固定 Legado 仍以 ' + $code + 'Element.select' + $code + ' 为语义基准。'),
    '',
    ('影响：52 个规则字符串、21 条书源（序号 ' + $code + '26, 70, 97, 144, 145, 147, 158, 195, 201, 223, 228, 231, 251, 255, 278, 283, 284, 357, 402, 408, 452' + $code + '）。243 保持 ' + $code + 'verifying' + $code + '，静态证据不得提升为 ' + $code + 'passed' + $code + ' 或 ' + $code + 'semantic_match' + $code + '；关闭条件是 R4 定向六案例、受影响集合、458 条确定性 Harness、固定 Legado 差分、构建和真机门禁全部通过。'),
    ''
  )) + $nl
  $document = Replace-MarkedSection -Document $document -StartMarker '## R3-SOURCE-QUEUE-CONTINUATION-NEXT-CANDIDATE' -EndMarker '## 单议题执行规则' -Replacement $queueSection
  $document = Normalize-GeneratedDocument $document
  Write-AtomicText $path $document
}

function Update-GovernanceDocument {
  $path = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  $document = Read-StrictText $path
  $topPattern = '(?s)机器事实 `full-source-validation-state\.json` 的固定基线未漂移；当前活动源码议题为 `ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION`（`verifying`）。.*?(?=\r?\n(?:\r?\n)*## R3 当前目标队列前置审计)'
  $topText = "机器事实 ``full-source-validation-state.json`` 的固定基线未漂移；当前活动源码议题为 ``$issue243``（``verifying``）。243 的 52 个标准 CSS 伪类规则字符串/21 条书源影响集合、失败见证、三路径消费者矩阵、post-fix 静态合同、current-head/source-fix 和唯一队列转移证据均已登记；242 保持 ``verifying`` 等待 R4。R4 运行时、458 条 Harness、Legado 差分、构建和设备验证仍延期。"
  if ([regex]::IsMatch($document, $topPattern)) { $document = [regex]::Replace($document, $topPattern, $topText, 1) }
  $topPattern = '(?s)机器事实 `full-source-validation-state\.json` 的固定基线未漂移：.*?(?=\r?\n(?:\r?\n)*## R3 当前目标队列前置审计)'
  if ([regex]::IsMatch($document, $topPattern)) { $document = [regex]::Replace($document, $topPattern, $topText, 1) }
  $queuePattern = '(?s)## R3 当前目标队列前置审计（当前活动议题）.*?(?=\r?\n(?:\r?\n)*<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->)'
  $queueText = @"
## R3 当前目标队列前置审计（当前活动议题）

`full-source-validation-state.json` 已原子登记 ``$issue243`` 为唯一活动源码议题（``verifying``），242 保持 ``verifying``。243 的五项证据门禁已满足：固定 Legado `Element.select` 语义、52 个规则字符串/21 条书源影响集合、可复现失败见证、V2 DOM/大文档字符串回退/ArkWeb 消费矩阵、post-fix/current-head/source-fix/关闭条件。

证据：``$transitionPath``、``$registrationPath``；重现脚本：`tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorSourceFix.ps1`。该登记只执行确定性静态合同、源码哈希、状态和文档刷新，不执行运行时、网络、构建、安装、Android/HarmonyOS 设备或 Legado 差分；R4 继续延期。

## R3 当前活动议题：243 标准 CSS 伪类

大文档字符串回退现已对四个标准 child pseudo 使用元素兄弟上下文；未知伪类仍 fail-closed。静态闭合不等同运行时兼容，243 必须在 R4 完成六案例、21 条书源、458 条 Harness、Legado 差分、构建和真机验证后才可改变终态。
"@
  $nl = [Environment]::NewLine
  $code = [string][char]96
  $queueText = [string]::Join($nl, @(
    '## R3 当前目标队列前置审计（当前活动议题）',
    '',
    ($code + 'full-source-validation-state.json' + $code + ' 已原子登记 ' + $code + $issue243 + $code + ' 为唯一活动源码议题（' + $code + 'verifying' + $code + '），242 保持 ' + $code + 'verifying' + $code + '。243 的五项证据门禁已满足：固定 Legado ' + $code + 'Element.select' + $code + ' 语义、52 个规则字符串/21 条书源影响集合、可复现失败见证、V2 DOM/大文档字符串回退/ArkWeb 消费矩阵、post-fix/current-head/source-fix/关闭条件。'),
    '',
    ('证据：' + $code + $transitionPath + $code + '、' + $code + $registrationPath + $code + '；重现脚本：' + $code + 'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorSourceFix.ps1' + $code + '。该登记只执行确定性静态合同、源码哈希、状态和文档刷新，不执行运行时、网络、构建、安装、Android/HarmonyOS 设备或 Legado 差分；R4 继续延期。'),
    '',
    '## R3 当前活动议题：243 标准 CSS 伪类',
    '',
    '大文档字符串回退现已对四个标准 child pseudo 使用元素兄弟上下文；未知伪类仍 fail-closed。静态闭合不等同运行时兼容，243 必须在 R4 完成六案例、21 条书源、458 条 Harness、Legado 差分、构建和真机验证后才可改变终态。'
  ))
  if ([regex]::IsMatch($document, $queuePattern)) { $document = [regex]::Replace($document, $queuePattern, $queueText.TrimEnd(), 1) }
  $legacyCandidatePattern = '(?s)## R3 静态候选边界（未激活）.*?(?=\r?\n(?:\r?\n)*<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->)'
  $document = [regex]::Replace($document, $legacyCandidatePattern, '', 1)
  if (-not $document.Contains('| ' + $issue243 + ' |')) {
    $row = "| $issue243 | verifying | P0 | 0 | $taskId | 243 静态闭合：大文档字符串回退补齐 `:first-child`、`:last-child`、`:nth-child`、`:only-child`，绑定 52 个规则字符串/21 条书源、三路径消费者矩阵、post-fix/current-head/source-fix 和 R4 关闭条件；运行时与差分延期。 | ``$preFixPath``<br>``$contractPath``<br>``$currentHeadPath``<br>``$sourceFixPath``<br>``$transitionPath``<br>``$registrationPath``<br>``$targetPath`` |"
    $anchor = '| ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION |'
    $index = $document.IndexOf($anchor, [System.StringComparison]::Ordinal)
    if ($index -ge 0) {
      $lineStart = $document.LastIndexOf("`n", $index)
      $document = $document.Insert($lineStart + 1, $row + "`r`n")
    }
  }
  $document = Normalize-GeneratedDocument $document
  Write-AtomicText $path $document
}

function Update-PostRegistrationEvidence {
  $state = Read-StrictJson $statePath
  $objective = Read-StrictJson $objectivePath
  $issue = Find-Issue @($state.governance.issues) $issue243
  $checks = @(
    [pscustomobject][ordered]@{ id = 'active_issue'; status = 'passed'; detail = '243 is the sole active source issue.' },
    [pscustomobject][ordered]@{ id = 'previous_issue_preserved'; status = 'passed'; detail = '242 remains verifying with its evidence paths.' },
    [pscustomobject][ordered]@{ id = 'objective_binding'; status = 'passed'; detail = 'objective and queueSelectionGate point to 243.' },
    [pscustomobject][ordered]@{ id = 'documents'; status = 'passed'; detail = 'objective and governance documents contain the 243 active boundary.' },
    [pscustomobject][ordered]@{ id = 'document_encoding'; status = 'passed'; detail = 'generated documents are UTF-8 without generator control-character residue.' },
    [pscustomobject][ordered]@{ id = 'active_boundary_exact'; status = 'passed'; detail = 'the exact 243 revision and governance queue boundary are present.' },
    [pscustomobject][ordered]@{ id = 'static_only'; status = 'passed'; detail = 'runtimeActionsPerformed is empty and semanticMatchAllowed is false.' }
  )
  Assert-Gate ([string]$state.governance.activeIssueId -eq $issue243 -and [string]$state.governance.status -eq 'running') 'post-registration machine queue is not active 243/running.'
  Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 issue is not verifying.'
  $previous = Find-Issue @($state.governance.issues) $issue242
  Assert-Gate ($null -ne $previous -and [string]$previous.status -eq 'verifying') '242 was not preserved as verifying.'
  Assert-Gate ([string]$objective.authority.activeIssueId -eq $issue243 -and [string]$objective.objective.queueSelectionGate.currentAnchor -eq $issue243 -and [string]$objective.executionTarget.currentIssue -eq $issue243) 'objective queue binding drifted.'
  $objectiveDocument = Read-StrictText 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceDocument = Read-StrictText 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Gate ($objectiveDocument.Contains($issue243) -and $objectiveDocument.Contains($transitionPath) -and $governanceDocument.Contains($issue243) -and $governanceDocument.Contains($registrationPath)) 'documents do not contain the active 243 evidence boundary.'
  $invalidObjectiveCodes = @([System.IO.File]::ReadAllBytes((Get-RepoPath 'docs/analysis/Legado书源V2源码重构持续目标.md')) | Where-Object { $_ -in @(0, 7, 8, 9, 11, 12) })
  $invalidGovernanceCodes = @([System.IO.File]::ReadAllBytes((Get-RepoPath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')) | Where-Object { $_ -in @(0, 7, 8, 9, 11, 12) })
  Assert-Gate ($invalidObjectiveCodes.Count -eq 0 -and $invalidGovernanceCodes.Count -eq 0) 'generated documents contain control-character residue.'
  $code = [string][char]96
  $governanceBoundary = $code + 'full-source-validation-state.json' + $code + ' 已原子登记 ' + $code + $issue243 + $code
  Assert-Gate ($objectiveDocument.Contains('当前修订：' + $revision) -and $governanceDocument.Contains($governanceBoundary)) 'exact active 243 revision or governance boundary is missing.'
  Assert-Gate (-not [bool]$state.governance.semanticMatchAllowed -and @($state.governance.runtimeActionsPerformed).Count -eq 0) 'post-registration state contains a runtime or semantic claim.'
  $post = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_jsoup_standard_pseudo_243_post_registration_consistency'; status = 'passed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); issueId = $issue243; previousIssueId = $issue242; baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }; assertions = $script:assertions; checks = $checks; evidencePaths = @($statePath, $objectivePath, $transitionPath, $registrationPath, $targetPath, $postRegistrationPath, 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-243-transition-20260809/registration-idempotency.json', 'docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md'); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_post_registration_static_only;R4_runtime_build_device_and_legado_diff_deferred' }
  Write-AtomicJson $postRegistrationPath $post
  return $post
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson $statePath
  $objective = Read-StrictJson $objectivePath
  $registrationAbsolutePath = Get-RepoPath $registrationPath
  if ([string]$state.governance.activeIssueId -eq $issue243 -and (Test-Path -LiteralPath $registrationAbsolutePath -PathType Leaf)) {
    $currentRevision = [string](Get-PropertyValue $objective 'targetRevision' '')
    if ($currentRevision -ne $revision) {
      $result = [pscustomobject][ordered]@{
        status = 'already_registered_historical_boundary'
        issueId = $issue243
        currentRevision = $currentRevision
        supersededRevision = $revision
        runtimeActionsPerformed = @()
        semanticMatchAllowed = $false
        idempotent = $true
        registrationPath = $registrationPath
        assertions = $script:assertions
      }
      $result | ConvertTo-Json -Depth 20
      return
    }
    $refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
    $refreshOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw ('derived document refresh failed during idempotent replay: ' + $refreshOutput) }
    Update-ObjectiveDocument
    Update-GovernanceDocument
    $post = Update-PostRegistrationEvidence
    $result = [pscustomobject][ordered]@{ status = 'already_registered'; issueId = $issue243; previousIssueId = $issue242; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; idempotent = $true; registrationPath = $registrationPath; postRegistrationEvidencePath = $postRegistrationPath; assertions = $script:assertions }
    $result | ConvertTo-Json -Depth 20
    return
  }

  Invoke-StaticScript 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorPostFixContract.ps1' | Out-Null
  Invoke-StaticScript 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorCurrentHeadAudit.ps1' | Out-Null
  $state = Read-StrictJson $statePath
  $objective = Read-StrictJson $objectivePath
  $fixture = Read-StrictJson $fixturePath
  $preFix = Read-StrictJson $preFixPath
  $contract = Read-StrictJson $contractPath
  $currentHead = Read-StrictJson $currentHeadPath
  Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
  Assert-Gate ([string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issue242 -and [string]$state.governance.status -eq 'running') '242 is not the sole active issue before registration.'
  $record242 = Find-Issue @($state.governance.issues) $issue242
  Assert-Gate ($null -ne $record242 -and [string]$record242.status -eq 'verifying') '242 must remain verifying.'
  Assert-Gate ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq $issue243 -and -not [bool]$preFix.semanticMatchAllowed) '243 failure witness is invalid.'
  Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 30 -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) '243 post-fix contract is invalid.'
  Assert-Gate ([string]$currentHead.status -eq 'passed' -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) '243 current-head audit is invalid.'
  Assert-Gate ([int]$fixture.pseudoCounts.total -eq 52 -and @($fixture.affectedSourceOrdinals).Count -eq 21) '243 impact metadata drifted.'
  Assert-Gate ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'Legado checkout is not pinned.'

  $sourceFix = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'source_fix'
    issueId = $issue243
    status = 'source_closed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    staticImpact = [pscustomobject][ordered]@{ ruleStringCount = 52; affectedSourceCount = 21; pseudoCounts = $fixture.pseudoCounts; affectedSourceOrdinals = @($fixture.affectedSourceOrdinals | ForEach-Object { [int]$_ } | Sort-Object) }
    rootCause = [pscustomobject][ordered]@{ category = '规则解析或编译'; originalSemantics = 'Pinned Legado AnalyzeByJSoup delegates CSS selection to Jsoup Element.select; standard child pseudos count element children, and nth-child is 1-based an+b.'; v2BeforeFix = 'The large-document string fallback extracted standard pseudo names but routed them to the unknown-pseudo fail-closed branch, while DOM and ArkWeb had separate paths.'; evidence = @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt', $preFixPath) }
    changes = @(
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; change = 'Add typed sibling-count context and standard child pseudo filtering to the large-document string fallback.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; change = 'Retain DOM standard child pseudo semantics as the cross-path reference.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/resources/rawfile/legado_runtime.html'; change = 'Retain standard CSS child pseudos for native ArkWeb querySelectorAll and custom-handle only Jsoup-specific predicates.' }
    )
    failureEvidence = @($preFixPath)
    staticContract = $contractPath
    currentHeadAudit = $currentHeadPath
    consumerMatrix = $currentHead.consumerMatrix
    currentHeadHashes = $currentHead.currentHeadHashes
    assertions = [int]$contract.assertions + [int]$currentHead.assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_source_fix_static_only;243_verifying;R4_runtime_build_device_and_legado_diff_deferred'
    closeCondition = 'R4 must execute all six standard-pseudo fixtures, the 52-rule/21-source affected set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
  }
  Write-AtomicJson $sourceFixPath $sourceFix

  $allEvidence = @($fixturePath, $preFixPath, $contractPath, $currentHeadPath, $sourceFixPath, 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets', 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets', 'entry/src/main/resources/rawfile/legado_runtime.html', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
  $transition = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_jsoup_standard_pseudo_242_to_243_transition_consistency'; status = 'passed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); fromIssue = $issue242; toIssue = $issue243; fromStatus = 'verifying'; toStatus = 'verifying'; currentActiveIssueBeforeRegistration = $issue242; nextCandidateAfterRegistration = ''; objectiveId = [string]$objective.objectiveId; fromRevision = [string]$objective.targetRevision; toRevision = $revision; baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }; assertions = $script:assertions; evidencePaths = $allEvidence; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_static_transition_only;243_becomes_verifying_source_anchor;R4_runtime_build_device_and_legado_diff_deferred'; closeCondition = [string]$sourceFix.closeCondition }
  Write-AtomicJson $transitionPath $transition

  $target = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_jsoup_standard_pseudo_243_target'; status = 'active'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); objectiveId = [string]$objective.objectiveId; targetRevision = $revision; issueId = $issue243; taskId = $taskId; baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }; reasonForTarget = '242 static trace closure remains verifying for R4; 243 now has fixed Legado semantics, a frozen affected set, failed witness, three-path consumer matrix, post-fix contract and current-head/source-fix evidence.'; plan = @([pscustomobject][ordered]@{ id = '243-SP-01'; status = 'completed'; action = '固定 Legado Element.select standard child pseudo semantics and the 52-rule/21-source impact set.'; evidence = $preFixPath }, [pscustomobject][ordered]@{ id = '243-SP-02'; status = 'completed'; action = 'Add and verify large-document string fallback sibling-context evaluation.'; evidence = $contractPath }, [pscustomobject][ordered]@{ id = '243-SP-03'; status = 'completed'; action = 'Bind DOM, ArkWeb and Legado consumer paths with current-head hashes.'; evidence = $currentHeadPath }, [pscustomobject][ordered]@{ id = '243-SP-04'; status = 'completed'; action = 'Register 243 as the sole active source issue while preserving 242 verifying.'; evidence = $registrationPath }, [pscustomobject][ordered]@{ id = '243-SP-05'; status = 'deferred'; action = 'R4 targeted/full Harness, fixed-Legado differential, build and device verification.' }); currentSubstage = '243-SP-05'; currentStatus = 'source_closed_static_only'; sourceFixEvidencePath = $sourceFixPath; currentHeadAuditEvidencePath = $currentHeadPath; transitionEvidencePath = $transitionPath; constraints = [pscustomobject][ordered]@{ runtimeActionsPerformed = @(); semanticMatchAllowed = $false; forbidden = @('458-source runtime batch', 'real network', 'build/install/device and Legado runtime differential') }; nextAction = '243 remains verifying; R4 deferred.' }
  Write-AtomicJson $targetPath $target

  $now = [DateTimeOffset]::UtcNow.ToString('o')
  $issues = @($state.governance.issues)
  $record243 = Find-Issue $issues $issue243
  if ($null -eq $record243) {
    $record243 = [pscustomobject][ordered]@{ id = $issue243; taskId = $taskId; status = 'verifying'; severity = 'P0'; attempts = 0; summary = '243 标准 CSS child pseudo 的大文档字符串回退已完成静态闭合；52 个规则字符串涉及 21 条书源，R4 deferred。'; closeCondition = [string]$sourceFix.closeCondition; evidencePaths = @() }
    $issues = @($issues) + @($record243)
  }
  Set-PropertyValue $record243 'status' 'verifying'
  Set-PropertyValue $record243 'taskId' $taskId
  Set-PropertyValue $record243 'severity' 'P0'
  Set-PropertyValue $record243 'summary' '243 标准 CSS child pseudo 的大文档字符串回退已完成静态闭合；52 个规则字符串涉及 21 条书源，DOM/ArkWeb/Legado 消费矩阵、post-fix/current-head/source-fix 和转移证据已登记，R4 deferred。'
  Set-PropertyValue $record243 'closeCondition' ([string]$sourceFix.closeCondition)
  Set-PropertyValue $record243 'lastUpdatedAt' $now
  Add-EvidencePath $record243 ($allEvidence + @($transitionPath, $targetPath, $registrationPath, $postRegistrationPath, 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorSourceFix.ps1'))
  Add-EvidencePath $record242 @($transitionPath, $targetPath, $registrationPath)
  Set-PropertyValue $state.governance 'issues' $issues
  Set-PropertyValue $state.governance 'activeIssueId' $issue243
  Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issue243
  Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
  Set-PropertyValue $state.governance 'runtimeActionsPerformed' @()
  $queue = Get-PropertyValue $state.governance 'queuePreflight' $null
  if ($null -eq $queue) { $queue = [pscustomobject][ordered]@{}; Set-PropertyValue $state.governance 'queuePreflight' $queue }
  Set-PropertyValue $queue 'status' 'passed_source_fix_static_closed_wait_r4'
  Set-PropertyValue $queue 'evidencePath' $transitionPath
  Set-PropertyValue $queue 'activeIssueId' $issue243
  Set-PropertyValue $queue 'candidateCount' 1
  Set-PropertyValue $queue 'candidateGateStatus' 'source_fix_static_closed_wait_r4'
  Set-PropertyValue $queue 'candidateIssueId' $issue243
  Set-PropertyValue $queue 'candidateEvidencePath' $sourceFixPath
  Set-PropertyValue $queue 'candidateCurrentHeadAuditEvidencePath' $currentHeadPath
  Set-PropertyValue $queue 'candidateSourceFixEvidencePath' $sourceFixPath
  Set-PropertyValue $queue 'transitionEvidencePath' $transitionPath
  Set-PropertyValue $queue 'updatedAt' $now
  Set-PropertyValue $state 'generatedAt' $now
  Write-AtomicJson $statePath $state

  Set-PropertyValue $objective 'targetRevision' $revision
  Set-PropertyValue $objective 'lastReviewedAt' $now
  Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
  Set-PropertyValue $objective.authority 'activeIssueId' $issue243
  Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 is the sole active source-closure issue after the passed static transition. 242 remains verifying for deferred R4, and static closure never becomes semantic_match.'
  Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  Set-PropertyValue $objective.objective 'activeIssue' $issue243
  Set-PropertyValue $objective.objective 'activeIssueRule' '当前唯一活动源码议题为 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS；大文档字符串回退现已评估 first-child、last-child、nth-child、only-child，静态闭合绑定 52 个规则字符串和 21 条书源；R4 deferred。'
  $queueGate = $objective.objective.queueSelectionGate
  Set-PropertyValue $queueGate 'status' 'issue_selected_r3_standard_css_pseudo_243'
  Set-PropertyValue $queueGate 'currentAnchor' $issue243
  Set-PropertyValue $queueGate 'selectedIssue' $issue243
  Set-PropertyValue $queueGate 'candidateIssues' @()
  Set-PropertyValue $queueGate 'evidencePath' $transitionPath
  Set-PropertyValue $queueGate 'previousEvidencePath' 'tools/legado-compat/evidence/r3-trace-mutation-bridge-preservation-registration-20260809/registration.json'
  Set-PropertyValue $queueGate 'candidateEvidencePath' $sourceFixPath
  Set-PropertyValue $queueGate 'candidateCurrentHeadAuditEvidencePath' $currentHeadPath
  Set-PropertyValue $queueGate 'candidateStatus' 'source_fix_static_closed'
  Set-PropertyValue $queueGate 'candidateGateStatus' 'source_fix_static_closed_wait_r4'
  Set-PropertyValue $objective.executionTarget 'currentIssue' $issue243
  Set-PropertyValue $objective.executionTarget 'nextIssues' @()
  Set-PropertyValue $objective.executionTarget 'statement' '243 已通过静态五项证据门禁并成为唯一活动源码议题；R4 运行时、458 条 Harness、固定 Legado 差分、构建和真机验证仍延期。'
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS 保持 verifying：52 个规则字符串/21 条书源影响集合、失败见证、三路径消费者矩阵、post-fix/current-head/source-fix 和转移证据已登记；242 保持 verifying 等待 R4。'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' '243 静态转移已完成；下一动作是由用户单独开启 R4 定向/全量 Harness、Legado 差分、构建和真机验证。'
  $closureOrder = New-Object 'System.Collections.Generic.List[string]'
  foreach ($existing in @($objective.objective.sourceClosureOrder)) { if (-not [string]::IsNullOrWhiteSpace([string]$existing)) { [void]$closureOrder.Add([string]$existing) } }
  if (-not $closureOrder.Contains($issue243)) { [void]$closureOrder.Add($issue243) }
  Set-PropertyValue $objective.objective 'sourceClosureOrder' $closureOrder.ToArray()
  $deferred = New-Object 'System.Collections.Generic.List[string]'
  foreach ($existing in @($objective.objective.deferredVerificationIssues)) { if (-not [string]::IsNullOrWhiteSpace([string]$existing)) { [void]$deferred.Add([string]$existing) } }
  if (-not $deferred.Contains($issue243)) { [void]$deferred.Add($issue243) }
  Set-PropertyValue $objective.objective 'deferredVerificationIssues' $deferred.ToArray()
  $plan = New-Object 'System.Collections.Generic.List[object]'
  foreach ($item in @($objective.continuationPlan)) { [void]$plan.Add($item) }
  if (@($plan | Where-Object { [string](Get-PropertyValue $_ 'id' '') -eq '243-SP-01' }).Count -eq 0) {
    [void]$plan.Add([pscustomobject][ordered]@{ id = '243-SP-01'; status = 'completed'; action = '固定 Legado Element.select 标准 child pseudo 语义与 52/21 影响集合。'; evidence = $preFixPath })
    [void]$plan.Add([pscustomobject][ordered]@{ id = '243-SP-02'; status = 'completed'; action = '完成大文档字符串回退标准 child pseudo 静态修复与 post-fix contract。'; evidence = $contractPath })
    [void]$plan.Add([pscustomobject][ordered]@{ id = '243-SP-03'; status = 'completed'; action = '完成 DOM/字符串回退/ArkWeb/Legado 消费矩阵与 current-head 哈希审计。'; evidence = $currentHeadPath })
    [void]$plan.Add([pscustomobject][ordered]@{ id = '243-SP-04'; status = 'completed'; action = '原子登记 243 为唯一活动源码议题并保留 242 verifying。'; evidence = $registrationPath })
    [void]$plan.Add([pscustomobject][ordered]@{ id = '243-SP-05'; status = 'deferred'; action = 'R4 定向/全量 Harness、Legado 差分、构建和真机验证。' })
  }
  Set-PropertyValue $objective 'continuationPlan' $plan.ToArray()
  Set-PropertyValue $objective 'nextAction' '243 源码静态闭合和唯一队列登记已完成并保持 verifying；R4 deferred。'
  Write-AtomicJson $objectivePath $objective

  $registration = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_jsoup_standard_pseudo_243_transition_registration'; status = 'registered'; generatedAt = $now; objectiveId = [string]$objective.objectiveId; targetRevision = $revision; previousIssueId = $issue242; issueId = $issue243; nextIssueId = ''; gateEvidencePath = $transitionPath; targetEvidencePath = $targetPath; failureWitnessPath = $preFixPath; postFixContractPath = $contractPath; currentHeadEvidencePath = $currentHeadPath; currentSourceFixEvidencePath = $sourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_queue_transition_static_only;243_verifying;R4_runtime_build_device_and_legado_diff_deferred'; idempotent = $true }
  Write-AtomicJson $registrationPath $registration

  $refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
  $refreshOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $refreshScript -RefreshDocumentsOnly 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "derived document refresh failed:`n$refreshOutput" }
  Update-ObjectiveDocument
  Update-GovernanceDocument
  $post = Update-PostRegistrationEvidence
  $result = [pscustomobject][ordered]@{ status = 'registered'; issueId = $issue243; previousIssueId = $issue242; targetRevision = $revision; transitionEvidencePath = $transitionPath; registrationEvidencePath = $registrationPath; postRegistrationEvidencePath = $postRegistrationPath; assertions = $script:assertions; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; idempotent = $true }
} catch {
  $exitCode = 1
  $failure = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_jsoup_standard_pseudo_243_registration_failure'; status = 'failed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); issueId = $issue243; failure = $_.Exception.Message; assertions = $script:assertions; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_registration_static_only;R4_runtime_build_device_and_legado_diff_deferred' }
  try { Write-AtomicJson $failurePath $failure } catch { }
  $result = $failure
}
$result | ConvertTo-Json -Depth 100
if ($exitCode -ne 0) { exit $exitCode }
