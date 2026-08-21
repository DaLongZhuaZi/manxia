[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-of-type-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-of-type-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-of-type-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-of-type-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-of-type-source-fix-20260810.json'
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
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 of-type source-fix gate failed: $Message" } }
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
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying; source closure cannot claim runtime completion.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 5 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 228) 'of-type fixture binding drifted.'
Assert-Gate ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 12 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract must remain static-only.'
Assert-Gate ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 8 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$audit.semanticMatchAllowed) 'current-head audit must remain static-only.'
Assert-Gate ($analyzer.Contains("pseudo.name === 'first-of-type'") -and $analyzer.Contains("pseudo.name === 'nth-last-of-type'") -and $analyzer.Contains('typeCount: number')) 'string fallback of-type implementation is absent.'
Assert-Gate ($element.Contains("pseudo.name === 'only-of-type'") -and $element.Contains('private getElementTypeCount(elem: HTMLElement, parent: HTMLElement): number')) 'DOM of-type implementation is absent.'
Assert-Gate ($runtime.Contains('querySelectorAll') -and $legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'native ArkWeb or pinned Legado consumer is missing.'

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-sibling-combinator-source-fix-20260810.json'
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    originalSemantics = 'Legado Jsoup counts element siblings with the same tag for first-of-type, last-of-type, only-of-type and nth-last-of-type; other tag names do not affect type position.'
    v2BeforeFix = 'The large-document string fallback only handled nth-of-type, eq and lt, and HTMLElement.matchesPseudoClass had no of-type branches beyond nth-of-type. Unknown names therefore failed closed for a selector used by frozen source ordinal 228.'
    v2AfterFix = 'The string fallback carries a typed same-tag count in the occurrence context and handles first/last/only-of-type plus nth-last-of-type from the end. The DOM Matcher uses the same typed counter, while ArkWeb keeps native CSS evaluation.'
    evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $FixturePath)
  }
  changedPaths = @($analyzerPath, $elementPath)
  consumerMatrix = [pscustomobject][ordered]@{ stringFallback = $analyzerPath; dom = $elementPath; arkWeb = $runtimePath; legado = $legadoPath }
  fixturePath = $FixturePath
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element; $runtimePath = Get-TextHash $runtime; $legadoPath = Get-TextHash $legado }
  affectedSourceOrdinals = @(228)
  ruleStringCount = 1
  assertions = [int]$contract.assertions + [int]$audit.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_of_type_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute the five of-type cases, existing 243 standard-pseudo/sibling equivalence classes, affected source ordinal 228, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-of-type-pseudo-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. The of-type pseudo repair extends the existing static closure; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'currentWorkstream' 'R3-ISSUE-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility now includes first/last/only-of-type and nth-last-of-type same-tag sibling semantics in the large-document fallback and DOM Matcher; R4 remains deferred.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators and of-type position semantics are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 of-type source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-16' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-16'; status = 'completed'; action = '固定 first/last/only-of-type 与 nth-last-of-type 的同标签兄弟语义，登记第 228 条书源失败见证并补齐 DOM/字符串回退消费者。'; evidence = @($FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-17'; status = 'deferred'; action = 'R4 执行 of-type 等价类、全部 243 规则集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorOfTypeFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorOfTypePostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupStandardPseudoSelectorOfTypeCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorOfTypeSourceFix.ps1', $analyzerPath, $elementPath, $runtimePath, $legadoPath)
$summary = '243 of-type semantics are statically closed: the large-document fallback and DOM Matcher now implement first-of-type, last-of-type, only-of-type and nth-last-of-type with same-tag occurrence counts; ArkWeb retains native CSS. Frozen ordinal 228 impact, failure witness, post-fix/current-head evidence and source-fix are registered. R4 deferred.'
$evidenceArgument = [string]::Join(',', $evidence)
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath $evidenceArgument 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }

[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; assertions = $sourceFix.assertions; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
