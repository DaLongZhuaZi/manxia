[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-repeated-ancestor-compound-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-repeated-ancestor-compound-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-repeated-ancestor-compound-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-repeated-ancestor-compound-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-arkweb-jsoup-repeated-ancestor-compound-source-fix-20260810.json'
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
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$backupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_repeated_ancestor_compound'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
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
  param(
    [Parameter(Mandatory = $true)][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    [object]$Value
  )
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}
function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "ArkWeb 243 repeated-ancestor compound source-fix gate failed: $Message"
  }
}
function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) {
      [System.IO.File]::Delete($temporary)
    }
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
$runtime = Read-StrictText $runtimePath
$backup = Read-StrictText $backupPath
$legado = Read-StrictText $legadoPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]
$sourceOrdinals = @($fixture.affectedSourceSet.sourceOrdinals | ForEach-Object { [int]$_ })
$ruleStringCount = [int]$fixture.affectedSourceSet.ruleStringCount

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed') 'failure, post-fix and current-head evidence are incomplete.'
Assert-Gate (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'evidence is not static-only.'
Assert-Gate ($sourceOrdinals.Count -eq 1 -and $sourceOrdinals[0] -eq 21 -and $ruleStringCount -eq 2) 'fixture is not bound to ordinal 21 and its two real rules.'
Assert-Gate ($backup.Contains('var targetFound = null;') -and $backup.Contains('predicateNode = targetFound;') -and -not $backup.Contains('targetOccurrenceFromRight')) 'backup does not capture the nearest-ancestor pre-fix implementation.'
Assert-Gate ($runtime.Contains('var legadoSelectorCompoundParts = function (selector)') -and $runtime.Contains('targetCompoundIndex: legadoSelectorCompoundIndexAt(text, cursor)') -and $runtime.Contains('pseudo.targetOccurrenceFromRight = occurrenceFromRight;') -and $runtime.Contains('predicateNode = matchingAncestors[targetOccurrence];')) 'current ArkWeb runtime does not retain occurrence-aware owning-compound projection.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer is missing.'

$hashes = [ordered]@{}
foreach ($path in @($runtimePath, $legadoPath)) {
  $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant()
}
$closeCondition = 'R4 must execute all three repeated-ancestor occurrence cases, both ordinal-21 BookInfo rules, the existing 243 pseudo fixtures, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-arkweb-jsoup-index-middle-compound-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($runtimePath)
  backupPath = $backupPath
  backupSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $backupPath)).Hash.ToUpperInvariant()
  currentHeadHashes = $hashes
  affectedSourceOrdinals = $sourceOrdinals
  affectedRuleStringCount = $ruleStringCount
  fixturePath = $FixturePath
  affectedRuleStrings = @($fixture.affectedSourceSet.ruleStrings)
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Pinned Legado delegates the complete selector to Jsoup Element.select, preserving each pseudo evaluator with the element identity of its own compound.'
    v2BeforeFix = 'ArkWeb stored only targetSelector and projected every repeated compound pseudo onto the nearest matching ancestor, so an outer tr:nth-of-type(3) could be evaluated on an inner tr.'
    v2AfterFix = 'The runtime records the pseudo owning compound and its occurrence from the right, collects matching ancestors, and evaluates the predicate on the occurrence-specific ancestor before terminal projection.'
    evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath)
  }
  consumerMatrix = [pscustomobject][ordered]@{
    arkWeb = $runtimePath
    stringFallback = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
    dom = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
    legado = $legadoPath
  }
  currentPackageImpact = 'Frozen ordinal 21 contributes two real BookInfo rules with repeated tr compounds; the source package remains externally blocked for interactive login, while this static fix closes the general occurrence-binding gap without claiming a runtime pass.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_repeated_ancestor_compound_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = $closeCondition
}
Write-AtomicJson $SourceFixPath $sourceFix

