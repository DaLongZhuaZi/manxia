[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-mixed-descendant-direct-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-mixed-descendant-direct-child-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-mixed-descendant-direct-child-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-mixed-descendant-direct-child-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-mixed-descendant-direct-child-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-mixed-descendant-direct-child-static-closure'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$backupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_mixed_descendant_direct_child'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 mixed-chain source-fix gate failed: $Message" } }
function Get-Hash { param([Parameter(Mandatory = $true)][string]$Path); return (Get-FileHash -LiteralPath (Get-RepoPath $Path) -Algorithm SHA256).Hash.ToUpperInvariant() }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }
function Write-AtomicText { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Value); $resolved = Get-RepoPath $Path; $temp = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, $Value, $noBomUtf8); Move-Item -LiteralPath $temp -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }
function Replace-Section { param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$StartMarker, [Parameter(Mandatory = $true)][string]$EndMarker, [Parameter(Mandatory = $true)][string]$Replacement); $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'; if (-not [regex]::IsMatch($Text, $pattern)) { throw "document section missing: $StartMarker" }; return [regex]::Replace($Text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement }) }

$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$fixture = Read-StrictJson -Path $FixturePath
$failure = Read-StrictJson -Path $FailureWitnessPath
$contract = Read-StrictJson -Path $PostFixContractPath
$audit = Read-StrictJson -Path $CurrentHeadAuditPath
$analyzer = Read-StrictText -Path $analyzerPath
$backup = Read-StrictText -Path $backupPath
$runtime = Read-StrictText -Path $runtimePath
$legado = Read-StrictText -Path $legadoPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying; static closure cannot claim runtime completion.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 2 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 97) 'mixed-chain fixture binding drifted.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed') 'failure, post-fix and current-head evidence are incomplete.'
Assert-Gate (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence must not contain runtime actions or semantic match.'
Assert-Gate ($analyzer.Contains('let currentElements = this.findElementsBySingleSelector(html, firstSelector, effectiveContextHtml);') -and $backup.Contains('let currentElements = this.findElementsBySimpleSelector(html, firstSelector, effectiveContextHtml);')) 'current source and pre-fix backup do not prove the exact change.'
Assert-Gate ($runtime.Contains('querySelectorAll') -and $legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'consumer matrix is incomplete.'

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-source-fix-20260809.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($analyzerPath)
  backupPath = $backupPath
  backupSha256 = Get-Hash -Path $backupPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-Hash -Path $analyzerPath }
  affectedSourceOrdinals = @(97)
  ruleStringCount = 1
  rulePaths = @('$[96].ruleToc.chapterList')
  fixturePath = $FixturePath
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado delegates the complete CSS selector to Jsoup Element.select, so a descendant left operand is resolved before a direct-child relation.'
    v2BeforeFix = 'findElementsByDirectChildSelector split top-level > correctly but evaluated the left segment through findElementsBySimpleSelector, which only consumes the first class/tag token and drops descendant combinators and pseudo classes.'
    v2AfterFix = 'The left segment is routed through findElementsBySingleSelector, preserving its complete descendant/sibling/pseudo semantics before the helper applies direct-child matching.'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath)
  }
  consumerMatrix = [pscustomobject][ordered]@{ stringFallback = $analyzerPath; arkWeb = $runtimePath; legado = $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_mixed_descendant_direct_child_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute both mixed descendant/direct-child cases, affected source ordinal 97, existing 243 selector equivalence classes, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $SourceFixPath -Value $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective -Name 'lastReviewedAt' -Value $now
Set-PropertyValue $objective -Name 'targetRevision' -Value $revision
Set-PropertyValue $objective -Name 'continuationMode' -Value 'R3_ISSUE_243_MIXED_DESCENDANT_DIRECT_CHILD_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority -Name 'activeIssueId' -Value $issueId
Set-PropertyValue $objective.authority -Name 'activeIssueSelection' -Value 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. The mixed descendant/direct-child selector repair is static-only; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective -Name 'currentWorkstream' -Value 'R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
Set-PropertyValue $objective.objective -Name 'activeIssueRule' -Value '243 mixed CSS chains must evaluate a complete descendant left operand before applying a top-level direct-child relation; the frozen ordinal 97 TOC selector is the witness.'
Set-PropertyValue $objective -Name 'nextAction' -Value '243 mixed descendant/direct-child source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$continuationTarget = $objective.continuationTarget
Set-PropertyValue $continuationTarget -Name 'activeBoundary' -Value '243 保持 verifying；mixed descendant/direct-child 左操作数已改为完整选择器派发，失败见证、post-fix/current-head/source-fix 证据已登记；242 保持 verifying 等待 R4。'
Set-PropertyValue $continuationTarget -Name 'nextTransition' -Value '继续审计 243 的多级链、重复兄弟和伪类组合；R4 运行时与差分保持延期。'
$queueAudit = $continuationTarget.queueAudit
Set-PropertyValue $queueAudit -Name 'id' -Value 'R3-ISSUE-243-MIXED-CHAIN-SOURCE-GATE'
Set-PropertyValue $queueAudit -Name 'status' -Value 'source_fix_static_closed_wait_r4'
Set-PropertyValue $queueAudit -Name 'activeIssueId' -Value $issueId
Set-PropertyValue $queueAudit -Name 'currentAnchor' -Value $issueId
Set-PropertyValue $queueAudit -Name 'selectedIssue' -Value $issueId
Set-PropertyValue $queueAudit -Name 'selectionPolicy' -Value '只读枚举 full-source-validation-state.json；243 是唯一活动源码议题并保持 verifying；242 作为历史前一议题等待 R4，不得重新激活第二根因。'
Set-PropertyValue $queueAudit -Name 'candidateIssueId' -Value $issueId
Set-PropertyValue $queueAudit -Name 'candidateStatus' -Value 'source_fix_static_closed'
Set-PropertyValue $queueAudit -Name 'candidateGateStatus' -Value 'source_fix_static_closed_wait_r4'
Set-PropertyValue $queueAudit -Name 'candidateSourceFixEvidencePath' -Value $SourceFixPath
Set-PropertyValue $queueAudit -Name 'sourceFixEvidencePath' -Value $SourceFixPath
Set-PropertyValue $queueAudit -Name 'failureWitnessPath' -Value $FailureWitnessPath
Set-PropertyValue $queueAudit -Name 'currentHeadEvidencePath' -Value $CurrentHeadAuditPath
Set-PropertyValue $queueAudit -Name 'postFixContractEvidencePath' -Value $PostFixContractPath
Set-PropertyValue $queueAudit -Name 'priorActiveIssueId' -Value 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'
Set-PropertyValue $queueAudit -Name 'nextRequired' -Value 'R4 前不启动运行时；继续只审计 243 的单一源码根因，发现新根因时先补齐五项静态证据。'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-47' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-47'; status = 'completed'; action = '登记第 97 条书源混合 descendant/direct-child 选择器的失败见证，并将 > 左操作数接入完整选择器派发。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-48'; status = 'deferred'; action = 'R4 执行混合链等价类、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective -Name 'continuationPlan' -Value $plan
}
Write-AtomicJson -Path $objectivePath -Value $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $analyzerPath, $backupPath, 'tools/legado-compat/Test-LegadoJsoupMixedDescendantDirectChildFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupMixedDescendantDirectChildPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupMixedDescendantDirectChildCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupMixedDescendantDirectChildSourceFix.ps1', $legadoPath)
$summary = '243 mixed descendant/direct-child selector closure: ordinal 97 uses .book_list2 .col-md-3:nth-child(n+1) > a; the > left operand now goes through the complete selector dispatcher. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$closeCondition = [string]$sourceFix.closeCondition
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$updateOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

