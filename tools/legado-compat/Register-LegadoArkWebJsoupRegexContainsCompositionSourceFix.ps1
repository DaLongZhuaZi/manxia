[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-regex-contains-composition-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-regex-contains-composition-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-regex-contains-composition-source-fix-20260810.json'
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
$backupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_regex_contains_composition'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); Read-StrictText $Path | ConvertFrom-Json -Depth 100 }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 regex/contains source-fix gate failed: $Message" } }
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

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed') 'failure, post-fix and current-head evidence are incomplete.'
Assert-Gate (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence must not claim runtime or semantic match.'
Assert-Gate ($backup.Contains('if (ancestor.matches && ancestor.matches(pseudo.targetSelector))')) 'pre-fix backup does not capture the native-only branch.'
Assert-Gate ($runtime.Contains('legadoMatchesJsoupSelector(ancestor, pseudo.targetSelector, documentRoot)') -and -not $runtime.Contains('if (ancestor.matches && ancestor.matches(pseudo.targetSelector))')) 'current ArkWeb source does not retain the Jsoup-aware owning-compound bridge.'
Assert-Gate ($legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer is missing.'

$hashes = [ordered]@{}
foreach ($path in @($runtimePath, $legadoPath, 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets', 'entry/src/main/ets/libs/htmlparser/Matcher.ets')) { $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant() }
$closeCondition = 'R4 must execute all three ordinal-267 regex/contains composition cases, the existing 243 pseudo equivalence classes, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-arkweb-jsoup-repeated-ancestor-compound-source-fix-20260810.json'
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
    originalSemantics = 'Pinned Legado delegates the complete CSS selector to Jsoup; ~= is a regular expression and :contains is evaluated on the same owning element.'
    v2BeforeFix = 'ArkWeb used native ancestor.matches(targetSelector) while targetSelector still contained Jsoup ~= syntax, so the pseudo projection disagreed with the final selector evaluator.'
    v2AfterFix = 'ArkWeb resolves the owning compound through legadoMatchesJsoupSelector, reusing Jsoup regex, Java inline flags and text-pseudo semantics before applying the pseudo predicate.'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath)
  }
  consumerMatrix = [pscustomobject][ordered]@{ arkWeb = $runtimePath; stringFallback = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; dom = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'; legado = $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_regex_contains_composition_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = $closeCondition
}
Write-AtomicJson $SourceFixPath $sourceFix

$existingOrdinals = @($issue.affectedSourceOrdinals | ForEach-Object { [int]$_ })
Set-PropertyValue $issue 'affectedSourceOrdinals' @($existingOrdinals + @($fixture.affectedSourceOrdinals) | Sort-Object -Unique)
Set-PropertyValue $issue 'latestAffectedSourceOrdinals' @($fixture.affectedSourceOrdinals)
Set-PropertyValue $issue 'latestAffectedRuleStringCount' ([int]$sourceFix.affectedRuleStringCount)
Set-PropertyValue $issue 'rootCauseCategory' '规则解析或编译'
Set-PropertyValue $issue 'lastSourceFixEvidencePath' $SourceFixPath
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-arkweb-jsoup-regex-contains-composition-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_ARKWEB_REGEX_CONTAINS_COMPOSITION_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. ArkWeb regex-attribute plus :contains owning-compound projection is statically closed; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 owning-compound projection must use one Jsoup-compatible evaluator across ArkWeb manual pseudos, including regex attribute (~=) plus text-pseudo compositions.'
Set-PropertyValue $objective 'nextAction' '243 ArkWeb regex/contains composition source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
if ($null -ne $objective.PSObject.Properties['continuationTarget']) {
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 remains verifying; ordinal 267 regex/contains composition, failure witness, post-fix and current-head evidence are registered; R4 remains deferred.'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' 'Continue auditing selector owning-compound projections for remaining real combinations; keep runtime and differential gates deferred.'
}
$plan = @($objective.continuationPlan)
$completedMatches = @($plan | Where-Object { [string]$_.id -eq '243-SP-67' })
$completed = if ($completedMatches.Count -gt 0) { $completedMatches[0] } else { $null }
if ($null -eq $completed) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-67'; status = 'completed'; action = '修复 ArkWeb 目标 compound 使用原生 ancestor.matches 忽略 Jsoup ~= 正则，导致第 267 条书源 `a[href~=(-|_)\\d+]:contains(下一页)` 丢失的问题；改由 Jsoup-aware selector bridge 统一投影。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
} else {
  Set-PropertyValue $completed 'status' 'completed'
  Set-PropertyValue $completed 'action' '修复 ArkWeb 目标 compound 使用原生 ancestor.matches 忽略 Jsoup ~= 正则，导致第 267 条书源 regex + :contains 组合丢失的问题；改由 Jsoup-aware selector bridge 统一投影。'
  Set-PropertyValue $completed 'evidence' @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath)
}
$deferredMatches = @($plan | Where-Object { [string]$_.id -eq '243-SP-68' })
$deferred = if ($deferredMatches.Count -gt 0) { $deferredMatches[0] } else { $null }
if ($null -eq $deferred) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-68'; status = 'deferred'; action = 'R4 执行 ordinal 267 三个 regex/contains 组合案例、243 现有伪类等价类、458 条 Harness、Legado 差分、构建和真机验证。' }
} else {
  Set-PropertyValue $deferred 'status' 'deferred'
  Set-PropertyValue $deferred 'action' 'R4 执行 ordinal 267 三个 regex/contains 组合案例、243 现有伪类等价类、458 条 Harness、Legado 差分、构建和真机验证。'
}
Set-PropertyValue $objective 'continuationPlan' $plan
Write-AtomicJson $statePath $state
Write-AtomicJson $objectivePath $objective

$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $runtimePath, $backupPath, $legadoPath, 'tools/legado-compat/Test-LegadoArkWebJsoupRegexContainsCompositionFailureWitness.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupRegexContainsCompositionPostFixContract.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupRegexContainsCompositionCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoArkWebJsoupRegexContainsCompositionSourceFix.ps1')
$summary = '243 ArkWeb regex/contains composition closure: owning-compound projection now uses the Jsoup-aware selector bridge, preserving ~= regular-expression semantics before :contains. Ordinal 267 is bound to static failure, post-fix and current-head evidence. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; latestAffectedSourceCount = @($fixture.affectedSourceOrdinals).Count; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; governanceUpdate = $updateOutput.Trim() } | ConvertTo-Json -Depth 100
