[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-document-root-child-pseudo.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-document-root-child-pseudo-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-document-root-child-pseudo-post-fix-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-dom-document-root-child-pseudo-source-fix-20260810.json'
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
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$parserPath = 'entry/src/main/ets/libs/htmlparser/Parser.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($resolved)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Assert-Gate { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 DOM document-root pseudo source-fix gate failed: $Message" } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$element = Read-StrictText $elementPath
$parser = Read-StrictText $parserPath
$legado = Read-StrictText $legadoPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'failure witness and post-fix contract must remain static-only.'
Assert-Gate ($parser.Contains("new HTMLElement('root', null, '', null, rootRange)") -and $element.Contains('isSyntheticDocumentParent')) 'synthetic Document source fix is missing.'
Assert-Gate ($legado.Contains('temp.select(ruleStr)')) 'pinned Legado selector consumer is missing.'

$closeCondition = 'R4 must execute top-level and nested DOM child/of-type cases, the affected 243 source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
$hashes = [ordered]@{}
foreach ($path in @($elementPath, $parserPath, $legadoPath)) { $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant() }
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-direct-child-occurrence-marker-guard-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  changedPaths = @($elementPath)
  currentHeadHashes = $hashes
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    before = 'Parser.parse creates a detached HTMLElement(root) wrapper, but HTMLElement.matchesPseudoClass treated that wrapper as a normal element parent. Top-level fragment nodes could satisfy child and of-type pseudos that Jsoup rejects under Document.'
    after = 'The matcher recognizes a detached root wrapper as a synthetic Document and fail-closes all child/of-type pseudos there; eq/lt retain their Jsoup sibling-index semantics.'
    legadoReference = 'Pinned Jsoup 1.16.2 IsFirstChild/IsLastChild/IsOnlyChild/CssNthEvaluator return false when the parent is Document.'
  }
  consumerMatrix = [pscustomobject][ordered]@{ dom = $elementPath; parser = $parserPath; legado = $legadoPath; stringFallback = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; arkWeb = 'entry/src/main/resources/rawfile/legado_runtime.html' }
  assertions = [int]$contract.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_document_root_child_pseudo_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = $closeCondition
}
Write-AtomicJson $SourceFixPath $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-dom-document-root-child-pseudo-static-closure'
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_STANDARD_CSS_PSEUDO_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS pseudo compatibility includes occurrence marker lifetime and Jsoup Document-root semantics: direct-child helpers preserve markers, the outer chain strips them once, and synthetic DOM roots fail-closed for child/of-type pseudos.'
Set-PropertyValue $objective.executionTarget 'statement' '243 direct-child context, top-level split, regex-class pseudo nesting, :has relative-selector context, :not ancestor context, duplicate occurrence identity, bulk offset projection, sibling combinators, of-type position semantics, selector-group occurrence identity, nested marker restoration, direct-child marker lifetime and synthetic Document-root child pseudo semantics are statically closed and registered; runtime, full Harness, Legado differential, build and device gates remain deferred.'
Set-PropertyValue $objective 'nextAction' '243 DOM Document-root pseudo source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-23' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-23'; status = 'completed'; action = '修复 DOM 解析器合成 root 与 Jsoup Document 的 child/of-type 伪类边界；仅在真实元素父节点上执行 child/of-type 语义，保留 eq/lt 兄弟索引。'; evidence = @($FailureWitnessPath, $PostFixContractPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-24'; status = 'deferred'; action = 'R4 执行顶层与嵌套 DOM child/of-type 案例、243 影响集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson $objectivePath $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $SourceFixPath, $elementPath, $parserPath, $legadoPath, 'tools/legado-compat/Test-LegadoJsoupDomDocumentRootChildPseudoFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupDomDocumentRootChildPseudoPostFixContract.ps1', 'tools/legado-compat/Register-LegadoJsoupDomDocumentRootChildPseudoSourceFix.ps1')
$summary = '243 DOM Document-root child/of-type semantics are statically closed: the parser keeps its internal root wrapper, while HTMLElement now treats a detached root as Jsoup Document and fail-closes child/of-type pseudos there; eq/lt sibling indexing remains unchanged. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; assertions = [int]$contract.assertions; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
