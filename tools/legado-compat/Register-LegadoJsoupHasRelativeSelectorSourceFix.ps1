[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-relative-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-post-fix-20260809.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-has-relative-selector-current-head-audit-20260809.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-has-relative-selector-source-fix-20260809.json'
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
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Get-PropertyValue { param([object]$Object, [string]$Name, [object]$Default = $null); if ($null -eq $Object) { return $Default }; $property = $Object.PSObject.Properties[$Name]; if ($null -eq $property -or $null -eq $property.Value) { return $Default }; return $property.Value }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has relative selector source-fix gate failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$audit = Read-StrictJson $CurrentHeadAuditPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying; source closure cannot claim runtime completion.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 4) 'relative selector fixture binding drifted.'
Assert-Gate ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 15 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract must remain static-only.'
Assert-Gate ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 8 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$audit.semanticMatchAllowed) 'current-head audit must remain static-only.'

$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-regex-class-context-source-fix-20260809.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Legado AnalyzeByJSoup delegates the complete CSS rule to Jsoup Element.select; a :has(>relative-selector) predicate is evaluated from the candidate parent, and the relative selector may continue below the direct child.'
    v2BeforeFix = 'DOM Matcher used child.matches(childSelector), which only accepts a single selector chain rooted at the child; the large-document string fallback required every returned element to equal the direct child, rejecting valid matches such as >div span.'
    v2AfterFix = 'DOM Matcher evaluates the relative selector from the candidate parent and accepts only matches whose ancestor chain reaches a direct child; the string fallback accepts non-wrapper matches returned below each direct child.'
    evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $FixturePath)
  }
  changedPaths = @($analyzerPath, $elementPath)
  consumerMatrix = [pscustomobject][ordered]@{ dom = $elementPath; stringFallback = $analyzerPath; arkWeb = $runtimePath; legado = $legadoPath }
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element; $runtimePath = Get-TextHash $runtime; $legadoPath = Get-TextHash $legado }
  assertions = [int]$contract.assertions + [int]$audit.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_relative_selector_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute the four relative-selector cases together with existing 243 child-pseudo, top-level split and regex-class cases, the full affected 52-rule/21-source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-09-actual-docs-source-refactor-jsoup-standard-pseudo-243-has-relative-selector-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. The :has relative-selector context repair extends the existing direct-child/static closure; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility now also covers :has relative selectors that continue below a direct child; DOM and large-document string fallback consumers are statically closed, while R4 remains deferred.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting and :has relative-selector context are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 :has relative-selector context static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-06' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-06'; status = 'completed'; action = '固定 :has(>div span) 相对选择器语义，登记 DOM 与字符串回退失败见证，并修复直接子节点以下的后代匹配边界。'; evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-07'; status = 'deferred'; action = 'R4 执行四项相对选择器、既有 243 等价类、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @(
  $FixturePath,
  $FailureWitnessPath,
  $PostFixContractPath,
  $CurrentHeadAuditPath,
  $SourceFixPath,
  'tools/legado-compat/Apply-LegadoJsoupHasRelativeSelectorFix.ps1',
  'tools/legado-compat/Test-LegadoJsoupHasRelativeSelectorFailureWitness.ps1',
  'tools/legado-compat/Test-LegadoJsoupHasRelativeSelectorPostFixContract.ps1',
  'tools/legado-compat/Test-LegadoJsoupHasRelativeSelectorCurrentHeadAudit.ps1',
  'tools/legado-compat/Register-LegadoJsoupHasRelativeSelectorSourceFix.ps1',
  $analyzerPath,
  $elementPath,
  $runtimePath,
  $legadoPath
)
$summary = '243 :has relative-selector context is statically closed: DOM Matcher now evaluates the complete selector from the candidate parent and verifies direct-child ancestry; the large-document string fallback accepts descendant matches below each direct child. Four cases, failure witness, post-fix/current-head evidence and source-fix are registered. R4 deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  sourceFixEvidencePath = $SourceFixPath
  assertions = $sourceFix.assertions
  governanceUpdate = $updateOutput.Trim()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 100
