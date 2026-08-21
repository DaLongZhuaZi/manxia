[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-not-selector-ancestor-context.json',
  [string]$AncestorFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-pre-fix-20260810.json',
  [string]$BulkFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-not-selector-ancestor-bulk-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-not-selector-ancestor-bulk-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Get-PropertyValue { param([object]$Object, [string]$Name, [object]$Default = $null); if ($null -eq $Object) { return $Default }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property -or $null -eq $property.Value) { return $Default }; return $property.Value }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :not ancestor bulk source-fix gate failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$ancestorFailure = Read-StrictJson $AncestorFailureWitnessPath
$bulkFailure = Read-StrictJson $BulkFailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]
Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 3) 'ancestor-context fixture binding drifted.'
Assert-Gate ([string]$ancestorFailure.status -eq 'failed' -and [string]$bulkFailure.status -eq 'failed' -and @($ancestorFailure.runtimeActionsPerformed).Count -eq 0 -and @($bulkFailure.runtimeActionsPerformed).Count -eq 0) 'failure witnesses must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 16 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'bulk post-fix contract must remain static-only.'
Assert-Gate ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 9 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$audit.semanticMatchAllowed) 'bulk current-head audit must remain static-only.'

$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath
Assert-Gate ($analyzer.Contains('private collectNestedSelectorMatchOffsets(contextHtml: string, selector: string): Set<number>') -and -not $analyzer.Contains('this.matchesStringNestedSelectorAtOccurrence(element, argument, contextHtml, occurrence.startIndex)')) 'bulk occurrence projection fix is absent or still per-candidate.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-not-selector-ancestor-source-fix-20260810.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Legado evaluates :not selector groups in the complete document context and each matching Element keeps its own node identity.'
    v2BeforeFix = 'The full-context repair evaluated the selector independently for every candidate, repeatedly rescanning the complete large response and risking quadratic work/ANR.'
    v2AfterFix = 'The :not branch evaluates each top-level selector group once, collects matched occurrence offsets in a typed Set, and filters candidates by their precomputed offsets; only incomplete occurrence mappings use the explicit safe fallback.'
    evidence = @($AncestorFailureWitnessPath, $BulkFailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $FixturePath)
  }
  changedPaths = @($analyzerPath)
  consumerMatrix = [pscustomobject][ordered]@{ cssChain = $analyzerPath; stringFallback = $analyzerPath; dom = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; arkWeb = 'entry/src/main/resources/rawfile/legado_runtime.html'; legado = $legadoPath }
  fixturePath = $FixturePath
  failureEvidence = @($AncestorFailureWitnessPath, $BulkFailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer }
  assertions = [int]$contract.assertions + [int]$audit.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_not_selector_ancestor_bulk_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute full-ancestor :not semantics, duplicate occurrence cases, the existing 243 pseudo equivalence classes, affected source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-not-full-ancestor-bulk-projection-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility now includes full document ancestor context, duplicate occurrence identity and bulk offset projection for complex :not selectors in the large-document fallback; R4 remains deferred.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, :has relative-selector context, :not ancestor context, duplicate occurrence identity and one-scan-per-selector-group projection are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 full-context :not bulk projection static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-12' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-12'; status = 'completed'; action = '固定完整上下文 :not 的全文扫描复杂度，登记逐候选扫描失败见证并改为按 selector group 一次收集 occurrence offsets。'; evidence = @($AncestorFailureWitnessPath, $BulkFailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-13'; status = 'deferred'; action = 'R4 执行 243 全部 :not 上下文与性能等价类、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $AncestorFailureWitnessPath, $BulkFailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, 'tools/legado-compat/Apply-LegadoJsoupNotSelectorAncestorContextFix.ps1', 'tools/legado-compat/Apply-LegadoJsoupNotSelectorAncestorBulkProjectionFix.ps1', 'tools/legado-compat/Test-LegadoJsoupNotSelectorAncestorFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupNotSelectorAncestorBulkFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupNotSelectorAncestorPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupNotSelectorAncestorBulkPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupNotSelectorAncestorCurrentHeadAudit.ps1', 'tools/legado-compat/Test-LegadoJsoupNotSelectorAncestorBulkCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupNotSelectorAncestorSourceFix.ps1', 'tools/legado-compat/Register-LegadoJsoupNotSelectorAncestorBulkSourceFix.ps1', $analyzerPath, $legadoPath)
$summary = '243 :not full-context bulk projection is statically closed: top-level selector groups are evaluated once and candidate occurrence offsets are filtered from a typed set, eliminating per-candidate full-response rescans while retaining the explicit incomplete-mapping fallback. Two failure witnesses, post-fix/current-head evidence and source-fix are registered. R4 deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; assertions = $sourceFix.assertions; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
