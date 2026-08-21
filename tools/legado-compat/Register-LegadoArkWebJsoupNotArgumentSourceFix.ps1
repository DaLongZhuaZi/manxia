[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-not-argument-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-not-argument-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-not-argument-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-not-argument-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-not-argument-source-fix-20260810.json'
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
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$backupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_not_argument_context'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 :not argument source-fix gate failed: $Message" } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$runtime = Read-StrictText $runtimePath
$backup = Read-StrictText $backupPath
$legado = Read-StrictText $legadoPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed') 'failure, post-fix and current-head evidence are incomplete.'
Assert-Gate (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence must not claim runtime or semantic match.'
Assert-Gate ($backup.Contains('legadoMatchesJsoupSelector(node, groups[groupIndex], documentRoot)') -and -not $backup.Contains('legadoMatchesJsoupSelectorInContext')) 'the pre-fix backup does not capture the local-only :not argument matcher.'
Assert-Gate ($runtime.Contains('var legadoMatchesJsoupSelectorInContext = function') -and $runtime.Contains('legadoSelectWithJsoupRegex(selectionRoot, selector, documentRoot)')) 'current ArkWeb source does not retain full-context :not argument matching.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer is missing.'

$hashes = [ordered]@{}
foreach ($path in @($runtimePath, $legadoPath)) { $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant() }
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-arkweb-jsoup-compound-pseudo-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($runtimePath)
  backupPath = $backupPath
  backupSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $backupPath)).Hash.ToUpperInvariant()
  currentHeadHashes = $hashes
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  affectedRuleStringCount = @($fixture.affectedRuleStrings).Count
  fixturePath = $FixturePath
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado evaluates each :not argument through Jsoup selection in the complete Element context and preserves selector-list identity.'
    v2BeforeFix = 'ArkWeb delegated :not arguments only to node.matches(browserSelector), so ancestor combinators and nested selector lists were treated as non-matches.'
    v2AfterFix = 'ArkWeb retains the node.matches fast path and falls back to legadoSelectWithJsoupRegex over the available document or parent root, projecting the same candidate node.'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath)
  }
  consumerMatrix = [pscustomobject][ordered]@{ arkWeb = $runtimePath; stringFallback = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; dom = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; legado = $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_not_argument_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute all three :not argument cases, ordinal 402, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$existingOrdinals = @($issue.affectedSourceOrdinals | ForEach-Object { [int]$_ })
$mergedOrdinals = @($existingOrdinals + $fixture.affectedSourceOrdinals | Sort-Object -Unique)
Set-PropertyValue $issue 'affectedSourceOrdinals' $mergedOrdinals
Set-PropertyValue $issue 'latestAffectedSourceOrdinals' @($fixture.affectedSourceOrdinals)
Set-PropertyValue $issue 'latestAffectedRuleStringCount' ([int]$sourceFix.affectedRuleStringCount)
Set-PropertyValue $issue 'rootCauseCategory' '规则解析或编译'
Set-PropertyValue $issue 'lastSourceFixEvidencePath' $SourceFixPath
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-arkweb-jsoup-not-argument-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_ARKWEB_NOT_ARGUMENT_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. ArkWeb :not argument context is statically closed; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 covers owning compounds and nested selector arguments: :not groups must be evaluated in the complete available root and project the same candidate identity, without bypassing synthetic Document or relative :has semantics.'
Set-PropertyValue $objective 'nextAction' '243 ArkWeb :not argument source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
if ($null -ne $objective.PSObject.Properties['continuationTarget']) {
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 remains verifying; ArkWeb :not argument context, ordinal 402, failure witness, post-fix and current-head evidence are registered; R4 remains deferred.'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' 'Continue auditing 243 for nested selector lists, relative roots and repeated compound projection; keep runtime and differential gates deferred.'
}
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-57' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-57'; status = 'completed'; action = '修复 ArkWeb :not 参数只能使用 node.matches 导致祖先组合和选择器列表上下文丢失，并登记第 402 条书源的真实规则。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-58'; status = 'deferred'; action = 'R4 执行三个 :not 参数案例、第 402 条书源、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $statePath $state
Write-AtomicJson $objectivePath $objective

$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $runtimePath, $backupPath, 'tools/legado-compat/Test-LegadoArkWebJsoupNotArgumentFailureWitness.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupNotArgumentPostFixContract.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupNotArgumentCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoArkWebJsoupNotArgumentSourceFix.ps1', $legadoPath)
$summary = '243 ArkWeb :not argument closure: nested selector lists and ancestor combinators now retain the complete selection root and project candidate identity after the owning compound is resolved. Ordinal 402 is bound to static failure, post-fix and current-head evidence. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; latestAffectedSourceCount = @($fixture.affectedSourceOrdinals).Count; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; governanceUpdate = $updateOutput.Trim() } | ConvertTo-Json -Depth 100