$objectiveDocumentPath = Get-RepoPath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText -Path 'docs/analysis/Legado书源V2源码重构持续目标.md'
$revisionSection = @"
## 当前修订

目标 ID：LEGADO-V2-SOURCE-CLOSURE-R3-20260808  
当前修订：$revision  
父任务：COMPAT-006  
工作流：R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS

当前唯一活动源码议题为 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS，状态为 verifying。源码审计已绑定固定包第 97 条书源的 `.book_list2 .col-md-3:nth-child(n+1) > a`：direct-child helper 现在先用完整选择器派发解析 `>` 左侧的 descendant 与 `:nth-child`，再应用直接子关系。该修复只完成静态证据闭合，R4 运行时、458 条 Harness、Legado 差分、构建和真机验证仍延期。

"@
$objectiveDocument = Replace-Section -Text $objectiveDocument -StartMarker '## 当前修订' -EndMarker '## 下一持续执行目标' -Replacement $revisionSection
$nextSection = @"
## 下一持续执行目标

继续以 ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS 为唯一源码活动边界：审计多级链、重复兄弟和伪类组合；每个新根因先补齐固定 Legado 语义、受影响规则、失败见证、V2 消费者矩阵和关闭条件，再修改源码。当前新增证据为 $FixturePath、$FailureWitnessPath、$PostFixContractPath、$CurrentHeadAuditPath、$SourceFixPath。本轮没有执行运行时、网络、构建、安装、设备或 Legado 差分，243 与历史 242 均保持 verifying，不能报告为语义兼容完成。

"@
$objectiveDocument = Replace-Section -Text $objectiveDocument -StartMarker '## 下一持续执行目标' -EndMarker '## 持续目标' -Replacement $nextSection
Write-AtomicText -Path 'docs/analysis/Legado书源V2源码重构持续目标.md' -Value $objectiveDocument

[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; assertions = 9; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
