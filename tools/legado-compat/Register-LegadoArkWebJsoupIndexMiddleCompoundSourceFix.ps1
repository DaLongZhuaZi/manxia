[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-index-middle-compound-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-index-middle-compound-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-index-middle-compound-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-index-middle-compound-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-index-middle-compound-source-fix-20260810.json'
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
$backupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_middle_compound_pseudo'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}
function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value }
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}
function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ArkWeb 243 index middle-compound source-fix gate failed: $Message" }
}

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
Assert-Gate ([string]$failure.sourcePackageHash -eq $baselineHash -and @($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0) 'evidence is not bound to the fixed package or static-only policy.'
Assert-Gate ($backup.Contains("var siblingIndex = legadoElementSiblingIndex(node);")) 'backup does not capture the pre-fix terminal-node branch.'
Assert-Gate ($runtime.Contains("var siblingIndex = legadoElementSiblingIndex(predicateNode);") -and -not $runtime.Contains("var siblingIndex = legadoElementSiblingIndex(node);")) 'current ArkWeb source does not retain the owning predicateNode repair.'
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
  extends = 'tools/legado-compat/evidence/v2-arkweb-jsoup-empty-compound-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($runtimePath)
  backupPath = $backupPath
  backupSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $backupPath)).Hash.ToUpperInvariant()
  currentHeadHashes = $hashes
  affectedSourceOrdinals = @()
  syntheticCaseCount = @($fixture.cases).Count
  fixturePath = $FixturePath
  sourcePackageScan = [pscustomobject][ordered]@{ scannedSourceCount = [int]$fixture.sourcePackageScan.scannedSourceCount; indexPseudoRuleStringCount = [int]$fixture.sourcePackageScan.indexPseudoRuleStringCount; middleCompoundRuleStringCount = [int]$fixture.sourcePackageScan.middleCompoundRuleStringCount }
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado delegates the complete CSS selector to Jsoup, and IndexEquals/IndexLessThan evaluate the element belonging to their own compound.'
    v2BeforeFix = 'ArkWeb retained predicateNode for most manual pseudos but the eq/lt branch called legadoElementSiblingIndex(node), so a non-terminal pseudo inspected the terminal querySelectorAll candidate.'
    v2AfterFix = 'The eq/lt branch calls legadoElementSiblingIndex(predicateNode), preserving the owning compound before descendant projection.'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath)
  }
  consumerMatrix = [pscustomobject][ordered]@{ arkWeb = $runtimePath; legado = $legadoPath; stringFallback = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; dom = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets' }
  currentPackageImpact = 'The frozen 458-source package has six terminal-only eq/lt rule strings and zero middle-compound occurrences; this source fix closes a general compatibility gap without assigning a false source failure.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_index_middle_compound_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute all four synthetic middle-compound cases, the six terminal frozen-package cases, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

Set-PropertyValue $issue 'latestAffectedSourceOrdinals' @()
Set-PropertyValue $issue 'latestAffectedRuleStringCount' 0
Set-PropertyValue $issue 'lastSourceFixEvidencePath' $SourceFixPath
Set-PropertyValue $issue 'rootCauseCategory' '规则解析或编译'
Set-PropertyValue $issue 'summary' '243 ArkWeb index-pseudo owning-compound closure: eq/lt now evaluate predicateNode for non-terminal compounds. The frozen package has six terminal-only index-pseudo strings and zero middle-compound occurrences; four synthetic cases protect general Legado semantics. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
Set-PropertyValue $issue 'closeCondition' ([string]$sourceFix.closeCondition)
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-arkweb-jsoup-index-middle-compound-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_ARKWEB_INDEX_MIDDLE_COMPOUND_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. ArkWeb index-pseudo owning-compound repair is statically closed; the frozen package has no affected middle-compound rule, semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 covers owning compounds and selector-root preservation: every manually evaluated pseudo, including eq and lt, must retain the element token and element context of its own compound before terminal projection.'
Set-PropertyValue $objective 'nextAction' '243 ArkWeb index-pseudo owning-compound source closure is registered; continue the single-root-cause static audit while R4 remains deferred.'
if ($null -ne $objective.PSObject.Properties['continuationTarget']) {
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 remains verifying; eq/lt owning-compound context is statically closed with four synthetic cases and zero frozen-package middle-compound occurrences; R4 remains deferred.'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' 'Continue auditing selector-root preservation for standard pseudos; keep runtime and differential gates deferred.'
}
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-61' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-61'; status = 'completed'; action = '修复 ArkWeb 中间 compound 的 :eq/:lt 仍读取终端候选 node 而不是 owning predicateNode 的语义缺口；固定 458 条书源扫描确认 6 条终端规则、0 条中间规则，新增四个合成保护案例。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-62'; status = 'deferred'; action = 'R4 执行四个中间 compound 合成案例、六个固定包 index pseudo 案例、458 条 Harness、Legado 差分、构建和真机验证。' }
} else {
  $completed = @($plan | Where-Object { [string]$_.id -eq '243-SP-61' })[0]
  Set-PropertyValue $completed 'status' 'completed'
  Set-PropertyValue $completed 'evidence' @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath)
}
Set-PropertyValue $objective 'continuationPlan' $plan
Write-AtomicJson $statePath $state
Write-AtomicJson $objectivePath $objective

$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $runtimePath, $backupPath, 'tools/legado-compat/Test-LegadoArkWebJsoupIndexMiddleCompoundFailureWitness.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupIndexMiddleCompoundPostFixContract.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupIndexMiddleCompoundCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoArkWebJsoupIndexMiddleCompoundSourceFix.ps1', $legadoPath)
$summary = '243 ArkWeb index-pseudo owning-compound closure: eq/lt now evaluate predicateNode for non-terminal compounds. Frozen 458-source scan records six terminal-only index-pseudo strings and zero middle-compound occurrences; four synthetic cases protect general Legado semantics. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; frozenPackageAffectedSourceCount = 0; syntheticCaseCount = @($fixture.cases).Count; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; governanceUpdate = $updateOutput.Trim() } | ConvertTo-Json -Depth 100
