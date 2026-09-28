[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-selector-group-occurrence-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-selector-group-occurrence-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-selector-group-occurrence-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$auditScriptPath = 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorCurrentHeadAudit.ps1'
$auditPreFixPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-current-head-audit-pre-fix-20260810.json'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100)
}

function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 selector-group occurrence source-fix gate failed: $Message" }
}

function Get-TextHash {
  param([Parameter(Mandatory = $true)][string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temp -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) }
  }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$auditPreFix = Read-StrictJson $auditPreFixPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$legado = Read-StrictText $legadoPath
$auditScript = Read-StrictText $auditScriptPath

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying; source closure cannot claim runtime completion.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_selector_group_occurrence_context' -and @($fixture.cases).Count -eq 2 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 97) 'selector-group occurrence fixture binding drifted.'
Assert-Gate ([string]$fixture.html -eq '<section><p>same</p><p>same</p></section>' -and [regex]::Matches([string]$fixture.html, '<p>same</p>').Count -eq 2) 'fixture must contain two distinct nodes with identical outerHTML.'
Assert-Gate ([int]$fixture.cases[0].expectedCount -eq 2 -and [int]$fixture.cases[1].expectedCount -eq 1) 'fixture must distinguish occurrence union from same-node de-duplication.'
Assert-Gate ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 8 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract must remain static-only.'
Assert-Gate ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 8 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$audit.semanticMatchAllowed) 'current-head audit must remain static-only.'
Assert-Gate ([string]$auditPreFix.status -eq 'failed' -and @($auditPreFix.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$auditPreFix.semanticMatchAllowed) 'stale current-head queue precondition failure witness must remain static-only.'
Assert-Gate ($auditScript.Contains("activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'") -and -not $auditScript.Contains("activeIssueId -eq 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'")) 'current-head audit must bind the active 243 issue after registration.'
Assert-Gate ($analyzer.Contains('private mergeSelectorGroupResultsByOccurrence(') -and $analyzer.Contains('const seenOffsets = new Set<number>();') -and $analyzer.Contains('const groupOccurrences = this.mapStringElementOccurrences(html, groupResults);') -and $analyzer.Contains('occurrences.sort(')) 'occurrence-aware selector-group consumer is absent.'
Assert-Gate ($analyzer.Contains('private annotateStringSelectorHtml(html: string, baseOffset: number): string') -and $analyzer.Contains('data-legado-occurrence-index')) 'selector-group evaluation must carry explicit source occurrence markers.'
Assert-Gate ($analyzer.Contains('private findAnnotatedSelectorOccurrences(') -and $analyzer.Contains('const absoluteOffset = parseInt(markerMatch[1], 10);')) 'marked selector results must be restored to source occurrences.'
Assert-Gate ($analyzer.Contains('const selectionContextHtml = needsOccurrenceMarkers') -and $analyzer.Contains('return this.stripStringSelectorOccurrenceMarker(element);')) 'large-document CSS chains must preserve and strip occurrence markers at the workflow boundary.'
Assert-Gate ($analyzer.Contains('if (html.includes(') -and $analyzer.Contains('data-legado-occurrence-index') -and $analyzer.Contains('return html;')) 'occurrence annotation must be idempotent across nested selector evaluation.'
Assert-Gate ($analyzer.Contains('originalHtml.includes(') -and $analyzer.Contains('stripStringSelectorOccurrenceMarker(markedResult)')) 'nested marked fragments must preserve absolute offsets while restoring unmarked elements.'
Assert-Gate ($element.Contains('const seen = new Set<HTMLElement>();')) 'DOM selector-group consumer must remain object-identity based.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-of-type-source-fix-20260810.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado delegates selector groups to Jsoup Element.select; equal outerHTML from distinct matching nodes must remain distinct occurrences, while the same node matched by multiple groups is returned once in document order.'
    v2BeforeFix = 'The large-document string fallback merged top-level comma selector groups with Set<string> over outerHTML values, collapsing distinct nodes that happened to serialize identically; its indexOf-based context projection also remapped positional pseudo results to the first equal outerHTML occurrence.'
    v2AfterFix = 'The fallback annotates each source tag with an internal occurrence offset while evaluating context-sensitive CSS chains, maps selector-group results back to those offsets, de-duplicates only equal offsets, sorts the union by document position, and strips markers before workflow output. The DOM Matcher continues to use HTMLElement object identity and the pinned Legado consumer remains the semantic reference.'
    evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $FixturePath)
  }
  changedPaths = @($analyzerPath, $auditScriptPath)
  auditPreconditionFix = [pscustomobject][ordered]@{
    status = 'source_closed_static_only'
    failureEvidence = $auditPreFixPath
    repairedEvidence = $CurrentHeadAuditPath
    changedPath = $auditScriptPath
    rootCause = 'The historical 243 current-head audit retained a pre-registration active-issue assertion for 242 and therefore failed after 243 became the machine-fact queue anchor.'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
  consumerMatrix = [pscustomobject][ordered]@{ selectorGroupFallback = $analyzerPath; dom = $elementPath; arkWeb = 'entry/src/main/resources/rawfile/legado_runtime.html'; legado = $legadoPath }
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element; $legadoPath = Get-TextHash $legado }
  affectedSourceOrdinals = @(97)
  ruleStringCount = 1
  assertions = [int]$contract.assertions + [int]$audit.assertions + [int]$auditPreFix.assertions + 1
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_selector_group_occurrence_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute both selector-group occurrence cases with existing 243 pseudo-selector/sibling equivalence classes, affected source ordinal 97, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-selector-group-occurrence-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. Selector-group occurrence identity extends the existing static closure; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility now includes occurrence-aware comma selector-group union and marker-preserving large-document CSS-chain semantics; equal outerHTML from distinct nodes is preserved, same occurrences are de-duplicated by offset, and R4 remains deferred.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, selector-group occurrence identity and nested marker restoration are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 selector-group occurrence source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-18' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-18'; status = 'completed'; action = '固定逗号选择器组的 occurrence identity：按源偏移合并，保留相同 outerHTML 的不同节点并按文档顺序输出；登记第 97 条书源失败见证和静态消费者合同。'; evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-19'; status = 'deferred'; action = 'R4 执行 selector-group occurrence 等价类、全部 243 规则集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-20' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-20'; status = 'completed'; action = '修复 243 current-head 审计残留 242 活动议题前置条件；保留失败见证，改为绑定机器事实 243，并重新生成静态通过证据。'; evidence = @($auditPreFixPath, $CurrentHeadAuditPath, $auditScriptPath) }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $auditPreFixPath, $auditScriptPath, 'tools/legado-compat/Test-LegadoJsoupSelectorGroupOccurrenceFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupSelectorGroupOccurrencePostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupSelectorGroupOccurrenceCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupSelectorGroupOccurrenceSourceFix.ps1', $analyzerPath, $elementPath, $legadoPath)
$summary = '243 selector-group occurrence identity is statically closed: the large-document fallback now carries internal source-offset markers through context-sensitive CSS chains, merges comma selector groups by occurrence, preserves distinct nodes with equal outerHTML, removes only the same occurrence across groups, restores nested marked fragments and strips markers at the workflow boundary. A stale 242 active-issue assertion in the historical 243 current-head audit was also witnessed and repaired; current evidence is static-only and R4 remains deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; assertions = $sourceFix.assertions; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