$existingOrdinals = @($issue.affectedSourceOrdinals | ForEach-Object { [int]$_ })
$mergedOrdinals = @($existingOrdinals + $sourceOrdinals | Sort-Object -Unique)
Set-PropertyValue $issue 'affectedSourceOrdinals' $mergedOrdinals
Set-PropertyValue $issue 'latestAffectedSourceOrdinals' $sourceOrdinals
Set-PropertyValue $issue 'latestAffectedRuleStringCount' $ruleStringCount
Set-PropertyValue $issue 'lastSourceFixEvidencePath' $SourceFixPath
Set-PropertyValue $issue 'rootCauseCategory' '规则解析或编译'
Set-PropertyValue $issue 'summary' '243 ArkWeb repeated-ancestor owning-compound closure: manual pseudo predicates now bind to the occurrence of their own repeated compound. Frozen ordinal 21 contributes two real BookInfo rules; runtime, full Harness, Legado differential, build and device validation remain deferred.'
Set-PropertyValue $issue 'closeCondition' $closeCondition
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))

Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-arkweb-jsoup-repeated-ancestor-compound-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_ARKWEB_REPEATED_ANCESTOR_COMPOUND_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. Repeated-ancestor owning-compound repair is statically closed for ordinal 21; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 covers owning compounds and selector-root preservation: every manually evaluated pseudo must retain the element token and occurrence of its own compound before terminal projection, including repeated ancestor compounds.'
Set-PropertyValue $objective 'nextAction' '243 repeated-ancestor owning-compound source closure is registered; continue the single-root-cause static audit while R4 remains deferred.'
if ($null -ne $objective.PSObject.Properties['continuationTarget']) {
  Set-PropertyValue $objective.continuationTarget 'activeBoundary' '243 remains verifying; repeated-ancestor context for ordinal 21 is statically closed with two real rules and three synthetic cases; R4 remains deferred.'
  Set-PropertyValue $objective.continuationTarget 'nextTransition' 'Continue auditing selector-root preservation for remaining standard pseudos; keep runtime and differential gates deferred.'
}
$plan = @($objective.continuationPlan)
$completedStep = $plan | Where-Object { [string]$_.id -eq '243-SP-63' } | Select-Object -First 1
if ($null -eq $completedStep) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-63'; status = 'completed'; action = '修复 ArkWeb 重复祖先 compound 的手工伪类总是投影到最近匹配祖先的问题；记录 owning compound index 与从右侧的重复 occurrence，绑定第 21 条书源的两条真实 BookInfo 规则。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
} else {
  Set-PropertyValue $completedStep 'status' 'completed'
  Set-PropertyValue $completedStep 'action' '修复 ArkWeb 重复祖先 compound 的手工伪类总是投影到最近匹配祖先的问题；记录 owning compound index 与从右侧的重复 occurrence，绑定第 21 条书源的两条真实 BookInfo 规则。'
  Set-PropertyValue $completedStep 'evidence' @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath)
}
$deferredStep = $plan | Where-Object { [string]$_.id -eq '243-SP-64' } | Select-Object -First 1
if ($null -eq $deferredStep) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-64'; status = 'deferred'; action = 'R4 执行三个重复祖先 occurrence 案例、第 21 条书源两条规则、现有 243 伪类 fixture、458 条 Harness、Legado 差分、构建和真机验证。' }
} else {
  Set-PropertyValue $deferredStep 'status' 'deferred'
}
Set-PropertyValue $objective 'continuationPlan' $plan
Write-AtomicJson $statePath $state
Write-AtomicJson $objectivePath $objective

$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $runtimePath, $backupPath, 'tools/legado-compat/Test-LegadoArkWebJsoupRepeatedAncestorCompoundFailureWitness.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupRepeatedAncestorCompoundPostFixContract.ps1', 'tools/legado-compat/Test-LegadoArkWebJsoupRepeatedAncestorCompoundCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoArkWebJsoupRepeatedAncestorCompoundSourceFix.ps1', $legadoPath)
$summary = '243 ArkWeb repeated-ancestor owning-compound closure: manual pseudo predicates now bind to the occurrence of their own repeated compound. Frozen ordinal 21 contributes two real BookInfo rules; runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw "Update-LegadoGovernanceState failed:`n$updateOutput"
}
[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  latestAffectedSourceOrdinals = $sourceOrdinals
  latestAffectedRuleStringCount = $ruleStringCount
  sourceFixEvidencePath = $SourceFixPath
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  governanceUpdate = $updateOutput.Trim()
} | ConvertTo-Json -Depth 100
