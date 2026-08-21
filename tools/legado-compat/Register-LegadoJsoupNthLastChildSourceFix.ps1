[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-nth-last-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nth-last-child-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nth-last-child-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-nth-last-child-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-nth-last-child-source-fix-20260810.json'
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
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzerBackupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_issue243_nth_last_child'
$elementBackupPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets.bak_20260810_issue243_nth_last_child'
$runtimeBackupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_nth_last_child'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
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
  if (-not $Condition) { throw "243 nth-last-child source-fix gate failed: $Message" }
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

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$analyzerBackup = Read-StrictText $analyzerBackupPath
$elementBackup = Read-StrictText $elementBackupPath
$runtimeBackup = Read-StrictText $runtimeBackupPath
$issue = $state.governance.issues | Where-Object { [string]$_.id -eq $issueId } | Select-Object -First 1

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$fixture.contract -eq 'legado_jsoup_nth_last_child_context' -and [int]$fixture.sourcePackageScan.nthLastChildRuleStringCount -eq 0 -and @($fixture.sourcePackageScan.affectedSourceOrdinals).Count -eq 0) 'fixture or package scan drifted.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed') 'failure, post-fix and current-head evidence are incomplete.'
Assert-Gate (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'evidence is not static-only.'
Assert-Gate (-not $analyzerBackup.Contains("pseudo.name === 'nth-last-child'") -and -not $elementBackup.Contains("pseudo.name === 'nth-last-child'") -and -not $runtimeBackup.Contains("pseudoName === 'nth-last-child'")) 'pre-fix backups do not prove the missing branches.'
Assert-Gate ($analyzer.Contains("pseudo.name === 'nth-last-child'") -and $element.Contains("pseudo.name === 'nth-last-child'") -and $runtime.Contains("pseudoName === 'nth-last-child'") -and $runtime.Contains('siblingCount - siblingIndexOneBased + 1')) 'current consumers do not contain the reverse child-position repair.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer is missing.'

$hashes = [ordered]@{}
foreach ($path in @($runtimePath, $elementPath, $analyzerPath, $legadoPath)) {
  $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant()
}
$closeCondition = 'R4 must execute all four nth-last-child fixture cases, the existing 243 pseudo equivalence classes, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
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
  changedPaths = @($runtimePath, $elementPath, $analyzerPath)
  backupPaths = @($runtimeBackupPath, $elementBackupPath, $analyzerBackupPath)
  backupHashes = [ordered]@{
    $runtimeBackupPath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $runtimeBackupPath)).Hash.ToUpperInvariant()
    $elementBackupPath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $elementBackupPath)).Hash.ToUpperInvariant()
    $analyzerBackupPath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerBackupPath)).Hash.ToUpperInvariant()
  }
  currentHeadHashes = $hashes
  fixturePath = $FixturePath
  affectedSourceOrdinals = @()
  affectedRuleStringCount = 0
  sourcePackageScan = [pscustomobject][ordered]@{ scannedSourceCount = 458; nthLastChildRuleStringCount = 0; affectedSourceOrdinals = @() }
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado delegates CSS selection to Jsoup, where nth-last-child counts all element siblings and evaluates a one-based position from the end; top-level Document children remain outside child-pseudo semantics.'
    v2BeforeFix = 'The V2 parser listed nth-last-child as a standard Document pseudo, but ArkWeb manual matching, HTMLElement.matchesPseudoClass and the large-document string fallback had no reverse child-position branch.'
    v2AfterFix = 'ArkWeb, DOM Matcher and string fallback now compute the reverse 1-based element-child position and reuse the existing synthetic Document boundary guard.'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath)
  }
  consumerMatrix = [pscustomobject][ordered]@{ arkWeb = $runtimePath; dom = $elementPath; stringFallback = $analyzerPath; legado = $legadoPath }
  currentPackageImpact = 'The frozen 458-source package contains zero nth-last-child rule strings and zero affected ordinals; this general compatibility closure does not claim a source-specific pass or failure.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_nth_last_child_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = $closeCondition
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $issue 'latestAffectedSourceOrdinals' @()
Set-PropertyValue $issue 'latestAffectedRuleStringCount' 0
Set-PropertyValue $issue 'lastSourceFixEvidencePath' $SourceFixPath
Set-PropertyValue $issue 'rootCauseCategory' '规则解析或编译'
Set-PropertyValue $issue 'summary' '243 nth-last-child reverse element-child semantics are statically closed across ArkWeb synthetic Document, DOM Matcher and large-document string fallback. The frozen 458-source package has zero occurrences; runtime, full Harness, Legado differential, build and device validation remain deferred.'
Set-PropertyValue $issue 'closeCondition' $closeCondition
Set-PropertyValue $issue 'lastUpdatedAt' $now
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-nth-last-child-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_NTH_LAST_CHILD_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. nth-last-child reverse element-child semantics are statically closed across all V2 consumers; the frozen package has zero occurrences, semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility must implement nth-last-child as a one-based reverse position over all element siblings in ArkWeb synthetic Document, DOM Matcher and large-document string fallback, while preserving the Jsoup Document boundary.'
if ($null -ne $objective.PSObject.Properties['executionTarget']) {
  Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, nth-last-child reverse element-child semantics and selector-root preservation are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
}
Set-PropertyValue $objective 'nextAction' '243 nth-last-child source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
if ($null -ne $objective.PSObject.Properties['continuationTarget']) {
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 remains verifying; nth-last-child has three consumer branches, four static cases and zero frozen-package occurrences; R4 remains deferred.'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' 'Continue auditing remaining standard pseudo and selector-root semantics; keep runtime and differential gates deferred.'
}
$plan = @($objective.continuationPlan)
$completedStep = $plan | Where-Object { [string]$_.id -eq '243-SP-65' } | Select-Object -First 1
if ($null -eq $completedStep) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-65'; status = 'completed'; action = '补齐 ArkWeb 合成 Document、DOM Matcher 与大文档字符串回退的 nth-last-child 反向元素兄弟语义；固定包扫描为 0 条，不伪造源失败。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
} else {
  Set-PropertyValue $completedStep 'status' 'completed'
  Set-PropertyValue $completedStep 'evidence' @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath)
}
$deferredStep = $plan | Where-Object { [string]$_.id -eq '243-SP-66' } | Select-Object -First 1
if ($null -eq $deferredStep) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-66'; status = 'deferred'; action = 'R4 执行四个 nth-last-child 案例、现有 243 伪类等价类、458 条 Harness、Legado 差分、构建和真机验证。' }
} else {
  Set-PropertyValue $deferredStep 'status' 'deferred'
}
Set-PropertyValue $objective 'continuationPlan' $plan
Write-AtomicJson $statePath $state
Write-AtomicJson $objectivePath $objective

$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $runtimePath, $elementPath, $analyzerPath, $runtimeBackupPath, $elementBackupPath, $analyzerBackupPath, 'tools/legado-compat/Test-LegadoJsoupNthLastChildFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupNthLastChildPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupNthLastChildCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupNthLastChildSourceFix.ps1', $legadoPath)
$summary = '243 nth-last-child reverse element-child semantics are statically closed across ArkWeb synthetic Document, DOM Matcher and large-document string fallback. The frozen 458-source package has zero occurrences; runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; affectedSourceOrdinals = @(); affectedRuleStringCount = 0; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; governanceUpdate = $updateOutput.Trim() } | ConvertTo-Json -Depth 100
